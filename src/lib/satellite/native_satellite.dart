// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_satellite_stub.dart'
    if (dart.library.ffi) 'native_satellite_ffi.dart'
    as impl;

abstract class NativeSatellite {
  static bool get supported => impl.supported;

  /// Only unsupported platforms return null. Missing assets, ABI mismatches
  /// and allocation failures on supported platforms are explicit errors.
  static NativeSatellite? create(Float64List coefficients) {
    if (!supported) return null;
    return impl.create(coefficients);
  }

  /// Rows: Vallado status followed by TEME x,y,z (km), vx,vy,vz (km/s).
  /// Implementations bound each FFI invocation to 256 samples.
  Float64List propagate(Float64List minutes);

  /// Five doubles per row: status, azimuth/elevation (deg), range (km) and
  /// range rate (km/s). Uses the package's inclusive, endpoint-clamped grid.
  Float64List lookGrid({
    required int epochUs,
    required int fromUs,
    required int toUs,
    required int stepUs,
    required double latitudeDeg,
    required double longitudeDeg,
    required double altitudeMeters,
  });
  void dispose();
}
