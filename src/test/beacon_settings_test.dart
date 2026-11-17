/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/edit_beacon_settings_dialog.dart';
import 'package:htcommander/dialogs/hardware_radio_settings_dialog.dart';
import 'package:htcommander/dialogs/radio_bitfield_settings_panels.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/services/bluetooth_service.dart';
import 'package:htcommander/services/data_broker.dart';

Uint8List _withHeader(List<int> payload) =>
    Uint8List.fromList([0, 2, 0x80, 10, 0, ...payload]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'beacon channel overlay preserves neighboring bits and raw settings',
    () {
      final raw = _withHeader(List<int>.filled(22, 0xFF));
      final settings = RadioSettings.fromBytes(raw);
      for (final channel in [0, 16, 31, 32, 255]) {
        final written = settings.toByteArrayWith(autoShareLocCh: channel);
        expect(
          RadioSettings.fromBytes(_withHeader(written)).autoShareLocCh,
          channel,
        );
        final expected = Uint8List.fromList(raw.sublist(5));
        expected[5] = 0xE0 | (channel & 0x1F);
        expected[11] = 0xF8 | (channel >> 5);
        expect(written, expected);
        expect(settings.rawData, _withHeader(List<int>.filled(22, 0xFF)));
        expect(settings.autoShareLocCh, 255);
      }
      expect(
        () => settings.toByteArrayWith(autoShareLocCh: 256),
        throwsRangeError,
      );
      expect(
        () => RadioSettings.fromBytes(
          Uint8List(16),
        ).toByteArrayWith(autoShareLocCh: 1),
        throwsStateError,
      );
    },
  );

  group('beacon settings save', () {
    const native = MethodChannel('com.htcommander/bluetooth_classic');
    final service = BluetoothService();
    final writes = <Uint8List>[];
    late int deviceId;

    setUp(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'com.htcommander/bluetooth_classic_data',
        'com.htcommander/bluetooth_classic_audio',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'send') {
          final args = call.arguments as Map;
          final bytes = args['data'] as Uint8List;
          if (bytes.length >= 8 && bytes[6] == 0 && bytes[7] == 11) {
            writes.add(Uint8List.fromList(bytes.sublist(8)));
          }
        }
        return true;
      });
      DataBroker.dispatch(deviceId: 0, name: 'AudioEnabled', data: false);
      final connected = await service.connectToRadio(
        '00:00:00:00:00:91',
        'Test N7500',
      );
      expect(connected, isNotNull);
      deviceId = connected!;
      final radio = service.radioInstance(deviceId)!;
      radio.settings = RadioSettings.fromBytes(_withHeader(List.filled(22, 0)));
      radio.bssSettings = RadioBssSettings.fromBytes(Uint8List(51))
        ..aprsCallsign = 'N0CALL'
        ..aprsSymbol = '/-';
      radio.aprsPath = 'WIDE1-1,WIDE2-1';
      radio.channels = [
        RadioChannelInfo(channelId: 7, name: 'Crossband'),
        RadioChannelInfo(channelId: 31, name: 'APRS'),
      ];
      DataBroker.dispatch(
        deviceId: 1,
        name: 'SelectedRadioDeviceId',
        data: deviceId,
      );
      writes.clear();
    });

    tearDown(() async {
      await service.disconnectRadio(deviceId);
      DataBroker.clearDevice(deviceId);
      writes.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, null);
    });

    Future<void> openDialog(
      WidgetTester tester, {
      bool standalone = false,
      bool openBeacon = true,
      bool editOtherSettings = false,
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (standalone) {
                      showEditBeaconSettingsDialog(context);
                    } else {
                      showHardwareRadioSettingsDialog(
                        context,
                        deviceId: deviceId,
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (!standalone) {
        if (editOtherSettings) {
          tester.widget<TabBar>(find.byType(TabBar)).controller!.animateTo(4);
          await tester.pumpAndSettle();
          final controller = tester
              .widget<RadioBitfieldPanel>(find.byType(RadioBitfieldPanel).first)
              .controller;
          controller.update(() {
            controller.autoPowerOff = 5;
            controller.chDataLock = true;
            controller.vfo2TxPower = 3;
          });
        }
        if (openBeacon) {
          tester.widget<TabBar>(find.byType(TabBar)).controller!.animateTo(1);
          await tester.pumpAndSettle();
        }
      }
    }

    Future<void> selectChannel(WidgetTester tester, String label) async {
      final dropdown = find
          .descendant(
            of: find.byType(BeaconSettingsPanel),
            matching: find.byType(DropdownButtonFormField<int>),
          )
          .first;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    for (final standalone in [false, true]) {
      testWidgets(
        '${standalone ? 'standalone' : 'combined'} Save writes channel 32 exactly once',
        (tester) async {
          await openDialog(
            tester,
            standalone: standalone,
            editOtherSettings: !standalone,
          );
          await selectChannel(tester, 'APRS');
          await tester.tap(find.text(standalone ? 'OK' : 'Save'));
          await tester.pumpAndSettle();
          expect(writes, hasLength(1));
          final written = RadioSettings.fromBytes(_withHeader(writes.single));
          expect(written.autoShareLocCh, 32);
          expect(written.autoPowerOff, standalone ? 0 : 5);
          expect(written.chDataLock, !standalone);
          expect(written.vfo2TxPowerX, standalone ? 0 : 3);
          // No firmware reply: the cache must not be changed optimistically.
          expect(service.radioInstance(deviceId)!.settings!.autoShareLocCh, 0);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('combined Save can reset a dedicated channel to Current', (
      tester,
    ) async {
      final radio = service.radioInstance(deviceId)!;
      radio.settings = RadioSettings.fromBytes(
        _withHeader(radio.settings!.toByteArrayWith(autoShareLocCh: 32)),
      );
      await openDialog(tester);
      await selectChannel(tester, 'Current (Not Recommended)');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(
        RadioSettings.fromBytes(_withHeader(writes.single)).autoShareLocCh,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('saving without opening Beacon preserves its channel', (
      tester,
    ) async {
      final radio = service.radioInstance(deviceId)!;
      radio.settings = RadioSettings.fromBytes(
        _withHeader(radio.settings!.toByteArrayWith(autoShareLocCh: 32)),
      );
      await openDialog(tester, openBeacon: false);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(
        RadioSettings.fromBytes(_withHeader(writes.single)).autoShareLocCh,
        32,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }, skip: !(Platform.isWindows || Platform.isLinux || Platform.isMacOS));
}
