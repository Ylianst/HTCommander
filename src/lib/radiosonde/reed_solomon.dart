/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Reed-Solomon decoder over GF(2^8) for radiosonde frames (RS41/RS92 use
RS(255,231) with reduction polynomial 0x11D, generator alpha=2, first root
exponent b=0). Standard syndrome / Berlekamp-Massey / Chien / Forney decoder;
also provides a systematic encoder used by the round-trip tests.
*/

library;

import 'dart:typed_data';

/// Reed-Solomon codec over GF(2^8). Codeword layout matches the reference
/// `bch_ecc_mod.c`: c(x) = sum cw[i]*x^i, parity in cw[0..R-1], message in
/// cw[R..N-1]; syndromes S_j = c(alpha^(b+j)).
class ReedSolomon {
  ReedSolomon({
    this.nroots = 24,
    this.fcr = 0,
    int prim = 0x11D,
    this.alpha = 2,
    this.primPow = 1,
  }) {
    _exp = Uint8List(512);
    _log = Uint8List(256);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      x = _mulNoTable(x, alpha, prim);
    }
    for (int i = 255; i < 512; i++) {
      _exp[i] = _exp[i - 255];
    }
    // Modular inverse of primPow mod 255 (p * ip = 1).
    int ip = 1;
    for (int i = 1; i < 255; i++) {
      if ((primPow * i) % 255 == 1) {
        ip = i;
        break;
      }
    }
    _ip = ip;
    // Generator g(x) = prod_{i=0}^{nroots-1} (x - (alpha^primPow)^(fcr+i)).
    final g = <int>[1];
    for (int i = 0; i < nroots; i++) {
      final root = _exp[(primPow * (fcr + i)) % 255];
      // Multiply g by (x - root).
      final ng = List<int>.filled(g.length + 1, 0);
      for (int j = 0; j < g.length; j++) {
        ng[j] ^= _gmul(g[j], root);
        ng[j + 1] ^= g[j];
      }
      g
        ..clear()
        ..addAll(ng);
    }
    _gen = Uint8List.fromList(g);
  }

  static const int n = 255;
  final int nroots; // number of parity symbols (2t)
  final int fcr; // first consecutive root exponent (b)
  final int alpha;
  final int primPow; // p: code uses beta = alpha^p as the root base

  late final Uint8List _exp;
  late final Uint8List _log;
  late final Uint8List _gen;
  late final int _ip;

  static int _mulNoTable(int a, int b, int prim) {
    int r = 0;
    while (b > 0) {
      if (b & 1 != 0) r ^= a;
      b >>= 1;
      a <<= 1;
      if (a & 0x100 != 0) a ^= prim;
    }
    return r & 0xFF;
  }

  int _gmul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _exp[_log[a] + _log[b]];
  }

  int _ginv(int a) => _exp[255 - _log[a]];

  int _polyEval(List<int> poly, int x) {
    // Horner (highest degree first).
    int y = poly[poly.length - 1];
    for (int i = poly.length - 2; i >= 0; i--) {
      y = _gmul(y, x) ^ poly[i];
    }
    return y;
  }

  /// Systematic encode: [cw] has the message bytes already placed at
  /// cw[nroots..N-1]; this fills the parity bytes cw[0..nroots-1].
  void encode(List<int> cw) {
    // remainder of cw(x) by g(x); message occupies high coefficients.
    final rem = List<int>.filled(nroots, 0);
    for (int i = n - 1; i >= nroots; i--) {
      final feedback = cw[i] ^ (rem.isNotEmpty ? rem[nroots - 1] : 0);
      // shift rem up by one and add feedback*g.
      for (int j = nroots - 1; j > 0; j--) {
        rem[j] = rem[j - 1] ^ _gmul(feedback, _gen[j]);
      }
      rem[0] = _gmul(feedback, _gen[0]);
    }
    for (int i = 0; i < nroots; i++) {
      cw[i] = rem[i];
    }
  }

  /// Decodes [cw] (length 255) in place. Returns the number of corrected
  /// errors, or -1 if uncorrectable.
  int decode(List<int> cw) {
    // 1. Syndromes: S_i = c((alpha^p)^(fcr+i)).
    final s = List<int>.filled(nroots, 0);
    bool anyError = false;
    for (int i = 0; i < nroots; i++) {
      s[i] = _polyEval(cw, _exp[(primPow * (fcr + i)) % 255]);
      if (s[i] != 0) anyError = true;
    }
    if (!anyError) return 0;

    // 2. Berlekamp-Massey -> error locator lambda.
    var lambda = <int>[1];
    var b = <int>[1];
    int l = 0;
    int m = 1;
    int bb = 1;
    for (int nn = 0; nn < nroots; nn++) {
      int delta = s[nn];
      for (int i = 1; i <= l; i++) {
        if (i < lambda.length) {
          delta ^= _gmul(lambda[i], s[nn - i]);
        }
      }
      if (delta == 0) {
        m++;
      } else if (2 * l <= nn) {
        final t = List<int>.from(lambda);
        final scale = _gmul(delta, _ginv(bb));
        final shifted = List<int>.filled(m + b.length, 0);
        for (int i = 0; i < b.length; i++) {
          shifted[i + m] = _gmul(scale, b[i]);
        }
        lambda = _polyAdd(lambda, shifted);
        l = nn + 1 - l;
        b = t;
        bb = delta;
        m = 1;
      } else {
        final scale = _gmul(delta, _ginv(bb));
        final shifted = List<int>.filled(m + b.length, 0);
        for (int i = 0; i < b.length; i++) {
          shifted[i + m] = _gmul(scale, b[i]);
        }
        lambda = _polyAdd(lambda, shifted);
        m++;
      }
    }

    final degLambda = _deg(lambda);
    if (degLambda > nroots ~/ 2) return -1;

    // 3. Chien search: roots of lambda among field elements -> positions.
    final rootsXe = <int>[];
    final errPos = <int>[];
    for (int xe = 1; xe < 256; xe++) {
      if (_polyEval(lambda, xe) == 0) {
        final pos = (_log[_ginv(xe)] * _ip) % 255;
        rootsXe.add(xe);
        errPos.add(pos);
      }
    }
    if (rootsXe.length != degLambda) return -1;

    // 4. Forney: error values. Omega = (S * lambda) mod x^nroots.
    final omega = _polyMulMod(s, lambda, nroots);
    // lambda' (formal derivative).
    final lambdaPrime = <int>[];
    for (int i = 1; i < lambda.length; i++) {
      lambdaPrime.add(i.isOdd ? lambda[i] : 0);
    }
    if (lambdaPrime.isEmpty) lambdaPrime.add(0);

    for (int k = 0; k < rootsXe.length; k++) {
      final xe = rootsXe[k];
      final pos = errPos[k];
      final num = _polyEval(omega, xe);
      final den = _polyEval(lambdaPrime, xe);
      if (den == 0) return -1;
      // Y = X^(1-b) * Omega(xe)/Lambda'(xe), with xe = X^-1.
      int y = _gmul(num, _ginv(den));
      if (fcr == 0) {
        y = _gmul(y, _ginv(xe)); // * X
      } else if (fcr > 1) {
        y = _gmul(y, _exp[((fcr - 1) * _log[xe]) % 255]);
      }
      cw[pos] ^= y;
    }

    // Verify: syndromes must now be zero.
    for (int i = 0; i < nroots; i++) {
      if (_polyEval(cw, _exp[(primPow * (fcr + i)) % 255]) != 0) return -1;
    }
    return rootsXe.length;
  }

  List<int> _polyAdd(List<int> a, List<int> b) {
    final len = a.length > b.length ? a.length : b.length;
    final r = List<int>.filled(len, 0);
    for (int i = 0; i < a.length; i++) {
      r[i] ^= a[i];
    }
    for (int i = 0; i < b.length; i++) {
      r[i] ^= b[i];
    }
    return r;
  }

  List<int> _polyMulMod(List<int> a, List<int> b, int mod) {
    final r = List<int>.filled(mod, 0);
    for (int i = 0; i < a.length && i < mod; i++) {
      if (a[i] == 0) continue;
      for (int j = 0; j < b.length && i + j < mod; j++) {
        r[i + j] ^= _gmul(a[i], b[j]);
      }
    }
    return r;
  }

  int _deg(List<int> p) {
    int d = p.length - 1;
    while (d > 0 && p[d] == 0) {
      d--;
    }
    return d;
  }
}
