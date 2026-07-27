/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/morse_keyer.dart';

void main() {
  group('MorseKeySettings', () {
    test('round-trips through JSON', () {
      const s = MorseKeySettings(
        keyType: MorseKeyType.paddle,
        paddleGroup: MorseKeyPaddleGroup.control,
        paddleReversed: false,
        straightBinding: MorseKeyBinding.bracketRight,
        wpm: 22,
        tailMs: 1200,
        toneHz: 650,
      );
      final decoded = MorseKeySettings.fromJson(s.toJson());
      expect(decoded.keyType, MorseKeyType.paddle);
      expect(decoded.paddleGroup, MorseKeyPaddleGroup.control);
      expect(decoded.paddleReversed, isFalse);
      expect(decoded.straightBinding, MorseKeyBinding.bracketRight);
      // Paddle on Ctrl, not reversed: dit = Left Ctrl, dah = Right Ctrl.
      expect(decoded.primaryBinding, MorseKeyBinding.controlLeft);
      expect(decoded.secondaryBinding, MorseKeyBinding.controlRight);
      expect(decoded.wpm, 22);
      expect(decoded.tailMs, 1200);
      expect(decoded.toneHz, 650);
    });

    test('paddle reverse swaps the dit and dah keys', () {
      const s = MorseKeySettings(
        keyType: MorseKeyType.paddle,
        paddleGroup: MorseKeyPaddleGroup.brackets,
        paddleReversed: true,
      );
      // Reversed: dit on the right lever, dah on the left lever.
      expect(s.primaryBinding, MorseKeyBinding.bracketRight);
      expect(s.secondaryBinding, MorseKeyBinding.bracketLeft);
    });

    test('straight key uses its single contact for the primary binding', () {
      const s = MorseKeySettings(
        keyType: MorseKeyType.straight,
        straightBinding: MorseKeyBinding.controlRight,
      );
      expect(s.primaryBinding, MorseKeyBinding.controlRight);
    });

    test('clamps out-of-range values and applies defaults', () {
      final decoded = MorseKeySettings.fromJson(<String, Object?>{
        'wpm': 999,
        'tailMs': 1,
        'toneHz': 50,
      });
      expect(decoded.wpm, 60);
      expect(decoded.tailMs, 100);
      expect(decoded.toneHz, 300);
      // Missing keys fall back to defaults.
      expect(decoded.keyType, MorseKeyType.straight);
      expect(decoded.paddleGroup, MorseKeyPaddleGroup.brackets);
      expect(decoded.primaryBinding, MorseKeyBinding.bracketLeft);
    });

    test('string conversions are stable', () {
      for (final b in MorseKeyBinding.values) {
        expect(morseKeyBindingFromString(morseKeyBindingToString(b)), b);
      }
      for (final t in MorseKeyType.values) {
        expect(morseKeyTypeFromString(morseKeyTypeToString(t)), t);
      }
      for (final m in MorseKeyMode.values) {
        expect(morseKeyModeFromString(morseKeyModeToString(m)), m);
      }
      for (final g in MorseKeyPaddleGroup.values) {
        expect(
          morseKeyPaddleGroupFromString(morseKeyPaddleGroupToString(g)),
          g,
        );
      }
    });
  });

  group('IambicKeyer', () {
    test('is idle with no paddle activity', () {
      final k = IambicKeyer();
      expect(k.idle, isTrue);
      expect(k.next(), isNull);
    });

    test('held dit paddle produces a stream of dits', () {
      final k = IambicKeyer();
      k.setDit(true);
      expect(k.next(), MorseElement.dit);
      expect(k.next(), MorseElement.dit);
      expect(k.next(), MorseElement.dit);
      k.setDit(false);
      // Once released and consumed, it goes idle.
      expect(k.next(), isNull);
    });

    test('held dah paddle produces a stream of dahs', () {
      final k = IambicKeyer();
      k.setDah(true);
      expect(k.next(), MorseElement.dah);
      expect(k.next(), MorseElement.dah);
      k.setDah(false);
      expect(k.next(), isNull);
    });

    test('squeeze alternates elements', () {
      final k = IambicKeyer();
      k.setDit(true);
      k.setDah(true);
      final first = k.next();
      final second = k.next();
      final third = k.next();
      expect(first, isNotNull);
      expect(second, isNot(first));
      expect(third, first);
    });

    test('remembers a tap on the opposite paddle during an element (memory)', () {
      final k = IambicKeyer();
      // Start a dah (paddle held).
      k.setDah(true);
      expect(k.next(), MorseElement.dah);
      // Tap the dit paddle during the dah, then release it before the next
      // boundary. The dit must be remembered and sent next.
      k.setDit(true);
      k.setDit(false);
      expect(k.next(), MorseElement.dit);
      // Then it returns to the still-held dah.
      expect(k.next(), MorseElement.dah);
    });

    test('reset clears all state', () {
      final k = IambicKeyer();
      k.setDit(true);
      k.reset();
      expect(k.idle, isTrue);
      expect(k.next(), isNull);
    });
  });

  group('MorseDecoder', () {
    // Helper: feed a text as ideal marks/spaces at a fixed unit and decode it.
    String roundTrip(String text, {int unitMs = 60}) {
      final d = MorseDecoder(fixedUnitMs: unitMs);
      const table = {
        'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
        'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-',
        'L': '.-..', 'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-',
        'R': '.-.', 'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--',
        'X': '-..-', 'Y': '-.--', 'Z': '--..', '0': '-----', '1': '.----',
        '2': '..---', '3': '...--', '4': '....-', '5': '.....', '6': '-....',
        '7': '--...', '8': '---..', '9': '----.',
      };
      final words = text.split(' ');
      for (var w = 0; w < words.length; w++) {
        final letters = words[w].split('');
        for (var li = 0; li < letters.length; li++) {
          final code = table[letters[li]]!;
          for (var ci = 0; ci < code.length; ci++) {
            d.onMark(code[ci] == '-' ? unitMs * 3 : unitMs);
            if (ci < code.length - 1) d.onSpace(unitMs); // intra-element
          }
          if (li < letters.length - 1) d.onSpace(unitMs * 3); // letter gap
        }
        if (w < words.length - 1) d.onSpace(unitMs * 7); // word gap
      }
      return d.finish();
    }

    test('decodes a single word from ideal timing', () {
      expect(roundTrip('HELLO'), 'HELLO');
    });

    test('decodes multiple words with spaces', () {
      expect(roundTrip('CQ DE VE1ABC'), 'CQ DE VE1ABC');
    });

    test('decodes SOS', () {
      expect(roundTrip('SOS'), 'SOS');
    });

    test('adaptive decoder handles hand timing that drifts', () {
      // Straight-key style: no fixed unit, slightly irregular durations.
      final d = MorseDecoder();
      // "OK" = --- / -.-
      const dit = 70;
      const dah = 210;
      // O
      d.onMark(dah);
      d.onSpace(dit);
      d.onMark(dah + 20);
      d.onSpace(dit);
      d.onMark(dah - 15);
      d.onSpace(dit * 3); // letter gap
      // K
      d.onMark(dah);
      d.onSpace(dit);
      d.onMark(dit);
      d.onSpace(dit);
      d.onMark(dah);
      expect(d.finish(), 'OK');
    });

    test('unknown symbols are skipped without crashing', () {
      final d = MorseDecoder(fixedUnitMs: 60);
      // An impossible code ........ then a valid E.
      for (var i = 0; i < 8; i++) {
        d.onMark(60);
        if (i < 7) d.onSpace(60);
      }
      d.onSpace(180); // letter gap
      d.onMark(60); // E
      expect(d.finish(), 'E');
    });
  });
}
