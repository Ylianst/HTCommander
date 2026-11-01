/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
VARA's AX.25/APRS field compressor used for unconnected (KISS) frames.
Strings are Latin-1 byte strings (one code unit per byte), mirroring the
upstream byte handling.
*/

import 'dart:typed_data';

import 'bits.dart';
import 'kiss_command.dart';

sealed class Ax25Error implements Exception {
  const Ax25Error();
}

class Ax25Short extends Ax25Error {
  const Ax25Short();

  @override
  bool operator ==(Object other) => other is Ax25Short;

  @override
  int get hashCode => 1;
}

class Ax25BadCall extends Ax25Error {
  final String call;

  const Ax25BadCall(this.call);

  @override
  bool operator ==(Object other) => other is Ax25BadCall && other.call == call;

  @override
  int get hashCode => call.hashCode;
}

class Ax25Format extends Ax25Error {
  const Ax25Format();

  @override
  bool operator ==(Object other) => other is Ax25Format;

  @override
  int get hashCode => 3;
}

const int uiCtrl = 0x03;
const int pidNoL3 = 0xF0;
const String callAlphabet = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

enum AprsType {
  text(0),
  binary(1),
  position(2),
  timestampedPosition(3),
  message(4),
  thirdParty(6);

  const AprsType(this.code);

  final int code;

  static AprsType? fromCode(int c) {
    for (final AprsType t in values) {
      if (t.code == c) return t;
    }
    return null;
  }

  bool get hasPosition => this == position || this == timestampedPosition;
}

final RegExp _u8 = RegExp(r'^\+?[0-9]+$');

int? _parseU8(String s) {
  if (!_u8.hasMatch(s)) return null;
  final int? v = int.tryParse(s.startsWith('+') ? s.substring(1) : s);
  return v != null && v <= 255 ? v : null;
}

bool _upperOrDigit(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39);

/// A plain callsign: 1-7 uppercase letters/digits and an SSID 0-15.
class Call {
  final String base;
  final int ssid;

  const Call(this.base, this.ssid);

  static Call? parse(String call) {
    final int dash = call.indexOf('-');
    final String base = dash < 0 ? call : call.substring(0, dash);
    final String s = dash < 0 ? '0' : call.substring(dash + 1);
    final int? ssid = _parseU8(s);
    if (ssid == null || ssid > 15) return null;
    if (base.isEmpty || base.length > 7 || !base.codeUnits.every(_upperOrDigit)) return null;
    return Call(base, ssid);
  }

  @override
  bool operator ==(Object other) => other is Call && other.base == base && other.ssid == ssid;

  @override
  int get hashCode => Object.hash(base, ssid);
}

const String _long = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!:#\$%&'()*+,-./;";
const List<String> _aliases = <String>['WIDE', 'PNW', 'MW', 'OR', 'WA'];
const List<String> _dictionary = <String>['/A=00', 'VARA', 'PinPoint', 'HF ', 'ack', 'APRS', 'ping{', 'Digi', 'Gate'];
const String _symbolTables = '/\\IRVTDS';
const String _symbolTablesCoded = '/\\IRVDS';
const List<String> _wideTokens = <String>['WIDE1-1', 'WIDE1', 'WIDE1-2', 'WIDE1-3', 'WIDE2', 'WIDE2-1', 'WIDE2-2', 'WIDE2-3'];
const List<(String, String, int, int, int)> _pairs = <(String, String, int, int, int)>[
  ('!', 'WIDE', 4, 6, 2),
  (':', 'PNW', 3, 5, 1),
  ('#', 'MW', 2, 4, 1),
  ('\$', 'OR', 2, 4, 1),
  ('%', 'WA', 2, 4, 1),
];
const List<(String, String)> _fixed = <(String, String)>[
  ('ALL', '&'),
  ('CQ', "'"),
  ('APBPQ1', '+'),
  ('APJYC1', ','),
  ('APOPYT', '-'),
  ('APU25N', '.'),
  ('APVARA', '/'),
];
const List<(String, String, int, int, int)> _numbered = <(String, String, int, int, int)>[
  ('(', 'APIN', 20, 36, 4),
  (')', 'APWW', 11, 19, 3),
  ('*', 'APDR', 16, 48, 5),
];

int callLenFor(KissCommand cmd) => cmd == KissCommand.ax25Long ? 7 : 6;

int addrEnd(int digis, int l) => (digis + 2) * (l + 1);

int _sym(String c) => _long.indexOf(c);

