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

//
// ax25_session_test.dart - End-to-end tests for the AX.25 connected-mode
// session (the Direwolf-derived data link state machine in
// lib/radio/ax25_session.dart).
//
// Two [AX25Session] instances are created on two different virtual radio
// device IDs and wired together with a [_RadioBridge]. The bridge turns a frame
// transmitted by one session (dispatched as a `TransmitDataFrame` event) into an
// incoming frame for the other session (a `UniqueDataFrame` event carrying a
// [TncDataFragment] with `incoming = true`). This is exactly the path a real
// radio + TNC would provide, so the two sessions genuinely negotiate a link and
// exchange acknowledged data over the data broker.
//
// Run with:  flutter test test/ax25_session_test.dart
//

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_session.dart';
import 'package:htcommander/radio/radio.dart' show TransmitDataFrameData;
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

/// Bridges the "over the air" path between two virtual radios.
///
/// Every frame a session transmits (a `TransmitDataFrame` event) is re-injected
/// as an incoming frame (`UniqueDataFrame` event) for the peer radio. An
/// optional [lossRate] can be used to randomly drop frames so the retransmission
/// / recovery logic can be exercised.
class _RadioBridge {
  final DataBrokerClient _client = DataBrokerClient();
  final int deviceA;
  final int deviceB;
  final double lossRate;
  final math.Random _rng;

  int deliveredFrames = 0;
  int droppedFrames = 0;

  _RadioBridge(this.deviceA, this.deviceB, {this.lossRate = 0.0, int seed = 1})
      : _rng = math.Random(seed) {
    _client.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TransmitDataFrame',
      callback: _onTransmit,
    );
  }

  void _onTransmit(int deviceId, String name, Object? data) {
    if (data is! TransmitDataFrameData) return;
    final packet = data.packet;
    if (packet == null) return;

    final int target;
    if (deviceId == deviceA) {
      target = deviceB;
    } else if (deviceId == deviceB) {
      target = deviceA;
    } else {
      return;
    }

    // Encode to bytes exactly as the radio would put on the air.
    final bytes = packet.toByteArray();

    // Optionally drop the frame to simulate a lossy channel.
    if (lossRate > 0 && _rng.nextDouble() < lossRate) {
      droppedFrames++;
      return;
    }

    // Deliver asynchronously (like a real radio) so we don't recurse deeply
    // through the data broker while a dispatch is already in progress.
    scheduleMicrotask(() {
      final fragment = TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: bytes,
        channelId: -1,
        regionId: -1,
        incoming: true,
        radioDeviceId: target,
      );
      deliveredFrames++;
      _client.dispatch(
        deviceId: target,
        name: 'UniqueDataFrame',
        data: fragment,
        store: false,
      );
    });
  }

  void dispose() => _client.dispose();
}

/// Collects data delivered to a session's callbacks.
class _Collector {
  final List<Uint8List> chunks = [];
  final List<Uint8List> uiChunks = [];
  final List<String> errors = [];

  void bind(AX25Session s) {
    s.onDataReceived = (sender, data) => chunks.add(Uint8List.fromList(data));
    s.onUiDataReceived = (sender, data) =>
        uiChunks.add(Uint8List.fromList(data));
    s.onError = (sender, err) => errors.add(err);
  }

  /// All received connected-mode bytes, concatenated in delivery order.
  Uint8List get allBytes {
    final b = BytesBuilder();
    for (final c in chunks) {
      b.add(c);
    }
    return b.toBytes();
  }

  String get text => utf8.decode(allBytes, allowMalformed: true);
  int get totalLen => allBytes.length;
}

