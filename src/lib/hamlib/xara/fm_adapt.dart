/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM rate adaptation: queue hints, SNR margins and the ACK decision table.
*/

import 'arq_host.dart';
import 'arq_util.dart';
import 'fm_ctrl.dart';
import 'fm_frame.dart';
import 'fm_level.dart';
import 'textcomp.dart';

const double snrOffsetDb = -3.5;
const int hintMax = 7;

int payload(FmBandwidth bw, FmRecord record, bool vias) {
  final int? p = payloadLen(record, bw.level(record).frameBytes, vias);
  if (p == null) throw StateError('level frame too short');
  return p;
}

double thr(FmBandwidth bw, FmRecord record) => dec1(bw.level(record).snrThrDb);

double widePenalty(FmBandwidth bw, FmRecord record) => dec1(bw.level(record).widePenaltyDb);

int decodeAllow(FmBandwidth bw, FmRecord record) => bw.level(record).decodeAllow;

int frameTicks(FmBandwidth bw, FmRecord record) => bw.level(record).frameTicks;

DataLevel qamCap(FmBandwidth bw) {
  DataLevel best = DataLevel.one;
  bool any = false;
  for (final DataLevel l in bw.levels) {
    if (bw.dataLevel(l).layout.bps < 7 && (!any || l.value > best.value)) {
      best = l;
      any = true;
    }
  }
  return best;
}

DataLevel asLevel(FmRecord record) => record.level ?? DataLevel.one;

const List<(int, int)> _up = <(int, int)>[(1, 4), (2, 5), (3, 6), (6, 7)];

int _hintBy(FmBandwidth bw, FmRecord record, bool Function(FmRecord r, int k) fits) {
  final int i = record == FmRecord.start ? 1 : record.index;
  return queueHintBy(i, bw.numLevels, <HintRow>[(0, 2, _up), (1, 3, _up.sublist(0, 3))], hintMax, (i, k) {
    final FmRecord? r = FmRecord.fromIndex(i);
    return r != null && fits(r, k);
  });
}

int queueHint(FmBandwidth bw, FmRecord record, int q, bool vias) =>
    _hintBy(bw, record, (l, k) => q <= k * payload(bw, l, vias));

int queueHintText(FmBandwidth bw, FmRecord record, List<int> queued, int state, bool vias) =>
    _hintBy(bw, record, (l, k) {
      final int p = payload(bw, l, vias);
      return fitsFrames(queued, k, p, p, state);
    });

/// Margins for staying (0) and climbing 1, 2, 3 and 6 levels.
typedef Margins = List<double>;

const List<double> _margin = <double>[1.0, 0.5, 0.0, 0.0];
const List<int> steps = <int>[0, 1, 2, 3, 6];
const List<double> _pen = <double>[0.5, 0.5, 1.0, 2.0, 3.0];

double _fmin(double a, double b) {
  if (a.isNaN) return b;
  if (b.isNaN) return a;
  return a < b ? a : b;
}

class Adaptation {
  final List<double> _hist = List<double>.filled(4, noSnr, growable: true);
  int nGood = 0;
  bool climbFail = false;
  int maxLevel = 0;
  int prevMax = 0;
  int good = 0;
  int lost = 0;

  double ratio() => lost == 0 ? 100.0 : good / lost;

  double frameOk(double snr, DataLevel l0, int n) {
    final int l = l0.value > n ? 1 : l0.value;
    _hist.removeAt(0);
    _hist.add(snr);
    if (nGood < 4) nGood++;
    if (maxLevel < l) {
      maxLevel = l;
      if (l > 1) prevMax = l - 1;
    }
    good++;
    return held();
  }

  double held() => _hist.fold(double.infinity, _fmin);

  void frameLost() {
    climbFail = true;
    lost++;
  }
}

Margins margins(FmBandwidth bw, Adaptation ad, DataLevel l0, double s) {
  final int n = bw.numLevels;
  final DataLevel l = l0.value > n ? DataLevel.one : l0;
  final double a = ad.nGood > 0 ? _margin[ad.nGood - 1] : _margin[3];
  final List<double> m = List<double>.filled(5, 0.0);
  for (int i = 0; i < steps.length; i++) {
    final int d = steps[i];
    final bool room = switch (d) {
      0 => true,
      6 => l.value + 5 < n,
      _ => l.value + d - 1 < n,
    };
    final DataLevel? up = room ? l.up(d) : null;
    double v = 0.0;
    if (up != null) {
      final double pen =
          d > 0 ? widePenalty(bw, FmRecord.data(up)) - widePenalty(bw, FmRecord.data(l)) : 0.0;
      v = s - thr(bw, FmRecord.data(up)) - _pen[i] - pen;
    }
    m[i] = v - a;
  }
  if (ad.climbFail) {
    m[2] = 0.0;
    m[3] = 0.0;
    m[4] = 0.0;
  }
  if (bw == FmBandwidth.narrow) {
    final DataLevel cap = qamCap(bw);
    for (int i = 2; i < 5; i++) {
      if (l.value + steps[i] > cap.value) m[i] = 0.0;
    }
  }
  if (l.value < n) {
    final double x = ad.ratio();
    final bool block = (x < 12.0 && l.value >= ad.maxLevel) ||
        (l.value + 1 == ad.maxLevel && x < 10.0) ||
        (l.value + 1 == ad.prevMax && x < 8.0) ||
        x < 6.0;
    if (block) {
      for (int i = 1; i < 5; i++) {
        m[i] = 0.0;
      }
    }
  }
  return m;
}

