// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sstv/decoder.dart';
import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/native_demodulator.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';

final _pixels = Int32List.fromList(
  List.generate(
    35,
    (i) =>
        [
          0xff000000,
          0xffffffff,
          0xffff0000,
          0xff00ff00,
          0xff0000ff,
          0xff123456,
          0xffabcdef,
        ][i % 7] ^
        (i ~/ 7 * 0x00110307),
  ),
);

void _compareSamples(Float64List actual, Float64List expected) {
  expect(actual.length, expected.length);
  double error = 0;
  for (int i = 0; i < actual.length; i++) {
    error = math.max(error, (actual[i] - expected[i]).abs());
  }
  expect(error, lessThan(1e-9));
}

(Float64List, Uint8List) _encodeViewsInIsolate() {
  final encoder = Encoder(1000);
  final samples = encoder.encodeRobot36(_pixels, 7, 5);
  final pcm = encoder.encodePcm16(
    _pixels,
    7,
    5,
    'Robot 36 Color',
    silenceSamples: 3,
  );
  return (
    Float64List.sublistView(samples, 3, samples.length - 1),
    Uint8List.sublistView(pcm, 2, pcm.length - 2),
  );
}

void main() {
  test('native output views survive subsequent encoding and reset', () {
    final encoder = Encoder(1000);
    final samples = encoder.encodeRobot36(_pixels, 7, 5);
    final pcm = encoder.encodePcm16(_pixels, 7, 5, 'Robot 36 Color');
    final sampleView = Float64List.sublistView(samples, 3);
    final pcmView = Uint8List.sublistView(pcm, 2);
    final expectedSamples = Float64List.fromList(sampleView);
    final expectedPcm = Uint8List.fromList(pcmView);
    final changedPixels = Int32List.fromList(
      _pixels.map((pixel) => pixel ^ 0x00ffffff).toList(),
    );
    for (int i = 0; i < 4; i++) {
      encoder.reset();
      encoder.encodeRobot36(changedPixels, 7, 5);
      encoder.encodePcm16(changedPixels, 7, 5, 'Robot 36 Color');
    }
    expect(sampleView, expectedSamples);
    expect(pcmView, expectedPcm);
  }, skip: !nativeSstvSupported);

  test('native output views survive the encoding isolate exiting', () async {
    final (samples, pcm) = await Isolate.run(_encodeViewsInIsolate);
    final (expectedSamples, expectedPcm) = _encodeViewsInIsolate();
    expect(samples, expectedSamples);
    expect(pcm, expectedPcm);
  }, skip: !nativeSstvSupported);

  test('SIMD PCM handles bipolar rails and odd-length output tails', () {
    for (final rate in [7600, 44100]) {
      final samples = Encoder(rate, useSimd: true).encodeRobot36(_pixels, 7, 5);
      expect(samples.length.isOdd, rate == 44100);
      final pcm = Encoder(
        rate,
        useSimd: true,
      ).encodePcm16(_pixels, 7, 5, 'Robot 36 Color', silenceSamples: 3);
      expect(pcm.length, (samples.length + 3) * 2);
      expect(pcm.take(6), everyElement(0));
      final bytes = ByteData.sublistView(pcm);
      int error = 0, minimum = 0, maximum = 0;
      for (int i = 0; i < samples.length; i++) {
        final value = bytes.getInt16((i + 3) * 2, Endian.little);
        final expected = (samples[i].clamp(-1.0, 1.0) * 32767).round();
        error = math.max(error, (value - expected).abs());
        minimum = math.min(minimum, value);
        maximum = math.max(maximum, value);
      }
      expect(error, lessThanOrEqualTo(1));
      expect(minimum, -32767);
      expect(maximum, 32767);
    }
  });

  for (final simd in [false, true]) {
    group(simd ? 'SIMD encoder' : 'scalar encoder', () {
      for (final mode in Encoder.getSupportedModes()) {
        test('$mode matches every Dart waveform sample', () {
          final expected = Encoder(
            8000,
            useNative: false,
          ).encode(_pixels, 7, 5, mode);
          final actual = Encoder(
            8000,
            useSimd: simd,
          ).encode(_pixels, 7, 5, mode);
          _compareSamples(actual, expected);
        });
      }

      for (final (rate, mode) in [
        (11025, 'Robot 36 Color'),
        (32000, 'Wraase SC2\u2013180'),
        (44100, 'Martin 2'),
      ]) {
        test('$mode timing and PCM rounding at $rate Hz', () {
          final actual = Encoder(
            rate,
            useSimd: simd,
          ).encodePcm16(_pixels, 7, 5, mode, silenceSamples: 17);
          final expected = Encoder(
            rate,
            useNative: false,
          ).encodePcm16(_pixels, 7, 5, mode, silenceSamples: 17);
          expect(actual.length, expected.length);
          expect(actual.take(34), everyElement(0));
          final a = ByteData.sublistView(actual);
          final b = ByteData.sublistView(expected);
          int error = 0;
          for (int i = 34; i < actual.length; i += 2) {
            error = math.max(
              error,
              (a.getInt16(i, Endian.little) - b.getInt16(i, Endian.little))
                  .abs(),
            );
          }
          expect(error, lessThanOrEqualTo(1));
        });
      }

      test('phase survives mixed APIs, instance interleaving, and reset', () {
        final native = Encoder(8000, useSimd: simd);
        final reference = Encoder(8000, useNative: false);
        _compareSamples(
          native.encodeRobot36(_pixels, 7, 5),
          reference.encodeRobot36(_pixels, 7, 5),
        );
        native.encodePcm16(_pixels, 7, 5, 'Martin 2', silenceSamples: 13);
        reference.encodePcm16(_pixels, 7, 5, 'Martin 2', silenceSamples: 13);
        Encoder(8000).encodeScottie(_pixels, 7, 5, '2');
        _compareSamples(
          native.encodePaulDon(_pixels, 7, 5, '50'),
          reference.encodePaulDon(_pixels, 7, 5, '50'),
        );
        native.reset();
        reference.reset();
        _compareSamples(
          native.encodeWraaseSc2180(_pixels, 7, 5),
          reference.encodeWraaseSc2180(_pixels, 7, 5),
        );
      });
    });
  }

  for (final mode in ['Robot 36 Color', 'Martin 2', 'PD 50']) {
    test('$mode native PCM decodes into the reference image', () {
      const rate = 8000;
      final pcm = Encoder(rate).encodePcm16(_pixels, 7, 5, mode);
      final expected = Encoder(
        rate,
        useNative: false,
      ).encodePcm16(_pixels, 7, 5, mode);
      final actualImage = PixelBuffer(800, 616);
      final expectedImage = PixelBuffer(800, 616);
      final a = Decoder(PixelBuffer(800, 616), actualImage, 'Raw', rate);
      final b = Decoder(PixelBuffer(800, 616), expectedImage, 'Raw', rate);
      final bytes = ByteData.sublistView(pcm);
      final expectedBytes = ByteData.sublistView(expected);
      final sampleCount = expected.length ~/ 2;
      try {
        for (int offset = 0; offset < sampleCount + rate * 2; offset += 128) {
          final actualBlock = Float64List(128);
          final expectedBlock = Float64List(128);
          for (int i = 0; i < 128 && offset + i < sampleCount; i++) {
            actualBlock[i] =
                bytes.getInt16((offset + i) * 2, Endian.little) / 32768;
            expectedBlock[i] =
                expectedBytes.getInt16((offset + i) * 2, Endian.little) / 32768;
          }
          a.process(actualBlock, 0);
          b.process(expectedBlock, 0);
        }
        expect(a.currentMode.getName(), mode);
        expect(actualImage.line, a.currentMode.getHeight());
        expect(actualImage.line, expectedImage.line);
        expect(actualImage.width, expectedImage.width);
        expect(actualImage.height, expectedImage.height);
        int error = 0;
        for (int i = 0; i < actualImage.width * actualImage.height; i++) {
          for (final shift in [0, 8, 16]) {
            error = math.max(
              error,
              (((actualImage.pixels[i] >> shift) & 255) -
                      ((expectedImage.pixels[i] >> shift) & 255))
                  .abs(),
            );
          }
        }
        expect(error, lessThanOrEqualTo(1));
      } finally {
        a.dispose();
        b.dispose();
      }
    });
  }

  for (final native in [false, true]) {
    test('invalid input fails explicitly (native=$native)', () {
      expect(() => Encoder(0, useNative: native), throwsRangeError);
      final encoder = Encoder(8000, useNative: native);
      expect(
        () => encoder.encode(_pixels, 0, 5, 'Robot 36 Color'),
        throwsRangeError,
      );
      expect(
        () => encoder.encode(_pixels, 7, 6, 'Robot 36 Color'),
        throwsArgumentError,
      );
      expect(
        () => encoder.encodePcm16(_pixels, 7, 5, 'unknown'),
        throwsArgumentError,
      );
      expect(
        () => encoder.encodePcm16(_pixels, 7, 5, 'PD 50', silenceSamples: -1),
        throwsRangeError,
      );
      expect(
        () => encoder.encodePaulDon(_pixels, 7, 5, 'unknown'),
        throwsArgumentError,
      );
    });
  }

  test('low sample rates preserve rounding and scalar sine fallback', () {
    for (final rate in [1, 1000]) {
      _compareSamples(
        Encoder(rate).encodeRobot36(_pixels, 7, 5),
        Encoder(rate, useNative: false).encodeRobot36(_pixels, 7, 5),
      );
    }
  });
}
