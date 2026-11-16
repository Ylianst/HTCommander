// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import 'native_scanline_stub.dart'
    if (dart.library.ffi) 'native_scanline_ffi.dart'
    as backend;

bool get nativeSstvScanLineSupported => backend.supported;

abstract class NativeSstvScanLine {
  void process(
    Float64List input,
    int start,
    Float64List scratch,
    int scratchStart,
    Int32List pixels,
    List<int> config,
    double alpha,
    double frequencyOffset,
  );
  void dispose();
}

NativeSstvScanLine? createNativeSstvScanLine() =>
    backend.supported ? backend.create() : null;
