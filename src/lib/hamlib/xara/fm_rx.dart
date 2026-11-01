/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM receiver: differential STFT detector, per-record OFDM engines, frame
decoding and transmission assembly. Spectra are stored at f32 precision as
upstream does; detection metrics accumulate in f64.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'decode.dart';
import 'demap.dart';
import 'dsp.dart';
import 'eq.dart';
import 'fm_code.dart';
import 'fm_constellation.dart';
import 'fm_ctrl.dart';
import 'fm_level.dart';
import 'fm_rx_frontend.dart';
import 'fm_tx.dart' show symbolMap;
import 'receiver_common.dart';

const int ofdmHop = 4;
const int sym = symLen ~/ ofdmHop;
const double mkFrac = 0.25;
const double minCoherence = 0.45;
const int cpMid = 10;
const int _maxDat = 600;
const int _refine = 3;
const double _snBwHz = 2500.0;

const double _bufSeconds = 12.0;
const int _grace = 2 * symLen;
const int _continueAt = 2 * symLen;
const int _noiseBlock = 60;
const int _probeRows = 6;

Cx _pow4(Cx z) {
  final Cx s = z * z;
  return s * s;
}

/// Differential STFT: `diff[j][k]` is the unit-normalised product of bin k at
/// hop j with the same bin one OFDM symbol earlier.
class Stft {
  final FftWindow _win = FftWindow(nf);
  final Track<Float32List> _spectra = Track<Float32List>(2 * sym + 8);
  final Track<Float32List> diff;
  int _stftNext = 0;

  Stft(int maxSpf) : diff = Track<Float32List>(sym * maxSpf + 64);

  void update(SampleTrack buf) {
    final int jHi = floorDiv(buf.end - nf, ofdmHop);
    final int j0 = math.max(_stftNext, floorDiv(buf.base + ofdmHop - 1, ofdmHop));
    for (int j = j0; j <= jHi; j++) {
      _win.at(buf, j * ofdmHop, nf);
      final Float32List row = Float32List(2 * nf);
      for (int k = 0; k < nf; k++) {
        row[2 * k] = _win.re[k];
        row[2 * k + 1] = _win.im[k];
      }
      final Float32List g = Float32List(2 * nf);
      if (_spectra.contains(j - sym)) {
        final Float32List prev = _spectra.at(j - sym);
        for (int k = 0; k < nf; k++) {
          final double ar = row[2 * k], ai = row[2 * k + 1];
          final double br = prev[2 * k], bi = prev[2 * k + 1];
          final double pr = ar * br + ai * bi, pi = ai * br - ar * bi;
          final double n = hypot(pr, pi) + 1e-30;
          g[2 * k] = pr / n;
          g[2 * k + 1] = pi / n;
        }
      }
      _spectra.append(j, <Float32List>[row]);
      diff.append(j, <Float32List>[g]);
    }
    _stftNext = math.max(_stftNext, jHi + 1);
  }
}

class _Cell {
  final int row;
  final int carrier;
  final int bin;
  final double refRe;
  final double refIm;

  _Cell(this.row, this.carrier, this.bin, Cx ref)
      : refRe = Float32List.fromList(<double>[ref.re])[0],
        refIm = Float32List.fromList(<double>[ref.im])[0];
}

class FmDetection {
  final FmRecord record;
  final int t;
  final double metric;

  const FmDetection(this.record, this.t, this.metric);
}

class FmFrameRx implements RxFrame {
  final FmRecord record;
  final int index;
  @override
  final int t;
  @override
  final int tEnd;
  @override
  final bool ok;
  final bool missing;
  final Uint8List bytes;
  final double esn0Db;
  final double snrDb;
  final int iterations;
  final double coherence;

  /// Equalised data symbols and their bits/symbol; only set while capture is on.
  final List<Cx>? symbols;
  final int bps;

  FmFrameRx({
    required this.record,
    this.index = 0,
    required this.t,
    required this.tEnd,
    this.ok = false,
    this.missing = false,
    Uint8List? bytes,
    this.esn0Db = 0.0,
    this.snrDb = 0.0,
    this.iterations = 0,
    this.coherence = 0.0,
    this.symbols,
    this.bps = 0,
  }) : bytes = bytes ?? Uint8List(0);

  int get tEnd48 => to48(tEnd);
}

class FmCtrlEvent {
  final CtrlDetection det;
  final Side side;

  const FmCtrlEvent(this.det, this.side);

  int get tEnd48 => to48(det.tEnd);
}