int? _alpha(int c) {
  final int i = callAlphabet.codeUnits.indexOf(c);
  return i < 0 ? null : i;
}

List<int> _slice(List<int> d, int a, int b) {
  final int s = a < d.length ? a : d.length;
  final int e = b < d.length ? b : d.length;
  return e > s ? d.sublist(s, e) : const <int>[];
}

int _at(List<int> d, int i) {
  if (i < 0 || i >= d.length) throw const Ax25Short();
  return d[i];
}

String _upper(String s) =>
    String.fromCharCodes(s.codeUnits.map((c) => c >= 0x61 && c <= 0x7A ? c - 0x20 : c));

String _pad(String s, int w) => s.length >= w ? s : s + ' ' * (w - s.length);

String _zeroPad(int v, int w) {
  final String s = v.toString();
  return s.length >= w ? s : '0' * (w - s.length) + s;
}

/// Encodes a call token. Throws [Ax25BadCall] on a character outside the
/// callsign alphabet.
void tokenEncode(String call, int callLen, Bits out) {
  final List<int> c = call.codeUnits;
  int num(int a, int b) => vbVal(_slice(c, a, b));
  int nbit(int i) => i < c.length && c[i] == 0x32 ? 1 : 0;
  if (_wideTokens.contains(call)) {
    out.push(_sym('!'), 6);
    out.push(nbit(4), 1);
    out.push(num(6, 7), 2);
    return;
  }
  for (final (String s, String name, int ni, int si, int w) in _pairs.skip(1)) {
    if (<String>['${name}1-1', '${name}1', '${name}2', '${name}2-1'].contains(call)) {
      out.push(_sym(s), 6);
      out.push(nbit(ni), 1);
      out.push(num(si, si + 1), w);
      return;
    }
  }
  for (final (String name, String s) in _fixed) {
    if (name == call) {
      out.push(_sym(s), 6);
      return;
    }
  }
  final bool plainAp = call.startsWith('AP') && !call.contains('-');
  for (final (String s, String pre, int lo, int hi, int w) in _numbered) {
    final int v = num(4, 6);
    if (call.startsWith(pre) && !call.contains('-') && v >= lo && v < hi) {
      out.push(_sym(s), 6);
      out.push(v - lo, w);
      return;
    }
  }
  if (plainAp) {
    out.push(_sym(';'), 6);
    for (final int ch in c.skip(2)) {
      final int? a = _alpha(ch);
      if (a == null) throw Ax25BadCall(call);
      out.push(a, 6);
    }
    if (c.length < callLen) out.push(0, 6);
    return;
  }
  final int dash = call.indexOf('-');
  final String base = _upper(dash < 0 ? call : call.substring(0, dash));
  final String ssid = dash < 0 ? '' : call.substring(dash + 1);
  for (final int ch in base.codeUnits) {
    final int? a = _alpha(ch);
    if (a == null) throw Ax25BadCall(call);
    out.push(a, 6);
  }
  if (base.length < callLen) out.push(0, 6);
  out.push(vbVal(ssid.codeUnits), 4);
}

String? tokenDecode(Reader r, int callLen) {
  final int? i = r.take(6);
  if (i == null || i >= _long.length) return null;
  final String ch = _long[i];
  for (final (String s, String name, int _, int _, int w) in _pairs) {
    if (s == ch) {
      final bool? b = r.bit();
      final String? t = r.text(w);
      if (b == null || t == null) return null;
      final String n = b ? '2' : '1';
      final int nn = vbVal(t.codeUnits);
      return nn != 0 ? '$name$n-${_u64(nn)}' : '$name$n';
    }
  }
  for (final (String name, String s) in _fixed) {
    if (s == ch) return name;
  }
  for (final (String s, String pre, int lo, int _, int w) in _numbered) {
    if (s == ch) {
      final int? v = r.take(w);
      return v == null ? null : '$pre${_zeroPad(v + lo, 2)}';
    }
  }
  if (ch == ';') {
    final StringBuffer call = StringBuffer('AP');
    for (int k = 2; k < callLen; k++) {
      final int? v = r.take(6);
      if (v == null || v >= callAlphabet.length) return null;
      final String c = callAlphabet[v];
      if (c == ' ') break;
      call.write(c);
    }
    return call.toString();
  }
  final StringBuffer call = StringBuffer(ch);
  for (int k = 1; k < callLen; k++) {
    final int? v = r.take(6);
    if (v == null) return null;
    if (v < callAlphabet.length) {
      final String c = callAlphabet[v];
      if (c == ' ') break;
      call.write(c);
    }
  }
  final int? ssid = r.take(4);
  if (ssid == null) return null;
  return ssid > 0 ? '$call-$ssid' : call.toString();
}

