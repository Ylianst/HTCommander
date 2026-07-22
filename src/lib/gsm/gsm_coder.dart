// gsm_coder.dart - Top level RPE-LTP coder (4.2) and decoder (4.3).
//
// Port of libgsm 1.0.22 code.c and decode.c. Source of truth:
// reference/libgsm/src/code.c, reference/libgsm/src/decode.c.

import 'dart:typed_data';

import 'gsm_long_term.dart';
import 'gsm_lpc.dart';
import 'gsm_math.dart';
import 'gsm_preprocess.dart';
import 'gsm_rpe.dart';
import 'gsm_short_term.dart';
import 'gsm_state.dart';

/// Gsm_Coder: encodes `s[0..159]` into the parameter arrays.
///
/// `larc[0..7]`, `nc[0..3]`, `bc[0..3]`, `mc[0..3]`, `xmaxc[0..3]`,
/// `xmc[0..51]` are filled in place.
void gsmCoder(GsmState state, Int16List s, Int16List larc, Int16List nc,
    Int16List bc, Int16List mc, Int16List xmaxc, Int16List xmc) {
  final Int16List dp0 = state.dp0;
  int dpIdx = 120; // dp = dp0 + 120; dpp shares the same index.

  final Int16List so = Int16List(160);

  gsmPreprocess(state, s, so);
  gsmLpcAnalysis(state, so, larc);
  gsmShortTermAnalysisFilter(state, larc, so);

  for (int k = 0; k <= 3; k++) {
    final List<int> ncBc = gsmLongTermPredictor(
        state, so, k * 40, dp0, dpIdx, state.e, 5, dp0, dpIdx);
    nc[k] = ncBc[0];
    bc[k] = ncBc[1];

    final List<int> mcXmaxc =
        gsmRpeEncoding(state, state.e, 5, xmc, k * 13);
    mc[k] = mcXmaxc[0];
    xmaxc[k] = mcXmaxc[1];

    for (int i = 0; i <= 39; i++) {
      dp0[dpIdx + i] = gsmAdd(state.e[5 + i], dp0[dpIdx + i]);
    }
    dpIdx += 40;
  }

  // memcpy(dp0, dp0 + 160, 120 words).
  dp0.setRange(0, 120, dp0, 160);
}

/// decode.c postprocessing (deemphasis, truncation, upscaling).
void _postprocessing(GsmState state, Int16List s) {
  int msr = state.msr;
  for (int k = 0; k < 160; k++) {
    final int tmp = multRMacro(msr, 28180);
    msr = gsmAdd(s[k], tmp);
    s[k] = wordOf(gsmAdd(msr, msr) & 0xFFF8);
  }
  state.msr = msr;
}

/// Gsm_Decoder: decodes the parameter arrays into `s[0..159]`.
void gsmDecoder(GsmState state, Int16List larcr, Int16List ncr, Int16List bcr,
    Int16List mcr, Int16List xmaxcr, Int16List xmcr, Int16List s) {
  final Int16List erp = Int16List(40);
  final Int16List wt = Int16List(160);
  final Int16List drp = state.dp0;
  const int drpIdx = 120;

  for (int j = 0; j <= 3; j++) {
    gsmRpeDecoding(state, xmaxcr[j], mcr[j], xmcr, j * 13, erp, 0);
    gsmLongTermSynthesisFiltering(
        state, ncr[j], bcr[j], erp, 0, drp, drpIdx);

    for (int k = 0; k <= 39; k++) {
      wt[j * 40 + k] = drp[drpIdx + k];
    }
  }

  gsmShortTermSynthesisFilter(state, larcr, wt, s);
  _postprocessing(state, s);
}
