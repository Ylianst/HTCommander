// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'audio_config.dart';
import 'demod_afsk.dart';
import 'ihdlc_receiver.dart';
import 'native_packet_modem.dart';

bool get supported => false;

class PacketDemodulator implements NativePacketDemodulator {
  PacketDemodulator(DemodulatorState state, IHdlcReceiver receiver) {
    throw UnsupportedError('Native packet modem is unavailable');
  }

  @override
  void process(Uint8List pcm, int offset, int length) =>
      throw UnsupportedError('Native packet modem is unavailable');

  @override
  void dispose() {}
}

Uint8List encodeTones(
  AudioChannelConfig channel,
  int sampleRate,
  int amplitude,
  Uint8List bits,
  int leading,
  int trailing,
) => throw UnsupportedError('Native packet modem is unavailable');
