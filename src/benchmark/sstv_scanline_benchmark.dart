// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/sstv/base_mode.dart';
import 'package:htcommander/sstv/hf_fax.dart';
import 'package:htcommander/sstv/native_scanline.dart';
import 'package:htcommander/sstv/pauldon.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';
import 'package:htcommander/sstv/raw_decoder.dart';
import 'package:htcommander/sstv/rgb_modes.dart';
import 'package:htcommander/sstv/robot_36_color.dart';
import 'package:htcommander/sstv/robot_72_color.dart';

void main() {
  if (!nativeSstvScanLineSupported) {
    throw UnsupportedError('Native SSTV scanlines unavailable');
  }
  const rate = 32000;
  final factories = <String, BaseMode Function(bool)>{
    'Martin 1': (n) => RGBModes.martin('1', 44, 0.146432, rate, useNative: n),
    'Scottie DX': (n) => RGBModes.scottie('DX', 76, 0.3456, rate, useNative: n),
    'Robot36': (n) => Robot_36_Color(rate, useNative: n),
    'Robot72': (n) => Robot_72_Color(rate, useNative: n),
    'PD290': (n) => PaulDon('290', 94, 800, 616, 0.2288, rate, useNative: n),
    'HF Fax': (n) => HFFax(rate, useNative: n),
    'Raw': (n) => RawDecoder('Raw', rate, useNative: n),
  };
  final input = Float64List(rate * 3);
  for (int i = 0; i < input.length; ++i) {
    input[i] = math.sin(i * 0.031) + 0.13 * math.cos(i * 0.007);
  }
  stdout.writeln(
    'Scanline filtering + sampling/color, $rate Hz; '
    'includes FFI copies, excludes demodulation',
  );
  for (final entry in factories.entries) {
    double? dartTime;
    Int32List? expectedPixels;
    Float64List? expectedScratch;
    for (final native in [false, true]) {
      final mode = entry.value(native);
      final pixels = PixelBuffer(800, 2);
      final scratch = Float64List(rate * 2);
      final times = <int>[];
      final samples = mode.getScanLineSamples() > 0
          ? mode.getScanLineSamples()
          : rate ~/ 4;
      try {
        for (int run = 0; run < 6; ++run) {
          mode.resetState();
          pixels.pixels.fillRange(0, pixels.pixels.length, 0);
          final timer = Stopwatch()..start();
          for (int line = 0; line < 1000; ++line) {
            mode.decodeScanLine(
              pixels,
              scratch,
              input,
              800,
              rate + 13,
              samples,
              0.03,
            );
          }
          timer.stop();
          if (run > 0) times.add(timer.elapsedMicroseconds);
        }
        if (!native) {
          expectedPixels = Int32List.fromList(pixels.pixels);
          expectedScratch = Float64List.fromList(scratch);
        } else {
          for (int i = 0; i < pixels.pixels.length; ++i) {
            if (pixels.pixels[i] != expectedPixels![i]) {
              throw StateError('${entry.key} pixel parity at $i');
            }
          }
          for (int i = 0; i < scratch.length; ++i) {
            if (scratch[i] != expectedScratch![i]) {
              throw StateError('${entry.key} scratch parity at $i');
            }
          }
        }
        times.sort();
        final micros = times[times.length ~/ 2] / 1000;
        if (!native) dartTime = micros;
        stdout.writeln(
          '${entry.key} ${native ? "Native" : "Dart"}: '
          '${micros.toStringAsFixed(2)} us/line'
          '${native ? ", ${(dartTime! / micros).toStringAsFixed(2)}x speedup" : ""}',
        );
      } finally {
        mode.dispose();
      }
    }
  }
}