class Decision {
  final int code;
  final FmRecord level;
  final bool stayReset;
  final double held;
  final Margins m;

  const Decision(this.code, this.level, this.stayReset, this.held, this.m);
}

const DataLevel _unregisteredTop = DataLevel(2);

DataLevel maxLevel(FmBandwidth bw, bool registered) => registered ? bw.topLevel : _unregisteredTop;

class Heard {
  final FmRecord record;
  final int hint;
  final bool complete;

  const Heard(this.record, this.hint, this.complete);
}

Decision frameOkAndDecide(FmBandwidth bw, Adaptation ad, Heard h, double snr, bool registered) {
  final double s = ad.frameOk(snr, asLevel(h.record), bw.numLevels);
  return decide(bw, ad, h, s, registered);
}

Decision decide(FmBandwidth bw, Adaptation ad, Heard h, double s, bool registered) {
  final DataLevel top = maxLevel(bw, registered);
  final bool was15 = h.record == FmRecord.start;
  final DataLevel l = asLevel(h.record);
  final Margins m = margins(bw, ad, l, s);
  Decision d(int code, FmRecord level, bool stayReset) => Decision(code, level, stayReset, s, m);
  for (final (int i, int code, int need) in const <(int, int, int)>[
    (4, FmCode.ackUp6, 7),
    (3, FmCode.ackUp3, 6),
    (2, FmCode.ackUp2, 5),
    (1, FmCode.ackUp1, 4),
  ]) {
    final DataLevel? up = l.up(steps[i]);
    if (up != null && h.complete && up.value <= top.value && m[i] > 0.0 && h.hint >= need) {
      return d(code, FmRecord.data(up), true);
    }
  }
  if (!h.complete) return d(FmCode.ackSecondOnly, FmRecord.data(l.down()), false);
  if (l.value > 1 && h.hint == 0) return d(FmCode.ackDown, FmRecord.data(l.down()), true);
  if (l.value > 1 && (h.hint == 1 || m[0] < 0.0)) return d(FmCode.ackDown, FmRecord.data(l.down()), false);
  return d(FmCode.ackStay, was15 ? FmRecord.short : FmRecord.data(l), h.hint == 2);
}

FmRecord senderLevelAfter(FmRecord record, int code) {
  DataLevel l;
  if (record == FmRecord.start && code == FmCode.ackStay) return FmRecord.short;
  if (record == FmRecord.start || record == FmRecord.short) {
    l = DataLevel.one;
  } else if (record.dataLevel != null) {
    l = record.dataLevel!;
  } else {
    return record;
  }
  FmRecord up(int d) => FmRecord.fromIndex(l.value + d) ?? FmRecord.data(DataLevel.max);
  return switch (code) {
    FmCode.ackUp6 => up(6),
    FmCode.ackUp3 => up(3),
    FmCode.ackUp2 => up(2),
    FmCode.ackUp1 => up(1),
    FmCode.nack || FmCode.ackDown || FmCode.ackSecondOnly || FmCode.ackFirstOnly => FmRecord.data(l.down()),
    _ => FmRecord.data(l),
  };
}

DataLevel stepDown(FmRecord record) => asLevel(record).down();

DataLevel? recommendLevel(FmBandwidth bw, Adaptation ad, bool registered) {
  final double s = ad.held();
  DataLevel top = maxLevel(bw, registered);
  if (bw == FmBandwidth.narrow && qamCap(bw).value < top.value) top = qamCap(bw);
  final FmRecord one = FmRecord.data(DataLevel.one);
  for (int v = top.value; v >= 1; v--) {
    final FmRecord r = FmRecord(v);
    if (s - thr(bw, r) - (widePenalty(bw, r) - widePenalty(bw, one)) > 3.0) return DataLevel(v);
  }
  return null;
}
