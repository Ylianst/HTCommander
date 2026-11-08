/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Simple text games for the BBS menu (see bbs_menu.dart). Replies are kept short
for slow radio links. While a game is running, every line the caller sends goes
to the game until it ends or the caller types QUIT.
*/

import 'dart:math' as math;

import 'bbs_settings.dart';

/// A text game played one line at a time.
abstract class BbsGame {
  /// Text sent when the game starts.
  String start();

  /// Handles a line typed by the player and returns the reply.
  String play(String input);

  /// The game ended; the caller is back to the BBS menu.
  bool get isOver;
}

class _GameInfo {
  const _GameInfo(this.key, this.name, this.description, this.create);

  final String key;
  final String name;
  final String description;
  final BbsGame Function(math.Random random) create;
}

/// The BBS games menu and the routing of lines to a running game. The running
/// game is kept in the session state map of each client.
class BbsGames {
  BbsGames(this._random);

  final math.Random _random;

  /// Session state key of the running game.
  static const String sessionKey = 'bbsGame';

  static final List<_GameInfo> _games = [
    _GameInfo(
      'GUESS',
      'Guess the number',
      'Find the number from 1 to 100',
      GuessNumberGame.new,
    ),
    _GameInfo(
      'HANGMAN',
      'Hangman',
      'Guess the ham radio word',
      HangmanGame.new,
    ),
    _GameInfo(
      'MORSE',
      'Morse quiz',
      'Decode ${MorseQuizGame.rounds} Morse code words',
      MorseQuizGame.new,
    ),
    _GameInfo(
      'TTT',
      'Tic-tac-toe',
      'Beat the BBS at tic-tac-toe',
      TicTacToeGame.new,
    ),
  ];

  static const String _quitHint = 'Type QUIT to leave the game.\r';
  static const String _back = 'Back to the BBS, [M] for menu.\r';

  /// Every game, enabled or not, for the sysop settings.
  static List<({String key, String name})> get all => [
    for (final g in _games) (key: g.key, name: g.name),
  ];

  /// The games the sysop left enabled.
  static List<_GameInfo> get _enabled {
    final settings = BbsSettings.load();
    return _games.where((g) => settings.isGameEnabled(g.key)).toList();
  }

  /// Whether at least one game can be played.
  static bool get anyEnabled => _enabled.isNotEmpty;

  /// True when a game is running in [session].
  static bool isPlaying(Map<String, Object?> session) =>
      session[sessionKey] is BbsGame;

  /// The `G [game]` command: lists the games, or starts the one named by
  /// [arg] (number or name).
  String command(Map<String, Object?> session, String arg) {
    final games = _enabled;
    if (games.isEmpty) return 'Games are not available on this BBS.\r';
    if (arg.isEmpty) return _list(games);
    final a = arg.trim().toUpperCase();
    final n = int.tryParse(a);
    _GameInfo? info;
    if (n != null && n >= 1 && n <= games.length) {
      info = games[n - 1];
    } else {
      for (final g in games) {
        if (g.key.startsWith(a) || g.name.toUpperCase().startsWith(a)) {
          info = g;
          break;
        }
      }
    }
    if (info == null) return 'Game $arg not found.\r${_list(games)}';
    final game = info.create(_random);
    session[sessionKey] = game;
    return '--- ${info.name} ---\r$_quitHint${game.start()}';
  }

  /// Sends [line] to the game running in [session].
  String play(Map<String, Object?> session, String line) {
    final game = session[sessionKey];
    if (game is! BbsGame) return _back;
    final input = line.trim();
    final upper = input.toUpperCase();
    if (upper == 'QUIT' || upper == 'EXIT') {
      session.remove(sessionKey);
      return 'Game over.\r$_back';
    }
    final text = game.play(input);
    if (!game.isOver) return text;
    session.remove(sessionKey);
    return '$text$_back';
  }

  String _list(List<_GameInfo> games) {
    final sb = StringBuffer('Games:\r');
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      sb.write('${i + 1} ${g.name.padRight(18)} ${g.description}\r');
    }
    sb.write('G <#> to play.\r');
    return sb.toString();
  }
}

// ---- guess the number -------------------------------------------------------

