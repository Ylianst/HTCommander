// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';
import 'native_telemetry.dart';

bool get supported => false;

NativeTelemetryRecording createRecording() =>
    throw UnsupportedError('Native telemetry DSP is unavailable');

List<Uint8List> sonde(
  Int16List pcm,
  int rate,
  int mode,
  int chipRate,
  int symbols,
  List<double> header,
) => throw UnsupportedError('Native telemetry DSP is unavailable');

List<Uint8List> sarsat(Int16List pcm, int rate, double carrier) =>
    throw UnsupportedError('Native telemetry DSP is unavailable');
