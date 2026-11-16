// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_cw_stub.dart'
    if (dart.library.ffi) 'native_cw_ffi.dart'
    as backend;

/// Web and iOS retain the Dart front end. Native failures are not hidden.
bool get nativeCwEnabled =>
    !const bool.fromEnvironment('HT_CW_DART') && backend.supported;

/// Reusable, synchronous Goertzel workspace; envelope and timing live in Dart.
abstract class NativeCw {
  static const int maxWindows = 256;

  /// Returns borrowed [energy, maximumPower, peakProbeIndex] triples.
  /// The view is invalidated by the next call or [dispose]. Input must be finite.
  Float64List analyze(List<double> samples, int start, int windows);
  void dispose();
}

NativeCw? createNativeCw(Float64List coefficients, int window, int hop) {
  if (!nativeCwEnabled) return null;
  return backend.create(coefficients, window, hop);
}
