/*
Base class for all modes
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'i_mode.dart';
import 'native_scanline.dart';
import 'pixel_buffer.dart';

abstract class BaseMode implements IMode {
  final bool useNative;
  NativeSstvScanLine? _nativeScanLine;
  bool _disposed = false;

  BaseMode({this.useNative = !const bool.fromEnvironment('HT_SSTV_DART')});

  bool get usingNativeScanLine => useNative && nativeSstvScanLineSupported;

  bool nativeScanLine(
    PixelBuffer pixels,
    Float64List scratch,
    Float64List input, {
    required int sourceStart,
    required int scratchStart,
    required int count,
    required int width,
    required int kind,
    required double alpha,
    required double frequencyOffset,
    required int first,
    required int firstLength,
    int second = 0,
    int secondLength = 0,
    int third = 0,
    int thirdLength = 0,
    int fourth = 0,
    int fourthLength = 0,
  }) {
    if (_disposed) throw StateError('SSTV mode is disposed');
    if (!usingNativeScanLine) return false;
    final native = _nativeScanLine ??= createNativeSstvScanLine()!;
    native.process(
      input,
      sourceStart,
      scratch,
      scratchStart,
      pixels.pixels,
      [
        kind,
        width,
        count,
        first,
        second,
        third,
        fourth,
        firstLength,
        secondLength,
        thirdLength,
        fourthLength,
      ],
      alpha,
      frequencyOffset,
    );
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _nativeScanLine?.dispose();
  }

  @override
  Int32List postProcessScopeImage(Int32List pixels, int width, int height) =>
      pixels;
}
