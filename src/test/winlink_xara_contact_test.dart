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
        await tester.enterText(path, 'N9DIG,N8DIG');
        await tester.pump();
        await tester.ensureVisible(ok);
        await tester.tap(ok);
        await tester.pumpAndSettle();
        expect(saved!.stationType, StationType.winlink);
        expect(saved!.terminalProtocol, protocol);
        expect(saved!.ax25Path, 'N9DIG,N8DIG');
        expect(saved!.modem, 'Hardware');
        final restored = StationInfo.fromJson(saved!.toJson());
        expect(restored.terminalProtocol, protocol);
        final imported = StationInfo.deserializeList(
          StationInfo.serializeList([saved!]),
        ).single;
        expect(imported.terminalProtocol, protocol);
      });
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
