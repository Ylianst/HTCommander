/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Strict raw DEFLATE (RFC 1951) decoder with an output cap. Returns null on any
malformed or truncated stream, or when the output would exceed the cap, so a
small hostile chunk can never expand without bound.
*/

import 'dart:typed_data';

class _Huffman {
  final Int32List counts;
  final Int32List symbols;

  _Huffman(this.counts, this.symbols);

  /// Builds canonical Huffman tables; returns null if over-subscribed.
  static _Huffman? build(List<int> lengths, {bool allowIncomplete = true}) {
    final Int32List counts = Int32List(16);
    for (final int l in lengths) {
      counts[l]++;
    }
    counts[0] = 0;
    int left = 1;
    for (int len = 1; len < 16; len++) {
      left <<= 1;
      left -= counts[len];
      if (left < 0) return null;
    }
    if (left > 0 && !allowIncomplete) return null;
    final Int32List offs = Int32List(16);
    for (int len = 1; len < 15; len++) {
      offs[len + 1] = offs[len] + counts[len];
    }
    final Int32List symbols = Int32List(lengths.length);
    for (int s = 0; s < lengths.length; s++) {
      if (lengths[s] != 0) symbols[offs[lengths[s]]++] = s;
    }
    return _Huffman(counts, symbols);
  }
}

class _Truncated implements Exception {}

class _Bad implements Exception {}

class _State {
  final List<int> input;
  int pos = 0;
  int bitBuf = 0;
  int bitCnt = 0;
  final Uint8List window;
  int outLen = 0;
  final int cap;

  _State(this.input, this.cap) : window = Uint8List(cap);

  int bits(int need) {
    int val = bitBuf;
    while (bitCnt < need) {
      if (pos >= input.length) throw _Truncated();
      val |= (input[pos++] & 0xFF) << bitCnt;
      bitCnt += 8;
    }
    bitBuf = val >> need;
    bitCnt -= need;
    return val & ((1 << need) - 1);
  }

  void emit(int b) {
    if (outLen >= cap) throw _Bad();
    window[outLen++] = b;
  }

  int decode(_Huffman h) {
    int code = 0, first = 0, index = 0;
    for (int len = 1; len < 16; len++) {
      code |= bits(1);
      final int count = h.counts[len];
      if (code - count < first) return h.symbols[index + (code - first)];
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw _Bad();
  }
}

const List<int> _lBase = <int>[3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const List<int> _lExt = <int>[0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const List<int> _dBase = <int>[1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const List<int> _dExt = <int>[0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
const List<int> _order = <int>[16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

final _Huffman _fixedLit = _Huffman.build(<int>[
  for (int i = 0; i < 144; i++) 8,
  for (int i = 144; i < 256; i++) 9,
  for (int i = 256; i < 280; i++) 7,
  for (int i = 280; i < 288; i++) 8,
])!;
final _Huffman _fixedDist = _Huffman.build(List<int>.filled(30, 5))!;

void _codes(_State s, _Huffman lit, _Huffman dist) {
  while (true) {
    int sym = s.decode(lit);
    if (sym < 256) {
      s.emit(sym);
    } else if (sym == 256) {
      return;
    } else {
      sym -= 257;
      if (sym >= 29) throw _Bad();
      final int len = _lBase[sym] + s.bits(_lExt[sym]);
      final int ds = s.decode(dist);
      if (ds >= 30) throw _Bad();
      final int d = _dBase[ds] + s.bits(_dExt[ds]);
      if (d > s.outLen) throw _Bad();
      for (int i = 0; i < len; i++) {
        s.emit(s.window[s.outLen - d]);
      }
    }
  }
}

void _dynamic(_State s) {
  final int nlen = s.bits(5) + 257, ndist = s.bits(5) + 1, ncode = s.bits(4) + 4;
  if (nlen > 286 || ndist > 30) throw _Bad();
  final List<int> lengths = List<int>.filled(19, 0);
  for (int i = 0; i < ncode; i++) {
    lengths[_order[i]] = s.bits(3);
  }
  final _Huffman? lencode = _Huffman.build(lengths, allowIncomplete: false);
  if (lencode == null) throw _Bad();
  final List<int> ll = List<int>.filled(nlen + ndist, 0);
  int i = 0;
  while (i < nlen + ndist) {
    final int sym = s.decode(lencode);
    if (sym < 16) {
      ll[i++] = sym;
    } else {
      int len = 0, rep;
      if (sym == 16) {
        if (i == 0) throw _Bad();
        len = ll[i - 1];
        rep = 3 + s.bits(2);
      } else if (sym == 17) {
        rep = 3 + s.bits(3);
      } else {
        rep = 11 + s.bits(7);
      }
      if (i + rep > nlen + ndist) throw _Bad();
      for (int k = 0; k < rep; k++) {
        ll[i++] = len;
      }
    }
  }
  if (ll[256] == 0) throw _Bad();
  final List<int> litLens = ll.sublist(0, nlen);
  final List<int> distLens = ll.sublist(nlen);
  // Incomplete codes are only legal when they hold a single symbol.
  final _Huffman? lit = _Huffman.build(litLens, allowIncomplete: litLens.where((v) => v != 0).length == 1);
  final _Huffman? dist = _Huffman.build(distLens, allowIncomplete: distLens.where((v) => v != 0).length <= 1);
  if (lit == null || dist == null) throw _Bad();
  _codes(s, lit, dist);
}

void _stored(_State s) {
  s.bitBuf = 0;
  s.bitCnt = 0;
  if (s.pos + 4 > s.input.length) throw _Truncated();
  final int len = s.input[s.pos] | s.input[s.pos + 1] << 8;
  final int nlen = s.input[s.pos + 2] | s.input[s.pos + 3] << 8;
  s.pos += 4;
  if (len != (~nlen & 0xFFFF)) throw _Bad();
  if (s.pos + len > s.input.length) throw _Truncated();
  for (int i = 0; i < len; i++) {
    s.emit(s.input[s.pos++]);
  }
}

/// Inflates a raw DEFLATE stream. Returns null when the stream is malformed or
/// truncated, or when it would produce more than [maxOutput] bytes.
Uint8List? inflateRaw(List<int> input, int maxOutput) {
  final _State s = _State(input, maxOutput);
  try {
    bool last;
    do {
      last = s.bits(1) == 1;
      switch (s.bits(2)) {
        case 0:
          _stored(s);
        case 1:
          _codes(s, _fixedLit, _fixedDist);
        case 2:
          _dynamic(s);
        default:
          throw _Bad();
      }
    } while (!last);
  } on _Truncated {
    return null;
  } on _Bad {
    return null;
  }
  return Uint8List.fromList(Uint8List.sublistView(s.window, 0, s.outLen));
}