void main() {
  // Pump the real event loop so pending microtasks and timers can run.
  Future<void> pump([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  // Wait until [cond] is true or a timeout elapses.
  Future<void> waitFor(
    bool Function() cond, {
    int timeoutMs = 5000,
    int stepMs = 10,
  }) async {
    final sw = Stopwatch()..start();
    while (!cond() && sw.elapsedMilliseconds < timeoutMs) {
      await pump(stepMs);
    }
  }

  AX25Session makeSession(int device, String callsign, {bool v22 = false, int frack = 1}) {
    final s = AX25Session(device);
    s.callSignOverride = callsign;
    s.stationIdOverride = 0;
    s.tracing = false;
    s.modulo128 = v22;
    s.frackSeconds = frack;
    return s;
  }

  List<AX25Address> path(String dest, String src) => [
        AX25Address.getAddress(dest)!,
        AX25Address.getAddress(src)!,
      ];

  group('AX25Session end-to-end', () {
    test('establishes a v2.0 link and transfers data in both directions',
        () async {
      final bridge = _RadioBridge(0, 1);
      final a = makeSession(0, 'NODEA');
      final b = makeSession(1, 'NODEB');
      final aRx = _Collector()..bind(a);
      final bRx = _Collector()..bind(b);

      addTearDown(() {
        a.dispose();
        b.dispose();
        bridge.dispose();
      });

      // A initiates the connection to B.
      expect(a.connect(path('NODEB', 'NODEA')), isTrue);

      await waitFor(() =>
          a.currentState == AX25ConnectionState.connected &&
          b.currentState == AX25ConnectionState.connected);

      expect(a.currentState, AX25ConnectionState.connected,
          reason: 'A should be connected');
      expect(b.currentState, AX25ConnectionState.connected,
          reason: 'B should be connected');

      // A -> B
      a.sendString('Hello from A');
      await waitFor(() => bRx.totalLen >= 'Hello from A'.length);
      expect(bRx.text, 'Hello from A');

      // B -> A
      b.sendString('Reply from B');
      await waitFor(() => aRx.totalLen >= 'Reply from B'.length);
      expect(aRx.text, 'Reply from B');

      // Clean disconnect initiated by A.
      a.disconnect();
      await waitFor(() =>
          a.currentState == AX25ConnectionState.disconnected &&
          b.currentState == AX25ConnectionState.disconnected);

      expect(a.currentState, AX25ConnectionState.disconnected);
      expect(b.currentState, AX25ConnectionState.disconnected);
      expect(aRx.errors, isEmpty);
      expect(bRx.errors, isEmpty);
    });

    test('transfers a large multi-frame payload that exceeds the window',
        () async {
      final bridge = _RadioBridge(0, 1);
      final a = makeSession(0, 'NODEA');
      final b = makeSession(1, 'NODEB');
      // Small frames + small window force many I-frames and several ACK rounds.
      a.packetLength = 32;
      b.packetLength = 32;
      a.maxFrames = 4;
      b.maxFrames = 4;
      final bRx = _Collector()..bind(b);

      addTearDown(() {
        a.dispose();
        b.dispose();
        bridge.dispose();
      });

      expect(a.connect(path('NODEB', 'NODEA')), isTrue);
      await waitFor(() =>
          a.currentState == AX25ConnectionState.connected &&
          b.currentState == AX25ConnectionState.connected);

      // 500 bytes of deterministic data -> ~16 I-frames through a window of 4.
      final payload = Uint8List.fromList(
        List<int>.generate(500, (i) => (i * 7 + 3) & 0xFF),
      );
      a.send(payload);

      await waitFor(() => bRx.totalLen >= payload.length, timeoutMs: 10000);

      expect(bRx.totalLen, payload.length,
          reason: 'all bytes should be delivered');
      expect(bRx.allBytes, equals(payload),
          reason: 'reassembled stream should match the original, in order');
    });

    test('exchanges several interleaved messages in both directions',
        () async {
      // Note: the current AX25Packet wire codec only round-trips modulo-8
      // (v2.0) framing, so these tests exercise the v2.0 path. The session's
      // v2.2 state machine is present but its extended (modulo-128) I/S frames
      // cannot be carried by the existing packet encoder/decoder.
      final bridge = _RadioBridge(0, 1);
      final a = makeSession(0, 'NODEA');
      final b = makeSession(1, 'NODEB');
      final aRx = _Collector()..bind(a);
      final bRx = _Collector()..bind(b);

      addTearDown(() {
        a.dispose();
        b.dispose();
        bridge.dispose();
      });

      expect(a.connect(path('NODEB', 'NODEA')), isTrue);
      await waitFor(() =>
          a.currentState == AX25ConnectionState.connected &&
          b.currentState == AX25ConnectionState.connected);

      const aToB = ['one\n', 'two\n', 'three\n', 'four\n'];
      const bToA = ['alpha\n', 'beta\n', 'gamma\n'];

      // Fire everything off back-to-back in both directions.
      for (final m in aToB) {
        a.sendString(m);
      }
      for (final m in bToA) {
        b.sendString(m);
      }

      final expectedB = aToB.join();
      final expectedA = bToA.join();

      await waitFor(
        () => bRx.totalLen >= expectedB.length && aRx.totalLen >= expectedA.length,
        timeoutMs: 10000,
      );

      expect(bRx.text, expectedB,
          reason: 'B should receive A\'s messages in order');
      expect(aRx.text, expectedA,
          reason: 'A should receive B\'s messages in order');
    });

    test('recovers and delivers reliably over a lossy channel', () async {
      // Drop ~25% of frames in both directions; the ARQ machinery (T1 timeouts,
      // REJ, retransmission) must still deliver everything eventually.
      final bridge = _RadioBridge(0, 1, lossRate: 0.25, seed: 42);
      final a = makeSession(0, 'NODEA', frack: 1);
      final b = makeSession(1, 'NODEB', frack: 1);
      a.packetLength = 64;
      b.packetLength = 64;
      final bRx = _Collector()..bind(b);

      addTearDown(() {
        a.dispose();
        b.dispose();
        bridge.dispose();
      });

      expect(a.connect(path('NODEB', 'NODEA')), isTrue);
      await waitFor(
        () =>
            a.currentState == AX25ConnectionState.connected &&
            b.currentState == AX25ConnectionState.connected,
        timeoutMs: 20000,
      );
      expect(a.currentState, AX25ConnectionState.connected,
          reason: 'link should establish despite loss');

      final payload = Uint8List.fromList(
        List<int>.generate(300, (i) => (i * 5 + 1) & 0xFF),
      );
      a.send(payload);

      await waitFor(() => bRx.totalLen >= payload.length, timeoutMs: 25000);

      expect(bRx.totalLen, payload.length,
          reason: 'every byte must arrive despite dropped frames');
      expect(bRx.allBytes, equals(payload),
          reason: 'data must be reassembled correctly and in order');
      expect(bridge.droppedFrames, greaterThan(0),
          reason: 'the test should actually have dropped some frames');
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}
