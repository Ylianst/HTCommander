// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_dsp.dart';

const bool supported = false;
const bool dartOnly = false;
const int simdWidth = 1;

NativeXaraRows createRows(int capacity, int width) =>
    throw UnsupportedError('Native XARA DSP is unavailable');

NativeXaraPattern createPattern(
  Int32List rows,
  Int32List bins,
  Float64List refs,
  int markers,
) => throw UnsupportedError('Native XARA DSP is unavailable');

NativeXaraFft createFft(
  Float64List cosine,
  Float64List sine,
  Int32List reverse,
) => throw UnsupportedError('Native XARA DSP is unavailable');

NativeXaraFir createFir(Float64List hr, Float64List hi, int dec) =>
    throw UnsupportedError('Native XARA DSP is unavailable');

NativeXaraResampler createResampler(Float64List table, int half, int phases) =>
    throw UnsupportedError('Native XARA DSP is unavailable');

(Uint8List, int) decodeTurbo(
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
) => throw UnsupportedError('Native XARA DSP is unavailable');
