// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'native_reed_solomon_stub.dart'
    if (dart.library.ffi) 'native_reed_solomon_ffi.dart'
    as backend;

bool get nativeReedSolomonSupported => backend.supported;

/// A cached field/generator plan with reusable block and decoder scratch space.
/// Mode 0 is radiosonde (ascending coefficients); mode 1 is FX.25.
abstract class NativeReedSolomon {
  void encode(List<int> data, [List<int>? parity]);
  int decode(List<int> data, [List<int>? erasures, int count = 0]);
  void dispose();
}

NativeReedSolomon createNativeReedSolomon({
  required int mode,
  required int roots,
  required int fcr,
  required int prim,
  required int inversePrim,
  required List<int> exp,
  required List<int> log,
  required List<int> generator,
}) => backend.create(mode, roots, fcr, prim, inversePrim, exp, log, generator);
