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
// dart_link_test.dart - Tests for the DART link layer (datagrams + ARQ).
//
// Usage:
//   dart run test/dart_link_test.dart datagram   # connectionless multicast
//   dart run test/dart_link_test.dart arq        # reliable ARQ round-trip
//   dart run test/dart_link_test.dart adapt      # rate adaptation up/down
//   dart run test/dart_link_test.dart all
//

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:htcommander/hamlib/dart_link.dart';
import 'package:htcommander/hamlib/dart_modem.dart';
import 'package:htcommander/hamlib/dart_packet_info.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

int _pass = 0;
int _fail = 0;

void main(List<String> args) {
  final cmd = args.isEmpty ? 'all' : args[0];

  if (cmd == 'datagram' || cmd == 'all') _testDatagram();
  if (cmd == 'arq' || cmd == 'all') _testArq();
  if (cmd == 'window' || cmd == 'all') _testSlidingWindow();
  if (cmd == 'adapt' || cmd == 'all') _testAdaptation();
  if (cmd == 'modef' || cmd == 'all') _testModeFFallback();

  print('');
  print('==================================================');
  print('Link layer tests: $_pass passed, $_fail failed');
  exit(_fail > 0 ? 1 : 0);
}

void _check(String label, bool ok) {
  if (ok) {
    _pass++;
    print('  PASS  $label');
  } else {
    _fail++;
    print('  FAIL  $label');
  }
}

// ============================================================================
// Test 1: Connectionless datagram (multicast / broadcast / chat)
// ============================================================================

void _testDatagram() {
  print('--- Connectionless datagram (multicast) ---');

  final tx = DartLink(config: const DartLinkConfig(callsign: 'N0CALL'));
  final rx = DartLink(config: const DartLinkConfig(callsign: 'W1AW'));

  const message = 'CQ CQ de N0CALL, testing DART broadcast';
  final frame = tx.sendDatagram(
    Uint8List.fromList(message.codeUnits),
    destination: '*',
    mode: DartMode.mode1,
  );

  print('  TX: ${frame.info.summary()}');
  _check('datagram is broadcast', frame.info.broadcast);
  _check('datagram frame type', frame.info.frameType == DartFrameType.datagram);

  // Receiver decodes it (through SBC to be realistic)
  final event = rx.receive(_sbc(frame.pcm));
  _check('datagram received', event != null);
  if (event != null) {
    print('  RX: ${event.info.summary()}');
    _check('payload delivered', event.delivered);
    _check(
      'payload matches',
      event.payload != null &&
          String.fromCharCodes(event.payload!) == message,
    );
    _check('no ACK response (connectionless)', event.response == null);
    _check('signal quality present', event.info.quality != null);
  }
  print('');
}

// ============================================================================
// Test 2: Reliable ARQ round-trip with ACK
// ============================================================================

void _testArq() {
  print('--- Reliable ARQ round-trip (ACK) ---');

  final alice = DartLink(
    config: const DartLinkConfig(callsign: 'ALICE', adaptive: false),
  );
  final bob = DartLink(
    config: const DartLinkConfig(callsign: 'BOB', adaptive: false),
  );

  const message = 'Reliable message requiring acknowledgement';
  final dataFrame = alice.sendReliable(
    Uint8List.fromList(message.codeUnits),
    destination: 'BOB',
    mode: DartMode.mode2,
  )!;
  print('  TX data: ${dataFrame.info.summary()}');
  _check('alice has pending frame', alice.hasPending);

  // Bob receives the data frame → should deliver + produce an ACK
  final bobEvent = bob.receive(_sbc(dataFrame.pcm));
  _check('bob received data', bobEvent != null);
  if (bobEvent == null) {
    print('');
    return;
  }
  print('  RX data: ${bobEvent.info.summary()}');
  _check('bob delivered payload', bobEvent.delivered);
  _check(
    'bob payload matches',
    bobEvent.payload != null &&
        String.fromCharCodes(bobEvent.payload!) == message,
  );
  _check('bob generated ACK', bobEvent.response != null);

  if (bobEvent.response != null) {
    print('  TX ack:  ${bobEvent.response!.info.summary()}');
    _check('ACK is mode 0', bobEvent.response!.info.modeIndex == 0);

    // Alice receives the ACK → clears pending
    final aliceEvent = alice.receive(_sbc(bobEvent.response!.pcm));
    _check('alice received ACK', aliceEvent != null);
    if (aliceEvent != null) {
      print('  RX ack:  ${aliceEvent.info.summary()}');
      _check('alice saw ACK', aliceEvent.ackReceived);
      _check('alice pending cleared', !alice.hasPending);
    }
  }
  print('');
}

// ============================================================================
// Test 3: Sliding-window selective-repeat ARQ
// ============================================================================

