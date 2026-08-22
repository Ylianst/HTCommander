/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// Verifies the SoftwareModem external-source API: a frame encoded to AFSK 1200
// PCM and fed through feedExternalSamples is decoded and dispatched as a
// DataFrame attributed to the given device id and channel name.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/hdlc_send.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

/// Encode a raw frame to 32 kHz mono AFSK 1200 PCM the way the software modem's
/// transmit chain does, returned as little-endian 16-bit bytes.
Uint8List _encodeAfsk1200(Uint8List frame) {
  final AudioConfig cfg = AudioConfig();
  cfg.devices[0].defined = true;
  cfg.devices[0].samplesPerSec = 32000;
  cfg.devices[0].bitsPerSample = 16;
  cfg.devices[0].numChannels = 1;
  cfg.channelMedium[0] = Medium.radio;
  cfg.channels[0].numSubchan = 1;
  cfg.channels[0].modemType = ModemType.afsk;
  cfg.channels[0].markFreq = 1200;
  cfg.channels[0].spaceFreq = 2200;
  cfg.channels[0].baud = 1200;
  cfg.channels[0].txdelay = 30;
  cfg.channels[0].txtail = 10;

  final AudioBuffer audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
  final GenTone genTone = GenTone(audioBuffer);
  genTone.init(cfg, 50);
  final HdlcSend hdlcSend = HdlcSend(genTone, cfg);

  audioBuffer.clearAll();
  hdlcSend.sendFlags(0, cfg.channels[0].txdelay, false, null);
  hdlcSend.sendFrame(0, frame, frame.length, false);
  hdlcSend.sendFlags(0, cfg.channels[0].txtail, true, (int device) {});
  final Int16List pcm = audioBuffer.getAndClear(0);

  final Uint8List bytes = Uint8List(pcm.length * 2);
  final ByteData bd = ByteData.sublistView(bytes);
  for (int i = 0; i < pcm.length; i++) {
    bd.setInt16(i * 2, pcm[i], Endian.little);
  }
  return bytes;
}

void main() {
  test('external AFSK source decodes and dispatches an attributed DataFrame',
      () {
    final SoftwareModem modem = SoftwareModem();
    modem.init();

    final DataBrokerClient client = DataBrokerClient();
    final List<TncDataFragment> frames = <TncDataFragment>[];
    client.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'DataFrame',
      callback: (int deviceId, String name, Object? data) {
        if (data is TncDataFragment) frames.add(data);
      },
    );

    // Arbitrary well-formed HDLC payload (the receiver validates the FCS only).
    final Uint8List frame =
        Uint8List.fromList(List<int>.generate(20, (int i) => (i * 7 + 3) & 0xff));

    modem.registerExternalSource(
      sourceId: 300,
      mode: SoftwareModemMode.afsk1200,
      fecEnabled: false,
      attributeDeviceId: 300,
      channelName: 'TestRX',
    );

    modem.feedExternalSamples(300, _encodeAfsk1200(frame));

    expect(frames, isNotEmpty);
    final TncDataFragment f = frames.first;
    expect(f.data, equals(frame));
    expect(f.radioDeviceId, 300);
    expect(f.channelName, 'TestRX');
    expect(f.incoming, isTrue);

    // After unregistering, feeding more audio produces nothing.
    modem.unregisterExternalSource(300);
    frames.clear();
    modem.feedExternalSamples(300, _encodeAfsk1200(frame));
    expect(frames, isEmpty);

    client.dispose();
    modem.dispose();
  });

  test('a paired source attributes frames to the radio device id', () {
    final SoftwareModem modem = SoftwareModem();
    modem.init();

    final DataBrokerClient client = DataBrokerClient();
    final List<TncDataFragment> frames = <TncDataFragment>[];
    client.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'DataFrame',
      callback: (int deviceId, String name, Object? data) {
        if (data is TncDataFragment) frames.add(data);
      },
    );

    final Uint8List frame =
        Uint8List.fromList(List<int>.generate(18, (int i) => (i * 5 + 1) & 0xff));

    // Paired: attributed to the radio's live device id, channel 'APRS'.
    modem.registerExternalSource(
      sourceId: 301,
      mode: SoftwareModemMode.afsk1200,
      fecEnabled: false,
      attributeDeviceId: 102,
      channelName: 'APRS',
      radioMac: 'AA:BB:CC:DD:EE:FF',
    );

    modem.feedExternalSamples(301, _encodeAfsk1200(frame));

    expect(frames, isNotEmpty);
    final TncDataFragment f = frames.first;
    expect(f.data, equals(frame));
    expect(f.radioDeviceId, 102);
    expect(f.channelName, 'APRS');
    expect(f.radioMac, 'AA:BB:CC:DD:EE:FF');

    client.dispose();
    modem.dispose();
  });
}
