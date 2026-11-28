import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprs/aprs_observation.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/aprs_handler.dart';
import 'package:htcommander/handlers/aprs_observation_handler.dart';
import 'package:htcommander/handlers/frame_deduplicator.dart';
import 'package:htcommander/dialogs/aprs_observations_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/aprs_observation_store.dart';
import 'package:htcommander/services/aprs_outbox_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/widgets/aprs_tab.dart';
import 'package:htcommander/widgets/chat_widget.dart';

class _FailingStore extends AprsObservationStore {
  final bool failLoad;
  _FailingStore({this.failLoad = false});
  @override
  Future<List<AprsObservation>> load() async {
    if (failLoad) throw StateError('archive unreadable');
    return [];
  }

  @override
  Future<void> save(AprsObservation observation) async {
    if (!failLoad) throw StateError('disk full');
  }
}

class _BlockedStore extends AprsObservationStore {
  final loading = Completer<List<AprsObservation>>();
  final saved = <AprsObservation>[];
  @override
  Future<List<AprsObservation>> load() => loading.future;
  @override
  Future<void> save(AprsObservation observation) async =>
      saved.add(observation);
}

void main() {
  late DataBrokerClient bus;
  late AprsObservationHandler handler;
  late FrameDeduplicator dedup;
  late DateTime now;
  final live = <AprsObservation>[];
  var unique = 0;

  setUp(() async {
    DataBroker.reset();
    await AppDatabase.openInMemory();
    now = DateTime.utc(2026, 1, 1, 12);
    live.clear();
    unique = 0;
    bus = DataBrokerClient();
    bus.subscribe(
      deviceId: 1,
      name: 'AprsObservation',
      callback: (_, _, data) {
        if (data is AprsObservation) live.add(data);
      },
    );
    bus.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: (_, _, _) => unique++,
    );
    handler = AprsObservationHandler(clock: () => now)..init();
    await handler.ready;
    dedup = FrameDeduplicator();
  });

  tearDown(() async {
    handler.dispose();
    await handler.ready;
    dedup.dispose();
    bus.dispose();
    await AppDatabase.close();
    DataBroker.reset();
  });

  List<AprsObservation> snapshot() =>
      (bus.getValueDynamic(1, 'AprsObservations') as List)
          .map(
            (json) => AprsObservation.fromJson(
              Map<String, dynamic>.from(json as Map),
            ),
          )
          .toList();

  TncDataFragment receive(
    String line, {
    int radio = 100,
    int channel = 7,
    FragmentEncodingType encoding = FragmentEncodingType.hardwareAfsk1200,
    bool incoming = true,
    bool historical = false,
  }) {
    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: Tnc2Codec.decode(line)!.toByteArray(),
      channelId: channel,
      regionId: 2,
      channelName: 'APRS',
      radioDeviceId: radio,
      radioMac: 'radio-$radio',
      encoding: encoding,
      frameType: FragmentFrameType.ax25,
      corrections: 3,
      incoming: incoming,
      historical: historical,
      time: now.subtract(const Duration(milliseconds: 20)),
    );
    bus.dispatch(
      deviceId: radio,
      name: 'DataFrame',
      data: fragment,
      store: false,
    );
    return fragment;
  }

  testWidgets(
    'two radios and two decoders retain observations but produce one chat entry',
    (tester) async {
      final aprs = AprsHandler();
      await tester.runAsync(() async {
        aprs.init();
        await aprs.ready;
      });
      addTearDown(() async {
        aprs.dispose();
        await aprs.ready;
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AprsTab()),
        ),
      );
      await tester.tap(find.text('All APRS Messages').first);
      await tester.pump();
      const line = 'W1AW>APRS,WIDE1-1::N0CALL-7 :Hello{2';
      await tester.runAsync(() async {
        final original = receive(line);
        receive(line, radio: 101);
        receive(line, encoding: FragmentEncodingType.softwareAfsk1200);
        original.data.fillRange(0, original.data.length, 0);
        original.channelId = 99;
        await handler.ready;
      });
      await tester.pump();
      expect(unique, 1);
      expect(
        tester.widget<ChatWidget>(find.byType(ChatWidget).first).messages,
        hasLength(1),
      );
      expect(live, hasLength(3));
      expect(live.map((o) => o.radioMac), [
        'radio-100',
        'radio-101',
        'radio-100',
      ]);
      expect(live[1].duplicate, AprsDecodeDuplicate.none);
      expect(live[2].duplicate, AprsDecodeDuplicate.otherDecoder);
      expect(live[2].duplicateOf, live.first.id);
      expect(live.first.channel, 7);
      expect(live.first.region, 2);
      expect(live.first.corrections, 3);
      expect(live.first.dataHex, isNotEmpty);
      expect(snapshot().every((o) => o.persisted), isTrue);
      unawaited(
        showAprsObservationsDialog(tester.element(find.byType(AprsTab))),
      );
      await tester.pumpAndSettle();
      expect(find.text('3/1000'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'requested paths, used hops, third-party, internet and loopback remain distinct',
    () async {
      receive('W1AW>APRS,WIDE1-1:>direct');
      receive('W1AW>APRS,WIDE1-1*:>repeated');
      receive('IGATE-1>APRS:}W1AW>APRS,TCPIP,IGATE-1*::N0CALL   :hello');
      receive('W1AW>APRS:>loop', encoding: FragmentEncodingType.loopback);
      receive('W1AW>APRS,TCPIP:>internet marker without a used hop');
      receive('W1AW>APRS,TCPXX*:>unverified internet marker');
      receive('W1AW>APRS,qAR,IGATE:>internet RF copy');
      receive('W1AW>APRS,qAI:>internet origin');
      await handler.ready;
      expect(live.map((o) => o.kind), [
        AprsReceiveKind.directRf,
        AprsReceiveKind.digipeatedRf,
        AprsReceiveKind.thirdParty,
        AprsReceiveKind.loopback,
        AprsReceiveKind.internet,
        AprsReceiveKind.internet,
        AprsReceiveKind.internet,
        AprsReceiveKind.internet,
      ]);
      expect(live.first.path.single.used, isFalse);
      expect(live[1].path.single.used, isTrue);
      expect(live[2].source, 'W1AW');
      expect(live[2].frameSource, 'IGATE-1');
      expect(live.last.radioDeviceId, live.first.radioDeviceId);
      expect(live.last.decoder, live.first.decoder);
      expect(live.where((o) => o.isLiveDirectRf), [live.first]);
    },
  );

  test(
    'cross-window packet serialization preserves used hops without mutating received addresses',
    () {
      for (final command in [false, true]) {
        final ax = Tnc2Codec.decode('W1AW>APRS,WIDE1-1*:>received')!
          ..command = command;
        final flags = ax.addresses
            .map((a) => (a.crBit1, a.crBit2, a.crBit3))
            .toList();
        final encoded = AprsFrameEventArgs(
          AprsPacket.parse(ax)!,
          ax,
          null,
        ).toJson();
        expect(ax.addresses.map((a) => (a.crBit1, a.crBit2, a.crBit3)), flags);
        final restored = AprsFrameEventArgs.fromJson(encoded);
        expect(restored.ax25Packet.addresses[2].crBit1, isTrue);
        expect(restored.ax25Packet.command, command);
      }
    },
  );

  test(
    'same decoder repeats and different channels are not discarded or conflated',
    () async {
      const line = 'W1AW>APRS:>repeat';
      receive(line);
      receive(line);
      receive(line, channel: 8);
      now = now.add(const Duration(seconds: 3));
      receive(line);
      await handler.ready;
      expect(live.map((o) => o.duplicate), [
        AprsDecodeDuplicate.none,
        AprsDecodeDuplicate.sameDecoder,
        AprsDecodeDuplicate.none,
        AprsDecodeDuplicate.none,
      ]);
    },
  );

  test(
    'outgoing and historical raw frames do not enter live receive processing',
    () async {
      receive('W1AW>APRS:>old', incoming: false);
      final old = receive('W1AW>APRS:>old', historical: true);
      expect(TncDataFragment.fromJson(old.toJson()).historical, isTrue);
      await handler.ready;
      expect(live, isEmpty);
      expect(
        unique,
        1,
      ); // The outgoing packet still follows the existing capture path.
      expect(snapshot(), isEmpty);
    },
  );

  test(
    'internet and imported history cannot establish direct RF reachability',
    () async {
      for (final historical in [false, true]) {
        final ax = Tnc2Codec.decode('W1AW>APRS,TCPIP*,qAC,APRSFI:>internet')!;
        final aprs = AprsPacket.parse(ax)!..fromAprsIs = true;
        bus.dispatch(
          deviceId: 1,
          name: 'AprsFrame',
          data: AprsFrameEventArgs(aprs, ax, null, historical: historical),
          store: false,
        );
      }
      await handler.ready;
      expect(live, hasLength(1));
      expect(snapshot(), hasLength(2));
      expect(
        snapshot().every(
          (o) => !o.isLiveDirectRf && o.kind == AprsReceiveKind.internet,
        ),
        isTrue,
      );
      expect(snapshot().last.live, isFalse);
      expect(unique, 0);
    },
  );

  test(
    'v7 file migration preserves outbox intent and observations survive a database reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'htc-aprs-observations-',
      );
      final path = '${dir.path}${Platform.pathSeparator}archive.db';
      addTearDown(() async {
        handler.dispose();
        await handler.ready;
        await AppDatabase.close();
        await dir.delete(recursive: true);
      });
      final legacy = AprsOutgoingMessage(
        id: 'legacy',
        source: 'N0CALL-7',
        destination: 'W1AW',
        text: 'Hello',
        created: now,
        radioDeviceId: 100,
        linkPolicy: AprsLinkPolicy.rfOnly,
        authenticated: false,
        parts: const [AprsOutboxPart(wireId: 42, text: 'Hello')],
      ).toJson()..remove('linkPolicy');
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE aprs_outbox (id TEXT PRIMARY KEY, created_ms INTEGER NOT NULL, '
              'active INTEGER NOT NULL, payload TEXT NOT NULL)',
            );
            await db.insert('aprs_outbox', {
              'id': 'legacy',
              'created_ms': now.millisecondsSinceEpoch,
              'active': 1,
              'payload': jsonEncode(legacy),
            });
          },
        ),
      );
      await old.close();
      await AppDatabase.openFileForTesting(path);
      receive('W1AW>APRS,WIDE1-1*:>durable');
      await handler.ready;
      final id = snapshot().single.id;
      await AppDatabase.close();
      await AppDatabase.openFileForTesting(path);
      final archive = await AprsObservationStore().load();
      expect(archive.single.id, id);
      expect(archive.single.kind, AprsReceiveKind.digipeatedRf);
      expect(archive.single.live, isFalse);
      expect(archive.single.persisted, isTrue);
      final restoredOutbox = await AprsOutboxStore().load();
      expect(restoredOutbox.single.linkPolicy, AprsLinkPolicy.rfOnly);
      expect(restoredOutbox.single.parts.single.wireId, 42);
    },
  );

  test(
    'archive and journal retain exactly 1000 observations including decode duplicates',
    () async {
      for (var i = 0; i < 1001; i++) {
        receive('W1AW>APRS:>repeat');
      }
      await handler.ready;
      final archive = await AprsObservationStore().load();
      expect(snapshot(), hasLength(1000));
      expect(archive, hasLength(1000));
      expect(archive.first.id, live[1].id);
      expect(archive.last.id, live.last.id);
      expect(
        archive.every((o) => !o.live && o.persisted && !o.isLiveDirectRf),
        isTrue,
      );
      handler.dispose();
      await handler.ready;
      live.clear();
      unique = 0;
      handler = AprsObservationHandler(clock: () => now)..init();
      await handler.ready;
      expect(snapshot(), hasLength(1000));
      expect(snapshot().every((o) => !o.isLiveDirectRf && !o.live), isTrue);
      expect(live, isEmpty);
      expect(unique, 0);
    },
  );

  test(
    'captures during archive loading are preserved and dispose drains accepted writes',
    () async {
      handler.dispose();
      final store = _BlockedStore();
      handler = AprsObservationHandler(store: store, clock: () => now)..init();
      receive('W1AW>APRS:>during load');
      store.loading.complete([]);
      await handler.ready;
      expect(snapshot().single.live, isTrue);
      receive('W1AW>APRS:>before dispose');
      handler.dispose();
      receive('W1AW>APRS:>after dispose');
      await handler.ready;
      expect(store.saved, hasLength(2));
      expect(live, hasLength(2));
    },
  );

  test(
    'persistence failure leaves an explicit unsaved record and archive error',
    () async {
      handler.dispose();
      handler = AprsObservationHandler(store: _FailingStore(), clock: () => now)
        ..init();
      await handler.ready;
      receive('W1AW>APRS:>not saved');
      await handler.ready;
      expect(live, hasLength(1));
      expect(snapshot().single.persisted, isFalse);
      expect(
        (bus.getValueDynamic(1, 'AprsObservationError') as Map)['detail'],
        contains('disk full'),
      );
    },
  );

  test(
    'a successful new write does not hide an archive restoration failure',
    () async {
      handler.dispose();
      handler = AprsObservationHandler(
        store: _FailingStore(failLoad: true),
        clock: () => now,
      )..init();
      await handler.ready;
      receive('W1AW>APRS:>new capture');
      await handler.ready;
      expect(live, hasLength(1));
      expect(snapshot().single.persisted, isTrue);
      expect(
        (bus.getValueDynamic(1, 'AprsObservationError') as Map)['detail'],
        contains('archive unreadable'),
      );
    },
  );
}
