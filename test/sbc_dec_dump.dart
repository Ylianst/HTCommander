// SBC decoder PCM dump (for cross-validation against libsbc).
//
// ignore_for_file: avoid_print  (diagnostic script: printing is the point)
//
// Purpose:
//   Encodes a fixed 1 kHz sine to mSBC, decodes it back, and prints the
//   reconstructed PCM samples (one per line). The Dart decoder output is
//   sample-for-sample identical to Google's libsbc reference decoder, so this
//   dump can be diffed against it to confirm the decoder stays bit-exact after
//   future changes.
//
// How to run:
//   dart run test/sbc_dec_dump.dart
//
// Cross-checking against the libsbc reference (reference/libsbc):
//   A tiny C harness that calls sbc_encode() then sbc_decode() on the same
//   sine input (built against reference/libsbc/src) produces identical PCM.
//   Diff the two sample dumps; every sample must match.
//
// Note: standalone diagnostic script (prints results), not a package:test
//   suite. Kept because it is useful for verifying bit-exactness.

import 'dart:math';
import 'dart:typed_data';

import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main() {
  final SbcEncoder enc = SbcEncoder();
  final SbcDecoder dec = SbcDecoder();
  const int n = 120;
  final StringBuffer sb = StringBuffer();
  for (int f = 0; f < 8; f++) {
    final Int16List pcm = Int16List(n);
    for (int i = 0; i < n; i++) {
      final int idx = f * n + i;
      pcm[i] = (sin(2 * pi * 1000.0 * idx / 16000.0) * 16000.0).round();
    }
    final Uint8List? data = enc.encode(pcm, null, SbcFrame.createMsbc());
    final res = dec.decode(data);
    for (final int s in res.pcmLeft) {
      sb.writeln(s);
    }
  }
  print(sb.toString());
}
