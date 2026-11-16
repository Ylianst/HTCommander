// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sstv/base_mode.dart';
import 'package:htcommander/sstv/decoder.dart';
import 'package:htcommander/sstv/hf_fax.dart';
import 'package:htcommander/sstv/native_scanline.dart';
import 'package:htcommander/sstv/pauldon.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';
import 'package:htcommander/sstv/raw_decoder.dart';
import 'package:htcommander/sstv/rgb_modes.dart';
import 'package:htcommander/sstv/robot_36_color.dart';
import 'package:htcommander/sstv/robot_72_color.dart';
import 'package:htcommander/sstv/sstv_round.dart';

typedef _Factory = BaseMode Function(int rate, bool native);

final _factories = <String, _Factory>{
  'Martin 1': (r, n) => RGBModes.martin('1', 44, 0.146432, r, useNative: n),
  'Martin 2': (r, n) => RGBModes.martin('2', 40, 0.073216, r, useNative: n),
  'Scottie 1': (r, n) => RGBModes.scottie('1', 60, 0.138240, r, useNative: n),
  'Scottie 2': (r, n) => RGBModes.scottie('2', 56, 0.088064, r, useNative: n),
  'Scottie DX': (r, n) => RGBModes.scottie('DX', 76, 0.3456, r, useNative: n),
  'Wraase': (r, n) => RGBModes.wraaseSc2180(r, useNative: n),
  'Robot36': (r, n) => Robot_36_Color(r, useNative: n),
  'Robot72': (r, n) => Robot_72_Color(r, useNative: n),
  for (final (name, code, width, height, seconds) in [
    ('50', 93, 320, 256, 0.09152),
    ('90', 99, 320, 256, 0.17024),
    ('120', 95, 640, 496, 0.1216),
    ('160', 98, 512, 400, 0.195584),
    ('180', 96, 640, 496, 0.18304),
    ('240', 97, 640, 496, 0.24448),
    ('290', 94, 800, 616, 0.2288),
  ])
    'PD $name': (r, n) =>
        PaulDon(name, code, width, height, seconds, r, useNative: n),
  'HF Fax': (r, n) => HFFax(r, useNative: n),
  'Raw': (r, n) => RawDecoder('Raw', r, useNative: n),
};

