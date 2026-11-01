/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM frame layouts: record 0 (connect) and data/short/start/broadcast frames.
*/

import 'dart:convert';
import 'dart:typed_data';

import 'call.dart';
import 'crc.dart';
import 'fm_level.dart';
import 'numeric.dart';

const int terminator = 0x14;
const int record0Len = 39;

int _overhead(FmRecord record, bool vias) {
  if (record == FmRecord.connect) return 4;
  if (record == FmRecord.broadcast) return 3;
  if (record == FmRecord.start) return 5 + (vias ? 1 : 0);
  return 4 + (vias ? 1 : 0);
}

int? payloadLen(FmRecord record, int frameLen, bool vias) {
  final int p = frameLen - _overhead(record, vias);
  return p >= 0 ? p : null;
}

class Control {
  final bool compressed;
  final int hint;
  final bool last;
  final bool full;

  const Control({this.compressed = false, this.hint = 0, this.last = false, this.full = false});

  int get byte =>
      ((compressed ? 1 : 0) << 5) | ((hint & 7) << 2) | ((last ? 1 : 0) << 1) | (full ? 1 : 0);

  factory Control.fromByte(int b) => Control(
        compressed: (b & 0x20) != 0,
        hint: (b >> 2) & 7,
        last: (b & 2) != 0,
        full: (b & 1) != 0,
      );

  @override
  bool operator ==(Object other) =>
      other is Control &&
      other.compressed == compressed &&
      other.hint == hint &&
      other.last == last &&
      other.full == full;

  @override
  int get hashCode => byte;
}

class Trailer {
  final int leadReport;
  final int level;
  final int? chainSnr;

  const Trailer({this.leadReport = 0, this.level = 0, this.chainSnr});

  Trailer copyWith({int? leadReport, int? level}) =>
      Trailer(leadReport: leadReport ?? this.leadReport, level: level ?? this.level, chainSnr: chainSnr);

  static Trailer _fromBytes(FmRecord record, List<int> t) {
    if (record == FmRecord.broadcast) return const Trailer();
    if (record == FmRecord.start) {
      return Trailer(leadReport: t[0], level: t[1], chainSnr: t.length > 2 ? t[2] : null);
    }
    return Trailer(leadReport: t[0], chainSnr: t.length > 1 ? t[1] : null);
  }

  void _write(FmRecord record, List<int> out) {
    if (record != FmRecord.broadcast) {
      out.add(leadReport & 0xFF);
      if (record == FmRecord.start) out.add(level & 0xFF);
      if (chainSnr != null) out.add(chainSnr! & 0xFF);
    }
  }

  static Trailer? read(FmRecord record, List<int> frame, bool vias) {
    final int? p = payloadLen(record, frame.length, vias);
    if (p == null || record == FmRecord.connect) return null;
    return _fromBytes(record, frame.sublist(p + 1, frame.length - 2));
  }

  Uint8List? restamp(FmRecord record, List<int> frame) {
    final int? p = payloadLen(record, frame.length, chainSnr != null && record != FmRecord.broadcast);
    if (p == null) return null;
    final List<int> out = List<int>.of(frame.take(p + 1));
    _write(record, out);
    return _seal(out);
  }

  @override
  bool operator ==(Object other) =>
      other is Trailer &&
      other.leadReport == leadReport &&
      other.level == level &&
      other.chainSnr == chainSnr;

  @override
  int get hashCode => Object.hash(leadReport, level, chainSnr);

  @override
  String toString() => 'Trailer($leadReport, $level, $chainSnr)';
}

class DataFrame {
  final Uint8List data;
  final Control control;
  final Trailer trailer;

  const DataFrame(this.data, this.control, this.trailer);
}

Uint8List _seal(List<int> out) {
  final int crc = crc16Genibus(out);
  return Uint8List.fromList(<int>[...out, crc >> 8, crc & 0xFF]);
}

Uint8List buildData(
  FmRecord record,
  int frameLen,
  List<int> data,
  bool compressed,
  int hint,
  bool last,
  Trailer trailer,
) {
  if (record == FmRecord.connect) throw ArgumentError('record 0 has its own layout');
  final bool vias = trailer.chainSnr != null && record != FmRecord.broadcast;
  final int? room = payloadLen(record, frameLen, vias);
  if (room == null) throw ArgumentError('frame too short');
  final int n = data.length < room ? data.length : room;
  final bool full = n == room;
  final List<int> out = <int>[...data.take(n)];
  if (!full) {
    out.add(terminator);
    while (out.length < room) {
      out.add(0);
    }
  }
  out.add(Control(compressed: compressed, hint: hint, last: last, full: full).byte);
  trailer._write(record, out);
  assert(out.length == frameLen - 2);
  return _seal(out);
}

DataFrame? parseData(FmRecord record, List<int> frame, bool vias) {
  if (record == FmRecord.connect) return null;
  final int? p = payloadLen(record, frame.length, vias);
  if (p == null || !crcOk(frame)) return null;
  final Control control = Control.fromByte(frame[p]);
  int n;
  if (control.full) {
    n = p;
  } else {
    n = frame.sublist(0, p).lastIndexOf(terminator);
    if (n < 0) return null;
  }
  final Trailer trailer = Trailer._fromBytes(record, frame.sublist(p + 1, frame.length - 2));
  return DataFrame(Uint8List.fromList(frame.sublist(0, n)), control, trailer);
}

