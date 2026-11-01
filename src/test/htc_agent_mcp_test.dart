/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// End to end: the Node MCP server in tools/htc_agent drives a real
// WebServerHandler + AgentApi over the WebSocket, as an AI agent would. Two
// station names point at this host to exercise multi-station tools and the
// merged timeline. Skipped when Node is not installed.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/agent_api.dart';
import 'package:htcommander/handlers/packet_store.dart';
import 'package:htcommander/handlers/web_server_handler.dart';
import 'package:htcommander/radio/radio.dart' show SetLockData, SetUnlockData;
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/xara_capture.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

const String token = 'mcp-test-token-0123456789';
const int radio = 601;

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

bool _hasNode() {
  try {
    final r = Process.runSync('node', ['--version'], runInShell: true);
    final v = RegExp(r'v(\d+)').firstMatch('${r.stdout}');
    return r.exitCode == 0 && v != null && int.parse(v.group(1)!) >= 22;
  } catch (_) {
    return false;
  }
}

/// Talks MCP (newline-delimited JSON-RPC) to the server process.
class Mcp {
  Mcp(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final msg = jsonDecode(line) as Map<String, dynamic>;
          _replies[msg['id']]?.complete(msg);
        });
    process.stderr.transform(utf8.decoder).listen(stderrText.write);
  }

  final Process process;
  final _replies = <Object?, Completer<Map<String, dynamic>>>{};
  final stderrText = StringBuffer();
  int _id = 0;

  Future<Map<String, dynamic>> request(String method, [Object? params]) {
    final id = ++_id;
    final c = _replies[id] = Completer<Map<String, dynamic>>();
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return c.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('$method: $stderrText'),
    );
  }

  void notify(String method) =>
      process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': method}));

  /// Calls a tool; returns (decoded result, isError).
  Future<(Object?, bool)> tool(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await request('tools/call', {'name': name, 'arguments': args});
    final result = r['result'] as Map<String, dynamic>;
    final text = (result['content'] as List).first['text'] as String;
    final isError = result['isError'] == true;
    return (isError ? text : jsonDecode(text), isError);
  }
}

