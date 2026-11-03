/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/ax25_session.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

Future<void> waitFor(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

void main() {
  const deviceId = 409;
  late DataBrokerClient broker;
  late Radio radio;
  late Bbs bbs;
  late List<TncDataFragment> sent;
  late List<TncDataFragment> software;
  final originalRelayFactory = Bbs.relayFactory;

  void receive(int type, FragmentEncodingType encoding, {bool command = true}) {
    final packet = AX25Packet(
      addresses: [
        AX25Address.getAddress('N0CALL')!,
        AX25Address.getAddress('N1ABC')!,
      ],
      type: type,
      command: command,
      pollFinal: true,
    );
    broker.dispatch(
      deviceId: deviceId,
      name: 'UniqueDataFrame',
      data: TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: packet.toByteArray(),
        channelId: 14,
        regionId: 0,
        channelName: 'Data',
        incoming: true,
        radioDeviceId: deviceId,
        encoding: encoding,
        frameType: FragmentFrameType.ax25,
        usage: 'BBS',
      ),
      store: false,
    );
  }

  setUp(() {
    broker = DataBrokerClient();
    for (final entry in <String, Object>{
      'CallSign': 'N0CALL',
      'StationId': 0,
      'AllowTransmit': 1,
      'SoftwareModemMode': 'XARA',
      'AprsSoftwareModemMode': 'AFSK1200',
      'WinlinkPassword': '',
    }.entries) {
      broker.dispatch(deviceId: 0, name: entry.key, data: entry.value);
    }
    broker.dispatch(deviceId: deviceId, name: 'AudioState', data: true);
    broker.dispatch(
      deviceId: deviceId,
      name: 'Channels',
      data: [
        RadioChannelInfo(channelId: 14, name: 'Data').toJson(),
        RadioChannelInfo(channelId: 29, name: 'APRS').toJson(),
      ],
    );
    broker.dispatch(
      deviceId: deviceId,
      name: 'HtStatus',
      data: {'currChId': 14, 'currRegion': 0},
    );
    sent = [];
    software = [];
    broker.subscribe(
      deviceId: deviceId,
      name: 'DataFrame',
      callback: (_, _, data) {
        if (data is TncDataFragment && !data.incoming) sent.add(data);
      },
    );
    broker.subscribe(
      deviceId: deviceId,
      name: 'SoftModemTransmitPacket',
      callback: (_, _, data) => software.add(data! as TncDataFragment),
    );
    radio = Radio(deviceId: deviceId, macAddress: 'test');
    Bbs.relayFactory = (id, client) => WinlinkGatewayRelay(
      id,
      client,
      server: '127.0.0.1',
      port: 1,
      useTls: false,
    );
    bbs = Bbs(deviceId)..enabled = true;
  });

  tearDown(() {
    bbs.dispose();
    radio.dispose();
    broker.dispose();
    Bbs.relayFactory = originalRelayFactory;
    DataBroker.clearDevice(deviceId);
    DataBroker.clearDevice(0);
  });

  for (final encoding in [
    FragmentEncodingType.hardwareAfsk1200,
    FragmentEncodingType.softwareAfsk1200,
    FragmentEncodingType.softwarePsk2400,
    FragmentEncodingType.softwareDart,
    FragmentEncodingType.softwareXara,
  ]) {
    test('BBS keeps $encoding for handshake, banner and disconnect', () async {
      receive(FrameType.uFrameSabm, encoding);
      expect(bbs.session!.currentState, AX25ConnectionState.connected);
      expect(AX25Packet.decode(sent.first)!.type, FrameType.uFrameUa);
      await waitFor(
        () => sent.any(
          (f) =>
              AX25Packet.decode(f)?.dataStr?.contains('[M] for menu') == true,
        ),
      );

      receive(FrameType.sFrameRr, FragmentEncodingType.unknown);
      bbs.session!.disconnect();
      expect(AX25Packet.decode(sent.last)!.type, FrameType.uFrameDisc);
      expect(sent.map((f) => f.encoding), everyElement(encoding));
      if (encoding == FragmentEncodingType.hardwareAfsk1200) {
        expect(
          software,
          isEmpty,
          reason: '1200 packet must not go through XARA',
        );
      } else {
        expect(software.length, sent.length);
        expect(software.map((f) => f.encoding), everyElement(encoding));
      }
      expect(broker.getValue<String>(0, 'SoftwareModemMode'), 'XARA');
    });
  }

  test('a new caller chooses its own encoding; outgoing uses defaults', () {
    receive(FrameType.uFrameSabm, FragmentEncodingType.hardwareAfsk1200);
    receive(FrameType.uFrameDisc, FragmentEncodingType.hardwareAfsk1200);
    expect(sent.last.encoding, FragmentEncodingType.hardwareAfsk1200);
    expect(bbs.activeLink, isNull);

    receive(FrameType.uFrameSabm, FragmentEncodingType.softwareXara);
    expect(sent.last.encoding, FragmentEncodingType.softwareXara);
    receive(FrameType.uFrameDisc, FragmentEncodingType.softwareXara);

    receive(FrameType.uFrameSabm, FragmentEncodingType.hardwareAfsk1200);
    receive(FrameType.uFrameDisc, FragmentEncodingType.hardwareAfsk1200);
    expect(
      bbs.session!.connect([
        AX25Address.getAddress('N2ABC')!,
        AX25Address.getAddress('N0CALL')!,
      ]),
      isTrue,
    );
    expect(sent.last.encoding, FragmentEncodingType.softwareXara);
  });

  test('stray DISC and command replies use the received encoding', () {
    receive(FrameType.uFrameDisc, FragmentEncodingType.hardwareAfsk1200);
    expect(AX25Packet.decode(sent.last)!.type, FrameType.uFrameUa);
    expect(sent.last.encoding, FragmentEncodingType.hardwareAfsk1200);
    receive(FrameType.sFrameRr, FragmentEncodingType.hardwareAfsk1200);
    expect(AX25Packet.decode(sent.last)!.type, FrameType.uFrameDm);
    expect(sent.last.encoding, FragmentEncodingType.hardwareAfsk1200);
    expect(software, isEmpty);
  });

  test('ordinary outgoing packets still use the selected XARA modem', () {
    broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: AX25Packet.ui([
          AX25Address.getAddress('APRS')!,
          AX25Address.getAddress('N0CALL')!,
        ], 'test'),
      ),
      store: false,
    );
    expect(software.single.encoding, FragmentEncodingType.softwareXara);
  });

  test('software replies do not fall back to hardware when audio is off', () {
    broker.dispatch(deviceId: deviceId, name: 'AudioState', data: false);
    receive(FrameType.uFrameSabm, FragmentEncodingType.softwarePsk2400);
    expect(sent, isEmpty);
    expect(software, isEmpty);
  });

  test(
    'software AFSK reply uses the AFSK pipeline, not general XARA',
    () async {
      final modem = SoftwareModem()..init();
      addTearDown(modem.dispose);
      modem.setMode(SoftwareModemMode.xara, persist: false);
      modem.setAprsMode(SoftwareModemMode.afsk1200, persist: false);
      modem.registerExternalSource(
        sourceId: 410,
        mode: SoftwareModemMode.afsk1200,
        fecEnabled: false,
        attributeDeviceId: 410,
      );
      final decoded = <TncDataFragment>[];
      broker.subscribe(
        deviceId: 410,
        name: 'DataFrame',
        callback: (_, _, data) => decoded.add(data! as TncDataFragment),
      );
      broker.subscribe(
        deviceId: deviceId,
        name: 'TransmitVoicePCM',
        callback: (_, _, data) {
          final pcm = (data! as Map)['Data'] as Uint8List;
          modem.feedExternalSamples(410, pcm);
        },
      );
      receive(FrameType.uFrameSabm, FragmentEncodingType.softwareAfsk1200);
      await waitFor(
        () => decoded.any(
          (f) => AX25Packet.decode(f)?.type == FrameType.uFrameUa,
        ),
      );
      expect(decoded.first.encoding, FragmentEncodingType.softwareAfsk1200);
    },
  );
}
