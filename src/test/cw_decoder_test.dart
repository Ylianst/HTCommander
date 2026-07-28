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

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/cw_decoder.dart';

const int _fs = 32000;

const Map<String, String> _morse = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
  'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
  'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
  'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
  'Y': '-.--', 'Z': '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
  '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
};

/// Renders on/off-keyed CW for [text]. During "key down" the sample value comes
/// from [onFill] (a tone, multiple tones, or noise); "key up" is silence. Each
/// element edge is cosine-ramped to avoid clicks. [onFill] receives a counter
/// that advances only while keyed, so a tone keeps phase across elements.
Float64List _renderCw(
  String text,
  double Function(int keyedIndex) onFill, {
  int wpm = 15,
  int rampSamples = 64,
}) {
  final unit = (_fs * 1.2 / wpm).round();
  final segs = <List<int>>[]; // [durationSamples, on?1:0]
  void on(int units) => segs.add([unit * units, 1]);
  void off(int units) => segs.add([unit * units, 0]);

  final words = text.toUpperCase().split(' ');
  for (int w = 0; w < words.length; w++) {
    if (w > 0) off(7);
    final word = words[w];
    bool firstChar = true;
    for (int c = 0; c < word.length; c++) {
      final code = _morse[word[c]];
      if (code == null) continue;
      if (!firstChar) off(3);
      firstChar = false;
      for (int s = 0; s < code.length; s++) {
        if (s > 0) off(1);
        on(code[s] == '.' ? 1 : 3);
      }
    }
  }

  int total = 0;
  for (final s in segs) {
    total += s[0];
  }
  final out = Float64List(total);
  int idx = 0;
  int keyed = 0;
  for (final seg in segs) {
    final dur = seg[0];
    final isOn = seg[1] == 1;
    for (int i = 0; i < dur; i++) {
      double v = 0.0;
      if (isOn) {
        v = onFill(keyed);
        if (i < rampSamples) {
          v *= i / rampSamples;
        } else if (i > dur - rampSamples) {
          v *= (dur - i) / rampSamples;
        }
        keyed++;
      }
      out[idx++] = v;
    }
  }
  return out;
}

double Function(int) _tone(double hz, double amp) =>
    (int i) => amp * math.sin(2 * math.pi * hz * i / _fs);

double Function(int) _twoTones(double a, double aa, double b, double ab) =>
    (int i) =>
        aa * math.sin(2 * math.pi * a * i / _fs) +
        ab * math.sin(2 * math.pi * b * i / _fs);

double Function(int) _noise(double amp, int seed) {
  final rng = math.Random(seed);
  return (int _) => amp * (rng.nextDouble() * 2 - 1);
}

void _addNoise(Float64List s, double amp, int seed) {
  final rng = math.Random(seed);
  for (int i = 0; i < s.length; i++) {
    s[i] += amp * (rng.nextDouble() * 2 - 1);
  }
}

Float64List _silence(int ms) => Float64List(_fs * ms ~/ 1000);

/// Decodes [samples] with a fresh [CwDecoder], feeding it in small chunks to
/// exercise the streaming buffer, then flushing. Returns the decoded text
/// (empty if nothing was decoded).
String _decode(Float64List samples, {CwDecoder? decoder}) {
  final results = <String>[];
  final dec = decoder ??
      CwDecoder(onDecoded: (text, wpm) => results.add(text));
  dec.onDecoded ??= (text, wpm) => results.add(text);
  const chunk = 800;
  for (int i = 0; i < samples.length; i += chunk) {
    final end = math.min(i + chunk, samples.length);
    dec.addSamples(Float64List.sublistView(samples, i, end));
  }
  dec.flush();
  return results.join(' ');
}

Float64List _concat(List<Float64List> parts) {
  int total = 0;
  for (final p in parts) {
    total += p.length;
  }
  final out = Float64List(total);
  int idx = 0;
  for (final p in parts) {
    out.setRange(idx, idx + p.length, p);
    idx += p.length;
  }
  return out;
}

