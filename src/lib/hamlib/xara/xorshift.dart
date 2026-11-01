/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
64-bit XorShift used by the ARQ layer. Values are raw u64 bit patterns.
*/

class XorShift {
  int _s;

  XorShift(int seed) : _s = seed | 1;

  XorShift._raw(this._s);

  XorShift copy() => XorShift._raw(_s);

  int nextU64() {
    _s ^= _s << 13;
    _s ^= _s >>> 7;
    _s ^= _s << 17;
    return _s;
  }

  /// `next_u64() % (n + 1)` with unsigned arithmetic; [n] must be below 2^63.
  int upto(int n) => _umod(nextU64(), n + 1);

  int below(int n) => ((nextU64() >>> 11) % (n < 1 ? 1 : n));

  double uniform() => (nextU64() >>> 11) / 9007199254740992.0;

  static int _umod(int a, int m) {
    if (a >= 0) return a % m;
    final int q = ((a >>> 1) ~/ m) << 1;
    int r = a - q * m;
    while (r < 0 || r >= m) {
      r -= m;
    }
    return r;
  }
}
