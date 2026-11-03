/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// Software modems must never key up while the radio is receiving. Receive
// activity comes from the Bluetooth audio runs (AudioDataStart / AudioDataEnd
// with transmit=false), which follow the radio's squelch; RSSI is ignored.
//

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker_client.dart';

const int radio = 102;

Uint8List _call(String call, int ssid, {bool last = false}) {
  final Uint8List b = Uint8List(7);
  final String c = call.padRight(6);
  for (int i = 0; i < 6; i++) {
    b[i] = c.codeUnitAt(i) << 1;
  }
  b[6] = 0x60 | (ssid << 1) | (last ? 1 : 0);
  return b;
}

/// An AX.25 UI frame (no FCS) from N0CALL to APRS.
Uint8List uiFrame() => Uint8List.fromList(<int>[
      ..._call('APRS', 0),
      ..._call('N0CALL', 0, last: true),
      0x03,
      0xF0,
      ...'hello world'.codeUnits,
    ]);

Future<bool> waitFor(bool Function() done, Duration limit) async {
  final DateTime end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

void main() {
  test('cancelled queued packets do not resume when RX ends', () async {
    final client = DataBrokerClient();
    final modem = SoftwareModem()..init();
    modem.setMode(SoftwareModemMode.afsk1200, persist: false);
    addTearDown(() {
      modem.dispose();
      client.dispose();
    });
    var transmissions = 0;
    client.subscribe(
      deviceId: radio,
      name: 'TransmitVoicePCM',
      callback: (_, _, _) => transmissions++,
    );
    client.dispatch(
      deviceId: radio,
      name: 'AudioDataStart',
      data: {'transmit': false},
      store: false,
    );
    modem.transmitPacket(
      radio,
      TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: uiFrame(),
        channelId: 14,
        regionId: 0,
      ),
    );
    client.dispatch(
      deviceId: radio,
      name: 'CancelDataTransmit',
      data: null,
      store: false,
    );
    client.dispatch(
      deviceId: radio,
      name: 'AudioDataEnd',
      data: {'transmit': false},
      store: false,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(transmissions, 0);
  });

  test('an encode completing after cancellation cannot transmit', () async {
    final client = DataBrokerClient();
    final modem = SoftwareModem()..init();
    modem.setMode(SoftwareModemMode.dart, persist: false);
    addTearDown(() {
      modem.dispose();
      client.dispose();
    });
    final cancelled = Completer<void>();
    var transmissions = 0;
    client.subscribe(
      deviceId: radio,
      name: 'TransmitVoicePCM',
      callback: (_, _, _) => transmissions++,
    );
    // Cancel at the encoder's completion, before its awaiting flush resumes.
    client.subscribe(
      deviceId: 1,
      name: 'LogInfo',
      callback: (_, _, data) {
        if (cancelled.isCompleted || data is! String || !data.contains('TX DART:')) {
          return;
        }
        client.dispatch(
          deviceId: radio,
          name: 'CancelDataTransmit',
          data: null,
          store: false,
        );
        cancelled.complete();
      },
    );
    TncDataFragment frame() => TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: uiFrame(),
      channelId: 14,
      regionId: 0,
    );
    modem.transmitPacket(radio, frame());
    await cancelled.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(transmissions, 0);

    modem.transmitPacket(radio, frame());
    expect(
      await waitFor(() => transmissions == 1, const Duration(seconds: 15)),
      isTrue,
      reason: 'a fresh modem should still be able to transmit',
    );
  });

  for (final String mode in <String>['AFSK1200', 'DART', 'XARA']) {
    test('$mode does not transmit while the radio is receiving audio', () async {
      final DataBrokerClient client = DataBrokerClient();
      client.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL', store: true);
      client.dispatch(deviceId: radio, name: 'LockState', data: null, store: true);
      client.dispatch(
        deviceId: radio,
        name: 'Channels',
        data: <Map<String, dynamic>>[
          RadioChannelInfo(channelId: 14, name: 'Data').toJson(),
        ],
      );
      // A non-zero RSSI used to block transmission; it must now be ignored.
      client.dispatch(
        deviceId: radio,
        name: 'HtStatus',
        data: <String, Object?>{'currChId': 14, 'currRegion': 0, 'rssi': 5},
      );

      final SoftwareModem modem = SoftwareModem();
      modem.init();
      client.dispatch(deviceId: 0, name: 'SetSoftwareModemMode', data: mode, store: false);

      int transmissions = 0;
      client.subscribe(
        deviceId: radio,
        name: 'TransmitVoicePCM',
        callback: (int d, String n, Object? data) => transmissions++,
      );

      try {
        client.dispatch(
          deviceId: radio,
          name: 'AudioDataStart',
          data: <String, Object?>{'transmit': false, 'channelName': 'Data'},
          store: false,
        );
        client.dispatch(
          deviceId: radio,
          name: 'SoftModemTransmitPacket',
          data: TncDataFragment(
            finalFragment: true,
            fragmentId: 0,
            data: uiFrame(),
            channelId: 14,
            regionId: 0,
            channelName: 'Data',
          ),
          store: false,
        );

        // Our own transmit echo must not count as reception ending.
        client.dispatch(
          deviceId: radio,
          name: 'AudioDataEnd',
          data: <String, Object?>{'transmit': true},
          store: false,
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(transmissions, 0, reason: 'keyed up while the radio was receiving');

        client.dispatch(
          deviceId: radio,
          name: 'AudioDataEnd',
          data: <String, Object?>{'transmit': false},
          store: false,
        );
        expect(
          await waitFor(() => transmissions > 0, const Duration(seconds: 15)),
          isTrue,
          reason: 'did not transmit once the radio stopped receiving',
        );
      } finally {
        modem.dispose();
        client.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}
