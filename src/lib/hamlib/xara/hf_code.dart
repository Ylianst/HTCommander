/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
HF coding helpers: tables, whitening, phasors and the frame encoder.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'dat.dart';
import 'decode.dart';
import 'fec.dart';
import 'hf_level.dart';
import 'seq.dart' as seq;
import 'turbo_decoder.dart';

Uint8List? _white;

Uint8List hfWhitening() => _white ??= seq.whitening(seq.hfSeed);

List<RecordTables> hfCodeTables(HfBandwidth bw) => hfTablesCached(bw);

List<List<Cx>> _phasors(List<Uint8List> idx) => idx
    .map((r) => List<Cx>.unmodifiable(r.map((d) => Cx.polar(1.0, 2.0 * math.pi * d / 128.0))))
    .toList(growable: false);

List<List<Cx>>? _psk;
List<List<Cx>>? _ofdm;

List<List<Cx>> pskPhasors() => _psk ??= _phasors(seq.pskPhasorIndex());

List<List<Cx>> ofdmPhasors() => _ofdm ??= _phasors(seq.ofdmPhasorIndex());

void warmHf(HfBandwidth bw) {
  hfCodeTables(bw);
  hfWhitening();
  pskPhasors();
  ofdmPhasors();
}

Uint8List hfEncode(HfBandwidth bw, HfRecord record, List<int> frame) {
  final HfLevel l = bw.level(record);
  final RecordTables t = hfCodeTables(bw)[record.index];
  final Uint8List info = frameBits(frame, l.k);
  whiten(info, hfWhitening());
  return interleave(turboEncode(info, t.turbo, l.puncturePeriodValue, l.n), t.chan);
}

/// HF frame decoder for one bandwidth.
class HfFrameDecoder {
  final HfBandwidth bw;
  final TurboDecoder _turbo = const TurboDecoder();
  bool early = true;

  HfFrameDecoder(this.bw);

  List<RecordTables> get tables => hfCodeTables(bw);

  FrameOut decode(HfRecord record, List<double> llrTx) {
    final HfLevel l = bw.level(record);
    return decodeFrame(_turbo, tables[record.index], l.k, l.n, l.puncturePeriodValue, hfWhitening(), early, llrTx);
  }
}