void _testSlidingWindow() {
  print('--- Sliding-window selective repeat ---');

  final alice = DartLink(
    config: const DartLinkConfig(
      callsign: 'ALICE',
      adaptive: false,
      windowSize: 4,
    ),
  );
  final bob = DartLink(
    config: const DartLinkConfig(callsign: 'BOB', windowSize: 4),
  );

  // Alice sends 4 frames back-to-back (fills the window).
  final messages = ['frame-A', 'frame-B', 'frame-C', 'frame-D'];
  final frames = <DartTxFrame>[];
  for (final m in messages) {
    final f = alice.sendReliable(
      Uint8List.fromList(m.codeUnits),
      destination: 'BOB',
    );
    _check('sent "$m" (window not full)', f != null);
    if (f != null) frames.add(f);
  }
  _check('4 frames in flight', alice.inFlight == 4);
  _check(
    'window full → 5th send blocked',
    alice.sendReliable(
          Uint8List.fromList('overflow'.codeUnits),
          destination: 'BOB',
        ) ==
        null,
  );

  // Bob receives frames A, C, D but B is "lost" (skip index 1).
  final delivered = <String>[];
  final acks = <DartTxFrame>[];
  for (int i = 0; i < frames.length; i++) {
    if (i == 1) continue; // frame-B lost in the air
    final ev = bob.receive(_sbc(frames[i].pcm));
    if (ev != null) {
      for (final p in ev.deliveredPayloads) {
        delivered.add(String.fromCharCodes(p));
      }
      if (ev.response != null) acks.add(ev.response!);
    }
  }
  // Only frame-A should have been delivered in order; C and D are buffered
  // waiting for B.
  print('  Delivered so far: $delivered');
  _check(
    'only frame-A delivered (B missing blocks C,D)',
    delivered.length == 1 && delivered[0] == 'frame-A',
  );

  // Alice processes the ACKs for A, C, D.
  for (final ack in acks) {
    alice.receive(_sbc(ack.pcm));
  }
  // Frame-B (seq 1) is still unacked → it remains the send base.
  _check('frame-B still pending', alice.pendingSeq == 1);

  // Alice retransmits the missing frame-B (selective repeat — just that one).
  final rtxB = alice.retransmit(seq: 1);
  _check('retransmitted frame-B', rtxB != null);

  // Bob receives the retransmitted B → now B, C, D all deliver in order.
  final evB = bob.receive(_sbc(rtxB!.pcm));
  if (evB != null) {
    for (final p in evB.deliveredPayloads) {
      delivered.add(String.fromCharCodes(p));
    }
    if (evB.response != null) alice.receive(_sbc(evB.response!.pcm));
  }
  print('  Delivered after B retransmit: $delivered');
  _check(
    'all 4 delivered in order',
    delivered.join(',') == 'frame-A,frame-B,frame-C,frame-D',
  );
  _check('alice window drained', !alice.hasPending);
  print('');
}

// ============================================================================
// Test 4: Rate adaptation (up on ACK streak, down on NACK)
// ============================================================================

void _testAdaptation() {
  print('--- Rate adaptation ---');

  final alice = DartLink(
    config: const DartLinkConfig(
      callsign: 'ALICE',
      initialMode: DartMode.mode1,
      adaptive: true,
      rateUpThreshold: 3,
    ),
  );
  final bob = DartLink(
    config: const DartLinkConfig(callsign: 'BOB', adaptive: false),
  );

  print('  Start mode: ${alice.mode.index}');
  _check('starts at mode 1', alice.mode.index == 1);

  // Send 3 reliable frames, each ACKed → after 3 clean ACKs, rate bumps up.
  for (int i = 0; i < 3; i++) {
    final data = alice.sendReliable(
      Uint8List.fromList('msg $i'.codeUnits),
      destination: 'BOB',
    )!;
    final bobEvent = bob.receive(_sbc(data.pcm));
    if (bobEvent?.response != null) {
      alice.receive(_sbc(bobEvent!.response!.pcm));
    }
    print('  After ACK ${i + 1}: mode ${alice.mode.index}');
  }
  _check('rate bumped up after 3 ACKs', alice.mode.index == 2);

  // Now simulate a NACK → rate should drop and the frame is retransmitted.
  final modeBefore = alice.mode.index;
  alice.sendReliable(
    Uint8List.fromList('will be nacked'.codeUnits),
    destination: 'BOB',
  );
  // Bob sends a NACK for Alice's outstanding frame (e.g. its payload CRC
  // failed on his end). Alice receives it, drops rate, and selectively
  // retransmits just that frame.
  final nack = _makeNack(bob, dest: 'ALICE', seqNum: alice.pendingSeq!);
  final aliceNackEvent = alice.receive(_sbc(nack.pcm));
  _check('alice saw NACK', aliceNackEvent?.nackReceived ?? false);
  print('  Mode before NACK: $modeBefore, after NACK: ${alice.mode.index}');
  _check('rate dropped after NACK', alice.mode.index < modeBefore);
  _check(
    'NACK triggered selective retransmit',
    aliceNackEvent?.response != null,
  );
  if (aliceNackEvent?.response != null) {
    _check(
      'retransmit count = 1',
      aliceNackEvent!.response!.info.retransmitCount == 1,
    );
  }
  print('');
}

