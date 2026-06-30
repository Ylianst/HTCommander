/*
Raw decoder
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';
import 'sstv_round.dart';

class RawDecoder extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final int _smallPictureMaxSamples;
  final int _mediumPictureMaxSamples;
  final String _name;

  RawDecoder(String name, int sampleRate)
    : _name = name,
      _smallPictureMaxSamples = sstvRound(0.125 * sampleRate),
      _mediumPictureMaxSamples = sstvRound(0.175 * sampleRate),
      _lowPassFilter = ExponentialMovingAverage();

  static double _freqToLevel(double frequency, double offset) =>
      0.5 * (frequency - offset + 1.0);

  @override
  String getName() => _name;
  @override
  int getVISCode() => -1;
  @override
  int getWidth() => -1;
  @override
  int getHeight() => -1;
  @override
  int getFirstPixelSampleIndex() => 0;
  @override
  int getFirstSyncPulseIndex() => -1;
  @override
  int getScanLineSamples() => -1;
  @override
  void resetState() {}

  @override
  bool decodeScanLine(
    PixelBuffer pixelBuffer,
    Float64List scratchBuffer,
    Float64List scanLineBuffer,
    int scopeBufferWidth,
    int syncPulseIndex,
    int scanLineSamples,
    double frequencyOffset,
  ) {
    if (syncPulseIndex < 0 ||
        syncPulseIndex + scanLineSamples > scanLineBuffer.length) {
      return false;
    }
    int horizontalPixels = scopeBufferWidth;
    if (scanLineSamples < _smallPictureMaxSamples) horizontalPixels ~/= 2;
    if (scanLineSamples < _mediumPictureMaxSamples) horizontalPixels ~/= 2;
    _lowPassFilter.cutoff(horizontalPixels, 2 * scanLineSamples, 2);
    _lowPassFilter.reset();
    for (int i = 0; i < scanLineSamples; ++i) {
      scratchBuffer[i] = _lowPassFilter.avg(scanLineBuffer[syncPulseIndex + i]);
    }
    _lowPassFilter.reset();
    for (int i = scanLineSamples - 1; i >= 0; --i) {
      scratchBuffer[i] = _freqToLevel(
        _lowPassFilter.avg(scratchBuffer[i]),
        frequencyOffset,
      );
    }
    for (int i = 0; i < horizontalPixels; ++i) {
      final position = (i * scanLineSamples) ~/ horizontalPixels;
      pixelBuffer.pixels[i] = ColorConverter.gray(scratchBuffer[position]);
    }
    pixelBuffer.width = horizontalPixels;
    pixelBuffer.height = 1;
    return true;
  }
}
