/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM (VARA FM) record layouts and speed levels. f32 constants are held at f32
precision.
*/

import 'dsp.dart';
import 'fec.dart';
import 'numeric.dart';
import 'ofdm_const.dart';

const int fmRecords = 17;
const int fmPilotPeriod = 9;

/// FM data speed level 1..13.
extension type const DataLevel(int value) {
  static const DataLevel one = DataLevel(1);
  static const DataLevel max = DataLevel(13);

  static DataLevel? of(int n) => n >= 1 && n <= 13 ? DataLevel(n) : null;

  DataLevel? up(int d) => of(value + d);

  DataLevel down() => value > 1 ? DataLevel(value - 1) : this;

  static DataLevel clamped(int n, DataLevel top) => DataLevel(n.clamp(1, top.value));

  static Iterable<DataLevel> range(DataLevel lo, DataLevel hi) sync* {
    for (int i = lo.value; i <= hi.value; i++) {
      yield DataLevel(i);
    }
  }
}

/// FM record: 0 = connect, 1..13 = data levels, 14 = short, 15 = start,
/// 16 = broadcast. The representation is the record index.
extension type const FmRecord(int index) {
  static const FmRecord connect = FmRecord(0);
  static const FmRecord short = FmRecord(14);
  static const FmRecord start = FmRecord(15);
  static const FmRecord broadcast = FmRecord(16);

  static FmRecord data(DataLevel l) => FmRecord(l.value);

  static FmRecord? fromIndex(int i) => i >= 0 && i < fmRecords ? FmRecord(i) : null;

  DataLevel? get dataLevel => index >= 1 && index <= 13 ? DataLevel(index) : null;

  DataLevel? get level {
    if (index >= 1 && index <= 13) return DataLevel(index);
    if (index == 14 || index == 15) return DataLevel.one;
    return null;
  }

  bool get keyed => index != 0 && index != 16;
}

class FmLayout {
  final int nc;
  final int first;
  final int step;
  final int bps;
  final int spf;
  final int markers;
  final int k;

  const FmLayout(this.nc, this.first, this.step, this.bps, this.spf, this.markers, this.k);

  int get n => bps == 2
      ? nc * 2 * (spf - 2 - markers)
      : nc * bps * (spf - 1 - markers - ((spf - 3) ~/ fmPilotPeriod + 1));

  int get otherLen => nc * (markers + spf - 1);
}

FmLayout _nc14(int bps, int spf, int markers, int k) => FmLayout(14, 10, 4, bps, spf, markers, k);
FmLayout _nc29(int bps, int spf, int markers, int k) => FmLayout(29, 10, 2, bps, spf, markers, k);
FmLayout _nc58(int bps, int spf, int markers, int k) => FmLayout(58, 10, 1, bps, spf, markers, k);
FmLayout _nc98(int bps, int spf, int markers, int k) => FmLayout(98, 6, 1, bps, spf, markers, k);
FmLayout _nc116(int bps, int spf, int markers, int k) => FmLayout(116, 6, 1, bps, spf, markers, k);

final List<FmLayout> _fmNarrow = List<FmLayout>.unmodifiable(<FmLayout>[
  _nc14(2, 29, 4, 316),
  _nc14(2, 200, 4, 2710),
  _nc29(2, 200, 2, 5678),
  _nc58(2, 200, 1, 11420),
  _nc58(2, 200, 1, 15226),
  _nc58(3, 201, 1, 20408),
  _nc58(4, 201, 1, 27212),
  _nc58(5, 201, 1, 34018),
  _nc58(6, 201, 1, 40824),
  _nc58(6, 201, 1, 45927),
  _nc58(7, 201, 1, 53583),
  _nc58(8, 192, 1, 58455),
  _nc58(2, 50, 1, 2720),
  _nc58(2, 50, 1, 2720),
  _nc14(2, 83, 4, 1072),
  _nc14(2, 18, 6, 134),
  _nc14(2, 69, 4, 876),
]);

final List<FmLayout> _fmWide = List<FmLayout>.unmodifiable(<FmLayout>[
  _nc14(2, 29, 4, 316),
  _nc14(2, 200, 4, 2710),
  _nc29(2, 200, 2, 5678),
  _nc58(2, 200, 1, 11420),
  _nc98(2, 200, 1, 19300),
  _nc98(2, 200, 1, 25732),
  _nc98(3, 201, 1, 34488),
  _nc98(4, 201, 1, 45986),
  _nc116(4, 201, 1, 54434),
  _nc116(5, 165, 1, 55672),
  _nc116(6, 138, 1, 55672),
  _nc116(6, 120, 1, 54279),
  _nc116(7, 102, 1, 53583),
  _nc116(8, 93, 1, 55671),
  _nc14(2, 83, 4, 1072),
  _nc14(2, 18, 6, 134),
  _nc14(2, 69, 4, 876),
]);

final int fmMaxSpf = [..._fmNarrow, ..._fmWide].map((l) => l.spf).reduce((a, b) => a > b ? a : b);