/// Build a NACK control frame from [bob] addressed to [dest] for [seqNum].
DartTxFrame _makeNack(DartLink bob, {required String dest, required int seqNum}) {
  final pcm = bob.modem.encode(
    payload: Uint8List(0),
    mode: DartMode.mode0,
    source: bob.config.callsign,
    destination: dest,
    seqNum: seqNum,
    flags: DartFlags.nack,
  );
  return DartTxFrame(
    pcm: pcm,
    info: DartPacketInfo(
      direction: DartDirection.transmit,
      timestamp: DateTime.now(),
      modeIndex: 0,
      constellation: DartModeParams.mode0.constellation,
      ldpcRate: DartModeParams.mode0.ldpcRate,
      modeDescription: DartModeParams.mode0.description,
      frameType: DartFrameType.nack,
      source: bob.config.callsign,
      destination: dest,
      seqNum: seqNum,
      payloadLength: 0,
      broadcast: false,
      durationMs: 0,
    ),
  );
}

// ============================================================================
// Test 5: Automatic Mode F fallback on repeated failure
// ============================================================================

void _testModeFFallback() {
  print('--- Automatic Mode F fallback ---');

  final alice = DartLink(
    config: const DartLinkConfig(
      callsign: 'ALICE',
      initialMode: DartMode.mode0,
      adaptive: true,
      allowModeF: true,
    ),
  );
  final bob = DartLink(config: const DartLinkConfig(callsign: 'BOB'));

  _check('starts at mode 0', alice.mode == DartMode.mode0);

  // Send a reliable frame; a NACK while at mode 0 drops the ladder past mode 0
  // into Mode F (the amplitude-immune fallback). The NACK also triggers a
  // selective retransmit, which now goes out at Mode F.
  const message = 'Fallback message over 4-FSK';
  alice.sendReliable(
    Uint8List.fromList(message.codeUnits),
    destination: 'BOB',
  );
  final nack = _makeNack(bob, dest: 'ALICE', seqNum: alice.pendingSeq!);
  final nackEvent = alice.receive(_sbc(nack.pcm));
  print('  After NACK at mode 0: ${alice.mode}');
  _check('dropped to Mode F', alice.mode == DartMode.modeF);
  _check('NACK produced a retransmit', nackEvent?.response != null);
  _check(
    'retransmit uses Mode F',
    nackEvent?.response?.info.modeIndex == DartMode.modeF.index,
  );

  // The Mode F retransmit round-trips through a hostile (clipped + SBC) audio
  // path where the QAM modes fail outright.
  if (nackEvent?.response != null) {
    final hostile = _hardClip(_sbc(nackEvent!.response!.pcm), 0.08);
    final ev = bob.receive(hostile);
    _check('Mode F frame decoded through hostile path',
        ev != null && ev.delivered);
    if (ev?.payload != null) {
      print('  RX: ${ev!.info.summary()}');
      _check('payload matches over Mode F',
          String.fromCharCodes(ev.payload!) == message);
    }
  }

  // allowModeF=false keeps the floor at mode 0 (Mode F never entered).
  final noFallback = DartLink(
    config: const DartLinkConfig(
      callsign: 'CARL',
      initialMode: DartMode.mode0,
      adaptive: true,
      allowModeF: false,
    ),
  );
  noFallback.sendReliable(Uint8List.fromList('x'.codeUnits), destination: 'BOB');
  final nack2 = _makeNack(bob, dest: 'CARL', seqNum: noFallback.pendingSeq!);
  noFallback.receive(_sbc(nack2.pcm));
  _check('allowModeF=false stays at mode 0', noFallback.mode == DartMode.mode0);
  print('');
}

/// Hard-clip PCM to a fraction of its peak (amplitude-hostile audio path).
Int16List _hardClip(Int16List pcm, double fraction) {
  int peak = 1;
  for (final s in pcm) {
    final int a = s.abs();
    if (a > peak) peak = a;
  }
  final int limit = (peak * fraction).round().clamp(1, 32767);
  final out = Int16List(pcm.length);
  for (int i = 0; i < pcm.length; i++) {
    out[i] = pcm[i].clamp(-limit, limit);
  }
  return out;
}

// ============================================================================
// SBC round-trip helper (realistic Bluetooth audio path)
// ============================================================================

Int16List _sbc(Int16List pcm) {
  final frame = SbcFrame()
    ..frequency = SbcFrequency.freq32K
    ..mode = SbcMode.mono
    ..allocationMethod = SbcBitAllocationMethod.loudness
    ..blocks = 16
    ..subbands = 8
    ..bitpool = 18;

  final encoder = SbcEncoder();
  final decoder = SbcDecoder();
  final int samplesPerFrame = frame.blocks * frame.subbands;
  final out = <int>[];

  for (int off = 0; off < pcm.length; off += samplesPerFrame) {
    final buf = Int16List(samplesPerFrame);
    for (int i = 0; i < samplesPerFrame; i++) {
      final int idx = off + i;
      buf[i] = idx < pcm.length ? pcm[idx] : 0;
    }
    final enc = encoder.encode(buf, null, frame);
    if (enc == null) continue;
    final dec = decoder.decode(enc);
    if (!dec.success) continue;
    out.addAll(dec.pcmLeft);
  }
  return Int16List.fromList(out);
}
