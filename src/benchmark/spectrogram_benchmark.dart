// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:htcommander/widgets/spectrogram/spectrogram_colormap.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_generator.dart';

void main() {
  const rate = 32000, block = 1600, frames = 100;
  final pcm = Uint8List(rate * 2 * 5);
  final data = ByteData.sublistView(pcm);
  for (int i = 0; i < pcm.length ~/ 2; i++) {
    data.setInt16(
      i * 2,
      (15000 * math.sin(2 * math.pi * 710 * i / rate) +
              5000 * math.sin(2 * math.pi * 2130 * i / rate))
          .round(),
      Endian.little,
    );
  }
  Uint8List? reference;
  for (final native in [false, true]) {
    final times = <int>[];
    for (int run = 0; run < 6; run++) {
      final generator = SpectrogramGenerator(useNative: native)
        ..setFixedWidth(480);
      final pixels = Uint8List(480 * generator.height * 4);
      final timer = Stopwatch()..start();
      try {
        for (int frame = 0; frame < frames; frame++) {
          generator.addPcm16(pcm, frame * block * 2, block * 2);
          final count = generator.fftsToProcess;
          generator.process();
          generator.renderInto(
            pixels,
            colormap: SpectrogramColormap.viridis,
            intensity: 5,
            decibel: true,
            newColumnCount: frame == 0 ? null : count,
          );
        }
        timer.stop();
        if (reference == null) {
          reference = Uint8List.fromList(pixels);
        } else {
          for (int i = 0; i < pixels.length; i++) {
            if (pixels[i] != reference[i]) {
              throw StateError('Spectrogram parity mismatch at pixel byte $i');
            }
          }
        }
        if (run > 0) times.add(timer.elapsedMicroseconds);
      } finally {
        generator.dispose();
      }
    }
    times.sort();
    stdout.writeln(
      '${native ? "Native" : "Dart"}: '
      '${(times[times.length ~/ 2] / 1000).toStringAsFixed(3)} ms '
      'median for 5 s audio, $frames renders; exact final RGBA parity',
    );
  }
}
