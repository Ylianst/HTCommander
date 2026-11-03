/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/ax25_session.dart';
import 'package:htcommander/radio/gaia_protocol.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

class _PendingRelay extends WinlinkGatewayRelay {
  final result = Completer<bool>();
  bool disposed = false;

  _PendingRelay(super.deviceId, super.broker);

  @override
  Future<bool> connectAsync(String stationCallsign, {int timeoutMs = 15000}) =>
      result.future;

  @override
  bool get isConnected => !disposed;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Transport extends MockRadioTransport {
  @override
  Future<void> disconnect() async {}
}

void main() {
  const id = 420;
  late DataBrokerClient broker;
  late Bbs bbs;
  late List<_PendingRelay> relays;
  late List<String> commands;
  final originalFactory = Bbs.relayFactory;

  void receiveSabm() {
    final packet = AX25Packet(
      addresses: [
        AX25Address.getAddress('N0CALL')!,
        AX25Address.getAddress('N1ABC')!,
      ],
      type: FrameType.uFrameSabm,
      command: true,
      pollFinal: true,
    );
    broker.dispatch(
      deviceId: id,
      name: 'UniqueDataFrame',
      data: TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: packet.toByteArray(),
        channelId: 14,
        regionId: 0,
        incoming: true,
        radioDeviceId: id,
        encoding: FragmentEncodingType.hardwareAfsk1200,
      ),
      store: false,
    );
  }

  setUp(() {
    broker = DataBrokerClient();
    broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    broker.dispatch(deviceId: 0, name: 'StationId', data: 0);
    broker.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
    broker.dispatch(deviceId: 0, name: 'SoftwareModemMode', data: 'None');
    relays = [];
    Bbs.relayFactory = (deviceId, client) {
      final relay = _PendingRelay(deviceId, client);
      relays.add(relay);
      return relay;
    };
    commands = [];
    broker.subscribeMultiple(
      deviceId: id,
      names: [
        'TransmitDataFrame',
        'XaraSend',
        'XaraDisconnect',
        'XaraAbort',
        'CancelDataTransmit',
        'SetUnlock',
      ],
      callback: (_, name, _) => commands.add(name),
    );
    bbs = Bbs(id)..enabled = true;
  });

  tearDown(() {
    bbs.dispose();
    for (final relay in relays) {
      if (!relay.result.isCompleted) relay.result.complete(false);
    }
    Bbs.relayFactory = originalFactory;
    broker.dispose();
    DataBroker.clearDevice(id);
    DataBroker.clearDevice(0);
  });

  test(
    'disabling AX.25 stops timers, pending relay and incoming replies',
    () async {
      final session = bbs.session!..frackSeconds = 1;
      receiveSabm();
      expect(session.currentState, AX25ConnectionState.connected);
      session.sendString('queued data');
      expect(commands, contains('TransmitDataFrame'));
      bbs.enabled = false;
      final count = commands.length;

      expect(session.currentState, AX25ConnectionState.disconnected);
      expect(session.sendBufferLength, 0);
      expect(bbs.session, isNull);
      expect(bbs.activeLink, isNull);
      expect(relays.single.disposed, isTrue);
      expect(commands.last, 'CancelDataTransmit');
      receiveSabm();
      relays.single.result.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(commands.length, count, reason: 'disabled BBS transmitted again');

      bbs.enabled = true;
      expect(bbs.session, isNot(same(session)));
      receiveSabm();
      expect(bbs.activeLink, isNotNull);
      expect(relays.length, 2);
    },
  );

  test(
    'disabling XARA drops the link without a disconnect or late banner',
    () async {
      broker.dispatch(
        deviceId: id,
        name: 'XaraEvent',
        data: {'evt': 'connected', 'caller': 'N1ABC', 'incoming': true},
        store: false,
      );
      final link = bbs.activeLink!;
      bbs.enabled = false;
      expect(link.isConnected, isFalse);
      expect(link.sessionState, isEmpty);
      expect(relays.single.disposed, isTrue);
      expect(commands, ['CancelDataTransmit']);
      expect(broker.getValue<bool>(id, 'BbsEnabled'), isFalse);

      bbs.enabled = true;
      relays.single.result.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(commands, ['CancelDataTransmit']);
      expect(bbs.activeLink, isNull);
    },
  );

  test(
    'disabling clears hardware fragments and handles a late ACK safely',
    () async {
      final radio = Radio(deviceId: id, macAddress: 'test');
      final transport = _Transport();
      await radio.connect(transport);
      addTearDown(() async {
        radio.dispose();
        await transport.dispose();
      });
      radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
      receiveSabm();
      bbs.session!.sendString('queued BBS data');
      await Future<void>.delayed(Duration.zero);
      expect(radio.transmitQueueLength, greaterThan(1));
      bbs.enabled = false;
      expect(radio.transmitQueueLength, 0);

      radio.transmitTncData(Uint8List(20), 'Data');
      expect(radio.transmitQueueLength, 1);
      final ack = GaiaProtocol.encode(
        GaiaProtocol.buildRawCommand(
          RadioCommandGroup.basic.value,
          RadioBasicCommand.htSendData.value | 0x8000,
          Uint8List.fromList([0]),
        ),
      );
      transport.simulateReceive(ack);
      await Future<void>.delayed(Duration.zero);
      expect(
        radio.transmitQueueLength,
        1,
        reason: 'old ACK discarded fresh data',
      );
      transport.simulateReceive(ack);
      await Future<void>.delayed(Duration.zero);
      expect(radio.transmitQueueLength, 0);
    },
  );

  test('RemoveBbs cancels before unlocking and disposal is idempotent', () {
    bbs.dispose();
    commands.clear();
    final handler = BbsHandler();
    handler.init();
    addTearDown(handler.dispose);
    broker.dispatch(
      deviceId: 1,
      name: 'CreateBbs',
      data: CreateBbsData(radioDeviceId: id, channelId: 14, regionId: 0),
      store: false,
    );
    final managed = handler.getBbsInstance(id)!;
    receiveSabm();
    commands.clear();
    broker.dispatch(
      deviceId: 1,
      name: 'RemoveBbs',
      data: RemoveBbsData(radioDeviceId: id),
      store: false,
    );
    expect(commands, ['CancelDataTransmit', 'SetUnlock']);
    expect(handler.getBbsInstance(id), isNull);
    expect(managed.session, isNull);
    expect(relays.single.disposed, isTrue);
    managed.dispose();
    expect(commands, ['CancelDataTransmit', 'SetUnlock']);
  });

  test('disabling during the connect notification cannot start a relay', () {
    broker.subscribe(
      deviceId: 0,
      name: 'BbsControlMessage',
      callback: (_, _, data) {
        if ((data! as BbsControlMessageData).message.startsWith('Connected to')) {
          bbs.enabled = false;
        }
      },
    );
    receiveSabm();
    expect(bbs.session, isNull);
    expect(bbs.activeLink, isNull);
    expect(relays, isEmpty);
    expect(commands.last, 'CancelDataTransmit');
  });
}
