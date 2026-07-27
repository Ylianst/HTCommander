/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Pure-Dart Morse-key model: the settings a USB morse key is configured with and
an iambic (Mode B) keyer state machine. Kept free of Flutter/dart:io imports so
it can be unit-tested and reused by both the handler and the UI.
*/

/// The kind of physical key attached over USB.
enum MorseKeyType { straight, paddle }

/// The keyboard keys a USB morse-key adapter can emit. USB morse keys present as
/// a HID keyboard; the common adapters press the bracket keys or the left/right
/// Control keys.
enum MorseKeyBinding { bracketLeft, bracketRight, controlLeft, controlRight }

/// The pair of keyboard keys a paddle's two levers use. A paddle is always wired
/// as a left/right pair, so we pick the pair rather than the two keys
/// separately.
enum MorseKeyPaddleGroup { brackets, control }

/// The current operating mode of the Morse Key panel.
enum MorseKeyMode { off, test, live }

/// A single timed Morse element produced by the keyer.
enum MorseElement { dit, dah }

/// Serializes a [MorseKeyType] to a stable string.
String morseKeyTypeToString(MorseKeyType t) =>
    t == MorseKeyType.paddle ? 'paddle' : 'straight';

/// Parses a [MorseKeyType], defaulting to straight.
MorseKeyType morseKeyTypeFromString(String? s) =>
    s == 'paddle' ? MorseKeyType.paddle : MorseKeyType.straight;

/// Serializes a [MorseKeyBinding] to a stable string.
String morseKeyBindingToString(MorseKeyBinding b) {
  switch (b) {
    case MorseKeyBinding.bracketLeft:
      return 'bracketLeft';
    case MorseKeyBinding.bracketRight:
      return 'bracketRight';
    case MorseKeyBinding.controlLeft:
      return 'controlLeft';
    case MorseKeyBinding.controlRight:
      return 'controlRight';
  }
}

/// Parses a [MorseKeyBinding], defaulting to [fallback].
MorseKeyBinding morseKeyBindingFromString(
  String? s, {
  MorseKeyBinding fallback = MorseKeyBinding.bracketLeft,
}) {
  switch (s) {
    case 'bracketLeft':
      return MorseKeyBinding.bracketLeft;
    case 'bracketRight':
      return MorseKeyBinding.bracketRight;
    case 'controlLeft':
      return MorseKeyBinding.controlLeft;
    case 'controlRight':
      return MorseKeyBinding.controlRight;
  }
  return fallback;
}

/// Serializes a [MorseKeyPaddleGroup] to a stable string.
String morseKeyPaddleGroupToString(MorseKeyPaddleGroup g) =>
    g == MorseKeyPaddleGroup.control ? 'control' : 'brackets';

/// Parses a [MorseKeyPaddleGroup], defaulting to brackets.
MorseKeyPaddleGroup morseKeyPaddleGroupFromString(String? s) =>
    s == 'control' ? MorseKeyPaddleGroup.control : MorseKeyPaddleGroup.brackets;

/// Serializes a [MorseKeyMode] to a stable string.
String morseKeyModeToString(MorseKeyMode m) {
  switch (m) {
    case MorseKeyMode.off:
      return 'off';
    case MorseKeyMode.test:
      return 'test';
    case MorseKeyMode.live:
      return 'live';
  }
}

/// Parses a [MorseKeyMode], defaulting to off.
MorseKeyMode morseKeyModeFromString(String? s) {
  switch (s) {
    case 'test':
      return MorseKeyMode.test;
    case 'live':
      return MorseKeyMode.live;
    default:
      return MorseKeyMode.off;
  }
}

/// Configuration for a USB morse key.
///
/// For a straight key only [straightBinding] is used (the single contact). For a
/// paddle, [paddleGroup] selects which pair of keyboard keys the two levers use,
/// and [paddleReversed] swaps the standard assignment. By convention the left
/// paddle sends dits (thumb) and the right paddle sends dahs (index finger);
/// reversing swaps that. [wpm] only affects the paddle keyer (a straight key is
/// timed entirely by the operator). [tailMs] is how long to keep the FM
/// transmitter keyed after the last element before dropping it. [toneHz] is the
/// sidetone/transmit pitch.
class MorseKeySettings {
  final MorseKeyType keyType;
  final MorseKeyBinding straightBinding;
  final MorseKeyPaddleGroup paddleGroup;
  final bool paddleReversed;
  final int wpm;
  final int tailMs;
  final int toneHz;

