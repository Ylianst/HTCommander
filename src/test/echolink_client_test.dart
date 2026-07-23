/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// echolink_client_test.dart - Orchestration tests for the device-200 EchoLink
// client, using a fake network + fake scheduler + the real Data Broker
// (standalone role).
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/echolink_audio.dart';
import 'package:htcommander/echolink/echolink_client.dart';
import 'package:htcommander/echolink/echolink_data_packet.dart';
import 'package:htcommander/echolink/echolink_directory.dart';
import 'package:htcommander/echolink/echolink_network.dart';
import 'package:htcommander/echolink/echolink_qso.dart';
import 'package:htcommander/echolink/echolink_station.dart';
import 'package:htcommander/echolink/rtcp_packet.dart';
import 'package:htcommander/services/data_broker.dart';

class _FakeNetwork implements EchoLinkNetwork {
  final StreamController<EchoLinkDatagram> audio =
      StreamController<EchoLinkDatagram>.broadcast();
  final StreamController<EchoLinkDatagram> control =
      StreamController<EchoLinkDatagram>.broadcast();

  final List<(String, Uint8List)> sentAudio = <(String, Uint8List)>[];
  final List<(String, Uint8List)> sentControl = <(String, Uint8List)>[];
  final List<Uint8List> directoryRequests = <Uint8List>[];

  Uint8List listResponse = Uint8List(0);

  @override
  Stream<EchoLinkDatagram> get audioIn => audio.stream;
  @override
  Stream<EchoLinkDatagram> get controlIn => control.stream;

  @override
  Future<void> open() async {}

  @override
  void sendAudio(String host, Uint8List data) => sentAudio.add((host, data));
  @override
  void sendControl(String host, Uint8List data) =>
      sentControl.add((host, data));

  @override
  Future<Uint8List> directoryExchange(
      List<String> servers, Uint8List request,
      {int? maxBytes}) async {
    directoryRequests.add(request);
    // 'l' = login ack (short), 's' = station list.
    if (request.isNotEmpty && request[0] == 0x73) return listResponse;
    return Uint8List.fromList(latin1.encode('OK2.0\r'));
  }

  @override
  Future<void> close() async {
    await audio.close();
    await control.close();
  }
}

class _FakeScheduler implements Scheduler {
  final List<void Function()> periodics = <void Function()>[];
  final List<void Function()> oneShots = <void Function()>[];

  @override
  CancelTimer periodic(Duration d, void Function() cb) {
    periodics.add(cb);
    return () => periodics.remove(cb);
  }

  @override
  CancelTimer oneShot(Duration d, void Function() cb) {
    oneShots.add(cb);
    return () => oneShots.remove(cb);
  }

  void fireOneShots() {
    for (final void Function() cb in List<void Function()>.of(oneShots)) {
      cb();
    }
  }
}

Uint8List _stationList(List<String> lines) =>
    Uint8List.fromList(latin1.encode(lines.join('\n')));