/// Find a number from 1 to [max], told after each try if it is higher or lower.
class GuessNumberGame implements BbsGame {
  GuessNumberGame(math.Random random) : _secret = random.nextInt(max) + 1;

  static const int max = 100;

  final int _secret;
  int _tries = 0;
  bool _over = false;

  @override
  bool get isOver => _over;

  @override
  String start() => 'I picked a number from 1 to $max. Your guess?\r';

  @override
  String play(String input) {
    final n = int.tryParse(input);
    if (n == null || n < 1 || n > max) {
      return 'Enter a number from 1 to $max.\r';
    }
    _tries++;
    if (n < _secret) return '$n is too low.\r';
    if (n > _secret) return '$n is too high.\r';
    _over = true;
    return _tries == 1
        ? 'Lucky! $n on the first try!\r'
        : 'You got it, $n in $_tries tries.\r';
  }
}

// ---- hangman ----------------------------------------------------------------

/// Guess a ham radio word one letter at a time, before [maxMisses] misses.
class HangmanGame implements BbsGame {
  HangmanGame(math.Random random, {String? word})
    : _word = word ?? words[random.nextInt(words.length)];

  static const int maxMisses = 6;

  static const List<String> words = [
    'ANTENNA',
    'REPEATER',
    'CALLSIGN',
    'SIMPLEX',
    'DUPLEX',
    'SQUELCH',
    'PROPAGATION',
    'FREQUENCY',
    'MODULATION',
    'BANDWIDTH',
    'DIPOLE',
    'TRANSCEIVER',
    'AMPLIFIER',
    'IONOSPHERE',
    'WAVELENGTH',
    'IMPEDANCE',
    'OSCILLATOR',
    'HANDHELD',
    'BEACON',
    'CONTEST',
    'TELEGRAPH',
    'SATELLITE',
    'COAXIAL',
    'GROUNDPLANE',
    'PACKET',
    'LOGBOOK',
    'ELMER',
    'MICROPHONE',
  ];

  final String _word;
  final Set<String> _guessed = {};
  final List<String> _misses = [];
  bool _over = false;

  @override
  bool get isOver => _over;

  bool get _solved => _word.split('').every(_guessed.contains);

  String get _status {
    final shown = _word.split('').map((c) => _guessed.contains(c) ? c : '_');
    final misses = _misses.isEmpty ? '' : ' ${_misses.join()}';
    return '${shown.join(' ')}  Misses ${_misses.length}/$maxMisses$misses\r';
  }

  @override
  String start() => '${_status}Guess a letter, or the whole word.\r';

  @override
  String play(String input) {
    final guess = input.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[A-Z]+$').hasMatch(guess)) {
      return 'Guess a letter, or the whole word.\r';
    }
    if (guess.length > 1) {
      if (guess == _word) {
        _over = true;
        return 'Yes, the word was $_word. You win!\r';
      }
      return _miss('$guess is not the word.\r', '?');
    }
    if (!_guessed.add(guess)) return 'You already tried $guess.\r$_status';
    if (!_word.contains(guess)) return _miss('No $guess.\r', guess);
    if (_solved) {
      _over = true;
      return 'Yes, the word was $_word. You win!\r';
    }
    return _status;
  }

  /// Counts a miss, shown as [mark] in the status line.
  String _miss(String text, String mark) {
    _misses.add(mark);
    if (_misses.length >= maxMisses) {
      _over = true;
      return '${text}Out of tries, the word was $_word.\r';
    }
    return '$text$_status';
  }
}

// ---- Morse quiz -------------------------------------------------------------

/// Decode [rounds] short words and abbreviations sent in Morse code.
class MorseQuizGame implements BbsGame {
  MorseQuizGame(math.Random random) {
    final pool = List<String>.of(words)..shuffle(random);
    _questions = pool.take(rounds).toList();
  }

  static const int rounds = 5;

  static const List<String> words = [
    'CQ',
    'DE',
    'QTH',
    'QSL',
    'QRZ',
    'QRM',
    'QSO',
    'RST',
    'SOS',
    '73',
    '88',
    'HAM',
    'RIG',
    'ANT',
    'WX',
    'TNX',
    'FB',
    'OM',
    'YL',
    'NAME',
    'DX',
    'BK',
    'AGN',
    'PSE',
  ];

