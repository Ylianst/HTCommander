/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
HF (VARA HF) speed level definitions. f32 constants are held at f32 precision.
*/

import 'fec.dart';
import 'numeric.dart';
import 'ofdm_const.dart';

const int hfRecords = 17;
const int fskPilots = 24;
const int hfPilotPeriod = 8;
const int pskSps = 32;

/// HF record / speed level, 1-based (1..17).
extension type const HfRecord(int value) {
  static const HfRecord one = HfRecord(1);
  static const HfRecord max = HfRecord(hfRecords);

  static HfRecord? of(int n) => n >= 1 && n <= hfRecords ? HfRecord(n) : null;

  int get index => value - 1;

  HfRecord? up(int d) => of(value + d);

  HfRecord down() => value > 1 ? HfRecord(value - 1) : this;

  static HfRecord clamped(int n, HfRecord top) => HfRecord(n.clamp(1, top.value));

  static Iterable<HfRecord> range(HfRecord lo, HfRecord hi) sync* {
    for (int i = lo.value; i <= hi.value; i++) {
      yield HfRecord(i);
    }
  }

  static Iterable<HfRecord> all() => range(one, max);
}

enum HfBandwidth {
  hz500(500, 13),
  hz2300(2300, 16),
  hz2750(2750, 17);

  const HfBandwidth(this.hz, this.numLevels);

  final int hz;
  final int numLevels;

  static HfBandwidth? parse(String s) {
    for (final HfBandwidth b in values) {
      if (b.hz.toString() == s) return b;
    }
    return null;
  }

  (double, double) get passband {
    final double half = hz / 2.0;
    return (1500.0 - half, 1500.0 + half);
  }

  HfRecord get topLevel => HfRecord(numLevels);

  Iterable<HfRecord> get levels => HfRecord.range(HfRecord.one, topLevel);

  List<HfLevel> get table => switch (this) {
        HfBandwidth.hz500 => _bw500,
        HfBandwidth.hz2300 => _bw2300,
        HfBandwidth.hz2750 => _bw2750,
      };

  HfLevel level(HfRecord r) => table[r.index];

  double ampNorm(HfRecord r) => switch (this) {
        HfBandwidth.hz500 => _ampNorm500,
        HfBandwidth.hz2300 => _ampNorm2300,
        HfBandwidth.hz2750 => _ampNorm2750,
      }[r.index];
}

enum HfWaveKind { fsk, psk, ofdm }

class HfPulse {
  final bool rc;
  final double span;

  HfPulse.rc() : rc = true, span = toF32(0.5);
  HfPulse.rrc(double span) : rc = false, span = toF32(span);
}

class HfLevel {
  final HfWaveKind kind;
  final int bps;
  final int rate;
  final double snrThrDb;
  final double paprDb;
  final bool skipOnStepDown;
  final bool extra;
  final double snrCorrDb;
  final int k;

  // FSK fields.
  final int symbols;
  final int fskSps;
  final int first;
  final int last;
  final int step;

  // PSK / OFDM fields.
  final int spf0;
  final int markers0;
  final List<int> carriersHz;
  final HfPulse? pulse;
  final int ofdmNc;

  HfLevel._({
    required this.kind,
    required this.bps,
    required this.rate,
    required double thr,
    required double papr,
    required this.skipOnStepDown,
    required this.extra,
    required double snrCorr,
    required this.k,
    this.symbols = 0,
    this.fskSps = 0,
    this.first = 0,
    this.last = 0,
    this.step = 0,
    this.spf0 = 0,
    this.markers0 = 0,
    this.carriersHz = const <int>[],
    this.pulse,
    this.ofdmNc = 0,
  })  : snrThrDb = toF32(thr),
        paprDb = toF32(papr),
        snrCorrDb = toF32(snrCorr);

  HfLevel _with({bool? extra, double? snrCorr}) => HfLevel._(
        kind: kind,
        bps: bps,
        rate: rate,
        thr: snrThrDb,
        papr: paprDb,
        skipOnStepDown: skipOnStepDown,
        extra: extra ?? this.extra,
        snrCorr: snrCorr ?? snrCorrDb,
        k: k,
        symbols: symbols,
        fskSps: fskSps,
        first: first,
        last: last,
        step: step,
        spf0: spf0,
        markers0: markers0,
        carriersHz: carriersHz,
        pulse: pulse,
        ofdmNc: ofdmNc,
      );

  bool get isFsk => kind == HfWaveKind.fsk;
  bool get isPsk => kind == HfWaveKind.psk;
  bool get isOfdm => kind == HfWaveKind.ofdm;
  bool get isQam => isOfdm && bps >= 4;

  int get spf => isFsk ? symbols : spf0;

