import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/widgets/packets_tab.dart';
import 'package:htcommander/widgets/tab_visibility.dart';

class _CountingFragment extends TncDataFragment {
  static int timeReads = 0;
  static int channelReads = 0;

  _CountingFragment(int n)
    : super(
        finalFragment: true,
        fragmentId: 0,
        data: Uint8List.fromList([0x42]),
        channelId: -1,
        regionId: -1,
        channelName: n.toString().padLeft(4, '0'),
        time: DateTime(2026, 1, 1).add(Duration(seconds: n)),
      );

  @override
  DateTime get time {
    timeReads++;
    return super.time;
  }

  @override
  String get channelName {
    channelReads++;
    return super.channelName;
  }
}

void main() {
  TncDataFragment packet(int second, String channel, int payload) =>
      TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: Uint8List.fromList([payload]),
        channelId: -1,
        regionId: -1,
        channelName: channel,
        radioMac: 'radio-$channel',
        time: DateTime(2026, 1, 1).add(Duration(seconds: second)),
      );

  void dispatch(String name, Object data) {
    DataBroker.dispatch(deviceId: 1, name: name, data: data, store: false);
  }

  Widget app({bool visible = true}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TabVisibility(visible: visible, child: const PacketsTab()),
    ),
  );

  Future<void> pumpTab(
    WidgetTester tester, [
    List<TncDataFragment> initial = const [],
  ]) async {
    await tester.pumpWidget(app());
    dispatch('PacketList', initial);
    await tester.pump();
  }

  Finder packetList() =>
      find.byWidgetPredicate((w) => w is ListView && w.itemExtent == 29);

  List<String> visibleChannels(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: packetList(), matching: find.byType(Text)),
        )
        .map((text) => text.data!)
        .toList();
    return [for (var i = 1; i < texts.length; i += 3) texts[i]];
  }

  tearDown(() {
    DataBroker.clearDevice(0);
    DataBroker.clearDevice(1);
  });

  for (final column in ['Time', 'Channel', 'Data']) {
    for (final ascending in [false, true]) {
      testWidgets('$column insertion stays sorted (ascending: $ascending)', (
        tester,
      ) async {
        await pumpTab(tester, [
          packet(30, 'B', 0x30),
          packet(10, 'D', 0x10),
          packet(20, 'A', 0x20),
        ]);
        if (column != 'Time') {
          await tester.tap(find.text(column));
          await tester.pump();
        }
        if (ascending == (column == 'Time')) {
          await tester.tap(find.text(column));
          await tester.pump();
        }

        dispatch('PacketStored', packet(40, 'C', 0x40));
        dispatch('PacketStored', packet(15, 'E', 0x15));
        dispatch('PacketStored', packet(20, 'F', 0x20));
        await tester.pump();

        final expected = column == 'Channel'
            ? (ascending
                  ? ['A', 'B', 'C', 'D', 'E', 'F']
                  : ['F', 'E', 'D', 'C', 'B', 'A'])
            : (ascending
                  ? ['D', 'E', 'A', 'F', 'B', 'C']
                  : ['C', 'B', 'A', 'F', 'E', 'D']);
        expect(visibleChannels(tester), expected);
      });
    }
  }

  testWidgets('chronological bursts use constant comparisons and one refresh', (
    tester,
  ) async {
    await pumpTab(tester);
    final before = tester.binding.transientCallbackCount;
    _CountingFragment.timeReads = 0;
    for (var n = 0; n < 1000; n++) {
      dispatch('PacketStored', _CountingFragment(n));
    }
    expect(_CountingFragment.timeReads, lessThanOrEqualTo(4000));
    expect(tester.binding.transientCallbackCount, before + 1);
    await tester.pump();
    expect(tester.widget<ListView>(packetList()).semanticChildCount, 1000);
    expect(visibleChannels(tester).first, '0999');

    await tester.tap(find.text('Time'));
    await tester.pump();
    expect(visibleChannels(tester).first, '0000');
    _CountingFragment.timeReads = 0;
    for (var n = 1000; n < 1100; n++) {
      dispatch('PacketStored', _CountingFragment(n));
    }
    expect(_CountingFragment.timeReads, lessThanOrEqualTo(200));
    await tester.pump();
    expect(tester.widget<ListView>(packetList()).semanticChildCount, 1100);
  });

  testWidgets('other columns use logarithmic insertion during bursts', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.text('Channel'));
    await tester.pump();
    _CountingFragment.channelReads = 0;
    for (var n = 0; n < 1000; n++) {
      dispatch('PacketStored', _CountingFragment((n * 337) % 1000));
    }
    expect(_CountingFragment.channelReads, lessThan(26000));
    await tester.pump();
    expect(tester.widget<ListView>(packetList()).semanticChildCount, 1000);
    expect(visibleChannels(tester).first, '0000');
  });

  for (final column in ['Time', 'Channel', 'Data']) {
    testWidgets('$column sort evicts oldest arrival and preserves selection', (
      tester,
    ) async {
      await pumpTab(tester, [
        for (var n = 0; n < 2000; n++)
          packet(n, n.toString().padLeft(4, '0'), 0x42),
      ]);
      if (column != 'Time') {
        await tester.tap(find.text(column));
        await tester.pump();
      }
      final selected = visibleChannels(tester).first;
      await tester.tap(find.text(selected));
      await tester.pump();
      expect(find.text('radio-$selected'), findsOneWidget);

      dispatch('PacketStored', packet(2000, 'newest', 0x43));
      await tester.pump();
      expect(tester.widget<ListView>(packetList()).semanticChildCount, 2000);
      if (selected == '0000') {
        expect(find.text('Select a packet to view decode'), findsOneWidget);
      } else {
        expect(find.text('radio-$selected'), findsOneWidget);
      }
      await tester.tap(find.text('Time').first);
      await tester.pump();
      if (column != 'Time') {
        await tester.tap(find.text('Time').first);
        await tester.pump();
      }
      expect(visibleChannels(tester).first, '0001');
      await tester.tap(find.text('Time').first);
      await tester.pump();
      expect(visibleChannels(tester).first, 'newest');
    });
  }

  testWidgets('replacement and disposal are safe with a pending refresh', (
    tester,
  ) async {
    await pumpTab(tester);
    dispatch('PacketStored', packet(1, 'old', 0x41));
    dispatch('PacketList', <TncDataFragment>[]);
    await tester.pump();
    expect(packetList(), findsNothing);
    dispatch('PacketStored', packet(2, 'new', 0x42));
    await tester.pump();
    expect(visibleChannels(tester), ['new']);
    dispatch('PacketStored', packet(3, 'pending', 0x43));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden tabs retain arrivals without scheduling refreshes', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.pumpWidget(app(visible: false));
    final before = tester.binding.transientCallbackCount;
    dispatch('PacketStored', packet(1, 'hidden-A', 0x41));
    dispatch('PacketStored', packet(2, 'hidden-B', 0x42));
    expect(tester.binding.transientCallbackCount, before);
    await tester.pumpWidget(app());
    expect(visibleChannels(tester), ['hidden-B', 'hidden-A']);
  });
}