void main() {
  final hasNode = _hasNode();
  late WebServerHandler handler;
  late Mcp mcp;
  final store = PacketStore();
  final radioBus = DataBrokerClient();
  final radioCommands = <String>[];
  final locks = <SetLockData>[];

  setUpAll(() async {
    if (!hasNode) return;
    await store.init();
    DataBroker.addDataHandler('PacketStore', store);

    final port = await _freePort();
    DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    DataBroker.dispatch(deviceId: 0, name: 'StationId', data: 0);
    DataBroker.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
    DataBroker.dispatch(deviceId: 0, name: AgentApi.tokenSetting, data: token);
    DataBroker.dispatch(deviceId: 0, name: AgentApi.enabledSetting, data: 1);
    DataBroker.dispatch(deviceId: 0, name: 'webServerPort', data: port);
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 1);
    DataBroker.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': radio, 'FriendlyName': 'UV-Pro'},
      ],
    );
    DataBroker.dispatch(deviceId: radio, name: 'FriendlyName', data: 'UV-Pro');
    DataBroker.dispatch(deviceId: radio, name: 'State', data: 'Connected');
    DataBroker.dispatch(
      deviceId: radio,
      name: 'LockState',
      data: {'isLocked': false},
    );
    radioBus.subscribe(
      deviceId: radio,
      name: 'SetLock',
      callback: (_, _, d) {
        locks.add(d! as SetLockData);
        DataBroker.dispatch(
          deviceId: radio,
          name: 'LockState',
          data: {'isLocked': true, 'usage': (d as SetLockData).usage},
        );
      },
    );
    radioBus.subscribe(
      deviceId: radio,
      name: 'SetUnlock',
      callback: (_, _, d) {
        radioCommands.add('SetUnlock:${(d! as SetUnlockData).usage}');
        DataBroker.dispatch(
          deviceId: radio,
          name: 'LockState',
          data: {'isLocked': false},
        );
      },
    );
    for (final n in ['XaraConnect', 'XaraSend', 'XaraAbort']) {
      radioBus.subscribe(
        deviceId: radio,
        name: n,
        callback: (_, _, d) => radioCommands.add(n),
      );
    }
    handler = WebServerHandler()..init();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final url = 'ws://127.0.0.1:$port/websocket.aspx';
    final process = await Process.start(
      'node',
      ['tools/htc_agent/htc_agent_mcp.mjs'],
      environment: {
        'HTC_STATIONS': 'bbs=$url,term=$url',
        'HTC_TOKEN_BBS': token,
        'HTC_TOKEN_TERM': token,
      },
      runInShell: true,
    );
    mcp = Mcp(process);
  });

  tearDownAll(() async {
    if (!hasNode) return;
    mcp.process.kill();
    radioBus.dispose();
    handler.dispose();
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 0);
  });

  test(
    'an MCP client observes and drives a station through the agent API',
    () async {
      final init = await mcp.request('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      });
      expect(init['result']['serverInfo']['name'], 'htc-agent');
      expect(init['result']['protocolVersion'], '2025-06-18');
      mcp.notify('notifications/initialized');

      final list = await mcp.request('tools/list');
      final tools = [
        for (final t in list['result']['tools'] as List) t['name'] as String,
      ];
      expect(
        tools,
        containsAll([
          'list_stations',
          'get_timeline',
          'wait_for',
          'radio_lock',
          'xara_connect',
          'terminal_connect',
          'terminal_send',
          'stop_all',
        ]),
      );

      // Terminal tools map their arguments (station_info is the ad-hoc
      // contact; station stays the HTCommander station name).
      final (noLink, noLinkErr) = await mcp.tool('terminal_send', {
        'station': 'term',
        'text': 'x',
      });
      expect(noLinkErr, isTrue);
      expect(noLink, contains('terminal.connect first'));
      final (adHoc, adHocErr) = await mcp.tool('terminal_connect', {
        'station': 'term',
        'radio': radio,
        'station_info': {'Callsign': 'N1ABC', 'TerminalProtocol': 0},
      });
      expect(adHocErr, isTrue);
      expect(adHoc, contains('the terminal did not start'));

      final (stations, _) = await mcp.tool('list_stations');
      final st = (stations! as Map)['stations'] as List;
      expect(st.map((s) => s['connected']), [true, true], reason: '$st');
      expect(st.first['station'], 'N0CALL');
      expect(st.first['allowTransmit'], isTrue);
      expect((st.first['radios'] as List).single['id'], radio);
      // Both stations are authenticated sessions on this host.
      expect(
        (DataBroker.getValueDynamic(1, AgentApi.controlValue)!
            as Map)['clients'],
        2,
      );

      final (lock, lockErr) = await mcp.tool('radio_lock', {
        'station': 'term',
        'radio': radio,
        'modem': 'XARA',
        'xara_wide': false,
      });
      expect(lockErr, isFalse, reason: '$lock');
      expect(locks.single.modem, 'XARA');
      expect(locks.single.xaraWide, isFalse);
      final cursor = (lock! as Map)['cursor'] as int;

      final (_, connErr) = await mcp.tool('xara_connect', {
        'station': 'term',
        'radio': radio,
        'remote': 'N0CALL-1',
      });
      expect(connErr, isFalse);
      expect(radioCommands, contains('XaraConnect'));

      // Wait for a link event the "radio" reports a little later.
      final waiting = mcp.tool('wait_for', {
        'station': 'term',
        'names': ['XaraEvent'],
        'contains': 'connected',
        'after': cursor,
        'timeout_s': 10,
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      DataBroker.dispatch(
        deviceId: radio,
        name: 'XaraEvent',
        data: {'evt': 'connected', 'caller': 'N0CALL', 'answerer': 'N0CALL-1'},
        store: false,
      );
      final (waited, _) = await waiting;
      final event = (waited! as Map)['event'] as Map;
      expect(event['event'], 'XaraEvent');
      expect((event['data'] as Map)['answerer'], 'N0CALL-1');

      // A captured XARA frame shows up in the merged timeline of both stations.
      DataBroker.dispatch(
        deviceId: radio,
        name: 'CaptureFrame',
        data: TncDataFragment(
          finalFragment: true,
          fragmentId: 0,
          data: XaraCapture.encode(
            record: 0,
            code: -1,
            ok: false,
            data: Uint8List(0),
            meta: {'bw': 'narrow'},
          ),
          channelId: 1,
          regionId: 0,
          incoming: true,
          encoding: FragmentEncodingType.softwareXara,
          frameType: FragmentFrameType.xara,
          radioDeviceId: radio,
        ),
        store: false,
      );
      final (tl, _) = await mcp.tool('get_timeline', {'limit': 5});
      final rows = ((tl! as Map)['timeline'] as List).cast<Map>();
      final hits = rows.where(
        (r) => (r['summary'] as String).contains('XARA Connect: CRC failed'),
      );
      expect(hits.map((r) => r['station']).toSet(), {'bbs', 'term'});
      expect(hits.first['dir'], 'RX');

      DataBroker.dispatch(
        deviceId: 1,
        name: 'LogInfo',
        data: 'agent test line',
        store: false,
      );
      final (logged, _) = await mcp.tool('wait_for', {
        'station': 'bbs',
        'names': ['LogInfo'],
        'contains': 'agent test line',
        'after': 0,
        'timeout_s': 10,
      });
      expect(((logged! as Map)['event'] as Map)['data'], 'agent test line');
      final (events, _) = await mcp.tool('get_events', {
        'station': 'bbs',
        'names': ['LogInfo'],
        'contains': 'agent test line',
      });
      expect(((events! as Map)['events'] as List), hasLength(1));

      final (bad, badErr) = await mcp.tool('xara_send', {
        'station': 'nope',
        'radio': radio,
        'text': 'x',
      });
      expect(badErr, isTrue);
      expect(bad, contains('unknown station'));
      final (denied, deniedErr) = await mcp.tool('set_setting', {
        'station': 'bbs',
        'name': 'CallSign',
        'value': 'X',
      });
      expect(deniedErr, isTrue);
      expect(denied, contains('setting must be one of'));

      final (stopped, _) = await mcp.tool('stop_all');
      // Both names share one host here, so the first stop already released the
      // lock taken through "term"; look at what all stations released.
      final released = [
        for (final v in ((stopped! as Map)['released'] as Map).values)
          ...(v as List),
      ];
      expect(released, contains('unlocked radio $radio'));
      expect(radioCommands, contains('SetUnlock:Agent'));

      // Ending the MCP session closes both sockets; the host sees no agents.
      await mcp.process.stdin.close();
      expect(
        await mcp.process.exitCode.timeout(const Duration(seconds: 10)),
        0,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((DataBroker.getValueDynamic(1, AgentApi.controlValue)!
                  as Map)['active'] ==
              true &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        (DataBroker.getValueDynamic(1, AgentApi.controlValue)!
            as Map)['active'],
        isFalse,
      );
    },
    skip: hasNode ? false : 'Node 22+ is not installed',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
