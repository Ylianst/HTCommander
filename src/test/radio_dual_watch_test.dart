/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/models/radio_models.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart' as wire;
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/radio_panel.dart';
import 'package:htcommander/widgets/radio_status_bar.dart';

void main() {
  final settings = RadioSettings(channelA: 14, channelB: 15, doubleChannel: 1);

  RadioHtStatus status({
    int selected = 1,
    int channel = 15,
    bool power = true,
    bool rx = true,
    bool sq = true,
    bool tx = false,
    bool scan = false,
  }) => RadioHtStatus(
    isPowerOn: power,
    isInRx: rx,
    isSq: sq,
    isInTx: tx,
    isScan: scan,
    doubleChannel: RadioChannelType.values[selected],
    currChId: channel,
  );

  test('receive highlight follows either VFO without changing selection', () {
    final receivingB = status();
    expect(receivingB.displayedVfo(settings), 2);
    expect(receivingB.doubleChannel.index, 1);
    expect(status(selected: 2, channel: 14).displayedVfo(settings), 1);
    expect(status(rx: false, sq: false).displayedVfo(settings), 1);
    expect(status(selected: 2, rx: false, sq: false).displayedVfo(settings), 2);
  });

  test('only audible dual-watch reception overrides selection', () {
    for (final unchanged in [
      status(rx: false),
      status(sq: false),
      status(tx: true),
      status(power: false),
      status(scan: true),
      status(channel: 12),
      status(selected: 0),
    ]) {
      expect(unchanged.displayedVfo(settings), unchanged.doubleChannel.index);
    }
    for (final unchangedSettings in [
      null,
      RadioSettings(channelA: 14, channelB: 15),
      RadioSettings(channelA: 14, channelB: 15, doubleChannel: 1, scan: true),
      RadioSettings(channelA: 15, channelB: 15, doubleChannel: 1),
    ]) {
      expect(status().displayedVfo(unchangedSettings), 1);
    }
  });

  for (final compact in [false, true]) {
    testWidgets(
      '${compact ? 'status bar' : 'radio tab'} follows Bluetooth RX/idle frames',
      (tester) async {
        const deviceId = 9200;
        DataBroker.clearDevice(deviceId);
        final broker = DataBrokerClient();
        final transport = MockRadioTransport();
        final radio = Radio(deviceId: deviceId, macAddress: 'test');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          radio.dispose();
          broker.dispose();
          await transport.dispose();
          DataBroker.clearDevice(deviceId);
        });
        await radio.connect(transport);
        broker.dispatch(deviceId: deviceId, name: 'State', data: 'Connected');
        broker.dispatch(
          deviceId: deviceId,
          name: 'Settings',
          data: settings.toJson(),
        );
        broker.dispatch(
          deviceId: deviceId,
          name: 'Channels',
          data: List.generate(
            16,
            (id) => wire.RadioChannelInfo(
              channelId: id,
              name: 'Channel $id',
              rxFreq: 146520000 + id * 25000,
              txFreq: 146520000 + id * 25000,
            ).toJson(),
          ),
        );
        final switches = <Object?>[];
        broker.subscribe(
          deviceId: deviceId,
          name: 'SwitchVfo',
          callback: (_, _, data) => switches.add(data),
        );

        Future<void> receive(String hex) async {
          transport.simulateReceive(RadioUtils.hexStringToByteArray(hex)!);
          await tester.pump();
          await tester.pump();
        }

        await receive('FF010005000200090184FB0000');
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: compact
                  ? const Align(
                      alignment: Alignment.topCenter,
                      child: RadioStatusBar(deviceId: deviceId),
                    )
                  : const RadioPanelControl(deviceId: deviceId),
            ),
          ),
        );
        await tester.pump();

        Finder label(int channel) => find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == 'Channel $channel' &&
              widget.style?.fontSize == (compact ? 14 : 22),
        );

        void expectHighlight(int vfo) {
          for (final channel in [14, 15]) {
            expect(
              tester.widget<Text>(label(channel)).style!.color,
              channel == (vfo == 1 ? 14 : 15)
                  ? const Color(0xFFDDD300)
                  : const Color(0xFFD3D3D3),
            );
          }
          final marker = find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.size == const Size(3, 7),
          );
          expect(marker, findsOneWidget);
          final markerY = tester.getCenter(marker).dy;
          final aY = tester.getCenter(label(14)).dy;
          final bY = tester.getCenter(label(15)).dy;
          // The compact bar's labels share a row; use the marker's X instead.
          if (compact) {
            final markerX = tester.getCenter(marker).dx;
            expect(
              markerX,
              vfo == 1
                  ? lessThan(tester.getTopLeft(label(14)).dx)
                  : greaterThan(tester.getTopRight(label(14)).dx),
            );
          } else {
            expect(
              (markerY - (vfo == 1 ? aY : bY)).abs(),
              lessThan((markerY - (vfo == 1 ? bY : aY)).abs()),
            );
          }
        }

        expectHighlight(1);
        for (final frame in [
          'FF0100050002000901B4FB8000',
          'FF0100050002000901B4FB7000',
          'FF010005000200090184FB0000',
          'FF0100050002000901B4FB8000',
          'FF010005000200090184FB0000',
        ]) {
          await receive(frame);
          final decoded = RadioHtStatus.fromJson(
            broker.getValue<Map<String, dynamic>>(deviceId, 'HtStatus')!,
          );
          expect(decoded.currChId, 15);
          expect(decoded.doubleChannel.index, 1);
          expectHighlight(decoded.isInRx ? 2 : 1);
        }
        expect(switches, isEmpty);

        await receive('FF0100050002000901B4FB8000');
        await tester.tap(label(14));
        await tester.pump();
        expect(switches, isEmpty);
        await tester.tap(label(15));
        await tester.pump();
        expect(switches, [2]);

      },
    );
  }
}
