// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_demodulator.dart';

bool get supported => false;
int get simdWidth => 1;

NativeSstvDemodulator? create(
  int sampleRate,
  Float64List taps,
  int syncCount,
  int min5,
  int max5,
  int max9,
  int max20,
  bool useSimd,
) => null;
