// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sstv/decoder.dart';
import 'package:htcommander/sstv/demodulator.dart';
import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/native_demodulator.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';
import 'package:htcommander/sstv/sstv_monitor.dart';

Float64List _tones(int rate, int channel) {
  final channels = channel == 0 ? 1 : 2;
  final values = <double>[];
  double phase = 0;
  final noise = math.Random(42);
  for (final (frequency, seconds) in [
    (1900.0, 0.02),
    (1200.0, 0.005),
    (2300.0, 0.02),
    (1225.0, 0.009),
    (1500.0, 0.02),
    (1165.0, 0.020),
    (1900.0, 0.02),
    (1200.0, 0.030),
    (1900.0, 0.02),
    (0.0, 0.01),
  ]) {
    for (int i = 0; i < (seconds * rate).round(); i++) {
      phase += 2 * math.pi * frequency / rate;
      final real = frequency == 0
          ? 0.0
          : 0.7 * math.cos(phase) + 0.002 * (noise.nextDouble() - 0.5);
      if (channels == 1) {
        values.add(real);
      } else {
        values.addAll([
          channel == 2 ? 0.0 : real,
          channel == 1 ? 0.0 : (channel == 4 ? math.sin(phase) * 0.7 : real),
        ]);
      }
    }
  }
  return Float64List.fromList(values);
}

