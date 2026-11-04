import 'dart:typed_data';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/debug_tab.dart';
import 'package:htcommander/widgets/satellite_tab.dart';

class _RecordingTransport extends MockRadioTransport {
  final sent = <Uint8List>[];

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> send(Uint8List data) async {
    sent.add(Uint8List.fromList(data));
    return true;
  }
}

void main() {
  const info = RadioSatelliteInfo(
    name: 'ISS',
    azimuthDeg: 90,
    elevationDeg: 45,
    rangeKm: 500,
    altitudeKm: 400,
    secondsToNextPass: 0,
  );
  const tuning = RadioFreqModePar(rxFreq: 145800000, txFreq: 0);
  late Radio radio;
  late _RecordingTransport transport;
  late DataBrokerClient broker;

  void disable(String name, bool value) {
    broker.dispatch(deviceId: 0, name: name, data: value);
  }

  void lock({String usage = 'Satellite'}) {
    radio.settings = RadioSettings.fromBytes(Uint8List(64));
    radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
    broker.dispatch(
      deviceId: radio.deviceId,
      name: 'SetLock',
      data: SetLockData(usage: usage),
    );
  }

  void update({
    int rx = 145800000,
    int tx = 0,
    double? tone,
    int noradId = 25544,
    int usageIndex = 0,
  }) => broker.dispatch(
    deviceId: radio.deviceId,
    name: 'SatelliteTrackUpdate',
    data: SatelliteTrackParams(
      noradId: noradId,
      usageIndex: usageIndex,
      name: 'ISS',
      rxFreqHz: rx,
      txFreqHz: tx,
      txCtcssHz: tone,
      azimuthDeg: 90,
      elevationDeg: 45,
      rangeKm: 500,
      altitudeKm: 400,
      secondsToNextPass: 0,
    ),
  );

  List<Uint8List> tuningFrames() =>
      transport.sent.where((frame) => frame[7] == 35).toList();

  void settle({int tx = 0}) {
    lock();
    update(tx: tx);
    update(tx: tx);
    update(tx: tx);
    transport.sent.clear();
  }

  void audio(String name, {bool transmit = false, int? deviceId}) =>
      broker.dispatch(
        deviceId: deviceId ?? radio.deviceId,
        name: name,
        data: {'transmit': transmit},
        store: false,
      );

  setUp(() async {
    broker = DataBrokerClient();
    transport = _RecordingTransport();
    radio = Radio(deviceId: 9300, macAddress: 'test');
    await radio.connect(transport);
    transport.sent.clear();
  });

  tearDown(() async {
    radio.dispose();
    broker.dispose();
    await transport.dispose();
    DataBroker.clearDevice(0);
    DataBroker.clearDevice(9300);
  });

  test('commands are enabled when debug settings are absent', () {
    DataBroker.clearDevice(0);
    radio.setSatelliteInfo(info);
    radio.freqModeSetPar(tuning);
    expect(transport.sent.length, 2);
  });

  for (final disableInfo in [false, true]) {
    for (final disableFreq in [false, true]) {
      test(
        'legacy debug settings cannot suppress commands: info=$disableInfo freq=$disableFreq',
        () {
          disable('DebugDisableSetSatelliteInfo', disableInfo);
          disable('DebugDisableFreqModeSetPar', disableFreq);
          radio.setSatelliteInfo(info);
          radio.freqModeSetPar(tuning);
          // Classic GAIA frames carry the command ID at bytes 6 and 7.
          expect(
            transport.sent.map((frame) => (frame[6] << 8) | frame[7]).toList(),
            [77, 35],
          );
        },
      );
    }
  }

  test('legacy debug settings cannot suppress teardown', () {
    disable('DebugDisableSetSatelliteInfo', true);
    disable('DebugDisableFreqModeSetPar', true);
    radio.setSatelliteInfo(info);
    radio.freqModeSetPar(tuning);
    radio.stopFreqMode();
    expect(transport.sent.map((frame) => (frame[6] << 8) | frame[7]).toList(), [
      77,
      35,
      35,
    ]);
    expect(transport.sent.last.sublist(8), everyElement(0));
  });

  test('teardown repeats the all-zero stop like the manufacturer app', () async {
    radio.freqModeSetPar(tuning);
    radio.stopFreqMode();
    expect(transport.sent.length, 2);
    await Future<void>.delayed(
      Radio.freqModeStopRepeatDelay + const Duration(milliseconds: 50),
    );
    expect(transport.sent.map((frame) => (frame[6] << 8) | frame[7]).toList(), [
      35,
      35,
      35,
    ]);
    expect(transport.sent[1].sublist(8), everyElement(0));
    expect(transport.sent[2].sublist(8), everyElement(0));
  });

  test('a new tuning cancels the pending teardown repeat', () async {
    radio.stopFreqMode();
    radio.freqModeSetPar(tuning);
    await Future<void>.delayed(
      Radio.freqModeStopRepeatDelay + const Duration(milliseconds: 50),
    );
    expect(transport.sent.length, 2);
    expect(transport.sent.last.sublist(8), isNot(everyElement(0)));
  });

  test('leaving satellite mode replaces the stale VFO channel id', () async {
    Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);
    Future<void> rx(String s) async {
      transport.simulateReceive(hex(s));
      await Future<void>.delayed(Duration.zero);
    }

    // Settings (channel A from the user's debug log) and the satellite-mode HT
    // status from the manufacturer capture, which reports channel id 254.
    await rx(
      'FF01001700020009060F01A6061A103CA0A100000000000078000000000000',
    );
    await rx('FF01000500020009' '01c4e3003c');
    expect(radio.htStatus!.currChId, 254);
    await rx('FF01000F00020009' '0e1a18364708b3a8c400001a2c8a40');

    radio.stopFreqMode();
    await rx('FF01000F00020009' '0e081b320000000000000000008000');
    final channelA = radio.settings!.channelA;
    expect(channelA, lessThan(254));
    expect(radio.htStatus!.currChId, channelA);

    // Changing channel on the radio only pushes htSettingsChanged.
    await rx(
      'FF0100170002000906FF01A6061A103CA0A100000000000078000000000000',
    );
    expect(radio.settings!.channelA, isNot(channelA));
    expect(radio.htStatus!.currChId, radio.settings!.channelA);

    // A stale GET_HT_STATUS reply is corrected too.
    await rx('FF01000500028014' '00c4e3003c');
    expect(radio.htStatus!.currChId, radio.settings!.channelA);

    // A real channel report ends the correction, so a later 254+ (e.g. NOAA
    // weather) is passed through untouched.
    await rx('FF01000500020009' '01c4330000');
    expect(radio.htStatus!.currChId, 3);
    await rx('FF01000500020009' '01c4e3003c');
    expect(radio.htStatus!.currChId, 254);
  });

  test('legacy debug settings cannot suppress tracking or entry flags', () {
    radio.settings = RadioSettings.fromBytes(Uint8List(64));
    radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
    broker.dispatch(
      deviceId: radio.deviceId,
      name: 'SetLock',
      data: SetLockData(usage: 'Satellite'),
    );
    void update() => broker.dispatch(
      deviceId: radio.deviceId,
      name: 'SatelliteTrackUpdate',
      data: const SatelliteTrackParams(
        name: 'ISS',
        rxFreqHz: 145800000,
        txFreqHz: 0,
        txCtcssHz: null,
        azimuthDeg: 90,
        elevationDeg: 45,
        rangeKm: 500,
        altitudeKm: 400,
        secondsToNextPass: 0,
      ),
    );

    disable('DebugDisableSetSatelliteInfo', true);
    disable('DebugDisableFreqModeSetPar', true);
    update();
    update();
    update();
    expect(transport.sent.map((frame) => frame[7]).toList(), [
      77,
      35,
      77,
      35,
      77,
      35,
    ]);
    expect(
      tuningFrames().map((frame) => (frame[20] << 8) | frame[21]).toList(),
      [0x0A03, 0x0A03, 0x0A00],
    );
  });

  test('default threshold compares accumulated RX drift against last sent', () {
    settle();
    update();
    update(rx: 145800499);
    update(rx: 145800999);
    expect(tuningFrames(), isEmpty);
    expect(
      transport.sent.length,
      3,
    ); // Display metadata still updates every tick.
    update(rx: 145801000);
    expect(tuningFrames().length, 1);
    update(rx: 145800001);
    expect(tuningFrames().length, 1);
    update(rx: 145800000);
    expect(tuningFrames().length, 2);
  });

  test('TX drift also triggers a retune at the threshold', () {
    settle(tx: 437800000);
    update(tx: 437800999);
    expect(tuningFrames(), isEmpty);
    update(tx: 437801000);
    expect(tuningFrames().length, 1);
  });

  test(
    'configured threshold and zero threshold still skip identical tuning',
    () {
      broker.dispatch(
        deviceId: 0,
        name: 'SatelliteDopplerThresholdHz',
        data: 500,
      );
      settle();
      update(rx: 145800499);
      expect(tuningFrames(), isEmpty);
      update(rx: 145800500);
      expect(tuningFrames().length, 1);
      broker.dispatch(
        deviceId: 0,
        name: 'SatelliteDopplerThresholdHz',
        data: 0,
      );
      update(rx: 145800500);
      expect(tuningFrames().length, 1);
      update(rx: 145800501);
      expect(tuningFrames().length, 2);
    },
  );

  test('RX hold sends only the latest correction when reception ends', () {
    settle();
    disable('SatelliteHoldDopplerDuringRx', true);
    audio('AudioDataStart');
    update(rx: 145801000);
    update(rx: 145803000);
    audio('AudioDataEnd', transmit: true);
    audio('AudioDataEnd', deviceId: 9301);
    expect(tuningFrames(), isEmpty);
    audio('AudioDataEnd');
    expect(tuningFrames().length, 1);
    expect(ByteData.sublistView(tuningFrames().single).getUint32(8), 145803000);
    update(rx: 145803999);
    expect(tuningFrames().length, 1);
  });

  test('receive hold is off by default and ignores TX echo activity', () {
    settle();
    audio('AudioDataStart');
    update(rx: 145801000);
    expect(tuningFrames().length, 1);
    audio('AudioDataEnd');
    disable('SatelliteHoldDopplerDuringRx', true);
    audio('AudioDataStart', transmit: true);
    update(rx: 145802000);
    expect(tuningFrames().length, 2);
  });

  test(
    'RX hold preserves initial tuning but defers remaining entry frames',
    () {
      disable('SatelliteHoldDopplerDuringRx', true);
      audio('AudioDataStart');
      lock();
      update();
      expect(tuningFrames().length, 1);
      update();
      update();
      expect(tuningFrames().length, 1);
      audio('AudioDataEnd');
      expect(tuningFrames().length, 2);
      update();
      expect(tuningFrames().length, 3);
      expect(
        tuningFrames().map((frame) => (frame[20] << 8) | frame[21]).toList(),
        [0x0A03, 0x0A03, 0x0A00],
      );
    },
  );

  test(
    'explicit target, tone and TX availability changes override RX hold',
    () {
      settle();
      disable('SatelliteHoldDopplerDuringRx', true);
      audio('AudioDataStart');
      update(rx: 145800100, usageIndex: 1);
      update(rx: 145800200, noradId: 12345);
      update(rx: 145800200, noradId: 12345, tone: 67);
      update(rx: 145800200, noradId: 12345, tone: 67, tx: 437800000);
      expect(tuningFrames().length, 4);
    },
  );

  test('releasing hold applies the latest correction on the next tick', () {
    settle();
    disable('SatelliteHoldDopplerDuringRx', true);
    audio('AudioDataStart');
    update(rx: 145802000);
    expect(tuningFrames(), isEmpty);
    disable('SatelliteHoldDopplerDuringRx', false);
    update(rx: 145803000);
    expect(tuningFrames().length, 1);
    expect(ByteData.sublistView(tuningFrames().single).getUint32(8), 145803000);
  });

  test(
    'audio shutdown releases hold but a below-threshold correction is skipped',
    () {
      settle();
      disable('SatelliteHoldDopplerDuringRx', true);
      audio('AudioDataStart');
      update(rx: 145800999);
      audio('AudioDataEnd');
      expect(tuningFrames(), isEmpty);
      audio('AudioDataStart');
      update(rx: 145802000);
      broker.dispatch(
        deviceId: radio.deviceId,
        name: 'AudioState',
        data: false,
      );
      expect(tuningFrames().length, 1);
    },
  );

  for (final stop in [
    'target',
    'other radio',
    'support',
    'unlock',
    'stop VFO',
    'disconnect',
  ]) {
    test('$stop discards deferred tuning', () {
      settle();
      disable('SatelliteHoldDopplerDuringRx', true);
      audio('AudioDataStart');
      update(rx: 145805000);
      switch (stop) {
        case 'target':
          broker.dispatch(
            deviceId: 0,
            name: 'SatelliteTrackTarget',
            data: null,
          );
          break;
        case 'other radio':
          broker.dispatch(
            deviceId: 0,
            name: 'SatelliteTrackTarget',
            data: {'radioDeviceId': 9301, 'noradId': 12345, 'usageIndex': 0},
          );
          break;
        case 'support':
          broker.dispatch(deviceId: 0, name: 'SatelliteSupport', data: 0);
          break;
        case 'unlock':
          broker.dispatch(
            deviceId: radio.deviceId,
            name: 'SetUnlock',
            data: SetUnlockData(usage: 'Satellite'),
          );
          expect(tuningFrames().single.sublist(8), everyElement(0));
          break;
        case 'stop VFO':
          radio.stopFreqMode();
          expect(tuningFrames().single.sublist(8), everyElement(0));
          break;
        case 'disconnect':
          radio.disconnect();
          break;
      }
      transport.sent.clear();
      audio('AudioDataEnd');
      expect(tuningFrames(), isEmpty);
    });
  }

  test('APRSSat uses the same threshold and a new session tunes afresh', () {
    lock(usage: 'APRSSat');
    update();
    update();
    update();
    transport.sent.clear();
    update(rx: 145800999);
    expect(tuningFrames(), isEmpty);
    broker.dispatch(
      deviceId: radio.deviceId,
      name: 'SetUnlock',
      data: SetUnlockData(usage: 'APRSSat'),
    );
    transport.sent.clear();
    lock();
    update(rx: 145800999);
    expect(tuningFrames().length, 1);
    expect(tuningFrames().single.sublist(20, 22), [0x0A, 0x03]);
  });

  for (final usage in ['APRSSat', 'Satellite']) {
    test('$usage hardware TNC frames ${usage == 'APRSSat' ? 'are' : 'are not'} '
        'routed as APRS', () async {
      final frames = <TncDataFragment>[];
      broker.subscribe(
        deviceId: radio.deviceId,
        name: 'DataFrame',
        callback: (_, _, data) {
          if (data is TncDataFragment) frames.add(data);
        },
      );
      lock(usage: usage);
      // Event notification dataRxd (2): final fragment 0 with channel id 3.
      const payload = [0x02, 0xC0, 0x41, 0x42, 0x43, 0x03];
      transport.simulateReceive(
        Uint8List.fromList([
          0xFF, 0x01, 0x00, payload.length, 0x00, 0x02, 0x00, 0x09, ...payload,
        ]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(frames, hasLength(1));
      if (usage == 'APRSSat') {
        expect(frames.single.usage, 'APRSSat');
        expect(frames.single.channelName, 'APRS');
      } else {
        expect(frames.single.usage, isNull);
        expect(frames.single.channelName, isNot('APRS'));
      }
    });
  }

  testWidgets('satellite Doppler settings save, reload and cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: const Scaffold(body: SatelliteTab()),
      ),
    );
    Future<void> openSettings() async {
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doppler settings...'));
      await tester.pumpAndSettle();
    }

    await openSettings();
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      1000,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('500 Hz').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(broker.getValue<int>(0, 'SatelliteDopplerThresholdHz'), 500);
    expect(broker.getValue<bool>(0, 'SatelliteHoldDopplerDuringRx'), isTrue);

    await openSettings();
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      500,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(broker.getValue<bool>(0, 'SatelliteHoldDopplerDuringRx'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Debug menu has no satellite command disable switches', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Ahem's wide glyphs overflow existing menu labels at normal scale.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: const Scaffold(body: DebugTab()),
      ),
    );
    Future<void> openMenu() async {
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Disable SET_SATELLITE_INFO'), findsNothing);
    expect(find.text('Disable FREQ_MODE_SET_PAR'), findsNothing);
    expect(find.text('Radio Settings...'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
