/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Turbo code framing, whitening, interleaving and puncturing.
*/

import 'dart:typed_data';

Uint8List frameBits(List<int> frame, int k) {
  final Uint8List bits = Uint8List(k);
  final int n = frame.length * 8 < k ? frame.length * 8 : k;
  for (int i = 0; i < n; i++) {
    bits[i] = (frame[i >> 3] >> (7 - (i & 7))) & 1;
  }
  return bits;
}

void whiten(List<int> bits, List<int> w) {
  final int n = bits.length < w.length ? bits.length : w.length;
  for (int i = 0; i < n; i++) {
    bits[i] ^= w[i];
  }
}

(Uint8List, Uint8List) _rsc(int k, int Function(int) input) {
  final Uint8List x = Uint8List(k + 3);
  final Uint8List p = Uint8List(k + 3);
  int r0 = 0, r1 = 0, r2 = 0;
  for (int t = 0; t < k + 3; t++) {
    final int u = t < k ? input(t) : r0 ^ r1;
    final int a = u ^ r0 ^ r1;
    x[t] = u;
    p[t] = a ^ r2 ^ r0;
    r0 = r1;
    r1 = r2;
    r2 = a;
  }
  return (x, p);
}

Uint8List turboEncode(List<int> info, List<int> perm, int p, int n) {
  final int k = info.length;
  final (Uint8List x1, Uint8List p1) = _rsc(k, (t) => info[t]);
  final (Uint8List x2, Uint8List p2) = _rsc(k, (t) => info[perm[t]]);
  final Uint8List out = Uint8List(n);
  int o = 0;
  void put(int v) {
    if (o >= n) throw StateError('turbo output exceeds N $n');
    out[o++] = v;
  }

  for (int t = 0; t < k; t++) {
    put(x1[t]);
    if (p == 1 || t % p == 0) put(p1[t]);
    if (p == 1 || t % p == p ~/ 2) put(p2[t]);
  }
  for (int t = k; t < k + 3; t++) {
    put(x1[t]);
    put(p1[t]);
    put(x2[t]);
    put(p2[t]);
  }
  return out;
}

Uint8List interleave(List<int> coded, List<int> chan) {
  final Uint8List out = Uint8List(chan.length);
  for (int i = 0; i < chan.length; i++) {
    out[i] = coded[chan[i]];
  }
  return out;
}

int puncturePeriod(int rate) {
  switch (rate) {
    case 2:
      return 1;
    case 3:
      return 2;
    case 4:
      return 4;
    case 5:
      return 6;
    case 6:
      return 8;
    case 7:
      return 10;
  }
  throw ArgumentError('codeRateIndex $rate');
}

int puncturedLen(int k, int p) {
  if (p == 1) return 3 * k + 12;
  final int p1 = (k + p - 1) ~/ p;
  final int half = p ~/ 2;
  final int p2 = k > half ? (k - half - 1) ~/ p + 1 : 0;
  return k + p1 + p2 + 12;
}
