// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/native_demodulator.dart';

void main(List<String> args) {
  if (!nativeSstvSupported) {
    throw UnsupportedError('Native SSTV is unavailable on this platform');
  }
  const rate = 32000;
  final pixels = Int32List.fromList(
    List.generate(320 * 240, (i) => 0xff000000 | ((i * 7919) & 0x00ffffff)),
  );
  if (args.isNotEmpty) {
    if (args.length != 1 ||
        !['--memory-pcm', '--memory-float'].contains(args.single)) {
      throw ArgumentError('Expected --memory-pcm or --memory-float');
    }
    final pcm = args.single == '--memory-pcm';
    final encoder = Encoder(rate);
    final TypedData result = pcm
        ? encoder.encodePcm16(
            pixels,
            320,
            240,
            'PD 290',
            silenceSamples: rate * 2,
          )
        : encoder.encode(pixels, 320, 240, 'PD 290');
    stdout.writeln(
      'PD 290 native SIMD ${pcm ? 'PCM16' : 'float'}: '
      '${(result.lengthInBytes / 1048576).toStringAsFixed(2)} MiB output, '
      '${(ProcessInfo.maxRss / 1048576).toStringAsFixed(2)} MiB peak RSS',
    );
    stdout.writeln(
      'Last output byte: '
      '${ByteData.sublistView(result).getUint8(result.lengthInBytes - 1)}',
    );
    return;
  }
  stdout.writeln('SSTV encode, $rate Hz, $nativeSstvSimdWidth SIMD lanes');
  for (final mode in ['Robot 36 Color', 'PD 290']) {
    for (final (name, native, simd, pcm) in [
      ('Dart float', false, false, false),
      ('Dart PCM16', false, false, true),
      ('Native scalar PCM16', true, false, true),
      ('Native SIMD float', true, true, false),
      ('Native SIMD PCM16', true, true, true),
    ]) {
      final times = <int>[];
      int bytes = 0;
      for (int run = 0; run < 4; run++) {
        final encoder = Encoder(rate, useNative: native, useSimd: simd);
        final timer = Stopwatch()..start();
        final TypedData result = pcm
            ? encoder.encodePcm16(
                pixels,
                320,
                240,
                mode,
                silenceSamples: rate * 2,
              )
            : encoder.encode(pixels, 320, 240, mode);
        timer.stop();
        bytes = result.lengthInBytes;
        if (bytes == 0) throw StateError('Empty encoded output');
        if (run > 0) times.add(timer.elapsedMicroseconds);
      }
      times.sort();
      stdout.writeln(
        '$mode $name: ${(times[1] / 1e3).toStringAsFixed(2)} ms, '
        '${(bytes / 1048576).toStringAsFixed(2)} MiB output',
      );
    }
  }
}
