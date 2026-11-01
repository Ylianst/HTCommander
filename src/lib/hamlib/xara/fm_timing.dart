/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM ARQ reply windows, in 128-sample ticks.
*/

import 'dart:collection';

import 'arq_host.dart';
import 'arq_time.dart';
import 'fm_adapt.dart';
import 'fm_level.dart';

const int tick = 128;
const int codeGate = 80;
const int detectHold = 4;
const int idleDataWait = 101;
const int fqWaitReplies = 4;

const List<double> _viaAckAdd = <double>[250.0, 353.5533905932738, 433.0127018922193];
const List<double> _viaCtrlAdd = <double>[75.0, 433.0127018922193, 559.0169943749474];
const List<double> _viaSpan = <double>[246.49999999999997, 739.4999999999999, 1232.4999999999998];
const List<double> _viaGates = <double>[80.0, 160.0, 240.0];
const double _directConnectSpan = 326.5;
const double _syncSlack = 520.0;
const double _activeScanSlack = 60.0;
const List<double> _backoff = <double>[846.5, 1499.5, 2152.5];
const List<int> _watchdogMs = <int>[16400, 22400, 31400];
// Deviates from VARA behaviour.
const int _recent = 8;
const int missTicks = 38;
const int _missLimit = 4;

int _v(int vias) => vias < 2 ? vias : 2;

int watchdog(int vias) => _watchdogMs[_v(vias)] * second ~/ 1000;

int state2Backoff(int vias, int mult) => rint(_backoff[_v(vias)] * mult);

int callerConnectWindow(FmBandwidth bw, int vias, bool activeScan) {
  final double u = (decodeAllow(bw, FmRecord.connect) - codeGate).toDouble();
  final double f = frameTicks(bw, FmRecord.connect).toDouble();
  final double x = switch (vias) {
    0 => u + _directConnectSpan,
    1 => 2.0 * u + f + _viaSpan[1] + _viaGates[1],
    _ => 3.0 * u + 2.0 * f + _viaSpan[2] + _viaGates[2],
  };
  return rint(x + (activeScan ? _activeScanSlack : _syncSlack));
}

(double, double) receiverSyncWindow(FmBandwidth bw, FmRecord record, int vias, bool two) {
  final double f = frameTicks(bw, record).toDouble();
  final double u = decodeAllow(bw, record).toDouble();
  if (two) return (f - 40.0, 2.0 * f + _viaSpan[0] + _syncSlack);
  final double lo = (vias + 1.0) * f - 40.0;
  const double g = codeGate * 1.0;
  final double hi = switch (vias) {
    0 => f + _viaSpan[0] + _syncSlack,
    1 => (u - g) + 2.0 * f + _viaSpan[1] + _viaGates[0] + _syncSlack,
    _ => 2.0 * (u - g) + 3.0 * f + _viaSpan[2] + _viaGates[1] + _syncSlack,
  };
  return (lo, hi);
}

class _Recent {
  final ListQueue<int> _q = ListQueue<int>();

  int push(int ticks) {
    if (_q.length == _recent) _q.removeFirst();
    _q.add(ticks);
    return rint(_q.fold<int>(0, (a, b) => a + b) / _q.length);
  }
}

class Timing {
  final FmBandwidth _bw;
  final int _vias;
  final List<int> count = List<int>.filled(fmRecords, 0);
  final List<_Recent> _recentAcks = List<_Recent>.generate(fmRecords, (_) => _Recent());
  final List<int> mean = List<int>.filled(fmRecords, 0);
  final List<int> window = List<int>.filled(fmRecords, 0);
  int ctrlN = 0;
  final _Recent _ctrlRecent = _Recent();
  int ctrlMean = 0;
  int _ctrlWin = 0;
  int _misses = 0;

  Timing(this._bw, int vias) : _vias = _v(vias);

  int _ackWindow(int mean) => _vias == 0 ? mean + 250 : rint(mean + _viaAckAdd[_vias]);

  void ack(int ticks0, FmRecord record) {
    final FmBandwidth bw = _bw;
    final int v = _vias, i = record.index;
    final int ticks = record == FmRecord.connect && v > 0 ? rint(ticks0 + 40.0 * v) : ticks0;
    count[i]++;
    mean[i] = _recentAcks[i].push(ticks);
    _misses = 0;
    final int base = record.dataLevel?.value ?? 0;
    for (final DataLevel l in bw.levels.skip(base)) {
      if (count[l.value] != 0) break;
      final int du = decodeAllow(bw, FmRecord.data(l)) - decodeAllow(bw, record);
      final int df = frameTicks(bw, FmRecord.data(l)) - frameTicks(bw, record);
      mean[l.value] = mean[i] + <int>[du, df + 2 * du, 2 * df + 3 * du][v];
    }
    for (final FmRecord r in const <FmRecord>[FmRecord.short, FmRecord.start]) {
      if (count[r.index] == 0) mean[r.index] = mean[1];
    }
    for (int l = 1; l <= FmRecord.start.index; l++) {
      window[l] = _ackWindow(mean[l]);
    }
    if (_ctrlWin == 0) {
      final double fl = (frameTicks(bw, record) - 80).toDouble();
      final double m = mean[i].toDouble();
      _ctrlWin = rint(switch (v) {
        0 => m + 75.0,
        1 => m - fl + _viaCtrlAdd[1],
        _ => m - 2.0 * fl + _viaCtrlAdd[2],
      });
    }
  }

  void ctrl(int ticks) {
    final FmBandwidth bw = _bw;
    final int v = _vias;
    ctrlN++;
    ctrlMean = ctrlN == 1 ? ticks : _ctrlRecent.push(ticks);
    _misses = 0;
    _ctrlWin = v == 0 ? ctrlMean + 75 : rint(ctrlMean + _viaCtrlAdd[v]);
    if (ctrlN != 1) return;
    for (final DataLevel l in bw.levels) {
      final int i = l.value;
      if (window[i] != 0) break;
      final double u = (decodeAllow(bw, FmRecord.data(l)) - 80).toDouble();
      final double f = (frameTicks(bw, FmRecord.data(l)) - 80).toDouble();
      mean[i] = rint(<double>[u, 2.0 * u + f, 3.0 * u + 2.0 * f][v] + ctrlMean);
      window[i] = _ackWindow(mean[i]);
    }
    for (final FmRecord r in const <FmRecord>[FmRecord.short, FmRecord.start]) {
      if (window[r.index] == 0) window[r.index] = window[1];
    }
  }

  void miss() => _misses = _misses + 1 < _missLimit ? _misses + 1 : _missLimit;

  int dataWindow(FmRecord record) {
    int w = window[record.index];
    if (w == 0) {
      final DataLevel? l = record.level;
      w = _ackWindow(decodeAllow(_bw, l == null ? record : FmRecord.data(l)) + 300);
    }
    return w + _misses * missTicks;
  }

  int ctrlWindow() => (_ctrlWin == 0 ? 500 : _ctrlWin) + _misses * missTicks;
}
