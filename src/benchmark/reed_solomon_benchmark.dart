// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:htcommander/fec/native_reed_solomon.dart';
import 'package:htcommander/hamlib/fx25.dart';
import 'package:htcommander/hamlib/reed_solomon_codec.dart' as fx;
import 'package:htcommander/radiosonde/reed_solomon.dart' as sonde;

void _equal(List<int> a, List<int> b) {
  if (a.length != b.length) throw StateError('RS length mismatch');
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw StateError('RS mismatch at $i');
  }
}

double _measure(void Function() operation, int iterations) {
  for (int i = 0; i < 100; i++) {
    operation();
  }
  final times = <double>[];
  for (int run = 0; run < 5; run++) {
    final timer = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      operation();
    }
    timer.stop();
    times.add(timer.elapsedMicroseconds / iterations);
  }
  times.sort();
  return times[2];
}

void main(List<String> arguments) {
  if (!nativeReedSolomonSupported) {
    throw UnsupportedError('Native Reed-Solomon unavailable');
  }
  final iterations = arguments.isEmpty ? 1000 : int.parse(arguments.first);
  if (iterations <= 0) throw ArgumentError('Expected positive iterations');
  final random = Random(255);
  final seed = Uint8List.fromList(
    List.generate(255, (_) => random.nextInt(256)),
  );
  var checksum = 0;
  for (final config in [
    ('RS41', 24, 0, 0x11d, 1),
    ('LMS6 CCSDS', 32, 112, 0x187, 11),
  ]) {
    final (label, roots, fcr, poly, primPow) = config;
    final native = sonde.ReedSolomon(
      nroots: roots,
      fcr: fcr,
      prim: poly,
      primPow: primPow,
    );
    final reference = sonde.ReedSolomon(
      nroots: roots,
      fcr: fcr,
      prim: poly,
      primPow: primPow,
      useNative: false,
    );
    try {
      final clean = Uint8List.fromList(seed);
      reference.encode(clean);
      final check = Uint8List.fromList(seed);
      native.encode(check);
      _equal(check, clean);
      for (final (name, codec) in [('native', native), ('Dart', reference)]) {
        final work = Uint8List(255);
        final encodeUs = _measure(() {
          work.setAll(0, seed);
          codec.encode(work);
          checksum += work[0];
        }, iterations);
        _equal(work, clean);
        stdout.writeln('$label $name encode ${encodeUs.toStringAsFixed(2)} us');
        for (final errors in [0, roots ~/ 2]) {
          final damaged = Uint8List.fromList(clean);
          for (int i = 0; i < errors; i++) {
            damaged[(i * 19) % 255] ^= i + 1;
          }
          final decodeUs = _measure(() {
            work.setAll(0, damaged);
            final result = codec.decode(work);
            if (result != errors) throw StateError('$label decode $result');
            checksum += result;
          }, iterations);
          _equal(work, clean);
          stdout.writeln(
            '$label $name decode $errors errors '
            '${decodeUs.toStringAsFixed(2)} us',
          );
        }
      }
    } finally {
      native.dispose();
      reference.dispose();
    }
  }
  Fx25.init(0);
  for (final tag in [1, 5, 9]) {
    final rs = Fx25.getRs(tag);
    final roots = rs.nRoots;
    final clean = Uint8List.fromList(seed);
    final parity = Uint8List(roots);
    fx.ReedSolomon.encode(rs, clean, parity, useNative: false);
    clean.setRange(255 - roots, 255, parity);
    try {
      for (final useNative in [true, false]) {
        final name = useNative ? 'native' : 'Dart';
        final work = Uint8List(255);
        final output = Uint8List(roots);
        final enc = _measure(() {
          fx.ReedSolomon.encode(rs, seed, output, useNative: useNative);
          checksum += output[0];
        }, iterations);
        _equal(output, parity);
        stdout.writeln(
          'FX.25 $roots $name encode ${enc.toStringAsFixed(2)} us',
        );
        for (final errors in [0, roots ~/ 2]) {
          final damaged = Uint8List.fromList(clean);
          // 19 is coprime to 255, so every injected location is distinct.
          for (int i = 0; i < errors; i++) {
            damaged[(i * 19) % 255] ^= i + 1;
          }
          for (final erasures in [false, true]) {
            final positions = errors > 0 && erasures ? <int>[0] : null;
            final us = _measure(() {
              work.setAll(0, damaged);
              final result = fx.ReedSolomon.decode(
                rs,
                work,
                positions,
                positions?.length ?? 0,
                useNative: useNative,
              );
              if (result != errors) throw StateError('FX.25 decode $result');
              checksum += result;
            }, iterations);
            _equal(work, clean);
            stdout.writeln(
              'FX.25 $roots $name decode $errors errors, '
              '${positions?.length ?? 0} erasures: ${us.toStringAsFixed(2)} us',
            );
          }
        }
      }
    } finally {
      fx.ReedSolomon.dispose(rs);
    }
  }
  stdout.writeln('Median of 5 x $iterations blocks; checksum $checksum');
}