class _Extra {
  final int rate;
  final double paprDb;
  final double ampNorm;
  final double thr;
  final int decodeAllow;

  const _Extra(this.rate, this.paprDb, this.ampNorm, this.thr, this.decodeAllow);
}

const _Extra _c14 = _Extra(3, 8.6, 5.29, -0.4, 176);

const List<_Extra> _narrow = <_Extra>[
  _c14,
  _c14,
  _Extra(3, 9.3, 7.62, 2.8, 198),
  _Extra(3, 10.0, 10.77, 5.6, 224),
  _Extra(4, 10.0, 10.77, 7.6, 245),
  _Extra(4, 9.9, 9.4844, 9.8, 300),
  _Extra(4, 9.9, 9.05, 11.8, 335),
  _Extra(4, 9.9, 10.28, 15.2, 393),
  _Extra(4, 9.9, 11.2, 17.4, 430),
  _Extra(5, 9.9, 11.2, 19.0, 465),
  _Extra(5, 9.9, 11.24, 21.8, 540),
  _Extra(5, 9.9, 11.18, 24.0, 550),
  _Extra(3, 10.0, 10.77, 5.6, 0),
  _Extra(3, 10.0, 10.77, 5.6, 0),
  _c14,
  _c14,
  _Extra(3, 8.6, 5.29, -0.4, 0),
];

const List<_Extra> _wide = <_Extra>[
  _c14,
  _c14,
  _Extra(3, 9.3, 7.62, 2.8, 198),
  _Extra(3, 10.0, 10.77, 5.6, 236),
  _Extra(3, 10.3, 14.0, 7.4, 289),
  _Extra(4, 10.3, 14.0, 9.4, 335),
  _Extra(4, 10.3, 12.32448, 12.0, 415),
  _Extra(4, 10.2, 11.76, 14.2, 463),
  _Extra(4, 10.4, 12.79, 15.0, 526),
  _Extra(4, 10.3, 14.53, 18.2, 551),
  _Extra(4, 10.3, 15.83, 20.4, 526),
  _Extra(5, 10.3, 15.83, 22.0, 500),
  _Extra(5, 10.3, 15.9, 24.8, 528),
  _Extra(5, 10.3, 15.9, 27.2, 520),
  _c14,
  _c14,
  _Extra(3, 8.6, 5.29, -0.4, 0),
];

enum FmBandwidth {
  narrow(11),
  wide(13);

  const FmBandwidth(this.numLevels);

  final int numLevels;

  List<FmLayout> get layouts => this == FmBandwidth.narrow ? _fmNarrow : _fmWide;

  FmLayout layout(FmRecord r) => layouts[r.index];

  DataLevel get topLevel => DataLevel(numLevels);

  Iterable<DataLevel> get levels => DataLevel.range(DataLevel.one, topLevel);

  FmLevel level(FmRecord record) {
    final _Extra x = (this == FmBandwidth.narrow ? _narrow : _wide)[record.index];
    final FmLayout layout = this.layout(record);
    final bool wide116 = this == FmBandwidth.wide && layout.nc == 116;
    return FmLevel._(
      bw: this,
      record: record,
      layout: layout,
      rate: x.rate,
      paprDb: toF32(x.paprDb),
      ampNorm: toF32(x.ampNorm),
      snrThrDb: toF32(x.thr),
      decodeAllow: x.decodeAllow,
      widePenaltyDb: toF32(wide116 ? 1.7 : 0.0),
    );
  }

  FmLevel dataLevel(DataLevel l) => level(FmRecord.data(l));
}

class FmLevel {
  final FmBandwidth bw;
  final FmRecord record;
  final FmLayout layout;
  final int rate;
  final double paprDb;
  final double ampNorm;
  final double snrThrDb;
  final int decodeAllow;
  final double widePenaltyDb;

  const FmLevel._({
    required this.bw,
    required this.record,
    required this.layout,
    required this.rate,
    required this.paprDb,
    required this.ampNorm,
    required this.snrThrDb,
    required this.decodeAllow,
    required this.widePenaltyDb,
  });

  int get frameBytes => layout.k ~/ 8;
  int get n => layout.n;
  int get nc => layout.nc;
  int get spf => layout.spf;
  int get nsym => layout.spf - 1;
  bool get isQam => layout.bps > 2;
  int get puncturePeriodValue => puncturePeriod(rate);

  int bin(int c) => layout.first + layout.step * c;

  Iterable<int> get bins => Iterable<int>.generate(nc, bin);

  int get frameTicks => (layout.spf - 1) * 9;

  double get netBps {
    if (record.dataLevel == null) return bw.dataLevel(DataLevel.one).netBps;
    final double num = roundTiesEven(frameBytes * binHz * 8.0);
    return num / (symRatio * nsym);
  }

  double gain(double driveDb) => fmGain(paprDb, driveDb);
}

double fmGain(double paprDb, double driveDb) =>
    dbAmp(-(paprDb + 2.0 + (10.0 - paprDb) / 1000.0 - driveDb));

bool fmQamPilot(int bin, int s) => s % fmPilotPeriod == 2 + bin % 2;
