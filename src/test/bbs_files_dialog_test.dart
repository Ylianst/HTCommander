/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// The BBS tab's Files dialog, driving a real BbsFileStore over the broker.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/bbs_files_dialog.dart';
import 'package:htcommander/handlers/bbs_files.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';

Uint8List _bytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) i & 0xFF]);

void main() {
  late Directory dir;
  late BbsFileStore files;

  setUp(() async {
    DataBroker.reset();
    dir = Directory.systemTemp.createTempSync('bbs_files_dialog_test');
    files = BbsFileStore(directory: dir.path);
    await files.init();
  });

  tearDown(() {
    files.dispose();
    DataBroker.reset();
    dir.deleteSync(recursive: true);
  });
  group('BBS tab Files dialog', () {
    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => BbsFilesDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists, toggles uploads and deletes files', (tester) async {
      files.add('readme.txt', _bytes(1500));
      files.add('log.txt', _bytes(20), uploader: 'K7ABC');
      await open(tester, const Size(1000, 800));

      expect(find.text('BBS Files'), findsOneWidget);
      expect(find.text('readme.txt'), findsOneWidget);
      expect(find.text('1.5 KB'), findsOneWidget);
      expect(find.text('K7ABC'), findsOneWidget);
      expect(find.text('Sysop'), findsOneWidget);
      // Newest first.
      expect(
        tester.getTopLeft(find.text('log.txt')).dy,
        lessThan(tester.getTopLeft(find.text('readme.txt')).dy),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(DataBroker.getValue<int>(0, BbsFileStore.uploadsSetting), 0);

      await tester.tap(find.text('readme.txt'));
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete readme.txt?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(files.list().map((f) => f.name), ['log.txt']);
      expect(find.text('readme.txt'), findsNothing);
    });

    testWidgets('fits a phone screen and shows an empty state', (tester) async {
      await open(tester, const Size(360, 640));
      expect(find.textContaining('No files yet'), findsOneWidget);
      files.add('a-rather-long-file-name-for-a-phone.txt', _bytes(10));
      await tester.pumpAndSettle();
      expect(find.text('Date'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