typedef FmEvent = RxEvent<FmCtrlEvent, FmRecord, FmFrameRx>;
typedef FmTransmission = Transmission<FmRecord, FmFrameRx>;

class OfdmEngine {
  final FmRecord record;
  final FmLevel l;
  final List<List<bool>> _map;
  final List<List<Cx>> _phasors;
  final List<_Cell> _markers = <_Cell>[];
  late final List<_Cell> _data;
  final List<int> _bins;
  final int span;
  int? _searchNext;
  final Hold<void> _hold;
  final Fft _fft = Fft.plan(nf);

  OfdmEngine(this.l, List<int> other, Phasors phasors)
      : record = l.record,
        _map = symbolMap(l, other),
        _bins = l.bins.toList(),
        _phasors = <List<Cx>>[],
        span = l.nsym * symLen,
        _hold = Hold<void>(sym ~/ 2, sym * (l.nsym - 2)) {
    for (int r = 0; r < l.nsym; r++) {
      _phasors.add(<Cx>[for (final int b in _bins) phasors[b][r]]);
    }
    final List<_Cell> data = <_Cell>[];
    for (int c = 0; c < _bins.length; c++) {
      for (int r = 1; r < l.nsym; r++) {
        final Cx q = _phasors[r][c] * _phasors[r - 1][c].conj();
        if (_map[c][r]) {
          _markers.add(_Cell(r, c, _bins[c], q));
        } else if (!l.isQam) {
          data.add(_Cell(r, c, _bins[c], _pow4(q)));
        }
      }
    }
    _data = thin(data, _maxDat);
  }

  void startAt(int j) => _searchNext = math.max(_searchNext ?? j, j);

  (double, double) _terms(Stft st, int j) {
    double ar = 0.0, ai = 0.0;
    for (final _Cell m in _markers) {
      final Float32List d = st.diff.at(j + sym * m.row);
      final double dr = d[2 * m.bin], di = d[2 * m.bin + 1];
      ar += dr * m.refRe - di * m.refIm;
      ai += dr * m.refIm + di * m.refRe;
    }
    double br = 0.0, bi = 0.0;
    for (final _Cell c in _data) {
      final Float32List d = st.diff.at(j + sym * c.row);
      final double dr = d[2 * c.bin], di = d[2 * c.bin + 1];
      final double sr = dr * dr - di * di, si = 2 * dr * di;
      final double qr = sr * sr - si * si, qi = 2 * sr * si;
      br += qr * c.refRe - qi * c.refIm;
      bi += qr * c.refIm + qi * c.refRe;
    }
    final double markerChi = (ar * ar + ai * ai) / _markers.length;
    final double dataChi = _data.isEmpty ? 0.0 : (br * br + bi * bi) / _data.length;
    return (markerChi, dataChi);
  }

  List<FmDetection> step(Stft st) {
    final int need = sym * (l.nsym - 1);
    final int hi = st.diff.end - 1 - need - 2 * _refine;
    final int lo = math.max(_searchNext ?? st.diff.base, st.diff.base);
    final List<FmDetection> out = <FmDetection>[];
    if (hi < lo) return out;
    final double markerMin = math.max(mkFrac * _markers.length, 6.0);
    for (int j = lo; j <= hi; j++) {
      final (double mc, double dc) = _terms(st, j);
      final double chi = mc + dc;
      final (double, void)? cand = mc >= markerMin && chi >= chiMin ? (chi, null) : null;
      final (int, double, void)? got = _hold.offer(j, cand);
      if (got != null) out.add(FmDetection(record, got.$1 * ofdmHop, got.$2));
    }
    _searchNext = hi + 1;
    return out;
  }

  List<List<Cx>> _cells(SampleTrack buf, int t, int rows) {
    final Float64List re = Float64List(nf), im = Float64List(nf);
    final List<List<Cx>> out = <List<Cx>>[];
    for (int r = 0; r < rows; r++) {
      final int a = t + r * symLen;
      buf.fill(a, a + nf, re, im);
      _fft.transform(re, im);
      final List<Cx> p = _phasors[r];
      out.add(<Cx>[for (int c = 0; c < _bins.length; c++) Cx(re[_bins[c]], im[_bins[c]]) * p[c]]);
    }
    return out;
  }

  (double, Cx) _coherence(List<List<Cx>> c) {
    Cx s = Cx.zero;
    for (final _Cell m in _markers) {
      s = s + unit(c[m.row - 1][m.carrier].conj() * c[m.row][m.carrier]);
    }
    return (s.norm / _markers.length, s);
  }

