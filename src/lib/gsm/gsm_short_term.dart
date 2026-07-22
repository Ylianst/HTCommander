// gsm_short_term.dart - Short term analysis/synthesis filtering (4.2.8 .. 4.2.10,
// 4.3.3 .. 4.3.5).
//
// Port of libgsm 1.0.22 short_term.c (pure integer path). Source of truth:
// reference/libgsm/src/short_term.c.

import 'dart:typed_data';

import 'gsm_math.dart';
import 'gsm_state.dart';

// B_TIMES_TWO, MIC, INVA per STEP in Decoding_of_the_coded_Log_Area_Ratios.
const List<List<int>> _larDecodeSteps = <List<int>>[
  <int>[0, -32, 13107],
  <int>[0, -32, 13107],
  <int>[4096, -16, 13107],
  <int>[-5120, -16, 13107],
  <int>[188, -8, 19223],
  <int>[-3584, -8, 17476],
  <int>[-682, -4, 31454],
  <int>[-2288, -4, 29708],
];

/// 4.2.8 Decoding of the coded log-area ratios into `larpp[0..7]`.
void _decodingOfCodedLogAreaRatios(Int16List larc, Int16List larpp) {
  for (int i = 0; i < 8; i++) {
    final int b2 = _larDecodeSteps[i][0];
    final int mic = _larDecodeSteps[i][1];
    final int inva = _larDecodeSteps[i][2];

    int temp1 = wordOf(gsmAdd(larc[i], mic) << 10);
    temp1 = gsmSub(temp1, b2);
    temp1 = wordOf(multRMacro(inva, temp1));
    larpp[i] = gsmAdd(temp1, temp1);
  }
}

/// 4.2.9.1 Interpolation of the LARpp values for samples 0..12.
void _coefficients0_12(Int16List j1, Int16List j, Int16List larp) {
  for (int i = 0; i < 8; i++) {
    larp[i] = gsmAdd(j1[i] >> 2, j[i] >> 2);
    larp[i] = gsmAdd(larp[i], j1[i] >> 1);
  }
}

/// Interpolation for samples 13..26.
void _coefficients13_26(Int16List j1, Int16List j, Int16List larp) {
  for (int i = 0; i < 8; i++) {
    larp[i] = gsmAdd(j1[i] >> 1, j[i] >> 1);
  }
}

/// Interpolation for samples 27..39.
void _coefficients27_39(Int16List j1, Int16List j, Int16List larp) {
  for (int i = 0; i < 8; i++) {
    larp[i] = gsmAdd(j1[i] >> 2, j[i] >> 2);
    larp[i] = gsmAdd(larp[i], j[i] >> 1);
  }
}

/// Interpolation for samples 40..159.
void _coefficients40_159(Int16List j, Int16List larp) {
  for (int i = 0; i < 8; i++) {
    larp[i] = j[i];
  }
}

/// 4.2.9.2 LARp -> reflection coefficients (in place).
void _larpToRp(Int16List larp) {
  for (int i = 0; i < 8; i++) {
    if (larp[i] < 0) {
      final int temp = larp[i] == kMinWord ? kMaxWord : -larp[i];
      larp[i] = -((temp < 11059)
          ? temp << 1
          : ((temp < 20070) ? temp + 11059 : gsmAdd(temp >> 2, 26112)));
    } else {
      final int temp = larp[i];
      larp[i] = (temp < 11059)
          ? temp << 1
          : ((temp < 20070) ? temp + 11059 : gsmAdd(temp >> 2, 26112));
    }
  }
}

/// 4.2.10 Short term analysis filtering over `sig[off .. off+count-1]`.
void _shortTermAnalysisFiltering(
    Int16List u, Int16List rp, int count, Int16List sig, int off) {
  int idx = off;
  for (; count-- > 0; idx++) {
    int di = sig[idx];
    int sav = di;
    for (int i = 0; i < 8; i++) {
      final int ui = u[i];
      final int rpi = rp[i];
      u[i] = sav;

      int zzz = multRMacro(rpi, di);
      sav = gsmAdd(ui, zzz);

      zzz = multRMacro(rpi, ui);
      di = gsmAdd(di, zzz);
    }
    sig[idx] = di;
  }
}

/// 4.3.3 Short term synthesis filtering over `wt`/`sr` segments.
void _shortTermSynthesisFiltering(Int16List v, Int16List rrp, int count,
    Int16List wt, int wtOff, Int16List sr, int srOff) {
  int wi = wtOff;
  int si = srOff;
  while (count-- > 0) {
    int sri = wt[wi++];
    for (int i = 8; i-- > 0;) {
      final int rpi = rrp[i];
      final int t2 = gsmMultR(rpi, v[i]);
      sri = gsmSub(sri, t2);
      final int t1 = gsmMultR(rpi, sri);
      v[i + 1] = gsmAdd(v[i], t1);
    }
    v[0] = sri;
    sr[si++] = sri;
  }
}

/// Gsm_Short_Term_Analysis_Filter: `larc[0..7]` in, `s[0..159]` in/out.
void gsmShortTermAnalysisFilter(GsmState state, Int16List larc, Int16List s) {
  final Int16List larppJ = state.larpp[state.j];
  state.j ^= 1;
  final Int16List larppJ1 = state.larpp[state.j];

  final Int16List larp = Int16List(8);

  _decodingOfCodedLogAreaRatios(larc, larppJ);

  _coefficients0_12(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermAnalysisFiltering(state.u, larp, 13, s, 0);

  _coefficients13_26(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermAnalysisFiltering(state.u, larp, 14, s, 13);

  _coefficients27_39(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermAnalysisFiltering(state.u, larp, 13, s, 27);

  _coefficients40_159(larppJ, larp);
  _larpToRp(larp);
  _shortTermAnalysisFiltering(state.u, larp, 120, s, 40);
}

/// Gsm_Short_Term_Synthesis_Filter: `larcr[0..7]` in, `wt[0..159]` in,
/// `s[0..159]` out.
void gsmShortTermSynthesisFilter(
    GsmState state, Int16List larcr, Int16List wt, Int16List s) {
  final Int16List larppJ = state.larpp[state.j];
  state.j ^= 1;
  final Int16List larppJ1 = state.larpp[state.j];

  final Int16List larp = Int16List(8);

  _decodingOfCodedLogAreaRatios(larcr, larppJ);

  _coefficients0_12(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermSynthesisFiltering(state.v, larp, 13, wt, 0, s, 0);

  _coefficients13_26(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermSynthesisFiltering(state.v, larp, 14, wt, 13, s, 13);

  _coefficients27_39(larppJ1, larppJ, larp);
  _larpToRp(larp);
  _shortTermSynthesisFiltering(state.v, larp, 13, wt, 27, s, 27);

  _coefficients40_159(larppJ, larp);
  _larpToRp(larp);
  _shortTermSynthesisFiltering(state.v, larp, 120, wt, 40, s, 40);
}
