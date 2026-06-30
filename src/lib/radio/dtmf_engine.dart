/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dart port of the C# DmtfEngine (reference/HTCommander/src/radio/DmtfEngine.cs).
Generates DTMF dual-tone audio as 8-bit unsigned PCM at 32 kHz mono.
*/

import 'dart:math' as math;
import 'dart:typed_data';

/// Generates DTMF dual-tone audio (8-bit unsigned PCM, 32 kHz mono).
class DtmfEngine {
  DtmfEngine._();

  static const int _sampleRate = 32000;

  /// Half of 127 so two tones summed stay within 8-bit range.
  static const int _amplitude = 63;

  /// DTMF frequency pairs (row/low frequency, column/high frequency).
  static const Map<String, List<int>> _dtmfFrequencies = {
    '1': [697, 1209],
    '2': [697, 1336],
    '3': [697, 1477],
    '4': [770, 1209],
    '5': [770, 1336],
    '6': [770, 1477],
    '7': [852, 1209],
    '8': [852, 1336],
    '9': [852, 1477],
    '*': [941, 1209],
    '0': [941, 1336],
    '#': [941, 1477],
  };

  /// Generates 8-bit unsigned PCM audio (32 kHz, mono) for a DTMF [digits]
  /// string.
  ///
  /// Valid characters: 0–9, *, #. Unknown characters are silently skipped.
  /// [toneDurationMs] is the duration of each tone; [gapDurationMs] is the
  /// silent gap between tones.
  static Uint8List generateDtmfPcm(
    String digits, {
    int toneDurationMs = 150,
    int gapDurationMs = 80,
  }) {
    final int toneSamples = (_sampleRate * toneDurationMs / 1000.0).toInt();
    final int gapSamples = (_sampleRate * gapDurationMs / 1000.0).toInt();

    final Uint8List gap = _generateSilence(gapSamples);

    final BytesBuilder stream = BytesBuilder();
    bool firstDigit = true;

    for (final String ch in digits.split('')) {
      final List<int>? freq = _dtmfFrequencies[ch];
      if (freq == null) continue;

      // Insert inter-digit gap before every digit except the first.
      if (!firstDigit) stream.add(gap);
      firstDigit = false;

      stream.add(_generateDualTone(freq[0], freq[1], toneSamples));
    }

    return stream.toBytes();
  }

  static Uint8List _generateDualTone(
    int lowFreq,
    int highFreq,
    int sampleCount,
  ) {
    final Uint8List buffer = Uint8List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final double t = i / _sampleRate;
      final double low = math.sin(2 * math.pi * lowFreq * t);
      final double high = math.sin(2 * math.pi * highFreq * t);
      // Mix two tones and scale to 8-bit unsigned PCM centered at 128.
      buffer[i] = (128 + (low + high) * _amplitude).toInt();
    }
    return buffer;
  }

  static Uint8List _generateSilence(int sampleCount) {
    return Uint8List(sampleCount)..fillRange(0, sampleCount, 128);
  }
}
