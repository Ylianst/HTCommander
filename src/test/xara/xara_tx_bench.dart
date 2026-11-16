/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Standalone AOT benchmark for phasor setup and driver TX buffering.
Build with native assets using `dart build cli`, then run with `phasors` or `tx`.
*/

// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/xara/complex.dart';
import 'package:htcommander/hamlib/xara/fm_code.dart';
import 'package:htcommander/hamlib/xara/fm_station.dart';
import 'package:htcommander/hamlib/xara/xara_driver.dart';

class _BurstStation implements FmStation {
  static const int samples = 20 * stationRate + 137;
  int _now = 0;
  @override
  int keyedFirst = -1;
  @override
  int keyedLast = -1;

  @override
  int get now => _now;
  @override
  bool get transmitting => _now < samples;

  @override
  void process(List<double> input, List<double> output) {
    final int n = math.min(output.length, samples - _now);
    keyedFirst = n > 0 ? 0 : -1;
    keyedLast = n - 1;
    for (int i = 0; i < n; i++) {
      output[i] = 0.6 * math.sin((_now + i) * 0.1);
    }
    _now += output.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main(List<String> args) {
  if (args.length != 1 || !const ['phasors', 'tx'].contains(args.single)) {
    throw ArgumentError('Expected phasors or tx');
  }
  final Stopwatch watch = Stopwatch()..start();
  if (args.single == 'phasors') {
    final List<Phasors> retained = <Phasors>[];
    double checksum = 0.0;
    for (int key = 0; key < 64; key++) {
      final Phasors p = phasors(key);
      checksum += p[key][key].re;
      if (key >= 56) retained.add(p);
    }
    watch.stop();
    final Set<Cx> values = HashSet<Cx>.identity();
    for (final Phasors p in retained) {
      for (final List<Cx> row in p) {
        values.addAll(row);
      }
    }
    print(
      'Phasors: ${watch.elapsedMicroseconds / 1000} ms; '
      '${values.length} distinct Cx objects in eight keys; checksum $checksum',
    );
  } else {
    final XaraDriver driver = XaraDriver(_BurstStation(), delay: 0, keyUp: 14400);
    final Int16List pcm = driver.tick(480).single;
    watch.stop();
    int hash = 0x811c9dc5;
    for (final int sample in pcm) {
      hash = ((hash ^ (sample & 0xffff)) * 0x01000193) & 0xffffffff;
    }
    print(
      'TX: ${watch.elapsedMicroseconds / 1000} ms; ${pcm.length} samples; '
      'hash ${hash.toRadixString(16)}; '
      'peak RSS ${(ProcessInfo.maxRss / (1024 * 1024)).toStringAsFixed(2)} MiB',
    );
  }
}
