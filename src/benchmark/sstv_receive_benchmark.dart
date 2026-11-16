// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:htcommander/sstv/decoder.dart';
import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/native_demodulator.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';

void main() {
  if (!nativeSstvSupported) {
    throw UnsupportedError('Native SSTV is unavailable on this platform');
  }
  const rate = 32000;
  final audio = Encoder(rate).encodeRobot36(
    Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
    2,
    2,
  );
  final pcm = Uint8List((audio.length + rate * 2 + 127) ~/ 128 * 128 * 2);
  final data = ByteData.sublistView(pcm);
  for (int i = 0; i < audio.length; ++i) {
    final raw = (audio[i] * 32768).round().clamp(-32768, 32767);
    data.setInt16(i * 2, raw, Endian.little);
    audio[i] = raw / 32768.0;
  }
  stdout.writeln('Robot 36 receive, $rate Hz, $nativeSstvSimdWidth SIMD lanes');
  for (final (name, native, simd, directPcm) in [
    ('Dart', false, false, false),
    ('Native scalar', true, false, false),
    ('Native SIMD', true, true, false),
    ('Native SIMD PCM16', true, true, true),
  ]) {
    final times = <int>[];
    for (int run = 0; run < 4; run++) {
      final image = PixelBuffer(800, 616);
      final decoder = Decoder(
        PixelBuffer(800, 616),
        image,
        'Raw',
        rate,
        useNative: native,
        useSimd: simd,
      );
      final block = Float64List(128);
      final timer = Stopwatch()..start();
      try {
        for (int offset = 0; offset < audio.length + rate * 2; offset += 128) {
          if (directPcm) {
            decoder.processPcm16(pcm, offset * 2, 256);
          } else {
            block.fillRange(0, block.length, 0);
            final count = math.min(block.length, audio.length - offset);
            if (count > 0) block.setRange(0, count, audio, offset);
            decoder.process(block, 0);
          }
        }
        timer.stop();
        if (image.line != 240) throw StateError('$name image incomplete');
        if (run > 0) times.add(timer.elapsedMicroseconds);
      } finally {
        decoder.dispose();
      }
    }
    times.sort();
    final seconds = times[1] / 1e6;
    stdout.writeln(
      '$name: ${seconds.toStringAsFixed(3)} s median, '
      '${(audio.length / rate / seconds).toStringAsFixed(1)}x realtime',
    );
  }
}
