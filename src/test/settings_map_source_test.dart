import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/settings_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/utils/map_tile_source.dart';

void main() {
  setUp(() {
    DataBroker.reset();
  });
  tearDown(() {
    DataBroker.reset();
  });

  Future<void> open(WidgetTester tester, {double width = 600}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SettingsDialog(
                  initialTab: kIsWeb
                      ? 3
                      : (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS)
                      ? 6
                      : 7,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (kIsWeb) {
      expect(find.widgetWithText(Tab, 'Map'), findsOneWidget);
      expect(find.text('Airplane Tracking'), findsNothing);
      expect(find.text('GPS Serial Port'), findsNothing);
    }
    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, 'Use custom map source'),
    );
    await tester.pumpAndSettle();
  }

  final url = find.byKey(const ValueKey('customMapUrl'));
  final attribution = find.byKey(const ValueKey('customMapAttribution'));
  final toggle = find.widgetWithText(SwitchListTile, 'Use custom map source');

  testWidgets('custom source controls are below the other Map settings', (
    tester,
  ) async {
    DataBroker.dispatch(deviceId: 0, name: customMapEnabledKey, data: 1);
    await open(tester);
    if (!kIsWeb) {
      expect(
        tester.getTopLeft(toggle).dy,
        greaterThan(
          tester.getBottomLeft(find.text('Airplane Tracking (dump1090)')).dy,
        ),
      );
    }
    expect(
      tester.getTopLeft(url).dy,
      greaterThan(tester.getBottomLeft(toggle).dy),
    );
    expect(
      tester.getTopLeft(attribution).dy,
      greaterThan(tester.getBottomLeft(url).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('off hides fields; enabling reveals fields and validates Save', (
    tester,
  ) async {
    await open(tester, width: 420);
    expect(url, findsNothing);
    expect(attribution, findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(url, findsOneWidget);
    expect(attribution, findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.textContaining('Enter a valid HTTP/HTTPS'), findsOneWidget);
    expect(DataBroker.hasValue(0, customMapEnabledKey), isFalse);
    await tester.ensureVisible(url);
    await tester.enterText(url, ' https://example.com/tile?z={z}&x={x}&y={y} ');
    await tester.ensureVisible(attribution);
    await tester.enterText(attribution, ' Example Maps ');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
    expect(DataBroker.getValue<int>(0, customMapEnabledKey, 0), 1);
    expect(
      DataBroker.getValue<String>(0, customMapUrlKey, ''),
      'https://example.com/tile?z={z}&x={x}&y={y}',
    );
    expect(
      DataBroker.getValue<String>(0, customMapAttributionKey, ''),
      'Example Maps',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabling accepts invalid retained text and re-enabling keeps it',
    (tester) async {
      await open(tester);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(url);
      await tester.enterText(url, 'not a valid map URL');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(url, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(url).controller!.text,
        'not a valid map URL',
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(DataBroker.getValue<int>(0, customMapEnabledKey, 1), 0);
      expect(
        DataBroker.getValue<String>(0, customMapUrlKey, ''),
        'not a valid map URL',
      );
    },
  );

  testWidgets('Cancel leaves saved custom source unchanged', (tester) async {
    const saved = 'https://example.com/{z}/{x}/{y}.png';
    DataBroker.dispatch(deviceId: 0, name: customMapEnabledKey, data: 1);
    DataBroker.dispatch(deviceId: 0, name: customMapUrlKey, data: saved);
    await open(tester);
    await tester.ensureVisible(url);
    await tester.enterText(url, 'https://other.example/{z}/{x}/{y}.png');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(DataBroker.getValue<String>(0, customMapUrlKey, ''), saved);
    expect(DataBroker.getValue<int>(0, customMapEnabledKey, 0), 1);
  });
}
