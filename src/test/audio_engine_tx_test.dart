/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';
import 'package:htcommander/hamlib/xara/receiver_common.dart';
import 'package:htcommander/hamlib/xara/resample.dart';
import 'package:htcommander/radio/audio_engine.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';

Uint8List _payload(Uint8List packet) {
  expect(packet.first, 0x7e);
  expect(packet.last, 0x7e);
  expect(packet[1], 0);
  final List<int> bytes = <int>[];
  for (int i = 2; i < packet.length - 1; i++) {
    bytes.add(packet[i] == 0x7d ? packet[++i] ^ 0x20 : packet[i]);
  }
  return Uint8List.fromList(bytes);
}

class _Tx {
  final List<Uint8List> packets = <Uint8List>[];
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  final Completer<void> done = Completer<void>();
  late final AudioEngine engine = AudioEngine(
    (Map<String, Object?> event) {
      events.add(event);
      if (event['evt'] == 'txState' && event['transmitting'] == false) {
        done.complete();
      }
    },
    btSend: (Uint8List packet) async {
      if (packet[1] == 0) packets.add(packet);
    },
  );

  Future<void> send(Uint8List pcm, {bool data = true}) async {
    engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: data);
    await done.future.timeout(const Duration(seconds: 5));
  }

  List<int> decode(SbcBitAllocationMethod allocation) {
    final SbcDecoder decoder = SbcDecoder();
    final List<int> samples = <int>[];
    for (final Uint8List packet in packets) {
      final Uint8List bytes = _payload(packet);
      expect(bytes.length, lessThanOrEqualTo(300));
      int offset = 0;
      while (offset < bytes.length) {
        final Uint8List rest = Uint8List.sublistView(bytes, offset);
        final frame = decoder.probe(rest);
        expect(frame, isNotNull);
        expect(frame!.bitpool, 18);
        expect(frame.frequency, SbcFrequency.freq32K);
        expect(frame.mode, SbcMode.mono);
        expect(frame.allocationMethod, allocation);
        expect(frame.getFrameSize(), 44);
        final result = decoder.decode(
          Uint8List.sublistView(rest, 0, frame.getFrameSize()),
        );
        expect(result.success, isTrue);
        samples.addAll(result.pcmLeft);
        offset += frame.getFrameSize();
      }
      expect(offset, bytes.length);
    }
    return samples;
  }
}

