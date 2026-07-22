// gsm_preprocess.dart - Preprocessing section (4.2.0 .. 4.2.3).
//
// Port of libgsm 1.0.22 preprocess.c. Downscaling, offset compensation and
// preemphasis. Source of truth: reference/libgsm/src/preprocess.c.

import 'dart:typed_data';

import 'gsm_math.dart';
import 'gsm_state.dart';

/// Gsm_Preprocess: filters `src[0..159]` into `so[0..159]`.
void gsmPreprocess(GsmState s, Int16List src, Int16List so) {
  int z1 = s.z1;
  int lZ2 = s.lZ2;
  int mp = s.mp;

  for (int k = 0; k < 160; k++) {
    // 4.2.1 Downscaling of the input signal.
    final int so0 = (src[k] >> 3) << 2;

    // 4.2.2 Offset compensation (high-pass filter).
    final int s1 = so0 - z1;
    z1 = so0;

    int lS2 = s1;
    lS2 <<= 15;

    final int msp0 = lZ2 >> 15;
    final int lsp = lZ2 - (msp0 << 15);

    lS2 += multRMacro(lsp, 32735);
    int lTemp = msp0 * 32735;
    lZ2 = gsmLAdd(lTemp, lS2);

    lTemp = gsmLAdd(lZ2, 16384);

    // 4.2.3 Preemphasis.
    final int msp = multRMacro(mp, -28180);
    mp = wordOf(lTemp >> 15);
    so[k] = gsmAdd(mp, msp);
  }

  s.z1 = z1;
  s.lZ2 = lZ2;
  s.mp = mp;
}
