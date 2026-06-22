import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_colormap.dart';
import 'package:htcommander/widgets/spectrogram/spectrogram_generator.dart';

void main() {
  test('detects the dominant frequency of a sine tone', () {
    const sampleRate = 32000;
    const fftSize = 1024;
    const toneHz = 4000.0;

    final gen = SpectrogramGenerator(
      sampleRate: sampleRate,
      fftSize: fftSize,
      stepSize: fftSize ~/ 20,
      maxFreq: 16000,
    );

    // Generate ~0.25s of a pure sine tone.
    const sampleCount = sampleRate ~/ 4;
    final samples = Float64List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = 16000 * math.sin(2 * math.pi * toneHz * i / sampleRate);
    }

    gen.addSamples(samples);
    expect(gen.fftsToProcess, greaterThan(0));
    gen.process();
    expect(gen.width, greaterThan(0));

    final peak = gen.getPeak();
    // The peak bin should land within one bin of the tone frequency.
    expect((peak.freqHz - toneHz).abs(), lessThan(gen.hzPerPixel));
  });

  test('renders an RGBA buffer of the expected size', () {
    final gen = SpectrogramGenerator(
      sampleRate: 32000,
      fftSize: 512,
      maxFreq: 16000,
    );
    gen.setFixedWidth(64);

    final samples = Float64List(32000 ~/ 4);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = 8000 * math.sin(2 * math.pi * 2000 * i / 32000);
    }
    gen.addSamples(samples);
    gen.process();
    gen.setFixedWidth(64);

    final rgba = Uint8List(gen.width * gen.height * 4);
    gen.renderInto(rgba, colormap: SpectrogramColormap.viridis, intensity: 5);

    // Alpha channel must be fully opaque everywhere.
    for (int i = 3; i < rgba.length; i += 4) {
      expect(rgba[i], 255);
    }
  });
}
