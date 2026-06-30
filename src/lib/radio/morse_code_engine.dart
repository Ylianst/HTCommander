/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dart port of the C# MorseCodeEngine (reference/HTCommander/src/radio/
MorseCodeEngine.cs). Converts text into a Morse-code tone as 8-bit unsigned PCM
audio at 32 kHz mono.
*/

import 'dart:math' as math;
import 'dart:typed_data';

/// Generates Morse-code audio (8-bit unsigned PCM, 32 kHz mono) from text.
class MorseCodeEngine {
  MorseCodeEngine._();

  static const int _sampleRate = 32000;

  /// Max for unsigned 8-bit PCM centered at 128.
  static const int _amplitude = 127;

  /// Morse code dictionary.
  static const Map<String, String> _morseCode = {
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
    ' ': ' ', // space between words
  };

  /// Generates 8-bit unsigned PCM audio (32 kHz, mono) for [text].
  ///
  /// Unknown characters are silently skipped. [frequency] is the tone pitch in
  /// Hz and [wpm] is the speed in words per minute (ITU standard timing).
  static Uint8List generateMorsePcm(
    String text, {
    int frequency = 500,
    int wpm = 15,
  }) {
    final double unit = 1.2 / wpm; // seconds per dit (ITU standard)
    final int samplesPerUnit = (_sampleRate * unit).toInt();

    // Tone and silence generators.
    final Uint8List ditTone = _generateTone(frequency, samplesPerUnit);
    final Uint8List dahTone = _generateTone(frequency, samplesPerUnit * 3);
    final Uint8List intraCharSpace = _generateSilence(samplesPerUnit); // 1 unit
    final Uint8List interCharSpace = _generateSilence(
      samplesPerUnit * 3,
    ); // 3 units
    final Uint8List wordSpace = _generateSilence(samplesPerUnit * 8); // 8 units

    final BytesBuilder stream = BytesBuilder();

    for (final String ch in text.toUpperCase().split('')) {
      final String? code = _morseCode[ch];
      if (code == null) continue;

      if (code == ' ') {
        stream.add(wordSpace);
        continue;
      }

      for (int i = 0; i < code.length; i++) {
        if (code[i] == '.') {
          stream.add(ditTone);
        } else if (code[i] == '-') {
          stream.add(dahTone);
        }

        if (i < code.length - 1) {
          stream.add(intraCharSpace);
        }
      }

      stream.add(interCharSpace);
    }

    return stream.toBytes();
  }

  static Uint8List _generateTone(int frequency, int sampleCount) {
    final Uint8List buffer = Uint8List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final double t = i / _sampleRate;
      final double value = math.sin(2 * math.pi * frequency * t);
      buffer[i] = (128 + value * _amplitude).toInt(); // 8-bit unsigned PCM
    }
    return buffer;
  }

  static Uint8List _generateSilence(int sampleCount) {
    // Silence centered at 128.
    return Uint8List(sampleCount)..fillRange(0, sampleCount, 128);
  }
}
