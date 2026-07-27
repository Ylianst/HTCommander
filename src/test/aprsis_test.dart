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

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/aprsis_client.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';

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
      expect(
        AprsIsClient.shouldGateToRf(aprs, {'K7VZT'}),
        isTrue,
      );
      // Not heard locally -> not gated.
      expect(AprsIsClient.shouldGateToRf(aprs, {'N0ONE'}), isFalse);
    });

    test('does not gate a position packet down to RF', () {
      final aprs = _parseTnc2('W1AW>APRS,TCPIP*:!4737.14N/12220.09W>Hi');
      expect(AprsIsClient.shouldGateToRf(aprs, {'W1AW'}), isFalse);
    });
  });
}
