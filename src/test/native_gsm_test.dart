// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/gsm/gsm_codec.dart';
import 'package:htcommander/gsm/native_gsm.dart';

Int16List _samples(int packet, Random random) => Int16List.fromList(
  List.generate(
    640,
    (i) => switch (packet % 8) {
      0 => 0,
      1 => 32767,
      2 => -32768,
      3 => i.isEven ? 32767 : -32768,
      4 => i == 0 ? 32767 : 0,
      5 => random.nextInt(7) - 3,
      6 => (sin((packet * 640 + i) * 0.17) * 24000).round(),
      _ => random.nextInt(65536) - 32768,
    },
  ),
);

void main() {
  for (final simd in [false, true]) {
    test(
      'native GSM simd=$simd preserves sparse frame boundaries and tails',
      () {
        final native = createNativeGsmEncoder(simd: simd)!;
        final reference = GsmEncoder();
        final silence = Int16List(640);
        final out = Uint8List(132);
        try {
          for (final index in [
            0,
            1,
            7,
            8,
            15,
            16,
            151,
            152,
            158,
            159,
            160,
            319,
            320,
            479,
            480,
            639,
          ]) {
            for (final amplitude in [-32768, -8, -1, 1, 7, 8, 32767]) {
              native.reset();
              reference.reset();
              final pcm = Int16List(640)..[index] = amplitude;
              native.encode(pcm, 0, out, 0);
              expect(
                out,
                reference.encode(pcm),
                reason: 'index $index, amplitude $amplitude',
              );
              for (var tail = 0; tail < 4; tail++) {
                native.encode(silence, 0, out, 0);
                expect(
                  out,
                  reference.encode(silence),
                  reason: 'tail $tail after $index/$amplitude',
                );
              }
              final next = Int16List(640)
                ..[639 - index] = amplitude == -32768 ? 32767 : -amplitude;
              native.encode(next, 0, out, 0);
              expect(
                out,
                reference.encode(next),
                reason: 'resuming after $index/$amplitude',
              );
            }
          }
        } finally {
          native.dispose();
        }
      },
      skip: !nativeGsmEnabled,
    );

    test('native GSM simd=$simd preserves silence and filter tails', () {
      final native = createNativeGsmEncoder(simd: simd)!;
      final reference = GsmEncoder();
      final random = Random(60610);
      final out = Uint8List(132);
      try {
        for (var p = 0; p < 80; p++) {
          final pcm = switch (p) {
            12 => _samples(4, random),
            >= 32 && < 36 => _samples(7, random),
            >= 56 && < 60 => _samples(5, random),
            _ => Int16List(640),
          };
          native.encode(pcm, 0, out, 0);
          expect(out, reference.encode(pcm), reason: 'packet $p');
        }
      } finally {
        native.dispose();
      }
    }, skip: !nativeGsmEnabled);

    test('native GSM simd=$simd matches Dart across streams and resets', () {
      final native = createNativeGsmEncoder(simd: simd)!;
      final receiver = createNativeGsmDecoder()!;
      final reference = GsmEncoder();
      final referenceReceiver = GsmDecoder();
      final random = Random(60610);
      try {
        for (var p = 0; p < 160; p++) {
          if (p % 31 == 0) {
            native.reset();
            receiver.reset();
            reference.reset();
            referenceReceiver.reset();
          }
          final pcm = _samples(p, random);
          final expected = reference.encode(pcm);
          final paddedPcm = Int16List(649)..setAll(5, pcm);
          final out = Uint8List(145)..fillRange(0, 145, 0xA5);
          native.encode(Int16List.sublistView(paddedPcm, 2), 3, out, 7);
          final frames = Uint8List.sublistView(out, 7, 139);
          expect(frames, expected, reason: 'encoded packet $p');
          expect(out.sublist(0, 7), everyElement(0xA5));
          expect(out.sublist(139), everyElement(0xA5));
          expect(paddedPcm.sublist(5, 645), pcm, reason: 'input is immutable');
          expect(
            receiver.decode(frames),
            referenceReceiver.decode(expected),
            reason: 'decoded packet $p',
          );
        }
      } finally {
        native.dispose();
        receiver.dispose();
      }
    }, skip: !nativeGsmEnabled);
  }

  test('native GSM encoder instances keep independent filter/SIMD state', () {
    final scalar = createNativeGsmEncoder(simd: false)!;
    final simd = createNativeGsmEncoder()!;
    final a = GsmEncoder();
    final b = GsmEncoder();
    final out = Uint8List(132);
    final random = Random(42);
    try {
      for (var p = 0; p < 20; p++) {
        final first = _samples(p, random), second = _samples(p + 3, random);
        scalar.encode(first, 0, out, 0);
        expect(out, a.encode(first));
        simd.encode(second, 0, out, 0);
        expect(out, b.encode(second));
      }
    } finally {
      scalar.dispose();
      simd.dispose();
    }
  }, skip: !nativeGsmEnabled);

  test('native GSM decoder preserves partial progress on malformed frames', () {
    final native = createNativeGsmDecoder()!;
    final reference = GsmDecoder();
    final random = Random(918);
    try {
      for (var invalid = 0; invalid < 4; invalid++) {
        native.reset();
        reference.reset();
        final frames = GsmEncoder().encode(_samples(7, random));
        frames[33 * invalid] = 0;
        final error = isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Invalid GSM frame magic at frame $invalid',
        );
        expect(() => native.decode(frames), throwsA(error));
        expect(() => reference.decode(frames), throwsA(error));
        for (var p = 0; p < 12; p++) {
          // Arbitrary frame parameters also exercise invalid pitch-lag fallback.
          final next = Uint8List.fromList(
            List.generate(132, (_) => random.nextInt(256)),
          );
          for (var f = 0; f < 4; f++) {
            next[f * 33] = (next[f * 33] & 15) | 0xD0;
          }
          expect(native.decode(next), reference.decode(next));
        }
      }
    } finally {
      native.dispose();
    }
  }, skip: !nativeGsmEnabled);

  test(
    'native GSM validates buffers before consuming state and owns results',
    () {
      final encoder = createNativeGsmEncoder()!;
      final decoder = createNativeGsmDecoder()!;
      final pcm = _samples(7, Random(5));
      final frames = Uint8List(132);
      try {
        expect(() => encoder.encode(pcm, -1, frames, 0), throwsRangeError);
        expect(() => encoder.encode(pcm, 1, frames, 0), throwsRangeError);
        expect(() => encoder.encode(pcm, 0, frames, -1), throwsRangeError);
        expect(() => encoder.encode(pcm, 0, frames, 1), throwsRangeError);
        expect(() => decoder.decode(Uint8List(131)), throwsArgumentError);
        expect(() => decoder.decode(Uint8List(133)), throwsArgumentError);
        encoder.encode(pcm, 0, frames, 0);
        expect(frames, GsmEncoder().encode(pcm));
        final result = decoder.decode(frames);
        final saved = Int16List.fromList(result);
        expect(result, GsmDecoder().decode(frames));
        decoder.decode(frames);
        decoder.reset();
        decoder.dispose();
        expect(result, saved, reason: 'PCM must not alias native storage');
      } finally {
        encoder.dispose();
        decoder.dispose();
      }
      encoder.dispose();
      decoder.dispose();
      expect(() => encoder.encode(pcm, 0, frames, 0), throwsStateError);
      expect(encoder.reset, throwsStateError);
      expect(() => decoder.decode(frames), throwsStateError);
      expect(decoder.reset, throwsStateError);
    },
    skip: !nativeGsmEnabled,
  );
}