String _u64(int v) => v >= 0 ? '$v' : (BigInt.from(v).toUnsigned(64)).toString();

bool _startsAt(List<int> data, int i, String p) {
  if (data.length - i < p.length) return false;
  for (int k = 0; k < p.length; k++) {
    if (data[i + k] != p.codeUnitAt(k)) return false;
  }
  return true;
}

final RegExp _uDigits = RegExp(r'^\+?[0-9]+$');

void _textEncode(List<int> data, int i0, AprsType mode, Bits out) {
  int i = i0;
  while (i < data.length) {
    int m = -1;
    for (int k = 0; k < _dictionary.length; k++) {
      if (_startsAt(data, i, _dictionary[k])) {
        m = k;
        break;
      }
    }
    if (m < 0) {
      out.pushBfi(data[i], 7);
    } else {
      out.pushBfi(m + 1, 7);
      if (m == 0 && i + 8 < data.length && mode.hasPosition) {
        final List<int> raw = data.sublist(i + 5, i + 9);
        final String s = String.fromCharCodes(raw).trim();
        if (raw.any((b) => b > 0x7F) || !_uDigits.hasMatch(s)) throw const Ax25Format();
        out.pushBfi(int.parse(s.startsWith('+') ? s.substring(1) : s), 14);
        i += 4;
      }
      i += _dictionary[m].length - 1;
    }
    i++;
  }
}

List<int> _textDecode(Reader r, AprsType mode) {
  final List<int> out = <int>[];
  while (true) {
    final int? v = r.take(7);
    if (v == null) break;
    if (v == 0) continue;
    if (v >= 32) {
      out.add(v);
    } else if (v == 1) {
      out.addAll(_dictionary[0].codeUnits);
      if (mode.hasPosition) {
        final int n = r.remaining < 14 ? r.remaining : 14;
        final int alt = r.take(n) ?? 0;
        r.pos += 14 - n;
        out.addAll(_zeroPad(alt, 4).codeUnits);
      }
    } else if (v <= 9) {
      out.addAll(_dictionary[v - 1].codeUnits);
    }
  }
  return out;
}

void _latlonEncode(List<int> data, int p0, AprsType mode, Bits out) {
  int p = p0;
  int joined(int a, int b, int c, int d) => vbVal(<int>[..._slice(data, a, b), ..._slice(data, c, d)]);
  out.pushBfi(joined(p, p + 4, p + 5, p + 7), 20);
  final int ns = _at(data, p + 7);
  if (ns == 0x4E) out.bit(true);
  if (ns == 0x53) out.bit(false);
  p += 8;
  final int tbl = _at(data, p);
  if (_symbolTablesCoded.codeUnits.contains(tbl)) {
    out.bit(true);
    out.push(_symbolTables.codeUnits.indexOf(tbl), 3);
  } else {
    out.bit(false);
    out.pushBfi(tbl, 7);
  }
  p += 1;
  out.pushBfi(joined(p, p + 5, p + 6, p + 8), 21);
  final int we = _at(data, p + 8);
  if (we == 0x57) out.bit(true);
  if (we == 0x45) out.bit(false);
  p += 9;
  out.pushBfi(_at(data, p), 7);
  _textEncode(data, p + 1, mode, out);
}

void _aprsEncode(AprsType mode, List<int> data, int p, int callLen, Bits out) {
  switch (mode) {
    case AprsType.text:
      _textEncode(data, p, mode, out);
    case AprsType.position:
      _latlonEncode(data, p, mode, out);
    case AprsType.timestampedPosition:
      out.pushBfi(vbVal(_slice(data, p, p + 6)), 20);
      _latlonEncode(data, p + 7, mode, out);
    default:
      final String addressee = _upper(String.fromCharCodes(_trimWs(_slice(data, p, p + 9))));
      tokenEncode(addressee, callLen, out);
      _textEncode(data, p + 10, AprsType.message, out);
  }
}

