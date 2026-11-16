// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import 'native_dart_dsp.dart';

const supported = false;
const referenceOnly = true;
const simdWidth = 1;
double peak(Float64List samples) => _unsupported();
void toPcm(Float64List samples, double scale, Int16List out) => _unsupported();
void fromPcm(Int16List samples, Float64List out) => _unsupported();
void multiplyConjugate(
  Float64List re,
  Float64List im,
  Float64List refRe,
  Float64List refIm,
) => _unsupported();
Never _unsupported() => throw UnsupportedError('Native DART DSP unavailable');
NativeDartLdpc createLdpc(
  int k,
  int n,
  Int32List starts,
  Int32List columns,
  Int32List varStarts,
  Int32List varEdges,
) => _unsupported();
void dft(
  Float64List input,
  Float64List cosine,
  Float64List sine,
  double norm,
  bool inverse,
  Float64List out,
) => _unsupported();
void correlate(
  Float64List samples,
  Float64List reference,
  double energy,
  int start,
  int count,
  Float64List out,
) => _unsupported();
void fskEnergy(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
) => _unsupported();
double fskModulate(
  Uint8List bits,
  int sps,
  Float64List steps,
  Float64List cosine,
  Float64List sine,
  double phase,
  Float64List out,
) => _unsupported();

void fskSoft(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
  Float64List quality,
  bool measureSnr,
) => _unsupported();

void normalizeCorrelation(
  Float64List samples,
  int length,
  double energy,
  Float64List correlation,
  int count,
  Float64List out,
) => _unsupported();