  const MorseKeySettings({
    this.keyType = MorseKeyType.straight,
    this.straightBinding = MorseKeyBinding.bracketLeft,
    this.paddleGroup = MorseKeyPaddleGroup.brackets,
    this.paddleReversed = false,
    this.wpm = 15,
    this.tailMs = 800,
    this.toneHz = 700,
  });

  MorseKeyBinding get _paddleLeftKey => paddleGroup == MorseKeyPaddleGroup.control
      ? MorseKeyBinding.controlLeft
      : MorseKeyBinding.bracketLeft;

  MorseKeyBinding get _paddleRightKey =>
      paddleGroup == MorseKeyPaddleGroup.control
          ? MorseKeyBinding.controlRight
          : MorseKeyBinding.bracketRight;

  /// The keyboard key of the dit contact. For a straight key this is the single
  /// contact; for a paddle it is the left lever (or the right lever when
  /// reversed).
  MorseKeyBinding get ditBinding {
    if (keyType == MorseKeyType.straight) return straightBinding;
    return paddleReversed ? _paddleRightKey : _paddleLeftKey;
  }

  /// The keyboard key of the dah contact (paddle only): the right lever, or the
  /// left lever when reversed.
  MorseKeyBinding get dahBinding =>
      paddleReversed ? _paddleLeftKey : _paddleRightKey;

  /// The primary contact key used by the UI to map keyboard events (the dit
  /// contact, or the single contact for a straight key).
  MorseKeyBinding get primaryBinding => ditBinding;

  /// The secondary contact key used by the UI to map keyboard events (the dah
  /// lever of a paddle).
  MorseKeyBinding get secondaryBinding => dahBinding;

  MorseKeySettings copyWith({
    MorseKeyType? keyType,
    MorseKeyBinding? straightBinding,
    MorseKeyPaddleGroup? paddleGroup,
    bool? paddleReversed,
    int? wpm,
    int? tailMs,
    int? toneHz,
  }) {
    return MorseKeySettings(
      keyType: keyType ?? this.keyType,
      straightBinding: straightBinding ?? this.straightBinding,
      paddleGroup: paddleGroup ?? this.paddleGroup,
      paddleReversed: paddleReversed ?? this.paddleReversed,
      wpm: wpm ?? this.wpm,
      tailMs: tailMs ?? this.tailMs,
      toneHz: toneHz ?? this.toneHz,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'keyType': morseKeyTypeToString(keyType),
        'straightBinding': morseKeyBindingToString(straightBinding),
        'paddleGroup': morseKeyPaddleGroupToString(paddleGroup),
        'paddleReversed': paddleReversed,
        'wpm': wpm,
        'tailMs': tailMs,
        'toneHz': toneHz,
      };

  factory MorseKeySettings.fromJson(Map<dynamic, dynamic> json) {
    int readInt(String key, int fallback) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return MorseKeySettings(
      keyType: morseKeyTypeFromString(json['keyType'] as String?),
      straightBinding: morseKeyBindingFromString(
        // Fall back to the legacy 'primaryBinding' key for older stored data.
        (json['straightBinding'] ?? json['primaryBinding']) as String?,
        fallback: MorseKeyBinding.bracketLeft,
      ),
      paddleGroup: morseKeyPaddleGroupFromString(
        json['paddleGroup'] as String?,
      ),
      paddleReversed: json['paddleReversed'] == true,
      wpm: readInt('wpm', 15).clamp(5, 60),
      tailMs: readInt('tailMs', 800).clamp(100, 5000),
      toneHz: readInt('toneHz', 700).clamp(300, 1200),
    );
  }
}

/// An iambic (Mode B) keyer.
///
/// Paddle contacts are pushed in with [setDit]/[setDah]; [next] is called at each
/// element boundary to obtain the element to send (or null when idle). A short
/// tap on the opposite paddle during an element is remembered (dit/dah memory)
/// and honored at the next boundary, and squeezing both paddles alternates
/// elements. This is deliberately transport-agnostic so it can be unit-tested.
class IambicKeyer {
  bool _ditDown = false;
  bool _dahDown = false;
  bool _ditMemory = false;
  bool _dahMemory = false;
  MorseElement? _last;

  /// Clears all paddle state and memory.
  void reset() {
    _ditDown = false;
    _dahDown = false;
    _ditMemory = false;
    _dahMemory = false;
    _last = null;
  }

