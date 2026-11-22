// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _asset = 'package:htcommander/sstv_dsp';

@Native<Int64 Function(Int32, Int32)>(
  symbol: 'ht_sstv_encoded_length',
  assetId: _asset,
  isLeaf: true,
)
external int _length(int sampleRate, int code);

@Native<
  Int32 Function(
    Pointer<Int32>,
    Int64,
    Int32,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
    Pointer<Void>,
    Int64,
    Int32,
    Int32,
  )
>(symbol: 'ht_sstv_encode', assetId: _asset)
external int _encode(
  Pointer<Int32> pixels,
  int pixelCount,
  int width,
  int height,
  int sampleRate,
  int code,
  Pointer<Double> phase,
  Pointer<Void> output,
  int capacity,
  int pcm,
  int simd,
);

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
}) => using((arena) {
  if (width < 1 ||
      height < 1 ||
      width > 0x7fffffff ||
      height > 0x7fffffff ||
      width * height > pixels.length ||
      sampleRate < 1 ||
      sampleRate > 0x7fffffff ||
      silenceSamples < 0 ||
      !phase.isFinite) {
    throw ArgumentError('Invalid native SSTV encoder dimensions or phase');
  }
  final count = _length(sampleRate, code);
  if (count < 0) throw ArgumentError('Invalid native SSTV mode or sample rate');
  final bytesPerSample = pcm16 ? 2 : 8;
  final byteCount = (silenceSamples + count) * bytesPerSample;
  RangeError.checkValueInInterval(byteCount, 0, 0x7fffffff, 'encoded bytes');
  if (count == 0) return (Uint8List(byteCount), phase);
  final source = arena<Int32>(width * height);
  source.asTypedList(width * height).setRange(0, width * height, pixels);
  final position = arena<Double>()..value = phase;
  final output = malloc<Uint8>(byteCount);
  try {
    final prefix = silenceSamples * bytesPerSample;
    output.asTypedList(prefix).fillRange(0, prefix, 0);
    final status = _encode(
      source,
      width * height,
      width,
      height,
      sampleRate,
      code,
      position,
      (output + prefix).cast(),
      count,
      pcm16 ? 1 : 0,
      useSimd ? 1 : 0,
    );
    if (status != 0) {
      throw StateError('Native SSTV encoder failed (status $status)');
    }
    final endPhase = position.value;
    // Isolate.run/compute may outlive the worker's native allocation.
    return (Uint8List.fromList(output.asTypedList(byteCount)), endPhase);
  } finally {
    malloc.free(output);
  }
}, malloc);
