// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_dsp_stub.dart'
    if (dart.library.ffi) 'native_dsp_ffi.dart'
    as backend;

/// HT_XARA_DART=true (environment or Dart define) selects reference kernels.
bool get nativeDspEnabled =>
    !const bool.fromEnvironment('HT_XARA_DART') &&
    backend.supported &&
    !backend.dartOnly;

int get nativeDspSimdWidth => nativeDspEnabled ? backend.simdWidth : 1;

abstract class NativeXaraFft {
  void transform(Float64List re, Float64List im, bool inverse);
}

abstract class NativeXaraFir {
  Float64List process(Float64List samples, int count);
}

abstract class NativeXaraRows {
  int get storageBytes;
  void append(int index, Float32List row);
  void appendSpectrum(
    int index,
    Float64List re,
    Float64List im,
    Float32List row,
    Float32List? previous,
  );
}

abstract class NativeXaraPattern {
  /// Optional mandatory marker threshold; rejected candidates get zero dataChi.
  /// Negative infinity preserves unrestricted metrics.
  Float64List terms(NativeXaraRows rows, int first, int last,
      [double markerMin = double.negativeInfinity]);
}

NativeXaraRows? createNativeRows(int capacity, int width) =>
    nativeDspEnabled ? backend.createRows(capacity, width) : null;

NativeXaraPattern? createNativePattern(
  Int32List rows,
  Int32List bins,
  Float64List refs,
  int markers,
) => nativeDspEnabled ? backend.createPattern(rows, bins, refs, markers) : null;

abstract class NativeXaraResampler {
  (List<double>, int, double) process(
    List<double> samples,
    int index,
    double fraction,
    int whole,
    double part,
  );
}

NativeXaraFft? createNativeFft(
  Float64List cosine,
  Float64List sine,
  Int32List reverse,
) => nativeDspEnabled ? backend.createFft(cosine, sine, reverse) : null;

NativeXaraFir? createNativeFir(Float64List hr, Float64List hi, int dec) =>
    nativeDspEnabled ? backend.createFir(hr, hi, dec) : null;

NativeXaraResampler? createNativeResampler(
  Float64List table,
  int half,
  int phases,
) => nativeDspEnabled ? backend.createResampler(table, half, phases) : null;

(Uint8List, int) decodeNativeTurbo(
  Float64List ls,
  Float64List lp1,
  Float64List ls2,
  Float64List lp2,
  List<int> perm,
  int iters,
  double scale,
  int minIters,
  List<int> white,
  int nbytes,
) => backend.decodeTurbo(
  ls,
  lp1,
  ls2,
  lp2,
  perm,
  iters,
  scale,
  minIters,
  white,
  nbytes,
);
