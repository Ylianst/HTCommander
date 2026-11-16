// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_demodulator_stub.dart'
    if (dart.library.ffi) 'native_demodulator_ffi.dart'
    as backend;

bool get nativeSstvSupported => backend.supported;
int get nativeSstvSimdWidth => backend.simdWidth;

abstract class NativeSstvDemodulator {
  int get syncWidth;
  int get syncOffset;
  double get frequencyOffset;
  bool process(Float64List samples, int channelSelect);

  /// Output is a borrowed native view, valid until the next call or disposal.
  (Float64List, bool) processPcm16(Uint8List pcm, int offset, int length);
  void dispose();
}

NativeSstvDemodulator? createNativeSstvDemodulator(
  int sampleRate,
  Float64List taps,
  int syncCount,
  int min5,
  int max5,
  int max9,
  int max20, {
  required bool useSimd,
}) => backend.supported
    ? backend.create(
        sampleRate,
        taps,
        syncCount,
        min5,
        max5,
        max9,
        max20,
        useSimd,
      )
    : null;
