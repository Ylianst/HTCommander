/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 4a: turbo decoder, frame decoding and soft demapping.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/complex.dart';
import 'package:htcommander/hamlib/xara/constellation.dart';
import 'package:htcommander/hamlib/xara/decode.dart';
import 'package:htcommander/hamlib/xara/demap.dart';
import 'package:htcommander/hamlib/xara/fec.dart';
import 'package:htcommander/hamlib/xara/fm_code.dart';
import 'package:htcommander/hamlib/xara/fm_constellation.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/hf_code.dart';
import 'package:htcommander/hamlib/xara/hf_level.dart';
import 'package:htcommander/hamlib/xara/seq.dart' as seq;
import 'package:htcommander/hamlib/xara/turbo_decoder.dart';

import 'xara_test_rng.dart';

/// Independent textbook max-log BCJR + turbo loop for a single window
/// (k + 3 <= 1024), derived directly from the RSC encoder equations.
Decoded _reference(Split sp, List<int> perm, int iters, double scale, (int, CrcCheck)? early) {
  final int k = perm.length, tLen = k + 3;
  const double neg = -1e9;
  (int, int) step(int s, int u) {
    final int r0 = (s >> 2) & 1, r1 = (s >> 1) & 1, r2 = s & 1;
    final int a = u ^ r0 ^ r1;
    return ((r1 << 2) | (r2 << 1) | a, a ^ r2 ^ r0);
  }

  double gamma(double x, double p, int u, int c) => 0.5 * (x * (1 - 2 * u) + p * (1 - 2 * c));

  Float64List siso(Float64List x, Float64List p) {
    final List<Float64List> alpha = List<Float64List>.generate(tLen + 1, (_) => Float64List(8));
    alpha[0].setAll(0, <double>[0, neg, neg, neg, neg, neg, neg, neg]);
    for (int t = 0; t < tLen; t++) {
      final Float64List n = Float64List(8)..fillRange(0, 8, double.negativeInfinity);
      for (int s = 0; s < 8; s++) {
        for (int u = 0; u < 2; u++) {
          final (int ns, int c) = step(s, u);
          n[ns] = math.max(n[ns], alpha[t][s] + gamma(x[t], p[t], u, c));
        }
      }
      for (int d = 0; d < 8; d++) {
        alpha[t + 1][d] = n[d] - n[0];
      }
    }
    final Float64List out = Float64List(k);
    Float64List beta = Float64List.fromList(<double>[0, neg, neg, neg, neg, neg, neg, neg]);
    for (int t = tLen - 1; t >= 0; t--) {
      final List<List<double>> bs = List.generate(8, (s) {
        return List<double>.generate(2, (u) {
          final (int ns, int c) = step(s, u);
          return beta[ns] + gamma(x[t], p[t], u, c);
        });
      });
      if (t < k) {
        double m0 = double.negativeInfinity, m1 = double.negativeInfinity;
        for (int s = 0; s < 8; s++) {
          m0 = math.max(m0, alpha[t][s] + bs[s][0]);
          m1 = math.max(m1, alpha[t][s] + bs[s][1]);
        }
        out[t] = scale * ((m0 - m1) - x[t]);
      }
      final Float64List n = Float64List.fromList(List<double>.generate(8, (s) => math.max(bs[s][0], bs[s][1])));
      beta = Float64List.fromList(List<double>.generate(8, (s) => n[s] - n[0]));
    }
    return out;
  }

  Float64List le21 = Float64List(k);
  final Uint8List bits = Uint8List(k);
  int ran = 0;
  for (int it = 1; it <= iters; it++) {
    final Float64List x1 = Float64List(tLen);
    for (int t = 0; t < tLen; t++) {
      x1[t] = t < k ? sp.ls[t] + le21[t] : sp.ls[t];
    }
    final Float64List e1 = siso(x1, sp.lp1);
    final Float64List x2 = Float64List(tLen);
    for (int t = 0; t < tLen; t++) {
      x2[t] = t < k ? sp.ls2[t] + e1[perm[t]] : sp.ls2[t];
    }
    final Float64List e2 = siso(x2, sp.lp2);
    final Float64List nl = Float64List(k);
    for (int i = 0; i < k; i++) {
      nl[perm[i]] = e2[i];
    }
    le21 = nl;
    bool changed = false;
    for (int j = 0; j < k; j++) {
      final int b = (sp.ls[j] + e1[j]) + le21[j] < 0 ? 1 : 0;
      if (b != bits[j]) changed = true;
      bits[j] = b;
    }
    ran = it;
    if (early != null && it >= early.$1 && it < iters && !changed && early.$2.ok(bits)) break;
  }
  return Decoded(bits, ran);
}

List<int> _shuffle(int k, TestRng r) {
  final List<int> perm = List<int>.generate(k, (i) => i);
  for (int i = k - 1; i > 0; i--) {
    final int jj = (r.nextU64() >>> 1) % (i + 1);
    final int t = perm[i];
    perm[i] = perm[jj];
    perm[jj] = t;
  }
  return perm;
}

