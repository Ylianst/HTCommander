import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_conversation.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/aprsis_history_store.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/aprs_handler.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/handlers/packet_store.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/db/packets_dao.dart';

const _local = AprsLocalStation('K7VZT', 'K7VZT-5');

/// Builds a stored RF frame from a TNC2 line.
TncDataFragment _rf(
  String tnc2, {
  bool incoming = true,
  String channel = 'APRS',
  int t = 1000,
}) {
  final ax25 = Tnc2Codec.decode(tnc2)!;
  return TncDataFragment(
    finalFragment: true,
    fragmentId: 0,
    data: ax25.toByteArray(),
    channelId: 0,
    regionId: 0,
    channelName: channel,
    incoming: incoming,
    time: DateTime.fromMillisecondsSinceEpoch(t),
  );
}

AprsPacket _aprs(String tnc2) => AprsPacket.parse(Tnc2Codec.decode(tnc2)!)!;

const _fromW1aw = 'W1AW-9>APRS,WIDE1-1::K7VZT-5  :hello{1';
const _toW1aw = 'K7VZT-5>APRS,WIDE1-1::W1AW-9   :hi back{2';
const _fromN0call = 'N0CALL>APRS,WIDE1-1::K7VZT-5  :other thread{3';
const _betweenOthers = 'N0CALL>APRS,WIDE1-1::W1AW-9   :not ours{4';

