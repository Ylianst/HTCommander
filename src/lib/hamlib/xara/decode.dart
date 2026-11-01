/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Frame decoding: de-interleave, turbo decode, de-whiten and CRC check.
*/

import 'dart:typed_data';

import 'crc.dart';
import 'dat.dart';
import 'turbo_decoder.dart';

const int decodeIterations = 10;
const double extrinsicScale = 0.7;
const int minIterations = 2;

class FrameOut {
  final Uint8List bytes;
  final bool ok;
  final int iterations;

  const FrameOut(this.bytes, this.ok, this.iterations);
}

/// Decodes one frame from channel-order LLRs [llrTx] (positive = bit 0).
FrameOut decodeFrame(
  TurboDecoder turbo,
  RecordTables t,
  int k,
  int n,
  int p,
  List<int> white,
  bool early,
  List<double> llrTx,
) {
  if (llrTx.length != t.chan.length) {
    throw ArgumentError('demapper and channel interleaver disagree on frame length');
  }
  final Float64List soft = Float64List(n);
  for (int i = 0; i < t.chan.length; i++) {
    soft[t.chan[i]] = llrTx[i];
  }
  final Split sp = split(Float64List.sublistView(soft, 0, usedLen(k, p)), t.turbo, p);
  final CrcCheck check = CrcCheck(white, k ~/ 8);
  final Decoded d = turbo.decode(sp, t.turbo, decodeIterations, extrinsicScale, early ? (minIterations, check) : null);
  final Uint8List bytes = check.bytes(d.bits);
  return FrameOut(bytes, crcOk(bytes), d.iterations);
}
