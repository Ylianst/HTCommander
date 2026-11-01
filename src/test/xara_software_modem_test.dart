/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// End-to-end test of the XARA software modem inside HTCommander: SoftwareModem
// (device 101, XARA mode) talks to a second XARA modem isolate through a
// simulated radio. Transmit PCM from 'TransmitVoicePCM' is played to the peer
// in real time after a key-up latency, and the peer's audio comes back as
// 'AudioDataAvailable' runs, exactly as the Bluetooth audio path delivers it.
// Cached status reports APRS while the PCM stream is tagged as the data channel.
//

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/xara_modem.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

const int radio = 101;
const int chunk = 640; // 20 ms at 32 kHz

/// Plays queued PCM bursts in real time, starting [lagMs] after they are queued.
class Playout {
  final int lagMs;
  final void Function(Uint8List chunk) deliver;
  final List<(DateTime, Uint8List)> _queue = <(DateTime, Uint8List)>[];
  Uint8List? _cur;
  int _pos = 0;

  Playout(this.lagMs, this.deliver);

  void add(Uint8List pcm) =>
      _queue.add((DateTime.now().add(Duration(milliseconds: lagMs)), pcm));

  bool get busy => _cur != null;

  void tick() {
    if (_cur == null &&
        _queue.isNotEmpty &&
        !DateTime.now().isBefore(_queue.first.$1)) {
      _cur = _queue.removeAt(0).$2;
      _pos = 0;
    }
    final Uint8List? cur = _cur;
    if (cur == null) return;
    final int end = (_pos + 2 * chunk).clamp(0, cur.length);
    deliver(Uint8List.fromList(cur.sublist(_pos, end)));
    _pos = end;
    if (_pos >= cur.length) _cur = null;
  }
}

