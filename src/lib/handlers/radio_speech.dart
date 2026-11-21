/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:collection';
import 'dart:typed_data';

/// Releases pre-roll when the neural detector opens, and ends on its
/// hysteretic silence decision. Input frames are 512 samples at 16 kHz.
class SpeechAudioGate {
  final Queue<Float32List> _preRoll = Queue();
  bool _active = false;

  ({List<Float32List> audio, bool ended}) process(
    Float32List frame,
    bool detected,
  ) {
    if (detected) {
      final audio = <Float32List>[if (!_active) ..._preRoll, frame];
      _preRoll.clear();
      _active = true;
      return (audio: audio, ended: false);
    }
    final ended = _active;
    _active = false;
    _preRoll.add(frame);
    while (_preRoll.length > 10) {
      _preRoll.removeFirst();
    }
    return (audio: const [], ended: ended);
  }

  void reset() {
    _preRoll.clear();
    _active = false;
  }
}

/// Tracks acknowledged audio, not elapsed wall time or model-buffer size.
class SpeechAudioBacklog {
  static const int limitSamples = 16000 * 10;
  int samples = 0;
  bool overloaded = false;

  bool enqueue(int count) {
    if (overloaded) return false;
    if (samples + count > limitSamples) {
      overloaded = true;
      return false;
    }
    samples += count;
    return true;
  }

  void acknowledge(int count) {
    samples = (samples - count).clamp(0, limitSamples);
    if (samples <= limitSamples ~/ 2) overloaded = false;
  }

  int get milliseconds => samples * 1000 ~/ 16000;
}

/// Only remove repeated words when audio overlap was deliberately retained.
String appendSpeechText(String previous, String next, {bool overlap = false}) {
  previous = previous.trim();
  next = next.trim();
  if (previous.isEmpty) return next;
  if (next.isEmpty) return previous;
  if (overlap) {
    final before = previous.split(RegExp(r'\s+'));
    final after = next.split(RegExp(r'\s+'));
    String key(String word) => word.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]', unicode: true),
      '',
    );
    for (var n = after.length.clamp(0, before.length); n > 0; n--) {
      var matches = true;
      for (var i = 0; i < n; i++) {
        final a = key(after[i]);
        if (a.isEmpty || a != key(before[before.length - n + i])) {
          matches = false;
          break;
        }
      }
      if (matches) {
        next = after.skip(n).join(' ');
        break;
      }
    }
  }
  return next.isEmpty ? previous : '$previous $next';
}

class RadioSpeechVocabulary {
  static const phonetics = <String, String>{
    'alpha': 'A',
    'alfa': 'A',
    'bravo': 'B',
    'charlie': 'C',
    'delta': 'D',
    'echo': 'E',
    'foxtrot': 'F',
    'golf': 'G',
    'hotel': 'H',
    'india': 'I',
    'juliet': 'J',
    'juliett': 'J',
    'kilo': 'K',
    'lima': 'L',
    'mike': 'M',
    'november': 'N',
    'oscar': 'O',
    'papa': 'P',
    'quebec': 'Q',
    'romeo': 'R',
    'sierra': 'S',
    'tango': 'T',
    'uniform': 'U',
    'victor': 'V',
    'whiskey': 'W',
    'whisky': 'W',
    'xray': 'X',
    'yankee': 'Y',
    'zulu': 'Z',
  };
  static const _digits = <String, String>{
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'niner': '9',
  };
  static final _call = RegExp(
    r'^(?:[A-Z]{1,2}|[0-9][A-Z]|[A-Z][0-9])[0-9][A-Z]{1,4}$',
  );
  static final _words = RegExp(
    r'x[\s-]?ray|[A-Za-z]+|[0-9]+',
    caseSensitive: false,
  );

  static List<String> hotwords(String callSign) {
    final result = <String>[
      'CQ',
      'QSO',
      'QSY',
      'QTH',
      'QRM',
      'QRN',
      'QRP',
      'QRZ',
      'RST',
      'VHF',
      'UHF',
      'simplex',
      'repeater',
      'squelch',
      'kilohertz',
      'megahertz',
    ];
    final call = callSign.toUpperCase();
    if (_call.hasMatch(call)) {
      final spoken = <String>[];
      for (final letter in call.split('')) {
        spoken.add(
          phonetics.entries
                  .where((e) => e.value == letter)
                  .map((e) => e.key)
                  .firstOrNull ??
              _digits.entries.firstWhere((e) => e.value == letter).key,
        );
      }
      result.add(spoken.join(' '));
    }
    return result;
  }

  /// Normalize only complete phonetic runs shaped like a callsign. Ordinary
  /// names, frequencies and ambiguous homophones ("for", "to") stay unchanged.
  static String normalizeCallsigns(String text) {
    final words = _words.allMatches(text).toList();
    final output = StringBuffer();
    var copied = 0;
    var i = 0;
    while (i < words.length) {
      final start = i;
      final symbols = StringBuffer();
      var hasPhonetic = false;
      while (i < words.length) {
        if (i > start &&
            !RegExp(
              r'^[\s,-]*$',
            ).hasMatch(text.substring(words[i - 1].end, words[i].start))) {
          break;
        }
        final word = words[i]
            .group(0)!
            .toLowerCase()
            .replaceAll(RegExp(r'[\s-]'), '');
        final letter = phonetics[word];
        final symbol =
            letter ??
            _digits[word] ??
            (RegExp(r'^[0-9]$').hasMatch(word) ? word : null);
        if (symbol == null) break;
        hasPhonetic |= letter != null;
        symbols.write(symbol);
        i++;
      }
      if (i > start && hasPhonetic && _call.hasMatch(symbols.toString())) {
        output.write(text.substring(copied, words[start].start));
        output.write(symbols);
        copied = words[i - 1].end;
      }
      if (i == start) i++;
    }
    output.write(text.substring(copied));
    return output.toString();
  }
}
