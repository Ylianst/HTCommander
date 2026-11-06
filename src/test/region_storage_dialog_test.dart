import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/region_storage_dialog.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  const deviceId = 9876;
  late DataBrokerClient radio;

  void setRadio(String name, Object data) {
    DataBroker.dispatch(deviceId: deviceId, name: name, data: data);
  }

  setUp(() {
    setRadio('HtStatus', {'currRegion': 0});
    setRadio('AllChannelsLoaded', true);
    setRadio('Channels', []);
    setRadio('RegionNames', List.generate(12, (i) => 'Radio $i'));
    DataBroker.dispatch(
      deviceId: 0,
      name: 'RegionStorage',
      data: List.generate(
        32,
        (i) => i < 12 ? {'name': 'Stored $i', 'channels': []} : null,
      ),
    );
    radio = DataBrokerClient();
    radio.subscribe(
      deviceId: deviceId,
      name: 'SetRegion',
      callback: (_, _, region) {
        setRadio('HtStatus', {'currRegion': region});
        setRadio('AllChannelsLoaded', true);
      },
    );
  });

  tearDown(() {
    radio.dispose();
    DataBroker.dispatch(deviceId: 0, name: 'RegionStorage', data: null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRegionStorageDialog(
                context,
                deviceId: deviceId,
                radioName: 'Test radio',
                regionCount: 12,
                channelCount: 16,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder list(int index) => find.byType(SingleChildScrollView).at(index);

  ScrollPosition position(WidgetTester tester, int index) => tester
      .state<ScrollableState>(
        find.descendant(of: list(index), matching: find.byType(Scrollable)),
      )
      .position;

  Finder handle(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(Stack)).last,
    matching: find.byIcon(Icons.drag_indicator),
  );

  for (final width in [800.0, 500.0]) {
    testWidgets('region cards fill their columns at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await open(tester);

      for (final (index, name) in [(0, 'Radio 0'), (1, 'Stored 0')]) {
        final tile = find
            .ancestor(
              of: find.text(name),
              matching: find.byType(GestureDetector),
            )
            .first;
        final columnRect = tester.getRect(list(index));
        final tileRect = tester.getRect(tile);
        expect(tileRect.left, columnRect.left + 8);
        expect(tileRect.right, columnRect.right - 8);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('region bodies scroll both lists without starting a copy', (
    tester,
  ) async {
    await open(tester);
    for (final (index, name) in [(0, 'Radio 2'), (1, 'Stored 2')]) {
      await tester.drag(find.text(name), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(position(tester, index).pixels, greaterThan(0));
      final offset = position(tester, index).pixels;
      await tester.dragFrom(
        tester.getRect(list(index)).center,
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      expect(position(tester, index).pixels, lessThan(offset));
      expect(find.byTooltip('Cancel assignment'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles copy in both directions and assignments can be undone', (
    tester,
  ) async {
    await open(tester);
    for (final (source, target) in [
      ('Radio 0', 'Stored 1'),
      ('Stored 0', 'Radio 1'),
    ]) {
      final start = tester.getCenter(handle(source));
      final end = tester.getCenter(find.text(target));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text(source), findsNWidgets(2));
      expect(find.text(target), findsNothing);
      expect(position(tester, 0).pixels, 0);
      expect(position(tester, 1).pixels, 0);
      await tester.tap(find.byTooltip('Cancel assignment'));
      await tester.pumpAndSettle();
      expect(find.text(source), findsOneWidget);
      expect(find.text(target), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press on a region body still opens its context menu', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.text('Stored 0'));
    await tester.pumpAndSettle();
    expect(find.text('Details...'), findsOneWidget);
    expect(find.text('Rename...'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
