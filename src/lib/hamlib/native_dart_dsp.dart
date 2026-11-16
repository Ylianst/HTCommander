// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import 'dart:math' as math;
import 'xara/native_dsp.dart' as xara;

import 'native_dart_dsp_stub.dart'
    if (dart.library.ffi) 'native_dart_dsp_ffi.dart'
    as backend;

/// Native DART kernels on Windows/Linux/macOS/Android. Web/iOS use Dart.
/// HT_DART_REFERENCE=true (environment or Dart define) forces the reference.
bool get nativeDartDspEnabled =>
    !const bool.fromEnvironment('HT_DART_REFERENCE') &&
    backend.supported &&
    !backend.referenceOnly;

int get nativeDartSimdWidth => nativeDartDspEnabled ? backend.simdWidth : 1;

double nativeDartPeak(Float64List samples) => backend.peak(samples);
void nativeDartToPcm(Float64List samples, double scale, Int16List out) =>
    backend.toPcm(samples, scale, out);
void nativeDartFromPcm(Int16List samples, Float64List out) =>
    backend.fromPcm(samples, out);

abstract class NativeDartLdpc {
  Uint8List encode(Uint8List info);
  Uint8List decode(Float64List llr, Int32List? corrections, int iterations);
}

NativeDartLdpc? createNativeDartLdpc(
  int k,
  int n,
  Int32List starts,
  Int32List columns,
  Int32List varStarts,
  Int32List varEdges,
) => nativeDartDspEnabled
    ? backend.createLdpc(k, n, starts, columns, varStarts, varEdges)
    : null;

void nativeDartDft(
  Float64List input,
  Float64List cosine,
  Float64List sine,
  double norm,
  bool inverse,
  Float64List out,
) => backend.dft(input, cosine, sine, norm, inverse, out);

void nativeDartCorrelate(
  Float64List samples,
  Float64List reference,
  double energy,
  int start,
  int count,
  Float64List out,
) => backend.correlate(samples, reference, energy, start, count, out);

void nativeDartFskEnergy(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
) => backend.fskEnergy(samples, cosine, sine, stride, out);

void nativeDartFskSoft(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
  Float64List quality,
  bool measureSnr,
) => backend.fskSoft(samples, cosine, sine, stride, out, quality, measureSnr);

double nativeDartFskModulate(
  Uint8List bits,
  int sps,
  Float64List steps,
  Float64List cosine,
  Float64List sine,
  double phase,
  Float64List out,
) => backend.fskModulate(bits, sps, steps, cosine, sine, phase, out);

final _fftPlans = <int, xara.NativeXaraFft>{};

/// Reuse XARA's baseline SSE2/NEON FFT; its inverse is unnormalized.
xara.NativeXaraFft? createNativeDartFft(int n) {
  if (!nativeDartDspEnabled || !xara.nativeDspEnabled) return null;
  if (n < 2 || n > 2048 || n & (n - 1) != 0) {
    throw ArgumentError.value(n, 'FFT size');
  }
  return _fftPlans.putIfAbsent(n, () {
    final cosine = Float64List(n ~/ 2);
    final sine = Float64List(n ~/ 2);
    final reverse = Int32List(n);
    for (int i = 0; i < n ~/ 2; i++) {
      cosine[i] = math.cos(2 * math.pi * i / n);
      sine[i] = math.sin(2 * math.pi * i / n);
    }
    for (int i = 0; i < n; i++) {
      int value = i, reversed = 0;
      for (int bit = n; bit > 1; bit >>= 1) {
        reversed = (reversed << 1) | (value & 1);
        value >>= 1;
      }
      reverse[i] = reversed;
    }
    final plan = xara.createNativeFft(cosine, sine, reverse);
    if (plan == null) throw StateError('Native DART FFT unavailable');
    return plan;
  });
}

/// Overlap-save correlation with O(N log M) work and bounded scratch space.
/// The returned block is owned by this plan and valid until its next call.
final class NativeDartCorrelation {
  final Float64List reference;
  final xara.NativeXaraFft _fft;
  final Float64List _re, _im, _refRe, _refIm, _out;
  final double _energy;
  int get capacity => _out.length;

  NativeDartCorrelation._(this.reference, this._fft, int n)
    : _re = Float64List(n),
      _im = Float64List(n),
      _refRe = Float64List(n),
      _refIm = Float64List(n),
      _out = Float64List(n - reference.length + 1),
      _energy = reference.fold(0, (sum, v) => sum + v * v) {
    _refRe.setAll(0, reference);
    _fft.transform(_refRe, _refIm, false);
  }

  static NativeDartCorrelation? create(Float64List reference) {
    if (!nativeDartDspEnabled || reference.isEmpty || reference.length > 512) {
      return null;
    }
    int n = 2;
    while (n < reference.length * 4) {
      n <<= 1;
    }
    final fft = createNativeDartFft(n);
    return fft == null ? null : NativeDartCorrelation._(reference, fft, n);
  }

  Float64List process(Float64List samples, int start, int count) {
    RangeError.checkValueInInterval(count, 1, capacity, 'correlation count');
    final length = count + reference.length - 1;
    RangeError.checkValidRange(start, start + length, samples.length);
    final window = Float64List.sublistView(samples, start, start + length);
    if (window.every((sample) => sample == 0)) {
      _out.fillRange(0, count, 0);
      return _out;
    }
    _re.setRange(0, length, window);
    _re.fillRange(length, _re.length, 0);
    _im.fillRange(0, _im.length, 0);
    _fft.transform(_re, _im, false);
    backend.multiplyConjugate(_re, _im, _refRe, _refIm);
    _fft.transform(_re, _im, true);
    backend.normalizeCorrelation(
      window,
      reference.length,
      _energy,
      _re,
      count,
      _out,
    );
    return _out;
  }
}
