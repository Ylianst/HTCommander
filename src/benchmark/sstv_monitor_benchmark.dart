// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/sstv_monitor.dart';

Future<void> main() async {
  const rate = 32000;
  final pcm = Encoder(rate).encodePcm16(
    Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
    2,
    2,
    'Robot 36 Color',
  );
  final tail = Uint8List(rate * 4);
  final receiveTimes = <int>[];
  final previewTimes = <int>[];
  for (int run = 0; run < 4; run++) {
    final monitor = SstvMonitor(sampleRate: rate);
    int completed = 0;
    final subscription = monitor.onDecodingComplete.listen((event) {
      if (event.image?.pixels.length != 320 * 240) {
        throw StateError('Incorrect completed image');
      }
      completed++;
    });
    final timer = Stopwatch()..start();
    try {
      for (final audio in [pcm, tail]) {
        for (int offset = 0; offset < audio.length; offset += 256) {
          monitor.processPcm16(
            audio,
            offset,
            math.min(256, audio.length - offset),
          );
        }
      }
      timer.stop();
      await Future<void>.delayed(Duration.zero);
      if (completed != 1) throw StateError('Expected one completed image');
      if (run > 0) receiveTimes.add(timer.elapsedMicroseconds);
      monitor.reset();
      for (int offset = 0; offset + 256 < pcm.length ~/ 2; offset += 256) {
        monitor.processPcm16(pcm, offset, 256);
      }
      timer.reset();
      timer.start();
      int checksum = 0;
      for (int i = 0; i < 200; i++) {
        final image = monitor.getPartialImage();
        if (image == null || image.pixels.length != 320 * 240) {
          throw StateError('Incorrect partial image');
        }
        checksum ^= image.pixels.first ^ image.pixels.last;
      }
      timer.stop();
      if (checksum != 0) throw StateError('Unstable partial image');
      if (run > 0) previewTimes.add(timer.elapsedMicroseconds);
    } finally {
      monitor.dispose();
      await subscription.cancel();
    }
  }
  receiveTimes.sort();
  previewTimes.sort();
  stdout.writeln(
    'Robot 36 PCM monitor, 32 kHz, 128-sample packets: '
    '${(receiveTimes[1] / 1000).toStringAsFixed(2)} ms median',
  );
  stdout.writeln(
    '200 half-received image snapshots: '
    '${(previewTimes[1] / 1000).toStringAsFixed(2)} ms median',
  );
}