void main() {
  for (final useNative in [false, true]) {
    test(
      'PCM16 input preserves streaming DSP and complete image ($useNative)',
      () {
        const rate = 8000;
        final audio = Encoder(rate, useNative: false).encodeRobot36(
          Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
          2,
          2,
        );
        final image = PixelBuffer(0, 0);
        final expectedImage = PixelBuffer(0, 0);
        final decoder = Decoder(null, image, 'Raw', rate, useNative: useNative);
        final reference = Decoder(
          null,
          expectedImage,
          'Raw',
          rate,
          useNative: false,
        );
        try {
          for (
            int offset = 0;
            offset < audio.length + rate * 2;
            offset += 128
          ) {
            final bytes = Uint8List(259);
            final data = ByteData.sublistView(bytes);
            final samples = Float64List(128);
            for (int i = 0; i < 128; ++i) {
              final raw = offset + i < audio.length
                  ? (audio[offset + i] * 32768).round().clamp(-32768, 32767)
                  : 0;
              data.setInt16(1 + i * 2, raw, Endian.little);
              samples[i] = raw / 32768.0;
            }
            final original = Uint8List.fromList(bytes);
            expect(
              decoder.processPcm16(bytes, 1, 257),
              reference.process(samples, 0),
            );
            expect(bytes, original);
            expect(image.line, expectedImage.line);
          }
          expect(image.line, 240);
          expect(image.pixels, orderedEquals(expectedImage.pixels));
        } finally {
          decoder.dispose();
          reference.dispose();
        }
      },
    );
  }

  for (final (name, packets, channels) in [
    ('exact capacity', [8000 * 7 - 1, 1], 1),
    ('crossing capacity', [8000 * 7 - 17, 128], 2),
    ('multiple shifts', [8000 * 14 + 37], 1),
  ]) {
    test('sample buffering preserves image after $name', () {
      const rate = 8000;
      final audio = Encoder(rate).encodeRobot36(
        Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
        2,
        2,
      );
      final image = PixelBuffer(0, 0);
      final expectedImage = PixelBuffer(0, 0);
      final decoder = Decoder(null, image, 'Raw', rate);
      final reference = Decoder(
        null,
        expectedImage,
        'Raw',
        rate,
        useNative: false,
      );
      try {
        for (final count in packets) {
          decoder.process(Float64List(count * channels), channels - 1);
          for (int offset = 0; offset < count; offset += 128) {
            reference.process(Float64List(math.min(128, count - offset)), 0);
          }
        }
        for (int offset = 0; offset < audio.length + rate * 2; offset += 128) {
          final block = Float64List(128 * channels);
          final expected = Float64List(128);
          for (int i = 0; i < 128 && offset + i < audio.length; i++) {
            block[i * channels] = expected[i] = audio[offset + i];
          }
          decoder.process(block, channels - 1);
          reference.process(expected, 0);
          expect(image.line, expectedImage.line);
        }
        expect(image.line, 240);
        expect(image.width, 320);
        expect(image.height, 240);
        expect(image.pixels, orderedEquals(expectedImage.pixels));
      } finally {
        decoder.dispose();
        reference.dispose();
      }
    });
  }

  if (!nativeSstvSupported) {
    test('unsupported platforms use the Dart demodulator', () {
      final decoder = Demodulator(32000);
      final reference = Demodulator(32000, useNative: false);
      try {
        final actual = _tones(32000, 0);
        final expected = Float64List.fromList(actual);
        expect(decoder.process(actual, 0), reference.process(expected, 0));
        expect(actual, orderedEquals(expected));
        expect(decoder.syncPulseWidthValue, reference.syncPulseWidthValue);
        expect(decoder.syncPulseOffset, reference.syncPulseOffset);
        expect(decoder.frequencyOffset, reference.frequencyOffset);
      } finally {
        decoder.dispose();
        reference.dispose();
      }
    });
    return;
  }
  for (final useSimd in [false, true]) {
    group(useSimd ? 'native SIMD' : 'native scalar', () {
      test(
        'direct PCM handles offsets, buffer growth, and mixed float input',
        () {
          for (final rate in [8000, 32000, 48000]) {
            final native = Demodulator(rate, useSimd: useSimd);
            final reference = Demodulator(rate, useNative: false);
            final signal = _tones(rate, 0);
            try {
              int block = 0;
              for (int offset = 0; offset < signal.length;) {
                final count = math.min(
                  [1, 7, 511, 3, 4097][block++ % 5],
                  signal.length - offset,
                );
                final bytes = Uint8List(count * 2 + 3);
                final data = ByteData.sublistView(bytes);
                final expected = Float64List(count);
                for (int i = 0; i < count; ++i) {
                  final raw = (signal[offset + i] * 32768).round().clamp(
                    -32768,
                    32767,
                  );
                  data.setInt16(1 + i * 2, raw, Endian.little);
                  expected[i] = raw / 32768.0;
                }
                final original = Uint8List.fromList(bytes);
                final (actual, detected) = block.isEven
                    ? native.processPcm16(bytes, 1, count * 2 + 1)
                    : (() {
                        final floats = Float64List.fromList(expected);
                        return (floats, native.process(floats, 0));
                      })();
                expect(detected, reference.process(expected, 0));
                expect(actual.length, count);
                for (int i = 0; i < count; ++i) {
                  expect(actual[i], closeTo(expected[i], 1e-10));
                }
                expect(bytes, original);
                expect(
                  native.syncPulseWidthValue,
                  reference.syncPulseWidthValue,
                );
                expect(native.syncPulseOffset, reference.syncPulseOffset);
                expect(
                  native.frequencyOffset,
                  closeTo(reference.frequencyOffset, 1e-10),
                );
                offset += count;
              }
              expect(native.processPcm16(Uint8List(1), 0, 1).$1, isEmpty);
              expect(
                () => native.processPcm16(Uint8List(2), 1, 2),
                throwsRangeError,
              );
            } finally {
              native.dispose();
              reference.dispose();
            }
            expect(
              () => native.processPcm16(Uint8List(2), 0, 2),
              throwsStateError,
            );
          }
        },
      );

      for (final rate in [8000, 11025, 16000, 32000, 44100, 48000]) {
        test('streaming demodulation matches Dart at $rate Hz', () {
          expect(nativeSstvSupported, isTrue);
          for (int channel = 0; channel <= 4; channel++) {
            final native = Demodulator(rate, useSimd: useSimd);
            final reference = Demodulator(rate, useNative: false);
            try {
              final signal = _tones(rate, channel);
              final channels = channel == 0 ? 1 : 2;
              final widths = <SyncPulseWidth>{};
              int block = 0;
              for (int offset = 0; offset < signal.length;) {
                final count = [1, 7, 128, 511][block++ % 4] * channels;
                final end = math.min(offset + count, signal.length);
                final actual = Float64List.fromList(
                  signal.sublist(offset, end),
                );
                final expected = Float64List.fromList(actual);
                final detected = native.process(actual, channel);
                expect(detected, reference.process(expected, channel));
                expect(
                  native.syncPulseWidthValue,
                  reference.syncPulseWidthValue,
                );
                expect(native.syncPulseOffset, reference.syncPulseOffset);
                expect(
                  native.frequencyOffset,
                  closeTo(reference.frequencyOffset, 1e-10),
                );
                double error = 0;
                for (int i = 0; i < actual.length; i++) {
                  error = math.max(error, (actual[i] - expected[i]).abs());
                }
                expect(
                  error,
                  lessThan(1e-10),
                  reason: 'channel $channel at $offset',
                );
                if (detected) widths.add(native.syncPulseWidthValue);
                offset = end;
              }
              expect(
                widths,
                containsAll([
                  SyncPulseWidth.nineMilliSeconds,
                  SyncPulseWidth.twentyMilliSeconds,
                  if (rate >= 16000) SyncPulseWidth.fiveMilliSeconds,
                ]),
              );
              expect(native.process(Float64List(0), channel), isFalse);
            } finally {
              native.dispose();
              reference.dispose();
            }
          }
        });
      }

      for (final mode in ['Robot 36 Color', 'Martin 2', 'PD 50']) {
        test('$mode produces the same complete image as Dart', () {
          const rate = 8000;
          final pixels = Int32List.fromList([
            0xffff0000,
            0xff00ff00,
            0xff0000ff,
            0xff808080,
            0xff000000,
            0xffffffff,
            0xffffff00,
            0xff00ffff,
          ]);
          final audio = Encoder(
            rate,
            useNative: false,
          ).encode(pixels, 4, 2, mode);
          final actualImage = PixelBuffer(800, 616);
          final expectedImage = PixelBuffer(800, 616);
          final actualScope = PixelBuffer(800, 616);
          final expectedScope = PixelBuffer(800, 616);
          final actual = Decoder(
            actualScope,
            actualImage,
            'Raw',
            rate,
            useSimd: useSimd,
          );
          final expected = Decoder(
            expectedScope,
            expectedImage,
            'Raw',
            rate,
            useNative: false,
          );
          try {
            for (
              int offset = 0;
              offset < audio.length + rate * 2;
              offset += 128
            ) {
              final block = offset < audio.length
                  ? Float64List.fromList(
                      audio.sublist(
                        offset,
                        math.min(offset + 128, audio.length),
                      ),
                    )
                  : Float64List(128);
              final reference = Float64List.fromList(block);
              expect(actual.process(block, 0), expected.process(reference, 0));
              expect(
                actual.currentMode.getName(),
                expected.currentMode.getName(),
              );
              expect(actualImage.line, expectedImage.line);
            }
            expect(actual.currentMode.getName(), mode);
            expect(actualImage.line, actual.currentMode.getHeight());
            expect(actualImage.width, expectedImage.width);
            expect(actualImage.height, expectedImage.height);
            expect(actualImage.pixels, orderedEquals(expectedImage.pixels));
            expect(actualScope.pixels, orderedEquals(expectedScope.pixels));
            expect(
              actualImage.pixels.take(actualImage.width).toSet().length,
              greaterThan(1),
            );
          } finally {
            actual.dispose();
            expected.dispose();
          }
        });
      }
    });
  }

  test('native lifetime handles independent states, growth, and disposal', () {
    final first = Demodulator(32000);
    final second = Demodulator(32000);
    final signal = _tones(32000, 0);
    final small = Float64List.fromList(signal.sublist(0, 3));
    first.process(small, 0);
    final rest = Float64List.fromList(signal.sublist(3));
    first.process(rest, 0);
    final whole = Float64List.fromList(signal);
    second.process(whole, 0);
    expect(small, orderedEquals(whole.take(3)));
    expect(rest, orderedEquals(whole.skip(3)));
    first.dispose();
    first.dispose();
    expect(() => first.process(Float64List(1), 0), throwsStateError);
    second.process(Float64List(128), 0);
    second.dispose();
  });

  test(
    'monitor reset and completion preserve events and release decoders',
    () async {
      const rate = 8000;
      final monitor = SstvMonitor(sampleRate: rate);
      final started = <SstvDecodingStarted>[];
      final progress = <SstvDecodingProgress>[];
      final complete = <SstvDecodingComplete>[];
      monitor.onDecodingStarted.listen(started.add);
      monitor.onDecodingProgress.listen(progress.add);
      monitor.onDecodingComplete.listen(complete.add);
      final audio = Encoder(
        rate,
        useNative: false,
      ).encodeRobot36(Int32List.fromList([0xff808080]), 1, 1);
      try {
        monitor.processFloatSamples(
          Float64List.fromList(audio.sublist(0, 256)),
        );
        monitor.reset();
        for (int pass = 0; pass < 2; pass++) {
          for (
            int offset = 0;
            offset < audio.length + rate * 2;
            offset += 128
          ) {
            monitor.processFloatSamples(
              offset < audio.length
                  ? Float64List.fromList(
                      audio.sublist(
                        offset,
                        math.min(offset + 128, audio.length),
                      ),
                    )
                  : Float64List(128),
            );
          }
        }
        await Future<void>.delayed(Duration.zero);
        expect(started.length, 2);
        expect(progress, isNotEmpty);
        expect(complete.length, 2);
        expect(complete.first.modeName, 'Robot 36 Color');
        expect(complete.first.image?.width, 320);
        expect(complete.first.image?.height, 240);
        expect(complete.first.image?.pixels, complete.last.image?.pixels);
      } finally {
        monitor.dispose();
        monitor.dispose();
      }
      monitor.reset();
      monitor.processFloatSamples(Float64List(128));
    },
  );
}
