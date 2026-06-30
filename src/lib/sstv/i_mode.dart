/*
Mode interface
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'pixel_buffer.dart';

abstract class IMode {
  String getName();

  int getVISCode();

  int getWidth();

  int getHeight();

  int getFirstPixelSampleIndex();

  int getFirstSyncPulseIndex();

  int getScanLineSamples();

  Int32List postProcessScopeImage(Int32List pixels, int width, int height);

  void resetState();

  /// Decode a scan line.
  ///
  /// [frequencyOffset] is the normalized correction of frequency
  /// (expected vs actual). Returns true if the scan line was decoded.
  bool decodeScanLine(
    PixelBuffer pixelBuffer,
    Float64List scratchBuffer,
    Float64List scanLineBuffer,
    int scopeBufferWidth,
    int syncPulseIndex,
    int scanLineSamples,
    double frequencyOffset,
  );
}
