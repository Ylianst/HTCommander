// gsm_state.dart - Persistent per-stream state for the GSM 06.10 codec.
//
// Mirrors `struct gsm_state` from libgsm 1.0.22 private.h, restricted to the
// fields used by the pure integer encode/decode path (WAV49, FAST and debug
// fields are omitted). Source of truth: reference/libgsm/inc/private.h.

import 'dart:typed_data';

class GsmState {
  /// code.c reconstructed short-term residual history ([-120..159] window).
  final Int16List dp0 = Int16List(280);

  /// code.c long-term residual signal buffer ([-5..44]).
  final Int16List e = Int16List(50);

  /// preprocess.c offset-compensation state.
  int z1 = 0; // word
  int lZ2 = 0; // longword
  int mp = 0; // preemphasis memory (word)

  /// short_term.c analysis filter memory.
  final Int16List u = Int16List(8);

  /// short_term.c decoded LARpp for the previous and current frame.
  final List<Int16List> larpp = <Int16List>[Int16List(8), Int16List(8)];
  int j = 0; // odd/even LARpp selector

  /// long_term.c synthesis lag memory.
  int nrp = 40;

  /// short_term.c synthesis filter memory.
  final Int16List v = Int16List(9);

  /// decode.c postprocessing (deemphasis) memory.
  int msr = 0;

  GsmState() {
    reset();
  }

  /// Restores the state to a freshly-created stream (gsm_create semantics:
  /// everything zeroed, then nrp = 40).
  void reset() {
    dp0.fillRange(0, dp0.length, 0);
    e.fillRange(0, e.length, 0);
    z1 = 0;
    lZ2 = 0;
    mp = 0;
    u.fillRange(0, u.length, 0);
    larpp[0].fillRange(0, 8, 0);
    larpp[1].fillRange(0, 8, 0);
    j = 0;
    nrp = 40;
    v.fillRange(0, v.length, 0);
    msr = 0;
  }
}
