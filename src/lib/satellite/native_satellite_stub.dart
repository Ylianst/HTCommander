// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import 'native_satellite.dart';

bool get supported => false;
NativeSatellite create(Float64List coefficients) =>
    throw UnsupportedError('Native satellite propagation unavailable');
