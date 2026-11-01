/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
HF CQ frames (record 15): callsign, SSID and bandwidth in 6 bytes + CRC.
*/

import 'dart:typed_data';

import 'ax25.dart';
import 'crc.dart';
import 'hf_level.dart';

const HfRecord cqRecord = HfRecord(15);
const int cqPayload = 6;

int _bwCode(HfBandwidth bw) => switch (bw) {
      HfBandwidth.hz500 => 1,
      HfBandwidth.hz2300 => 2,
      HfBandwidth.hz2750 => 3,
    };

/// CQ bandwidth: a known [HfBandwidth] or null for an unknown code.
class CqBw {
  final HfBandwidth? known;

  const CqBw(this.known);

  @override
  String toString() => known == null ? '' : '${known!.hz}';

  @override
  bool operator ==(Object other) => other is CqBw && other.known == known;

  @override
  int get hashCode => known.hashCode;
}

class Cq {
  final String call;
  final CqBw? bw;

  const Cq(this.call, [this.bw]);

  String get hostLine => bw != null ? 'CQFRAME $call $bw' : 'CQFRAME $call';

  @override
  bool operator ==(Object other) => other is Cq && other.call == call && other.bw == bw;

  @override
  int get hashCode => Object.hash(call, bw);

  @override
  String toString() => 'Cq($call, $bw)';
}

bool validCall(String call) => Call.parse(call) != null;

Uint8List? payload(String call, HfBandwidth bw) {
  final Call? c = Call.parse(call);
  if (c == null) return null;
  int v = 0;
  final String base = c.base.padRight(7);
  for (final int ch in base.codeUnits) {
    final int i = callAlphabet.codeUnits.indexOf(ch);
    if (i < 0) return null;
    v = (v << 6) | i;
  }
  v = (v << 6) | (_bwCode(bw) * 16 + c.ssid);
  return Uint8List.fromList(<int>[for (int i = 5; i >= 0; i--) (v >> (8 * i)) & 0xFF]);
}

Uint8List? frame(String call, HfBandwidth bw) {
  final Uint8List? p = payload(call, bw);
  if (p == null) return null;
  final int crc = crc16Genibus(p);
  return Uint8List.fromList(<int>[...p, crc >> 8, crc & 0xFF]);
}

Cq? parse(List<int> frame) {
  if (frame.length < cqPayload) return null;
  int v = 0;
  for (int i = 0; i < cqPayload; i++) {
    v = (v << 8) | frame[i];
  }
  final StringBuffer sb = StringBuffer();
  for (int k = 0; k < 7; k++) {
    final int idx = (v >> (42 - 6 * k)) & 63;
    if (idx < callAlphabet.length) sb.write(callAlphabet[idx]);
  }
  String call = sb.toString().trimRight();
  final int x = v & 63;
  if (x & 15 != 0) call += '-${x & 15}';
  HfBandwidth? bw;
  for (final HfBandwidth b in HfBandwidth.values) {
    if (_bwCode(b) == x >> 4) bw = b;
  }
  return Cq(call, CqBw(bw));
}
