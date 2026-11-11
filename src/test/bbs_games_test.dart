/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The BBS games menu and its text games.
//

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_games.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_store.dart';

void main() {
  late BbsMenu menu;
  late Map<String, Object?> session;

  String run(String line) {
    final reply = menu.handleLine('W1AW', line, session: session);
    expect(reply, isA<BbsMenuReply>());
    final text = (reply as BbsMenuReply).text;
    expect(text, endsWith(BbsMenu.prompt));
    return text;
  }

  setUp(() {
    menu = BbsMenu(
      store: BbsStore(),
      aprsPackets: () => const [],
      callsignLookupAvailable: () => false,
      random: math.Random(1),
    );
    session = {};
  });

  test('menu lists games only for clients with a session', () {
    expect(run('M'), contains('[G]ames'));
    final reply = menu.handleLine('W1AW', 'M') as BbsMenuReply;
    expect(reply.text, isNot(contains('[G]ames')));
    final g = menu.handleLine('W1AW', 'G') as BbsMenuReply;
    expect(g.text, contains('not available'));
  });

  test('G lists the games, unknown game is reported', () {
    final text = run('G');
    expect(text, contains('1 Guess the number'));
    expect(text, contains('2 Hangman'));
    expect(text, contains('3 Morse quiz'));
    expect(text, contains('4 Tic-tac-toe'));
    expect(text, contains('5 Micro Trader'));
    expect(text, contains('6 Packet Adventure'));
    expect(run('G 9'), contains('Game 9 not found'));
    expect(BbsGames.isPlaying(session), isFalse);
  });

  test('a running game gets every line until QUIT', () {
    expect(run('G 1'), contains('Guess the number'));
    expect(BbsGames.isPlaying(session), isTrue);
    expect(run('M'), contains('Enter a number'));
    expect(run('D'), contains('Enter a number'));
    expect(run('quit'), contains('Back to the BBS'));
    expect(BbsGames.isPlaying(session), isFalse);
    expect(run('M'), contains('[G]ames'));
  });

  test('games can be started by name', () {
    expect(run('G hang'), contains('Hangman'));
    expect(run('EXIT'), contains('Back to the BBS'));
    expect(run('G ttt'), contains('Tic-tac-toe'));
  });

  test('guess the number finds the secret by bisection', () {
    run('G 1');
    var low = 1, high = GuessNumberGame.max;
    String text = '';
    for (var i = 0; i < 10 && BbsGames.isPlaying(session); i++) {
      final guess = (low + high) ~/ 2;
      text = run('$guess');
      if (text.contains('too low')) low = guess + 1;
      if (text.contains('too high')) high = guess - 1;
    }
    expect(text, contains('You got it'));
    expect(text, contains('Back to the BBS'));
    expect(BbsGames.isPlaying(session), isFalse);
    expect(run('abc'), contains('Unknown command'));
  });

  test('hangman win and loss', () {
    final win = HangmanGame(math.Random(3), word: 'DIPOLE');
    expect(win.start(), startsWith('_ _ _ _ _ _  Misses 0/6'));
    expect(win.play('O'), startsWith('_ _ _ O _ _'));
    expect(win.play('O'), contains('already tried O'));
    expect(win.play('Z'), contains('Misses 1/6 Z'));
    expect(win.play('1'), contains('Guess a letter'));
    expect(win.play('dipole'), contains('You win'));
    expect(win.isOver, isTrue);

    final lose = HangmanGame(math.Random(3), word: 'DIPOLE');
    var text = '';
    for (final c in ['A', 'B', 'C', 'F', 'G']) {
      text = lose.play(c);
    }
    expect(lose.isOver, isFalse);
    text = lose.play('DIPOLES');
    expect(text, contains('Out of tries, the word was DIPOLE'));
    expect(lose.isOver, isTrue);
  });

  test('Morse quiz encodes and scores', () {
    expect(MorseQuizGame.encode('cq 73'), '-.-. --.-  --... ...--');
    final game = MorseQuizGame(math.Random(5));
    final codes = {
      for (final w in MorseQuizGame.words) MorseQuizGame.encode(w): w,
    };
    var text = game.start();
    for (var i = 0; i < MorseQuizGame.rounds; i++) {
      final code = text.trimRight().split(': ').last;
      final word = codes[code]!;
      text = game.play(i == 0 ? 'WRONG' : word.toLowerCase());
    }
    expect(game.isOver, isTrue);
    expect(text, contains('Score: ${MorseQuizGame.rounds - 1}/'));
  });

  test('tic-tac-toe blocks and wins', () {
    final game = TicTacToeGame(math.Random(1));
    game.start();
    expect(game.play('0'), contains('from 1 to 9'));
    // Takes the center after a corner.
    expect(game.play('1'), contains('I play 5'));
    expect(game.play('1'), contains('taken'));
    // Blocks 1-2-3.
    expect(game.play('2'), contains('I play 3'));
    // O has 3-5, must win on 7.
    final text = game.play('9');
    expect(text, contains('I play 7. I win!'));
    expect(game.isOver, isTrue);
  });

  test('Micro Trader starts by name, finishes, and quits through the menu', () {
    expect(run('G TRADER'), contains('Micro Trader'));
    expect(BbsGames.isPlaying(session), isTrue);
    expect(run('finish'), contains('Final credits: 500. Profit: 0.'));
    expect(BbsGames.isPlaying(session), isFalse);
    expect(run('G Micro'), contains('Micro Trader'));
    expect(run('QUIT'), contains('Back to the BBS'));
    expect(BbsGames.isPlaying(session), isFalse);
  });

  int price(String market, String good) =>
      int.parse(RegExp('$good: (\\d+) cr').firstMatch(market)!.group(1)!);

  test('Micro Trader trades at arrival prices and liquidates cargo', () {
    final game = MicroTraderGame(math.Random(4));
    final initial = game.start();
    final buyPrice = price(initial, 'Food');
    expect(game.play('buy food 10'), contains('Cargo 10/20'));
    expect(game.play('JUMP forge'), contains('Flights 1/10'));
    final market = game.play('MARKET');
    final sellPrice = price(market, 'Food');
    expect(sellPrice, greaterThan(buyPrice));
    expect(game.play('SELL 1 4'), contains('Sold 4 Food'));
    expect(game.play('MARKET'), contains('aboard 6'));
    final credits = 500 - buyPrice * 10 + sellPrice * 10;
    expect(
      game.play('FINISH'),
      contains('Final credits: $credits. Profit: ${credits - 500}.'),
    );
    expect(game.isOver, isTrue);
    expect(game.play('FINISH'), contains('has ended'));
  });

  test('Micro Trader rejects invalid trades without changing the market', () {
    final game = MicroTraderGame(math.Random(2));
    game.start();
    final market = game.play('MARKET');
    for (final command in [
      'BUY',
      'BUY gold 1',
      'BUY Food 0',
      'BUY Food -1',
      'BUY Food nope',
      'BUY Food 1.5',
      'BUY Food 9223372036854775807',
      'BUY Meds 20',
      'SELL Food 1',
      'FUEL -1',
      'FUEL 3',
      'JUMP Outpost',
      'JUMP nowhere',
      'JUMP 5',
      'HELP extra',
    ]) {
      expect(game.play(command), isNotEmpty, reason: command);
      expect(game.play('MARKET'), market, reason: command);
      expect(game.isOver, isFalse);
    }
    expect(game.play('BUY Food 20'), contains('Cargo 20/20'));
    expect(game.play('BUY Parts 1'), contains('Not enough cargo space'));
    expect(game.play('SELL Food 21'), contains('Not enough Food aboard'));
    expect(game.play('SELL Food 20'), contains('Credits 500'));
  });

  test('Micro Trader consumes fuel and charges for refills', () {
    final game = MicroTraderGame(math.Random(3));
    game.start();
    expect(game.play('JUMP 4'), contains('Fuel 1/6'));
    final market = game.play('MARKET');
    expect(game.play('JUMP 1'), contains('Not enough fuel; need 3'));
    expect(game.play('MARKET'), market);
    expect(game.play('FUEL 5'), contains('Credits 475'));
    expect(game.play('STATUS'), contains('Fuel 6/6'));
    expect(game.play('JUMP 1'), contains('Fuel 3/6'));
    expect(game.play('STATUS'), contains('Flights 2/10'));
    expect(game.play('HELP'), contains('FINISH'));
  });

  test('Micro Trader enforces credits for cargo and fuel', () {
    final game = MicroTraderGame(math.Random(9));
    final market = game.start();
    final unitPrice = price(market, 'Meds');
    final quantity = 500 ~/ unitPrice;
    expect(game.play('BUY Meds $quantity'), contains('Bought'));
    expect(game.play('BUY Meds 1'), contains('Not enough credits'));
    var remaining = 500 - quantity * unitPrice;
    final foodPrice = price(market, 'Food');
    final food = remaining ~/ foodPrice;
    if (food > 0) {
      expect(game.play('BUY Food $food'), contains('Bought'));
      remaining -= food * foodPrice;
    }
    game.play('JUMP Forge');
    final fuel = remaining ~/ 5;
    if (fuel > 0) {
      expect(game.play('FUEL $fuel'), contains('Added $fuel fuel'));
    }
    game.play('JUMP Haven');
    final before = game.play('MARKET');
    expect(game.play('FUEL 1'), contains('Not enough credits'));
    expect(game.play('MARKET'), before);
  });

  test('Micro Trader ends at ten flights and returns to the BBS', () {
    run('G TRADER');
    for (var flight = 1; flight <= 10; flight++) {
      run('FUEL 1');
      final text = run(flight.isOdd ? 'JUMP Forge' : 'JUMP Outpost');
      if (flight < 10) {
        expect(text, contains('Flights $flight/10'));
        expect(BbsGames.isPlaying(session), isTrue);
      } else {
        expect(text, contains('Flight limit reached'));
        expect(text, contains('Final credits: 450. Profit: -50.'));
        expect(text, contains('Back to the BBS'));
        expect(BbsGames.isPlaying(session), isFalse);
      }
    }
  });

  test('Packet Adventure can be solved through the BBS menu', () {
    expect(run('G ADVENTURE'), contains('Trailhead'));
    expect(run(' take   battery '), contains('Taken: BATTERY'));
    expect(run('go north'), contains('Cabin'));
    final note = run('read note');
    final code = RegExp(r'Controller code: (\d+)').firstMatch(note)!.group(1)!;
    expect(run('E'), contains('Workshop'));
    for (final item in ['key', 'fuse', 'cable']) {
      expect(run('TAKE $item'), contains('Taken: ${item.toUpperCase()}'));
    }
    run('W');
    expect(run('USE KEY'), contains('unlock'));
    run('N');
    expect(run('USE FUSE'), contains('FUSE installed'));
    expect(run('USE BATTERY'), contains('controller lights up'));
    expect(run('CODE $code'), contains('Controller unlocked'));
    run('E');
    expect(run('USE CABLE'), contains('CABLE installed'));
    run('W');
    final win = run('TRANSMIT');
    expect(win, contains('ACK from the valley BBS'));
    expect(win, contains('You win!'));
    expect(win, contains('Back to the BBS'));
    expect(BbsGames.isPlaying(session), isFalse);
    expect(run('M'), contains('[G]ames'));
  });

  test('Packet Adventure rejects invalid actions without losing items', () {
    final game = PacketAdventureGame(math.Random(2));
    game.start();
    expect(game.play('GO WEST'), contains('No exit'));
    expect(game.play('TAKE KEY'), contains('No such item'));
    expect(game.play('EXAMINE NOTE'), contains('Nothing by that name'));
    expect(game.play('INVENTORY'), contains('nothing'));
    expect(game.play('TAKE BATTERY'), contains('Taken'));
    expect(game.play('USE BATTERY'), contains('cannot be used here'));
    expect(game.play('TAKE BATTERY'), contains('already have'));
    expect(game.play('INVENTORY'), contains('BATTERY'));
    expect(game.play('EXAMINE BATTERY'), contains('charged battery'));
    game.play('N');
    expect(game.play('N'), contains('locked'));
    expect(game.play('LOOK'), contains('Cabin'));
    game.play('E');
    game.play('GET KEY');
    game.play('TAKE FUSE');
    game.play('TAKE CABLE');
    game.play('W');
    game.play('USE KEY');
    expect(game.play('USE KEY'), contains('already unlocked'));
    game.play('N');
    expect(game.play('USE CABLE'), contains('cannot be used here'));
    expect(game.play('USE BATTERY'), contains('installed'));
    expect(game.play('USE BATTERY'), contains('not carrying'));
    expect(game.play('I'), isNot(contains('BATTERY')));
    expect(game.play('I'), contains('CABLE'));
    expect(game.play('I'), contains('FUSE'));
    expect(game.play('TAKE FUSE'), contains('already have'));
    expect(game.play('DANCE'), contains('Unknown command'));
    expect(game.play('GO'), contains('No exit'));
    expect(game.play('TRANSMIT extra'), contains('without arguments'));
    expect(game.isOver, isFalse);
  });

  test('Packet Adventure requires every repair before transmitting', () {
    final game = PacketAdventureGame(math.Random(3));
    game.start();
    expect(game.play('TRANSMIT'), contains('from the radio shack'));
    expect(game.play('CODE 123'), contains('in the radio shack'));
    game.play('TAKE BATTERY');
    game.play('N');
    final note = game.play('LOOK NOTE');
    final code = RegExp(r'Controller code: (\d+)').firstMatch(note)!.group(1)!;
    game.play('E');
    for (final item in ['KEY', 'FUSE', 'CABLE']) {
      game.play('TAKE $item');
    }
    game.play('W');
    game.play('USE KEY');
    game.play('N');
    expect(game.play('CODE $code'), contains('power first'));
    expect(game.play('TRANSMIT'), contains('BATTERY and FUSE'));
    game.play('USE BATTERY');
    expect(game.play('TRANSMIT'), contains('BATTERY and FUSE'));
    game.play('USE FUSE');
    expect(game.play('EXAMINE REPEATER'), contains('controller: locked'));
    expect(game.play('CODE 000'), contains('Code rejected'));
    expect(game.play('TRANSMIT'), contains('CABLE needs replacing'));
    game.play('E');
    game.play('USE CABLE');
    expect(game.play('TRANSMIT'), contains('from the radio shack'));
    game.play('W');
    expect(game.play('TRANSMIT'), contains('CODE <digits>'));
    expect(game.isOver, isFalse);
    game.play('CODE $code');
    expect(game.play('EXAMINE REPEATER'), contains('controller: ready'));
    expect(game.play('HINT'), contains('TRANSMIT'));
    expect(game.play('TRANSMIT'), contains('You win'));
    expect(game.isOver, isTrue);
    expect(game.play('TRANSMIT'), contains('has ended'));
  });

  test('Packet Adventure sessions are isolated and can be restarted', () {
    run('G Packet');
    run('TAKE BATTERY');
    final otherSession = <String, Object?>{};
    menu.handleLine('W2AW', 'G ADVENTURE', session: otherSession);
    final other = menu.handleLine('W2AW', 'I', session: otherSession);
    expect((other as BbsMenuReply).text, contains('carrying nothing'));
    expect(run('I'), contains('BATTERY'));
    expect(run('HELP'), contains('TAKE <item>'));
    expect(run('HINT'), contains('KEY'));
    expect(run('EXIT'), contains('Back to the BBS'));
    run('G 6');
    expect(run('I'), contains('carrying nothing'));
    expect(run('LOOK'), contains('Items: BATTERY'));
    expect(run('QUIT'), contains('Back to the BBS'));
  });
}
