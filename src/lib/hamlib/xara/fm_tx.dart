/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM OFDM modulator.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'dat.dart';
import 'dsp.dart';
import 'fm_code.dart';
import 'fm_constellation.dart';
import 'fm_ctrl.dart';
import 'fm_level.dart';
import 'numeric.dart';
import 'ofdm.dart' as ofdm;

const int preSignalSymbols = 42;
const int preSignalBin = 32;
const int tuneBin = 32;
const double tuneBackoffDb = 5.007;
final int connectLeadIn = dataLeadIn(23);
const int idleBeaconLeadIn = 9;

/// One OFDM symbol: [fmBins] bins stored as interleaved (re, im).
typedef Row = Float64List;

Row newRow() => Float64List(2 * fmBins);

void _set(Row row, int b, Cx z) {
  row[2 * b] = z.re;
  row[2 * b + 1] = z.im;
}

List<List<bool>> symbolMap(FmLevel l, List<int> other) =>
    markerMap(other, l.nc, l.layout.markers, l.nsym);

List<Row> frameRows(FmLevel l, List<int> other, Phasors p, List<int> tx) {
  final ofdm.OfdmLayout layout = ofdm.OfdmLayout(
    spf: l.spf,
    bps: l.layout.bps,
    n: l.n,
    qam: l.isQam,
    cst: fmConstellation(l.layout.bps),
    map: symbolMap(l, other),
  );
  final List<Row> rows = List<Row>.generate(l.nsym, (_) => newRow());
  layout.cells(l.bins, fmQamPilot, tx, (_, b, r, cell) => _set(rows[r], b, cell * p[b][r].conj()));
  return rows;
}

List<Row> leadRowsFor(FmLevel l, int n, int Function(int) rand) {
  final List<Cx> cst = fmConstellation(l.layout.bps);
  final List<Row> rows = List<Row>.generate(n, (_) => newRow());
  for (final int b in l.bins) {
    for (final Row row in rows) {
      _set(row, b, cst[rand(cst.length)]);
    }
  }
  return rows;
}

List<Row> preSignalRows() => List<Row>.generate(preSignalSymbols, (_) {
      final Row r = newRow();
      _set(r, preSignalBin, const Cx(0.0, -7.2));
      return r;
    });

Float64List fmSynth(List<Row> rows, double scale) => ofdm.synth(0, rows, scale);

Float64List tuneBlock(double driveDb) {
  final double a = math.sqrt2 * dbAmp(driveDb - tuneBackoffDb);
  return Float64List.fromList(List<double>.generate(
      ofdm.nfft, (n) => a * math.cos(2.0 * math.pi * (tuneBin * n) / ofdm.nfft)));
}

class TxOptions {
  final double driveDb;
  final bool preSignal;

  const TxOptions({this.driveDb = 0.0, this.preSignal = false});
}

class Modulator {
  final FmBandwidth bw;

  Modulator(this.bw);

  FmLevel level(FmRecord record) => bw.level(record);

  Uint8List encode(FmRecord record, List<int> frame) => fmEncode(bw, record, frame);

  List<Row> rows(FmRecord record, int key, List<List<int>> frames) {
    final FmLevel l = level(record);
    final Phasors p = phasors(recordKey(record, key));
    final List<int> other = fmCodeTables(bw)[record.index].other;
    return <Row>[for (final List<int> f in frames) ...frameRows(l, other, p, encode(record, f))];
  }

  Float64List transmission(
    FmRecord record,
    int key,
    List<List<int>> frames,
    int lead,
    TxOptions opt,
    int Function(int) rand,
  ) {
    final FmLevel l = level(record);
    final List<Row> rows = <Row>[
      if (opt.preSignal) ...preSignalRows(),
      ...leadRowsFor(l, lead, rand),
      ...this.rows(record, key, frames),
    ];
    final double g = l.gain(opt.driveDb) / l.ampNorm;
    final Float64List x = fmSynth(rows, g);
    for (int i = 0; i < x.length; i++) {
      x[i] = x[i].clamp(-1.0, 1.0);
    }
    return x;
  }
}

Int16List toI16(List<double> x) {
  final Int16List out = Int16List(x.length);
  for (int i = 0; i < x.length; i++) {
    final double v = roundTiesEven(x[i] * 32767.0);
    out[i] = v >= 32767 ? 32767 : (v <= -32768 ? -32768 : v.toInt());
  }
  return out;
}
