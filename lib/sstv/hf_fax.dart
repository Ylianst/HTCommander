/*
HF Fax mode
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;
import 'dart:typed_data';
import 'base_mode.dart';
import 'color_converter.dart';
import 'exponential_moving_average.dart';
import 'pixel_buffer.dart';

/// HF Fax, IOC 576, 120 lines per minute
class HFFax extends BaseMode {
  final ExponentialMovingAverage _lowPassFilter;
  final String _name;
  final int _sampleRate;
  final Float64List _cumulated;
  int _horizontalShift = 0;

  HFFax(int sampleRate)
    : _name = 'HF Fax',
      _lowPassFilter = ExponentialMovingAverage(),
      _sampleRate = sampleRate,
      _cumulated = Float64List(640);

  static double _freqToLevel(double frequency, double offset) =>
      0.5 * (frequency - offset + 1.0);

  @override
  String getName() => _name;
  @override
  int getVISCode() => -1;
  @override
  int getWidth() => 640;
  @override
  int getHeight() => 1200;
  @override
  int getFirstPixelSampleIndex() => 0;
  @override
  int getFirstSyncPulseIndex() => -1;
  @override
  int getScanLineSamples() => _sampleRate ~/ 2;
  @override
  void resetState() {}

  @override
  Int32List postProcessScopeImage(Int32List pixels, int width, int height) {
    const int realWidth = 1808;
    final int realHorizontalShift = _horizontalShift * realWidth ~/ getWidth();
    final result = Int32List(realWidth * height);

    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < realWidth; ++x) {
        int srcX;
        if (_horizontalShift > 0 && x >= realWidth - realHorizontalShift) {
          // Right side of result maps to left part of source.
          srcX =
              (x - (realWidth - realHorizontalShift)) *
              _horizontalShift ~/
              realHorizontalShift;
        } else {
          // Left side of result maps to source (horizontalShift..width).
          final srcWidth = getWidth() - _horizontalShift;
          final dstWidth = realWidth - realHorizontalShift;
          srcX = _horizontalShift + x * srcWidth ~/ dstWidth;
        }
        srcX = math.min(srcX, getWidth() - 1);
        srcX = math.max(srcX, 0);
        result[y * realWidth + x] = pixels[y * width + srcX];
      }
    }

    return result;
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
    if (syncPulseIndex < 0 ||
        syncPulseIndex + scanLineSamples > scanLineBuffer.length) {
      return false;
    }
    final horizontalPixels = getWidth();
    _lowPassFilter.cutoff(horizontalPixels, 2 * scanLineSamples, 2);
    _lowPassFilter.reset();
    for (int i = 0; i < scanLineSamples; ++i) {
      scratchBuffer[i] = _lowPassFilter.avg(scanLineBuffer[i]);
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
      final color = ColorConverter.gray(scratchBuffer[position]);
      pixelBuffer.pixels[i] = color;

      // Accumulate recent values, forget old.
      const double decay = 0.99;
      final luminance =
          ((color >> 16) & 0xFF) /
          255.0; // extract R channel as luminance proxy
      _cumulated[i] = _cumulated[i] * decay + luminance * (1 - decay);
    }

    // Try to detect "sync": thick white margin.
    int bestIndex = 0;
    double bestValue = 0;
    for (int x = 0; x < getWidth(); ++x) {
      final val = _cumulated[x];
      if (val > bestValue) {
        bestIndex = x;
        bestValue = val;
      }
    }

    _horizontalShift = bestIndex;

    pixelBuffer.width = horizontalPixels;
    pixelBuffer.height = 1;
    return true;
  }
}