  double? earlyCoherence(SampleTrack buf, int t0, int rows0) {
    final int rows = math.min(rows0, l.nsym);
    if (t0 + rows * symLen + _refine > buf.end || t0 - _refine < buf.base) return null;
    final bool qam = l.isQam;
    final List<(int, int)> cells = <(int, int)>[
      for (int r = 1; r < rows; r++)
        for (int c = 0; c < l.nc; c++)
          if (!qam || _map[c][r]) (r, c),
    ];
    double? best;
    for (int t = t0 - _refine; t <= t0 + _refine; t++) {
      final List<List<Cx>> c = _cells(buf, t, rows);
      Cx s = Cx.zero;
      for (final (int r, int k) in cells) {
        final Cx d = c[r - 1][k].conj() * c[r][k];
        s = s + unit(qam ? d : _pow4(d));
      }
      final double v = s.norm / math.max(cells.length, 1);
      if (best == null || totalCmp(v, best) >= 0) best = v;
    }
    return best;
  }

  FmFrameRx? decode(SampleTrack buf, FmCodec codec, int t0, int index, [List<Cx>? capture]) {
    if (t0 + span + _refine > buf.end || t0 - _refine < buf.base) return null;
    final List<(List<List<Cx>>, double, Cx)> cand = <(List<List<Cx>>, double, Cx)>[];
    for (int t = t0 - _refine; t <= t0 + _refine; t++) {
      final List<List<Cx>> c = _cells(buf, t, l.nsym);
      final (double m, Cx s) = _coherence(c);
      cand.add((c, m, s));
    }
    final List<double> vals = cand.map((x) => x.$2).toList();
    final int i = peakMid(vals, argmax(vals), 0.02);
    final int t = t0 - _refine + i;
    final (List<List<Cx>> c, double coh, Cx s) = cand[i];
    final (List<double> llr, double esn0) = l.isQam ? _qamLlr(c, capture) : _dpskLlr(c, s, capture);
    final FrameOut out = codec.decode(record, llr);
    final double esn0Db = 10.0 * math.log(math.max(esn0, 1e-6)) / math.ln10;
    final double nc = l.nc.toDouble();
    return FmFrameRx(
      record: record,
      index: index,
      t: t,
      tEnd: t - cpMid + span,
      ok: out.ok,
      bytes: out.bytes,
      esn0Db: esn0Db,
      snrDb: esn0Db + 10.0 * math.log(nc * fs6 / nf / _snBwHz) / math.ln10,
      iterations: out.iterations,
      coherence: coh,
      symbols: capture,
      bps: l.isQam ? l.layout.bps : 2,
    );
  }

  (List<double>, double) _dpskLlr(List<List<Cx>> c, Cx s, List<Cx>? capture) {
    final int nc = l.nc;
    final Cx rot = unit(s.conj());
    final List<List<Cx>> d = eqDiff(c, c.length, nc, rot);
    final double nvar = dpskNvar(d, 1e-30, _markers.map((m) => (m.row - 1, m.carrier)));
    final List<Cx> cst = fmConstellation(2);
    final List<double> llr = <double>[];
    for (int b = 0; b < nc; b++) {
      final List<Cx> obs = <Cx>[
        for (int r = 1; r < c.length; r++)
          if (!_map[b][r]) d[r - 1][b],
      ];
      capture?.addAll(obs);
      softBits(obs, cst, nvar, llr);
    }
    return (llr, 2.0 / nvar);
  }

  (List<double>, double) _qamLlr(List<List<Cx>> c0, List<Cx>? capture) {
    final int nc = l.nc, nsy = l.nsym;
    bool known(int b, int r) => fmQamPilot(_bins[b], r + 2) || _map[b][r];
    Cx v = Cx.zero;
    for (int b = 0; b < nc; b++) {
      for (int r = 0; r < math.max(nsy - fmPilotPeriod, 0); r++) {
        if (fmQamPilot(_bins[b], r + 2)) v = v + c0[r][b].conj() * c0[r + fmPilotPeriod][b];
      }
    }
    final double thd = v.arg / fmPilotPeriod;
    final List<List<Cx>> c = c0.map((row) => List<Cx>.of(row)).toList();
    derotate(c, thd);
    final List<Cx> cst = fmConstellation(l.layout.bps);
    final double es = cst.fold<double>(0.0, (a, z) => a + z.normSqr) / cst.length;
    final Equaliser e = Equaliser();
    for (int b = 0; b < nc; b++) {
      final List<int> ks = <int>[for (int r = 0; r < nsy; r++) if (known(b, r)) r];
      final List<Cx> hs = ks.map((r) => c[r][b]).toList();
      for (int r = 0; r < nsy; r++) {
        if (!known(b, r)) e.push(c[r][b], r.toDouble(), ks, hs);
      }
    }
    final List<double> llr = <double>[];
    final double nvar = e.llrs(cst, 1e-4, llr);
    capture?.addAll(e.symbols);
    return (llr, es / nvar);
  }
}

