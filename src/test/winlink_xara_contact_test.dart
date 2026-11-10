import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/add_station_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  for (final protocol in [
    TerminalProtocol.xaraNarrow,
    TerminalProtocol.xaraWide,
  ]) {
    for (final editing in [false, true]) {
      testWidgets('${editing ? 'edit' : 'create'} Winlink $protocol', (
        tester,
      ) async {
        final broker = DataBrokerClient();
        addTearDown(broker.dispose);
        StationInfo? saved;
        final existing = StationInfo(
          callsign: 'N1RMS-10',
          stationType: StationType.winlink,
          terminalProtocol: protocol,
          channel: 'WINLINK',
          channelRegion: 'Old region',
          frequencyHz: 145050000,
          ax25Path: 'N9DIG',
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showStationDialog(
                      context,
                      existing: editing ? existing : null,
                      fixedType: StationType.winlink,
                      initialCallsign: 'N1RMS-10',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final dropdown = find.byType(DropdownButtonFormField<TerminalProtocol>);
        expect(dropdown, findsOneWidget);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(find.text('XARA Narrow'), findsWidgets);
        expect(find.text('XARA Wide'), findsWidgets);
        expect(find.text('Raw AX.25'), findsNothing);
        expect(find.text('VARA FM (XARA)'), findsNothing);
        await tester.tap(
          find
              .text(
                protocol == TerminalProtocol.xaraWide
                    ? 'XARA Wide'
                    : 'XARA Narrow',
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(find.text('Software AFSK 1200'), findsNothing);

        if (!editing) {
          final callsign = find.widgetWithText(TextField, 'N1RMS-10');
          await tester.enterText(callsign, 'KK7VZT7');
          await tester.pump();
          expect(find.text('KK7VZT-7'), findsOneWidget);
          final frequency = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.keyboardType ==
                    const TextInputType.numberWithOptions(decimal: true),
          );
          await tester.ensureVisible(frequency);
          await tester.enterText(frequency, '145.050');
          await tester.pump();
        }

        final path = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              (widget.decoration?.labelText?.startsWith('Digipeater Path') ??
                  false),
        );
        await tester.ensureVisible(path);
        await tester.enterText(path, 'N9DIG,N8DIG,N7DIG');
        await tester.pump();
        final ok = find.widgetWithText(ElevatedButton, 'OK');
        expect(tester.widget<ElevatedButton>(ok).onPressed, isNull);
        expect(find.textContaining('up to two'), findsOneWidget);
        await tester.enterText(path, 'N9DIG7,N8DIG15');
        await tester.pump();
        await tester.ensureVisible(ok);
        await tester.tap(ok);
        await tester.pumpAndSettle();
        expect(saved!.stationType, StationType.winlink);
        expect(saved!.terminalProtocol, protocol);
        expect(saved!.callsign, editing ? 'N1RMS-10' : 'KK7VZT-7');
        expect(saved!.ax25Path, 'N9DIG-7,N8DIG-15');
        expect(saved!.modem, 'Hardware');
        expect(saved!.frequencyHz, 145050000);
        expect(saved!.channel, isEmpty);
        expect(saved!.channelRegion, isEmpty);
        expect(saved!.copyWith().frequencyHz, saved!.frequencyHz);
        final restored = StationInfo.fromJson(saved!.toJson());
        expect(restored.terminalProtocol, protocol);
        expect(restored.frequencyHz, saved!.frequencyHz);
        final imported = StationInfo.deserializeList(
          StationInfo.serializeList([saved!]),
        ).single;
        expect(imported.terminalProtocol, protocol);
        expect(imported.frequencyHz, saved!.frequencyHz);
      });
    }
  }

  for (final type in [
    StationType.winlink,
    StationType.terminal,
    StationType.bbs,
  ]) {
    for (final width in [360.0, 900.0]) {
      testWidgets(
        '$type copies channel frequency without saving channel at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final broker = DataBrokerClient();
          addTearDown(() {
            broker.dispatch(deviceId: 1, name: 'ConnectedRadios', data: null);
            broker.dispatch(deviceId: 9401, name: 'Channels', data: null);
            broker.dispose();
          });
          broker.dispatch(
            deviceId: 1,
            name: 'ConnectedRadios',
            data: [
              {'DeviceId': 9401},
            ],
          );
          broker.dispatch(
            deviceId: 9401,
            name: 'Channels',
            data: [
              {
                'name': 'Packet',
                'channelId': 2,
                'rxFreq': 145050000,
                'txFreq': 145050000,
              },
            ],
          );
          StationInfo? saved;
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      saved = await showStationDialog(
                        context,
                        fixedType: type,
                        initialCallsign: 'N1ABC-1',
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.text('Channel'), findsNothing);
          final picker = find.byType(PopupMenuButton<String>);
          await tester.ensureVisible(picker);
          await tester.tap(picker);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Packet (145.050000 MHz)'));
          await tester.pumpAndSettle();
          final frequency = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.keyboardType ==
                    const TextInputType.numberWithOptions(decimal: true),
          );
          expect(
            tester.widget<TextField>(frequency).controller!.text,
            '145.050000',
          );
          expect(tester.takeException(), isNull);
          final ok = find.widgetWithText(ElevatedButton, 'OK');
          await tester.ensureVisible(ok);
          await tester.tap(ok);
          await tester.pumpAndSettle();
          expect(saved!.frequencyHz, 145050000);
          expect(saved!.channel, isEmpty);
          expect(saved!.channelRegion, isEmpty);
        },
      );
    }
  }

  for (final wide in [false, true]) {
    testWidgets('legacy Winlink XARA contact adopts bandwidth $wide', (
      tester,
    ) async {
      final broker = DataBrokerClient();
      addTearDown(broker.dispose);
      broker.dispatch(deviceId: 0, name: 'XaraWide', data: wide);
      StationInfo? saved;
      final existing = StationInfo.fromJson(
        StationInfo(
          callsign: 'N1RMS-10',
          stationType: StationType.winlink,
          modem: 'XARA',
        ).toJson(),
      );
      expect(existing.modem, 'XARA');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showStationDialog(context, existing: existing);
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text(wide ? 'XARA Wide' : 'XARA Narrow'), findsOneWidget);
      expect(find.text('VARA FM (XARA)'), findsNothing);
      await tester.ensureVisible(find.text('OK'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        saved!.terminalProtocol,
        wide ? TerminalProtocol.xaraWide : TerminalProtocol.xaraNarrow,
      );
      expect(saved!.modem, 'Hardware');
      broker.dispatch(deviceId: 0, name: 'XaraWide', data: false);
    });
  }
}