  static const Map<String, String> code = {
    'A': '.-',
    'B': '-...',
    'C': '-.-.',
    'D': '-..',
    'E': '.',
    'F': '..-.',
    'G': '--.',
    'H': '....',
    'I': '..',
    'J': '.---',
    'K': '-.-',
    'L': '.-..',
    'M': '--',
    'N': '-.',
    'O': '---',
    'P': '.--.',
    'Q': '--.-',
    'R': '.-.',
    'S': '...',
    'T': '-',
    'U': '..-',
    'V': '...-',
    'W': '.--',
    'X': '-..-',
    'Y': '-.--',
    'Z': '--..',
    '0': '-----',
    '1': '.----',
    '2': '..---',
    '3': '...--',
    '4': '....-',
    '5': '.....',
    '6': '-....',
    '7': '--...',
    '8': '---..',
    '9': '----.',
  };

  /// [text] in Morse code, letters separated by spaces.
  static String encode(String text) =>
      text.toUpperCase().split('').map((c) => code[c] ?? '').join(' ');

  late final List<String> _questions;
  int _round = 0;
  int _score = 0;

  @override
  bool get isOver => _round >= _questions.length;

  String get _question =>
      'Word ${_round + 1}/${_questions.length}: '
      '${encode(_questions[_round])}\r';

  @override
  String start() => _question;

  @override
  String play(String input) {
    final answer = input.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (answer.isEmpty) return _question;
    final word = _questions[_round];
    final String result;
    if (answer == word) {
      _score++;
      result = 'Correct!\r';
    } else {
      result = 'No, it was $word.\r';
    }
    _round++;
    if (!isOver) return '$result$_question';
    return '${result}Score: $_score/${_questions.length}.\r';
  }
}

// ---- tic-tac-toe ------------------------------------------------------------

/// Tic-tac-toe, the player is X and moves first.
class TicTacToeGame implements BbsGame {
  TicTacToeGame(this._random);

  final math.Random _random;
  final List<String?> _board = List.filled(9, null);
  bool _over = false;

  static const List<List<int>> _lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  @override
  bool get isOver => _over;

  String get _boardText {
    String cell(int i) => _board[i] ?? '${i + 1}';
    String row(int r) =>
        ' ${cell(r * 3)} | ${cell(r * 3 + 1)} | ${cell(r * 3 + 2)}\r';
    return '${row(0)}---+---+---\r${row(1)}---+---+---\r${row(2)}';
  }

  @override
  String start() => '${_boardText}You are X. Your move (1-9)?\r';

  @override
  String play(String input) {
    final n = int.tryParse(input);
    if (n == null || n < 1 || n > 9) return 'Enter a square from 1 to 9.\r';
    if (_board[n - 1] != null) return 'Square $n is taken.\r';
    _board[n - 1] = 'X';
    if (_winner() == 'X') return _end('You win!\r');
    if (_full) return _end('Draw.\r');
    final move = _computerMove();
    _board[move] = 'O';
    if (_winner() == 'O') return _end('I play ${move + 1}. I win!\r');
    if (_full) return _end('I play ${move + 1}. Draw.\r');
    return 'I play ${move + 1}.\r${_boardText}Your move?\r';
  }

  String _end(String text) {
    _over = true;
    return '$_boardText$text';
  }

  bool get _full => !_board.contains(null);

  String? _winner() {
    for (final l in _lines) {
      final a = _board[l[0]];
      if (a != null && a == _board[l[1]] && a == _board[l[2]]) return a;
    }
    return null;
  }

  /// Wins if it can, blocks the player, else takes the center, a corner or
  /// any square. Picks at random among equal choices so games vary.
  int _computerMove() {
    for (final mark in ['O', 'X']) {
      for (final l in _lines) {
        final marks = l.where((i) => _board[i] == mark).length;
        final empty = l.where((i) => _board[i] == null).toList();
        if (marks == 2 && empty.length == 1) return empty.first;
      }
    }
    if (_board[4] == null) return 4;
    final free = [
      for (var i = 0; i < 9; i++)
        if (_board[i] == null) i,
    ];
    final corners = free.where((i) => i != 4 && i.isEven).toList();
    final pick = corners.isNotEmpty ? corners : free;
    return pick[_random.nextInt(pick.length)];
  }
}
