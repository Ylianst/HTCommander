/*
Robot 36 Color
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';
import 'sstv_round.dart';

// ignore_for_file: camel_case_types
class Robot_36_Color extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final int _horizontalPixels;
  final int _verticalPixels;
  final int _scanLineSamplesValue;
  final int _luminanceSamples;
  final int _separatorSamples;
  final int _chrominanceSamples;
  final int _beginSamples;
  final int _luminanceBeginSamples;
  final int _separatorBeginSamples;
  final int _chrominanceBeginSamples;
  final int _endSamples;
  bool _lastEven = false;

  factory Robot_36_Color(int sampleRate) {
    const horizontalPixels = 320;
    const verticalPixels = 240;
    const double syncPulseSeconds = 0.009;
    const double syncPorchSeconds = 0.003;
    const double luminanceSeconds = 0.088;
    const double separatorSeconds = 0.0045;
    const double porchSeconds = 0.0015;
    const double chrominanceSeconds = 0.044;
    const double scanLineSeconds =
        syncPulseSeconds +
        syncPorchSeconds +
        luminanceSeconds +
        separatorSeconds +
        porchSeconds +
        chrominanceSeconds;
    const double luminanceBeginSeconds = syncPorchSeconds;
    const double separatorBeginSeconds =
        luminanceBeginSeconds + luminanceSeconds;
    const double separatorEndSeconds = separatorBeginSeconds + separatorSeconds;
    const double chrominanceBeginSeconds = separatorEndSeconds + porchSeconds;
    const double chrominanceEndSeconds =
        chrominanceBeginSeconds + chrominanceSeconds;
    final luminanceBeginSamples = sstvRound(luminanceBeginSeconds * sampleRate);
    return Robot_36_Color._(
      horizontalPixels,
      verticalPixels,
      sstvRound(scanLineSeconds * sampleRate),
      sstvRound(luminanceSeconds * sampleRate),
      sstvRound(separatorSeconds * sampleRate),
      sstvRound(chrominanceSeconds * sampleRate),
      luminanceBeginSamples,
      luminanceBeginSamples,
      sstvRound(separatorBeginSeconds * sampleRate),
      sstvRound(chrominanceBeginSeconds * sampleRate),
      sstvRound(chrominanceEndSeconds * sampleRate),
    );
  }

  Robot_36_Color._(
    this._horizontalPixels,
    this._verticalPixels,
    this._scanLineSamplesValue,
    this._luminanceSamples,
    this._separatorSamples,
    this._chrominanceSamples,
    this._beginSamples,
    this._luminanceBeginSamples,
    this._separatorBeginSamples,
    this._chrominanceBeginSamples,
    this._endSamples,
  ) : _lowPassFilter = ExponentialMovingAverage();

  static double _freqToLevel(double frequency, double offset) =>
      0.5 * (frequency - offset + 1.0);

  @override
  String getName() => 'Robot 36 Color';
  @override
  int getVISCode() => 8;
  @override
  int getWidth() => _horizontalPixels;
  @override
  int getHeight() => _verticalPixels;
  @override
  int getFirstPixelSampleIndex() => _beginSamples;
  @override
  int getFirstSyncPulseIndex() => 0;
  @override
  int getScanLineSamples() => _scanLineSamplesValue;

  @override
  void resetState() {
    _lastEven = false;
  }

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
    double separator = 0;
    for (int i = 0; i < _separatorSamples; ++i) {
      separator += scanLineBuffer[syncPulseIndex + _separatorBeginSamples + i];
    }
    separator /= _separatorSamples;
    separator -= frequencyOffset;
    bool even = separator < 0;
    if (separator < -1.1 ||
        (separator > -0.9 && separator < 0.9) ||
        separator > 1.1) {
      even = !_lastEven;
    }
    _lastEven = even;
    _lowPassFilter.cutoff(_horizontalPixels, 2 * _luminanceSamples, 2);
    _lowPassFilter.reset();
    for (int i = _beginSamples; i < _endSamples; ++i) {
      scratchBuffer[i] = _lowPassFilter.avg(scanLineBuffer[syncPulseIndex + i]);
    }
    _lowPassFilter.reset();
    for (int i = _endSamples - 1; i >= _beginSamples; --i) {
      scratchBuffer[i] = _freqToLevel(
        _lowPassFilter.avg(scratchBuffer[i]),
        frequencyOffset,
      );
    }
    for (int i = 0; i < _horizontalPixels; ++i) {
      final luminancePos =
          _luminanceBeginSamples + (i * _luminanceSamples) ~/ _horizontalPixels;
      final chrominancePos =
          _chrominanceBeginSamples +
          (i * _chrominanceSamples) ~/ _horizontalPixels;
      if (even) {
        pixelBuffer.pixels[i] = ColorConverter.rgb(
          scratchBuffer[luminancePos],
          0,
          scratchBuffer[chrominancePos],
        );
      } else {
        final evenYUV = pixelBuffer.pixels[i];
        final oddYUV = ColorConverter.rgb(
          scratchBuffer[luminancePos],
          scratchBuffer[chrominancePos],
          0,
        );
        pixelBuffer.pixels[i] = ColorConverter.yuv2rgbPacked(
          (evenYUV & 0x00ff00ff) | (oddYUV & 0x0000ff00),
        );
        pixelBuffer.pixels[i +
            _horizontalPixels] = ColorConverter.yuv2rgbPacked(
          (oddYUV & 0x00ffff00) | (evenYUV & 0x000000ff),
        );
      }
    }
    pixelBuffer.width = _horizontalPixels;
    pixelBuffer.height = 2;
    return !even;
  }
}
