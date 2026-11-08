/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The BBS file area: the folder-backed store, the F / DL / UL / FK menu
// commands, YAPP transfers with a real AX.25 + YAPP client over a simulated
// radio link, and HTTP downloads / uploads from the web BBS. The BBS tab's
// Files dialog is tested in bbs_files_dialog_test.dart.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_files.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_store.dart';
import 'package:htcommander/handlers/web_bbs_handler.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/ax25_session.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/yapp_transfer.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

class _NoRelay extends WinlinkGatewayRelay {
  _NoRelay(super.deviceId, super.broker);

  @override
  Future<bool> connectAsync(String stationCallsign, {int timeoutMs = 15000}) =>
      Future.value(false);
}

Uint8List _bytes(int n, [int seed = 0]) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + seed) & 0xFF]);

Future<bool> _waitFor(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return true;
}

void main() {
  late Directory dir;
  late BbsFileStore files;

  setUp(() async {
    DataBroker.reset();
    dir = await Directory.systemTemp.createTemp('bbs_files_test');
    files = BbsFileStore(directory: dir.path);
    await files.init();
  });

  tearDown(() async {
    files.dispose();
    DataBroker.reset();
    await dir.delete(recursive: true);
  });

  group('BbsFileStore', () {
    test('adds, lists, numbers and deletes files', () {
      expect(files.list(), isEmpty);
      final a = files.add('../evil/My Report.txt', _bytes(10));
      expect(a!.name, 'My_Report.txt');
      expect(a.id, 1);
      final b = files.add('My_Report.txt', _bytes(3), uploader: 'K7ABC');
      expect(b!.name, 'My_Report-2.txt');
      expect(b.uploader, 'K7ABC');

      // Files the sysop copies into the folder are picked up and numbered.
      File('${dir.path}/zz.bin').writeAsBytesSync(_bytes(5));
      File('${dir.path}/.hidden').writeAsStringSync('x');
      final list = files.list();
      expect(list.map((f) => f.id), [1, 2, 3]);
      expect(list.map((f) => f.name), [
        'My_Report.txt',
        'My_Report-2.txt',
        'zz.bin',
      ]);
      expect(list.last.size, 5);
      expect(list.last.uploader, '');

      expect(files.find('2')!.name, 'My_Report-2.txt');
      expect(files.find('#3')!.name, 'zz.bin');
      expect(files.find('ZZ.BIN')!.id, 3);
      expect(files.read(list.first), _bytes(10));

      expect(files.delete(1), isTrue);
      expect(files.delete(1), isFalse);
      File('${dir.path}/zz.bin').deleteSync();
      expect(files.list().map((f) => f.id), [2]);

      // Numbers are never reused, even after a reload.
      final reloaded = BbsFileStore(directory: dir.path);
      expect(reloaded.list().single.id, 2);
      expect(reloaded.list().single.uploader, 'K7ABC');
      expect(reloaded.add('new.txt', _bytes(1))!.id, 4);
    });

    test('sanitizes names', () {
      expect(BbsFileStore.sanitizeName(r'C:\x\photo 1.JPG'), 'photo_1.JPG');
      expect(BbsFileStore.sanitizeName('...'), 'file');
      expect(BbsFileStore.sanitizeName('.bashrc'), 'bashrc');
      expect(BbsFileStore.sanitizeName('a<b>|c'), 'a_b_c');
      final long = BbsFileStore.sanitizeName('${'x' * 100}.txt');
      expect(long.length, 64);
      expect(long, endsWith('.txt'));
    });

    test('checks uploads', () {
      expect(files.checkUpload(100), isNull);
      expect(files.checkUpload(0), contains('empty'));
      expect(
        files.checkUpload(BbsFileStore.maxUploadBytes + 1),
        contains('too large'),
      );
      DataBroker.dispatch(
        deviceId: 0,
        name: BbsFileStore.uploadsSetting,
        data: 0,
      );
      expect(files.checkUpload(100), contains('disabled'));
      expect(files.upload('K7ABC', 'a.txt', _bytes(5)).error, isNotNull);
      expect(BbsFileStore().checkUpload(100), contains('not available'));
    });

    test('serves the BBS tab over the broker', () async {
      final broker = DataBrokerClient();
      broker.dispatch(
        deviceId: 1,
        name: 'BbsFileAdd',
        data: <String, Object?>{'Name': 'tab.txt', 'Data': _bytes(4)},
        store: false,
      );
      final listed = DataBroker.getValueDynamic(1, 'BbsFiles') as List;
      expect(BbsFile.fromJson(listed.single)!.name, 'tab.txt');
      broker.dispatch(
        deviceId: 1,
        name: 'BbsFileDelete',
        data: 1,
        store: false,
      );
      expect(DataBroker.getValueDynamic(1, 'BbsFiles'), isEmpty);
      broker.dispose();
    });
  });

  group('menu', () {
    late BbsMenu menu;

    String run(
      String caller,
      String line, [
      BbsFileTransfer transfer = BbsFileTransfer.yapp,
    ]) => (menu.handleLine(caller, line, transfer: transfer) as BbsMenuReply)
        .text;

    setUp(() {
      DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
      menu = BbsMenu(store: BbsStore(), files: files);
    });

    test('lists files and offers transfers by transport', () {
      expect(run('W1AW', 'M'), contains('[F]iles'));
      expect(run('W1AW', 'M'), contains('[DL] <#>'));
      expect(run('W1AW', 'M'), contains('[UL]'));
      expect(run('W1AW', 'M', BbsFileTransfer.none), isNot(contains('[DL]')));
      expect(run('W1AW', 'F'), contains('UL to upload the first one'));

      files.add('readme.txt', _bytes(1500));
      files.add('log.txt', _bytes(20), uploader: 'K7ABC');
      final list = run('W1AW', 'F');
      expect(list, startsWith('Files, 2:\r'));
      expect(list, contains('#1 readme.txt'));
      expect(list, contains('1.5 KB'));
      expect(list, contains('20 bytes'));
      expect(list, contains(' K7ABC\r'));
      expect(list, contains('DL <#> to download, UL to upload.'));
      expect(run('W1AW', 'F 1'), contains('last 1 of 2'));
      expect(run('W1AW', 'F', BbsFileTransfer.none), contains('need an AX.25'));
    });

    test('download replies carry the file', () {
      files.add('readme.txt', _bytes(1500));
      final yapp =
          menu.handleLine('W1AW', 'DL 1', transfer: BbsFileTransfer.yapp)
              as BbsMenuReply;
      expect(yapp.download!.name, 'readme.txt');
      expect(yapp.text, 'Sending readme.txt (1.5 KB) with YAPP...\r');

      final web =
          menu.handleLine(
                'W1AW',
                'get readme.txt',
                transfer: BbsFileTransfer.web,
              )
              as BbsMenuReply;
      expect(web.download!.id, 1);
      expect(web.text, endsWith(BbsMenu.prompt));

      final none =
          menu.handleLine('W1AW', 'DL 1', transfer: BbsFileTransfer.none)
              as BbsMenuReply;
      expect(none.download, isNull);
      expect(run('W1AW', 'DL 9'), contains('not found'));
      expect(run('W1AW', 'DL'), startsWith('Usage'));
    });

    test('upload instructions and the uploads setting', () {
      expect(run('W1AW', 'UL'), contains('Send your file with YAPP now'));
      expect(run('W1AW', 'UL', BbsFileTransfer.web), contains('Upload button'));
      DataBroker.dispatch(
        deviceId: 0,
        name: BbsFileStore.uploadsSetting,
        data: 0,
      );
      expect(run('W1AW', 'UL'), contains('Uploads are disabled'));
      expect(run('W1AW', 'M'), isNot(contains('[UL]')));
    });

    test('only the uploader or the sysop may delete a file', () {
      files.add('sysop.txt', _bytes(1));
      files.add('mine.txt', _bytes(1), uploader: 'K7ABC');
      expect(run('K7ABC-5', 'FK 1'), contains('added by the sysop'));
      expect(run('W1AW', 'FK 2'), contains('uploaded by K7ABC'));
      expect(run('K7ABC-5', 'FK 2'), contains('#2 mine.txt deleted'));
      expect(run('N0CALL-1', 'FK sysop.txt'), contains('#1 sysop.txt deleted'));
      expect(files.list(), isEmpty);
    });
  });

  group('YAPP over AX.25', () {
    const bbsId = 440;
    const clientId = 441;
    late DataBrokerClient broker;
    late Bbs bbs;
    late AX25Session client;
    YappTransfer? clientYapp;
    late StringBuffer clientText;
    final received = <String, Uint8List>{};
    final clientErrors = <String>[];
    final sent = <String>[];
    final originalFactory = Bbs.relayFactory;

    Uint8List onAir(AX25Packet packet) => packet.toByteArray();

    void sendLine(String line) =>
        client.send(Uint8List.fromList(utf8.encode('$line\r')));

    setUp(() async {
      broker = DataBrokerClient();
      broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
      broker.dispatch(deviceId: 0, name: 'StationId', data: 0);
      Bbs.relayFactory = _NoRelay.new;
      clientText = StringBuffer();
      received.clear();
      clientErrors.clear();
      sent.clear();

      // Simulated radio link between the BBS radio and the client radio.
      broker.subscribe(
        deviceId: bbsId,
        name: 'TransmitDataFrame',
        callback: (_, _, data) {
          final bytes = onAir((data! as TransmitDataFrameData).packet!);
          scheduleMicrotask(() {
            final packet = AX25Packet.decode(
              TncDataFragment(
                finalFragment: true,
                fragmentId: 0,
                data: bytes,
                channelId: 1,
                regionId: 0,
                incoming: true,
                radioDeviceId: clientId,
              ),
            );
            if (packet != null) client.receive(packet);
          });
        },
      );
      broker.subscribe(
        deviceId: clientId,
        name: 'TransmitDataFrame',
        callback: (_, _, data) {
          final bytes = onAir((data! as TransmitDataFrameData).packet!);
          scheduleMicrotask(
            () => broker.dispatch(
              deviceId: bbsId,
              name: 'UniqueDataFrame',
              data: TncDataFragment(
                finalFragment: true,
                fragmentId: 0,
                data: bytes,
                channelId: 1,
                regionId: 0,
                incoming: true,
                radioDeviceId: bbsId,
                encoding: FragmentEncodingType.hardwareAfsk1200,
              ),
              store: false,
            ),
          );
        },
      );

      bbs = Bbs(bbsId)..enabled = true;
      bbs.menu = BbsMenu(store: BbsStore(), files: files);

      client = AX25Session(clientId, listen: false)..callSignOverride = 'N1ABC';
      client.onDataReceived = (_, data) {
        if (clientYapp?.processIncomingData(data) == true) return;
        clientText.write(utf8.decode(data, allowMalformed: true));
      };
    });

    tearDown(() {
      clientYapp?.dispose();
      clientYapp = null;
      client.dispose();
      bbs.dispose();
      Bbs.relayFactory = originalFactory;
      broker.dispose();
    });

    /// Connects the client, like the terminal does, with or without YAPP.
    Future<void> connect({bool yapp = true}) async {
      if (yapp) {
        clientYapp = YappTransfer(client)
          ..onReceiveComplete = (name, data) {
            received[name] = data;
          }
          ..onSendComplete = sent.add
          ..onError = clientErrors.add
          ..enableAutoReceive();
      }
      client.connect([
        AX25Address.parse('N0CALL')!,
        AX25Address.parse('N1ABC')!,
      ]);
      expect(
        await _waitFor(() => clientText.toString().contains('[M] for menu')),
        isTrue,
      );
    }

    test('uploads and downloads a file', () async {
      await connect();
      final data = _bytes(1000, 3);
      clientYapp!.sendFile('notes.txt', data);
      expect(
        await _waitFor(() => clientText.toString().contains('saved as file')),
        isTrue,
        reason: clientText.toString(),
      );
      expect(sent, ['notes.txt']);
      expect(
        clientText.toString(),
        contains('Received notes.txt (1000 bytes)'),
      );
      final file = files.list().single;
      expect(file.uploader, 'N1ABC');
      expect(File('${dir.path}/notes.txt').readAsBytesSync(), data);

      sendLine('DL 1');
      expect(
        await _waitFor(
          () => clientText.toString().contains('Transfer complete.'),
        ),
        isTrue,
        reason: clientText.toString(),
      );
      expect(received['notes.txt'], data);
      expect(clientText.toString(), contains('Sending notes.txt (1000 bytes)'));

      // Commands keep working after the transfers.
      sendLine('F');
      expect(
        await _waitFor(() => clientText.toString().contains('Files, 1:')),
        isTrue,
      );
      expect(clientErrors, isEmpty);
    });

    test('refuses oversized uploads and uploads when disabled', () async {
      await connect();
      clientYapp!.sendFile('big.bin', _bytes(BbsFileStore.maxUploadBytes + 1));
      expect(await _waitFor(() => clientErrors.isNotEmpty), isTrue);
      expect(clientErrors.single, contains('File too large'));
      expect(
        await _waitFor(
          () => clientText.toString().contains('File transfer failed'),
        ),
        isTrue,
      );

      DataBroker.dispatch(
        deviceId: 0,
        name: BbsFileStore.uploadsSetting,
        data: 0,
      );
      clientYapp!.sendFile('small.txt', _bytes(10));
      expect(await _waitFor(() => clientErrors.length == 2), isTrue);
      expect(clientErrors.last, contains('Uploads are disabled'));
      expect(files.list(), isEmpty);
    });

    test('a client without YAPP can type past a download offer', () async {
      files.add('readme.txt', _bytes(50));
      await connect(yapp: false);
      sendLine('DL 1');
      expect(
        await _waitFor(() => clientText.toString().contains('with YAPP...')),
        isTrue,
      );
      sendLine('B');
      expect(
        await _waitFor(() => clientText.toString().contains('board is empty')),
        isTrue,
        reason: clientText.toString(),
      );
      expect(clientText.toString(), contains('Download cancelled.'));
    });
  });

  group('web BBS', () {
    late WebBbsHandler handler;
    late int port;

    setUp(() async {
      BbsFileStore.instance = files;
      DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerPort', data: 0);
      DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerEnabled', data: 1);
      handler = WebBbsHandler()..init();
      handler.menu = BbsMenu(store: BbsStore(), files: files);
      for (var i = 0; i < 100 && handler.server?.boundPort == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      port = handler.server!.boundPort!;
    });

    tearDown(() {
      handler.dispose();
      BbsFileStore.instance = BbsFileStore();
    });

    test('downloads and uploads over HTTP with the session token', () async {
      files.add('readme.txt', _bytes(300));
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/bbs?callsign=W1AW',
      );
      final messages = StreamIterator<String>(ws.cast<String>());
      expect(await messages.moveNext(), isTrue);
      final session =
          jsonDecode(
                messages.current.substring(WebBbsHandler.controlPrefix.length),
              )
              as Map;
      expect(session['t'], 'session');
      expect(session['upload'], isTrue);
      final token = session['token'] as String;
      expect(token.length, 32);
      expect(await messages.moveNext(), isTrue); // Banner.

      ws.add('DL 1\r');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, contains('Downloading readme.txt'));
      expect(await messages.moveNext(), isTrue);
      final download =
          jsonDecode(
                messages.current.substring(WebBbsHandler.controlPrefix.length),
              )
              as Map;
      expect(download['url'], '/files/1?token=$token');

      final http = HttpClient();
      Future<HttpClientResponse> get(String path) async =>
          (await http.get('127.0.0.1', port, path)).close();
      final res = await get('/files/1?token=$token');
      expect(res.statusCode, 200);
      expect(
        res.headers.value('content-disposition'),
        contains('filename="readme.txt"'),
      );
      expect(
        await res.fold<List<int>>([], (a, b) => a..addAll(b)),
        _bytes(300),
      );
      final bad = await get('/files/1?token=${'0' * 32}');
      expect(bad.statusCode, 403);
      await bad.drain<void>();

      Future<(int, Map)> post(String name, List<int> body) async {
        final req = await http.post(
          '127.0.0.1',
          port,
          '/upload?token=$token&name=${Uri.encodeQueryComponent(name)}',
        );
        req.contentLength = body.length;
        req.add(body);
        final r = await req.close();
        return (
          r.statusCode,
          jsonDecode(await r.transform(utf8.decoder).join()) as Map,
        );
      }

      final (okStatus, ok) = await post('my log.txt', _bytes(100));
      expect(okStatus, 200);
      expect(ok['notified'], isTrue);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, contains('saved as file #2'));
      expect(files.find('2')!.name, 'my_log.txt');
      expect(files.find('2')!.uploader, 'W1AW');

      final (bigStatus, big) = await post(
        'big.bin',
        _bytes(BbsFileStore.maxUploadBytes + 1),
      );
      expect(bigStatus, 413);
      expect(big['message'], contains('too large'));

      http.close();
      await ws.close();
    });
  });
}