void main() {
  group('CwDecoder decoding', () {
    test('decodes a clean 700 Hz message', () {
      final s = _renderCw('PARIS', _tone(700, 0.5));
      expect(_decode(s), 'PARIS');
    });

    test('decodes tones across the 600-800 Hz band', () {
      for (final hz in [600.0, 650.0, 700.0, 750.0, 800.0]) {
        final s = _renderCw('SOS', _tone(hz, 0.5));
        expect(_decode(s), 'SOS', reason: 'failed at ${hz.toInt()} Hz');
      }
    });

    test('decodes at different sending speeds', () {
      for (final wpm in [10, 15, 20, 25]) {
        final s = _renderCw('TEST', _tone(700, 0.5), wpm: wpm);
        expect(_decode(s), 'TEST', reason: 'failed at $wpm wpm');
      }
    });

    test('decodes word spacing', () {
      final s = _renderCw('CQ TEST', _tone(700, 0.5));
      expect(_decode(s), 'CQ TEST');
    });

    test('decodes with additive white noise (~7 dB SNR)', () {
      final s = _renderCw('PARIS', _tone(700, 0.5));
      _addNoise(s, 0.15, 7);
      expect(_decode(s), 'PARIS');
    });

    test('decodes via the 16-bit PCM entry point', () {
      final f = _renderCw('CQ', _tone(700, 0.5));
      final pcm = Uint8List(f.length * 2);
      for (int i = 0; i < f.length; i++) {
        final v = (f[i] * 32767).round().clamp(-32768, 32767);
        pcm[i * 2] = v & 0xFF;
        pcm[i * 2 + 1] = (v >> 8) & 0xFF;
      }
      final results = <String>[];
      final dec = CwDecoder(onDecoded: (t, w) => results.add(t));
      dec.processPcm16(pcm, 0, pcm.length);
      dec.flush();
      expect(results.join(' '), 'CQ');
    });

    test('auto-finishes after an idle gap without an explicit flush', () {
      final s = _concat([
        _renderCw('OK', _tone(700, 0.5)),
        _silence(2000), // longer than idleFinishMs
      ]);
      final results = <String>[];
      final dec = CwDecoder(onDecoded: (t, w) => results.add(t));
      dec.addSamples(s);
      // No flush(): the trailing silence should trigger the idle finish.
      expect(results, ['OK']);
    });
  });

  group('CwDecoder false-positive rejection', () {
    test('rejects broadband voice-like noise keyed in a Morse pattern', () {
      // Same on/off envelope as real CW, but the "key down" is broadband noise
      // rather than a pure tone, so no single peak dominates.
      final s = _renderCw('PARIS', _noise(0.8, 1));
      expect(_decode(s), isEmpty);
    });

    test('rejects continuous white noise', () {
      final s = Float64List(_fs); // 1 s
      _addNoise(s, 0.5, 3);
      expect(_decode(s), isEmpty);
    });

    test('rejects an out-of-band keyed tone (1200 Hz)', () {
      final s = _renderCw('PARIS', _tone(1200, 0.6));
      expect(_decode(s), isEmpty);
    });

    test('rejects an in-band tone masked by strong out-of-band energy', () {
      // 700 Hz present, but a stronger 1500 Hz tone spreads the energy so the
      // in-band peak holds well under half the frame energy (low purity).
      final s = _renderCw('PARIS', _twoTones(700, 0.4, 1500, 0.6));
      expect(_decode(s), isEmpty);
    });

    test('decodes silence as nothing', () {
      expect(_decode(_silence(1000)), isEmpty);
    });

    test('rejects one-letter and bare E/T two-letter results', () {
      for (final t in ['E', 'T', 'ET', 'TE', 'EE', 'TT']) {
        expect(_decode(_renderCw(t, _tone(700, 0.5))), isEmpty, reason: t);
      }
    });

    test('accepts a legitimate two-letter word', () {
      expect(_decode(_renderCw('OK', _tone(700, 0.5))), 'OK');
      // Two letters that include E but aren't only E/T are kept.
      expect(_decode(_renderCw('EA', _tone(700, 0.5))), 'EA');
    });
  });
}