Future<bool> waitFor(bool Function() done, Duration limit) async {
  final DateTime end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

void main() {
  for (final wide in [false, true]) {
    test(
      'XARA ${wide ? "wide lock override" : "narrow global mode"} links, transfers and broadcasts through SoftwareModem',
      () async {
        final DataBrokerClient client = DataBrokerClient();
        client.dispatch(
          deviceId: 0,
          name: 'CallSign',
          data: 'N0CALL',
          store: true,
        );
        client.dispatch(
          deviceId: 0,
          name: 'XaraTxLatencyMs',
          data: 400,
          store: true,
        );
        client.dispatch(
          deviceId: 0,
          name: 'XaraWide',
          data: false,
          store: true,
        );
        client.dispatch(
          deviceId: radio,
          name: 'LockState',
          data: null,
          store: true,
        );
        client.dispatch(
          deviceId: radio,
          name: 'Channels',
          data: <Map<String, dynamic>>[
            RadioChannelInfo(channelId: 14, name: 'Data').toJson(),
            RadioChannelInfo(channelId: 29, name: 'APRS').toJson(),
          ],
        );
        client.dispatch(
          deviceId: radio,
          name: 'HtStatus',
          data: <String, Object?>{'currChId': 29, 'currRegion': 0},
        );

        final SoftwareModem modem = SoftwareModem();
        modem.init();
        client.dispatch(
          deviceId: 0,
          name: 'SetSoftwareModemMode',
          data: wide ? 'None' : 'XARA',
          store: false,
        );
        if (wide) {
          client.dispatch(
            deviceId: radio,
            name: 'LockState',
            data: {
              'isLocked': true,
              'usage': 'Terminal',
              'modem': 'XARA',
              'xaraWide': true,
            },
            store: true,
          );
        }

        final List<Map<String, Object?>> peerEvents = <Map<String, Object?>>[];
        final List<int> peerData = <int>[];
        late final Playout toPeer, toRadio;
        final XaraModem peer = XaraModem(
          config: XaraModemConfig(
            callsign: 'N1CALL',
            txLatencyMs: 400,
            wide: wide,
          ),
          onTransmit: (Uint8List pcm) => toRadio.add(pcm),
          onEvent: (Map<String, Object?> e) {
            if (e['evt'] == 'data') {
              peerData.addAll(e['data'] as Uint8List);
            } else {
              peerEvents.add(e);
            }
          },
        );
        toPeer = Playout(250, (Uint8List c) => peer.pushRx(c, 0, c.length));
        toRadio = Playout(250, (Uint8List c) {
          client.dispatch(
            deviceId: radio,
            name: 'AudioDataAvailable',
            data: <String, Object?>{
              'data': c,
              'offset': 0,
              'length': c.length,
              'channelName': 'Data',
              'transmit': false,
            },
            store: false,
          );
        });
        final Timer clock = Timer.periodic(const Duration(milliseconds: 20), (
          _,
        ) {
          toPeer.tick();
          toRadio.tick();
        });

        client.subscribe(
          deviceId: radio,
          name: 'TransmitVoicePCM',
          callback: (int d, String n, Object? data) =>
              toPeer.add((data! as Map)['Data'] as Uint8List),
        );
        final List<Map<Object?, Object?>> events = <Map<Object?, Object?>>[];
        final List<int> radioData = <int>[];
        final List<TncDataFragment> frames = <TncDataFragment>[];
        Map<Object?, Object?>? linkState;
        client.subscribe(
          deviceId: radio,
          name: 'XaraEvent',
          callback: (int d, String n, Object? e) => events.add(e! as Map),
        );
        client.subscribe(
          deviceId: radio,
          name: 'XaraLinkState',
          callback: (int d, String n, Object? e) => linkState = e! as Map,
        );
        client.subscribe(
          deviceId: radio,
          name: 'XaraDataReceived',
          callback: (int d, String n, Object? e) =>
              radioData.addAll(e! as Uint8List),
        );
        client.subscribe(
          deviceId: DataBroker.allDevices,
          name: 'DataFrame',
          callback: (int d, String n, Object? f) {
            if (f is TncDataFragment && f.incoming) frames.add(f);
          },
        );

        try {
          client.dispatch(
            deviceId: radio,
            name: 'XaraConnect',
            data: <String, Object?>{'Remote': 'N1CALL'},
            store: false,
          );
          bool connected(List<Map<Object?, Object?>> ev) =>
              ev.any((e) => e['evt'] == 'connected');
          expect(
            await waitFor(
              () => connected(events) && connected(peerEvents),
              const Duration(seconds: 40),
            ),
            isTrue,
            reason: 'radio $events\npeer $peerEvents',
          );
          expect(linkState?['peer'], 'N1CALL');
          expect(
            events.firstWhere((e) => e['evt'] == 'connected')['wide'],
            wide,
          );
          if (wide) {
            client.dispatch(
              deviceId: 0,
              name: 'SetXaraWide',
              data: false,
              store: false,
            );
            expect(client.getValue<bool>(0, 'XaraWide'), isFalse);
          }

          final Uint8List up = Uint8List.fromList(
            List<int>.generate(600, (i) => (i * 7 + 3) & 0xFF),
          );
          final Uint8List down = Uint8List.fromList(
            'Hello from the peer station\r'.codeUnits,
          );
          client.dispatch(
            deviceId: radio,
            name: 'XaraSend',
            data: up,
            store: false,
          );
          peer.send(down);
          expect(
            await waitFor(
              () =>
                  peerData.length >= up.length &&
                  radioData.length >= down.length,
              const Duration(seconds: 60),
            ),
            isTrue,
            reason:
                'peer got ${peerData.length}, radio got ${radioData.length}',
          );
          expect(peerData, up);
          expect(radioData, down);

          client.dispatch(
            deviceId: radio,
            name: 'XaraDisconnect',
            data: null,
            store: false,
          );
          bool closed(List<Map<Object?, Object?>> ev) =>
              ev.any((e) => e['evt'] == 'disconnected');
          expect(
            await waitFor(
              () => closed(events) && closed(peerEvents),
              const Duration(seconds: 40),
            ),
            isTrue,
          );
          expect(
            await waitFor(
              () => !toPeer.busy && !toRadio.busy,
              const Duration(seconds: 10),
            ),
            isTrue,
          );

          // Unconnected AX.25 UI frame from the peer reaches the normal packet path.
          final Uint8List ui = Uint8List.fromList(<int>[
            ...'APZ001'.codeUnits.map((c) => c << 1), 0x60, //
            ...'N1CALL'.codeUnits.map((c) => c << 1), 0x61,
            0x03, 0xF0, ...'>XARA test beacon'.codeUnits,
          ]);
          peer.kiss(ui);
          expect(
            await waitFor(() => frames.isNotEmpty, const Duration(seconds: 20)),
            isTrue,
          );
          expect(frames.first.data, ui);
          expect(frames.first.encoding, FragmentEncodingType.softwareXara);
          expect(frames.first.radioDeviceId, radio);
        } finally {
          clock.cancel();
          peer.dispose();
          modem.dispose();
          client.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
