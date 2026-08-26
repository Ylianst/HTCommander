/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/audio_rx/audio_rx_device.dart';

void main() {
  group('AudioRxDevice', () {
    test('round-trips an unpaired Comms device through toMap/fromMap', () {
      const device = AudioRxDevice(
        deviceId: 301,
        name: 'Shack Base',
        inputDeviceId: 'line-in-1',
        inputDeviceLabel: 'Line In (Realtek)',
        usage: AudioRxUsage.comms,
        modem: AudioRxModem.psk2400,
        fecEnabled: false,
        pairedRadioMac: '',
        audioChannel: AudioRxChannel.right,
        audioGain: 4.0,
      );

      final AudioRxDevice copy = AudioRxDevice.fromMap(device.toMap());

      expect(copy.deviceId, 301);
      expect(copy.name, 'Shack Base');
      expect(copy.inputDeviceId, 'line-in-1');
      expect(copy.inputDeviceLabel, 'Line In (Realtek)');
      expect(copy.usage, AudioRxUsage.comms);
      expect(copy.modem, AudioRxModem.psk2400);
      expect(copy.fecEnabled, false);
      expect(copy.isPaired, false);
      expect(copy.audioChannel, AudioRxChannel.right);
      expect(copy.audioGain, 4.0);
    });

    test('round-trips a paired device', () {
      const device = AudioRxDevice(
        deviceId: 300,
        name: '',
        inputDeviceId: 'usb-audio',
        usage: AudioRxUsage.paired,
        modem: AudioRxModem.dart,
        pairedRadioMac: 'AA:BB:CC:DD:EE:FF',
      );

      final AudioRxDevice copy = AudioRxDevice.fromMap(device.toMap());

      expect(copy.usage, AudioRxUsage.paired);
      expect(copy.modem, AudioRxModem.dart);
      expect(copy.pairedRadioMac, 'AA:BB:CC:DD:EE:FF');
      expect(copy.isPaired, true);
      expect(copy.fecEnabled, true); // default
    });

    test('migrates a legacy device that stored a paired radio to paired mode',
        () {
      // Older builds recorded pairing as a separate field alongside an
      // 'aprs'/'comms' usage; that device must load as the paired mode.
      final AudioRxDevice copy = AudioRxDevice.fromMap(<String, Object?>{
        'DeviceId': 300,
        'InputDeviceId': 'usb-audio',
        'Usage': 'aprs',
        'PairedRadioMac': 'AA:BB:CC:DD:EE:FF',
      });

      expect(copy.usage, AudioRxUsage.paired);
      expect(copy.pairedRadioMac, 'AA:BB:CC:DD:EE:FF');
      expect(copy.isPaired, true);
    });

    test('fromMap tolerates missing/partial fields', () {
      final AudioRxDevice copy = AudioRxDevice.fromMap(<String, Object?>{
        'Name': 'Partial',
      });

      expect(copy.deviceId, audioRxDeviceIdBase);
      expect(copy.name, 'Partial');
      expect(copy.inputDeviceId, '');
      expect(copy.usage, AudioRxUsage.aprs);
      expect(copy.modem, AudioRxModem.afsk1200);
      expect(copy.fecEnabled, true);
      expect(copy.isPaired, false);
      expect(copy.audioChannel, AudioRxChannel.auto); // default
      expect(copy.audioGain, 1.0); // default
    });

    test('copyWith overrides only the given fields', () {
      const device = AudioRxDevice(
        deviceId: 305,
        name: 'A',
        inputDeviceId: 'x',
        usage: AudioRxUsage.comms,
        modem: AudioRxModem.afsk1200,
      );

      final AudioRxDevice updated =
          device.copyWith(name: 'B', modem: AudioRxModem.dart);

      expect(updated.deviceId, 305);
      expect(updated.name, 'B');
      expect(updated.inputDeviceId, 'x');
      expect(updated.modem, AudioRxModem.dart);
      expect(updated.usage, AudioRxUsage.comms);
    });
  });
}
