// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/radio/cw_decoder.dart';
import 'package:htcommander/radio/native_cw.dart';

void main() {
  stdout.writeln(
    nativeCwEnabled
        ? 'CW Dart/native benchmark (correctness checked before reporting)'
        : 'CW Dart benchmark (native unavailable or HT_CW_DART=true)',
  );
  const rate = 32000;
  const unit = rate * 80 ~/ 1000;
  const segments = [
    1,
    -1,
    1,
    -1,
    1,
    -3,
    3,
    -1,
    3,
    -1,
    3,
    -3,
    1,
    -1,
    1,
    -1,
    1,
    -25,
  ];
  final keyed = Float64List(
    segments.fold<int>(0, (sum, n) => sum + n.abs()) * unit * 3,
  );
  int position = 0;
  for (int repeat = 0; repeat < 3; repeat++) {
    for (final segment in segments) {
      for (int i = 0; i < segment.abs() * unit; i++) {
        if (segment > 0) {
          keyed[position] = 0.5 * math.sin(2 * math.pi * 700 * position / rate);
        }
        position++;
      }
    }
  }
  final random = math.Random(7);
  final noise = Float64List(keyed.length);
  for (int i = 0; i < noise.length; i++) {
    noise[i] = (random.nextDouble() * 2 - 1) * 0.3;
  }

  for (final entry in {
    'keyed 700 Hz': keyed,
    'noise': noise,
    'silence': Float64List(keyed.length),
  }.entries) {
    final samples = entry.value;
    final pcm = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final value = (samples[i] * 32767).round();
      pcm[i * 2] = value & 0xff;
      pcm[i * 2 + 1] = (value >> 8) & 0xff;
    }
    String? referenceSignature;
    for (final chunk in [640, 2048, 65536]) {
      for (final useNative in [false, if (nativeCwEnabled) true]) {
        final times = <int>[];
        for (int run = 0; run < 7; run++) {
          final decoded = <(String, int)>[];
          final decoder = CwDecoder(
            useNative: useNative,
            onDecoded: (text, wpm) => decoded.add((text, wpm)),
          );
          try {
            if (decoder.usingNative != useNative) {
              throw StateError('Requested CW backend was not selected');
            }
            final timer = Stopwatch()..start();
            for (int offset = 0; offset < pcm.length; offset += chunk * 2) {
              decoder.processPcm16(
                pcm,
                offset,
                math.min(chunk * 2, pcm.length - offset),
              );
            }
            decoder.flush();
            timer.stop();
            final expected = entry.key == 'keyed 700 Hz' ? 'SOS SOS SOS' : '';
            if (decoded.map((result) => result.$1).join(' ') != expected) {
              throw StateError(
                '${entry.key}: unexpected decoded text $decoded',
              );
            }
            final signature = '$decoded/${decoder.lastToneHz}';
            referenceSignature ??= signature;
            if (signature != referenceSignature) {
              throw StateError(
                '${entry.key}: text/WPM/tone or chunk parity failed: '
                '$signature != $referenceSignature',
              );
            }
            if (run >= 2) times.add(timer.elapsedMicroseconds);
          } finally {
            decoder.dispose();
          }
        }
        times.sort();
        final ms = times[times.length ~/ 2] / 1000;
        final audioSeconds = samples.length / rate;
        stdout.writeln(
          '${useNative ? 'native' : 'Dart reference'}: '
          '${entry.key}, $chunk samples/block, '
          '${audioSeconds.toStringAsFixed(2)} s audio: '
          '${ms.toStringAsFixed(2)} ms median, '
          '${(audioSeconds * 1000 / ms).toStringAsFixed(1)}x realtime',
        );
      }
    }
  }
}
