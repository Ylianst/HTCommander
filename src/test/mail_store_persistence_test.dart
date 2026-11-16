import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/winlink/mail_store.dart';
import 'package:htcommander/winlink/winlink_mail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  MailStore? store;

  setUp(() async {
    DataBroker.reset();
    directory = await Directory.systemTemp.createTemp('htc-mail-');
    db = await AppDatabase.openInMemory();
  });

  tearDown(() async {
    await store?.flush();
    store?.dispose();
    store = null;
    await AppDatabase.close();
    await directory.delete(recursive: true);
    DataBroker.reset();
  });

  WinLinkMail mail(String mid) => WinLinkMail()
    ..mid = mid
    ..body = 'body $mid'
    ..attachments = [
      WinLinkMailAttachement(
        name: 'binary.dat',
        data: Uint8List.fromList([0, 1, 255]),
      ),
    ];

  Future<MailStore> open() async {
    final result = MailStore(storagePath: directory.path);
    await result.initialize();
    store = result;
    return result;
  }

  test(
    'imports legacy mail once and does not resurrect deleted mail',
    () async {
      await File(
        '${directory.path}${Platform.pathSeparator}mails.txt',
      ).writeAsString(WinLinkMail.serialize([mail('legacy')]));
      final first = await open();
      expect(first.getMail('legacy')!.attachments!.single.data, [0, 1, 255]);
      first.deleteMail('legacy');
      await first.flush();
      first.dispose();
      final second = await open();
      expect(second.count, 0);
      expect(await db.mails.initialized, isTrue);
    },
  );

  test('coalesces updates and leaves untouched attachments unwritten', () async {
    final current = await open();
    current.addMails([mail('a'), mail('b')]);
    await current.flush();
    await db.db.execute('CREATE TABLE attachment_writes (mid TEXT)');
    await db.db.execute(
      'CREATE TRIGGER count_attachment_update AFTER UPDATE ON mail_attachments '
      'BEGIN INSERT INTO attachment_writes VALUES (NEW.mid); END',
    );
    final changed = current.getMail('a')!;
    for (var i = 0; i < 10; i++) {
      changed.subject = 'subject $i';
      current.updateMail(changed);
    }
    await current.flush();
    expect(
      (await db.mails.all()).firstWhere((m) => m.mid == 'a').subject,
      'subject 9',
    );
    expect(await db.db.query('attachment_writes'), isEmpty);

    changed.attachments!.single.data[0] = 42;
    current.updateMail(changed);
    await current.flush();
    expect(await db.db.query('attachment_writes'), [
      {'mid': 'a'},
    ]);
    expect(
      (await db.mails.all())
          .firstWhere((m) => m.mid == 'a')
          .attachments!
          .single
          .data,
      [42, 1, 255],
    );
  });

  test('freezes in-flight data and drains later mutations in order', () async {
    final current = await open();
    final message = mail('a');
    current.addMail(message);
    final first = current.flush();
    message.body = 'new body';
    message.attachments!.single.data[1] = 55;
    current.updateMail(message);
    await first;
    final saved = (await db.mails.all()).single;
    expect(saved.body, 'new body');
    expect(saved.attachments!.single.data, [0, 55, 255]);
    current.deleteMail('a');
    await current.flush();
    expect(await db.db.query('mail_attachments'), isEmpty);
    expect(await db.mails.all(), isEmpty);
  });

  test('failed saves remain pending and can be retried explicitly', () async {
    final current = await open();
    await db.db.execute(
      "CREATE TRIGGER reject_mail BEFORE INSERT ON mail_messages "
      "BEGIN SELECT RAISE(FAIL, 'test write failure'); END",
    );
    current.addMail(mail('retry'));
    await expectLater(current.flush(), throwsA(isA<Exception>()));
    await db.db.execute('DROP TRIGGER reject_mail');
    await current.flush();
    expect((await db.mails.all()).single.mid, 'retry');
  });

  test(
    'initialized database does not depend on the legacy directory',
    () async {
      await db.mails.save([mail('saved')], <String>{});
      final blocked = File('${directory.path}${Platform.pathSeparator}blocked');
      await blocked.writeAsString('not a directory');
      final current = MailStore(storagePath: blocked.path);
      store = current;
      await current.initialize();
      final saved = current.getMail('saved')!;
      saved.body = 'updated';
      current.updateMail(saved);
      await current.flush();
      expect((await db.mails.all()).single.body, 'updated');
    },
  );

  test('replacement snapshots assign missing message identifiers', () async {
    await open();
    final replacement = mail('placeholder')..mid = null;
    DataBroker.dispatch(
      deviceId: 0,
      name: 'MailReplaceAll',
      data: [replacement],
      store: false,
    );
    await store!.flush();
    expect(replacement.mid, isNotEmpty);
    expect((await db.mails.all()).single.mid, replacement.mid);
  });

  for (final version in [1, 4]) {
    test(
      'upgrades a version $version database without losing stored history',
      () async {
        await db.comms.insert(DecodedTextEntry(text: 'retained'));
        final path = '${directory.path}${Platform.pathSeparator}htcommander.db';
        await db.db.execute('VACUUM INTO ?', [path]);
        await AppDatabase.close();
        final legacy = await databaseFactoryFfi.openDatabase(path);
        for (final table in [
          'mail_messages',
          'mail_attachments',
          'mail_state',
        ]) {
          await legacy.execute('DROP TABLE $table');
        }
        await legacy.setVersion(version);
        await legacy.close();

        const channel = MethodChannel('plugins.flutter.io/path_provider');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return directory.path;
          }
          throw MissingPluginException();
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await AppDatabase.open();
        final upgraded = AppDatabase.instance!;
        expect(await upgraded.db.getVersion(), 5);
        expect((await upgraded.comms.recent(10)).single.text, 'retained');
        await upgraded.mails.save([mail('upgraded')], <String>{});
        expect((await upgraded.mails.all()).single.mid, 'upgraded');
      },
    );
  }

  test(
    'database-unavailable fallback flushes the latest coalesced snapshot',
    () async {
      await AppDatabase.close();
      final current = await open();
      current.addMail(mail('file'));
      final changed = current.getMail('file')!;
      changed.body = 'latest body';
      current.updateMail(changed);
      await current.flush();
      final text = await File(
        '${directory.path}${Platform.pathSeparator}mails.txt',
      ).readAsString();
      expect(WinLinkMail.deserialize(text).single.body, 'latest body');
      changed.body = 'replaced body';
      current.updateMail(changed);
      await current.flush();
      expect(
        WinLinkMail.deserialize(
          await File(
            '${directory.path}${Platform.pathSeparator}mails.txt',
          ).readAsString(),
        ).single.body,
        'replaced body',
      );
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}mails.txt.tmp',
        ).exists(),
        isFalse,
      );
    },
  );
}
