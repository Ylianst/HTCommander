/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_auth.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/aprsfi_client.dart';
import 'package:htcommander/aprsis/aprsis_client.dart';
import 'package:htcommander/aprsis/aprsis_manager.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/aprs_handler.dart';
import 'package:htcommander/radio/radio.dart' show TransmitDataFrameData;
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory fake transport so the client's protocol logic can be exercised
/// without a real socket.
class _FakeAprsIsNetwork implements AprsIsNetwork {
  final StreamController<String> _incoming = StreamController<String>();
  final Completer<void> _done = Completer<void>();
  final List<String> sent = [];
  bool connected = false;

  void serverSend(String text) => _incoming.add(text);

  @override
  Future<void> connect(String host, int port) async {
    connected = true;
  }

  @override
  void sendLine(String line) => sent.add(line);

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    connected = false;
    if (!_done.isCompleted) _done.complete();
    await _incoming.close();
  }
}

AprsPacket _parseTnc2(String line) {
  final ax25 = Tnc2Codec.decode(line);
  expect(ax25, isNotNull);
  final aprs = AprsPacket.parse(ax25!);
  expect(aprs, isNotNull);
  return aprs!;
}

void main() {
  group('AprsFiClient', () {
    test('keeps the earliest identical retransmission', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'result': 'ok',
            'entries': [
              {
                'messageid': '3',
                'time': '1788036963',
                'srccall': 'KC1MUR-5',
                'dst': 'KK7VZT-7',
                'message': 'I really like the msg view :)',
              },
              {
                'messageid': '2',
                'time': '1788022543',
                'srccall': 'KC1MUR-5',
                'dst': 'KK7VZT-7',
                'message': 'I really like the msg view :)',
              },
              {
                'messageid': '1',
                'time': '1788021592',
                'srccall': 'KC1MUR-5',
                'dst': 'KK7VZT-7',
                'message': 'I really like the msg view :)',
              },
              {
                'messageid': '4',
                'time': '1788037000',
                'srccall': 'KC1MUR-5',
                'dst': 'KK7VZT-7',
                'message': 'A different message',
              },
            ],
          }),
          200,
        );
      });

      final result = await AprsFiClient.fetchMessages(
        apiKey: 'test-key',
        dstCallsign: 'KK7VZT-7',
        client: client,
      );

      expect(result.ok, isTrue);
      expect(result.messages, hasLength(2));
      final duplicate = result.messages.singleWhere(
        (message) => message.message == 'I really like the msg view :)',
      );
      expect(duplicate.messageId, '1');
      expect(duplicate.time.millisecondsSinceEpoch, 1788021592000);
    });
  });

  group('Tnc2Codec', () {
    test('decodes source, destination, path and info', () {
      final packet = Tnc2Codec.decode(
        'K7VZT-5>APRS,WIDE1-1,WIDE2-1:!4737.14N/12220.09W>Testing',
      );
      expect(packet, isNotNull);
      // AX.25 order: [dest, source, ...digis].
      expect(packet!.addresses.length, 4);
      expect(packet.addresses[0].toString(), 'APRS');
      expect(packet.addresses[1].toString(), 'K7VZT-5');
      expect(packet.addresses[2].toString(), 'WIDE1-1');
      expect(packet.addresses[3].toString(), 'WIDE2-1');
      expect(packet.dataStr, '!4737.14N/12220.09W>Testing');
      expect(packet.incoming, isTrue);
    });

    test('strips used-path markers and trailing CR/LF', () {
      final packet = Tnc2Codec.decode('N0CALL>APRS,WIDE1-1*:hello\r\n');
      expect(packet, isNotNull);
      expect(packet!.addresses[2].toString(), 'WIDE1-1');
      expect(packet.dataStr, 'hello');
    });

    test('rejects comments and malformed lines', () {
      expect(Tnc2Codec.decode('# server keep-alive'), isNull);
      expect(Tnc2Codec.decode(''), isNull);
      expect(Tnc2Codec.decode('no-colon-here'), isNull);
      expect(Tnc2Codec.decode('SRC>:empty info'), isNull);
      expect(Tnc2Codec.decode('>DEST:no source'), isNull);
    });

    test('round-trips through encode', () {
      const line = 'K7VZT-5>APRS,WIDE1-1:!4737.14N/12220.09W>Test';
      final packet = Tnc2Codec.decode(line);
      expect(packet, isNotNull);
      expect(Tnc2Codec.encode(packet!), line);
    });
  });

  group('AprsPacket third-party header', () {
    test('reports the original sender, not the relaying IGate', () {
      // An IGate (IGATE-1) gates an internet message onto RF wrapped in a
      // third-party header. The AX.25 source is the IGate; the real sender
      // (KC1MUR-5) lives inside the "}" header.
      final aprs = _parseTnc2(
        'IGATE-1>APRS,WIDE1-1:}KC1MUR-5>APRS,TCPIP*::KK7VZT-7 :hello{1',
      );
      expect(aprs.packet!.addresses[1].toString(), 'IGATE-1');
      expect(aprs.thirdPartySourceCallsign?.stationCallsign, 'KC1MUR-5');
      expect(aprs.sourceCallsignWithId, 'KC1MUR-5');
      expect(aprs.messageData.addressee, 'KK7VZT-7');
      expect(aprs.messageData.msgText, 'hello');
    });

    test('falls back to the AX.25 source for non-relayed traffic', () {
      final aprs = _parseTnc2('KC1MUR-5>APRS,WIDE1-1::KK7VZT-7 :hi{2');
      expect(aprs.thirdPartySourceCallsign, isNull);
      expect(aprs.sourceCallsignWithId, 'KC1MUR-5');
    });
  });

  group('AprsIsClient login', () {
    test('builds a login line with filter', () {
      final client = AprsIsClient(
        callsign: 'K7VZT-5',
        passcode: '12345',
        softwareName: 'HTCommander',
        softwareVersion: '0.1.21',
        filter: 'r/47.6/-122.3/50',
        network: _FakeAprsIsNetwork(),
      );
      expect(
        client.buildLoginLine(),
        'user K7VZT-5 pass 12345 vers HTCommander 0.1.21 '
        'filter r/47.6/-122.3/50',
      );
    });

    test('omits the filter clause when empty', () {
      final client = AprsIsClient(
        callsign: 'K7VZT',
        passcode: '-1',
        softwareName: 'HTCommander',
        softwareVersion: '1.0',
        filter: '',
        network: _FakeAprsIsNetwork(),
      );
      expect(
        client.buildLoginLine(),
        'user K7VZT pass -1 vers HTCommander 1.0',
      );
      expect(client.canTransmit, isFalse); // -1 is receive-only.
    });

    test('sends the login line on open and detects verified login', () async {
      final net = _FakeAprsIsNetwork();
      final client = AprsIsClient(
        callsign: 'K7VZT-5',
        passcode: '12345',
        softwareName: 'HTCommander',
        softwareVersion: '1.0',
        filter: '',
        network: net,
      );
      bool? verified;
      client.onLogin = (v) => verified = v;

      await client.open('example.com', 14580);
      expect(net.sent.single, client.buildLoginLine());

      net.serverSend('# aprsc 2.1 server\r\n');
      net.serverSend('# logresp K7VZT-5 verified, server T2XYZ\r\n');
      await Future<void>.delayed(Duration.zero);

      expect(verified, isTrue);
      expect(client.isVerified, isTrue);
      expect(client.state, AprsIsConnectionState.connected);
    });

    test('reassembles packet lines split across chunks', () async {
      final net = _FakeAprsIsNetwork();
      final client = AprsIsClient(
        callsign: 'K7VZT',
        passcode: '-1',
        softwareName: 'HTCommander',
        softwareVersion: '1.0',
        filter: '',
        network: net,
      );
      final lines = <String>[];
      client.onPacketLine = lines.add;

      await client.open('example.com', 14580);
      net.serverSend('K7VZT>APR');
      net.serverSend('S:hello\r\nN0CALL>APRS:hi\r\n');
      await Future<void>.delayed(Duration.zero);

      expect(lines, ['K7VZT>APRS:hello', 'N0CALL>APRS:hi']);
    });

    test('receive-only client never sends packets', () async {
      final net = _FakeAprsIsNetwork();
      final client = AprsIsClient(
        callsign: 'K7VZT',
        passcode: '-1',
        softwareName: 'HTCommander',
        softwareVersion: '1.0',
        filter: '',
        network: net,
      );
      await client.open('example.com', 14580);
      net.sent.clear();
      client.sendPacketLine('K7VZT>APRS:test');
      expect(net.sent, isEmpty);
    });
  });

  group('outgoing APRS messages', () {
    const radioId = 91;
    late ServerSocket server;
    Socket? socket;
    StreamIterator<String>? lines;
    late AprsIsManager manager;
    late AprsHandler handler;
    late DataBrokerClient bus;
    final rf = <TransmitDataFrameData>[];

    setUp(() async {
      DataBroker.clearDevice(0);
      DataBroker.clearDevice(1);
      DataBroker.clearDevice(radioId);
      rf.clear();
      await AppDatabase.openInMemory();
      socket = null;
      lines = null;
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      bus = DataBrokerClient();
      for (final entry in <String, Object>{
        'CallSign': 'N0CALL',
        'StationId': 7,
        'NextAprsMessageId': 1,
        'AprsIsEnabled': 1,
        'AprsIsServer': '127.0.0.1',
        'AprsIsPort': server.port,
      }.entries) {
        bus.dispatch(deviceId: 0, name: entry.key, data: entry.value);
      }
      bus.dispatch(
        deviceId: radioId,
        name: 'Channels',
        data: [
          {'channelId': 7, 'name': 'APRS'},
        ],
      );
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': radioId},
        ],
      );
      bus.subscribe(
        deviceId: radioId,
        name: 'TransmitDataFrame',
        callback: (_, _, data) {
          if (data is TransmitDataFrameData) rf.add(data);
        },
      );
      handler = AprsHandler()..init();
      await handler.ready;
      manager = AprsIsManager();
    });

    tearDown(() async {
      handler.dispose();
      await handler.ready;
      await manager.dispose();
      await lines?.cancel();
      socket?.destroy();
      await server.close();
      bus.dispose();
      await AppDatabase.close();
      DataBroker.clearDevice(0);
      DataBroker.clearDevice(1);
      DataBroker.clearDevice(radioId);
    });

    Future<void> connect({bool verified = true}) async {
      final loggedIn = Completer<void>();
      bus.subscribe(
        deviceId: DataBroker.allDevices,
        name: 'AprsIsState',
        callback: (_, _, data) {
          if (data ==
                  (verified
                      ? 'Connected (verified)'
                      : 'Connected (read-only)') &&
              !loggedIn.isCompleted) {
            loggedIn.complete();
          }
        },
      );
      final accepted = server.first;
      manager.init();
      socket = await accepted.timeout(const Duration(seconds: 5));
      lines = StreamIterator(
        socket!
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      expect(
        await lines!.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(lines!.current, startsWith('user N0CALL-7 pass '));
      socket!.write(
        '# logresp N0CALL-7 ${verified ? 'verified' : 'unverified'}, test\r\n',
      );
      await loggedIn.future.timeout(const Duration(seconds: 5));
    }

    Future<List<String>> sentLines() async {
      // The filter command is an ordered socket barrier, avoiding timing-based
      // assertions that an unexpected second packet was not sent.
      bus.dispatch(deviceId: 0, name: 'AprsIsRangeKm', data: 0);
      final packets = <String>[];
      while (await lines!.moveNext().timeout(const Duration(seconds: 5))) {
        if (lines!.current == '#filter default') return packets;
        packets.add(lines!.current);
      }
      fail('APRS-IS socket closed before the filter command');
    }

    Future<void> send(int deviceId) async {
      bus.dispatch(
        deviceId: 1,
        name: 'SendAprsMessage',
        data: AprsSendMessageData(
          destination: 'W1AW',
          message: 'Hello',
          radioDeviceId: deviceId,
          route: const ['Local', 'APRS', 'WIDE1-1', 'WIDE2-1'],
        ),
        store: false,
      );
      await handler.ready;
    }

    for (final deviceId in [radioId, -1]) {
      test(
        'sends directly to APRS-IS ${deviceId < 0 ? 'without' : 'with'} RF',
        () async {
          await connect();
          await send(deviceId);
          expect(await sentLines(), [
            'N0CALL-7>APRS,TCPIP*::W1AW     :Hello{1',
          ]);
          expect(rf, hasLength(deviceId < 0 ? 0 : 1));
          if (deviceId >= 0) {
            expect(rf.single.channelId, 7);
            expect(
              Tnc2Codec.encode(rf.single.packet!),
              'N0CALL-7>APRS,WIDE1-1,WIDE2-1::W1AW     :Hello{1',
            );
          }
        },
      );
    }

    test('an unverified connection does not prevent RF transmission', () async {
      await connect(verified: false);
      await send(radioId);
      expect(await sentLines(), isEmpty);
      expect(rf, hasLength(1));
    });

    test(
      'queued radio messages retain configured internet intent while disconnected',
      () async {
        bus.dispatch(deviceId: 1, name: 'ConnectedRadios', data: []);
        await send(radioId);
        expect(rf, isEmpty);
        expect(handler.outgoingMessages.single.parts.single.attempts, 0);
        await connect();
        await handler.processOutbox();
        expect(await sentLines(), ['N0CALL-7>APRS,TCPIP*::W1AW     :Hello{1']);
        expect(rf, isEmpty);
      },
    );

    test(
      'APRS-IS auto-ACK preserves authentication for a zero-SSID sender',
      () async {
        await connect();
        bus.dispatch(
          deviceId: 0,
          name: 'Stations',
          data: [
            const AprsStationInfo(
              callsign: 'W1AW',
              isAprs: true,
              authPassword: 'test-key',
            ),
          ],
        );
        final peer = AprsAuth()
          ..stations = [
            const AprsStationInfo(
              callsign: 'N0CALL-7',
              isAprs: true,
              authPassword: 'test-key',
            ),
          ];
        final received = Completer<void>();
        bus.subscribe(
          deviceId: 1,
          name: 'AprsFrame',
          callback: (_, _, data) {
            if (data is AprsFrameEventArgs &&
                data.aprsPacket.messageData.msgText == 'signed hello' &&
                !received.isCompleted) {
              received.complete();
            }
          },
        );
        final content = peer
            .addAprsAuth(
              'W1AW',
              'N0CALL-7',
              'signed hello',
              123,
              DateTime.now(),
            )
            .content;
        socket!.write('W1AW>APRS,TCPIP*:$content\r\n');
        await received.future.timeout(const Duration(seconds: 5));
        final outgoing = await sentLines();
        expect(outgoing, hasLength(1));
        final ack = Tnc2Codec.decode(outgoing.single)!;
        expect(AprsPacket.parse(ack)!.messageData.seqId, '123');
        expect(
          peer.checkAprsAuth(false, 'N0CALL-7', ack.dataStr, DateTime.now()),
          AuthState.success,
        );
      },
    );

    test('received RF messages retain IGate routing', () async {
      await connect();
      final aprs = _parseTnc2('W1AW>APRS,WIDE1-1::N0CALL-7 :Hello{2');
      bus.dispatch(
        deviceId: 1,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(aprs, aprs.packet!, null),
        store: false,
      );
      expect(await sentLines(), [
        'W1AW>APRS,WIDE1-1,qAR,N0CALL-7::N0CALL-7 :Hello{2',
      ]);
      expect(rf, isEmpty);
    });

    test('relayed messages and internet echoes are not sent back', () async {
      await connect();
      for (final line in [
        'N0CALL-7>APRS,WIDE1-1:}WXBOT>APRS,TCPIP,N0CALL-7*::W1AW     :Sunny{3',
        'WXBOT>APRS,WIDE1-1::W1AW     :Sunny{3',
        'N0CALL-7>APRS,TCPIP*::W1AW     :Hello{1',
      ]) {
        final aprs = _parseTnc2(line);
        aprs.packet!.incoming = false;
        if (line.contains('TCPIP*')) aprs.fromAprsIs = true;
        bus.dispatch(
          deviceId: 1,
          name: 'AprsFrame',
          data: AprsFrameEventArgs(aprs, aprs.packet!, null),
          store: false,
        );
      }
      expect(await sentLines(), isEmpty);
      expect(rf, isEmpty);
    });
  });

  group('AprsIsClient gating', () {
    test('gates a plain RF position packet up to the internet', () {
      final aprs = _parseTnc2('K7VZT-5>APRS,WIDE1-1:!4737.14N/12220.09W>Hi');
      expect(AprsIsClient.shouldGateToInternet(aprs), isTrue);
      final line = AprsIsClient.buildGateUpLine(aprs, 'N0CALL-10');
      expect(line, contains(',qAR,N0CALL-10:'));
      expect(line, startsWith('K7VZT-5>APRS,WIDE1-1,qAR,N0CALL-10:'));
    });

    test('does not gate packets with TCPIP/NOGATE in the path', () {
      expect(
        AprsIsClient.shouldGateToInternet(
          _parseTnc2('K7VZT>APRS,TCPIP*:!4737.14N/12220.09W>Hi'),
        ),
        isFalse,
      );
      expect(
        AprsIsClient.shouldGateToInternet(
          _parseTnc2('K7VZT>APRS,WIDE1-1,NOGATE:!4737.14N/12220.09W>Hi'),
        ),
        isFalse,
      );
    });

    test('does not gate a packet already from APRS-IS', () {
      final aprs = _parseTnc2('K7VZT>APRS,WIDE1-1:!4737.14N/12220.09W>Hi');
      aprs.fromAprsIs = true;
      expect(AprsIsClient.shouldGateToInternet(aprs), isFalse);
    });

    test('does not gate generic queries', () {
      expect(
        AprsIsClient.shouldGateToInternet(
          _parseTnc2('K7VZT>APRS,WIDE1-1:?APRS?'),
        ),
        isFalse,
      );
    });

    test('gates a message to a locally-heard station down to RF', () {
      final aprs = _parseTnc2('W1AW>APRS,TCPIP*::K7VZT    :Hello{1');
      expect(aprs.messageData.addressee.trim(), 'K7VZT');
      expect(AprsIsClient.shouldGateToRf(aprs, {'K7VZT'}), isTrue);
      // Not heard locally -> not gated.
      expect(AprsIsClient.shouldGateToRf(aprs, {'N0ONE'}), isFalse);
    });

    test('does not gate a position packet down to RF', () {
      final aprs = _parseTnc2('W1AW>APRS,TCPIP*:!4737.14N/12220.09W>Hi');
      expect(AprsIsClient.shouldGateToRf(aprs, {'W1AW'}), isFalse);
    });

    test('wraps a gated-down message in a third-party header', () {
      final aprs = _parseTnc2('WXBOT>APRS,TCPIP*,qAC,T2X::K9BDH    :Sunny{7');
      final payload = AprsIsClient.buildGateDownPayload(aprs, 'K9BDH-10');
      expect(payload, '}WXBOT>APRS,TCPIP,K9BDH-10*::K9BDH    :Sunny{7');

      // Heard back on RF (e.g. via a digipeater), the frame's AX.25 source is
      // the IGate, so the internet sender is never mistaken as locally heard,
      // and the third-party frame is never gated back up.
      final echo = _parseTnc2('K9BDH-10>APRS,WIDE1-1*:$payload');
      expect(echo.packet!.addresses[1].toString(), 'K9BDH-10');
      expect(echo.sourceCallsignWithId, 'WXBOT');
      expect(echo.messageData.addressee.trim(), 'K9BDH');
      expect(AprsIsClient.shouldGateToInternet(echo), isFalse);
    });

    test('identifies own-station transmissions by base callsign', () {
      expect(AprsIsClient.isOwnStation('K9BDH-7', 'K9BDH'), isTrue);
      expect(AprsIsClient.isOwnStation('k9bdh', 'K9BDH-10'), isTrue);
      expect(AprsIsClient.isOwnStation('WXBOT', 'K9BDH'), isFalse);
      expect(AprsIsClient.isOwnStation('K9BDH', ''), isFalse);
    });
  });
}