  /// Updates the dit-lever state, latching memory on a fresh press.
  void setDit(bool down) {
    if (down && !_ditDown) _ditMemory = true;
    _ditDown = down;
  }

  /// Updates the dah-lever state, latching memory on a fresh press.
  void setDah(bool down) {
    if (down && !_dahDown) _dahMemory = true;
    _dahDown = down;
  }

  /// Whether the keyer has nothing pending to send.
  bool get idle =>
      !_ditDown && !_dahDown && !_ditMemory && !_dahMemory;

  /// Returns the next element to send, consuming any pending memory, or null when
  /// idle.
  MorseElement? next() {
    MorseElement? el;
    if (_ditDown && _dahDown) {
      // Squeeze: alternate from the last element sent.
      el = _last == MorseElement.dit ? MorseElement.dah : MorseElement.dit;
    } else if (_ditDown || _ditMemory) {
      el = MorseElement.dit;
    } else if (_dahDown || _dahMemory) {
      el = MorseElement.dah;
    }
    _ditMemory = false;
    _dahMemory = false;
    if (el != null) _last = el;
    return el;
  }
}

/// Decodes hand-sent Morse into text from a stream of mark (tone-on) and space
/// (tone-off) durations in milliseconds.
///
/// A dit is roughly one "unit" long and a dah three; the intra-element gap is
/// one unit, the inter-letter gap three, and the inter-word gap seven. When a
/// [fixedUnitMs] is supplied (e.g. from a paddle keyer's WPM) the classification
/// thresholds are exact; otherwise the unit length is estimated adaptively from
/// the incoming marks so a straight key sent by hand can still be decoded.
class MorseDecoder {
  MorseDecoder({int? fixedUnitMs})
      : _fixed = fixedUnitMs != null,
        _unitMs = (fixedUnitMs ?? 80).toDouble();

  final bool _fixed;
  double _unitMs;
  final StringBuffer _out = StringBuffer();
  final StringBuffer _symbol = StringBuffer();

  /// Reverse Morse table (code -> character).
  static final Map<String, String> _reverse = _buildReverse();

  static const Map<String, String> _forward = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
    'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
    'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
    'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
    'Y': '-.--', 'Z': '--..',
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
    '.': '.-.-.-', ',': '--..--', '?': '..--..', "'": '.----.', '!': '-.-.--',
    '/': '-..-.', '(': '-.--.', ')': '-.--.-', '&': '.-...', ':': '---...',
    ';': '-.-.-.', '=': '-...-', '+': '.-.-.', '-': '-....-', '_': '..--.-',
    '"': '.-..-.', '@': '.--.-.',
  };

  static Map<String, String> _buildReverse() {
    final m = <String, String>{};
    _forward.forEach((ch, code) => m[code] = ch);
    return m;
  }

  /// Feeds a completed mark (tone-on) of [ms] milliseconds.
  void onMark(int ms) {
    if (ms <= 0) return;
    final bool isDah = ms >= 2 * _unitMs;
    _symbol.write(isDah ? '-' : '.');
    if (!_fixed) {
      // Track the dit length so hand-keyed speed drift is followed.
      if (isDah) {
        _unitMs = _unitMs * 0.7 + (ms / 3.0) * 0.3;
      } else {
        _unitMs = _unitMs * 0.6 + ms * 0.4;
      }
      _unitMs = _unitMs.clamp(20.0, 600.0);
    }
  }

  /// Feeds a completed space (tone-off) of [ms] milliseconds between marks.
  void onSpace(int ms) {
    if (ms <= 0) return;
    if (ms < 2 * _unitMs) return; // intra-element gap: same letter continues
    _commitSymbol();
    if (ms >= 5 * _unitMs) {
      // Inter-word gap.
      final s = _out.toString();
      if (s.isNotEmpty && !s.endsWith(' ')) _out.write(' ');
    }
  }

  void _commitSymbol() {
    if (_symbol.isEmpty) return;
    final code = _symbol.toString();
    _symbol.clear();
    final ch = _reverse[code];
    if (ch != null) _out.write(ch);
  }

  /// Flushes any pending symbol and returns the decoded text (trimmed).
  String finish() {
    _commitSymbol();
    return _out.toString().trim();
  }

  /// The current estimated sending speed in words per minute. Exact when a fixed
  /// unit was supplied (a paddle keyer), and adaptively estimated from the marks
  /// for a hand-sent straight key.
  int get estimatedWpm => (1200.0 / _unitMs).round().clamp(1, 100);
}