class FmRxStats {
  final DecodeStats decode = DecodeStats();
  int discarded = 0;
  int tx = 0;
  int unexpectedFrame2 = 0;
}

class FmReceiver with Assemble<FmCtrlEvent, FmRecord, FmFrameRx, void, void> {
  FmBandwidth bw;
  int _key;
  final FrontEnd _fe = FrontEnd();
  final SampleTrack _buf = SampleTrack((_bufSeconds * fs6).toInt(), stride: 2);
  final Stft _stft = Stft(fmMaxSpf + 1);
  final Map<FmRecord, OfdmEngine> _engines = <FmRecord, OfdmEngine>{};
  final Assembly<FmRecord, FmFrameRx, void> _asm;
  final Muted _muted = Muted();
  final List<CtrlDetector?> _ctrl = <CtrlDetector?>[null, null];
  FmCodec _codec;
  int? _probed;
  final FmRxStats stats = FmRxStats();

  /// When true, decoded frames carry their symbols and are queued in [captured].
  bool captureSymbols = false;
  final List<FmFrameRx> captured = <FmFrameRx>[];

  FmReceiver(this.bw, int key, List<FmRecord> records, int nframes)
      : _key = key,
        _asm = Assembly<FmRecord, FmFrameRx, void>(nframes),
        _codec = FmCodec(bw) {
    expect(records, nframes);
  }

  int get key => _key;

  @override
  int get pairTol => symLen ~/ 2;
  @override
  bool get emitBad => false;
  @override
  bool get closeOnMiss => true;
  @override
  bool get lostNeedsOk => true;
  @override
  Assembly<FmRecord, FmFrameRx, void> get asm => _asm;
  @override
  SampleTrack get track => _buf;

  OfdmEngine _engine(FmRecord record) {
    final OfdmEngine e = OfdmEngine(
        bw.level(record), fmCodeTables(bw)[record.index].other, phasors(recordKey(record, _key)));
    final int spanHops = e.span ~/ ofdmHop;
    e.startAt(math.max(_stft.diff.base, _stft.diff.end - spanHops - fs6.toInt() ~/ ofdmHop));
    return e;
  }

  void expect(List<FmRecord> records, [int? nframes]) {
    for (final FmRecord r in records) {
      _engines.putIfAbsent(r, () => _engine(r));
    }
    _engines.removeWhere((r, _) => !records.contains(r));
    if (nframes != null) _asm.nframes = nframes;
  }

  List<FmRecord> get expected => (_engines.keys.toList()..sort((a, b) => a.index - b.index));

  void setKey(int key) {
    if (key == _key) return;
    _key = key;
    for (final FmRecord r in _engines.keys.where((r) => r.keyed).toList()) {
      _engines[r] = _engine(r);
    }
  }

  void setBandwidth(FmBandwidth b) {
    if (b == bw) return;
    bw = b;
    _codec = FmCodec(b);
    final List<FmRecord> recs = expected;
    _engines.clear();
    expect(recs);
  }

  void setCtrl(Side side, Codebook? cb, List<int> codes) {
    final int start = math.max(_buf.base, _buf.end - 40 * 128);
    final CtrlDetector? slot = _ctrl[side.idx];
    if (cb == null) {
      _ctrl[side.idx] = null;
    } else if (slot != null) {
      if (slot.codebook != cb) slot.codebook = cb;
      slot.setEnabled(codes);
    } else {
      _ctrl[side.idx] = CtrlDetector(cb, codes)..startAt(start);
    }
  }

  void mute(int a48, int b48) => _muted.mute(_buf, fs6, a48 ~/ dec, b48 ~/ dec);

  void markTxEnd(int n48) => _asm.txEnd48 = n48;

