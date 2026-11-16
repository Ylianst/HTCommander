// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:htcommander/gsm/gsm_codec.dart';
import 'package:htcommander/gsm/native_gsm.dart';

void main() {
  if (!nativeGsmEnabled) {
    throw UnsupportedError('Native GSM is unavailable on this platform');
  }
  final random = Random(60610);
  final pcm = Int16List.fromList(
    List.generate(640, (_) => random.nextInt(65536) - 32768),
  );
  final frames = GsmEncoder().encode(pcm);
  final silence = Int16List(640);
  var checksum = 0;

  double measure(void Function() operation) {
    for (var i = 0; i < 1000; i++) {
      operation();
    }
    final times = <double>[];
    for (var r = 0; r < 5; r++) {
      final timer = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        operation();
      }
      timer.stop();
      times.add(timer.elapsedMicroseconds / 10000);
    }
    times.sort();
    return times[2];
  }

  stdout.writeln(
    'GSM: 640 samples / 132 bytes; $nativeGsmSimdWidth SIMD lanes',
  );
  for (final (label, simd) in [
    ('Native scalar', false),
    ('Native SIMD', true),
  ]) {
    final encoder = createNativeGsmEncoder(simd: simd)!;
    final decoder = createNativeGsmDecoder()!;
    final output = Uint8List(132);
    try {
      final enc = measure(() {
        encoder.encode(pcm, 0, output, 0);
        checksum += output[0];
      });
      final dec = measure(() {
        checksum += decoder.decode(frames)[0];
      });
      encoder.reset();
      final quiet = measure(() {
        encoder.encode(silence, 0, output, 0);
        checksum += output[0];
      });
      stdout.writeln(
        '$label: encode ${enc.toStringAsFixed(2)} us, '
        'decode ${dec.toStringAsFixed(2)} us, '
        'silence encode ${quiet.toStringAsFixed(2)} us',
      );
    } finally {
      encoder.dispose();
      decoder.dispose();
    }
  }
  final encoder = GsmEncoder();
  final decoder = GsmDecoder();
  final enc = measure(() {
    checksum += encoder.encode(pcm)[0];
  });
  final dec = measure(() {
    checksum += decoder.decode(frames)[0];
  });
  encoder.reset();
  final quiet = measure(() {
    checksum += encoder.encode(silence)[0];
  });
  stdout.writeln(
    'Dart: encode ${enc.toStringAsFixed(2)} us, '
    'decode ${dec.toStringAsFixed(2)} us, '
    'silence encode ${quiet.toStringAsFixed(2)} us; checksum $checksum',
  );
}
