/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/xara-modem/xara), crates/xara-phy/src/busy.rs
and crates/xara-phy/src/hf/rx/frontend.rs. Copyright (c) the XARA authors, MIT License.

Channel-busy detector: a strong-tone detector and a PSK carrier-signature
detector on the HF baseband, with a hang time after the last hit.
*/

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'dsp.dart';
import 'hf_level.dart';
import 'numeric.dart';
import 'ofdm_const.dart' as ofdm;

const int hang = 34;
const double tonePeakRatio = 270.0;
const double vuGateDbfs = -46.0;
const double signaturePowerGate = 1e6;
const int _rows = 20;
const double _fullScale = 32767.0;
const double _centerHz = 1500.0;

/// HF receive front end: 48 kHz real audio to 3 kHz complex baseband.
class HfFrontEnd {
  static const int _n1 = 33;
  static const int _n2 = 273;
  static const int _d1 = (_n1 - 1) ~/ 2;
  static const int _d2 = (_n2 - 1) ~/ 2;

  final List<double> _h1 = kaiserLowpass(_n1, 6000.0, ofdm.fs, 5.65);
  final List<double> _h2 = kaiserLowpass(_n2, 1520.0, ofdm.fs / 4.0, 5.65);
  int _nIn = 0;
  final Track<Cx> _z = Track<Cx>(8192);
  int _stage1Next = 0;
  final Track<Cx> _u = Track<Cx>(8192);
  int _outNext = 0;
  final List<Cx> _mix = List<Cx>.generate(32, (n) => Cx.polar(1.0, -math.pi * n / 16.0));

  (int, List<Cx>) process(List<double> x) {
    final int n0 = _nIn;
    _nIn += x.length;
    _z.append(_z.end, <Cx>[for (int i = 0; i < x.length; i++) _mix[(n0 + i) % 32].scale(x[i])]);
    final int kHi = floorDiv(_nIn - 1 - _d1, 4);
    if (kHi >= _stage1Next) {
      _u.append(_stage1Next, <Cx>[for (int k = _stage1Next; k <= kHi; k++) _fir(_z, _h1, 4 * k - _d1)]);
      _stage1Next = kHi + 1;
    }
    final int mHi = floorDiv(_stage1Next - 1 - _d2, 4);
    final int m0 = _outNext;
    if (mHi < m0) return (m0, const <Cx>[]);
    final List<Cx> b3 = <Cx>[
      for (int m = m0; m <= mHi; m++) _fir(_u, _h2, 4 * m - _d2).scale(m.isOdd ? -2.0 : 2.0),
    ];
    _outNext = mHi + 1;
    return (m0, b3);
  }

  static Cx _fir(Track<Cx> t, List<double> h, int start) {
    double re = 0.0, im = 0.0;
    for (int i = 0; i < h.length; i++) {
      final int n = start + i;
      if (n >= t.base) {
        final Cx v = t.buf[n - t.base];
        re += v.re * h[i];
        im += v.im * h[i];
      }
    }
    return Cx(re, im);
  }
}

(int, int, int) toneBand(HfBandwidth bw) => switch (bw) {
      HfBandwidth.hz500 => (54, 74, 4),
      HfBandwidth.hz2300 => (21, 107, 14),
      HfBandwidth.hz2750 => (16, 112, 17),
    };

(int, int) signatureBand(HfBandwidth bw) => switch (bw) {
      HfBandwidth.hz500 => (27, 37),
      HfBandwidth.hz2300 => (15, 49),
      HfBandwidth.hz2750 => (10, 54),
    };

double signatureThreshold(HfBandwidth bw) => bw == HfBandwidth.hz500 ? 3.1 : 2.0;

class Signature {
  final HfRecord record;
  final List<int> carriers;
  final List<int> gaps;

  const Signature(this.record, this.carriers, this.gaps);

  @override
  bool operator ==(Object other) =>
      other is Signature &&
      other.record == record &&
      _same(other.carriers, carriers) &&
      _same(other.gaps, gaps);

  @override
  int get hashCode => Object.hash(record, Object.hashAll(carriers), Object.hashAll(gaps));

