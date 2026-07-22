// gsm_lpc.dart - LPC analysis section (4.2.4 .. 4.2.7).
//
// Port of libgsm 1.0.22 lpc.c (pure integer path, no USE_FLOAT_MUL/FAST).
// Source of truth: reference/libgsm/src/lpc.c.

import 'dart:typed_data';

import 'gsm_math.dart';
import 'gsm_state.dart';

/// 4.2.4 Autocorrelation with dynamic scaling. `s[0..159]` is scaled in place
/// and rescaled back; `lAcf[0..8]` receives the autocorrelation.
void _autocorrelation(Int16List s, List<int> lAcf) {
  int smax = 0;
  for (int k = 0; k <= 159; k++) {
    final int t = gsmAbs(s[k]);
    if (t > smax) smax = t;
  }

  int scalauto;
  if (smax == 0) {
    scalauto = 0;
  } else {
    scalauto = 4 - gsmNorm(smax << 16);
  }

  if (scalauto > 0) {
    final int factor = 16384 >> (scalauto - 1);
    for (int k = 0; k <= 159; k++) {
      s[k] = multRMacro(s[k], factor);
    }
  }

  // Compute L_ACF[0..8] = sum_i s[i] * s[i-k].
  for (int k = 0; k <= 8; k++) {
    int acc = 0;
    for (int i = k; i <= 159; i++) {
      acc += s[i] * s[i - k];
    }
    lAcf[k] = acc;
  }

  for (int k = 0; k <= 8; k++) {
    lAcf[k] <<= 1;
  }

  if (scalauto > 0) {
    for (int k = 0; k <= 159; k++) {
      s[k] = s[k] << scalauto;
    }
  }
}

/// 4.2.5 Schur recursion producing reflection coefficients `r[0..7]`.
void _reflectionCoefficients(List<int> lAcf, Int16List r) {
  if (lAcf[0] == 0) {
    for (int i = 0; i < 8; i++) {
      r[i] = 0;
    }
    return;
  }

  int temp = gsmNorm(lAcf[0]);

  final Int16List acf = Int16List(9);
  for (int i = 0; i <= 8; i++) {
    acf[i] = (lAcf[i] << temp) >> 16;
  }

  final Int16List p = Int16List(9);
  final Int16List k = Int16List(9);
  for (int i = 1; i <= 7; i++) {
    k[i] = acf[i];
  }
  for (int i = 0; i <= 8; i++) {
    p[i] = acf[i];
  }

  int ri = 0;
  for (int n = 1; n <= 8; n++) {
    temp = p[1];
    temp = gsmAbs(temp);
    if (p[0] < temp) {
      for (int i = n; i <= 8; i++) {
        r[ri++] = 0;
      }
      return;
    }

    r[ri] = gsmDiv(temp, p[0]);
    if (p[1] > 0) r[ri] = -r[ri];
    if (n == 8) return;

    // Schur recursion.
    temp = multRMacro(p[1], r[ri]);
    p[0] = gsmAdd(p[0], temp);

    for (int m = 1; m <= 8 - n; m++) {
      temp = multRMacro(k[m], r[ri]);
      p[m] = gsmAdd(p[m + 1], temp);

      temp = multRMacro(p[m + 1], r[ri]);
      k[m] = gsmAdd(k[m], temp);
    }

    ri++;
  }
}

/// 4.2.6 Transformation of reflection coefficients into log-area ratios.
void _transformationToLogAreaRatios(Int16List r) {
  for (int i = 0; i < 8; i++) {
    int temp = gsmAbs(r[i]);
    if (temp < 22118) {
      temp >>= 1;
    } else if (temp < 31130) {
      temp -= 11059;
    } else {
      temp -= 26112;
      temp <<= 2;
    }
    r[i] = r[i] < 0 ? -temp : temp;
  }
}

const List<List<int>> _quantSteps = <List<int>>[
  <int>[20480, 0, 31, -32],
  <int>[20480, 0, 31, -32],
  <int>[20480, 2048, 15, -16],
  <int>[20480, -2560, 15, -16],
  <int>[13964, 94, 7, -8],
  <int>[15360, -1792, 7, -8],
  <int>[8534, -341, 3, -4],
  <int>[9036, -1144, 3, -4],
];

/// 4.2.7 Quantization and coding of the log-area ratios into `lar[0..7]`.
void _quantizationAndCoding(Int16List lar) {
  for (int i = 0; i < 8; i++) {
    final int a = _quantSteps[i][0];
    final int b = _quantSteps[i][1];
    final int mac = _quantSteps[i][2];
    final int mic = _quantSteps[i][3];

    int temp = multMacro(a, lar[i]);
    temp = gsmAdd(temp, b);
    temp = gsmAdd(temp, 256);
    temp >>= 9;
    lar[i] = temp > mac ? mac - mic : (temp < mic ? 0 : temp - mic);
  }
}

/// Gsm_LPC_Analysis: `s[0..159]` in/out, `larc[0..7]` out.
void gsmLpcAnalysis(GsmState state, Int16List s, Int16List larc) {
  final List<int> lAcf = List<int>.filled(9, 0);
  _autocorrelation(s, lAcf);
  _reflectionCoefficients(lAcf, larc);
  _transformationToLogAreaRatios(larc);
  _quantizationAndCoding(larc);
}
