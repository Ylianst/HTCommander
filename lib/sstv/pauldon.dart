/*
PD modes
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';
import 'sstv_round.dart';

class PaulDon extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final int _horizontalPixels;
  final int _verticalPixels;
  final int _scanLineSamplesValue;
  final int _channelSamples;
  final int _beginSamples;
  final int _yEvenBeginSamples;
  final int _vAvgBeginSamples;
  final int _uAvgBeginSamples;
  final int _yOddBeginSamples;
  final int _endSamples;
  final String _name;
  final int _code;

  factory PaulDon(
    String name,
    int code,
    int horizontalPixels,
    int verticalPixels,
    double channelSeconds,
    int sampleRate,
  ) {
    const double syncPulseSeconds = 0.02;
    const double syncPorchSeconds = 0.00208;
    final double scanLineSeconds =
        syncPulseSeconds + syncPorchSeconds + 4 * channelSeconds;
    const double yEvenBeginSeconds = syncPorchSeconds;
    final double vAvgBeginSeconds = yEvenBeginSeconds + channelSeconds;
    final double uAvgBeginSeconds = vAvgBeginSeconds + channelSeconds;
    final double yOddBeginSeconds = uAvgBeginSeconds + channelSeconds;
    final double yOddEndSeconds = yOddBeginSeconds + channelSeconds;
    final yEvenBeginSamples = sstvRound(yEvenBeginSeconds * sampleRate);
    return PaulDon._(
      'PD $name',
      code,
      horizontalPixels,
      verticalPixels,
      sstvRound(scanLineSeconds * sampleRate),
      sstvRound(channelSeconds * sampleRate),
      yEvenBeginSamples,
      yEvenBeginSamples,
      sstvRound(vAvgBeginSeconds * sampleRate),
      sstvRound(uAvgBeginSeconds * sampleRate),
      sstvRound(yOddBeginSeconds * sampleRate),
      sstvRound(yOddEndSeconds * sampleRate),
    );
  }

  PaulDon._(
    this._name,
    this._code,
    this._horizontalPixels,
    this._verticalPixels,
    this._scanLineSamplesValue,
    this._channelSamples,
    this._beginSamples,
    this._yEvenBeginSamples,
    this._vAvgBeginSamples,
    this._uAvgBeginSamples,
    this._yOddBeginSamples,
    this._endSamples,
  ) : _lowPassFilter = ExponentialMovingAverage();

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
  int getFirstSyncPulseIndex() => 0;
  @override
  int getScanLineSamples() => _scanLineSamplesValue;
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
    _lowPassFilter.cutoff(_horizontalPixels, 2 * _channelSamples, 2);
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
      final position = (i * _channelSamples) ~/ _horizontalPixels;
      final yEvenPos = position + _yEvenBeginSamples;
      final vAvgPos = position + _vAvgBeginSamples;
      final uAvgPos = position + _uAvgBeginSamples;
      final yOddPos = position + _yOddBeginSamples;
      pixelBuffer.pixels[i] = ColorConverter.yuv2rgb(
        scratchBuffer[yEvenPos],
        scratchBuffer[uAvgPos],
        scratchBuffer[vAvgPos],
      );
      pixelBuffer.pixels[i + _horizontalPixels] = ColorConverter.yuv2rgb(
        scratchBuffer[yOddPos],
        scratchBuffer[uAvgPos],
        scratchBuffer[vAvgPos],
      );
    }
    pixelBuffer.width = _horizontalPixels;
    pixelBuffer.height = 2;
    return true;
  }
}