void main() {
  group('trellis', () {
    test('tables match the RSC encoder', () {
      for (int s = 0; s < 8; s++) {
        for (int u = 0; u < 2; u++) {
          final int r0 = (s >> 2) & 1, r1 = (s >> 1) & 1, r2 = s & 1;
          final int a = u ^ r0 ^ r1;
          expect(trellisNext[s][u], (r1 << 2) | (r2 << 1) | a);
          expect(trellisPar[s][u], (a ^ r2 ^ r0) == 1);
        }
      }
    });
  });

  group('split', () {
    test('recovers systematic and parity streams for every puncture period', () {
      final TestRng r = TestRng(5);
      for (final int p in [1, 2, 4, 6, 8, 10]) {
        const int k = 157;
        final Uint8List info = Uint8List.fromList(List<int>.generate(k, (_) => r.nextU64() & 1));
        final List<int> perm = _shuffle(k, r);
        final Uint8List coded = turboEncode(info, perm, p, puncturedLen(k, p));
        final List<double> llr = coded.map((b) => 1.0 - 2.0 * b).toList();
        final Split s = split(llr, perm, p);
        for (int t = 0; t < k; t++) {
          expect(s.ls[t], 1.0 - 2.0 * info[t]);
          expect(s.ls2[t], 1.0 - 2.0 * info[perm[t]]);
          if (!(p == 1 || t % p == 0)) expect(s.lp1[t], 0.0);
          if (!(p == 1 || t % p == p ~/ 2)) expect(s.lp2[t], 0.0);
        }
        expect(() => split(llr.sublist(0, llr.length - 1), perm, p), throwsStateError);
      }
      final Split nf = split([double.nan, double.infinity, ...List<double>.filled(100, 1)], [0, 1], 1);
      expect([nf.ls[0], nf.lp1[0]], [0.0, 0.0]);
    });
  });

  group('turbo decoder', () {
    test('single-window schedule equals an independent max-log BCJR', () {
      final TestRng r = TestRng(9);
      final List<int> white = seq.whitening(seq.hfSeed);
      for (int trial = 0; trial < 24; trial++) {
        final int k = 8 * (5 + r.below(120));
        final int p = const [1, 2, 4, 6, 8, 10][trial % 6];
        final List<int> perm = _shuffle(k, r);
        final Uint8List info = Uint8List.fromList(List<int>.generate(k, (_) => r.nextU64() & 1));
        final Uint8List coded = turboEncode(info, perm, p, puncturedLen(k, p));
        final double amp = 0.4 + 2.0 * r.uniform();
        final List<double> llr = coded.map((b) => (1.0 - 2.0 * b) * amp + 1.2 * r.gauss()).toList();
        final Split sp = split(llr, perm, p);
        final CrcCheck check = CrcCheck(white, k ~/ 8);
        for (final bool early in [false, true]) {
          final (int, CrcCheck)? e = early ? (2, check) : null;
          final Decoded a = const TurboDecoder().decode(sp, perm, 10, 0.7, e);
          final Decoded b = _reference(sp, perm, 10, 0.7, e);
          expect(a.bits, b.bits, reason: 'k=$k p=$p early=$early');
          expect(a.iterations, b.iterations, reason: 'k=$k p=$p early=$early');
        }
      }
    });

    test('decodes long multi-window, multi-segment blocks', () {
      final TestRng r = TestRng(13);
      for (final int k in [1021, 1022, 2048, 4100, 20000, 58455 ~/ 8 * 8]) {
        final List<int> perm = _shuffle(k, r);
        final Uint8List info = Uint8List.fromList(List<int>.generate(k, (_) => r.nextU64() & 1));
        final Uint8List coded = turboEncode(info, perm, 4, puncturedLen(k, 4));
        final List<double> llr = coded.map((b) => (1.0 - 2.0 * b) * 2.0 + r.gauss()).toList();
        final Decoded d = const TurboDecoder().decode(split(llr, perm, 4), perm, 10, 0.7, null);
        expect(d.bits, info, reason: 'k=$k');
        expect(d.iterations, 10);
      }
    });
  });

  group('frame decode', () {
    test('noisy LLRs decode on every HF level', () {
      final TestRng rng = TestRng(1);
      for (final HfBandwidth bw in HfBandwidth.values) {
        final HfFrameDecoder d = HfFrameDecoder(bw);
        for (final HfRecord rec in bw.levels) {
          final HfLevel l = bw.level(rec);
          final Uint8List frame = randomFrame(rng, l.frameBytes);
          final Uint8List tx = hfEncode(bw, rec, frame);
          final List<double> llr = tx.map((b) => (1.0 - 2.0 * b) * 2.0 + rng.gauss()).toList();
          final FrameOut out = d.decode(rec, llr);
          expect(out.ok, isTrue, reason: '${bw.hz} record ${rec.value}');
          expect(out.bytes, frame, reason: '${bw.hz} record ${rec.value}');
          expect(out.iterations < 10, isTrue, reason: '${bw.hz} record ${rec.value}: ${out.iterations}');
        }
      }
    });

    test('noisy LLRs decode on every FM record', () {
      final TestRng rng = TestRng(4);
      for (final FmBandwidth bw in FmBandwidth.values) {
        final FmCodec c = FmCodec(bw);
        for (int i = 0; i < fmRecords; i++) {
          final FmRecord rec = FmRecord(i);
          final Uint8List frame = randomFrame(rng, bw.level(rec).frameBytes);
          final List<double> llr = c.encode(rec, frame).map((b) => (1.0 - 2.0 * b) * 2.0 + rng.gauss()).toList();
          final FrameOut out = c.decode(rec, llr);
          expect(out.ok, isTrue, reason: '${bw.name} record $i');
          expect(out.bytes, frame, reason: '${bw.name} record $i');
          expect(out.iterations < 10, isTrue, reason: '${bw.name} record $i');
        }
      }
    });

    test('noise fails CRC after all iterations', () {
      final TestRng rng = TestRng(2);
      final HfFrameDecoder d = HfFrameDecoder(HfBandwidth.hz2300);
      for (final int r in [1, 5, 12]) {
        final HfRecord rec = HfRecord(r);
        final int n = HfBandwidth.hz2300.level(rec).n;
        final FrameOut out = d.decode(rec, List<double>.generate(n, (_) => rng.gauss()));
        expect(out.ok, isFalse);
        expect(out.iterations, 10);
      }
    });

    test('early stop can be disabled', () {
      final TestRng rng = TestRng(6);
      final FmCodec c = FmCodec(FmBandwidth.narrow)..early = false;
      final Uint8List frame = randomFrame(rng, FmBandwidth.narrow.level(FmRecord.connect).frameBytes);
      final List<double> llr = c.encode(FmRecord.connect, frame).map((b) => (1.0 - 2.0 * b) * 4.0).toList();
      final FrameOut out = c.decode(FmRecord.connect, llr);
      expect(out.ok, isTrue);
      expect(out.iterations, 10);
      expect(() => c.decode(FmRecord.connect, llr.sublist(1)), throwsArgumentError);
    });
  });

  group('demap', () {
    List<double> brute(Cx z, List<Cx> cst, double nvar) {
      final int bps = cst.length.bitLength - 1;
      return List<double>.generate(bps, (b) {
        final int sh = bps - 1 - b;
        double d0 = double.infinity, d1 = double.infinity;
        for (int j = 0; j < cst.length; j++) {
          final double d = (z - cst[j]).normSqr;
          if (((j >> sh) & 1) == 0) {
            d0 = math.min(d0, d);
          } else {
            d1 = math.min(d1, d);
          }
        }
        return (d1 - d0) / nvar;
      });
    }

    test('matches exact max-log on constellation points and near them', () {
      final TestRng rng = TestRng(8);
      final List<List<Cx>> all = <List<Cx>>[
        for (int b = 1; b <= 8; b++) fmConstellation(b),
        for (int b = 1; b <= 5; b++) constellation(b),
      ];
      for (final List<Cx> cst in all) {
        for (int h = 0; h < cst.length; h++) {
          final List<double> got = <double>[];
          softBits(<Cx>[cst[h]], cst, 0.5, got);
          final List<double> want = brute(cst[h], cst, 0.5);
          for (int b = 0; b < want.length; b++) {
            expect(got[b], closeTo(want[b], 1e-12), reason: 'M=${cst.length} h=$h b=$b');
          }
        }
        if (cst.length <= 8) {
          for (int i = 0; i < 50; i++) {
            final Cx z = Cx(rng.gauss(), rng.gauss());
            final List<double> got = <double>[];
            softBits(<Cx>[z], cst, 0.3, got);
            final List<double> want = brute(z, cst, 0.3);
            for (int b = 0; b < want.length; b++) {
              expect(got[b], closeTo(want[b], 1e-12));
            }
          }
        }
      }
    });

    test('weights, nearest, energy llrs and cache', () {
      final List<Cx> cst = fmConstellation(4);
      final Demapper d = demapper(cst);
      expect(identical(d, demapper(List<Cx>.of(cst))), isTrue);
      expect(d.nearest(cst[7]), (7, 0.0));
      final List<double> a = <double>[], b = <double>[];
      d.softBits(<Cx>[const Cx(0.1, -0.2)], 1.0, null, a);
      d.softBits(<Cx>[const Cx(0.1, -0.2)], 1.0, <double>[3.0], b);
      for (int i = 0; i < 4; i++) {
        expect(b[i], closeTo(3 * a[i], 1e-12));
      }
      final List<double> e = <double>[];
      energyLlrs(<double>[0.0, -4.0], 1, e);
      expect(e, [4.0]);
      final List<double> n = <double>[];
      energyLlrs(<double>[double.nan, -1.0, -2.0, -3.0], 2, n);
      expect(n, [1.0, -1.0]);
    });
  });
}