  int get sps => switch (kind) {
        HfWaveKind.fsk => fskSps,
        HfWaveKind.psk => pskSps,
        HfWaveKind.ofdm => 64,
      };

  int get nc => switch (kind) {
        HfWaveKind.fsk => 1,
        HfWaveKind.psk => carriersHz.length,
        HfWaveKind.ofdm => ofdmNc,
      };

  int get markers => isFsk ? fskPilots : markers0;

  int get dataCells {
    if (isFsk) return spf - 1 - fskPilots;
    if (isQam) {
      return nc * (spf - 1 - markers - ((spf - 3) ~/ hfPilotPeriod + 1));
    }
    return nc * (spf - 2 - markers);
  }

  int get puncturePeriodValue => puncturePeriod(rate);

  int get n => dataCells * bps;

  int get otherLen => isFsk ? 3 * (symbols - 1) + fskPilots : nc * (markers + spf - 1);

  int get pad => n - puncturedLen(k, puncturePeriod(rate));

  int get frameBytes => k ~/ 8;

  int get payload => frameBytes - 3;

  int get dataSymbols => spf - 1;

  double get symbolPeriod => sps * (isOfdm ? symRatio : 1.0) / 3000.0;

  int get leadIn {
    final double t = bps < 4 ? 0.080 : 0.120;
    return asU32((t / symbolPeriod - 1e-9).ceilToDouble());
  }

  int get flushSymbols => isPsk ? asU32((2.0 * pulse!.span).roundToDouble()) : 0;

  double get airtime => (leadIn + dataSymbols + flushSymbols) * symbolPeriod;

  double get netBps => (8 * frameBytes) / (dataSymbols * symbolPeriod);
}

List<int> datOffsets(HfBandwidth bw) {
  final List<int> out = List<int>.filled(hfRecords, 0);
  int p = 0;
  for (int i = 0; i < hfRecords; i++) {
    out[i] = p;
    final HfLevel l = bw.table[i];
    p += l.n + l.k + l.otherLen;
  }
  return out;
}

HfRecord qamLimit(HfBandwidth bw) {
  HfRecord best = HfRecord.one;
  for (final HfRecord r in HfRecord.all()) {
    if (!bw.level(r).isQam && r.value > best.value) best = r;
  }
  return best;
}

HfRecord startLevelMax(HfBandwidth bw) =>
    bw == HfBandwidth.hz500 ? const HfRecord(7) : const HfRecord(6);

final List<double> _ampNorm500 = const <double>[
  1.41, 1.41, 1.41, 0.61, 0.61, 1.22, 4.9678, 4.9678, 4.9678, 4.9678, 4.9678,
  4.21, 4.67, 0.61, 1.41, 4.67, 4.67,
].map(toF32).toList(growable: false);

final List<double> _ampNorm2300 = const <double>[
  1.41, 1.41, 1.41, 1.41, 0.75, 0.86, 1.73, 2.0, 2.23, 10.44435, 10.44435,
  10.44435, 10.44435, 10.44435, 8.82035, 10.01805, 4.67,
].map(toF32).toList(growable: false);

final List<double> _ampNorm2750 = const <double>[
  1.41, 1.41, 1.41, 1.41, 0.75, 0.86, 1.73, 2.0, 2.23, 2.5422, 11.4219,
  11.4219, 11.4219, 11.4219, 11.4219, 9.6459, 10.9557,
].map(toF32).toList(growable: false);

HfLevel _fsk({
  required int symbols,
  required int bps,
  required int rate,
  required int sps,
  required int first,
  required int last,
  required int step,
  required double thr,
  bool skip = false,
  required int k,
}) =>
    HfLevel._(
      kind: HfWaveKind.fsk,
      bps: bps,
      rate: rate,
      thr: thr,
      papr: 3.0,
      skipOnStepDown: skip,
      extra: false,
      snrCorr: 0.0,
      k: k,
      symbols: symbols,
      fskSps: sps,
      first: first,
      last: last,
      step: step,
    );

HfLevel _psk({
  required int spf,
  required int bps,
  required int markers,
  required List<int> fc,
  required HfPulse pulse,
  required double thr,
  required double papr,
  bool skip = false,
  required int k,
}) =>
    HfLevel._(
      kind: HfWaveKind.psk,
      bps: bps,
      rate: 3,
      thr: thr,
      papr: papr,
      skipOnStepDown: skip,
      extra: false,
      snrCorr: 0.0,
      k: k,
      spf0: spf,
      markers0: markers,
      carriersHz: List<int>.unmodifiable(fc),
      pulse: pulse,
    );

enum _O { o500, o2300, o2750 }

