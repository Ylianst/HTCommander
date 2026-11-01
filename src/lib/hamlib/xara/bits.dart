/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
MSB-first bit writer/reader used by the ARQ wire codecs. Integers are raw u64
bit patterns.
*/

import 'dart:typed_data';

import 'numeric.dart';

class Bits {
  final List<bool> bits;

  Bits([List<bool>? bits]) : bits = bits ?? <bool>[];

  void push(int v, int n) {
    for (int i = n - 1; i >= 0; i--) {
      bits.add(i < 64 && ((v >>> i) & 1) == 1);
    }
  }

  void pushBfi(int v, int n) {
    final int w = bitWidthU64(v) < 1 ? 1 : bitWidthU64(v);
    if (w > n) {
      push(v >>> (w - n), n);
    } else {
      push(v, n);
    }
  }

  void pushText7(List<int> data) {
    for (final int c in data) {
      push(c, 7);
    }
    final bool pad = last != true;
    bit(pad);
    while (bits.length % 8 != 0) {
      bit(pad);
    }
  }

  void bit(bool b) => bits.add(b);

  int get length => bits.length;

  bool get isEmpty => bits.isEmpty;

  bool? get last => bits.isEmpty ? null : bits.last;

  Uint8List pack() {
    final Uint8List out = Uint8List((bits.length + 7) ~/ 8);
    for (int i = 0; i < bits.length; i++) {
      if (bits[i]) out[i >> 3] |= 0x80 >> (i & 7);
    }
    return out;
  }

  static Bits unpack(List<int> bytes) {
    final List<bool> out = <bool>[];
    for (final int b in bytes) {
      for (int i = 7; i >= 0; i--) {
        out.add(((b >> i) & 1) == 1);
      }
    }
    return Bits(out);
  }

  @override
  bool operator ==(Object other) =>
      other is Bits &&
      other.bits.length == bits.length &&
      Iterable<int>.generate(bits.length).every((i) => other.bits[i] == bits[i]);

  @override
  int get hashCode => Object.hashAll(bits);
}

class Reader {
  final List<bool> bits;
  int pos = 0;

  Reader(this.bits);

  int get remaining => bits.length > pos ? bits.length - pos : 0;

  bool? bit() {
    if (pos >= bits.length) return null;
    return bits[pos++];
  }

  int? take(int n) {
    if (remaining < n) return null;
    int v = 0;
    for (int i = 0; i < n; i++) {
      v = (v << 1) | (bits[pos + i] ? 1 : 0);
    }
    pos += n;
    return v;
  }

  List<int>? text7() {
    if (bits.isEmpty) return null;
    final bool pad = bits.last;
    final int end = bits.lastIndexWhere((b) => b != pad) + 1;
    final List<int> out = <int>[];
    while (pos + 7 <= end) {
      out.add(take(7)!);
    }
    return out;
  }

  String? text(int n) {
    if (remaining < n) return null;
    final String s = bits.sublist(pos, pos + n).map((b) => b ? '1' : '0').join();
    pos += n;
    return s;
  }
}

/// VB `Val()` on leading digits (spaces skipped), saturating like Rust u64.
int vbVal(List<int> s) {
  BigInt a = BigInt.zero;
  final BigInt max = (BigInt.one << 64) - BigInt.one;
  for (final int c in s) {
    if (c == 0x20) continue;
    if (c < 0x30 || c > 0x39) break;
    a = a * BigInt.from(10) + BigInt.from(c - 0x30);
    if (a > max) a = max;
  }
  return a.toSigned(64).toInt();
}
