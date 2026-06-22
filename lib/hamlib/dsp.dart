/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// dsp.dart - Digital Signal Processing functions for filter generation
//
// Ported from C# HamLib/Dsp.cs
//

import 'dart:math' as math;

/// Window types for filter shaping.
enum BpWindowType { truncated, cosine, hamming, blackman, flattop }

/// Digital Signal Processing functions for generating filters used by
/// demodulators.
class Dsp {
  Dsp._();

  /// Maximum number of filter taps.
  static const int maxFilterSize = 480;

  /// Filter window shape functions.
  /// [type] window type, [size] number of filter taps, [j] index 0..size-1.
  /// Returns the multiplier for the window shape.
  static double window(BpWindowType type, int size, int j) {
    final double center = 0.5 * (size - 1);
    double w;

    switch (type) {
      case BpWindowType.cosine:
        w = math.cos((j - center) / size * math.pi);
        break;

      case BpWindowType.hamming:
        w = 0.53836 - 0.46164 * math.cos((j * 2 * math.pi) / (size - 1));
        break;

      case BpWindowType.blackman:
        w =
            0.42659 -
            0.49656 * math.cos((j * 2 * math.pi) / (size - 1)) +
            0.076849 * math.cos((j * 4 * math.pi) / (size - 1));
        break;

      case BpWindowType.flattop:
        w =
            1.0 -
            1.93 * math.cos((j * 2 * math.pi) / (size - 1)) +
            1.29 * math.cos((j * 4 * math.pi) / (size - 1)) -
            0.388 * math.cos((j * 6 * math.pi) / (size - 1)) +
            0.028 * math.cos((j * 8 * math.pi) / (size - 1));
        break;

      case BpWindowType.truncated:
        w = 1.0;
        break;
    }

    return w;
  }

  /// Generate low pass filter kernel.
  static void genLowpass(
    double fc,
    List<double> lpFilter,
    int filterSize,
    BpWindowType wtype,
  ) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError('Filter size must be between 3 and $maxFilterSize');
    }
    if (lpFilter.length < filterSize) {
      throw ArgumentError(
        'Filter array must have at least $filterSize elements',
      );
    }

    final double center = 0.5 * (filterSize - 1);

    for (int j = 0; j < filterSize; j++) {
      double sinc;
      if (j - center == 0) {
        sinc = 2 * fc;
      } else {
        sinc =
            math.sin(2 * math.pi * fc * (j - center)) /
            (math.pi * (j - center));
      }
      final double shape = window(wtype, filterSize, j);
      lpFilter[j] = sinc * shape;
    }

    // Normalize lowpass for unity gain at DC
    double g = 0;
    for (int j = 0; j < filterSize; j++) {
      g += lpFilter[j];
    }
    for (int j = 0; j < filterSize; j++) {
      lpFilter[j] = lpFilter[j] / g;
    }
  }

  /// Generate band pass filter kernel for the prefilter.
  /// This is NOT for the mark/space filters.
  static void genBandpass(
    double f1,
    double f2,
    List<double> bpFilter,
    int filterSize,
    BpWindowType wtype,
  ) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError('Filter size must be between 3 and $maxFilterSize');
    }
    if (bpFilter.length < filterSize) {
      throw ArgumentError(
        'Filter array must have at least $filterSize elements',
      );
    }

    final double center = 0.5 * (filterSize - 1);

    for (int j = 0; j < filterSize; j++) {
      double sinc;
      if (j - center == 0) {
        sinc = 2 * (f2 - f1);
      } else {
        sinc =
            math.sin(2 * math.pi * f2 * (j - center)) /
                (math.pi * (j - center)) -
            math.sin(2 * math.pi * f1 * (j - center)) /
                (math.pi * (j - center));
      }
      final double shape = window(wtype, filterSize, j);
      bpFilter[j] = sinc * shape;
    }

    // Normalize bandpass for unity gain in middle of passband
    final double w = 2 * math.pi * (f1 + f2) / 2;
    double g = 0;
    for (int j = 0; j < filterSize; j++) {
      g += 2 * bpFilter[j] * math.cos((j - center) * w);
    }
    for (int j = 0; j < filterSize; j++) {
      bpFilter[j] = bpFilter[j] / g;
    }
  }

  /// Generate mark and space filters.
  static void genMs(
    int fc,
    int sps,
    List<double> sinTable,
    List<double> cosTable,
    int filterSize,
    BpWindowType wtype,
  ) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError('Filter size must be between 3 and $maxFilterSize');
    }
    if (sinTable.length < filterSize || cosTable.length < filterSize) {
      throw ArgumentError(
        'Filter arrays must have at least $filterSize elements',
      );
    }

    double gs = 0, gc = 0;

    for (int j = 0; j < filterSize; j++) {
      final double center = 0.5 * (filterSize - 1);
      final double am = ((j - center) / sps) * fc * (2.0 * math.pi);

      final double shape = window(wtype, filterSize, j);

      sinTable[j] = math.sin(am) * shape;
      cosTable[j] = math.cos(am) * shape;

      gs += sinTable[j] * math.sin(am);
      gc += cosTable[j] * math.cos(am);
    }

    // Normalize for unity gain
    for (int j = 0; j < filterSize; j++) {
      sinTable[j] = sinTable[j] / gs;
      cosTable[j] = cosTable[j] / gc;
    }
  }

  /// Root Raised Cosine function.
  /// [t] time in units of symbol duration, [a] roll off factor between 0 and 1.
  static double rrc(double t, double a) {
    double sinc, win, result;

    if (t > -0.001 && t < 0.001) {
      sinc = 1;
    } else {
      sinc = math.sin(math.pi * t) / (math.pi * t);
    }

    if ((a * t).abs() > 0.499 && (a * t).abs() < 0.501) {
      win = math.pi / 4;
    } else {
      win = math.cos(math.pi * a * t) / (1 - math.pow(2 * a * t, 2));
    }

    result = sinc * win;
    return result;
  }

  /// Generate Root Raised Cosine low pass filter.
  static void genRrcLowpass(
    List<double> pfilter,
    int filterTaps,
    double rolloff,
    double samplesPerSymbol,
  ) {
    if (filterTaps < 3 || filterTaps > maxFilterSize) {
      throw ArgumentError('Filter taps must be between 3 and $maxFilterSize');
    }
    if (pfilter.length < filterTaps) {
      throw ArgumentError(
        'Filter array must have at least $filterTaps elements',
      );
    }

    for (int k = 0; k < filterTaps; k++) {
      final double t = (k - ((filterTaps - 1.0) / 2.0)) / samplesPerSymbol;
      pfilter[k] = rrc(t, rolloff);
    }

    double sum = 0;
    for (int k = 0; k < filterTaps; k++) {
      sum += pfilter[k];
    }
    for (int k = 0; k < filterTaps; k++) {
      pfilter[k] = pfilter[k] / sum;
    }
  }
}