HfLevel _ofdm(
  _O base, {
  int spf = 150,
  required int bps,
  required int rate,
  required double thr,
  required double papr,
  bool skip = false,
  required int k,
}) {
  final (int markers, int nc, int first) = switch (base) {
    _O.o500 => (4, 11, 27),
    _O.o2300 => (1, 49, 8),
    _O.o2750 => (1, 59, 3),
  };
  return HfLevel._(
    kind: HfWaveKind.ofdm,
    bps: bps,
    rate: rate,
    thr: thr,
    papr: papr,
    skipOnStepDown: skip,
    extra: false,
    snrCorr: 0.0,
    k: k,
    spf0: spf,
    markers0: markers,
    ofdmNc: nc,
    first: first,
  );
}

HfLevel _extra(HfLevel l) => l._with(extra: true);
HfLevel _snrCorr(HfLevel l, double db) => l._with(snrCorr: db);

final HfPulse _rc = HfPulse.rc();
final HfPulse _rrc1 = HfPulse.rrc(1.0);
final HfPulse _rrc2 = HfPulse.rrc(2.0);

final HfLevel _ofdm500X = _extra(_snrCorr(
    _ofdm(_O.o500, spf: 51, bps: 5, rate: 6, thr: 5.4, papr: 8.7, k: 1704), -0.4));

final List<HfLevel> _bw500 = List<HfLevel>.unmodifiable(<HfLevel>[
  _fsk(symbols: 125, bps: 3, rate: 2, sps: 128, first: 54, last: 74, step: 2, thr: -13.6, k: 96),
  _fsk(symbols: 229, bps: 3, rate: 2, sps: 64, first: 27, last: 37, step: 1, thr: -11.2, skip: true, k: 200),
  _fsk(symbols: 227, bps: 3, rate: 3, sps: 64, first: 27, last: 37, step: 1, thr: -10.4, k: 297),
  _psk(spf: 394, bps: 1, markers: 18, fc: [1350, 1650], pulse: _rc, thr: -8.4, papr: 4.4, k: 368),
  _psk(spf: 395, bps: 2, markers: 18, fc: [1350, 1650], pulse: _rc, thr: -5.4, papr: 4.4, k: 744),
  _psk(spf: 376, bps: 2, markers: 12, fc: [1320, 1500, 1680], pulse: _rrc2, thr: -3.8, papr: 7.2, k: 1080),
  _ofdm(_O.o500, bps: 2, rate: 3, thr: -1.2, papr: 8.3, k: 1578),
  _ofdm(_O.o500, bps: 2, rate: 4, thr: 0.6, papr: 8.3, k: 2104),
  _ofdm(_O.o500, bps: 2, rate: 6, thr: 2.6, papr: 8.3, k: 2524),
  _ofdm(_O.o500, bps: 3, rate: 4, thr: 5.0, papr: 8.2, skip: true, k: 3160),
  _ofdm(_O.o500, bps: 3, rate: 6, thr: 6.4, papr: 8.2, k: 3792),
  _snrCorr(_ofdm(_O.o500, spf: 155, bps: 4, rate: 7, thr: 8.0, papr: 8.2, k: 4755), -1.59),
  _snrCorr(_ofdm(_O.o500, spf: 155, bps: 5, rate: 6, thr: 10.6, papr: 8.2, k: 5708), -0.4),
  _extra(_psk(spf: 451, bps: 2, markers: 18, fc: [1350, 1650], pulse: _rc, thr: -5.4, papr: 4.4, k: 856)),
  _extra(_fsk(symbols: 93, bps: 3, rate: 2, sps: 128, first: 54, last: 74, step: 2, thr: -13.6, k: 64)),
  _ofdm500X,
  _ofdm500X,
]);

