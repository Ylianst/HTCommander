import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/mime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/app_settings.dart';
import 'package:htcommander/handlers/mail_server_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/winlink/mail_server.dart';
import 'package:htcommander/winlink/mail_store.dart';
import 'package:htcommander/winlink/pop3_server.dart';
import 'package:htcommander/winlink/smtp_server.dart';
import 'package:htcommander/winlink/winlink_mail.dart';

class _Client {
  _Client(this.socket)
    : lines = StreamIterator(
        socket
            .cast<List<int>>()
            .transform(latin1.decoder)
            .transform(const LineSplitter()),
      );
  final Socket socket;
  final StreamIterator<String> lines;
  Future<String> read() async {
    if (!await lines.moveNext().timeout(const Duration(seconds: 15))) {
      throw StateError('Server disconnected before replying');
    }
    return lines.current;
  }

  Future<String> command(String command) {
    socket.write('$command\r\n');
    return read();
  }

  Future<List<String>> multiline(String command) async {
    expect(await this.command(command), startsWith('+OK'));
    final result = <String>[];
    while (true) {
      final line = await read();
      if (line == '.') return result;
      result.add(line.startsWith('..') ? line.substring(1) : line);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MailStore store;
  late AppDatabase database;
  final servers = <MailServer>[];
  final clients = <_Client>[];

  setUp(() async {
    DataBroker.reset();
    directory = await Directory.systemTemp.createTemp('htc-mail-server-');
    database = await AppDatabase.openInMemory();
    store = MailStore(storagePath: directory.path);
    await store.initialize();
  });
  tearDown(() async {
    for (final client in clients) {
      client.socket.destroy();
      await client.lines.cancel();
    }
    clients.clear();
    for (final server in servers) {
      await server.stop();
      server.dispose();
    }
    servers.clear();
    await store.flush();
    store.dispose();
    await AppDatabase.close();
    await directory.delete(recursive: true);
    DataBroker.reset();
  });

  Future<_Client> connect(MailServer server) async {
    servers.add(server);
    expect(await server.start(), isTrue);
    final socket = await Socket.connect('127.0.0.1', server.boundPort!);
    expect(socket.remoteAddress.isLoopback, isTrue);
    final client = _Client(socket);
    clients.add(client);
    await client.read();
    return client;
  }

  SmtpServer smtp() => SmtpServer(
    0,
    store: store,
    account: 'N0CALL',
    password: 'bridge-password',
  );
  Pop3Server pop3() => Pop3Server(
    0,
    store: store,
    account: 'N0CALL',
    password: 'bridge-password',
  );

  Future<void> smtpLogin(_Client client) async {
    expect(await client.command('EHLO test'), startsWith('250-'));
    while (!(await client.read()).startsWith('250 ')) {}
    expect(
      await client.command(
        'AUTH PLAIN ${base64.encode(utf8.encode('\x00N0CALL@winlink.org\x00bridge-password'))}',
      ),
      startsWith('235'),
    );
  }

  Future<void> envelope(
    _Client client, {
    String to = 'other@example.org',
  }) async {
    expect(
      await client.command(
        'MAIL FROM:<N0CALL@winlink.org> BODY=8BITMIME SIZE=100',
      ),
      startsWith('250'),
    );
    expect(await client.command('RCPT TO:<$to>'), startsWith('250'));
    expect(await client.command('DATA'), startsWith('354'));
  }

  Future<String> submit(_Client client, String message) {
    client.socket.add(utf8.encode('$message\r\n.\r\n'));
    return client.read();
  }

  const headers =
      'From: N0CALL <N0CALL@winlink.org>\r\n'
      'To: other@example.org\r\n'
      'Subject: test\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n\r\n';

  Future<_Client> popLogin(Pop3Server server) async {
    final client = await connect(server);
    expect(await client.command('USER N0CALL'), startsWith('+OK'));
    expect(await client.command('PASS bridge-password'), startsWith('+OK'));
    return client;
  }

  WinLinkMail incoming(String mid) => WinLinkMail()
    ..mid = mid
    ..from = 'SMTP:Sender <sender@example.org>'
    ..to = 'N0CALL; N1TEST'
    ..subject = 'Received café'
    ..body = '.leading dot\r\nsecond line\r\n'
    ..attachments = [
      WinLinkMailAttachement(
        name: 'binary.dat',
        data: Uint8List.fromList([0, 1, 255]),
      ),
    ];

  test(
    'SMTP authenticates, parses fragmented MIME and durably queues Outbox',
    () async {
      final client = await connect(smtp());
      expect(
        await client.command('MAIL FROM:<N0CALL@winlink.org>'),
        startsWith('530'),
      );
      await smtpLogin(client);
      expect(
        await client.command('MAIL FROM:<stranger@example.org>'),
        startsWith('553'),
      );
      await envelope(client);
      final message =
          'From: N0CALL <N0CALL@winlink.org>\r\n'
          'To: other@example.org\r\n'
          'Subject: =?UTF-8?B?Y2Fmw6k=?=\r\n'
          'Date: Tue, 24 Nov 2026 12:00:00 +0000\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: multipart/mixed; boundary="test"\r\n\r\n'
          '--test\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
          '..leading dot\r\ncafé\r\n'
          '--test\r\nContent-Type: application/octet-stream\r\n'
          'Content-Disposition: attachment; filename="binary.dat"\r\n'
          'Content-Transfer-Encoding: base64\r\n\r\nAAH/\r\n--test--\r\n.\r\n';
      final bytes = utf8.encode(message);
      final split = bytes.indexOf(0xc3) + 1;
      client.socket.add(bytes.sublist(0, split));
      await client.socket.flush();
      client.socket.add(bytes.sublist(split));
      expect(await client.read(), startsWith('250'));
      final queued = store.getAllMails().single;
      expect(queued.mailbox, 'Outbox');
      expect(queued.from, 'N0CALL');
      expect(queued.to, 'other@example.org');
      expect(queued.subject, 'café');
      expect(queued.body, contains('.leading dot'));
      expect(queued.body, contains('café'));
      expect(queued.attachments!.single.data, [0, 1, 255]);
      expect(queued.dateTime.toUtc(), DateTime.utc(2026, 11, 24, 12));
      expect((await database.mails.all()).single.mid, queued.mid);
      expect(await client.command('QUIT'), startsWith('221'));
    },
  );

  test(
    'SMTP LOGIN works and rejects persistence failures without queueing',
    () async {
      final client = await connect(smtp());
      expect(await client.command('HELO test'), startsWith('250'));
      expect(await client.command('AUTH LOGIN'), '334 VXNlcm5hbWU6');
      expect(
        await client.command(base64.encode(utf8.encode('N0CALL'))),
        '334 UGFzc3dvcmQ6',
      );
      expect(
        await client.command(base64.encode(utf8.encode('wrong'))),
        startsWith('535'),
      );
      await smtpLogin(client);
      await database.db.execute(
        "CREATE TRIGGER reject_mail BEFORE INSERT ON mail_messages "
        "BEGIN SELECT RAISE(ABORT, 'test persistence failure'); END",
      );
      await envelope(client);
      expect(await submit(client, '${headers}hello'), startsWith('451'));
      expect(store.getAllMails(), isEmpty);
      expect(await database.mails.all(), isEmpty);
      await database.db.execute('DROP TRIGGER reject_mail');
      await envelope(client);
      expect(await submit(client, '${headers}retry'), startsWith('250'));
      expect((await database.mails.all()).single.body, contains('retry'));
    },
  );

  test('SMTP rejects HTML-only, hidden recipients and oversize mail', () async {
    final client = await connect(smtp());
    await smtpLogin(client);
    expect(
      await client.command(
        'MAIL FROM:<N0CALL@winlink.org> SIZE=${MailServer.maxMessageBytes + 1}',
      ),
      startsWith('552'),
    );
    await envelope(client);
    expect(
      await submit(
        client,
        '${headers.replaceFirst('text/plain', 'text/html')}<p>html only</p>',
      ),
      startsWith('554'),
    );
    await envelope(client, to: 'hidden@example.org');
    expect(
      await submit(client, '${headers}hidden recipient'),
      startsWith('554'),
    );
    expect(store.getAllMails(), isEmpty);
    Future<String> sizedMessage(int size) async {
      await envelope(client);
      client.socket.write(headers);
      var remaining = size - utf8.encode(headers).length;
      final fullLine = '${'x' * 16382}\r\n';
      while (remaining > 16384) {
        client.socket.write(fullLine);
        remaining -= 16384;
      }
      client.socket.write('${'x' * (remaining - 2)}\r\n.\r\n');
      return client.read();
    }

    expect(await sizedMessage(MailServer.maxMessageBytes), startsWith('250'));
    expect(
      await sizedMessage(MailServer.maxMessageBytes + 1),
      startsWith('552'),
    );
    expect(store.count, 1);
    await envelope(client);
    expect(
      await submit(client, '${headers}after oversized message'),
      startsWith('250'),
    );
  });

  test('POP3 exposes Inbox MIME, exact octets, TOP and stable UIDL', () async {
    store.addMail(incoming('received-mid'));
    store.addMail(incoming('not-in-inbox')..mailbox = 'Sent');
    await store.flush();
    final server = pop3();
    final client = await popLogin(server);
    final uids = await client.multiline('UIDL');
    expect(uids, hasLength(1));
    final size = int.parse((await client.command('LIST 1')).split(' ').last);
    expect(await client.command('STAT'), '+OK 1 $size');
    final lines = await client.multiline('RETR 1');
    final bytes = latin1.encode('${lines.join('\r\n')}\r\n');
    expect(bytes.length, size);
    final mime = MimeMessage.parseFromData(Uint8List.fromList(bytes));
    expect(mime.decodeSubject(), 'Received café');
    expect(mime.fromEmail, 'sender@example.org');
    expect(mime.to!.map((a) => a.email), [
      'N0CALL@winlink.org',
      'N1TEST@winlink.org',
    ]);
    expect(mime.decodeTextPlainPart(), contains('.leading dot'));
    final attachment = mime.findContentInfo().single;
    expect(mime.getPart(attachment.fetchId)!.decodeContentBinary(), [
      0,
      1,
      255,
    ]);
    final top = await client.multiline('TOP 1 0');
    expect(top.last, isEmpty);
    expect(await client.command('QUIT'), startsWith('+OK'));
    final next = await Socket.connect('127.0.0.1', server.boundPort!);
    final nextClient = _Client(next);
    clients.add(nextClient);
    await nextClient.read();
    await nextClient.command('USER N0CALL@winlink.org');
    await nextClient.command('PASS bridge-password');
    expect(await nextClient.multiline('UIDL'), uids);
  });

  test(
    'POP3 auth, maildrop locking, RSET and QUIT deletion semantics',
    () async {
      store.addMail(incoming('one'));
      await store.flush();
      final server = pop3();
      final first = await connect(server);
      expect(await first.command('STAT'), startsWith('-ERR'));
      await first.command('USER N0CALL');
      expect(await first.command('PASS wrong'), startsWith('-ERR'));
      expect(await first.command('PASS bridge-password'), startsWith('+OK'));
      final secondSocket = await Socket.connect('127.0.0.1', server.boundPort!);
      final second = _Client(secondSocket);
      clients.add(second);
      await second.read();
      await second.command('USER N0CALL');
      expect(
        await second.command('PASS bridge-password'),
        contains('[IN-USE]'),
      );
      expect(await first.command('DELE 1'), startsWith('+OK'));
      expect(await first.command('LIST 1'), startsWith('-ERR'));
      expect(await first.command('RSET'), startsWith('+OK'));
      expect(await first.command('DELE 1'), startsWith('+OK'));
      first.socket.destroy();
      await first.lines.cancel();
      // Server observes EOF before the next client's retry.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await second.command('PASS bridge-password'), startsWith('+OK'));
      expect(store.getMail('one')!.mailbox, 'Inbox');
      expect(await second.command('DELE 1'), startsWith('+OK'));
      expect(await second.command('QUIT'), startsWith('+OK'));
      expect(store.getMail('one')!.mailbox, 'Trash');
      expect((await database.mails.all()).single.mailbox, 'Trash');
    },
  );

  test(
    'settings disable servers by default and persist independent ports',
    () async {
      final handler = MailServerHandler(store)..init();
      addTearDown(() async {
        handler.dispose();
        await handler.settled;
      });
      await handler.settled;
      expect(handler.smtpRunning, isFalse);
      expect(handler.pop3Running, isFalse);
      final smtpReservation = await ServerSocket.bind('127.0.0.1', 0);
      final popReservation = await ServerSocket.bind('127.0.0.1', 0);
      final settings = AppSettings.loadFromDataBroker().copyWith(
        callSign: 'N0CALL',
        smtpServerEnabled: true,
        smtpServerPort: smtpReservation.port,
        pop3ServerEnabled: true,
        pop3ServerPort: popReservation.port,
        mailServerPassword: 'bridge-password',
      );
      await smtpReservation.close();
      await popReservation.close();
      settings.saveToDataBroker();
      await handler.settled;
      expect(handler.smtpRunning, isTrue);
      expect(handler.pop3Running, isTrue);
      final restored = AppSettings.loadFromDataBroker();
      expect(restored.smtpServerPort, settings.smtpServerPort);
      expect(restored.pop3ServerPort, settings.pop3ServerPort);
      final oldClient = _Client(
        await Socket.connect('127.0.0.1', settings.smtpServerPort),
      );
      clients.add(oldClient);
      expect(await oldClient.read(), startsWith('220'));
      final replacement = await ServerSocket.bind('127.0.0.1', 0);
      final replacementPort = replacement.port;
      await replacement.close();
      DataBroker.dispatch(
        deviceId: 0,
        name: 'smtpServerPort',
        data: replacementPort,
      );
      DataBroker.dispatch(
        deviceId: 0,
        name: 'MailServerPassword',
        data: 'replacement-password',
      );
      await handler.settled;
      expect(await oldClient.lines.moveNext(), isFalse);
      final newClient = _Client(
        await Socket.connect('127.0.0.1', replacementPort),
      );
      clients.add(newClient);
      expect(await newClient.read(), startsWith('220'));
      expect(await newClient.command('HELO test'), startsWith('250'));
      expect(
        await newClient.command(
          'AUTH PLAIN ${base64.encode(utf8.encode('\x00N0CALL\x00bridge-password'))}',
        ),
        startsWith('535'),
      );
      expect(
        await newClient.command(
          'AUTH PLAIN ${base64.encode(utf8.encode('\x00N0CALL\x00replacement-password'))}',
        ),
        startsWith('235'),
      );
      DataBroker.dispatch(deviceId: 0, name: 'smtpServerEnabled', data: 0);
      await handler.settled;
      expect(handler.smtpRunning, isFalse);
      expect(handler.pop3Running, isTrue);
      handler.dispose();
      await handler.settled;
      expect(handler.pop3Running, isFalse);
    },
  );
}
