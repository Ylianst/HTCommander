/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM coding: tables, whitening, per-key phasors and the frame encoder.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'dat.dart';
import 'decode.dart';
import 'fec.dart';
import 'fm_level.dart';
import 'rnd.dart';
import 'seq.dart' as seq;
import 'turbo_decoder.dart';

const int phasorRows = 201;
const int fmBins = 128;

/// Phasors indexed `[bin][row]`.
typedef Phasors = List<List<Cx>>;

List<RecordTables> fmCodeTables(FmBandwidth bw) => fmTablesCached(bw);

Uint8List? _white;

Uint8List fmWhitening() => _white ??= seq.whitening(seq.fmSeed);

void warmFm() {
  for (final FmBandwidth bw in FmBandwidth.values) {
    fmCodeTables(bw);
  }
  fmWhitening();
}

List<Uint8List> phaseIndices(int? key) {
  final VbRnd r;
  if (key == null) {
    r = VbRnd.stream(seq.fmSeed);
  } else {
    r = VbRnd()..seedRnd(key);
  }
  return List<Uint8List>.generate(fmBins, (_) {
    final Uint8List row = Uint8List(phasorRows);
    for (int i = 0; i < phasorRows; i++) {
      row[i] = r.randInt(32);
    }
    return row;
  });
}

final List<(int?, Phasors)> _phasorCache = <(int?, Phasors)>[];

Phasors phasors(int? key) {
  for (final (int? k, Phasors p) in _phasorCache) {
    if (k == key) return p;
  }
  final Phasors p = phaseIndices(key)
      .map((r) => List<Cx>.unmodifiable(r.map((d) => Cx.polar(1.0, math.pi * d / 15.0))))
      .toList(growable: false);
  if (_phasorCache.length >= 8) _phasorCache.removeAt(0);
  _phasorCache.add((key, p));
  return p;
}

int? recordKey(FmRecord record, int key) => record.keyed ? key : null;

Uint8List fmEncode(FmBandwidth bw, FmRecord record, List<int> frame) {
  final FmLevel l = bw.level(record);
  final RecordTables t = fmCodeTables(bw)[record.index];
  final Uint8List info = frameBits(frame, l.layout.k);
  whiten(info, fmWhitening());
  return interleave(turboEncode(info, t.turbo, l.puncturePeriodValue, l.n), t.chan);
}

/// FM frame codec (encode + turbo decode) for one bandwidth.
class FmCodec {
  final FmBandwidth bw;
  final TurboDecoder _turbo = const TurboDecoder();
  bool early = true;

  FmCodec(this.bw);

  FmLevel level(FmRecord record) => bw.level(record);

  RecordTables tables(FmRecord record) => fmCodeTables(bw)[record.index];

  Uint8List encode(FmRecord record, List<int> frame) => fmEncode(bw, record, frame);

  FrameOut decode(FmRecord record, List<double> llrTx) {
    final FmLevel l = level(record);
    return decodeFrame(_turbo, tables(record), l.layout.k, l.n, l.puncturePeriodValue, fmWhitening(), early, llrTx);
  }
}
