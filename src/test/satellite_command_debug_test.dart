import 'dart:typed_data';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/radio_transport.dart';
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
    disable('DebugDisableSetSatelliteInfo', false);
    disable('DebugDisableFreqModeSetPar', false);
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
        'independent command gates: info=$disableInfo freq=$disableFreq',
        () {
          disable('DebugDisableSetSatelliteInfo', disableInfo);
          disable('DebugDisableFreqModeSetPar', disableFreq);
          radio.setSatelliteInfo(info);
          radio.freqModeSetPar(tuning);
          // Classic GAIA frames carry the command ID at bytes 6 and 7.
          expect(
            transport.sent.map((frame) => (frame[6] << 8) | frame[7]).toList(),
            [if (!disableInfo) 77, if (!disableFreq) 35],
          );
        },
      );
    }
  }

  test('toggles take effect without reconnecting and gate teardown', () {
    disable('DebugDisableSetSatelliteInfo', true);
    disable('DebugDisableFreqModeSetPar', true);
    radio.setSatelliteInfo(info);
    radio.freqModeSetPar(tuning);
    radio.stopFreqMode();
    expect(transport.sent, isEmpty);

    disable('DebugDisableSetSatelliteInfo', false);
    disable('DebugDisableFreqModeSetPar', false);
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

  test('disabled tracking updates do not consume initial mode flags', () {
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

    disable('DebugDisableFreqModeSetPar', true);
    update();
    update();
    update();
    expect(transport.sent.length, 3);
    expect(transport.sent.every((frame) => frame[7] == 77), isTrue);
    transport.sent.clear();
    disable('DebugDisableSetSatelliteInfo', true);
    disable('DebugDisableFreqModeSetPar', false);
    update();
    update();
    update();
    expect(transport.sent.length, 3);
    expect(transport.sent.every((frame) => frame[7] == 35), isTrue);
    expect(
      transport.sent.map((frame) => (frame[20] << 8) | frame[21]).toList(),
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

  test('debug suppression cannot advance tuning snapshot or entry flags', () {
    lock();
    disable('DebugDisableFreqModeSetPar', true);
    update(rx: 145801000);
    update(rx: 145805000);
    expect(tuningFrames(), isEmpty);
    disable('DebugDisableFreqModeSetPar', false);
    update(rx: 145805000);
    expect(tuningFrames().length, 1);
    expect(tuningFrames().single.sublist(20, 22), [0x0A, 0x03]);
  });

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

  testWidgets('Debug menu independently toggles and restores command gates', (
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

    for (final (label, setting) in [
      ('Disable SET_SATELLITE_INFO', 'DebugDisableSetSatelliteInfo'),
      ('Disable FREQ_MODE_SET_PAR', 'DebugDisableFreqModeSetPar'),
    ]) {
      await openMenu();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.widgetWithText(CheckedPopupMenuItem<String>, label),
            )
            .checked,
        isFalse,
      );
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, label),
      );
      await tester.pumpAndSettle();
      expect(broker.getValue<bool>(0, setting), isTrue);
      await openMenu();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.widgetWithText(CheckedPopupMenuItem<String>, label),
            )
            .checked,
        isTrue,
      );
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, label),
      );
      await tester.pumpAndSettle();
      expect(broker.getValue<bool>(0, setting), isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
