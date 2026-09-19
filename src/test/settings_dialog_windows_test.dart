/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/settings_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';

/// Regression coverage for issue #59: opening the settings dialog on desktop
/// (Windows) must build and lay out every tab without throwing or overflowing.
void main() {
  testWidgets('settings dialog builds every tab on Windows without overflow',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A valid 1x1 transparent PNG, base64-encoded, as a stored avatar image.
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

    void set(String name, Object? data) =>
        DataBroker.dispatch(deviceId: 0, name: name, data: data, store: true);

    set('CallSign', 'KK7ABC');
    set('StationId', 7);
    set('AvatarImage', png);
    set('AprsIsEnabled', 1);
    set('AprsIsServer', 'my.custom.server.example.com');
    set('AprsIsPort', 12345);
    set('AprsIsPasscode', '12345');
    set('GpsSerialPort', 'COM5');
    set('EchoLinkProxyEnabled', 1);
    set('EchoLinkProxyAuto', 0);
    set('ManualLocationEnabled', 1);
    set('ManualLatitude', 47.6062);
    set('ManualLongitude', -122.3321);

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsDialog()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'initial build');

      final tabs = find.byType(Tab);
      final count = tabs.evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(tabs.at(i), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'tab index $i');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
