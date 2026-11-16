// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/fx25.dart';
import 'package:htcommander/hamlib/fx25_send.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/hdlc_send.dart';
import 'package:htcommander/radio/modem_tx_encoder.dart';

Uint8List _reference(
  PacketModulation mode,
  int rate,
  bool fec,
  List<Uint8List> frames,
) {
  final config = AudioConfig();
  config.devices[0].defined = true;
  config.devices[0].samplesPerSec = rate;
  config.devices[0].bitsPerSample = 16;
  config.devices[0].numChannels = 1;
  config.channelMedium[0] = Medium.radio;
  final channel = config.channels[0];
  channel.modemType = mode == PacketModulation.afsk1200
      ? ModemType.afsk
      : ModemType.qpsk;
  channel.baud = mode == PacketModulation.afsk1200 ? 1200 : 2400;
  channel.v26Alt = V26Alternative.b;
  final buffer = AudioBuffer(1);
  final tone = GenTone(buffer)..init(config, 50);
  final hdlc = HdlcSend(tone, config);
  final fx25 = Fx25Send()..init(tone);
  for (int i = 0; i < rate ~/ 2; i++) {
    buffer.put(0, 0);
  }
  hdlc.sendFlags(0, 30, false, null);
  for (final frame in frames) {
    int sent = -1;
    if (fec && frame.length >= 15) {
      sent = fx25.sendFrame(0, frame, frame.length, 16);
    }
    if (sent < 0) hdlc.sendFrame(0, frame, frame.length, false);
  }
  hdlc.sendFlags(0, 10, true, (_) {});
  for (int i = 0; i < rate ~/ 10; i++) {
    buffer.put(0, 0);
  }
  final samples = buffer.getAndClear(0);
  final pcm = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(pcm);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return pcm;
}

void main() {
  setUpAll(() => Fx25.init(0));
  for (final mode in PacketModulation.values) {
    for (final rate in [32000, 48000]) {
      for (final fec in [false, true]) {
        test(
          '$mode $rate Hz FEC=$fec bundled isolate TX matches reference',
          () async {
            final encoder = ModemTxEncoder();
            addTearDown(encoder.dispose);
            final frames = [
              Uint8List.fromList(List.generate(83, (i) => (i * 13 + 7) & 255)),
              Uint8List.fromList([
                0xff,
                0xff,
                0xff,
                0x7e,
              ]), // No FEC for short data.
              Uint8List.fromList(List.generate(34, (i) => (i * 17 + 3) & 255)),
            ];
            // Also cover reuse of the isolate with no tones and only PTT silence.
            for (final bundle in [frames, <Uint8List>[]]) {
              final result = await encoder.encodePacket(
                modulation: mode,
                fecEnabled: fec,
                sampleRate: rate,
                txdelay: bundle.isEmpty ? 0 : 30,
                txtail: bundle.isEmpty ? 0 : 10,
                frames: bundle,
              );
              expect(
                result.logs.any((line) => line.contains('encode error')),
                false,
              );
              if (bundle.isEmpty) {
                expect(result.pcm!.length, (rate ~/ 2 + rate ~/ 10) * 2);
                expect(result.pcm, everyElement(0));
              } else {
                expect(result.pcm, _reference(mode, rate, fec, frames));
              }
            }
          },
        );
      }
    }
  }
}
