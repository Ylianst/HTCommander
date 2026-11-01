/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 4b: FM receiver. Ports upstream `tests/fm_rx.rs`: modulated
streams (data and control frames, with noise) are fed through the receiver in
480-sample blocks and every frame, code and transmission must be recovered.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/dsp.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_rx_frontend.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';
import 'package:htcommander/hamlib/xara/receiver_common.dart';

import 'xara_test_rng.dart';

FmRecord _rec(int i) => FmRecord.fromIndex(i)!;

List<FmRecord> _recs(List<int> ids) => ids.map(_rec).toList();

class _Burst {
  final int? record;
  final int? code;
  final List<Uint8List> frames;

  _Burst(this.record, this.code, this.frames);
}

class _Stream {
  final List<double> x = List<double>.filled(12000, 0.0, growable: true);
  final List<_Burst> bursts = <_Burst>[];
  final TestRng rng = TestRng(99);

  void gap(int n) => x.addAll(List<double>.filled(n, 0.0));

  void data(Modulator m, int record, int key, List<Uint8List> frames, int lead) {
    x.addAll(m.transmission(_rec(record), key, frames, lead, const TxOptions(driveDb: -5.0), rng.below));
    bursts.add(_Burst(record, null, frames));
    gap(9000);
  }

  void ctrl(Codebook cb, int code, int lead) {
    x.addAll(frameAudio(cb, code, lead, -5.0));
    bursts.add(_Burst(null, code, <Uint8List>[]));
    gap(9000);
  }

  List<double> noisy(TestRng r, double sigma) => x.map((v) => v + sigma * r.gauss()).toList();
}

List<FmEvent> _run(FmReceiver rx, List<double> x) {
  final List<FmEvent> ev = <FmEvent>[];
  for (int i = 0; i < x.length; i += 480) {
    ev.addAll(rx.feed(x.sublist(i, math.min(i + 480, x.length))));
  }
  ev.addAll(rx.flush());
  return ev;
}

Uint8List _payload(TestRng rng, int record, FmBandwidth bw, int n, int report) {
  final int len = bw.level(_rec(record)).frameBytes;
  return buildData(_rec(record), len, rng.bytes(n), false, 3, false, Trailer(leadReport: report));
}

void _check(List<FmEvent> ev, _Stream s) {
  final List<Uint8List> frames = <Uint8List>[
    for (final FmEvent e in ev)
      if (e is FrameEv<FmCtrlEvent, FmRecord, FmFrameRx> && e.frame.ok) e.frame.bytes,
  ];
  final List<FmTransmission> txs = <FmTransmission>[
    for (final FmEvent e in ev)
      if (e is TxEv<FmCtrlEvent, FmRecord, FmFrameRx>) e.tx,
  ];
  final List<int> codes = <int>[
    for (final FmEvent e in ev)
      if (e is CtrlEv<FmCtrlEvent, FmRecord, FmFrameRx>) e.ctrl.det.code,
  ];
  final List<Uint8List> wantFrames = <Uint8List>[for (final _Burst b in s.bursts) ...b.frames];
  final List<int> wantCodes = <int>[for (final _Burst b in s.bursts) if (b.code != null) b.code!];
  final List<String> wantTx = <String>[
    for (final _Burst b in s.bursts) if (b.record != null) '${b.record}x${b.frames.length}',
  ];
  final List<String> gotTx = txs.map((t) => '${t.record.index}x${t.frames.length}').toList();
  expect(gotTx, wantTx);
  expect(txs.every((t) => t.complete), isTrue, reason: 'incomplete transmissions');
  expect(frames, wantFrames);
  expect(codes, wantCodes);
}

