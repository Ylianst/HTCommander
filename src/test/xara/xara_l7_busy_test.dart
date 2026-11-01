/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Layer 7 tests: the channel-busy detector. Ports XARA's `xara-phy/tests/busy.rs`
(except the HF PSK case, which needs the HF modulator that is not ported yet).
*/

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/busy.dart';
import 'package:htcommander/hamlib/xara/hf_level.dart';

import 'xara_test_rng.dart';
import 'xara_vectors.dart';

const int block48 = 128 * 16;

HfBandwidth bwOf(Object? v) => HfBandwidth.values.firstWhere((b) => b.hz == (v as num).toInt());

List<double> spectrum(Map<String, dynamic> v, int n) {
  final List<double> p = List<double>.filled(n, 0.0);
  v.forEach((k, x) => p[int.parse(k)] = (x as num).toDouble());
  return p;
}

List<double> noise(TestRng r, int n, double rms) => List<double>.generate(n, (_) => rms * r.gauss());

double db(double x) => math.pow(10.0, x / 20.0).toDouble();

List<double> tone(int n, double hz, double amp) =>
    List<double>.generate(n, (i) => amp * math.sin(2.0 * math.pi * hz * i / 48000.0));

List<(int, bool)> run(Busy b, List<double> x) {
  final List<(int, bool)> edges = <(int, bool)>[];
  for (int i = 0; i * 480 < x.length; i++) {
    final int end = math.min((i + 1) * 480, x.length);
    for (final bool e in b.feed(x.sublist(i * 480, end), false)) {
      edges.add((end, e));
    }
  }
  return edges;
}

List<double> add(List<double> a, List<double> b) => List<double>.generate(a.length, (i) => a[i] + b[i]);

void main() {
  group('busy', () {
    test('tone detector matches vector', () {
      for (final dynamic c in loadDoc('hf/busy')['detector1']['cases'] as List) {
        final HfBandwidth bw = bwOf(c['bw']);
        final List<double> p = spectrum(c['spectrum'] as Map<String, dynamic>, 128);
        expect(toneBand(bw).$1, (c['bins'][0] as num).toInt());
        expect(detectTone(p, bw), c['busy'] as bool, reason: '$c');
      }
    });

    test('signature detector matches vector', () {
      final dynamic d2 = loadDoc('hf/busy')['detector2'];
      for (final HfBandwidth bw in HfBandwidth.values) {
        final List<Signature> want = <Signature>[
          for (final dynamic s in d2['signatures'] as List)
            if (bwOf(s['bw']) == bw)
              Signature(HfRecord((s['record'] as num).toInt()), ints(s['carrier_bins']), ints(s['gap_bins'])),
        ];
        expect(signatures(bw), want, reason: '$bw');
      }
      for (final dynamic c in d2['cases'] as List) {
        final HfBandwidth bw = bwOf(c['bw']);
        final Signature sig = signatures(bw).firstWhere((s) => s.record.value == (c['record'] as num).toInt());
        final List<double> s = spectrum(c['S'] as Map<String, dynamic>, 64);
        expect(signatureThreshold(bw), (c['threshold'] as num).toDouble());
        expect(detectSignature(s, sig, signatureThreshold(bw)), c['busy'] as bool, reason: '$c');
      }
    });

    test('silence and noise rarely trip', () {
      for (final HfBandwidth bw in HfBandwidth.values) {
        expect(run(Busy(bw), List<double>.filled(48000 * 3, 0.0)), isEmpty);
        final Busy b = Busy(bw);
        run(b, noise(TestRng(7), 48000 * 20, db(-15.0)));
        expect(b.hits[0] == 0 && b.hits[1] <= 3, isTrue, reason: '$bw ${b.hits}');
      }
    });

    test('tone in noise hangs 34 blocks', () {
      final Busy b = Busy(HfBandwidth.hz2300);
      final TestRng n = TestRng(3);
      final List<double> x = noise(n, 48000, db(-30.0));
      x.addAll(add(tone(9600, 1500.0, db(-20.0)), noise(n, 9600, db(-30.0))));
      x.addAll(noise(n, 48000 * 3, db(-30.0)));
      final List<(int, bool)> edges = run(b, x);
      expect(edges.map((e) => e.$2).toList(), <bool>[true, false], reason: '$edges');
      final double off = (edges[1].$1 - 57600.0) / 48000.0;
      final double h = hang * block48 / 48000.0;
      expect(off >= h - 0.09 && off <= h + 0.05, isTrue, reason: '$off');
      expect(edges[0].$1 < 48000 + 2 * block48 + 480, isTrue);
    });

    test('tone threshold is 24 dB over the floor', () {
      final TestRng n = TestRng(11);
      final double sigma = db(-30.0);
      for (final (double binDb, bool want) in <(double, bool)>[(8.0, false), (30.0, true)]) {
        final Busy b = Busy(HfBandwidth.hz2300);
        final List<double> nz = noise(n, 48000 * 2, sigma);
        final List<double> t = tone(nz.length, 1500.0, sigma * math.sqrt(db(binDb) * db(binDb) / 1024.0));
        run(b, add(nz, t));
        expect(b.hits[0] > 0, want, reason: '$binDb dB ${b.hits}');
      }
    });

    test('quiet tone is gated', () {
      final Busy b = Busy(HfBandwidth.hz2300);
      final TestRng n = TestRng(13);
      List<double> floor(List<double> x) => add(x, noise(n, x.length, db(-75.0)));
      expect(run(b, floor(tone(48000 * 3, 1500.0, db(-52.0)))), isEmpty, reason: '${b.hits}');
      final List<(int, bool)> edges = run(b, floor(tone(48000, 1500.0, db(-40.0))));
      expect(edges.isNotEmpty ? edges.first.$2 : null, isTrue);
    });

    test('forced holds and releases after hang', () {
      final Busy b = Busy(HfBandwidth.hz2300);
      expect(b.feed(List<double>.filled(480, 0.0), true), <bool>[true]);
      for (int i = 0; i < 100; i++) {
        expect(b.feed(List<double>.filled(480, 0.0), true), isEmpty);
      }
      final List<(int, bool)> edges = run(b, List<double>.filled(48000 * 2, 0.0));
      expect(edges.length, 1);
      expect(edges[0].$2, isFalse);
      final double t = edges[0].$1 / 48000.0;
      expect(t >= 1.40 && t < 1.50, isTrue, reason: '$t');
    });
  });
}
