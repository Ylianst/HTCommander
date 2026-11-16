// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'native_gsm.dart';

bool get supported => false;
int get simdWidth => 1;
NativeGsmEncoder createEncoder(bool simd) =>
    throw UnsupportedError('Native GSM is unavailable');
NativeGsmDecoder createDecoder() =>
    throw UnsupportedError('Native GSM is unavailable');
