// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sbc/radio_audio_codec.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';
import 'package:htcommander/sbc/sbc_tables.dart';

Uint8List _packet(int command, List<int> payload) {
  final bytes = BytesBuilder()..add([0x7e, command]);
  for (final byte in payload) {
    if (byte == 0x7d || byte == 0x7e) {
      bytes.add([0x7d, byte ^ 0x20]);
    } else {
      bytes.addByte(byte);
    }
  }
  return (bytes..addByte(0x7e)).takeBytes();
}

Int16List _signal(int count, int seed) {
  final random = math.Random(seed);
  return Int16List.fromList(
    List.generate(count, (i) {
      if (i % 31 == 0) return -32768;
      if (i % 29 == 0) return 32767;
      return random.nextInt(65536) - 32768;
    }),
  );
}

SbcFrame _frame({bool snr = false}) => SbcFrame()
  ..frequency = SbcFrequency.freq32K
  ..blocks = 16
  ..mode = SbcMode.mono
  ..allocationMethod = snr
      ? SbcBitAllocationMethod.snr
      : SbcBitAllocationMethod.loudness
  ..subbands = 8
  ..bitpool = 18;

// The Dart encoder cannot create dual-channel frames; use quantized wire data.
Uint8List _dualFixture(SbcFrame frame, int seed) {
  final bytes = Uint8List(frame.getFrameSize())
    ..fillRange(0, frame.getFrameSize(), 0xff);
  bytes[0] = 0x9c;
  bytes[1] =
      (frame.frequency.index << 6) |
      ((frame.blocks ~/ 4 - 1) << 4) |
      (frame.mode.index << 2) |
      (frame.allocationMethod.index << 1) |
      (frame.subbands == 8 ? 1 : 0);
  bytes[2] = frame.bitpool;
  for (int i = 4 + frame.subbands; i < bytes.length; i++) {
    bytes[i] = (i * 37 + seed * 29) & 0xff;
  }
  final usedBits = 32 + 8 * frame.subbands + 2 * frame.blocks * frame.bitpool;
  bytes[bytes.length - 1] &= (0xff << ((8 - usedBits % 8) % 8)) & 0xff;
  bytes[3] = SbcTables.computeCrc(frame, bytes, bytes.length);
  return bytes;
}

EncodedRadioAudio _referenceEncode(
  Uint8List pcm,
  SbcEncoder encoder,
  SbcFrame frame,
) {
  final payload = BytesBuilder();
  final batches = BytesBuilder();
  final lengths = <int>[];
  final samples = <int>[];
  int framesInPacket = 0;
  int framesInBatch = 0;
  int packetsInBatch = 0;
  final completeBytes = pcm.length ~/ 256 * 256;
  final input = ByteData.sublistView(pcm);
  for (int offset = 0; offset < completeBytes; offset += 256) {
    final block = Int16List(128);
    for (int i = 0; i < block.length; i++) {
      block[i] = input.getInt16(offset + i * 2, Endian.little);
    }
    payload.add(encoder.encode(block, null, frame)!);
    framesInPacket++;
    framesInBatch++;
    if (framesInPacket == 6 || offset + 256 == completeBytes) {
      batches.add(_packet(0, payload.takeBytes()));
      framesInPacket = 0;
      packetsInBatch++;
    }
    if (packetsInBatch == 4 || offset + 256 == completeBytes) {
      lengths.add(batches.length - lengths.fold(0, (a, b) => a + b));
      samples.add(framesInBatch * 128);
      framesInBatch = 0;
      packetsInBatch = 0;
    }
  }
  return EncodedRadioAudio(
    pcmConsumed: completeBytes,
    data: batches.takeBytes(),
    lengths: Int32List.fromList(lengths),
    samples: Int32List.fromList(samples),
  );
}

List<ReceivedRadioAudio> _receive(
  RadioAudioCodec codec,
  Uint8List bytes, {
  int mask = (1 << 0) | (1 << 3),
}) {
  final packets = <ReceivedRadioAudio>[];
  codec.receive(bytes, decodeMask: () => mask, onPacket: packets.add);
  return packets;
}

Uint8List _encodeInIsolate() {
  final codec = RadioAudioCodec();
  try {
    return codec.encode(Uint8List(256), isDataFrame: false).data;
  } finally {
    codec.dispose();
  }
}