Uint8List _pcm(List<double> samples) {
  final ByteData bytes = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    bytes.setInt16(
      i * 2,
      (samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

void main() {
  for (final bool data in <bool>[false, true]) {
    test(
      'stock bitrate and bounded complete packets for ${data ? "data" : "voice"}',
      () async {
        final _Tx tx = _Tx();
        await tx.send(
          _pcm(
            List<double>.generate(17 * 128, (int i) => 0.3 * math.sin(i * 0.3)),
          ),
          data: data,
        );
        expect(tx.packets.map((Uint8List p) => _payload(p).length), <int>[
          264,
          264,
          220,
        ]);
        expect(
          tx
              .decode(
                data
                    ? SbcBitAllocationMethod.snr
                    : SbcBitAllocationMethod.loudness,
              )
              .length,
          17 * 128,
        );
      },
    );
  }

  test('partial SBC input is carried across streamed PCM chunks', () async {
    final _Tx tx = _Tx();
    final Uint8List first = Uint8List(6 * 256 + 42);
    tx.engine.transmitVoice(first, 0, first.length, false, isDataFrame: true);
    final Uint8List second = Uint8List(214);
    tx.engine.transmitVoice(second, 0, second.length, false, isDataFrame: true);
    await tx.done.future.timeout(const Duration(seconds: 5));
    expect(tx.decode(SbcBitAllocationMethod.snr).length, 7 * 128);
  });

  test(
    'precomputed modem audio retains the ten-second buffering lead',
    () async {
      final _Tx tx = _Tx();
      await tx.send(Uint8List(3 * 32000 * 2));
      expect(tx.decode(SbcBitAllocationMethod.snr).length, 3 * 32000);
      expect(
        tx.events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
        contains(
          startsWith('TX audio: bitpool=18, lead=10000ms, audio=3000ms,'),
        ),
      );
    },
  );

  test('failed writes abort queued audio and report the failure', () async {
    final Completer<void> release = Completer<void>();
    final Completer<void> done = Completer<void>();
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    int audioWrites = 0;
    int endWrites = 0;
    final AudioEngine engine = AudioEngine(
      (event) {
        events.add(event);
        if (event['evt'] == 'txState' && event['transmitting'] == false) {
          done.complete();
        }
      },
      btSend: (packet) async {
        if (packet[1] != 0) {
          endWrites++;
          return;
        }
        audioWrites++;
        await release.future;
        throw StateError('write rejected');
      },
    );
    final Uint8List pcm = Uint8List(256 * 12);
    engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
    engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
    release.complete();
    await done.future.timeout(const Duration(seconds: 5));
    expect(audioWrites, 1);
    expect(endWrites, 1);
    expect(
      events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
      contains(contains('Voice transmit error: Bad state: write rejected')),
    );
  });

  test('failed stop writes still release transmit state', () async {
    final Completer<void> done = Completer<void>();
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    final AudioEngine engine = AudioEngine(
      (event) {
        events.add(event);
        if (event['evt'] == 'txState' && event['transmitting'] == false) {
          done.complete();
        }
      },
      btSend: (packet) async {
        if (packet[1] != 0) throw StateError('stop rejected');
      },
    );
    final Uint8List pcm = Uint8List(256);
    engine.transmitVoice(pcm, 0, pcm.length, false);
    await done.future.timeout(const Duration(seconds: 5));
    expect(
      events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
      contains(contains('Voice transmit stop error: Bad state: stop rejected')),
    );
  });

  for (final FmBandwidth bandwidth in FmBandwidth.values) {
    test(
      'XARA ${bandwidth.name} frame survives the stock SBC transmit path',
      () async {
        final FmRecord record = FmRecord.fromIndex(1)!;
        final Uint8List frame = buildData(
          record,
          bandwidth.level(record).frameBytes,
          Uint8List.fromList('Bluetooth continuity test'.codeUnits),
          false,
          3,
          false,
          const Trailer(leadReport: 0),
        );
        final Modulator modulator = Modulator(bandwidth);
        final math.Random rng = math.Random(42);
        final List<double> audio = <double>[
          ...List<double>.filled(12000, 0),
          ...modulator.transmission(
            record,
            3,
            <Uint8List>[frame],
            20,
            const TxOptions(driveDb: -5),
            rng.nextInt,
          ),
          ...List<double>.filled(12000, 0),
        ];
        final Resampler down = Resampler(48000, 32000);
        final _Tx tx = _Tx();
        final Uint8List pcm = _pcm(<double>[
          ...down.process(audio),
          ...down.flush(),
        ]);
        await tx.send(pcm);
        final List<double> compressed = tx
            .decode(SbcBitAllocationMethod.snr)
            .map((int n) => n / 32768.0)
            .toList();
        final Resampler up = Resampler(32000, 48000);
        final List<double> received = <double>[
          ...up.process(compressed),
          ...up.flush(),
        ];
        final FmReceiver receiver = FmReceiver(bandwidth, 3, <FmRecord>[
          record,
        ], 1);
        final List<Uint8List> frames = <Uint8List>[];
        for (int i = 0; i < received.length; i += 480) {
          for (final FmEvent event in receiver.feed(
            received.sublist(i, math.min(i + 480, received.length)),
          )) {
            if (event is FrameEv<FmCtrlEvent, FmRecord, FmFrameRx> &&
                event.frame.ok) {
              frames.add(event.frame.bytes);
            }
          }
        }
        expect(frames, <Uint8List>[frame]);
      },
    );
  }
}
