/*
Decoder for RGB modes
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';
import 'sstv_round.dart';

class RGBDecoder extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final int _horizontalPixels;
  final int _verticalPixels;
  final int _firstSyncPulseIndex;
  final int _scanLineSamples;
  final int _beginSamples;
  final int _redBeginSamples;
  final int _redSamples;
  final int _greenBeginSamples;
  final int _greenSamples;
  final int _blueBeginSamples;
  final int _blueSamples;
  final int _endSamples;
  final String _name;
  final int _code;

  RGBDecoder(
    String name,
    int code,
    int horizontalPixels,
    int verticalPixels,
    double firstSyncPulseSeconds,
    double scanLineSeconds,
    double beginSeconds,
    double redBeginSeconds,
    double redEndSeconds,
    double greenBeginSeconds,
    double greenEndSeconds,
    double blueBeginSeconds,
    double blueEndSeconds,
    double endSeconds,
    int sampleRate,
  ) : _name = name,
      _code = code,
      _horizontalPixels = horizontalPixels,
      _verticalPixels = verticalPixels,
      _firstSyncPulseIndex = sstvRound(firstSyncPulseSeconds * sampleRate),
      _scanLineSamples = sstvRound(scanLineSeconds * sampleRate),
      _beginSamples = sstvRound(beginSeconds * sampleRate),
      _redBeginSamples =
          sstvRound(redBeginSeconds * sampleRate) -
          sstvRound(beginSeconds * sampleRate),
      _redSamples = sstvRound((redEndSeconds - redBeginSeconds) * sampleRate),
      _greenBeginSamples =
          sstvRound(greenBeginSeconds * sampleRate) -
          sstvRound(beginSeconds * sampleRate),
      _greenSamples = sstvRound(
        (greenEndSeconds - greenBeginSeconds) * sampleRate,
      ),
      _blueBeginSamples =
          sstvRound(blueBeginSeconds * sampleRate) -
          sstvRound(beginSeconds * sampleRate),
      _blueSamples = sstvRound(
        (blueEndSeconds - blueBeginSeconds) * sampleRate,
      ),
      _endSamples = sstvRound(endSeconds * sampleRate),
      _lowPassFilter = ExponentialMovingAverage();

  static double _freqToLevel(double frequency, double offset) =>
      0.5 * (frequency - offset + 1.0);

  @override
  String getName() => _name;
  @override
  int getVISCode() => _code;
  @override
  int getWidth() => _horizontalPixels;
  @override
  int getHeight() => _verticalPixels;
  @override
  int getFirstPixelSampleIndex() => _beginSamples;
  @override
  int getFirstSyncPulseIndex() => _firstSyncPulseIndex;
  @override
  int getScanLineSamples() => _scanLineSamples;
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
    if (syncPulseIndex + _beginSamples < 0 ||
        syncPulseIndex + _endSamples > scanLineBuffer.length) {
      return false;
    }
    _lowPassFilter.cutoff(_horizontalPixels, 2 * _greenSamples, 2);
    _lowPassFilter.reset();
    for (int i = 0; i < _endSamples - _beginSamples; ++i) {
      scratchBuffer[i] = _lowPassFilter.avg(
        scanLineBuffer[syncPulseIndex + _beginSamples + i],
      );
    }
    _lowPassFilter.reset();
    for (int i = _endSamples - _beginSamples - 1; i >= 0; --i) {
      scratchBuffer[i] = _freqToLevel(
        _lowPassFilter.avg(scratchBuffer[i]),
        frequencyOffset,
      );
    }
    for (int i = 0; i < _horizontalPixels; ++i) {
      final redPos = _redBeginSamples + (i * _redSamples) ~/ _horizontalPixels;
      final greenPos =
          _greenBeginSamples + (i * _greenSamples) ~/ _horizontalPixels;
      final bluePos =
          _blueBeginSamples + (i * _blueSamples) ~/ _horizontalPixels;
      pixelBuffer.pixels[i] = ColorConverter.rgb(
        scratchBuffer[redPos],
        scratchBuffer[greenPos],
        scratchBuffer[bluePos],
      );
    }
    pixelBuffer.width = _horizontalPixels;
    pixelBuffer.height = 1;
    return true;
  }
}