/// Lets pending broadcast-stream events be delivered.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeNetwork net;
  late _FakeScheduler sched;
  late EchoLinkClient client;

  setUp(() {
    DataBroker.clearDevice(echoLinkDeviceId);
    net = _FakeNetwork();
    sched = _FakeScheduler();
    client = EchoLinkClient(
      localCallsign: 'N0CALL',
      localPassword: 'secret',
      localName: 'Tester',
      localInfo: 'HTCommander',
      network: net,
      scheduler: sched,
    );
  });

  tearDown(() async {
    await client.close();
    DataBroker.clearDevice(echoLinkDeviceId);
  });

  test('open registers device 200 on the broker', () async {
    await client.open();
    expect(DataBroker.getValue<String>(echoLinkDeviceId, 'FriendlyName'),
        'EchoLink');
    expect(DataBroker.getValue<String>(echoLinkDeviceId, 'State'),
        'Disconnected');
    expect(client.state, EchoLinkClientState.offline);
  });

  test('goOnline sends a login command and moves online', () async {
    await client.open();
    await client.goOnline();
    expect(net.directoryRequests, isNotEmpty);
    expect(net.directoryRequests.first[0], 0x6c); // 'l'
    expect(client.state, EchoLinkClientState.online);
    expect(DataBroker.getValue<String>(echoLinkDeviceId, 'State'), 'Online');
  });

  test('refreshStations parses and publishes the station list', () async {
    await client.open();
    net.listResponse = _stationList(<String>[
      '@@@',
      '2',
      'W1AW', 'Newington, CT      [ON 10:00]', '1234', '1.2.3.4',
      'K6IRF-R', 'Claremont, CA      [ON 13:49]', '13887', '5.6.7.8',
      '+++',
    ]);

    DirectoryListing? got;
    client.onStations = (DirectoryListing l) => got = l;
    final DirectoryListing listing = await client.refreshStations();

    expect(net.directoryRequests.last[0], 0x73); // 's'
    expect(listing.stations.single.callsign, 'W1AW');
    expect(listing.repeaters.single.callsign, 'K6IRF-R');
    expect(got, isNotNull);

    final Object? published =
        DataBroker.getValue<Object?>(echoLinkDeviceId, 'StationList');
    expect(published, isA<List<dynamic>>());
    expect((published as List<dynamic>).length, 2);
  });

  test('connectTo performs the handshake and reports connected', () async {
    await client.open();
    const StationData station = StationData(
        callsign: 'W1AW', ip: '10.0.0.5', id: 1234, status: StationStatus.online);

    client.connectTo(station);
    expect(client.state, EchoLinkClientState.connecting);
    expect(net.sentControl.length, 1);
    expect(isSdesPacket(net.sentControl.single.$2), isTrue);
    expect(net.sentControl.single.$1, '10.0.0.5');
    expect(sched.periodics.length, 1); // keep-alive armed
    expect(sched.oneShots.length, 1); // timeout armed

    // Remote answers with SDES from the station's address.
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW', name: 'Hiram')));
    await _pump();

    expect(client.state, EchoLinkClientState.inQso);
    expect(DataBroker.getValue<String>(echoLinkDeviceId, 'State'), 'Connected');
    final Object? cs =
        DataBroker.getValue<Object?>(echoLinkDeviceId, 'ConnectedStation');
    expect(cs, isA<Map<dynamic, dynamic>>());
    expect((cs as Map<dynamic, dynamic>)['Callsign'], 'W1AW');
  });

  test('incoming voice packets are decoded to 8 kHz audio', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();

    Int16List? audio;
    client.onAudio = (Int16List pcm) => audio = pcm;

    final EchoLinkAudioEncoder enc = EchoLinkAudioEncoder();
    net.audio.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkAudioPort, enc.encodePacket(Int16List(640))));
    await _pump();

    expect(audio, isNotNull);
    expect(audio!.length, 640);
  });

  test('packets from a different host are ignored', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);

    // SDES from a stranger must not complete the handshake.
    net.control.add(EchoLinkDatagram(
        '9.9.9.9', echoLinkControlPort, buildSdes(callsign: 'BADX')));
    await _pump();
    expect(client.state, EchoLinkClientState.connecting);
  });

  test('sendAudio emits 640-sample voice packets when connected', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();
    net.sentAudio.clear();

    client.sendAudio(Int16List(640 * 2)); // exactly two packets
    expect(net.sentAudio.length, 2);
    expect(net.sentAudio.first.$1, '10.0.0.5');
  });

  test('flushAudio emits a final padded packet for the trailing partial buffer',
      () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();
    net.sentAudio.clear();

    // One full packet plus a partial remainder that would otherwise be dropped.
    client.sendAudio(Int16List(640 + 100));
    expect(net.sentAudio.length, 1);

    client.flushAudio();
    expect(net.sentAudio.length, 2);
    expect(net.sentAudio.last.$1, '10.0.0.5');

    // A second flush with nothing buffered is a no-op.
    client.flushAudio();
    expect(net.sentAudio.length, 2);
  });

  test('sendChat emits a chat packet over the audio port when connected',
      () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();
    net.sentAudio.clear();

    client.sendChat('Hello there');
    expect(net.sentAudio.length, 1);
    expect(net.sentAudio.single.$1, '10.0.0.5');
    expect(classifyAudioPortPacket(net.sentAudio.single.$2),
        EchoLinkAudioPortPacket.chat);
    final EchoLinkChat parsed = parseChatPacket(net.sentAudio.single.$2);
    expect(parsed.message, 'Hello there');
  });

  test('incoming chat packets fire the onChat callback', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();

    EchoLinkChat? chat;
    client.onChat = (EchoLinkChat c) => chat = c;

    net.audio.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkAudioPort, buildChatPacket('W1AW', 'Hi HTC')));
    await _pump();

    expect(chat, isNotNull);
    expect(chat!.callsign, 'W1AW');
    expect(chat!.message, 'Hi HTC');
  });

  test('disconnect sends BYE and returns to online', () async {
    await client.open();
    await client.goOnline();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();
    net.sentControl.clear();

    client.disconnect();
    expect(net.sentControl.length, 1);
    expect(isByePacket(net.sentControl.single.$2), isTrue);
    expect(client.state, EchoLinkClientState.online);
    expect(DataBroker.getValue<Object?>(echoLinkDeviceId, 'ConnectedStation'),
        isNull);
  });

  test('receiving BYE drops the connection', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();

    net.control.add(
        EchoLinkDatagram('10.0.0.5', echoLinkControlPort, buildBye()));
    await _pump();
    expect(client.state, EchoLinkClientState.offline);
  });

  test('connection timeout drops the QSO', () async {
    await client.open();
    const StationData station = StationData(callsign: 'W1AW', ip: '10.0.0.5');
    client.connectTo(station);
    net.control.add(EchoLinkDatagram(
        '10.0.0.5', echoLinkControlPort, buildSdes(callsign: 'W1AW')));
    await _pump();
    expect(client.state, EchoLinkClientState.inQso);

    sched.fireOneShots(); // simulate 50 s inactivity timeout
    expect(client.state, EchoLinkClientState.offline);
  });
}
