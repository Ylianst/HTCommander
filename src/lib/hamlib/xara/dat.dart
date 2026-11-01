/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Per-record channel/turbo permutations and marker tables (VARA's .dat files).
*/

import 'dart:typed_data';

import 'crc.dart';
import 'fm_level.dart';
import 'hf_level.dart';
import 'numeric.dart';
import 'rnd.dart';

const double tableSeed = 43.0;
const double fmRecord16Seed = 77.0;

class RecordTables {
  final Uint32List chan;
  final Uint32List turbo;
  final Uint16List other;

  const RecordTables(this.chan, this.turbo, this.other);
}

List<List<bool>> markerMap(List<int> other, int nc, int markers, int nsym) {
  final List<List<bool>> out = <List<bool>>[];
  for (int c = 0; c < nc; c++) {
    final int start = nc * markers + c * nsym;
    if (start >= other.length) break;
    final int end = start + nsym < other.length ? start + nsym : other.length;
    out.add([for (int i = start; i < end; i++) other[i] != 0]);
  }
  return out;
}

Uint32List _perm(VbRnd r, int n) {
  final Uint8List used = Uint8List(n);
  final Uint32List out = Uint32List(n);
  int len = 0;
  while (len < n) {
    final int v = r.draw(n);
    if (used[v] == 0) {
      used[v] = 1;
      out[len++] = v;
    }
  }
  return out;
}

Uint16List _fskOther(VbRnd r, HfLevel l) {
  final int s = l.symbols;
  final int first = l.first;
  final int step = l.step;
  final int nb = l.last - first + 1;
  final int m = step > 1 ? nb ~/ step + 1 : nb;
  final List<int> out = <int>[
    for (int i = 0; i < s - 1; i++)
      (first + (step > 1 && i % 2 == 0 ? 1 : 0) + step * r.draw(m)) & 0xFFFF,
  ];
  final double inc = toF32((s - 2) / fskPilots);
  double acc = toF32(1.0);
  final List<int> rows = <int>[];
  for (int i = 0; i < fskPilots; i++) {
    acc = toF32(acc + inc);
    rows.add(asU32(acc));
  }
  out.addAll(rows.map((x) => x & 0xFFFF));
  final int scale = (1 << l.bps) ~/ 8;
  final List<int?> pilot = List<int?>.filled(s - 1, null);
  for (final int row in rows) {
    pilot[row - 2] = scale * r.draw(8);
  }
  for (final int? p in pilot) {
    if (p != null) {
      out.add(1);
      out.add(p & 0xFFFF);
    } else {
      out.add(0);
      out.add(0);
    }
  }
  return Uint16List.fromList(out);
}

List<List<int>> _markerRows(int nc, int markers, int Function(int) next, int gap) {
  return <List<int>>[
    for (int c = 0; c < nc; c++)
      () {
        final List<int> row = <int>[];
        while (row.length < markers) {
          final int v = next(c);
          if (row.every((w) => (v - w).abs() > gap)) row.add(v);
        }
        return row;
      }(),
  ];
}

Uint16List _carrierOther(List<List<int>> rows, int spf) {
  final List<int> out = <int>[for (final List<int> row in rows) ...row.map((v) => v & 0xFFFF)];
  for (final List<int> row in rows) {
    final List<int> m = List<int>.filled(spf - 1, 0);
    for (final int v in row) {
      m[v - 2] = 1;
    }
    out.addAll(m);
  }
  return Uint16List.fromList(out);
}

Uint16List _pskOther(VbRnd r, HfLevel l) {
  final int spf = l.spf;
  final int first = l.isOfdm ? l.first : 0;
  final bool qam = l.isQam;
  final List<List<int>> rows = _markerRows(
    l.nc,
    l.markers,
    (c) => qam
        ? 3 + (first + c) % 2 + hfPilotPeriod * r.draw((spf - 3) ~/ hfPilotPeriod)
        : 5 + r.draw(spf - 8),
    0,
  );
  return _carrierOther(rows, spf);
}

Uint16List _fmOther(VbRnd r, FmLayout f) {
  final int gap = f.spf < 50 ? 0 : 2;
  final List<List<int>> rows = _markerRows(
    f.nc,
    f.markers,
    (c) => f.bps > 2
        ? 3 + (f.first + f.step * c) % 2 + fmPilotPeriod * r.draw((f.spf - 3) ~/ fmPilotPeriod)
        : 3 + r.draw(f.spf - 2),
    gap,
  );
  return _carrierOther(rows, f.spf);
}

List<RecordTables> hfTables(HfBandwidth bw) {
  final VbRnd r = VbRnd.stream(tableSeed);
  return <RecordTables>[
    for (final HfLevel l in bw.table)
      () {
        final Uint32List chan = _perm(r, l.n);
        final Uint32List turbo = _perm(r, l.k);
        final Uint16List other = l.isFsk ? _fskOther(r, l) : _pskOther(r, l);
        assert(other.length == l.otherLen);
        return RecordTables(chan, turbo, other);
      }(),
  ];
}

final Map<FmBandwidth, List<RecordTables>> _fmCache = <FmBandwidth, List<RecordTables>>{};
final Map<HfBandwidth, List<RecordTables>> _hfCache = <HfBandwidth, List<RecordTables>>{};

/// Cached [fmTables]; the tables are immutable once generated.
List<RecordTables> fmTablesCached(FmBandwidth bw) => _fmCache[bw] ??= fmTables(bw);

/// Cached [hfTables].
List<RecordTables> hfTablesCached(HfBandwidth bw) => _hfCache[bw] ??= hfTables(bw);

List<RecordTables> fmTables(FmBandwidth bw) {
  VbRnd r = VbRnd.stream(tableSeed);
  final List<RecordTables> out = <RecordTables>[];
  for (int i = 0; i < bw.layouts.length; i++) {
    final FmLayout f = bw.layouts[i];
    if (i == FmRecord.broadcast.index) r = VbRnd.stream(fmRecord16Seed);
    final Uint32List chan = _perm(r, f.n);
    final Uint32List turbo = _perm(r, f.k);
    final Uint16List other = _fmOther(r, f);
    out.add(RecordTables(chan, turbo, other));
  }
  return out;
}

void _putPerm(BytesBuilder out, Uint32List p) {
  final bool wide = p.length > 65536;
  final Uint8List b = Uint8List(p.length * (wide ? 3 : 2));
  int o = 0;
  for (final int v in p) {
    if (wide) b[o++] = (v >> 16) & 0xFF;
    b[o++] = (v >> 8) & 0xFF;
    b[o++] = v & 0xFF;
  }
  out.add(b);
}

Uint8List _serialize(List<RecordTables> tables) {
  final BytesBuilder out = BytesBuilder(copy: false);
  for (final RecordTables t in tables) {
    _putPerm(out, t.chan);
    _putPerm(out, t.turbo);
    final Uint8List b = Uint8List(t.other.length * 2);
    for (int i = 0; i < t.other.length; i++) {
      b[2 * i] = t.other[i] >> 8;
      b[2 * i + 1] = t.other[i] & 0xFF;
    }
    out.add(b);
  }
  final Uint8List body = out.toBytes();
  final int crc = crc16Genibus(body, 0, body.length - 1);
  final Uint8List res = Uint8List(body.length + 2)..setRange(0, body.length, body);
  res[body.length] = crc >> 8;
  res[body.length + 1] = crc & 0xFF;
  return res;
}

Uint8List hfDat(HfBandwidth bw) => _serialize(hfTables(bw));

Uint8List fmDat(FmBandwidth bw) => _serialize(fmTables(bw));