void main() {
  late RadioAudioCodec codec;
  setUp(() => codec = RadioAudioCodec());
  tearDown(() => codec.dispose());

  for (final snr in [false, true]) {
    test('fused TX matches Dart bytes and batches, SNR=$snr', () {
      final storage = Uint8List(3 + 98304 + 25 * 256 + 37);
      final data = ByteData.sublistView(storage, 3);
      final signal = _signal(data.lengthInBytes ~/ 2, 73);
      for (int i = 0; i < signal.length; i++) {
        data.setInt16(i * 2, signal[i], Endian.little);
      }
      final encoder = SbcEncoder();
      final frame = _frame(snr: snr);
      for (final chunk in [
        Uint8List.sublistView(storage, 3, 3 + 98304),
        Uint8List.sublistView(storage, 3 + 98304),
      ]) {
        final native = codec.encode(chunk, isDataFrame: snr);
        final reference = _referenceEncode(chunk, encoder, frame);
        expect(native.pcmConsumed, reference.pcmConsumed);
        expect(native.data, reference.data);
        expect(native.lengths, reference.lengths);
        expect(native.samples, reference.samples);
      }
    });
  }

  test('incomplete PCM is not consumed or hidden in codec state', () {
    for (final length in [0, 1, 255]) {
      final encoded = codec.encode(Uint8List(length), isDataFrame: false);
      expect(encoded.pcmConsumed, 0);
      expect(encoded.data, isEmpty);
      expect(encoded.lengths, isEmpty);
      expect(encoded.samples, isEmpty);
    }
    final chunk = Uint8List(256);
    expect(
      codec.encode(chunk, isDataFrame: false).data,
      _referenceEncode(chunk, SbcEncoder(), _frame()).data,
    );
  });

  test('native asset resolves in a background audio isolate', () async {
    expect(
      await Isolate.run(_encodeInIsolate),
      _referenceEncode(Uint8List(256), SbcEncoder(), _frame()).data,
    );
  });

  for (final bands in [4, 8]) {
    for (final mode in SbcMode.values) {
      test('RX matches Dart: $bands subbands, ${mode.name}', () {
        int seed = 0;
        for (final frequency in SbcFrequency.values) {
          for (final blocks in [4, 8, 12, 16]) {
            for (final allocation in SbcBitAllocationMethod.values) {
              for (final bitpool in [2, 18, 53]) {
                final frame = SbcFrame()
                  ..frequency = frequency
                  ..blocks = blocks
                  ..mode = mode
                  ..allocationMethod = allocation
                  ..subbands = bands
                  ..bitpool = bitpool;
                if (!frame.isValid()) continue;
                final encoder = SbcEncoder();
                final decoder = SbcDecoder();
                codec.resetReceiver();
                final encoded = BytesBuilder();
                final expected = <int>[];
                for (int n = 0; n < 3; n++) {
                  final bytes = mode == SbcMode.dualChannel
                      ? _dualFixture(frame, seed++)
                      : encoder.encode(
                          _signal(blocks * bands, seed++),
                          _signal(blocks * bands, seed++),
                          frame,
                        )!;
                  encoded.add(bytes);
                  final decoded = decoder.decode(bytes);
                  expect(decoded.success, isTrue);
                  expected.addAll(decoded.pcmLeft);
                }
                final result = _receive(
                  codec,
                  _packet(3, encoded.takeBytes()),
                ).single;
                final label = '${frequency.name}/$blocks/$allocation/$bitpool';
                expect(result.error, 0, reason: label);
                expect(result.pcm, expected, reason: label);
                expect(result.decodedFrames, 3, reason: label);
                expect(
                  result.audioUs,
                  3 * (blocks * bands * 1000000 ~/ frame.getFrequencyHz()),
                  reason: label,
                );
                expect(result.formats, [
                  (frequency.index << 16) | (mode.index << 8) | bitpool,
                ], reason: label);
              }
            }
          }
        }
      });
    }
  }

  test('mSBC decoding and duration match the Dart reference', () {
    final frame = SbcFrame.createMsbc();
    final encoder = SbcEncoder();
    final decoder = SbcDecoder();
    final payload = BytesBuilder();
    final expected = <int>[];
    for (int n = 0; n < 4; n++) {
      final bytes = encoder.encode(_signal(120, n), null, frame)!;
      payload.add(bytes);
      final result = decoder.decode(bytes);
      expect(result.success, isTrue);
      expected.addAll(result.pcmLeft);
    }
    final result = _receive(codec, _packet(3, payload.takeBytes())).single;
    expect(result.error, 0);
    expect(result.pcm, expected);
    expect(result.decodedFrames, 4);
    expect(result.audioUs, 4 * (120 * 1000000 ~/ frame.getFrequencyHz()));
  });

  test('RX storage grows for large packets and resets its format list', () {
    final encoder = SbcEncoder();
    final decoder = SbcDecoder();
    final payload = BytesBuilder();
    final expected = <int>[];
    for (int n = 0; n < 512; n++) {
      final frame = _frame()..bitpool = 2 + n % 64;
      final bytes = encoder.encode(_signal(128, n), null, frame)!;
      payload.add(bytes);
      final decoded = decoder.decode(bytes);
      expect(decoded.success, isTrue);
      expected.addAll(decoded.pcmLeft);
    }
    final large = _receive(codec, _packet(3, payload.takeBytes())).single;
    expect(large.error, 0);
    expect(large.decodedFrames, 512);
    expect(large.pcm, expected);
    expect(large.formats, List.generate(64, (n) => (1 << 16) | (n + 2)));

    final next = encoder.encode(_signal(128, 999), null, _frame())!;
    final small = _receive(codec, _packet(3, next)).single;
    expect(small.error, 0);
    expect(small.pcm, decoder.decode(next).pcmLeft);
    expect(small.formats, [(1 << 16) | 18]);
    expect(large.pcm, expected);
  });

  test('split escapes, garbage, and consecutive delimiters preserve audio', () {
    final frame = _frame();
    final encoded = SbcEncoder().encode(_signal(128, 42), null, frame)!;
    final expected = SbcDecoder().decode(encoded).pcmLeft;
    final bytes = Uint8List.fromList([
      1,
      2,
      0x7d,
      0x7e,
      0x7e,
      ..._packet(3, encoded),
      0x7e,
    ]);
    final packets = <ReceivedRadioAudio>[];
    for (final byte in bytes) {
      packets.addAll(_receive(codec, Uint8List.fromList([byte])));
    }
    expect(packets, hasLength(1));
    expect(packets.single.error, 0);
    expect(packets.single.pcm, expected);
  });

  test('bulk spans preserve framing across scan and input boundaries', () {
    final payload = Uint8List(700)..fillRange(0, 700, 0x11);
    for (final offset in [14, 15, 254, 255, 510, 511, 699]) {
      payload[offset] = offset.isEven ? 0x7d : 0x7e;
    }
    final frame = SbcEncoder().encode(_signal(128, 42), null, _frame())!;
    final expected = SbcDecoder().decode(frame).pcmLeft;
    final wire = Uint8List.fromList([
      ..._packet(2, payload),
      ..._packet(3, frame),
    ]);
    for (final chunk in [15, 16, 255, 256, 257, wire.length]) {
      codec.resetReceiver();
      final packets = <ReceivedRadioAudio>[];
      for (int offset = 0; offset < wire.length; offset += chunk) {
        packets.addAll(
          _receive(
            codec,
            Uint8List.sublistView(
              wire,
              offset,
              math.min(offset + chunk, wire.length),
            ),
          ),
        );
      }
      expect(packets.map((p) => p.command), [2, 3], reason: 'chunk=$chunk');
      expect(packets.map((p) => p.error), [0, 0]);
      expect(packets.first.payloadBytes, payload.length);
      expect(packets.first.pcm, isEmpty);
      expect(packets.last.pcm, expected);
    }
  });

  test('bulk and escaped bytes respect the exact packet limit', () {
    final frame = SbcEncoder().encode(_signal(128, 12), null, _frame())!;
    final expected = SbcDecoder().decode(frame).pcmLeft;
    for (final overflow in [false, true]) {
      for (final escapedLast in [false, true]) {
        codec.resetReceiver();
        final length = 65535 + (overflow ? 1 : 0);
        final payload = Uint8List(length)..fillRange(0, length, 0x11);
        payload[0] = 0x7d;
        if (escapedLast) payload[length - 1] = 0x7e;
        final packets = _receive(
          codec,
          Uint8List.fromList([..._packet(2, payload), ..._packet(3, frame)]),
        );
        expect(packets.map((p) => p.command), [overflow ? -1 : 2, 3]);
        expect(packets.map((p) => p.error), [overflow ? 5 : 0, 0]);
        expect(packets.first.payloadBytes, 65535);
        expect(packets.first.rejectedBytes, overflow ? 65536 : 0);
        expect(packets.last.pcm, expected);
      }
    }
  });

  test('dangling escape at the packet limit is not reported as overflow', () {
    final payload = Uint8List(65535)..fillRange(0, 65535, 0x11);
    final prefix = _packet(2, payload);
    final frame = SbcEncoder().encode(_signal(128, 12), null, _frame())!;
    final packets = _receive(
      codec,
      Uint8List.fromList([
        ...prefix.take(prefix.length - 1),
        0x7d,
        0x7e,
        ..._packet(3, frame),
      ]),
    );
    expect(packets.map((p) => p.error), [6, 0]);
    expect(packets.first.command, -1);
    expect(packets.first.payloadBytes, 65535);
    expect(packets.first.rejectedBytes, 65535);
    expect(packets.last.pcm, SbcDecoder().decode(frame).pcmLeft);
  });

  test('coalesced end changes decode mask before next packet', () {
    final frame = _frame();
    final encoder = SbcEncoder();
    final a = encoder.encode(_signal(128, 1), null, frame)!;
    final b = encoder.encode(_signal(128, 2), null, frame)!;
    final decoder = SbcDecoder();
    final expectedA = decoder.decode(a).pcmLeft;
    final expectedB = decoder.decode(b).pcmLeft;
    int mask = 1 << 3;
    final packets = <ReceivedRadioAudio>[];
    codec.receive(
      Uint8List.fromList([
        ..._packet(3, a),
        ..._packet(9, a),
        ..._packet(1, [0]),
        ..._packet(9, b),
      ]),
      decodeMask: () => mask,
      onPacket: (packet) {
        packets.add(packet);
        if (packet.command == 1) mask = 1 << 9;
      },
    );
    expect(packets.map((p) => p.command), [3, 9, 1, 9]);
    expect(packets[0].pcm, expectedA);
    expect(packets[1].pcm, isEmpty);
    expect(packets[3].pcm, expectedB);
  });

  test(
    'valid decoded prefix survives invalid sync, header, CRC, and truncation',
    () {
      final valid = SbcEncoder().encode(_signal(128, 1), null, _frame())!;
      final expected = SbcDecoder().decode(valid).pcmLeft;
      final badCrc = Uint8List.fromList(valid)..[3] ^= 1;
      final badHeader = Uint8List.fromList(valid)..[2] = 255;
      for (final (tail, error) in [
        (Uint8List.fromList([0]), 1),
        (badHeader, 2),
        (Uint8List.sublistView(valid, 0, valid.length - 1), 3),
        (badCrc, 4),
      ]) {
        codec.resetReceiver();
        final result = _receive(codec, _packet(3, [...valid, ...tail])).single;
        expect(result.error, error);
        expect(result.pcm, expected);
        expect(result.decodedFrames, 1);
        expect(result.rejectedBytes, tail.length);
      }
    },
  );

  test('malformed escape and oversized packet report errors and recover', () {
    final frame = SbcEncoder().encode(_signal(128, 12), null, _frame())!;
    final packets = _receive(
      codec,
      Uint8List.fromList([
        0x7e,
        3,
        0x7d,
        0x7e,
        0x7e,
        3,
        ...List.filled(65536 + 32, 1),
        0x7e,
        ..._packet(3, frame),
      ]),
    );
    expect(packets.map((p) => p.error), [6, 5, 0]);
    expect(packets.take(2).map((p) => p.command), [-1, -1]);
    expect(packets.last.pcm, SbcDecoder().decode(frame).pcmLeft);
  });

  test(
    'parser-only reset preserves synthesis history, full reset clears it',
    () {
      final encoder = SbcEncoder();
      final frame = _frame();
      final a = encoder.encode(_signal(128, 3), null, frame)!;
      final b = encoder.encode(_signal(128, 4), null, frame)!;
      final reference = SbcDecoder()..decode(a);
      _receive(codec, _packet(3, a));
      _receive(codec, Uint8List.fromList([0x7e, 3, ...b.take(10)]));
      codec.resetReceiver(resetDecoder: false);
      expect(
        _receive(codec, _packet(3, b)).single.pcm,
        reference.decode(b).pcmLeft,
      );
      codec.resetReceiver();
      expect(
        _receive(codec, _packet(3, a)).single.pcm,
        SbcDecoder().decode(a).pcmLeft,
      );
    },
  );
}
