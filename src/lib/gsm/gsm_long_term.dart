// gsm_long_term.dart - Long term predictor section (4.2.11 .. 4.2.12, 4.3.2).
//
// Port of libgsm 1.0.22 long_term.c (pure integer path, no LTP_CUT/FAST).
// Source of truth: reference/libgsm/src/long_term.c.

import 'dart:typed_data';

import 'gsm_math.dart';
import 'gsm_state.dart';
import 'gsm_tables.dart';

/// 4.2.11 Calculation of the LTP parameters. Returns (Nc, bc).
///
/// `d[dOff .. dOff+39]` is the current sub-segment residual; `dp` is the
/// previous reconstructed residual accessed as `dp[dpOff + k - lambda]`.
List<int> _calculationOfTheLtpParameters(
    Int16List d, int dOff, Int16List dp, int dpOff) {
  int dmax = 0;
  for (int k = 0; k <= 39; k++) {
    final int t = gsmAbs(d[dOff + k]);
    if (t > dmax) dmax = t;
  }

  int temp = 0;
  if (dmax != 0) {
    temp = gsmNorm(dmax << 16);
  }
  final int scal = temp > 6 ? 0 : 6 - temp;

  final Int16List wt = Int16List(40);
  for (int k = 0; k <= 39; k++) {
    wt[k] = d[dOff + k] >> scal;
  }

  int lMax = 0;
  int nc = 40;
  for (int lambda = 40; lambda <= 120; lambda++) {
    int lResult = 0;
    for (int k = 0; k <= 39; k++) {
      lResult += wt[k] * dp[dpOff + k - lambda];
    }
    if (lResult > lMax) {
      nc = lambda;
      lMax = lResult;
    }
  }

  lMax <<= 1;
  lMax = lMax >> (6 - scal);

  int lPower = 0;
  for (int k = 0; k <= 39; k++) {
    final int lTemp = dp[dpOff + k - nc] >> 3;
    lPower += lTemp * lTemp;
  }
  lPower <<= 1;

  if (lMax <= 0) {
    return <int>[nc, 0];
  }
  if (lMax >= lPower) {
    return <int>[nc, 3];
  }

  temp = gsmNorm(lPower);
  final int r = wordOf((lMax << temp) >> 16);
  final int sVal = wordOf((lPower << temp) >> 16);

  int bc = 0;
  for (bc = 0; bc <= 2; bc++) {
    if (r <= gsmMult(sVal, gsmDlb[bc])) break;
  }
  return <int>[nc, bc];
}

const List<int> _bpForBc = <int>[3277, 11469, 21299, 32767];

/// 4.2.12 Long term analysis filtering.
void _longTermAnalysisFiltering(int bc, int nc, Int16List dp, int dpOff,
    Int16List d, int dOff, Int16List dpp, int dppOff, Int16List e, int eOff) {
  final int bp = _bpForBc[bc];
  for (int k = 0; k <= 39; k++) {
    dpp[dppOff + k] = multRMacro(bp, dp[dpOff + k - nc]);
    e[eOff + k] = gsmSub(d[dOff + k], dpp[dppOff + k]);
  }
}

/// Gsm_Long_Term_Predictor. Returns (Nc, bc); writes `e`/`dpp` estimates.
List<int> gsmLongTermPredictor(GsmState state, Int16List d, int dOff,
    Int16List dp, int dpOff, Int16List e, int eOff, Int16List dpp, int dppOff) {
  final List<int> ncBc = _calculationOfTheLtpParameters(d, dOff, dp, dpOff);
  final int nc = ncBc[0];
  final int bc = ncBc[1];
  _longTermAnalysisFiltering(bc, nc, dp, dpOff, d, dOff, dpp, dppOff, e, eOff);
  return ncBc;
}

/// 4.3.2 Gsm_Long_Term_Synthesis_Filtering.
void gsmLongTermSynthesisFiltering(GsmState state, int ncr, int bcr,
    Int16List erp, int erpOff, Int16List drp, int drpOff) {
  final int nr = (ncr < 40 || ncr > 120) ? state.nrp : ncr;
  state.nrp = nr;

  final int brp = gsmQlb[bcr];

  for (int k = 0; k <= 39; k++) {
    final int drpp = multRMacro(brp, drp[drpOff + k - nr]);
    drp[drpOff + k] = gsmAdd(erp[erpOff + k], drpp);
  }

  for (int k = 0; k <= 119; k++) {
    drp[drpOff - 120 + k] = drp[drpOff - 80 + k];
  }
}
