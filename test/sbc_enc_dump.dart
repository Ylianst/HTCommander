// SBC encoder byte dump (for cross-validation against libsbc).
//
// ignore_for_file: avoid_print  (diagnostic script: printing is the point)
//
// Purpose:
//   Encodes a fixed 1 kHz sine into mSBC frames and prints each frame as hex.
//   The Dart encoder output is byte-for-byte identical to Google's libsbc
//   reference encoder, so this dump can be diffed against it to confirm the
//   encoder stays bit-exact after future changes.
//
// How to run:
//   dart run test/sbc_enc_dump.dart
//
// Cross-checking against the libsbc reference (reference/libsbc):
//   A tiny C harness that calls sbc_encode() with `.msbc = true` on the same
//   sine input produces identical hex. Build it with:
//     cc -O2 -Ireference/libsbc/include \
//        reference/libsbc/src/sbc.c reference/libsbc/src/bits.c <harness>.c \
//        -lm -o /tmp/ench
//   then diff the two hex dumps. All eight frames must match exactly.
//
// Note: standalone diagnostic script (prints results), not a package:test
//   suite. Kept because it is useful for verifying bit-exactness.

import 'dart:math';
import 'dart:typed_data';

import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main() {
  final SbcEncoder enc = SbcEncoder();
  const int n = 120;
  for (int f = 0; f < 8; f++) {
    final Int16List pcm = Int16List(n);
    for (int i = 0; i < n; i++) {
      final int idx = f * n + i;
      pcm[i] = (sin(2 * pi * 1000.0 * idx / 16000.0) * 16000.0).round();
    }
    final Uint8List? data = enc.encode(pcm, null, SbcFrame.createMsbc());
    final String hex = data == null
        ? 'NULL'
        : data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    print('frame $f: $hex');
  }
}
