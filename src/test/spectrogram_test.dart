// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_fft.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_generator.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_view.dart';
import 'package:htcommander/widgets/spectrogram/native_spectrogram.dart';
import 'package:htcommander/hamlib/xara/native_dsp.dart';

Float64List _samples(int length, [int offset = 0]) => Float64List.fromList(
  List.generate(length, (i) {
    final t = (i + offset) / 160;
    return 11000 * math.sin(2 * math.pi * 23 * t) +
        3100 * math.sin(2 * math.pi * 57 * t);
  }),
);

SpectrogramGenerator _generator(int width) =>
    SpectrogramGenerator(sampleRate: 160, fftSize: 16, stepSize: 4)
      ..setFixedWidth(width);

void _render(
  SpectrogramGenerator generator,
  Uint8List buffer, {
  bool roll = false,
  int? newColumnCount,
}) {
  generator.renderInto(
    buffer,
    colormap: SpectrogramColormap.viridis,
    intensity: 5,
    decibel: true,
    roll: roll,
    newColumnCount: newColumnCount,
  );
}

Future<ui.Image> _nextImage(SpectrogramController controller) async {
  final ready = Completer<ui.Image>();
  void listener() {
    final image = controller.image;
    if (image != null && !ready.isCompleted) ready.complete(image);
  }

  controller.addListener(listener);
  try {
    return await ready.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}

Future<void> _expectImage(
  SpectrogramController controller,
  SpectrogramGenerator reference,
) async {
  final image = await _nextImage(controller);
  final expected = Uint8List(reference.width * reference.height * 4);
  reference.renderInto(
    expected,
    colormap: controller.colormap,
    intensity: controller.intensity,
    decibel: controller.decibel,
    dbScale: controller.dbScale,
    roll: controller.roll,
  );
  expect(image.width, reference.width);
  expect(image.height, reference.height);
  final pixels = await image.toByteData();
  expect(pixels!.buffer.asUint8List(), orderedEquals(expected));
}

SpectrogramController _controller() => SpectrogramController(
  sampleRate: 160,
  fftSize: 16,
  stepSize: 4,
  maxFrequency: 80,
  columnCount: 16,
  updateInterval: const Duration(milliseconds: 5),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native spectrogram rejects mismatched window and empty render is safe',
    () {
      expect(
        () => createNativeSpectrogram(16, 4, 0, 8, Float64List(15)),
        throwsArgumentError,
      );
      final native = createNativeSpectrogram(16, 4, 0, 8, Float64List(16))!;
      try {
        native.render(
          Uint8List(0),
          SpectrogramColormap.viridis,
          1,
          1,
          false,
          true,
          0,
        );
        expect(
          () => native.render(
            Uint8List(0),
            SpectrogramColormap.viridis,
            1,
            1,
            false,
            false,
            -1,
          ),
          throwsRangeError,
        );
      } finally {
        native.dispose();
      }
    },
    skip: !nativeDspEnabled,
  );

  test('accelerated FFT matches the Dart reference', () {
    final random = math.Random(42);
    for (final size in [2, 16, 512, 4096]) {
      final accelerated = SpectrogramFft(size);
      final reference = SpectrogramFft(size, useNative: false);
      for (var pass = 0; pass < 3; pass++) {
        final re = Float64List.fromList(
          List.generate(size, (_) => random.nextDouble() * 200 - 100),
        );
        final im = Float64List.fromList(
          List.generate(size, (_) => random.nextDouble() * 200 - 100),
        );
        final expectedRe = Float64List.fromList(re);
        final expectedIm = Float64List.fromList(im);
        reference.forward(expectedRe, expectedIm);
        accelerated.forward(re, im);
        for (var i = 0; i < size; i++) {
          expect(re[i], closeTo(expectedRe[i], 1e-8));
          expect(im[i], closeTo(expectedIm[i], 1e-8));
        }
      }
    }
  });

  test('native pipeline matches reference through streaming and rendering', () {
    final actual = SpectrogramGenerator(
      sampleRate: 32000,
      fftSize: 512,
      stepSize: 25,
      minFreq: 125,
      maxFreq: 12000,
    );
    final reference = SpectrogramGenerator(
      sampleRate: 32000,
      fftSize: 512,
      stepSize: 25,
      minFreq: 125,
      maxFreq: 12000,
      useNative: false,
    );
    addTearDown(actual.dispose);
    addTearDown(reference.dispose);
    final random = math.Random(19);
    for (final width in [31, 1, 67, -1, 7]) {
      actual.setFixedWidth(width);
      reference.setFixedWidth(width);
      for (final length in [1, 511, 1000, 7, 8192]) {
        final samples = Float64List.fromList(
          List.generate(length, (_) => random.nextDouble() * 60000 - 30000),
        );
        actual.addSamples(samples);
        reference.addSamples(samples);
        expect(actual.fftsToProcess, reference.fftsToProcess);
        actual.process();
        reference.process();
        expect(actual.width, reference.width);
        final expected = Uint8List(reference.width * reference.height * 4);
        final pixels = Uint8List(expected.length);
        for (final decibel in [false, true]) {
          for (final roll in [false, true]) {
            for (final colors in [
              SpectrogramColormap.viridis,
              SpectrogramColormap.magma,
            ]) {
              actual.renderInto(
                pixels,
                colormap: colors,
                intensity: decibel ? 7 : 0.03,
                decibel: decibel,
                dbScale: 3,
                roll: roll,
              );
              reference.renderInto(
                expected,
                colormap: colors,
                intensity: decibel ? 7 : 0.03,
                decibel: decibel,
                dbScale: 3,
                roll: roll,
              );
              expect(pixels, orderedEquals(expected));
            }
          }
        }
        expect(actual.getPeak().freqHz, reference.getPeak().freqHz);
        expect(
          actual.getPeak().magnitude,
          closeTo(reference.getPeak().magnitude, 1e-8),
        );
        actual.rollReset(-11);
        reference.rollReset(-11);
        expect(actual.nextColumnIndex, reference.nextColumnIndex);
      }
      actual.clear();
      reference.clear();
    }
  });

  test('native rendering rejects nonfinite colors and short output', () {
    final generator = _generator(17);
    addTearDown(generator.dispose);
    generator.addSamples(_samples(80));
    generator.process();
    expect(
      () => generator.renderInto(
        Uint8List(1),
        colormap: SpectrogramColormap.viridis,
      ),
      throwsRangeError,
    );
    expect(
      () => generator.renderInto(
        Uint8List(17 * generator.height * 4),
        colormap: SpectrogramColormap.viridis,
        intensity: double.nan,
      ),
      throwsA(isA<Error>()),
    );
    generator.dispose();
    expect(generator.process, throwsStateError);
  });

  test('pooled history matches append-and-trim through resize and backlog', () {
    final actual = _generator(17);
    final reference = SpectrogramGenerator(
      sampleRate: 160,
      fftSize: 16,
      stepSize: 4,
      useNative: false,
    );
    var offset = 0;
    for (final width in [17, 3, 31, 1, 12, 0, 7]) {
      actual.setFixedWidth(width);
      if (width > 0) reference.setFixedWidth(width);
      reference.setFixedWidth(0);
      for (final length in [23, 4, 280, 9]) {
        final samples = _samples(length, offset);
        offset += length;
        actual.addSamples(samples);
        reference.addSamples(samples);
        expect(actual.fftsToProcess, reference.fftsToProcess);
        actual.process();
        reference.process();
        if (width > 0) reference.setFixedWidth(width);
        expect(actual.width, reference.width);
        final expected = Uint8List(reference.width * reference.height * 4);
        final pixels = Uint8List(expected.length);
        for (final roll in [false, true]) {
          _render(reference, expected, roll: roll);
          _render(actual, pixels, roll: roll);
          expect(pixels, orderedEquals(expected));
          actual.rollReset(2);
          reference.rollReset(2);
        }
        expect(actual.nextColumnIndex, reference.nextColumnIndex);
        expect(actual.getPeak().freqHz, reference.getPeak().freqHz);
        expect(
          actual.getPeak().magnitude,
          closeTo(reference.getPeak().magnitude, 1e-8),
        );
        reference.setFixedWidth(0);
      }
      actual.clear();
      reference.clear();
      if (width > 0) {
        reference.setFixedWidth(width);
        final expected = Uint8List(width * reference.height * 4);
        final pixels = Uint8List(expected.length);
        _render(reference, expected);
        _render(actual, pixels);
        expect(pixels, orderedEquals(expected));
        reference.setFixedWidth(0);
      }
    }
  });

  test('direct PCM conversion preserves offsets, tails and compaction', () {
    final actual = _generator(17);
    final reference = _generator(17);
    for (var frame = 0; frame < 80; frame++) {
      final count = [1, 7, 37, 1024, 3][frame % 5];
      final pcm = Uint8List(count * 2 + 6)..fillRange(0, count * 2 + 6, 0x7f);
      final data = ByteData.sublistView(pcm);
      final samples = Float64List(count);
      for (var i = 0; i < count; i++) {
        final value = (frame * 997 + i * 8191) % 65536 - 32768;
        data.setInt16(3 + i * 2, value, Endian.little);
        samples[i] = value.toDouble();
      }
      actual.addPcm16(pcm, 3, count * 2 + 1);
      reference.addSamples(samples);
      actual.process();
      reference.process();
      final expected = Uint8List(17 * reference.height * 4);
      final pixels = Uint8List(expected.length);
      _render(reference, expected);
      _render(actual, pixels);
      expect(pixels, orderedEquals(expected));
      expect(actual.fftsToProcess, reference.fftsToProcess);
    }
  });

  for (final roll in [false, true]) {
    test('packed updates preserve independent caller buffers (roll=$roll)', () {
      final actual = _generator(17);
      final reference = SpectrogramGenerator(
        sampleRate: 160,
        fftSize: 16,
        stepSize: 4,
        useNative: false,
      )..setFixedWidth(17);
      addTearDown(actual.dispose);
      addTearDown(reference.dispose);
      var offset = 0;
      for (final width in [17, 31, 9]) {
        actual.setFixedWidth(width);
        reference.setFixedWidth(width);
        final buffers = List.generate(
          2,
          (_) => Uint8List(width * actual.height * 4),
        );
        final expected = List.generate(
          2,
          (_) => Uint8List(width * reference.height * 4),
        );
        for (var i = 0; i < buffers.length; i++) {
          buffers[i].fillRange(0, buffers[i].length, 37 + i * 86);
          expected[i].setAll(0, buffers[i]);
        }
        for (final length in [23, 12, 8, 36, 16, 8192, 4, 20]) {
          final samples = _samples(length, offset);
          offset += length;
          final pcm = Uint8List(length * 2);
          final data = ByteData.sublistView(pcm);
          for (var i = 0; i < length; i++) {
            data.setInt16(i * 2, samples[i].round(), Endian.little);
          }
          actual.addPcm16(pcm);
          reference.addPcm16(pcm);
          final count = math.max(0, reference.fftsToProcess);
          actual.process();
          reference.process();
          for (var i = 0; i < buffers.length; i++) {
            _render(actual, buffers[i], roll: roll, newColumnCount: count);
            _render(reference, expected[i], roll: roll, newColumnCount: count);
            expect(buffers[i], orderedEquals(expected[i]));
            actual.getPeak();
          }
        }
      }
    });

    test('incremental pixels match full rendering (roll=$roll)', () {
      for (final width in [17, 31]) {
        final generator = _generator(width);
        final full = Uint8List(width * generator.height * 4);
        final incremental = Uint8List(full.length);
        _render(generator, incremental, roll: roll);
        var offset = 0;
        for (final length in [23, 4, 36, 16, 5, 160, 1, 87]) {
          generator.addSamples(_samples(length, offset));
          offset += length;
          final count = math.max(0, generator.fftsToProcess);
          generator.process();
          _render(generator, full, roll: roll);
          _render(generator, incremental, roll: roll, newColumnCount: count);
          expect(incremental, orderedEquals(full));
        }
      }
    });

    test('incremental rendering retains cached pixels (roll=$roll)', () {
      final generator = _generator(17);
      final buffer = Uint8List(17 * generator.height * 4);
      _render(generator, buffer, roll: roll);
      buffer.fillRange(0, buffer.length, 123);
      generator.addSamples(_samples(20));
      expect(generator.fftsToProcess, 1);
      generator.process();
      _render(generator, buffer, roll: roll, newColumnCount: 1);
      final updatedColumn = roll ? 0 : 16;
      for (var row = 0; row < generator.height; row++) {
        for (var col = 0; col < 17; col++) {
          if (col == updatedColumn) continue;
          final start = (row * 17 + col) * 4;
          expect(buffer.sublist(start, start + 4), [123, 123, 123, 123]);
        }
      }
    });
  }

  test('roll rendering is a rotation of scroll rendering', () {
    final generator = _generator(17)..addSamples(_samples(168));
    generator.process();
    final scroll = Uint8List(17 * generator.height * 4);
    final roll = Uint8List(scroll.length);
    _render(generator, scroll);
    _render(generator, roll, roll: true);
    for (var row = 0; row < generator.height; row++) {
      for (var col = 0; col < 17; col++) {
        final from = (row * 17 + col) * 4;
        final to = (row * 17 + (col + generator.nextColumnIndex) % 17) * 4;
        expect(roll.sublist(to, to + 4), scroll.sublist(from, from + 4));
      }
    }
  });

  test('negative incremental column counts are rejected', () {
    final generator = _generator(17);
    expect(
      () => _render(
        generator,
        Uint8List(17 * generator.height * 4),
        newColumnCount: -1,
      ),
      throwsRangeError,
    );
  });

  test(
    'controller refreshes cached history and settings without audio',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final reference = _generator(16);
      for (var offset = 0; offset < 320; offset += 80) {
        final samples = _samples(80, offset);
        reference
          ..addSamples(samples)
          ..process();
        controller.feedSamples(samples);
        await _expectImage(controller, reference);
      }

      controller.intensity = 9;
      await _expectImage(controller, reference);
      controller.decibel = false;
      await _expectImage(controller, reference);
      controller.dbScale = 3;
      controller.decibel = true;
      await _expectImage(controller, reference);
      controller.colormap = SpectrogramColormap.magma;
      await _expectImage(controller, reference);
      controller.roll = true;
      await _expectImage(controller, reference);
      for (final width in [24, 16]) {
        controller.columnCount = width;
        reference.setFixedWidth(width);
        await _expectImage(controller, reference);
      }

      final image = controller.image;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.image, same(image));
      controller.clear();
      expect(controller.image, isNull);
      reference.clear();
      final samples = _samples(80);
      reference
        ..addSamples(samples)
        ..process();
      controller.feedSamples(samples);
      await _expectImage(controller, reference);
    },
  );

  for (final change in [
    'clear',
    'reconfigure',
    'resize',
    'settings',
    'dispose',
  ]) {
    test('controller discards an in-flight image after $change', () async {
      final controller = _controller();
      var disposed = false;
      final originalOnCreate = ui.Image.onCreate;
      addTearDown(() {
        ui.Image.onCreate = originalOnCreate;
        if (!disposed) controller.dispose();
      });
      final created = Completer<ui.Image>();
      ui.Image.onCreate = (image) {
        ui.Image.onCreate = originalOnCreate;
        originalOnCreate?.call(image);
        switch (change) {
          case 'clear':
            controller.clear();
          case 'reconfigure':
            controller.reconfigure(fftSize: 32);
          case 'resize':
            controller.columnCount = 24;
          case 'settings':
            controller.intensity = 9;
          case 'dispose':
            controller.dispose();
            disposed = true;
        }
        created.complete(image);
      };
      controller.feedSamples(_samples(80));
      final stale = await created.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(stale.debugDisposed, isTrue);
      expect(controller.image, isNull);

      if (!disposed) {
        final next = _nextImage(controller);
        controller.feedSamples(_samples(160, 80));
        final fresh = await next;
        expect(fresh.debugDisposed, isFalse);
        expect(fresh.width, controller.imageWidth);
        expect(fresh.height, controller.imageHeight);
      }
    });
  }
}
