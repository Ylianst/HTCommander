/*
Efficient in-place iterative radix-2 Cooley-Tukey FFT.

Ported to Dart for the spectrogram widget (equivalent of FftSharp.FFT.Forward
used by the C# Spectrogram component). Operates on flat Float64List real/imag
buffers with precomputed twiddle factors and a bit-reversal table so no objects
are allocated per transform.
*/

import 'dart:math' as math;
import 'dart:typed_data';

/// A reusable forward FFT for a fixed power-of-two [size].
///
/// Create once and call [forward] repeatedly with the same buffer length to
/// avoid re-computing the twiddle factors on every transform.
class SpectrogramFft {
  /// Transform length (must be a power of two).
  final int size;

  final Int32List _bitReverse;
  final Float64List _cosTable;
  final Float64List _sinTable;

  SpectrogramFft(this.size)
    : _bitReverse = Int32List(size),
      _cosTable = Float64List(size ~/ 2),
      _sinTable = Float64List(size ~/ 2) {
    if (size < 2 || (size & (size - 1)) != 0) {
      throw ArgumentError('FFT size must be a power of two >= 2 (was $size)');
    }

    final levels = _log2(size);
    for (int i = 0; i < size; i++) {
      _bitReverse[i] = _reverseBits(i, levels);
    }

    final half = size ~/ 2;
    for (int i = 0; i < half; i++) {
      // Forward transform uses e^{-j 2*pi*i/size}.
      final angle = -2.0 * math.pi * i / size;
      _cosTable[i] = math.cos(angle);
      _sinTable[i] = math.sin(angle);
    }
  }

  /// Perform an in-place forward FFT. [re] and [im] must both have length
  /// [size]; on return they hold the transform's real and imaginary parts.
  void forward(Float64List re, Float64List im) {
    final n = size;

    // Bit-reversal permutation.
    for (int i = 0; i < n; i++) {
      final j = _bitReverse[i];
      if (j > i) {
        double t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }

    // Cooley-Tukey butterflies.
    for (int len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final tableStep = n ~/ len;
      for (int i = 0; i < n; i += len) {
        for (int j = i, k = 0; j < i + half; j++, k += tableStep) {
          final l = j + half;
          final cos = _cosTable[k];
          final sin = _sinTable[k];
          final tre = re[l] * cos - im[l] * sin;
          final tim = re[l] * sin + im[l] * cos;
          re[l] = re[j] - tre;
          im[l] = im[j] - tim;
          re[j] += tre;
          im[j] += tim;
        }
      }
    }
  }

  static int _log2(int x) {
    int result = 0;
    while (x > 1) {
      x >>= 1;
      result++;
    }
    return result;
  }

  static int _reverseBits(int value, int bits) {
    int result = 0;
    for (int i = 0; i < bits; i++) {
      result = (result << 1) | (value & 1);
      value >>= 1;
    }
    return result;
  }
}
