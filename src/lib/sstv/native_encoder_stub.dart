// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

(Uint8List, double) encode(
  Int32List pixels,
  int width,
  int height,
  int sampleRate,
  int code,
  double phase, {
  required bool pcm16,
  required int silenceSamples,
  required bool useSimd,
}) => throw UnsupportedError('Native SSTV encoding is unavailable');