void main() {
  for (final entry in _factories.entries) {
    for (final rate in [8000, 11025, 32000]) {
      test('${entry.key}: pixels, scratch, offsets and state at $rate Hz', () {
        final native = entry.value(rate, true);
        final reference = entry.value(rate, false);
        final actual = PixelBuffer(800, 2);
        final expected = PixelBuffer(800, 2);
        actual.pixels.fillRange(0, actual.pixels.length, 0x12345678);
        expected.pixels.setAll(0, actual.pixels);
        final scratch = Float64List(rate * 2)..fillRange(0, rate * 2, -123);
        final referenceScratch = Float64List.fromList(scratch);
        final input = Float64List(rate * 3);
        final random = math.Random(73);
        try {
          expect(reference.usingNativeScanLine, isFalse);
          expect(native.usingNativeScanLine, nativeSstvScanLineSupported);
          // Invalid leading ranges must not mutate pixels, scratch or state.
          expect(
            native.decodeScanLine(
              actual,
              scratch,
              input,
              800,
              -rate * 2,
              rate ~/ 2,
              0,
            ),
            isFalse,
          );
          expect(scratch, orderedEquals(referenceScratch));
          expect(actual.pixels, orderedEquals(expected.pixels));
          for (int line = 0; line < 9; ++line) {
            if (line == 5) {
              native.resetState();
              reference.resetState();
            }
            final offset = [0.0, -0.17, 0.23][line % 3];
            // Scottie includes channels before sync. Other modes also exercise
            // a legal negative sync index ending exactly at their first pixel.
            final sync = line.isEven && native.getFirstPixelSampleIndex() > 0
                ? -native.getFirstPixelSampleIndex()
                : rate + 13;
            final samples = entry.key == 'Raw'
                ? [rate ~/ 10, rate * 3 ~/ 20, rate ~/ 4][line % 3]
                : native.getScanLineSamples();
            for (int i = 0; i < input.length; ++i) {
              input[i] =
                  1.7 * math.sin(i * 0.019 + line) +
                  0.04 * (random.nextDouble() - 0.5) +
                  offset;
            }
            if (entry.key == 'Robot36') {
              // Explicit parity, repeated parity, then ambiguous separator:
              // all must keep the original alternating-chroma behavior.
              final separator = [
                -1.0,
                1.0,
                0.0,
                -1.0,
                -1.0,
                0.0,
                1.0,
                0.0,
                0.0,
              ][line];
              final start = sync + sstvRound((0.003 + 0.088) * rate);
              input.fillRange(
                start,
                start + sstvRound(0.0045 * rate),
                separator + offset,
              );
            }
            final original = Float64List.fromList(input);
            expect(
              native.decodeScanLine(
                actual,
                scratch,
                input,
                800,
                sync,
                samples,
                offset,
              ),
              reference.decodeScanLine(
                expected,
                referenceScratch,
                input,
                800,
                sync,
                samples,
                offset,
              ),
              reason: 'return line $line',
            );
            expect(actual.width, expected.width);
            expect(actual.height, expected.height);
            expect(actual.line, expected.line);
            expect(
              actual.pixels,
              orderedEquals(expected.pixels),
              reason: 'pixels line $line',
            );
            expect(
              scratch,
              orderedEquals(referenceScratch),
              reason: 'scratch line $line',
            );
            expect(input, orderedEquals(original));
            if (entry.key == 'HF Fax') {
              expect(
                native.postProcessScopeImage(actual.pixels, actual.width, 1),
                orderedEquals(
                  reference.postProcessScopeImage(
                    expected.pixels,
                    expected.width,
                    1,
                  ),
                ),
              );
            }
          }
          expect(
            native.decodeScanLine(
              actual,
              scratch,
              input,
              800,
              input.length,
              rate,
              0,
            ),
            isFalse,
          );
        } finally {
          native.dispose();
          reference.dispose();
          native.dispose();
        }
      });
    }
  }

  test('Decoder propagates reference choice to every scanline constructor', () {
    final decoder = Decoder(
      null,
      PixelBuffer(0, 0),
      'Raw',
      8000,
      useNative: false,
    );
    try {
      for (final name in [
        'Raw',
        'HF Fax',
        'Robot 36 Color',
        'Robot 72 Color',
        'Martin 1',
        'Martin 2',
        'Scottie 1',
        'Scottie 2',
        'Scottie DX',
        'Wraase SC2\u2013180',
        for (final pd in ['50', '90', '120', '160', '180', '240', '290'])
          'PD $pd',
      ]) {
        decoder.setMode(name);
        expect(decoder.currentMode.getName(), name);
        expect((decoder.currentMode as BaseMode).usingNativeScanLine, isFalse);
      }
    } finally {
      decoder.dispose();
    }
  });

  test(
    'Native config validation rejects stale, nonpositive and narrowed values',
    () {
      if (!nativeSstvScanLineSupported) return;
      final native = createNativeSstvScanLine()!;
      final input = Float64List.fromList([-2, 0, 2]);
      final scratch = Float64List(3);
      final pixels = Int32List(3);
      final config = [5, 3, 3, 0, 0, 0, 0, 3, 0, 0, 0];
      try {
        native.process(input, 0, scratch, 0, pixels, config, 1, 0);
        final expectedScratch = Float64List.fromList(scratch);
        final expectedPixels = Int32List.fromList(pixels);
        for (final invalid in [
          <int>[],
          config.sublist(0, 3),
          config.sublist(0, 10),
          [...config, 0],
        ]) {
          expect(
            () => native.process(input, 0, scratch, 0, pixels, invalid, 1, 0),
            throwsArgumentError,
          );
        }
        for (final (index, value) in [
          (0, -1),
          (0, 6),
          (1, 0),
          (1, -1),
          (2, 0),
          (2, -1),
          (1, 0x100000003),
          (2, 0x100000003),
          (7, 0x100000003),
          (10, -0x80000001),
        ]) {
          final invalid = List<int>.from(config)..[index] = value;
          expect(
            () => native.process(input, 0, scratch, 0, pixels, invalid, 1, 0),
            throwsRangeError,
          );
        }
        expect(scratch, orderedEquals(expectedScratch));
        expect(pixels, orderedEquals(expectedPixels));
        native.process(input, 0, scratch, 0, pixels, config, 1, 0);
        expect(pixels, orderedEquals(expectedPixels));
      } finally {
        native.dispose();
      }
    },
  );

  test(
    'Native rejects finite inputs whose intermediate filter levels overflow',
    () {
      if (!nativeSstvScanLineSupported) return;
      final native = createNativeSstvScanLine()!;
      final scratch = Float64List.fromList([42, 42]);
      final pixels = Int32List.fromList([42, 42]);
      final config = [5, 2, 2, 0, 0, 0, 0, 2, 0, 0, 0];
      try {
        for (final (values, alpha, offset) in [
          ([double.maxFinite, 0.0], 2.0, 0.0),
          ([double.maxFinite / 4, 0.0], 2.0, 0.0),
          ([1.0, 0.0], double.maxFinite, 0.0),
          ([double.maxFinite, double.maxFinite], 1.0, -double.maxFinite),
          ([1e200, 1e200], 1e100, 0.0),
        ]) {
          expect(
            () => native.process(
              Float64List.fromList(values),
              0,
              scratch,
              0,
              pixels,
              config,
              alpha,
              offset,
            ),
            throwsStateError,
          );
          expect(scratch, orderedEquals([42.0, 42.0]));
          expect(pixels, orderedEquals([42, 42]));
        }
      } finally {
        native.dispose();
      }
    },
  );

  test(
    'Native errors surface and disposal invalidates the reusable buffer',
    () {
      if (!nativeSstvScanLineSupported) return;
      final native = createNativeSstvScanLine()!;
      final input = Float64List.fromList([-2, 0, 2]);
      final scratch = Float64List(3);
      final pixels = Int32List(3);
      final config = [5, 3, 3, 0, 0, 0, 0, 3, 0, 0, 0];
      try {
        native.process(input, 0, scratch, 0, pixels, config, 1, 0);
        expect(
          pixels,
          orderedEquals(
            Int32List.fromList([0xff000000, 0xffb4b4b4, 0xffffffff]),
          ),
        );
        input[1] = double.nan;
        expect(
          () => native.process(input, 0, scratch, 0, pixels, config, 1, 0),
          throwsStateError,
        );
        config[3] = 100;
        expect(
          () => native.process(input, 0, scratch, 0, pixels, config, 1, 0),
          throwsStateError,
        );
      } finally {
        native.dispose();
      }
      expect(
        () => native.process(input, 0, scratch, 0, pixels, config, 1, 0),
        throwsStateError,
      );
    },
  );
}
