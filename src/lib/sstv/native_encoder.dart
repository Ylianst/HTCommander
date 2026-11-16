// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_demodulator.dart';
import 'native_encoder_stub.dart'
    if (dart.library.ffi) 'native_encoder_ffi.dart'
    as backend;

(Uint8List, double)? encodeNativeSstv(
  Int32List pixels,
  int width,
  int height,
  int sampleRate,
  int code,
  double phase, {
  required bool pcm16,
  required int silenceSamples,
  required bool useSimd,
}) => nativeSstvSupported
    ? backend.encode(
        pixels,
        width,
        height,
        sampleRate,
        code,
        phase,
        pcm16: pcm16,
        silenceSamples: silenceSamples,
        useSimd: useSimd,
      )
    : null;
