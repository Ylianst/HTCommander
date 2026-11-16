// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'audio_config.dart';
import 'demod_afsk.dart';
import 'ihdlc_receiver.dart';
import 'native_packet_modem_stub.dart'
    if (dart.library.ffi) 'native_packet_modem_ffi.dart'
    as backend;

/// Unsupported platforms retain the reference Dart modem. Native failures on
/// supported platforms are errors, never a reason to replay consumed audio.
bool get nativePacketModemEnabled =>
    !const bool.fromEnvironment('HT_PACKET_MODEM_DART') && backend.supported;

abstract class NativePacketDemodulator {
  /// Owns a fresh DSP stream configured from an initialized, unused Dart state.
  /// Subsequent samples belong exclusively to this native stream.
  factory NativePacketDemodulator(
    DemodulatorState state,
    IHdlcReceiver receiver,
  ) = backend.PacketDemodulator;

  /// Borrows [pcm] only for this call, without modifying or retaining it.
  void process(Uint8List pcm, int offset, int length);
  void dispose();
}

/// Modulates raw NRZI levels, not HDLC data bits. Framing/FEC stay in Dart.
/// Returns little-endian mono PCM, including the requested silence.
Uint8List encodeNativePacketTones(
  AudioChannelConfig channel,
  int sampleRate,
  int amplitude,
  Uint8List bits, {
  int leadingSamples = 0,
  int trailingSamples = 0,
}) => backend.encodeTones(
  channel,
  sampleRate,
  amplitude,
  bits,
  leadingSamples,
  trailingSamples,
);
