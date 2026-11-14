/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// Sysop customization of the BBS menu (see bbs_settings.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/bbs_menu.dart';
import 'package:htcommander/handlers/bbs_settings.dart';
import 'package:htcommander/handlers/bbs_store.dart';
import 'package:htcommander/services/data_broker_client.dart';

AprsPacket _aprs(String tnc2, DateTime time) {
  final ax25 = Tnc2Codec.decode(tnc2, time: time)!;
  ax25.incoming = true;
  return AprsPacket.parse(ax25)!;
}

void main() {
  final broker = DataBrokerClient();
  late DateTime now;
  late List<AprsPacket> packets;
  late BbsMenu menu;

  String run(String line, {Map<String, Object?>? session}) {
    final reply = menu.handleLine('N1ABC', line, session: session);
    return (reply as BbsMenuReply).text;
  }

  setUp(() {
    now = DateTime(2026, 11, 8, 12, 0);
    packets = [];
    menu = BbsMenu(
      store: BbsStore(),
      aprsPackets: () => packets,
      callsignLookupAvailable: () => true,
      stationCallsign: () => 'N0CALL',
      clock: () => now,
    );
  });

  tearDown(() => BbsSettings().save(broker));

  test('defaults keep the standard menu', () {
    BbsSettings().save(broker);
    final text = run('M', session: {});
    expect(text, startsWith('${BbsSettings.defaultWelcomeMessage}\r'));
    expect(text, contains('[A]PRS'));
    expect(text, contains('[C]all'));
    expect(text, contains('[G]ames'));
    expect(text, isNot(contains('[N]ews')));
    expect(text, isNot(contains('[AP]')));
    expect(text, isNot(contains('[AH]')));
  });

  test('welcome message and announcement', () {
    BbsSettings(
      welcomeMessage: 'Hello from N0CALL\nSecond line',
      announcementEnabled: true,
      announcementText: 'Net tonight at 8pm',
    ).save(broker);
    final text = run('M');
    expect(text, startsWith('Hello from N0CALL\rSecond line\r'));
    expect(text, contains('[N]ews'));
    expect(run('N'), startsWith('Net tonight at 8pm\r'));
    expect(menu.welcome('N2XYZ', 'Test'), contains('[N] to read it'));
  });

  test('disabled features are hidden and refused', () {
    BbsSettings(
      callsignLookupEnabled: false,
      gamesEnabled: false,
      aprsMessagesEnabled: false,
    ).save(broker);
    final session = <String, Object?>{};
    final text = run('M', session: session);
    expect(text, isNot(contains('[C]all')));
    expect(text, isNot(contains('[G]ames')));
    expect(text, isNot(contains('[A]PRS')));
    expect(run('A'), contains('not available'));
    expect(run('G', session: session), contains('not available'));
  });

  test('individual games can be turned off', () {
    BbsSettings(
      disabledGames: {'GUESS', 'HANGMAN', 'MORSE', 'TRADER', 'ADVENTURE'},
    ).save(broker);
    final session = <String, Object?>{};
    final list = run('G', session: session);
    expect(list, contains('Tic-tac-toe'));
    expect(list, isNot(contains('Hangman')));
    expect(list, isNot(contains('Micro Trader')));
    expect(run('G TRADER', session: session), contains('not found'));
    expect(list, isNot(contains('Packet Adventure')));
    expect(run('G ADVENTURE', session: session), contains('not found'));
    expect(run('G 1', session: session), contains('Tic-tac-toe'));
  });

  test('APRS station lookup and heard list', () {
    BbsSettings(aprsLookupEnabled: true, aprsHeardEnabled: true).save(broker);
    packets = [
      _aprs(
        'N1XYZ-9>APRS:!4903.50N/07201.75W>Mobile on the road',
        now.subtract(const Duration(minutes: 30)),
      ),
      _aprs(
        'N2WX>APRS:!4903.50N/07201.75W_180/010g015t068r000p000P000h50b10150',
        now.subtract(const Duration(minutes: 5)),
      ),
    ];
    final menuText = run('M');
    expect(menuText, contains('[AP]'));
    expect(menuText, contains('[AH]'));

    final station = run('AP N1XYZ');
    expect(station, startsWith('N1XYZ-9 last heard'));
    expect(station, contains('Position: 49.0583, -72.0292'));
    expect(station, contains('Comment: Mobile on the road'));

    expect(run('AP N2WX'), contains('Weather:'));
    expect(run('AP K9ZZZ'), contains('No APRS station K9ZZZ'));

    final heard = run('AH');
    expect(heard.indexOf('N2WX'), lessThan(heard.indexOf('N1XYZ-9')));
  });
}