  List<FmEvent> feed(List<double> x) {
    final (int m0, Float64List y) = _fe.process(x);
    if (y.isNotEmpty) _buf.append(m0, y);
    final List<FmEvent> ev = <FmEvent>[];
    for (final Side side in Side.values) {
      final CtrlDetector? c = _ctrl[side.idx];
      if (c != null) {
        for (final CtrlDetection d in c.step(_buf)) {
          ev.add(CtrlEv<FmCtrlEvent, FmRecord, FmFrameRx>(FmCtrlEvent(d, side)));
        }
      }
    }
    _stft.update(_buf);
    final List<FmDetection> dets = <FmDetection>[
      for (final FmRecord r in expected) ..._engines[r]!.step(_stft),
    ];
    dets.sort((a, b) {
      if (a.t != b.t) return a.t.compareTo(b.t);
      final int m = totalCmp(b.metric, a.metric);
      return m != 0 ? m : a.record.index - b.record.index;
    });
    for (final FmDetection d in dets) {
      ev.addAll(onDet(d.record, d.t, null));
    }
    ev.addAll(_pending());
    return ev;
  }

  List<FmEvent> flush() => finalize();

  double noiseFloor() {
    final List<double>? p = _muted.quietBlocks(_buf, fs6, _noiseBlock);
    return p == null ? 0.0 : p[p.length ~/ 100];
  }

  bool _continues(int end) =>
      continuesAfter(_buf, (end + cp, end + _continueAt), (end - 2 * symLen, end - cp), noiseFloor());

  List<FmEvent> _pending() {
    final Pending<FmRecord, FmFrameRx, void>? cur = _asm.cur;
    if (cur == null) return <FmEvent>[];
    _asm.cur = null;
    if (!_engines.containsKey(cur.record)) return finish(cur);
    final int sp = span(cur.record);
    final int end1 = cur.t - cpMid + sp;
    if (!cur.two) {
      if (_buf.end < end1 + _continueAt) {
        _asm.cur = cur;
        return <FmEvent>[];
      }
      if (!(cur.frames[0].ok && cur.record != FmRecord.broadcast && _continues(end1))) return finish(cur);
      stats.unexpectedFrame2++;
      cur.two = true;
    }
    final int t2 = cur.t + sp;
    final FmRecord record = cur.record;
    final bool guessed = _asm.nframes != 2;
    if (guessed && _probed != t2) {
      final double? c = _engines[record]!.earlyCoherence(_buf, t2, _probeRows);
      if (c == null) {
        _asm.cur = cur;
        return <FmEvent>[];
      }
      if (c < minCoherence) return finish(cur);
      _probed = t2;
    }
    _asm.cur = cur;
    if (_buf.end < t2 + sp + _grace) return <FmEvent>[];
    final FmFrameRx? r = decode(record, t2, 1, null);
    if (r != null && (!guessed || r.ok || r.coherence >= minCoherence)) {
      return close(r, false, <FmEvent>[]);
    }
    return finalize();
  }

  @override
  bool has(FmRecord record) => _engines.containsKey(record);

  @override
  int span(FmRecord record) => bw.level(record).nsym * symLen;

  @override
  FmFrameRx? decode(FmRecord record, int t, int index, void hint) {
    final OfdmEngine? e = _engines[record];
    if (e == null) return null;
    final FmFrameRx? r = e.decode(_buf, _codec, t, index, captureSymbols ? <Cx>[] : null);
    if (r != null) stats.decode.count(r.ok);
    if (r != null && captureSymbols) {
      if (captured.length >= 8) captured.removeAt(0);
      captured.add(r);
    }
    return r;
  }

  @override
  bool pairs(Pending<FmRecord, FmFrameRx, void> cur, FmRecord record) => record != FmRecord.broadcast;

  @override
  int frame1End(Pending<FmRecord, FmFrameRx, void> cur) => cur.t + span(cur.record);

  @override
  FmFrameRx? lost(FmRecord record, int back, int t, int sp) {
    final int? te48 = _asm.txEnd48;
    if (te48 == null) return null;
    final int te = te48 ~/ dec;
    if (back - cpMid < te) return null;
    return FmFrameRx(record: record, t: back, tEnd: back - cpMid + sp, missing: true);
  }

  @override
  bool keep(FmFrameRx r) {
    final bool k = r.ok || r.coherence >= minCoherence;
    if (!k) stats.discarded++;
    return k;
  }

  @override
  void wait(FmRecord record, FmFrameRx r, void hint) {}

  @override
  int expectedFrames(Pending<FmRecord, FmFrameRx, void> cur) => math.max(_asm.nframes, 1);

  @override
  void finished(List<FmFrameRx> frames) => stats.tx++;
}