enum Kind { connect, autoTune, ping, reply }

List<int>? _callField(String call) {
  final List<int> b = utf8
      .encode(call.split('-').first)
      .map((c) => c >= 0x61 && c <= 0x7A ? c - 0x20 : c)
      .toList();
  if (b.length > 7 || b.any((c) => c > 0x7F)) return null;
  final List<int> f = List<int>.filled(8, 0x20);
  f.setRange(0, b.length, b);
  final int dash = call.indexOf('-');
  final int? ssid = dash < 0 ? 0 : ssidCode(call.substring(dash + 1));
  if (ssid == null) return null;
  f[7] = ssid;
  return f;
}

String _parseCall(List<int> f) {
  if (f[0] == 0) return '';
  final String base = String.fromCharCodes(f.sublist(0, 7)).trimRight();
  return withSsid(base, f[7]);
}

int snrByte(double snrDb) {
  final int v = asU32(roundTiesEven(snrDb.clamp(0.0, 35.0) * 7.0)) & 0xFF;
  return v < 1 ? 1 : v;
}

class Record0 {
  final Kind kind;
  final int hop;
  final bool registered;
  final bool wide;
  final String source;
  final String via1;
  final String via2;
  final String target;
  final bool aes;
  final int compression;
  final int control;
  final int chainSnr;

  const Record0({
    this.kind = Kind.connect,
    this.hop = 0,
    this.registered = false,
    this.wide = false,
    this.source = '',
    this.via1 = '',
    this.via2 = '',
    this.target = '',
    this.aes = false,
    this.compression = 0,
    this.control = 0,
    this.chainSnr = 0,
  });

  factory Record0.connect(String source, String target, String via1, String via2, bool registered, bool wide) =>
      Record0(
        source: source,
        target: target,
        via1: via1,
        via2: via2,
        registered: registered,
        wide: wide,
        control: 0x07,
      );

  Record0 copyWith({
    Kind? kind,
    int? hop,
    bool? registered,
    bool? wide,
    bool? aes,
    int? compression,
    int? control,
    int? chainSnr,
  }) =>
      Record0(
        kind: kind ?? this.kind,
        hop: hop ?? this.hop,
        registered: registered ?? this.registered,
        wide: wide ?? this.wide,
        source: source,
        via1: via1,
        via2: via2,
        target: target,
        aes: aes ?? this.aes,
        compression: compression ?? this.compression,
        control: control ?? this.control,
        chainSnr: chainSnr ?? this.chainSnr,
      );

  int get vias => (via1.isNotEmpty ? 1 : 0) + (via2.isNotEmpty ? 1 : 0);

  int get _head =>
      (kind.index << 5 | (hop & 3) << 3 | (registered ? 1 : 0) << 2 | (wide ? 1 : 0) << 1) & 0xFF;

  int _flags(int comp) => (aes ? 1 : 0) << 6 | 0x08 | (comp & 3) << 1;

  Uint8List? toBytes() {
    final int comp = registered ? compression : 0;
    final List<int> f = <int>[_head];
    for (final String c in <String>[source, via1, via2, target]) {
      final List<int>? field = _callField(c);
      if (field == null) return null;
      f.addAll(field);
    }
    f.addAll(<int>[0, _flags(comp), control & 0xFF, chainSnr & 0xFF]);
    return _seal(f);
  }

  Uint8List restamp(List<int> raw) {
    final List<int> f = raw.sublist(0, record0Len - 2);
    f[0] = _head;
    f[34] = _flags(compression) | raw[34] & 0x80;
    f[36] = chainSnr & 0xFF;
    return _seal(f);
  }

  static Record0? parse(List<int> f) {
    if (f.length != record0Len || !crcOk(f)) return null;
    String call(int i) => _parseCall(f.sublist(1 + 8 * i, 9 + 8 * i));
    return Record0(
      kind: Kind.values[(f[0] >> 5) & 3],
      hop: (f[0] >> 3) & 3,
      registered: (f[0] & 4) != 0,
      wide: (f[0] & 2) != 0,
      source: call(0),
      via1: call(1),
      via2: call(2),
      target: call(3),
      aes: (f[34] & 0x40) != 0,
      compression: (f[34] >> 1) & 3,
      control: f[35],
      chainSnr: f[36],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Record0 &&
      other.kind == kind &&
      other.hop == hop &&
      other.registered == registered &&
      other.wide == wide &&
      other.source == source &&
      other.via1 == via1 &&
      other.via2 == via2 &&
      other.target == target &&
      other.aes == aes &&
      other.compression == compression &&
      other.control == control &&
      other.chainSnr == chainSnr;

  @override
  int get hashCode => Object.hash(kind, hop, registered, wide, source, via1, via2, target, aes, compression, control, chainSnr);
}
