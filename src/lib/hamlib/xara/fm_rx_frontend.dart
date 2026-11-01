/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM receive front end (48 kHz real -> 6 kHz complex baseband) and the control
frame (three-tone codeword) detector.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'fm_ctrl.dart';
import 'ofdm_const.dart';

const double fs6 = 6000.0;
const int dec = 8;
const int nf = nfft ~/ dec;
const int cp = ncp ~/ dec;
const int symLen = nf + cp;

int to48(int m) => m * dec;

const int frontTaps = 481;
const int _d = (frontTaps - 1) ~/ 2;

/// Complex band-pass (centred on 3 kHz) and decimation by [dec].
class FrontEnd {
  final Float64List _hr = Float64List(frontTaps);
  final Float64List _hi = Float64List(frontTaps);
  final SampleTrack _x = SampleTrack(4 * frontTaps);
  int _outNext = 0;

  FrontEnd() {
    final List<double> lp = kaiserLowpass(frontTaps, 3000.0, fs, 6.76);
    for (int i = 0; i < frontTaps; i++) {
      final double a = 2.0 * math.pi * 3000.0 * (i - _d) / fs;
      _hr[i] = lp[i] * math.cos(a);
      _hi[i] = lp[i] * math.sin(a);
    }
  }

  /// Returns the absolute 6 kHz index of the first output sample and the
  /// outputs as interleaved (re, im).
  (int, Float64List) process(List<double> x) {
    _x.append(_x.end, x);
    final int m0 = _outNext;
    final int mHi = floorDiv(_x.end - 1 - _d, dec);
    final int n = mHi >= m0 ? mHi - m0 + 1 : 0;
    final Float64List out = Float64List(2 * n);
    final int base = _x.base;
    for (int o = 0; o < n; o++) {
      final int c = dec * (m0 + o) + _d;
      double ar = 0.0, ai = 0.0;
      for (int i = 0; i < frontTaps; i++) {
        final int k = c - i;
        if (k >= base) {
          final double v = _x.at(k);
          ar += _hr[i] * v;
          ai += _hi[i] * v;
        }
      }
      out[2 * o] = ar;
      out[2 * o + 1] = ai;
    }
    _outNext = m0 + n;
    return (m0, out);
  }
}

const int ctrlHop = 16;
const int ctrlRow = 8;
const int minHits = 18;
const int noLeadHits = 22;
const int ctrlHold = 4;
const int _top = 64;
const int _span = ctrlRow * (codeRows - 1);
const int _keep = 8 * (leadRows + codeRows + 4);

class CtrlDetection {
  final int code;
  final int hits;
  final int leadRow;
  final int tEnd;

  const CtrlDetection(this.code, this.hits, this.leadRow, this.tEnd);
}

class _Spec {
  final Float32List power = Float32List(_top);
  final Uint8List peak = Uint8List(_top);
}

class _Best {
  final double energy;
  final int j;
  final int code;
  final int hits;

  const _Best(this.energy, this.j, this.code, this.hits);
}

class CtrlDetector {
  Codebook codebook;
  List<int> _enabled;
  final FftWindow _win = FftWindow(nf);
  final Track<_Spec> _spec = Track<_Spec>(_keep);
  int _stftNext = 0;
  int _erased = -0x8000000000000000;
  _Best? _best;
  int _hold = 0;

  CtrlDetector(this.codebook, List<int> enabled) : _enabled = List<int>.of(enabled);

  void setEnabled(List<int> enabled) {
    _enabled = List<int>.of(enabled);
    _best = null;
    _hold = 0;
  }

  void startAt(int m) => _stftNext = math.max(_stftNext, floorDiv(m, ctrlHop));

  _Spec _spectrum(SampleTrack buf, int j) {
    _win.at(buf, j * ctrlHop, nf);
    final _Spec s = _Spec();
    for (int k = 0; k < _top; k++) {
      s.power[k] = _win.re[k] * _win.re[k] + _win.im[k] * _win.im[k];
    }
    for (int b = codeBlock0; b < codeBlock0 + 7 * ctrlBlock; b += ctrlBlock) {
      double m = 0.0;
      for (int i = 0; i < ctrlBlock; i++) {
        if (s.power[b + i] > m) m = s.power[b + i];
      }
      for (int i = 0; i < ctrlBlock; i++) {
        s.peak[b + i] = m > 0.0 && s.power[b + i] == m ? 1 : 0;
      }
    }
    return s;
  }

  _Spec? _row(int j) => j > _erased && _spec.contains(j) ? _spec.at(j) : null;

  (int, double)? _correlate(int j, Codeword cw) {
    int hits = 0;
    double energy = 0.0;
    for (int r = 0; r < cw.length; r++) {
      final _Spec? s = _row(j - ctrlRow * (codeRows - 1 - r));
      if (s == null) continue;
      for (final int k in cw[r]) {
        energy += s.power[k];
        hits += s.peak[k];
      }
    }
    return hits >= minHits ? (hits, energy) : null;
  }

  int _leadRow(int j) {
    int start = 0, run = 0;
    for (int r = 1; r <= leadRows; r++) {
      final int jj = j - _span - ctrlRow * (noLeadRow - r);
      final _Spec? s = _row(jj);
      final bool ok = s != null && leadIn[r - 1].every((k) => s.peak[k] == 1);
      if (ok) {
        if (start == 0) start = r;
        run++;
        if (run == 4) break;
      } else {
        start = 0;
        run = 0;
      }
    }
    return start == 0 ? noLeadRow : start;
  }

  List<CtrlDetection> step(SampleTrack buf) {
    final int jHi = floorDiv(buf.end - nf, ctrlHop);
    _stftNext = math.max(_stftNext, floorDiv(buf.base + ctrlHop - 1, ctrlHop));
    final List<CtrlDetection> out = <CtrlDetection>[];
    while (_stftNext <= jHi) {
      final int j = _stftNext;
      _spec.append(j, <_Spec>[_spectrum(buf, j)]);
      _stftNext++;
      for (final int c in _enabled) {
        final (int, double)? hit = _correlate(j, codebook.code(c));
        if (hit != null && (_best == null || hit.$2 >= _best!.energy)) {
          _best = _Best(hit.$2, j, c, hit.$1);
          _hold = ctrlHold;
        }
      }
      if (_hold > 0) {
        _hold--;
      } else if (_best != null) {
        final _Best b = _best!;
        _best = null;
        final int lead = _leadRow(b.j);
        if (lead > leadRows && b.hits < noLeadHits) continue;
        out.add(CtrlDetection(b.code, b.hits, lead, b.j * ctrlHop + nf));
        _erased = j;
      }
    }
    return out;
  }
}
