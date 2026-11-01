/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
VARA's state-machine text compression (prefix codes over a phrase dictionary).
*/

import 'dart:typed_data';

import 'bits.dart';
import 'textcomp_dict.dart';

class _Entry {
  final Uint8List phrase;
  final List<bool> code;
  final int next;

  _Entry(this.phrase, this.code, this.next);
}

class _StateTab {
  final List<bool> start;
  final List<_Entry> entries;
  final (List<bool>, int)? escape;
  final List<int>? byteMiss;
  // Keyed by (code length << 32) | code value.
  final Map<int, int> decode;

  _StateTab(this.start, this.entries, this.escape, this.byteMiss, this.decode);
}

const int _hitEscape = -1;

List<bool> _bits(String s) => s.codeUnits.map((c) => c == 0x31).toList();

int _key(List<bool> code, [int start = 0, int? end]) {
  final int e = end ?? code.length;
  int v = 0;
  for (int i = start; i < e; i++) {
    v = v << 1 | (code[i] ? 1 : 0);
  }
  return (e - start) << 32 | v;
}

Uint8List _hex(String s) => Uint8List.fromList(
    List<int>.generate(s.length ~/ 2, (i) => int.parse(s.substring(2 * i, 2 * i + 2), radix: 16)));

List<_StateTab>? _tabs;

List<_StateTab> _tables() => _tabs ??= _build();

List<_StateTab> _build() {
  final List<List<bool>> start = List<List<bool>>.filled(8, const <bool>[]);
  final List<List<_Entry>> entries = List<List<_Entry>>.generate(8, (_) => <_Entry>[]);
  final List<(List<bool>, int)?> escapes = List<(List<bool>, int)?>.filled(8, null);
  int cur = 0;
  for (final String line in textcompDict.split('\n')) {
    if (line.isEmpty) continue;
    final List<String> f = line.split(' ');
    if (f[0] == 'S') {
      cur = int.parse(f[1]) - 1;
      start[cur] = _bits(f[2]);
      escapes[cur] = f[3] != '-' ? (_bits(f[3]), int.parse(f[4])) : null;
    } else {
      entries[cur].add(_Entry(f[1] == '-' ? Uint8List(0) : _hex(f[1]), _bits(f[2]), int.parse(f[3])));
    }
  }
  return List<_StateTab>.generate(8, (s) {
    final List<_Entry> es = entries[s];
    List<int>? byteMiss;
    if (escapes[s] == null) {
      byteMiss = List<int>.generate(256, (b) {
        final int i = es.indexWhere((e) => e.phrase.length == 1 && e.phrase[0] == b);
        if (i < 0) throw StateError('textcomp dict: state without escape lacks a byte');
        return i;
      });
    }
    final Map<int, int> decode = <int, int>{};
    for (int i = 0; i < es.length; i++) {
      decode.putIfAbsent(_key(es[i].code), () => i);
    }
    final (List<bool>, int)? esc = escapes[s];
    if (esc != null) decode.putIfAbsent(_key(esc.$1), () => _hitEscape);
    return _StateTab(start[s], es, esc, byteMiss, decode);
  });
}

const int startState = 1;
const int maxPhrase = 39;
const int trialBytes = 150;
const int _maxCode = 10;

class Encoded {
  final Uint8List bytes;
  final int consumed;
  final int endState;

  const Encoded(this.bytes, this.consumed, this.endState);
}

bool _startsWith(List<int> data, int pos, Uint8List p) {
  if (data.length - pos < p.length) return false;
  for (int i = 0; i < p.length; i++) {
    if (data[pos + i] != p[i]) return false;
  }
  return true;
}

Encoded compress(List<int> data, int cap, int state0) {
  final List<_StateTab> t = _tables();
  int state = state0 >= 1 && state0 <= t.length ? state0 : startState;
  final List<bool> out = List<bool>.of(t[state - 1].start);
  int consumed = 0, pos = 0;
  (int, int, int)? last;
  while (pos < data.length) {
    final _StateTab st = t[state - 1];
    List<bool>? code;
    int m = 0, next = 0;
    for (final _Entry e in st.entries) {
      if (e.phrase.isNotEmpty && _startsWith(data, pos, e.phrase)) {
        code = e.code;
        m = e.phrase.length;
        next = e.next;
        break;
      }
    }
    if (code == null) {
      if (st.escape != null) {
        code = st.escape!.$1;
        m = 0;
        next = st.escape!.$2;
      } else {
        final _Entry e = st.entries[st.byteMiss![data[pos] & 0xFF]];
        code = e.code;
        m = 1;
        next = e.next;
      }
    }
    final bool full = out.length + code.length > cap * 8;
    if (!full) {
      consumed += m;
      out.addAll(code);
      last = (code.length, m, state);
    }
    if (next != 0) state = next;
    if (full) break;
    pos += m;
  }
  _pad(out);
  if (out.length > cap * 8 && last != null) {
    out.length = out.length - 8 - last.$1;
    consumed -= last.$2;
    state = last.$3;
    _pad(out);
  }
  return Encoded(Bits(out).pack(), consumed, state);
}

bool turnCompresses(List<int> queued) {
  final int n = queued.length < trialBytes ? queued.length : trialBytes;
  final Encoded c = compress(queued.sublist(0, n), n, startState);
  return c.bytes.length < c.consumed;
}

int inputWindow(int room) => 3 * room + maxPhrase;

Encoded fillFrame(List<int> queued, int room, int state) {
  final int w = inputWindow(room);
  return compress(queued.length > w ? queued.sublist(0, w) : queued, room, state);
}

bool fitsFrames(List<int> queued, int frames, int room, int lastRoom, int state) {
  final int q = queued.length;
  if (q <= (frames - 1) * room + lastRoom) return true;
  if (frames == 1) {
    return q <= inputWindow(room) && compress(queued, lastRoom, state).consumed == q;
  }
  if (q > inputWindow(2 * room)) return false;
  final Encoded c = compress(queued, room, state);
  final int r = q - c.consumed;
  return r == 0 || compress(queued.sublist(c.consumed), r < lastRoom ? r : lastRoom, c.endState).consumed == r;
}

void _pad(List<bool> b) {
  final bool p = !(b.isEmpty ? true : b.last);
  final int n = b.length % 8 == 0 ? 8 : 8 - b.length % 8;
  for (int i = 0; i < n; i++) {
    b.add(p);
  }
}

/// Returns the decompressed text and the final state, or null if malformed.
(Uint8List, int)? decompress(List<int> payload) {
  final List<_StateTab> t = _tables();
  final List<bool> b = Bits.unpack(payload).bits;
  if (b.isEmpty) return null;
  final bool p = b.last;
  while (b.isNotEmpty && b.last == p) {
    b.removeLast();
  }
  if (b.length < 3) return null;
  int state = (_key(b, 0, 3) & 0xFFFFFFFF) + 1;
  int i = 3;
  final BytesBuilder out = BytesBuilder(copy: false);
  while (i < b.length) {
    final _StateTab st = t[state - 1];
    int len = 0;
    int? hit;
    final int maxLen = _maxCode < b.length - i ? _maxCode : b.length - i;
    for (int l = 1; l <= maxLen; l++) {
      final int? h = st.decode[_key(b, i, i + l)];
      if (h != null) {
        len = l;
        hit = h;
        break;
      }
    }
    if (hit == null) return null;
    i += len;
    if (hit == _hitEscape) {
      state = st.escape!.$2;
    } else {
      final _Entry e = st.entries[hit];
      out.add(e.phrase);
      if (e.next != 0) state = e.next;
    }
  }
  return (out.toBytes(), state);
}