  @override
  String toString() => 'Signature(${record.value}, $carriers, $gaps)';

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

int _bin(double hz) => roundTiesEven(hz / ofdm.binHz).toInt();

(List<int>, List<int>) signature(List<int> fc0) {
  final List<double> fc = fc0.map((f) => f.toDouble()).toList();
  final int nc = fc.length;
  final List<int> car = <int>[0, 0, 0, 0], gap = <int>[0, 0, 0];
  if (nc.isEven) {
    final int h = nc ~/ 2;
    gap[0] = _bin(_centerHz);
    car[0] = _bin(fc[h - 1]);
    car[1] = _bin(fc[h]);
    if (nc > 3) {
      car[2] = _bin(fc[h - 2]);
      car[3] = _bin(fc[h + 1]);
      gap[1] = _bin((fc[h - 2] + fc[h - 1]) * 0.5);
      gap[2] = _bin((fc[h] + fc[h + 1]) * 0.5);
    }
  } else {
    final int c = (nc - 1) ~/ 2;
    gap[0] = _bin((fc[c - 1] + _centerHz) * 0.5);
    car[0] = _bin(_centerHz);
    car[1] = _bin(fc[c - 1]);
    if (nc > 2) {
      gap[1] = _bin((fc[c + 1] + _centerHz) * 0.5);
      car[2] = _bin(fc[c + 1]);
    }
  }
  return (car, gap);
}

List<Signature> signatures(HfBandwidth bw) => <Signature>[
      for (final HfRecord r in HfRecord.all())
        if (bw.level(r).isPsk && bw.level(r).carriersHz.length >= 2)
          () {
            final (List<int> c, List<int> g) = signature(bw.level(r).carriersHz);
            return Signature(r, c, g);
          }(),
    ];

bool detectTone(List<double> power, HfBandwidth bw) {
  final (int lo, int hi, int rank) = toneBand(bw);
  final List<double> v = power.sublist(lo, hi + 1)..sort(totalCmp);
  return v[v.length - 1] > tonePeakRatio * v[rank - 1];
}

bool detectSignature(List<double> power, Signature sig, double threshold) {
  double at(int b, int sh) => power[b + sh];
  double best = 0.0;
  int shift = 0;
  for (int sh = -1; sh <= 1; sh++) {
    double tot = 0.0;
    for (final int c in sig.carriers) {
      if (c > 0) tot += at(c, sh);
    }
    if (best <= tot) {
      best = tot;
      shift = sh;
    }
  }
  double maxGap = 0.0;
  for (final int g in sig.gaps) {
    if (g > 0) maxGap = math.max(maxGap, at(g, shift));
  }
  double minCarrier = double.infinity;
  for (final int c in sig.carriers) {
    if (c > 0) minCarrier = math.min(minCarrier, at(c, shift));
  }
  return maxGap > 0.0 && minCarrier / maxGap > threshold;
}

class Busy {
  HfBandwidth _bw;
  List<Signature> _sigs;
  final HfFrontEnd _fe = HfFrontEnd();
  final List<Cx> _block = <Cx>[];
  final ListQueue<Cx> _last64 = ListQueue<Cx>();
  int _sinceSignature = 0;
  final ListQueue<Float64List> _rowsQ = ListQueue<Float64List>();
  double _peak = 0.0;
  double _vu = -200.0;
  int _hang = 0;
  bool _on = false;
  final List<int> hits = <int>[0, 0];
  final Float64List _re128 = Float64List(128), _im128 = Float64List(128);
  final Float64List _re64 = Float64List(64), _im64 = Float64List(64);

  Busy(HfBandwidth bw)
      : _bw = bw,
        _sigs = signatures(bw);

  factory Busy.fm() => Busy(HfBandwidth.hz2750);

  bool get isOn => _on;

  void setBw(HfBandwidth bw) {
    if (bw != _bw) {
      _bw = bw;
      _sigs = signatures(bw);
    }
  }

  List<bool> feed(List<double> x, bool forced) {
    final List<bool> edges = <bool>[];
    if (forced) {
      _hang = hang;
      _set(true, edges);
    }
    for (final double v in x) {
      _peak = math.max(_peak, v.abs());
    }
    final (_, List<Cx> bb) = _fe.process(x);
    for (final Cx z0 in bb) {
      final Cx z = z0.scale(_fullScale);
      if (_last64.length == 64) _last64.removeFirst();
      _last64.addLast(z);
      _sinceSignature++;
      if (_sinceSignature == 32) {
        _sinceSignature = 0;
        if (_last64.length == 64 && _signatureHit() && !forced) {
          hits[1]++;
          _hang = hang;
          _set(true, edges);
        }
      }
      _block.add(z);
      if (_block.length == 128) {
        final bool hit = _toneHit();
        _block.clear();
        if (forced) continue;
        if (_hang > 0) {
          _hang--;
          if (_hang == 0) _set(false, edges);
        }
        if (hit) {
          hits[0]++;
          _hang = hang;
          _set(true, edges);
        }
      }
    }
    return edges;
  }

  void _set(bool on, List<bool> edges) {
    if (_on != on) {
      _on = on;
      edges.add(on);
    }
  }

  bool _toneHit() {
    final double peakDb = 20.0 * math.log(math.max(_peak, 1e-12)) / math.ln10;
    _vu = math.max(peakDb, _vu - 1.0);
    _peak = 0.0;
    if (_vu <= vuGateDbfs) return false;
    for (int i = 0; i < 128; i++) {
      _re128[i] = _block[i].re;
      _im128[i] = _block[i].im;
    }
    Fft.plan(128).transform(_re128, _im128);
    final List<double> p = List<double>.generate(128, (k) => _re128[k] * _re128[k] + _im128[k] * _im128[k]);
    return detectTone(p, _bw);
  }

  bool _signatureHit() {
    int i = 0;
    for (final Cx z in _last64) {
      _re64[i] = z.re;
      _im64[i] = z.im;
      i++;
    }
    Fft.plan(64).transform(_re64, _im64);
    final Float64List row = Float64List(64);
    for (int k = 0; k < 64; k++) {
      row[k] = _re64[k] * _re64[k] + _im64[k] * _im64[k];
    }
    final (int lo, int hi) = signatureBand(_bw);
    double sum = 0.0;
    for (int k = lo; k <= hi; k++) {
      sum += row[k];
    }
    final double mean = sum / (hi - lo + 1);
    if (_rowsQ.length == _rows) _rowsQ.removeFirst();
    _rowsQ.addLast(row);
    if (mean < signaturePowerGate || _rowsQ.length < _rows) return false;
    final Float64List s = Float64List(64);
    for (final Float64List r in _rowsQ) {
      for (int k = 0; k < 64; k++) {
        s[k] += r[k];
      }
    }
    final double threshold = signatureThreshold(_bw);
    return _sigs.any((g) => detectSignature(s, g, threshold));
  }
}
