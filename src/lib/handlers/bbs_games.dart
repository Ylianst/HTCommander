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
    _GameInfo(
      'TRADER',
      'Micro Trader',
      'Trade cargo between space stations',
      MicroTraderGame.new,
    ),
    _GameInfo(
      'ADVENTURE',
      'Packet Adventure',
      'Restore a remote repeater',
      PacketAdventureGame.new,
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

// ---- Packet Adventure ------------------------------------------------------

enum _AdventureRoom { trail, cabin, workshop, shack, mast }

/// A small, forgiving adventure with tools and clues to restore a repeater.
class PacketAdventureGame implements BbsGame {
  PacketAdventureGame(math.Random random)
    : _accessCode = '${100 + random.nextInt(900)}';

  static const String _help =
      'LOOK, N/S/E/W (or GO NORTH/SOUTH/EAST/WEST)\r'
      'TAKE <item>, USE <item>, EXAMINE <item>, INVENTORY\r'
      'CODE <digits>, TRANSMIT, HINT, HELP, QUIT\r'
      'Restore the repeater and send a test packet. No move or time limit.\r';
  static const Map<_AdventureRoom, Map<String, _AdventureRoom>> _routes = {
    _AdventureRoom.trail: {'NORTH': _AdventureRoom.cabin},
    _AdventureRoom.cabin: {
      'SOUTH': _AdventureRoom.trail,
      'EAST': _AdventureRoom.workshop,
      'NORTH': _AdventureRoom.shack,
    },
    _AdventureRoom.workshop: {'WEST': _AdventureRoom.cabin},
    _AdventureRoom.shack: {
      'SOUTH': _AdventureRoom.cabin,
      'EAST': _AdventureRoom.mast,
    },
    _AdventureRoom.mast: {'WEST': _AdventureRoom.shack},
  };
  static const Map<String, String> _directions = {
    'N': 'NORTH',
    'S': 'SOUTH',
    'E': 'EAST',
    'W': 'WEST',
  };
  static const Map<String, String> _itemDescriptions = {
    'KEY': 'A brass key tagged "radio shack".',
    'BATTERY': 'A charged battery module for the repeater.',
    'FUSE': 'A replacement fuse module for the repeater.',
    'CABLE': 'A replacement antenna cable for the mast.',
  };

  final String _accessCode;
  final Set<String> _inventory = {};
  final Map<String, _AdventureRoom> _items = {
    'BATTERY': _AdventureRoom.trail,
    'KEY': _AdventureRoom.workshop,
    'FUSE': _AdventureRoom.workshop,
    'CABLE': _AdventureRoom.workshop,
  };
  _AdventureRoom _room = _AdventureRoom.trail;
  bool _unlocked = false;
  bool _batteryInstalled = false;
  bool _fuseInstalled = false;
  bool _cableInstalled = false;
  bool _controllerReady = false;
  bool _over = false;

  @override
  bool get isOver => _over;

  bool get _powered => _batteryInstalled && _fuseInstalled;

  @override
  String start() =>
      'A storm silenced Pine Ridge repeater. Restore its packet link!\r'
      '$_help${_look()}';

  String _look() {
    final description = switch (_room) {
      _AdventureRoom.trail =>
        'Trailhead: a supply crate sits beside the path to the cabin.',
      _AdventureRoom.cabin =>
        'Cabin: a NOTE lies on the desk. The radio shack is north'
            '${_unlocked ? ' (unlocked)' : ' (locked)'}.',
      _AdventureRoom.workshop =>
        'Workshop: spare repeater modules are stored here.',
      _AdventureRoom.shack =>
        'Radio shack: the REPEATER is ${_powered ? 'powered' : 'without power'}.'
            ' The antenna mast is east.',
      _AdventureRoom.mast =>
        'Antenna mast: the antenna cable is '
            '${_cableInstalled ? 'replaced' : 'damaged'}.',
    };
    final items = _items.entries
        .where((entry) => entry.value == _room)
        .map((entry) => entry.key)
        .join(', ');
    return '$description\r'
        '${items.isEmpty ? '' : 'Items: $items\r'}'
        'Exits: ${_routes[_room]!.keys.join(', ')}\r';
  }

  @override
  String play(String input) {
    if (_over) return 'This adventure has ended.\r';
    final words = input.trim().toUpperCase().split(RegExp(r'\s+'));
    final command = words.first;
    final arg = words.skip(1).join(' ');
    final direction = _directions[command] ?? command;
    if (arg.isEmpty && _directions.containsValue(direction)) {
      return _go(direction);
    }
    switch (command) {
      case '':
      case 'LOOK':
      case 'L':
        return arg.isEmpty ? _look() : _examine(arg);
      case 'HELP':
        return arg.isEmpty ? _help : 'Use HELP without arguments.\r';
      case 'INVENTORY':
      case 'I':
        if (arg.isNotEmpty) return 'Use INVENTORY without arguments.\r';
        return _inventory.isEmpty
            ? 'You are carrying nothing.\r'
            : 'Carrying: ${_inventory.join(', ')}\r';
      case 'GO':
        return _go(_directions[arg] ?? arg);
      case 'TAKE':
      case 'GET':
        if (_inventory.contains(arg)) return 'You already have $arg.\r';
        if (!_items.containsKey(arg) || _items[arg] != _room) {
          return 'No such item here. Use LOOK to see items.\r';
        }
        _items.remove(arg);
        _inventory.add(arg);
        return 'Taken: $arg.\r';
      case 'EXAMINE':
      case 'READ':
        return _examine(arg);
      case 'USE':
        return _use(arg);
      case 'CODE':
        if (_room != _AdventureRoom.shack) {
          return 'The controller is in the radio shack.\r';
        }
        if (!_powered) return 'The controller needs power first.\r';
        if (arg != _accessCode) {
          return 'Code rejected. Read the NOTE in the cabin.\r';
        }
        _controllerReady = true;
        return 'Controller unlocked. Send a test with TRANSMIT.\r';
      case 'TRANSMIT':
        if (arg.isNotEmpty) return 'Use TRANSMIT without arguments.\r';
        if (_room != _AdventureRoom.shack) {
          return 'Send the test packet from the radio shack.\r';
        }
        if (!_powered) return 'The repeater needs a BATTERY and FUSE.\r';
        if (!_cableInstalled) return 'The antenna CABLE needs replacing.\r';
        if (!_controllerReady) {
          return 'Unlock the controller with CODE <digits>.\r';
        }
        _over = true;
        return 'Test packet sent... ACK from the valley BBS!\r'
            'Pine Ridge repeater is back online. You win!\r';
      case 'HINT':
        return arg.isEmpty ? _hint() : 'Use HINT without arguments.\r';
      default:
        return 'Unknown command. Type HELP for adventure commands.\r';
    }
  }

  String _go(String direction) {
    final destination = _routes[_room]![direction];
    if (destination == null) return 'No exit that way. Use LOOK for exits.\r';
    if (destination == _AdventureRoom.shack && !_unlocked) {
      return 'The radio shack is locked. Find a KEY and USE KEY in the cabin.\r';
    }
    _room = destination;
    return _look();
  }

  String _examine(String item) {
    if (item == 'NOTE' && _room == _AdventureRoom.cabin) {
      return 'NOTE: Spares are in the workshop; battery at the trailhead.\r'
          'USE BATTERY and USE FUSE in the shack; USE CABLE at the mast.\r'
          'Controller code: $_accessCode. Enter CODE $_accessCode in the shack,\r'
          'then TRANSMIT a test packet after all repairs.\r';
    }
    if (item == 'REPEATER' && _room == _AdventureRoom.shack) {
      return 'Battery: ${_batteryInstalled ? 'installed' : 'missing'}; '
          'fuse: ${_fuseInstalled ? 'installed' : 'blown'}.\r'
          'Antenna cable: ${_cableInstalled ? 'replaced' : 'damaged'}; '
          'controller: ${_controllerReady ? 'ready' : 'locked'}.\r';
    }
    if (_inventory.contains(item) || _items[item] == _room) {
      return '${_itemDescriptions[item]}\r';
    }
    return 'Nothing by that name here. Try LOOK or INVENTORY.\r';
  }

  String _use(String item) {
    if (!_inventory.contains(item)) return 'You are not carrying that item.\r';
    final location = switch (item) {
      'KEY' => _AdventureRoom.cabin,
      'BATTERY' || 'FUSE' => _AdventureRoom.shack,
      'CABLE' => _AdventureRoom.mast,
      _ => null,
    };
    if (_room != location) {
      return 'That item cannot be used here. EXAMINE $item for a clue.\r';
    }
    switch (item) {
      case 'KEY':
        if (_unlocked) return 'The radio shack is already unlocked.\r';
        _unlocked = true;
        return 'You unlock the radio shack door to the north.\r';
      case 'BATTERY':
        _batteryInstalled = true;
      case 'FUSE':
        _fuseInstalled = true;
      case 'CABLE':
        _cableInstalled = true;
    }
    _inventory.remove(item);
    return '$item installed.\r'
        '${_powered && _room == _AdventureRoom.shack ? 'The controller lights up. Enter CODE <digits>.\r' : ''}';
  }

  String _hint() {
    if (!_unlocked) {
      return 'From the cabin, go EAST to the workshop for the KEY.\r'
          'Return WEST and USE KEY to unlock the shack to the NORTH.\r';
    }
    if (!_batteryInstalled) {
      return 'TAKE BATTERY at the trailhead, south of the cabin.\r'
          'USE BATTERY in the radio shack.\r';
    }
    if (!_fuseInstalled) {
      return 'TAKE FUSE in the workshop; USE FUSE in the radio shack.\r';
    }
    if (!_cableInstalled) {
      return 'TAKE CABLE in the workshop; USE CABLE at the mast, east of the shack.\r';
    }
    if (!_controllerReady) {
      return 'READ NOTE in the cabin for the controller CODE. Enter it in the shack.\r';
    }
    return 'Return to the radio shack and TRANSMIT the test packet!\r';
  }
}

// ---- Micro Trader ----------------------------------------------------------

/// Trade cargo for up to ten flights. Prices change only on arrival.
class MicroTraderGame implements BbsGame {
  MicroTraderGame(this._random) {
    _updatePrices();
  }

  static const int maxFlights = 10;
  static const int cargoCapacity = 20;
  static const int tankCapacity = 6;
  static const int fuelPrice = 5;
  static const int startingCredits = 500;
  static const List<String> _stations = ['Outpost', 'Forge', 'Haven', 'Relay'];
  static const List<String> _goods = ['Food', 'Parts', 'Meds'];
  static const List<List<int>> _basePrices = [
    [12, 38, 55],
    [26, 20, 70],
    [18, 45, 30],
    [22, 30, 45],
  ];

  static const String _help =
      'BUY <good> <qty>, SELL <good> <qty>\r'
      'JUMP <station>, FUEL <qty>, MARKET, STATUS, HELP, FINISH\r'
      'Goods/stations: name or number. Fuel: 5 credits/unit.\r'
      'Each flight uses the listed fuel. No time limit per turn.\r'
      'After 10 flights (or FINISH), cargo sells at local prices.\r'
      'Score = credits minus starting 500. Unused fuel has no resale value.\r';

  final math.Random _random;
  final List<int> _cargo = [0, 0, 0];
  late List<int> _prices;
  int _station = 0;
  int _credits = startingCredits;
  int _fuel = 4;
  int _flights = 0;
  bool _over = false;

  @override
  bool get isOver => _over;

  int get _load => _cargo.fold(0, (sum, quantity) => sum + quantity);

  String get _status =>
      '${_stations[_station]} | Flights $_flights/$maxFlights | '
      'Credits $_credits\r'
      'Cargo $_load/$cargoCapacity | Fuel $_fuel/$tankCapacity\r';

  String get _market {
    final text = StringBuffer(_status);
    for (var i = 0; i < _goods.length; i++) {
      text.write(
        '${i + 1} ${_goods[i]}: ${_prices[i]} cr, aboard ${_cargo[i]}\r',
      );
    }
    text.write('Stations (fuel):\r');
    for (var i = 0; i < _stations.length; i++) {
      if (i != _station) {
        text.write('${i + 1} ${_stations[i]} (${(i - _station).abs()})\r');
      }
    }
    return text.toString();
  }

  @override
  String start() =>
      'Buy low, sell high! You have 500 credits and 10 flights.\r'
      '$_help$_market';

  @override
  String play(String input) {
    if (_over) return 'This trading run has ended.\r';
    final args = input.trim().toUpperCase().split(RegExp(r'\s+'));
    final command = args.first;
    if (args.length == 1) {
      switch (command) {
        case 'HELP':
          return _help;
        case 'STATUS':
          return _status;
        case '':
        case 'MARKET':
          return _market;
        case 'FINISH':
          return _finish('Trading run complete.');
      }
    }
    switch (command) {
      case 'BUY':
      case 'SELL':
        return _trade(args, buying: command == 'BUY');
      case 'FUEL':
        return _refuel(args);
      case 'JUMP':
        return _jump(args);
      default:
        return 'Unknown command. Type HELP for trading commands.\r';
    }
  }

  int? _index(String input, List<String> names) {
    final number = int.tryParse(input);
    if (number != null && number >= 1 && number <= names.length) {
      return number - 1;
    }
    final index = names.indexWhere((name) => name.toUpperCase() == input);
    return index < 0 ? null : index;
  }

  String _trade(List<String> args, {required bool buying}) {
    final verb = buying ? 'BUY' : 'SELL';
    if (args.length != 3) return 'Use $verb <good> <positive qty>.\r';
    final good = _index(args[1], _goods);
    final quantity = int.tryParse(args[2]);
    if (good == null) return 'Unknown good. Use Food, Parts, Meds or 1-3.\r';
    if (quantity == null || quantity <= 0) {
      return 'Enter a positive whole quantity.\r';
    }
    if (buying) {
      if (quantity > cargoCapacity - _load) return 'Not enough cargo space.\r';
      // Compare before multiplying, so very large input cannot overflow.
      if (quantity > _credits ~/ _prices[good]) {
        return 'Not enough credits.\r';
      }
      _credits -= quantity * _prices[good];
      _cargo[good] += quantity;
    } else {
      if (quantity > _cargo[good]) {
        return 'Not enough ${_goods[good]} aboard.\r';
      }
      _credits += quantity * _prices[good];
      _cargo[good] -= quantity;
    }
    return '${buying ? 'Bought' : 'Sold'} $quantity ${_goods[good]} '
        'for ${quantity * _prices[good]} credits.\r$_status';
  }

  String _refuel(List<String> args) {
    if (args.length != 2) return 'Use FUEL <positive qty>.\r';
    final quantity = int.tryParse(args[1]);
    if (quantity == null || quantity <= 0) {
      return 'Enter a positive whole quantity.\r';
    }
    if (quantity > tankCapacity - _fuel) return 'Not enough tank space.\r';
    if (quantity > _credits ~/ fuelPrice) return 'Not enough credits.\r';
    _credits -= quantity * fuelPrice;
    _fuel += quantity;
    return 'Added $quantity fuel for ${quantity * fuelPrice} credits.\r$_status';
  }

  String _jump(List<String> args) {
    if (args.length != 2) return 'Use JUMP <station name or number>.\r';
    final destination = _index(args[1], _stations);
    if (destination == null) {
      return 'Unknown station. Type MARKET for routes.\r';
    }
    if (destination == _station) return 'You are already at that station.\r';
    final cost = (destination - _station).abs();
    if (_fuel < cost) return 'Not enough fuel; need $cost. Use FUEL <qty>.\r';
    _fuel -= cost;
    _station = destination;
    _flights++;
    _updatePrices();
    final arrival = 'Arrived at ${_stations[_station]}.\r';
    if (_flights >= maxFlights) {
      return '$arrival${_finish('Flight limit reached.')}';
    }
    if (_fuel == 0 && _credits < fuelPrice && _load == 0) {
      return '$arrival${_finish('Stranded without fuel or tradeable cargo.')}';
    }
    return '$arrival$_market';
  }

  void _updatePrices() {
    _prices = [
      for (final base in _basePrices[_station]) base + _random.nextInt(9) - 4,
    ];
  }

  String _finish(String reason) {
    var cargoValue = 0;
    for (var i = 0; i < _cargo.length; i++) {
      cargoValue += _cargo[i] * _prices[i];
      _cargo[i] = 0;
    }
    _credits += cargoValue;
    _over = true;
    final profit = _credits - startingCredits;
    return '$reason Cargo sold for $cargoValue credits.\r'
        'Final credits: $_credits. Profit: $profit.\r';
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
