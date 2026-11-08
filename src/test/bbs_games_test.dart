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
}
