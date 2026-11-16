// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sstv/decoder.dart';
import 'package:htcommander/sstv/encoder.dart';
import 'package:htcommander/sstv/pixel_buffer.dart';
import 'package:htcommander/sstv/sstv_monitor.dart';
import 'package:htcommander/sstv/sstv_worker.dart';

void main() {
  test('worker preserves images, progress, and ordered end-of-run partials', () async {
    const rate = 8000;
    final errors = <Object>[];
    final worker = SstvWorker(
      sampleRate: rate,
      onError: (error, _) => errors.add(error),
    );
    final reference = SstvMonitor(sampleRate: rate);
    addTearDown(worker.dispose);
    addTearDown(reference.dispose);
    final events = <String>[];
    final complete = <SstvDecodingComplete>[];
    final expected = <SstvDecodingComplete>[];
    final sources = <int>[];
    SstvImage? snapshot;
    Int32List? snapshotCopy;
    worker.onDecodingStarted.listen((event) {
      events.add('start');
      sources.add(worker.context!.deviceId);
    });
    worker.onDecodingProgress.listen((event) {
      events.add('progress');
      snapshot ??= worker.getPartialImage();
      snapshotCopy ??= Int32List.fromList(snapshot!.pixels);
    });
    worker.onDecodingComplete.listen((event) {
      events.add('complete');
      sources.add(worker.context!.deviceId);
      complete.add(event);
    });
    reference.onDecodingComplete.listen(expected.add);
    final audio = Encoder(rate).encodePcm16(
      Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
      2,
      2,
      'Robot 36 Color',
    );
    final run = Uint8List(audio.length + rate * 4)..setAll(0, audio);
    for (int offset = 0; offset < run.length; offset += 1024) {
      final length = math.min(1024, run.length - offset);
      worker.processPcm16(
        run,
        offset,
        length,
        context: const SstvReceiveContext(101, 'SSTV', false),
      );
      reference.processPcm16(run, offset, length);
      if (offset % (1024 * 16) == 0) await worker.idle;
    }
    worker.end(101);
    await worker.idle;
    expect(errors, isEmpty);
    expect(complete, hasLength(1));
    expect(expected, hasLength(1));
    expect(complete.single.image!.pixels, expected.single.image!.pixels);
    expect(events.first, 'start');
    expect(events.last, 'complete');
    expect(events.where((event) => event == 'progress'), isNotEmpty);
    expect(snapshot!.pixels, snapshotCopy);

    events.clear();
    reference.reset();
    // Queue an end while VIS detection and partial decoding are still pending.
    // An end from a different radio must not finish this image.
    for (int offset = 0; offset < rate * 2 * 3; offset += 1024) {
      final length = math.min(1024, rate * 2 * 3 - offset);
      worker.processPcm16(
        audio,
        offset,
        length,
        context: const SstvReceiveContext(202, 'Other SSTV', true),
      );
      reference.processPcm16(audio, offset, length);
    }
    worker.end(101);
    worker.end(202);
    await worker.idle;
    expect(errors, isEmpty);
    expect(complete, hasLength(2));
    expect(complete.last.image!.pixels, reference.getPartialImage()!.pixels);
    expect(events.first, 'start');
    expect(events.last, 'complete');
    expect(sources, [101, 101, 202, 202]);
  });

  for (final mode in ['Robot 36 Color', 'Martin 2', 'PD 290']) {
    test('$mode works without scope storage and sizes its image on VIS', () {
      const rate = 8000;
      final audio = Encoder(rate).encode(
        Int32List.fromList([0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff]),
        2,
        2,
        mode,
      );
      final image = PixelBuffer(0, 0);
      final expectedImage = PixelBuffer(800, 616);
      final decoder = Decoder(null, image, 'Raw', rate);
      final reference = Decoder(
        PixelBuffer(800, 616),
        expectedImage,
        'Raw',
        rate,
      );
      expect(image.pixels, isEmpty);
      try {
        for (int offset = 0; offset < audio.length + rate * 2; offset += 128) {
          final block = Float64List(128);
          if (offset < audio.length) {
            block.setRange(
              0,
              math.min(128, audio.length - offset),
              audio,
              offset,
            );
          }
          final expected = Float64List.fromList(block);
          expect(decoder.process(block, 0), reference.process(expected, 0));
          expect(image.line, expectedImage.line);
          if (image.line >= 0) {
            expect(image.pixels.length, image.width * image.height);
          }
        }
        expect(decoder.currentMode.getName(), mode);
        expect(image.line, image.height);
        expect(image.width, decoder.currentMode.getWidth());
        expect(image.height, decoder.currentMode.getHeight());
        expect(
          image.pixels,
          orderedEquals(expectedImage.pixels.take(image.pixels.length)),
        );
        decoder.setMode('HF Fax');
        expect(image.pixels.length, greaterThanOrEqualTo(640 * 1200));
        expect(() => decoder.process(Float64List(128), 0), returnsNormally);
      } finally {
        decoder.dispose();
        reference.dispose();
      }
    });
  }

  test(
    'PCM reuse and completion transfer preserve snapshots and later images',
    () async {
      const rate = 8000;
      final monitor = SstvMonitor(sampleRate: rate);
      final reference = SstvMonitor(sampleRate: rate);
      final images = <SstvImage>[];
      final expectedImages = <SstvImage>[];
      final subscription = monitor.onDecodingComplete.listen((event) {
        images.add(event.image!);
      });
      final referenceSubscription = reference.onDecodingComplete.listen((
        event,
      ) {
        expectedImages.add(event.image!);
      });
      SstvImage? savedPartial;
      Int32List? partialCopy;
      Int32List? firstImageCopy;
      try {
        // Large non-packet input must not contaminate the smaller reused buffer.
        monitor.processPcm16(Uint8List(8194), 0, 8194);
        reference.processFloatSamples(Float64List(4097));
        monitor.reset();
        reference.reset();
        for (final color in [0xffff0000, 0xff00ff00]) {
          final pcm = Encoder(
            rate,
          ).encodePcm16(Int32List.fromList([color]), 1, 1, 'Robot 36 Color');
          final tail = Uint8List(rate * 4);
          int packet = 0;
          for (final audio in [pcm, tail]) {
            final view = ByteData.sublistView(audio);
            for (int offset = 0; offset < audio.length;) {
              final count = math.min(
                [1, 17, 128, 73, 257, 64][packet++ % 6],
                (audio.length - offset) ~/ 2,
              );
              final padded = Uint8List(count * 2 + 5);
              padded.setRange(3, 3 + count * 2, audio, offset);
              final samples = Float64List(count);
              for (int i = 0; i < count; i++) {
                samples[i] =
                    view.getInt16(offset + i * 2, Endian.little) / 32768;
              }
              monitor.processPcm16(padded, 3, count * 2);
              reference.processFloatSamples(samples);
              offset += count * 2;
              final partial = savedPartial == null
                  ? monitor.getPartialImage()
                  : null;
              if (partial != null) {
                expect(partial.pixels.length, 320 * 240);
                expect(partial.pixels.last & 0xffffffff, 0xff000000);
                final other = monitor.getPartialImage()!;
                expect(identical(partial.pixels, other.pixels), isFalse);
                final first = other.pixels.first;
                partial.pixels[0] = 0x12345678;
                expect(monitor.getPartialImage()!.pixels.first, first);
                savedPartial = other;
                partialCopy = Int32List.fromList(other.pixels);
              }
            }
          }
          await Future<void>.delayed(Duration.zero);
          expect(images.length, expectedImages.length);
          expect(images.last.pixels, orderedEquals(expectedImages.last.pixels));
          if (firstImageCopy == null) {
            firstImageCopy = Int32List.fromList(images.first.pixels);
          } else {
            expect(images.first.pixels, orderedEquals(firstImageCopy));
            expect(identical(images.first.pixels, images.last.pixels), isFalse);
            expect(
              images.first.pixels,
              isNot(orderedEquals(images.last.pixels)),
            );
          }
        }
        expect(images.length, 2);
        expect(savedPartial, isNotNull);
        expect(savedPartial!.pixels, orderedEquals(partialCopy!));
        monitor.reset();
        expect(images.first.pixels, orderedEquals(firstImageCopy!));
      } finally {
        monitor.dispose();
        reference.dispose();
        await subscription.cancel();
        await referenceSubscription.cancel();
      }
      expect(images.first.pixels, orderedEquals(firstImageCopy));
    },
  );
}