final List<HfLevel> _bw2300 = List<HfLevel>.unmodifiable(<HfLevel>[
  _fsk(symbols: 125, bps: 3, rate: 2, sps: 128, first: 33, last: 96, step: 2, thr: -13.6, k: 96),
  _fsk(symbols: 229, bps: 3, rate: 2, sps: 64, first: 17, last: 48, step: 2, thr: -11.2, k: 200),
  _fsk(symbols: 229, bps: 4, rate: 3, sps: 64, first: 17, last: 48, step: 2, thr: -9.4, k: 402),
  _fsk(symbols: 396, bps: 4, rate: 3, sps: 32, first: 9, last: 24, step: 1, thr: -6.6, k: 736),
  _psk(spf: 376, bps: 2, markers: 12, fc: [900, 1500, 2100], pulse: _rc, thr: -3.6, papr: 6.1, k: 1080),
  _psk(spf: 365, bps: 2, markers: 9, fc: [750, 1250, 1750, 2250], pulse: _rc, thr: -2.4, papr: 7.1, k: 1410),
  _psk(spf: 355, bps: 2, markers: 6, fc: [700, 1020, 1340, 1660, 1980, 2300], pulse: _rrc2, thr: -0.6, papr: 8.5, skip: true, k: 2076),
  _psk(spf: 352, bps: 2, markers: 5, fc: [702, 930, 1158, 1386, 1614, 1842, 2070, 2298], pulse: _rrc2, thr: 0.4, papr: 8.6, skip: true, k: 2754),
  _psk(spf: 349, bps: 2, markers: 4, fc: [555, 765, 975, 1185, 1395, 1605, 1815, 2025, 2235, 2445], pulse: _rrc1, thr: 1.3, papr: 8.9, k: 3424),
  _ofdm(_O.o2300, bps: 2, rate: 3, thr: 5.4, papr: 9.4, k: 7197),
  _ofdm(_O.o2300, bps: 2, rate: 4, thr: 7.2, papr: 9.4, skip: true, k: 9596),
  _ofdm(_O.o2300, bps: 2, rate: 6, thr: 8.5, papr: 9.4, k: 11512),
  _ofdm(_O.o2300, bps: 3, rate: 4, thr: 11.2, papr: 9.4, k: 14398),
  _snrCorr(_ofdm(_O.o2300, bps: 3, rate: 6, thr: 13.2, papr: 9.4, skip: true, k: 17276), -1.7),
  _snrCorr(_ofdm(_O.o2300, spf: 155, bps: 4, rate: 7, thr: 14.2, papr: 9.3, k: 21710), -1.59),
  _snrCorr(_ofdm(_O.o2300, spf: 155, bps: 5, rate: 6, thr: 17.2, papr: 9.3, k: 26056), -0.4),
  _ofdm500X,
]);

final List<HfLevel> _bw2750 = List<HfLevel>.unmodifiable(<HfLevel>[
  _fsk(symbols: 125, bps: 3, rate: 2, sps: 128, first: 24, last: 103, step: 2, thr: -13.6, k: 96),
  _fsk(symbols: 229, bps: 3, rate: 2, sps: 64, first: 12, last: 51, step: 2, thr: -11.2, k: 200),
  _fsk(symbols: 229, bps: 4, rate: 3, sps: 64, first: 12, last: 51, step: 2, thr: -9.4, k: 402),
  _fsk(symbols: 396, bps: 4, rate: 3, sps: 32, first: 6, last: 25, step: 1, thr: -6.6, k: 736),
  _psk(spf: 376, bps: 2, markers: 12, fc: [600, 1500, 2400], pulse: _rc, thr: -3.6, papr: 6.1, k: 1080),
  _psk(spf: 365, bps: 2, markers: 9, fc: [510, 1170, 1830, 2490], pulse: _rc, thr: -2.4, papr: 7.1, k: 1410),
  _psk(spf: 355, bps: 2, markers: 6, fc: [450, 870, 1290, 1710, 2130, 2550], pulse: _rrc2, thr: -0.6, papr: 8.4, skip: true, k: 2076),
  _psk(spf: 352, bps: 2, markers: 5, fc: [380, 700, 1020, 1340, 1660, 1980, 2300, 2620], pulse: _rrc2, thr: 0.4, papr: 8.7, skip: true, k: 2754),
  _psk(spf: 349, bps: 2, markers: 4, fc: [375, 625, 875, 1125, 1375, 1625, 1875, 2125, 2375, 2625], pulse: _rrc1, thr: 1.3, papr: 8.8, skip: true, k: 3424),
  _psk(spf: 349, bps: 2, markers: 3, fc: [240, 450, 660, 870, 1080, 1290, 1500, 1710, 1920, 2130, 2340, 2550, 2760], pulse: _rrc1, thr: 2.3, papr: 8.8, k: 4466),
  _ofdm(_O.o2750, bps: 2, rate: 3, thr: 6.0, papr: 9.3, k: 8667),
  _ofdm(_O.o2750, bps: 2, rate: 4, thr: 8.0, papr: 9.3, skip: true, k: 11556),
  _ofdm(_O.o2750, bps: 2, rate: 6, thr: 9.3, papr: 9.4, k: 13864),
  _ofdm(_O.o2750, bps: 3, rate: 4, thr: 11.8, papr: 9.5, k: 17338),
  _snrCorr(_ofdm(_O.o2750, bps: 3, rate: 6, thr: 14.0, papr: 9.5, skip: true, k: 20804), -1.7),
  _snrCorr(_ofdm(_O.o2750, spf: 155, bps: 4, rate: 7, thr: 15.0, papr: 9.3, k: 26145), -1.59),
  _snrCorr(_ofdm(_O.o2750, spf: 155, bps: 5, rate: 6, thr: 18.0, papr: 9.3, k: 31376), -0.4),
]);
