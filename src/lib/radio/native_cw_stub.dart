// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_cw.dart';

bool get supported => false;

NativeCw create(Float64List coefficients, int window, int hop) =>
    throw UnsupportedError('Native CW DSP is unavailable on this platform');
