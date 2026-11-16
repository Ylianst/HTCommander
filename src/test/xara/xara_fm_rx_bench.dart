/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Real-time benchmark for the XARA FM receiver (not a test). Run AOT with assets:
  dart build cli --target=test/xara/xara_fm_rx_bench.dart --output=build/xara_bench
Set environment HT_XARA_DART=true for Dart or HT_XARA_SCALAR=true for native
without SIMD when running the resulting bundle/bin executable.
*/

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';
import 'package:htcommander/hamlib/xara/native_dsp.dart';

void _traceFrame(FmFrameRx frame) {
  int hash = 0x811c9dc5;
  void add(int b) => hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
  for (final int b in frame.bytes) {
    add(b);
  }
  final ByteData bits = ByteData(8);
  final symbols = frame.symbols;
  if (symbols == null) throw StateError('Missing benchmark constellation capture');
  for (final z in symbols) {
    for (final double value in [z.re, z.im]) {
      bits.setFloat64(0, value, Endian.little);
      for (int i = 0; i < 8; i++) {
        add(bits.getUint8(i));
      }
    }
  }
  print('TRACE ${frame.record.index} ${frame.index} ${frame.t} ${frame.tEnd} '
      '${frame.ok} ${frame.iterations} ${frame.coherence} ${frame.esn0Db} ${frame.snrDb} '
      '${frame.bps} ${symbols.length} ${hash.toRadixString(16)}');
}

void main(List<String> args) {
  final bool trace = args.contains('--trace');
  print('DSP: ${nativeDspEnabled ? "native" : "Dart"}, SIMD width: $nativeDspSimdWidth');
  for (final FmBandwidth bw in FmBandwidth.values) {
    final int key = callHash('N1CALL'.codeUnits);
    final Modulator m = Modulator(bw);
    int seed = 1;
    int rand(int n) => (seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF) % n;
    final List<double> x = List<double>.filled(24000, 0.0, growable: true);
    final List<FmRecord> recs = <FmRecord>[];
    for (int r = 1; r <= bw.numLevels; r++) {
      final FmRecord rec = FmRecord(r);
      recs.add(rec);
      final int len = bw.level(rec).frameBytes;
      final Uint8List f = buildData(
          rec, len, List<int>.generate(len - 10, (i) => rand(256)), false, 0, false, const Trailer());
      x.addAll(m.transmission(rec, key, [f], 2, const TxOptions(driveDb: -5), rand));
      x.addAll(List<double>.filled(9000, 0.0));
    }
    if (args.contains('--noise')) {
      final math.Random noise = math.Random(73);
      for (int i = 0; i < x.length; i++) {
        final double u = math.max(noise.nextDouble(), 1e-300);
        final double v = noise.nextDouble();
        x[i] += 0.003 * math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
      }
    }
    final FmReceiver rx = FmReceiver(bw, key, recs, 1)..captureSymbols = trace;
    rx.setCtrl(Side.source, Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits),
        List<int>.generate(24, (i) => i + 1));
    final Stopwatch sw = Stopwatch()..start();
    for (int i = 0; i + 480 <= x.length; i += 480) {
      rx.feed(x.sublist(i, i + 480));
      if (trace) {
        for (final FmFrameRx frame in rx.captured) {
          _traceFrame(frame);
        }
        rx.captured.clear();
      }
    }
    sw.stop();
    final double audio = x.length / 48000.0;
    final double cpu = sw.elapsedMicroseconds / 1000000.0;
    print('${bw.name}: ${audio.toStringAsFixed(1)} s audio, ${cpu.toStringAsFixed(1)} s elapsed, '
        '${(audio / cpu).toStringAsFixed(2)}x real time, ${rx.stats.decode.crcOk}/${recs.length} frames ok');
    if (rx.stats.decode.crcOk != recs.length) throw StateError('Receiver benchmark lost frames');
    print('  retained differential history: '
        '${(rx.retainedDifferenceBytes / (1024 * 1024)).toStringAsFixed(2)} MiB');
    print('  retained spectrum rows: ${(rx.retainedSpectrumBytes / 1024).toStringAsFixed(1)} KiB');
  }
}