void main() {
  group('conversation threading', () {
    test('threads messages addressed to us or sent by us', () {
      expect(
        aprsPacketConversationPeer(
          _aprs(_fromW1aw),
          outgoing: false,
          local: _local,
        ),
        'W1AW-9',
      );
      expect(
        aprsPacketConversationPeer(
          _aprs(_toW1aw),
          outgoing: true,
          local: _local,
        ),
        'W1AW-9',
      );
      expect(
        aprsPacketConversationPeer(
          _aprs(_betweenOthers),
          outgoing: false,
          local: _local,
        ),
        isNull,
      );
    });

    test('ignores ACKs and non-message packets', () {
      expect(
        aprsPacketConversationPeer(
          _aprs('W1AW-9>APRS::K7VZT-5  :ack2'),
          outgoing: false,
          local: _local,
        ),
        isNull,
      );
      expect(
        aprsPacketConversationPeer(
          _aprs('W1AW-9>APRS:>status text'),
          outgoing: false,
          local: _local,
        ),
        isNull,
      );
    });

    test('drops a -0 SSID and threads SMS by phone digits', () {
      expect(aprsPeerKey(' sms-0 '), 'SMS');
      expect(
        aprsConversationPeer(
          sender: 'K7VZT-5',
          addressee: 'SMS',
          text: '@555-1234 hello',
          outgoing: true,
          local: _local,
        ),
        '5551234',
      );
      expect(
        aprsConversationPeer(
          sender: 'SMSGTE',
          addressee: 'K7VZT-5',
          text: '@5551234 reply',
          outgoing: false,
          local: _local,
        ),
        '5551234',
      );
    });

    test('decodes stored RF frames', () {
      expect(aprsFrameConversationPeer(_rf(_fromW1aw), local: _local), 'W1AW-9');
      expect(
        aprsFrameConversationPeer(_rf(_toW1aw, incoming: false), local: _local),
        'W1AW-9',
      );
    });
  });

  group('database', () {
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.openInMemory();
    });

    tearDown(() async {
      await AppDatabase.close();
    });

    test('hides one APRS conversation but keeps the raw packets', () async {
      await db.packets.insert(_rf(_fromW1aw, t: 1));
      await db.packets.insert(_rf(_toW1aw, incoming: false, t: 2));
      await db.packets.insert(_rf(_fromN0call, t: 3));
      await db.packets.insert(_rf(_fromW1aw, channel: '1', t: 4));

      final hidden = await db.packets.hideAprsWhere(
        (f) => aprsFrameConversationPeer(f, local: _local) == 'W1AW-9',
      );
      expect(hidden, 2);

      final rows = await db.packets.recent(10);
      expect(rows.length, 4);
      expect(rows.map((f) => f.aprsHidden), [true, true, false, false]);
    });

    test('hiding all APRS leaves other channels visible', () async {
      await db.packets.insert(_rf(_fromW1aw, t: 1));
      await db.packets.insert(_rf(_fromW1aw, channel: '1', t: 2));
      await db.packets.hideAllAprs();
      final rows = await db.packets.recent(10);
      expect(rows.map((f) => f.aprsHidden), [true, false]);
    });

    test('upgrading a v2 database adds the aprs_hidden column', () async {
      final old = db.db;
      await old.execute('DROP TABLE packets');
      await old.execute('''
        CREATE TABLE packets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          time_us INTEGER NOT NULL,
          incoming INTEGER NOT NULL,
          channel_id INTEGER NOT NULL,
          region_id INTEGER NOT NULL,
          channel_name TEXT NOT NULL,
          data BLOB NOT NULL,
          encoding INTEGER NOT NULL,
          frame_type INTEGER NOT NULL,
          corrections INTEGER NOT NULL,
          radio_mac TEXT
        )
      ''');
      await PacketsDao.addAprsHiddenColumn(old);
      final dao = PacketsDao(old);
      await dao.insert(_rf(_fromW1aw));
      await dao.hideAllAprs();
      expect((await dao.recent(1)).single.aprsHidden, isTrue);
    });

    test('deletes the APRS-IS records of one conversation', () async {
      await db.aprsis.insert(DateTime(2026), _fromW1aw);
      await db.aprsis.insert(DateTime(2026), _fromN0call);
      final deleted = await db.aprsis.deleteWhere(
        (AprsIsHistoryRecord r) => r.tnc2Line.startsWith('W1AW-9>'),
      );
      expect(deleted, 1);
      expect((await db.aprsis.recent(10)).single.tnc2Line, _fromN0call);
    });

    test('deletes only APRS-channel comms entries', () async {
      DecodedTextEntry aprs(String channel, String source) => DecodedTextEntry(
        text: 'hello',
        channel: channel,
        encoding: VoiceTextEncodingType.aprs,
        source: source,
        destination: 'K7VZT-5',
      );
      await db.comms.insert(aprs('APRS', 'W1AW-9'));
      await db.comms.insert(aprs('APRS-IS', 'N0CALL'));
      await db.comms.insert(aprs('2', 'W1AW-9'));
      await db.comms.insert(DecodedTextEntry(text: 'voice', channel: 'APRS'));

      final deleted = await db.comms.deleteAprsMessages(
        where: (e) => e.source == 'W1AW-9',
      );
      expect(deleted, 1);
      expect(await db.comms.count(), 3);

      await db.comms.deleteAprsMessages();
      final left = await db.comms.recent(10);
      expect(left.map((e) => e.channel), ['2', 'APRS']);
      expect(left.last.encoding, VoiceTextEncodingType.voice);
    });
  });

  group('Comms history clear', () {
    late CommsHandler handler;

    setUp(() async {
      await AppDatabase.openInMemory();
      DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'K7VZT');
      DataBroker.dispatch(deviceId: 0, name: 'StationId', data: 5);
    });

    tearDown(() async {
      handler.dispose();
      await AppDatabase.close();
    });

    Future<void> waitForCount(int count) async {
      for (var i = 0; i < 100; i++) {
        if (await AppDatabase.instance!.comms.count() == count) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('expected $count comms rows');
    }

    Future<void> start() async {
      final dao = AppDatabase.instance!.comms;
      await dao.insert(DecodedTextEntry(text: 'voice', channel: '1'));
      await dao.insert(
        DecodedTextEntry(
          text: 'hello',
          channel: 'APRS',
          encoding: VoiceTextEncodingType.aprs,
          source: 'W1AW-9',
          destination: 'K7VZT-5',
        ),
      );
      await dao.insert(
        DecodedTextEntry(
          text: 'other',
          channel: 'APRS',
          encoding: VoiceTextEncodingType.aprs,
          source: 'N0CALL',
          destination: 'K7VZT-5',
        ),
      );
      handler = CommsHandler()..init();
      for (var i = 0; i < 100; i++) {
        if (DataBroker.getValueDynamic(1, 'DecodedTextHistory') is List &&
            (DataBroker.getValueDynamic(1, 'DecodedTextHistory') as List)
                .isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('clearing Comms history empties the database', () async {
      await start();
      DataBroker.dispatch(
        deviceId: 1,
        name: 'ClearVoiceText',
        data: null,
        store: false,
      );
      await waitForCount(0);
    });

    test('clearing an APRS thread drops only its mirrored rows', () async {
      await start();
      DataBroker.dispatch(
        deviceId: 1,
        name: clearAprsConversationEvent,
        data: {'peer': 'W1AW-9'},
        store: false,
      );
      await waitForCount(2);
      final texts = (await AppDatabase.instance!.comms.recent(10)).map(
        (e) => e.text,
      );
      expect(texts, ['voice', 'other']);
    });
  });

  group('APRS clear survives a restart', () {
    setUp(() async {
      await AppDatabase.openInMemory();
      DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'K7VZT');
      DataBroker.dispatch(deviceId: 0, name: 'StationId', data: 5);
    });

    tearDown(() async {
      await AppDatabase.close();
    });

    /// Simulates a fresh launch: loads the stores from the database and returns
    /// the APRS messages the APRS tab would show.
    Future<List<String>> relaunch() async {
      final store = PacketStore();
      await store.init();
      final handler = AprsHandler()..init();
      final texts = handler
          .getAprsFrames()
          .map((p) => p.messageData.msgText)
          .toList();
      handler.dispose();
      await store.dispose();
      return texts;
    }

    Future<void> seed() async {
      final dao = AppDatabase.instance!.packets;
      await dao.insert(_rf(_fromW1aw, t: 1));
      await dao.insert(_rf(_toW1aw, incoming: false, t: 2));
      await dao.insert(_rf(_fromN0call, t: 3));
    }

    /// Waits for the fire-and-forget database update to land.
    Future<void> waitForHidden(int count) async {
      for (var i = 0; i < 100; i++) {
        final rows = await AppDatabase.instance!.packets.recent(10);
        if (rows.where((f) => f.aprsHidden).length == count) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('expected $count hidden packets');
    }

    test('clearing a thread only removes that thread', () async {
      await seed();
      final store = PacketStore();
      await store.init();
      DataBroker.dispatch(
        deviceId: 1,
        name: clearAprsConversationEvent,
        data: {'peer': 'W1AW-9'},
        store: false,
      );
      expect(store.getPackets().where((p) => p.aprsHidden).length, 2);
      await store.dispose();
      await waitForHidden(2);

      expect(await relaunch(), ['other thread']);
      // The raw packets are still in the capture.
      expect((await AppDatabase.instance!.packets.recent(10)).length, 3);
    });

    test('clearing all APRS messages removes them all', () async {
      await seed();
      final store = PacketStore();
      await store.init();
      DataBroker.dispatch(
        deviceId: 1,
        name: 'ClearAprsPackets',
        data: null,
        store: false,
      );
      await store.dispose();
      await waitForHidden(3);

      expect(await relaunch(), isEmpty);
      expect((await AppDatabase.instance!.packets.recent(10)).length, 3);
    });
  });
}
