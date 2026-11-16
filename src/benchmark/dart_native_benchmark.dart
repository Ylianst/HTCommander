// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Run with: dart run benchmark/dart_native_benchmark.dart
// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'package:htcommander/hamlib/dart_ldpc.dart';
import 'package:htcommander/hamlib/dart_fsk.dart';
import 'package:htcommander/hamlib/dart_modem.dart';
import 'package:htcommander/hamlib/native_dart_dsp.dart';

void main() {
  if (!nativeDartDspEnabled) {
    throw StateError('This benchmark requires native DART DSP');
  }
  print('DART tone detector SIMD width: $nativeDartSimdWidth');
  final payload = Uint8List.fromList(List.generate(256, (i) => i));
  final reference = DartModem(useNative: false);
  for (final mode in [DartMode.mode2, DartMode.mode5, DartMode.modeF]) {
    final pcm = reference.encode(payload: payload, mode: mode);
    for (final useNative in [false, true]) {
      final modem = DartModem(useNative: useNative);
      _measure('${mode.name} ${useNative ? "native" : "Dart"} encode', 40, () {
        final out = modem.encode(payload: payload, mode: mode);
        if (out.length != pcm.length) throw StateError('PCM length changed');
      });
      _measure('${mode.name} ${useNative ? "native" : "Dart"} decode', 20, () {
        final result = modem.decode(pcm);
        if (result == null || result.payload.length != payload.length) {
          throw StateError('Decode failed');
        }
        for (int i = 0; i < payload.length; i++) {
          if (result.payload[i] != payload[i]) {
            throw StateError('Payload changed');
          }
        }
      });
      final silence = Int16List(32000);
      _measure(
        '${mode.name} ${useNative ? "native" : "Dart"} idle scan',
        20,
        () {
          if (modem.detectPreamble(silence).position != -1) {
            throw StateError('False detection');
          }
        },
      );
    }
  }
  final code = DartLdpc.getCode(LdpcRate.r1_2);
  final bits = Uint8List.fromList(List.generate(code.k, (i) => i & 1));
  final encoded = DartLdpc.encode(code, bits);
  final llr = Float64List.fromList([
    for (int i = 0; i < encoded.length; i++)
      (encoded[i] == 0 ? 1.0 : -1.0) * (i % 7 == 0 ? -0.5 : 1.0),
  ]);
  for (final useNative in [false, true]) {
    _measure('LDPC noisy ${useNative ? "native" : "Dart"}', 200, () {
      DartLdpc.decode(code, llr, useNative: useNative);
    });
  }
  for (final rate in LdpcRate.values) {
    final code = DartLdpc.getCode(rate);
    print(
      '$rate: ${code.totalEdges * 8} reusable LDPC message bytes '
      '(previous native: ${2 * code.totalEdges * 8})',
    );
    final graphEntries =
        code.checkEdgeStart.length +
        code.varEdgeStart.length +
        2 * code.totalEdges;
    print(
      '$rate: ${2 * graphEntries} native graph bytes '
      '(previous native: ${4 * graphEntries})',
    );
  }
  final fskBits = Uint8List.fromList(List.generate(2048, (i) => i & 1));
  final fsk = DartFsk(DartFskParams());
  final samples = fsk.modulate(fskBits);
  final quality = Float64List(1);
  _measure('Mode F native soft decode + SNR', 100, () {
    final llr = fsk.demodulateSoft(samples, 0, fskBits.length, snrOut: quality);
    if (llr.length != fskBits.length) throw StateError('LLR length changed');
  });
}

void _measure(String label, int iterations, void Function() run) {
  for (int i = 0; i < 12; i++) {
    run();
  }
  final timings = <double>[];
  for (int batch = 0; batch < 5; batch++) {
    final watch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      run();
    }
    watch.stop();
    timings.add(watch.elapsedMicroseconds / iterations / 1000);
  }
  timings.sort();
  print(
    '$label: ${timings[timings.length ~/ 2].toStringAsFixed(3)} ms (median of 5 batches)',
  );
}
