// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_gsm_stub.dart'
    if (dart.library.ffi) 'native_gsm_ffi.dart'
    as backend;

/// Keep the pure-Dart EchoLink codec with --dart-define=HT_GSM_DART=true.
bool get nativeGsmEnabled =>
    !const bool.fromEnvironment('HT_GSM_DART') && backend.supported;

int get nativeGsmSimdWidth =>
    nativeGsmEnabled && !const bool.fromEnvironment('HT_GSM_SCALAR')
    ? backend.simdWidth
    : 1;

/// One continuous TX stream of four 160-sample frames per call.
abstract class NativeGsmEncoder {
  void encode(Int16List pcm, int pcmOff, Uint8List out, int outOff);
  void reset();
  void dispose();
}

/// One continuous RX stream of four 33-byte toast frames per call.
abstract class NativeGsmDecoder {
  Int16List decode(Uint8List frames);
  void reset();
  void dispose();
}

NativeGsmEncoder? createNativeGsmEncoder({bool simd = true}) =>
    nativeGsmEnabled ? backend.createEncoder(simd) : null;

NativeGsmDecoder? createNativeGsmDecoder() =>
    nativeGsmEnabled ? backend.createDecoder() : null;
