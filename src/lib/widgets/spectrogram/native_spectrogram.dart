// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import '../../hamlib/xara/native_dsp.dart';
import 'native_spectrogram_stub.dart'
    if (dart.library.ffi) 'native_spectrogram_ffi.dart'
    as backend;
import 'spectrogram_colormap.dart';

abstract class NativeSpectrogram {
  int get width;
  int get pending;
  int get nextColumn;
  void addSamples(Float64List samples, int offset, int count);
  void addPcm16(Uint8List samples, int offset, int count);
  void process();
  void setFixedWidth(int columns);
  void rollReset(int offset);
  void clear();
  (double, double) peak();
  void render(
    Uint8List rgba,
    SpectrogramColormap colormap,
    double intensity,
    double dbScale,
    bool decibel,
    bool roll,
    int count,
  );
  void dispose();
}

NativeSpectrogram? createNativeSpectrogram(
  int size,
  int step,
  int first,
  int last,
  Float64List window,
) =>
    nativeDspEnabled &&
        !const bool.fromEnvironment('HT_SPECTROGRAM_DART') &&
        !backend.referenceOnly
    ? backend.create(size, step, first, last, window)
    : null;
