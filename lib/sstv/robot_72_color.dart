/*
Robot 72 Color
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';
import 'sstv_round.dart';

// ignore_for_file: camel_case_types
class Robot_72_Color extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final int _horizontalPixels;
  final int _verticalPixels;
  final int _scanLineSamplesValue;
  final int _luminanceSamples;
  final int _chrominanceSamples;
  final int _beginSamples;
  final int _yBeginSamples;
  final int _vBeginSamples;
  final int _uBeginSamples;
  final int _endSamples;

  factory Robot_72_Color(int sampleRate) {
    const horizontalPixels = 320;
    const verticalPixels = 240;
    const double syncPulseSeconds = 0.009;
    const double syncPorchSeconds = 0.003;
    const double luminanceSeconds = 0.138;
    const double separatorSeconds = 0.0045;
    const double porchSeconds = 0.0015;
    const double chrominanceSeconds = 0.069;
    const double scanLineSeconds =
        syncPulseSeconds +
        syncPorchSeconds +
        luminanceSeconds +
        2 * (separatorSeconds + porchSeconds + chrominanceSeconds);
    const double yBeginSeconds = syncPorchSeconds;
    const double yEndSeconds = yBeginSeconds + luminanceSeconds;
    const double vBeginSeconds = yEndSeconds + separatorSeconds + porchSeconds;
    const double vEndSeconds = vBeginSeconds + chrominanceSeconds;
    const double uBeginSeconds = vEndSeconds + separatorSeconds + porchSeconds;
    const double uEndSeconds = uBeginSeconds + chrominanceSeconds;
    final yBeginSamples = sstvRound(yBeginSeconds * sampleRate);
    return Robot_72_Color._(
      horizontalPixels,
      verticalPixels,
      sstvRound(scanLineSeconds * sampleRate),
      sstvRound(luminanceSeconds * sampleRate),
      sstvRound(chrominanceSeconds * sampleRate),
      yBeginSamples,
      yBeginSamples,
      sstvRound(vBeginSeconds * sampleRate),
      sstvRound(uBeginSeconds * sampleRate),
      sstvRound(uEndSeconds * sampleRate),
    );
  }

  Robot_72_Color._(
    this._horizontalPixels,
    this._verticalPixels,
    this._scanLineSamplesValue,
    this._luminanceSamples,
    this._chrominanceSamples,
    this._beginSamples,
    this._yBeginSamples,
    this._vBeginSamples,
    this._uBeginSamples,
    this._endSamples,
  ) : _lowPassFilter = ExponentialMovingAverage();

  static double _freqToLevel(double frequency, double offset) =>
      0.5 * (frequency - offset + 1.0);

  @override
  String getName() => 'Robot 72 Color';
  @override
  int getVISCode() => 12;
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
      final yPos =
          _yBeginSamples + (i * _luminanceSamples) ~/ _horizontalPixels;
      final uPos =
          _uBeginSamples + (i * _chrominanceSamples) ~/ _horizontalPixels;
      final vPos =
          _vBeginSamples + (i * _chrominanceSamples) ~/ _horizontalPixels;
      pixelBuffer.pixels[i] = ColorConverter.yuv2rgb(
        scratchBuffer[yPos],
        scratchBuffer[uPos],
        scratchBuffer[vPos],
      );
    }
    pixelBuffer.width = _horizontalPixels;
    pixelBuffer.height = 1;
    return true;
  }
}
