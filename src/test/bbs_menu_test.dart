/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The BBS menu: message board, visitor log, APRS message lists and callsign
// lookup, plus the store that persists the board and visitor log.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/callsign/callsign_record.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_store.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';

AprsPacket _aprs(String tnc2, DateTime time, {bool incoming = true}) {
  final ax25 = Tnc2Codec.decode(tnc2, time: time)!;
  ax25.incoming = incoming;
  return AprsPacket.parse(ax25)!;
}

class _TestLink extends BbsLink {
  @override
  final String remoteCallsign;
  @override
  final Map<String, Object?> sessionState = {};
  final sent = <int>[];
  bool closed = false;

  _TestLink(this.remoteCallsign);

  String get text => utf8.decode(sent, allowMalformed: true);

  @override
  String get protocol => 'Test';

  @override
  bool get isConnected => !closed;

  @override
  void send(Uint8List data) => sent.addAll(data);

  @override
  void disconnect() => closed = true;
}

void main() {
  late BbsStore store;
  late DateTime now;
  late List<AprsPacket> packets;
  late bool lookupAvailable;
  late Map<String, CallsignRecord> records;
  late BbsMenu menu;

  String run(String caller, String line) {
    final reply = menu.handleLine(caller, line);
    expect(reply, isA<BbsMenuReply>());
    final text = (reply as BbsMenuReply).text;
    expect(text, endsWith(BbsMenu.prompt));
    return text;
  }

  setUp(() {
    store = BbsStore();
    now = DateTime(2026, 11, 7, 10, 0);
    packets = [];
    lookupAvailable = false;
    records = {};
    menu = BbsMenu(
      store: store,
      aprsPackets: () => packets,
      callsignLookupAvailable: () => lookupAvailable,
      callsignLookup: (call) async => records[call],
      stationCallsign: () => 'N0CALL',
      clock: () => now,
    );
  });

  group('menu', () {
    test('lists the commands and only offers lookup with a database', () {
      final text = run('W1AW', 'm');
      for (final item in [
        '[B]oard',
        '[R]ead',
        '[P]ost',
        '[K]ill',
        '[A]PRS',
        '[AM]',
        '[L]ast',
        '[S]oftware',
        '[D]isconnect',
      ]) {
        expect(text, contains(item));
      }
      expect(text, isNot(contains('[C]all')));
      expect(run('W1AW', 'C W1AW'), contains('not available'));

      lookupAvailable = true;
      expect(run('W1AW', 'help'), contains('[C]all <call>'));
    });

    test('shows how many entries each listing has', () {
      expect(run('W1AW', 'm'), contains('List board messages (0)\r'));
      run('W1AW', 'P Hello');
      run('K7ABC', 'P Hi');
      menu.welcome('W1AW', 'AX.25');
      packets
        ..add(_aprs('K7ABC>APRS::W1AW-9   :First{1', now))
        ..add(_aprs('N1XYZ>APRS::K7ABC    :Second{7', now));
      final text = run('W1AW-5', 'm');
      expect(text, contains('List board messages (2)\r'));
      expect(text, contains('APRS messages heard (2)\r'));
      expect(text, contains('APRS messages for you (1)\r'));
      expect(text, contains('Stations that connected (1)\r'));
    });

    test('unknown commands and disconnect', () {
      expect(run('W1AW', 'XYZZY'), startsWith('Unknown command'));
      for (final cmd in ['d', 'BYE', 'disconnect']) {
        final reply = menu.handleLine('W1AW', cmd) as BbsMenuReply;
        expect(reply.disconnect, isTrue);
      }
    });
  });

  group('message board', () {
    test('post, list, read and delete', () {
      expect(run('W1AW', 'B'), contains('board is empty'));
      expect(run('W1AW-5', 'P Hello   everyone'), contains('#1 posted'));
      now = now.add(const Duration(minutes: 5));
      expect(run('K7ABC', 'post Second one'), contains('#2 posted'));

      final list = run('W1AW', 'b');
      expect(list, contains('Message board, 2 messages:'));
      expect(list, contains('#1 W1AW-5 2026-11-07 10:00\r  Hello everyone\r'));
      expect(list, contains('#2 K7ABC 2026-11-07 10:05\r  Second one\r'));
      expect(list.indexOf('#1'), lessThan(list.indexOf('#2')));

      expect(run('W1AW', 'B 1'), contains('last 1 of 2 messages'));
      expect(run('W1AW', 'B 1'), isNot(contains('#1 ')));
      expect(run('W1AW', 'R #2'), contains('Second one'));
      expect(run('W1AW', 'R 9'), contains('#9 not found'));
      expect(run('W1AW', 'R'), startsWith('Usage'));

      // Only the poster (any SSID) or the sysop may delete a message.
      expect(run('K7ABC', 'K 1'), contains('only delete your own'));
      expect(run('W1AW-7', 'K 1'), contains('#1 deleted'));
      expect(run('N0CALL-3', 'kill 2'), contains('#2 deleted'));
      expect(store.messages, isEmpty);

      // Numbers are never reused.
      expect(run('W1AW', 'P Third'), contains('#3 posted'));
    });

    test('rejects empty and oversized posts and strips control codes', () {
      expect(run('W1AW', 'P'), startsWith('Usage'));
      final long = 'x' * (BbsStore.maxMessageLength + 1);
      expect(run('W1AW', 'P $long'), contains('too long'));
      expect(store.messages, isEmpty);
      run('W1AW', 'P a\x1b[2Jb\tc');
      expect(store.messages.single.text, 'a [2Jb c');
    });

    test('the board is capped', () {
      final small = BbsStore(maxMessages: 2);
      for (var i = 1; i <= 3; i++) {
        small.post('W1AW', 'm$i');
      }
      expect(small.messages.map((m) => m.id), [2, 3]);
    });
  });

  group('visitors', () {
    test('lists the last unique stations, most recent first', () {
      expect(run('W1AW', 'L'), contains('No stations'));
      menu.welcome('W1AW', 'AX.25');
      now = now.add(const Duration(hours: 2));
      menu.welcome('K7ABC-5', 'Web');
      now = now.add(const Duration(hours: 1));
      menu.welcome('w1aw', 'XARA');

      final text = run('K7ABC-5', 'L');
      expect(text, contains('Last 2 stations to connect:'));
      final lines = text.split('\r');
      expect(lines[1], startsWith('W1AW '));
      expect(lines[1], contains('2026-11-07 13:00'));
      expect(lines[1], contains('just now'));
      expect(lines[1], contains('XARA'));
      expect(lines[1], contains('2 visits'));
      expect(lines[2], startsWith('K7ABC-5 '));
      expect(lines[2], contains('1h ago'));
      expect(lines[2], contains('1 visit'));
      expect(run('K7ABC-5', 'L 1'), contains('Last station to connect:'));
      expect(run('K7ABC-5', 'L x'), startsWith('Usage'));
    });

    test('greets returning stations with what is new', () {
      store.post('K7ABC', 'old post', time: now);
      final first = menu.welcome('W1AW', 'AX.25');
      expect(first, contains('Welcome W1AW!'));
      expect(first, contains('1 message on the board'));

      now = now.add(const Duration(days: 1));
      store.post('K7ABC', 'new post', time: now);
      store.post('W1AW-3', 'my own post', time: now);
      packets.add(_aprs('K7ABC>APRS::W1AW-9   :Are you there?{1', now));
      final greeting = menu.welcome('W1AW', 'AX.25');
      expect(greeting, contains('Welcome back W1AW, last visit 2026-11-07'));
      expect(greeting, contains('1 new board message,'));
      expect(greeting, contains('1 new APRS message for you'));
    });
  });

  group('APRS messages', () {
    test('lists received messages, oldest first, without repeats', () {
      expect(run('W1AW', 'A'), contains('No APRS messages'));
      packets
        ..add(_aprs('K7ABC>APRS::W1AW-9   :First{1', now))
        // A retry of the same message, also heard over APRS-IS.
        ..add(
          _aprs(
            'K7ABC>APRS::W1AW-9   :First{1',
            now.add(const Duration(minutes: 1)),
          ),
        )
        ..add(
          _aprs(
            'N1XYZ>APRS::K7ABC    :Second{7',
            now.add(const Duration(minutes: 2)),
          ),
        )
        // Acks, bulletins and our own sent messages are not listed.
        ..add(_aprs('W1AW>APRS::K7ABC    :ack1', now))
        ..add(_aprs('W1AW>APRS::BLN1     :Bulletin', now))
        ..add(_aprs('N0CALL>APRS::K7ABC    :Sent{3', now, incoming: false));

      final all = run('K7ABC', 'A');
      expect(all, startsWith('2 APRS messages heard:'));
      expect(all, contains('2026-11-07 10:00 K7ABC > W1AW-9: First\r'));
      expect(all, contains('2026-11-07 10:02 N1XYZ > K7ABC: Second\r'));
      expect(all.indexOf('First'), lessThan(all.indexOf('Second')));
      expect(all, isNot(contains('Bulletin')));
      expect(all, isNot(contains('Sent')));

      expect(run('K7ABC', 'A 1'), startsWith('Last 1 of 2 APRS messages'));
      expect(run('K7ABC', 'A 1'), contains('Second'));

      final mine = run('W1AW-5', 'AM');
      expect(mine, startsWith('1 APRS message for W1AW:'));
      expect(mine, contains('First'));
      expect(run('N9ZZZ', 'AM'), contains('No APRS messages for N9ZZZ'));
    });
  });

  group('callsign lookup', () {
    setUp(() {
      lookupAvailable = true;
      records['W1AW'] = const CallsignRecord(
        callsign: 'W1AW',
        name: 'ARRL HQ',
        operatorClass: 'E',
        status: 'A',
        city: 'Newington',
        state: 'CT',
        zip: '06111',
        expireDate: 20300115,
      );
    });

    Future<String> lookup(String caller, String line) async {
      final reply = menu.handleLine(caller, line);
      expect(reply, isA<Future<BbsMenuReply>>());
      return (await reply).text;
    }

    test('shows the license record', () async {
      final text = await lookup('K7ABC', 'C w1aw-5');
      expect(text, contains('W1AW: ARRL HQ\r'));
      expect(text, contains('License: Amateur Extra, Active\r'));
      expect(text, contains('Location: Newington, CT 06111\r'));
      expect(text, contains('Expires: 2030-01-15\r'));
      expect(text, endsWith(BbsMenu.prompt));
    });

    test('looks up the caller by default and reports misses', () async {
      expect(await lookup('W1AW-9', 'C'), contains('ARRL HQ'));
      expect(await lookup('W1AW', 'C K7ABC'), contains('K7ABC was not found'));
      expect(await lookup('W1AW', 'C !!'), startsWith('Usage'));
    });

    test('BBS links keep reply order around a lookup', () async {
      final gate = Completer<CallsignRecord?>();
      final broker = DataBrokerClient();
      broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
      final bbs = Bbs(431)..enabled = true;
      bbs.menu = BbsMenu(
        store: store,
        aprsPackets: () => packets,
        callsignLookupAvailable: () => true,
        callsignLookup: (_) => gate.future,
      );
      final link = _TestLink('K7ABC');
      bbs.openLink(link, cmsRelay: false);
      expect(link.text, contains('Welcome K7ABC!'));

      bbs.linkReceived(link, Uint8List.fromList(utf8.encode('C W1AW\rS\r')));
      bbs.linkReceived(link, Uint8List.fromList(utf8.encode('B\r')));
      expect(link.text, isNot(contains('open source')));

      gate.complete(records['W1AW']);
      await Future<void>.delayed(Duration.zero);
      final text = link.text;
      expect(text.indexOf('ARRL HQ'), greaterThan(0));
      expect(text.indexOf('open source'), greaterThan(text.indexOf('ARRL HQ')));
      expect(text.indexOf('board is empty'), greaterThan(text.indexOf('open')));

      bbs.dispose();
      broker.dispose();
      DataBroker.clearDevice(0);
    });
  });

  group('BbsStore persistence', () {
    tearDown(AppDatabase.close);

    test('board and visitor log survive a reload', () async {
      await AppDatabase.openInMemory();
      final first = BbsStore();
      await first.init();
      first.post('W1AW', 'one', time: now);
      first.post('K7ABC', 'two', time: now);
      first.post('K7ABC', 'three', time: now);
      first.delete(3);
      first.recordVisit('W1AW-5', 'Web', time: now);
      first.recordVisit(
        'W1AW-5',
        'AX.25',
        time: now.add(const Duration(hours: 1)),
      );
      await first.flush();

      final second = BbsStore();
      await second.init();
      expect(second.messages.map((m) => m.text), ['one', 'two']);
      expect(second.message(2)!.callsign, 'K7ABC');
      expect(second.post('W1AW', 'four').id, 4);
      final visit = second.visit('w1aw-5')!;
      expect(visit.count, 2);
      expect(visit.protocol, 'AX.25');
      expect(visit.firstSeen, now);
      await second.flush();
    });

    test(
      'visitors keep connection order across reloads and are capped',
      () async {
        await AppDatabase.openInMemory();
        final first = BbsStore(maxVisits: 2);
        await first.init();
        for (final call in ['W1AW', 'K7ABC', 'N1XYZ', 'K7ABC']) {
          first.recordVisit(call, 'Web', time: now);
        }
        expect(first.recentVisits(10).map((v) => v.callsign), [
          'K7ABC',
          'N1XYZ',
        ]);
        await first.flush();

        final second = BbsStore();
        await second.init();
        expect(second.recentVisits(10).map((v) => v.callsign), [
          'K7ABC',
          'N1XYZ',
        ]);
      },
    );
  });
}
