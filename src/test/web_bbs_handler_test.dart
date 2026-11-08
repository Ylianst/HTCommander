import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/web_bbs_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/web/bbs_web_page.dart';
import 'package:htcommander/utils/callsign_format.dart';

void main() {
  group('normalizeAmateurCallsign', () {
    test('accepts valid callsigns, normalized to upper case', () {
      expect(normalizeAmateurCallsign(' w1aw '), 'W1AW');
      expect(normalizeAmateurCallsign('ve2abc-7'), 'VE2ABC-7');
      expect(normalizeAmateurCallsign('2E0ABC'), '2E0ABC');
      expect(normalizeAmateurCallsign('3DA0RU'), '3DA0RU');
      expect(normalizeAmateurCallsign('JA1XYZ-15'), 'JA1XYZ-15');
      expect(normalizeAmateurCallsign('K7A-0'), 'K7A-0');
    });

    test('rejects invalid callsigns', () {
      for (final bad in <String?>[
        null,
        '',
        'ABC',
        'W1',
        '123ABC',
        'W1AW-16',
        'W1AW-',
        'W1AW-01',
        'N0CALLX',
        'VE2ABCD',
        'W1 AW',
        'W1AW<script>',
        'W1\nAW',
        'W1AW1',
      ]) {
        expect(normalizeAmateurCallsign(bad), isNull, reason: '$bad');
      }
    });

    test('page validator mirrors the server pattern', () {
      expect(
        bbsWebPageHtml,
        contains(r'/^([A-Z0-9]{1,3})[0-9][A-Z]{1,4}(?:-(?:[0-9]|1[0-5]))?$/'),
      );
    });
  });

  group('WebBbsHandler', () {
    late WebBbsHandler handler;
    late DataBrokerClient broker;
    late int port;

    setUp(() async {
      DataBroker.reset();
      DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerPort', data: 0);
      DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerEnabled', data: 1);
      broker = DataBrokerClient();
      handler = WebBbsHandler()..init();
      for (var i = 0; i < 100 && handler.server?.boundPort == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      port = handler.server!.boundPort!;
    });

    tearDown(() {
      handler.dispose();
      broker.dispose();
      DataBroker.reset();
    });

    Future<WebSocket> connect(String callsign) => WebSocket.connect(
      'ws://127.0.0.1:$port/bbs?callsign=${Uri.encodeQueryComponent(callsign)}',
    );

    test('serves the terminal page with security headers', () async {
      final client = HttpClient();
      final req = await client.get('127.0.0.1', port, '/');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(body, contains('Handy-Talky Commander BBS'));
      expect(res.headers.value('content-security-policy'), isNotNull);

      final missing = await (await client.get('127.0.0.1', port, '/x')).close();
      await missing.drain<void>();
      expect(missing.statusCode, 404);
      client.close();
    });

    test('rejects an invalid callsign', () async {
      final ws = await connect('NOTACALL');
      await ws.drain<void>();
      expect(ws.closeCode, 4001);
      expect(ws.closeReason, 'Invalid callsign');
    });

    test('runs the BBS menu and disconnects on D', () async {
      final traffic = <BbsTrafficData>[];
      final stats = <BbsStatsUpdatedData>[];
      broker.subscribe(
        deviceId: 0,
        name: 'BbsTraffic',
        callback: (_, _, d) => traffic.add(d as BbsTrafficData),
      );
      broker.subscribe(
        deviceId: 0,
        name: 'BbsStatsUpdated',
        callback: (_, _, d) => stats.add(d as BbsStatsUpdatedData),
      );

      final ws = await connect('w1aw-5');
      final received = StreamController<String>();
      ws.listen((m) => received.add(m as String), onDone: received.close);
      final messages = StreamIterator<String>(received.stream);

      expect(await messages.moveNext(), isTrue);
      expect(messages.current, startsWith('${WebBbsHandler.controlPrefix}{'));
      expect(messages.current, contains('"t":"session"'));
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, startsWith(BbsMenu.banner));

      ws.add('m\r');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, contains('[D]isconnect'));

      ws.add('hello');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, contains('Unknown command'));

      ws.add('D\r');
      expect(await messages.moveNext(), isFalse);
      expect(ws.closeCode, 1000);

      expect(traffic.where((t) => !t.outgoing).map((t) => t.message), <String>[
        'm',
        'hello',
        'D',
      ]);
      expect(traffic.every((t) => t.callsign == 'W1AW-5'), isTrue);
      expect(stats.last.stats.callsign, 'W1AW-5');
      expect(stats.last.stats.protocol, 'Web');
      expect(stats.last.stats.packetsIn, 3);
    });

    test('closes connections that send oversized messages', () async {
      final ws = await connect('K7ABC');
      ws.add('x' * 5000);
      await ws.drain<void>();
      expect(ws.closeCode, 1009);
    });

    test('stops when disabled', () async {
      DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerEnabled', data: 0);
      expect(handler.server, isNull);
      await expectLater(
        WebSocket.connect('ws://127.0.0.1:$port/bbs?callsign=W1AW'),
        throwsA(anything),
      );
    });
  });
}
