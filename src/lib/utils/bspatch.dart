/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Applies a `BSDIFF40` binary patch to a base image to reconstruct a target
/// image.
///
/// This is a pure-Dart implementation of the classic `bspatch` algorithm used
/// by `bsdiff4` (the same tool the `benlink` reference implementation uses to
/// assemble Benshi firmware). The patch format is:
///
/// ```
/// offset  bytes  meaning
/// 0       8      magic "BSDIFF40"
/// 8       8      length of the (bzip2-compressed) control block  (int64 LE*)
/// 16      8      length of the (bzip2-compressed) diff block      (int64 LE*)
/// 24      8      length of the new/target file                    (int64 LE*)
/// 32      ...    bzip2(control) | bzip2(diff) | bzip2(extra)
/// ```
///
/// (*) Integers use bsdiff's sign-magnitude "offtin" encoding, where the high
/// bit of the last byte is the sign flag rather than two's-complement.
class BsPatch {
  static const List<int> _magic = [0x42, 0x53, 0x44, 0x49, 0x46, 0x46, 0x34, 0x30]; // "BSDIFF40"

  /// Returns `true` if [patch] begins with the `BSDIFF40` magic.
  static bool isBsdiff40(Uint8List patch) {
    if (patch.length < 8) return false;
    for (int i = 0; i < 8; i++) {
      if (patch[i] != _magic[i]) return false;
    }
    return true;
  }

  /// Reconstruct the target image by applying [patch] to [base].
  ///
  /// Throws [FormatException] if the patch is malformed.
  static Uint8List apply(Uint8List base, Uint8List patch) {
    if (!isBsdiff40(patch)) {
      throw const FormatException('Not a BSDIFF40 patch (bad magic)');
    }
    if (patch.length < 32) {
      throw const FormatException('BSDIFF40 patch too short (truncated header)');
    }

    final ctrlLen = _offtin(patch, 8);
    final diffLen = _offtin(patch, 16);
    final newSize = _offtin(patch, 24);

    if (ctrlLen < 0 || diffLen < 0 || newSize < 0) {
      throw const FormatException('BSDIFF40 patch has negative block sizes');
    }

    final ctrlStart = 32;
    final diffStart = ctrlStart + ctrlLen;
    final extraStart = diffStart + diffLen;
    if (extraStart > patch.length) {
      throw const FormatException('BSDIFF40 block lengths exceed patch size');
    }

    final decoder = BZip2Decoder();
    final control = decoder.decodeBytes(
      patch.sublist(ctrlStart, diffStart),
    );
    final diff = decoder.decodeBytes(
      patch.sublist(diffStart, extraStart),
    );
    final extra = decoder.decodeBytes(
      patch.sublist(extraStart, patch.length),
    );

    final out = Uint8List(newSize);

    int oldPos = 0;
    int newPos = 0;
    int ctrlPos = 0;
    int diffPos = 0;
    int extraPos = 0;

    while (newPos < newSize) {
      // Read a control triple: (add length, copy length, old seek).
      if (ctrlPos + 24 > control.length) {
        throw const FormatException('BSDIFF40 control block underflow');
      }
      final addLen = _offtin(control, ctrlPos);
      final copyLen = _offtin(control, ctrlPos + 8);
      final seekLen = _offtin(control, ctrlPos + 16);
      ctrlPos += 24;

      // Sanity check the add block.
      if (addLen < 0 || newPos + addLen > newSize) {
        throw const FormatException('BSDIFF40 add block out of bounds');
      }
      if (diffPos + addLen > diff.length) {
        throw const FormatException('BSDIFF40 diff block underflow');
      }

      // Add: out[newPos+i] = diff[i] + base[oldPos+i] (byte wraparound).
      for (int i = 0; i < addLen; i++) {
        int value = diff[diffPos + i];
        final op = oldPos + i;
        if (op >= 0 && op < base.length) {
          value = (value + base[op]) & 0xFF;
        }
        out[newPos + i] = value;
      }
      newPos += addLen;
      oldPos += addLen;
      diffPos += addLen;

      // Copy: out[newPos+i] = extra[i].
      if (copyLen < 0 || newPos + copyLen > newSize) {
        throw const FormatException('BSDIFF40 copy block out of bounds');
      }
      if (extraPos + copyLen > extra.length) {
        throw const FormatException('BSDIFF40 extra block underflow');
      }
      out.setRange(newPos, newPos + copyLen, extra, extraPos);
      newPos += copyLen;
      extraPos += copyLen;

      // Seek within the base image.
      oldPos += seekLen;
    }

    return out;
  }

  /// Decode a bsdiff "offtin" 64-bit sign-magnitude integer at [offset].
  static int _offtin(Uint8List buf, int offset) {
    int y = buf[offset + 7] & 0x7F;
    y = y * 256 + buf[offset + 6];
    y = y * 256 + buf[offset + 5];
    y = y * 256 + buf[offset + 4];
    y = y * 256 + buf[offset + 3];
    y = y * 256 + buf[offset + 2];
    y = y * 256 + buf[offset + 1];
    y = y * 256 + buf[offset + 0];
    if (buf[offset + 7] & 0x80 != 0) {
      y = -y;
    }
    return y;
  }
}