List<int>? _latlonDecode(Reader r, AprsType mode) {
  final List<int> out = <int>[];
  final int? la = r.take(20);
  if (la == null) return null;
  final String lat = _zeroPad(la, 6);
  out.addAll('${lat.substring(0, 4)}.${lat.substring(4)}'.codeUnits);
  final bool? ns = r.bit();
  if (ns == null) return null;
  out.add(ns ? 0x4E : 0x53);
  final bool? coded = r.bit();
  if (coded == null) return null;
  final int? t = coded ? r.take(3) : r.take(7);
  if (t == null) return null;
  out.add(coded ? _symbolTables.codeUnitAt(t) : t);
  final int? lo = r.take(21);
  if (lo == null) return null;
  final String lon = _zeroPad(lo, 7);
  out.addAll('${lon.substring(0, 5)}.${lon.substring(5)}'.codeUnits);
  final bool? we = r.bit();
  if (we == null) return null;
  out.add(we ? 0x57 : 0x45);
  final int? s = r.take(7);
  if (s == null) return null;
  out.add(s);
  out.addAll(_textDecode(r, mode));
  return out;
}

List<int>? _aprsDecode(AprsType mode, Reader r, int callLen) {
  switch (mode) {
    case AprsType.text:
      return _textDecode(r, mode);
    case AprsType.position:
      final List<int>? ll = _latlonDecode(r, mode);
      return ll == null ? null : <int>[0x21, ...ll];
    case AprsType.timestampedPosition:
      final int? ts = r.take(20);
      if (ts == null) return null;
      final List<int>? ll = _latlonDecode(r, mode);
      return ll == null ? null : <int>[...'@${_zeroPad(ts, 6)}h'.codeUnits, ...ll];
    default:
      final String? addressee = tokenDecode(r, callLen);
      if (addressee == null) return null;
      return <int>[...':${_pad(addressee, 9)}:'.codeUnits, ..._textDecode(r, AprsType.message)];
  }
}

class Ax25Record {
  final int callLen;
  final String dest;
  final String src;
  final List<String> digis;
  final List<bool> h;
  int ctrl = 0;
  int pid = 0;
  int alias = 0;
  AprsType aprsType = AprsType.text;

  Ax25Record(this.callLen, this.dest, this.src) : digis = <String>[], h = <bool>[];
}

bool _ws(int c) => (c >= 9 && c <= 13) || (c >= 28 && c <= 32);

List<int> _trimWs(List<int> s) {
  int a = 0;
  while (a < s.length && _ws(s[a])) {
    a++;
  }
  int b = s.length;
  while (b > a && _ws(s[b - 1])) {
    b--;
  }
  return s.sublist(a, b);
}

String _addrCall(List<int> frame, int off, int n) {
  if (off + n > frame.length) throw const Ax25Short();
  final List<int> raw = frame.sublist(off, off + n).map((b) => b >> 1).toList();
  String call = String.fromCharCodes(_trimWs(raw));
  final int ssid = (_at(frame, off + n) & 0x1E) >> 1;
  if (ssid != 0) call += '-$ssid';
  return call;
}

