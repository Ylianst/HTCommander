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

class _RecordingTransport extends MockRadioTransport {
  final sent = <Uint8List>[];

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