void main() {
  group('fm rx building blocks', () {
    test('front end is a 3 kHz complex band-pass decimating by 8', () {
      final FrontEnd fe = FrontEnd();
      for (final (double hz, bool pass) in const [(1500.0, true), (3000.0, true), (5000.0, true), (8000.0, false), (11000.0, false)]) {
        final FrontEnd f = FrontEnd();
        final List<double> x = List<double>.generate(48000, (n) => math.cos(2 * math.pi * hz * n / 48000));
        final List<double> y = <double>[];
        int? m0;
        for (int i = 0; i < x.length; i += 480) {
          final (int m, Float64List out) = f.process(x.sublist(i, i + 480));
          m0 ??= m;
          y.addAll(out);
        }
        expect(m0, 0);
        double p = 0;
        for (int i = 2 * 2000; i < y.length; i++) {
          p += y[i] * y[i];
        }
        p /= (y.length - 4000) / 2;
        expect(pass ? p > 0.2 : p < 1e-4, isTrue, reason: '$hz Hz power $p');
      }
      int total = 0;
      for (int i = 0; i < 100; i++) {
        total += fe.process(List<double>.filled(480, 0.0)).$2.length ~/ 2;
      }
      expect(total, (48000 - 1 - 240) ~/ 8 + 1);
    });

    test('kaiser lowpass and helpers', () {
      final List<double> h = kaiserLowpass(31, 3000, 48000, 6.76);
      expect(h.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-12));
      for (int i = 0; i < 31; i++) {
        expect(h[i], closeTo(h[30 - i], 1e-15));
      }
      expect(median([3.0, 1.0, 2.0]), 2.0);
      expect(median([4.0, 1.0, 2.0, 3.0]), 2.5);
      expect(peakMid([0, 1, 5, 5, 5, 1, 0], 2, 0.0), 3);
      expect(argmax([1, 3, 3, 2]), 1);
      expect(thin([1, 2, 3, 4, 5, 6], 3), [1, 3, 5]);
      expect(totalCmp(-0.0, 0.0), -1);
      final double posNan = (ByteData(8)..setInt64(0, 0x7FF8000000000000)).getFloat64(0);
      expect(totalCmp(posNan, double.infinity), 1);
      expect(totalCmp(-posNan, double.negativeInfinity), -1);
      expect(floorDiv(-1, 4), -1);
      expect(floorDiv(7, 4), 1);
      final Hold<int> hold = Hold<int>(2, 10);
      expect(hold.offer(0, (1.0, 0)), isNull);
      expect(hold.offer(1, (3.0, 1)), isNull);
      expect(hold.offer(2, (2.0, 2)), isNull);
      expect(hold.offer(4, null), (1, 3.0, 1));
      expect(hold.offer(5, (9.0, 5)), isNull);
      expect(hold.best, isNull);
      expect(hold.offer(11, (1.0, 11)), isNull);
      expect(hold.offer(14, null), (11, 1.0, 11));
      final SampleTrack t = SampleTrack(4, stride: 2);
      t.append(0, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect([t.base, t.end], [0, 5]);
      t.append(5, [11, 12, 13, 14, 15, 16, 17, 18]);
      expect([t.base, t.end, t.at(5), t.at(5, 1)], [5, 9, 11.0, 12.0]);
      t.append(20, [1, 1]);
      expect([t.base, t.end], [20, 21]);
      expect(t.meanPower(19, 21), 1.0);
    });
  });

  group('fm receiver', () {
    test('loopback link', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final Modulator m = Modulator(bw);
      final TestRng rng = TestRng(7);
      final int key = callHash('N1CALL'.codeUnits);
      final Codebook cb = Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits);
      final _Stream s = _Stream();
      final Uint8List r0 = Record0.connect('N0CALL', 'N1CALL', '', '', false, false).toBytes()!;
      s.data(m, 0, 0, [r0], 21);
      s.ctrl(cb, 23, 28);
      s.ctrl(cb, 14, 28);
      s.data(m, 15, key, [_payload(rng, 15, bw, 11, 1)], 25);
      s.ctrl(cb, 7, 1);
      s.data(m, 2, key, [_payload(rng, 2, bw, 705, 27)], 1);
      s.ctrl(cb, 1, 1);
      s.data(m, 2, key, [_payload(rng, 2, bw, 705, 27), _payload(rng, 2, bw, 300, 27)], 1);
      s.ctrl(cb, 6, 1);
      s.data(m, 1, key, [_payload(rng, 1, bw, 169, 27)], 1);
      s.data(m, 14, key, [_payload(rng, 14, bw, 89, 27)], 1);
      s.data(m, 1, key, [_payload(rng, 1, bw, 334, 27), _payload(rng, 1, bw, 334, 27)], 2);
      s.ctrl(cb, 4, 2);
      s.data(m, 16, key, [_payload(rng, 16, bw, 12, 0)], 9);
      s.ctrl(cb, 3, 2);
      final List<int> codes = List<int>.generate(24, (i) => i + 1);
      for (final (double sigma, int seed) in const [(0.0, 1), (0.01, 2), (0.03, 3)]) {
        final List<double> x = s.noisy(TestRng(seed), sigma);
        final FmReceiver rx = FmReceiver(bw, key, _recs([0, 1, 2, 14, 15, 16]), 1);
        rx.setCtrl(Side.source, cb, codes);
        _check(_run(rx, x), s);
        expect(rx.stats.unexpectedFrame2, 2, reason: 'sigma $sigma');
      }
    });

    test('wrong key is silent', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final Modulator m = Modulator(bw);
      final TestRng rng = TestRng(9);
      final _Stream s = _Stream();
      s.data(m, 1, callHash('N2CALL'.codeUnits), [_payload(rng, 1, bw, 20, 1)], 3);
      s.ctrl(Codebook.forLink('N3CALL'.codeUnits, 'N2CALL'.codeUnits), 1, 3);
      final FmReceiver rx = FmReceiver(bw, callHash('N1CALL'.codeUnits), _recs([1, 14, 15]), 1);
      rx.setCtrl(Side.source, Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits),
          List<int>.generate(24, (i) => i + 1));
      expect(_run(rx, s.noisy(rng, 0.01)), isEmpty);
    });

    test('all levels loopback', () {
      for (final FmBandwidth bw in FmBandwidth.values) {
        final Modulator m = Modulator(bw);
        final TestRng rng = TestRng(11);
        final int key = callHash('N1CALL'.codeUnits);
        final _Stream s = _Stream();
        final List<int> levels = List<int>.generate(bw.numLevels, (i) => i + 1);
        for (final int r in levels) {
          final int n = bw.level(_rec(r)).frameBytes - 10;
          s.data(m, r, key, [_payload(rng, r, bw, n, 5)], 2);
        }
        final FmReceiver rx = FmReceiver(bw, key, _recs(levels), 1);
        _check(_run(rx, s.noisy(TestRng(5), 0.002)), s);
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('expected double with lost frame 1', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final Modulator m = Modulator(bw);
      final TestRng rng = TestRng(13);
      final int key = callHash('N1CALL'.codeUnits);
      final List<Uint8List> f = [_payload(rng, 2, bw, 705, 27), _payload(rng, 2, bw, 100, 27)];
      final Float64List tx = m.transmission(_rec(2), key, f, 2, const TxOptions(), rng.below);
      final List<double> x = List<double>.filled(24000, 0.0, growable: true);
      final int a = x.length + 2 * 1152;
      x.addAll(tx);
      final int b = a + 199 * 1152;
      x.fillRange(a, b, 0.0);
      x.addAll(List<double>.filled(24000, 0.0));
      final FmReceiver rx = FmReceiver(bw, key, _recs([1, 2]), 2);
      rx.markTxEnd(20000);
      final List<FmTransmission> txs = <FmTransmission>[
        for (final FmEvent e in _run(rx, x))
          if (e is TxEv<FmCtrlEvent, FmRecord, FmFrameRx>) e.tx,
      ];
      expect(txs.length, 1);
      expect(txs[0].frames.map((fr) => [fr.missing, fr.ok]).toList(), [
        [true, false],
        [false, true],
      ]);
      expect(txs[0].frames[1].bytes, f[1]);
    });

    test('hiss after a single frame is not frame 2', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final Modulator m = Modulator(bw);
      final int key = callHash('N1CALL'.codeUnits);
      for (final (int record, int n) in const [(15, 11), (14, 60), (1, 200)]) {
        for (final int tailMs in const [100, 300, 1000]) {
          for (final double level in const [0.3, 1.0]) {
            final TestRng rng = TestRng(5);
            final _Stream s = _Stream();
            final int start = s.x.length;
            s.data(m, record, key, [_payload(rng, record, bw, n, 1)], 25);
            final int end = s.x.length - 9000;
            s.gap(tailMs * 48);
            double e2 = 0;
            for (int i = start; i < end; i++) {
              e2 += s.x[i] * s.x[i];
            }
            final double rms = math.sqrt(e2 / (end - start));
            final List<(double, double)> tones = <(double, double)>[
              for (int k = 6; k < 60; k++) (k * 50.0, rng.below(1000) / 1000.0 * 2 * math.pi),
            ];
            final double g = level * rms / math.sqrt(tones.length / 2.0);
            for (int i = 0; i < tailMs * 48; i++) {
              final double t = i / 48000.0;
              double v = 0;
              for (final (double f, double ph) in tones) {
                v += math.sin(2 * math.pi * f * t + ph);
              }
              s.x[end + i] = g * v;
            }
            s.gap(48000);
            final FmReceiver rx = FmReceiver(bw, key, _recs([1, 14, 15]), 1);
            final List<(int, bool, int)> txs = <(int, bool, int)>[];
            for (int i = 0; i * 480 < s.x.length; i++) {
              for (final FmEvent e in rx.feed(s.x.sublist(i * 480, math.min((i + 1) * 480, s.x.length)))) {
                if (e is TxEv<FmCtrlEvent, FmRecord, FmFrameRx>) {
                  txs.add((e.tx.frames.length, e.tx.complete, (i + 1) * 480 - end));
                }
              }
            }
            final String what = 'rec $record tail $tailMs ms x$level';
            expect(txs.map((t) => [t.$1, t.$2]).toList(), [
              [1, true],
            ], reason: what);
            expect(txs[0].$3 < 12000, isTrue, reason: '$what: closed ${txs[0].$3} samples after frame 1');
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
