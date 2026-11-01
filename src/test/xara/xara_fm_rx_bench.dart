/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Real-time benchmark for the XARA FM receiver port (not a test). Run AOT:
  dart compile exe test/xara/xara_fm_rx_bench.dart -o build/xara_bench.exe
*/

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';

void main() {
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
    final FmReceiver rx = FmReceiver(bw, key, recs, 1);
    rx.setCtrl(Side.source, Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits),
        List<int>.generate(24, (i) => i + 1));
    final Stopwatch sw = Stopwatch()..start();
    for (int i = 0; i + 480 <= x.length; i += 480) {
      rx.feed(x.sublist(i, i + 480));
    }
    sw.stop();
    final double audio = x.length / 48000.0;
    final double cpu = sw.elapsedMilliseconds / 1000.0;
    print('${bw.name}: ${audio.toStringAsFixed(1)} s audio, ${cpu.toStringAsFixed(1)} s CPU, '
        '${(audio / cpu).toStringAsFixed(2)}x real time, ${rx.stats.decode.crcOk}/${recs.length} frames ok');
  }
}