/// Parses an AX.25 frame header. Throws [Ax25Error].
Ax25Record parse(List<int> frame, KissCommand cmd) {
  final int l = callLenFor(cmd);
  final int a = l + 1;
  final Ax25Record rec = Ax25Record(l, _upper(_addrCall(frame, 0, l)), _upper(_addrCall(frame, a, l)));
  int pos = 2 * a - 1;
  while (_at(frame, pos) & 1 == 0 && rec.digis.length < 8) {
    rec.digis.add(_addrCall(frame, pos + 1, l));
    rec.h.add(_at(frame, pos + a) >> 7 == 1);
    pos += a;
  }
  rec.ctrl = _at(frame, pos + 1);
  rec.pid = _at(frame, pos + 2);
  final int n = rec.digis.length;
  if (n > 0) {
    for (int k = 0; k < _aliases.length; k++) {
      bool all = true;
      for (int d = 1; d <= n; d++) {
        if (rec.digis[d - 1] != '${_aliases[k]}$d-1') {
          all = false;
          break;
        }
      }
      if (all) {
        rec.alias = k + 1;
        break;
      }
    }
  }
  rec.aprsType = _classify(frame, rec, cmd);
  return rec;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

AprsType _classify(List<int> f, Ax25Record rec, KissCommand cmd) {
  final int n = rec.digis.length;
  final int i = addrEnd(n, rec.callLen) + 2;
  if (i <= f.length && f.skip(i).any((b) => b > 0x7F)) return AprsType.binary;
  if (!rec.dest.startsWith('AP') || cmd == KissCommand.ax25Long || i >= f.length) return AprsType.text;
  final int ub = f.length - 1;
  final int c = f[i];
  if (i + 19 <= ub &&
      (c == 0x21 || c == 0x3D) &&
      _isDigit(f[i + 1]) &&
      f[i + 5] == 0x2E &&
      (f[i + 8] == 0x4E || f[i + 8] == 0x53) &&
      f[i + 15] == 0x2E &&
      (f[i + 18] == 0x57 || f[i + 18] == 0x45)) {
    return AprsType.position;
  }
  if (i + 26 <= ub &&
      (c == 0x40 || c == 0x2F) &&
      _isDigit(f[i + 1]) &&
      f[i + 7] == 0x68 &&
      f[i + 12] == 0x2E &&
      (f[i + 15] == 0x4E || f[i + 15] == 0x53) &&
      f[i + 22] == 0x2E &&
      (f[i + 25] == 0x57 || f[i + 25] == 0x45)) {
    return AprsType.timestampedPosition;
  }
  if (i + 10 <= ub && c == 0x3A && f[i + 10] == 0x3A) return AprsType.message;
  if (i + 20 <= ub && c == 0x7D) {
    int gt = 0, comma = 0;
    for (int j = i; j <= ub; j++) {
      switch (f[j]) {
        case 0x3E:
          gt++;
        case 0x2C:
          if (comma == 0 && String.fromCharCodes(_slice(f, j + 1, j + 7)) != 'TCPIP,') return AprsType.text;
          comma++;
        case 0x2A:
          if (gt == 1 && comma == 2 && j + 1 < f.length && f[j + 1] == 0x3A) return AprsType.thirdParty;
      }
    }
  }
  return AprsType.text;
}

(String, int) _collect(List<int> f, int i, int stop, int span) {
  final StringBuffer s = StringBuffer();
  for (int j = i; j <= i + span; j++) {
    final int c = _at(f, j);
    if (c == stop) return (s.toString(), j + 1);
    s.writeCharCode(c);
  }
  return (s.toString(), i);
}

String _thirdPartyCall(String s) => _upper(String.fromCharCodes(_trimWs(s.codeUnits)));

/// Compresses an AX.25 frame. Throws [Ax25Error].
(Uint8List, Ax25Record) encode(List<int> frame, KissCommand cmd) {
  final Ax25Record rec = parse(frame, cmd);
  final int l = rec.callLen, n = rec.digis.length;
  final AprsType typ = rec.aprsType;
  final bool ui = rec.ctrl == uiCtrl && rec.pid == pidNoL3;
  int hdr = cmd == KissCommand.ax25Long ? 0x10 : 0x00;
  if (ui) hdr |= 0x40;
  final Bits b = Bits();
  if (n > 0) {
    hdr |= 0x08 | (n - 1);
    for (final bool h in rec.h) {
      b.bit(h);
    }
  }
  tokenEncode(rec.dest, l, b);
  tokenEncode(rec.src, l, b);
  final bool ap = rec.dest.startsWith('AP');
  if (n > 0) {
    if (ap && rec.alias > 0) {
      b.bit(true);
      b.push(rec.alias, 3);
    } else {
      if (ap) b.bit(false);
      for (final String d in rec.digis) {
        tokenEncode(d, l, b);
      }
    }
  }
  b.push(typ.code, ap ? 3 : 1);
  switch (typ) {
    case AprsType.text:
    case AprsType.binary:
      final int start = addrEnd(n, l) + (ui ? 2 : 0);
      final List<int> body = start <= frame.length ? frame.sublist(start) : const <int>[];
      if (typ == AprsType.text) {
        b.pushText7(body);
      } else {
        for (final int c in body) {
          b.push(c, 8);
        }
      }
    case AprsType.position:
    case AprsType.timestampedPosition:
    case AprsType.message:
      _aprsEncode(typ, frame, addrEnd(n, l) + 3, l, b);
    case AprsType.thirdParty:
      final (String s1, int i1) = _collect(frame, addrEnd(n, l) + 3, 0x3E, 9);
      tokenEncode(_thirdPartyCall(s1), l, b);
      final (String s2, int i2) = _collect(frame, i1, 0x2C, 9);
      tokenEncode(_thirdPartyCall(s2), l, b);
      final (String _, int j) = _collect(frame, i2, 0x2C, 13);
      if (j == i2) throw const Ax25Format();
      final (String s3, int j2) = _collect(frame, j, 0x2A, 9);
      final int i = j2 != j ? j2 + 1 : j;
      tokenEncode(_thirdPartyCall(s3), l, b);
      final int c = _at(frame, i);
      final bool dig = _isDigit(_at(frame, i + 1));
      final (int inner, AprsType mode, int p) = switch (c) {
        0x21 || 0x3D when dig => (0, AprsType.position, i + 1),
        0x40 || 0x2F when dig => (1, AprsType.timestampedPosition, i + 1),
        0x3A => (2, AprsType.message, i + 1),
        _ => (3, AprsType.text, i),
      };
      b.push(inner, 2);
      _aprsEncode(mode, frame, p, l, b);
  }
  while (b.length % 8 != 0) {
    b.bit(false);
  }
  return (Uint8List.fromList(<int>[hdr, ...b.pack()]), rec);
}

void _callBytes(String call, int l, List<int> out) {
  final int dash = call.indexOf('-');
  final String base = _upper(dash < 0 ? call : call.substring(0, dash));
  final String ssid = dash < 0 ? '' : call.substring(dash + 1);
  final int ss = switch (ssid) {
    'T' => 16,
    'R' => 17,
    'X' => 18,
    'L' => 19,
    _ => vbVal(ssid.codeUnits),
  };
  out.addAll(_pad(base, l).codeUnits.take(l).map((c) => (c * 2) & 0xFF));
  out.add(0x60 | ((ss & 0xFF) * 2) & 0xFF);
}

/// Expands a compressed buffer back into an AX.25 frame.
(KissCommand, Uint8List)? decode(List<int> buf) {
  if (buf.isEmpty) return null;
  final int hdr = buf[0];
  final KissCommand cmd = (hdr & 0x10) != 0 ? KissCommand.ax25Long : KissCommand.ax25;
  final int l = callLenFor(cmd);
  final Reader r = Reader(Bits.unpack(buf.sublist(1)).bits);
  final int n = (hdr & 8) != 0 ? (hdr & 7) + 1 : 0;
  final List<bool> h = <bool>[];
  for (int k = 0; k < n; k++) {
    final bool? v = r.bit();
    if (v == null) return null;
    h.add(v);
  }
  final String? dest = tokenDecode(r, l);
  if (dest == null) return null;
  final String? src = tokenDecode(r, l);
  if (src == null) return null;
  final bool ap = dest.startsWith('AP');
  List<String> digis = <String>[];
  if (n > 0) {
    bool aliased = false;
    if (ap) {
      final bool? bit = r.bit();
      if (bit == null) return null;
      aliased = bit;
    }
    if (aliased) {
      final int? a = r.take(3);
      if (a == null || a < 1 || a > _aliases.length) return null;
      digis = <String>[for (int k = 1; k <= n; k++) '${_aliases[a - 1]}$k-1'];
    } else {
      for (int k = 0; k < n; k++) {
        final String? d = tokenDecode(r, l);
        if (d == null) return null;
        digis.add(d);
      }
    }
  }
  final int? code = r.take(ap ? 3 : 1);
  final AprsType? typ = code == null ? null : AprsType.fromCode(code);
  if (typ == null) return null;
  final List<int> out = <int>[];
  for (final String c in <String>[dest, src, ...digis]) {
    _callBytes(c, l, out);
  }
  out[out.length - 1] |= 0x01;
  for (int k = 0; k < h.length; k++) {
    if (h[k]) out[addrEnd(k + 1, l) - 1] |= 0x80;
  }
  if ((hdr & 0x40) != 0) out.addAll(<int>[uiCtrl, pidNoL3]);
  switch (typ) {
    case AprsType.text:
      final List<int>? t = r.text7();
      if (t == null) return null;
      out.addAll(t);
    case AprsType.binary:
      while (true) {
        final int? v = r.take(8);
        if (v == null) break;
        out.add(v);
      }
    case AprsType.position:
    case AprsType.timestampedPosition:
    case AprsType.message:
      final List<int>? a = _aprsDecode(typ, r, l);
      if (a == null) return null;
      out.addAll(a);
    case AprsType.thirdParty:
      final String? s1 = tokenDecode(r, l);
      final String? s2 = s1 == null ? null : tokenDecode(r, l);
      final String? s3 = s2 == null ? null : tokenDecode(r, l);
      if (s3 == null) return null;
      out.addAll('}$s1>$s2,TCPIP,$s3*:'.codeUnits);
      final int? m = r.take(2);
      if (m == null) return null;
      final AprsType mode = <AprsType>[
        AprsType.position,
        AprsType.timestampedPosition,
        AprsType.message,
        AprsType.text,
      ][m];
      final List<int>? a = _aprsDecode(mode, r, l);
      if (a == null) return null;
      out.addAll(a);
  }
  return (cmd, Uint8List.fromList(out));
}
