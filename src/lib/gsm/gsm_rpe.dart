// gsm_rpe.dart - RPE encoding/decoding section (4.2.13 .. 4.2.18, 4.3.1).
//
// Port of libgsm 1.0.22 rpe.c. Source of truth: reference/libgsm/src/rpe.c.

import 'dart:typed_data';

import 'gsm_math.dart';
import 'gsm_state.dart';
import 'gsm_tables.dart';

/// 4.2.13 Weighting filter: `e[eOff-5 .. eOff+44]` -> `x[0..39]`.
void _weightingFilter(Int16List e, int eOff, Int16List x) {
  final int base = eOff - 5;
  for (int k = 0; k <= 39; k++) {
    int lResult = 8192 >> 1;
    lResult += e[base + k + 0] * -134;
    lResult += e[base + k + 1] * -374;
    lResult += e[base + k + 3] * 2054;
    lResult += e[base + k + 4] * 5741;
    lResult += e[base + k + 5] * 8192;
    lResult += e[base + k + 6] * 5741;
    lResult += e[base + k + 7] * 2054;
    lResult += e[base + k + 9] * -374;
    lResult += e[base + k + 10] * -134;

    lResult >>= 13;
    x[k] = lResult < kMinWord
        ? kMinWord
        : (lResult > kMaxWord ? kMaxWord : lResult);
  }
}

/// 4.2.14 RPE grid selection. Returns Mc; fills `xm[0..12]`.
int _rpeGridSelection(Int16List x, Int16List xm) {
  int em = 0;
  int mc = 0;
  for (int m = 0; m <= 3; m++) {
    int lResult = 0;
    for (int i = 0; i <= 12; i++) {
      final int t = x[m + 3 * i] >> 2;
      lResult += t * t;
    }
    lResult <<= 1;
    if (lResult > em) {
      mc = m;
      em = lResult;
    }
  }

  for (int i = 0; i <= 12; i++) {
    xm[i] = x[mc + 3 * i];
  }
  return mc;
}

/// 4.2.15 Decode xmaxc into exponent/mantissa. Returns [exp, mant].
List<int> _apcmQuantizationXmaxcToExpMant(int xmaxc) {
  int exp = 0;
  if (xmaxc > 15) exp = (xmaxc >> 3) - 1;
  int mant = xmaxc - (exp << 3);

  if (mant == 0) {
    exp = -4;
    mant = 7;
  } else {
    while (mant <= 7) {
      mant = (mant << 1) | 1;
      exp--;
    }
    mant -= 8;
  }
  return <int>[exp, mant];
}

/// 4.2.15 APCM quantization. Returns [mant, exp, xmaxc]; fills `xmc[xmcOff..+12]`.
List<int> _apcmQuantization(Int16List xm, Int16List xmc, int xmcOff) {
  int xmax = 0;
  for (int i = 0; i <= 12; i++) {
    final int t = gsmAbs(xm[i]);
    if (t > xmax) xmax = t;
  }

  int exp = 0;
  int temp = xmax >> 9;
  int itest = 0;
  for (int i = 0; i <= 5; i++) {
    itest |= (temp <= 0) ? 1 : 0;
    temp >>= 1;
    if (itest == 0) exp++;
  }

  temp = exp + 5;
  final int xmaxc = gsmAdd(xmax >> temp, exp << 3);

  final List<int> expMant = _apcmQuantizationXmaxcToExpMant(xmaxc);
  exp = expMant[0];
  final int mant = expMant[1];

  final int temp1 = 6 - exp;
  final int temp2 = gsmNrfac[mant];

  for (int i = 0; i <= 12; i++) {
    int t = wordOf(xm[i] << temp1);
    t = multMacro(t, temp2);
    t >>= 12;
    xmc[xmcOff + i] = t + 4;
  }

  return <int>[mant, exp, xmaxc];
}

/// 4.2.16 APCM inverse quantization: `xmc[xmcOff..+12]` -> `xmp[0..12]`.
void _apcmInverseQuantization(
    Int16List xmc, int xmcOff, int mant, int exp, Int16List xmp) {
  final int temp1 = gsmFac[mant];
  final int temp2 = gsmSub(6, exp);
  final int temp3 = gsmAsl(1, gsmSub(temp2, 1));

  for (int i = 0; i < 13; i++) {
    int temp = (xmc[xmcOff + i] << 1) - 7;
    temp <<= 12;
    temp = multRMacro(temp1, temp);
    temp = gsmAdd(temp, temp3);
    xmp[i] = gsmAsr(temp, temp2);
  }
}

/// 4.2.17 RPE grid positioning: upsample `xmp[0..12]` into `ep[epOff+0..39]`.
void _rpeGridPositioning(int mc, Int16List xmp, Int16List ep, int epOff) {
  for (int k = 0; k <= 39; k++) {
    ep[epOff + k] = 0;
  }
  for (int i = 0; i <= 12; i++) {
    ep[epOff + mc + 3 * i] = xmp[i];
  }
}

/// Gsm_RPE_Encoding. Returns [Mc, xmaxc]; fills `xmc[xmcOff..+12]` and updates
/// `e[eOff..eOff+39]` via grid positioning.
List<int> gsmRpeEncoding(
    GsmState state, Int16List e, int eOff, Int16List xmc, int xmcOff) {
  final Int16List x = Int16List(40);
  final Int16List xm = Int16List(13);
  final Int16List xmp = Int16List(13);

  _weightingFilter(e, eOff, x);
  final int mc = _rpeGridSelection(x, xm);
  final List<int> mantExpXmaxc = _apcmQuantization(xm, xmc, xmcOff);
  final int mant = mantExpXmaxc[0];
  final int exp = mantExpXmaxc[1];
  final int xmaxc = mantExpXmaxc[2];
  _apcmInverseQuantization(xmc, xmcOff, mant, exp, xmp);
  _rpeGridPositioning(mc, xmp, e, eOff);

  return <int>[mc, xmaxc];
}

/// 4.3.1 Gsm_RPE_Decoding: fills `erp[erpOff+0..39]`.
void gsmRpeDecoding(GsmState state, int xmaxcr, int mcr, Int16List xmcr,
    int xmcrOff, Int16List erp, int erpOff) {
  final List<int> expMant = _apcmQuantizationXmaxcToExpMant(xmaxcr);
  final int exp = expMant[0];
  final int mant = expMant[1];

  final Int16List xmp = Int16List(13);
  _apcmInverseQuantization(xmcr, xmcrOff, mant, exp, xmp);
  _rpeGridPositioning(mcr, xmp, erp, erpOff);
}
