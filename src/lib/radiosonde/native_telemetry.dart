// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'native_telemetry_stub.dart'
    if (dart.library.ffi) 'native_telemetry_ffi.dart'
    as backend;

bool get nativeTelemetrySupported => backend.supported;

enum NativeSondeMode {
  manchesterBits,
  nrzBytes,
  differentialBytes,
  nrzBits,
  imetBytes,
}

/// Owns an input snapshot in reusable native storage. Upload once before trying
/// multiple formats; when passed to a demodulator, upload its PCM and rate first.
abstract class NativeTelemetryRecording {
  void upload(Int16List pcm, int sampleRate);
  List<Uint8List> sonde(
    NativeSondeMode mode,
    int chipRate,
    int frameSymbols,
    List<double> header,
  );
  List<Uint8List> sarsat(double carrier);
  void dispose();
}

NativeTelemetryRecording? createNativeTelemetryRecording() =>
    backend.supported ? backend.createRecording() : null;

List<Uint8List> nativeSondeDemodulate(
  Int16List pcm,
  int sampleRate, {
  required NativeSondeMode mode,
  required int chipRate,
  required int frameSymbols,
  required List<double> header,
  NativeTelemetryRecording? recording,
}) => recording != null
    ? recording.sonde(mode, chipRate, frameSymbols, header)
    : backend.sonde(
        pcm,
        sampleRate,
        mode.index,
        chipRate,
        frameSymbols,
        header,
      );

List<Uint8List> nativeSarsatDemodulate(
  Int16List pcm,
  int sampleRate,
  double carrier, {
  NativeTelemetryRecording? recording,
}) => recording != null
    ? recording.sarsat(carrier)
    : backend.sarsat(pcm, sampleRate, carrier);
