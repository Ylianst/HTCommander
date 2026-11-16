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
import 'package:htcommander/radio/native_cw.dart';

const int _fs = 32000;

const Map<String, String> _morse = {
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
  final dec = decoder ?? CwDecoder(onDecoded: (text, wpm) => results.add(text));
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
  group('CW native/reference parity', () {
    test(
      'selects the reference explicitly and the platform default safely',
      () {
        final reference = CwDecoder(useNative: false);
        final automatic = CwDecoder();
        expect(reference.usingNative, isFalse);
        expect(automatic.usingNative, nativeCwEnabled);
        reference.dispose();
        automatic.dispose();
      },
    );

    test(
      'matches text, WPM and tone through chunking, idle, flush and reset',
      () {
        final noisy = _renderCw('PARIS', _tone(712.5, 0.4), wpm: 20);
        _addNoise(noisy, 0.12, 72);
        final signals = [
          _renderCw('SOS', _tone(700, 0.5)),
          _concat([
            _silence(70),
            noisy,
            _silence(2000),
            _renderCw('OK', _tone(400, 0.2), wpm: 10),
          ]),
          _renderCw('TEST', _noise(0.7, 31)),
          _renderCw('SOS', _tone(1200, 0.6)),
          _renderCw('CQ', _twoTones(700, 0.3, 1500, 0.6)),
          _silence(20),
        ];
        for (final chunk in [1, 127, 640, 2048, 1 << 30]) {
          final expected = <(String, int)>[];
          final actual = <(String, int)>[];
          final reference = CwDecoder(
            useNative: false,
            onDecoded: (text, wpm) => expected.add((text, wpm)),
          );
          final decoder = CwDecoder(
            onDecoded: (text, wpm) => actual.add((text, wpm)),
          );
          try {
            for (int signal = 0; signal < signals.length; signal++) {
              final samples = signals[signal];
              for (int i = 0; i < samples.length; i += chunk) {
                final part = Float64List.sublistView(
                  samples,
                  i,
                  math.min(i + chunk, samples.length),
                );
                reference.addSamples(part);
                decoder.addSamples(part);
              }
              expect(actual, expected, reason: 'before flush, chunk $chunk');
              reference.flush();
              decoder.flush();
              decoder.flush();
              expect(actual, expected, reason: 'after flush, chunk $chunk');
              expect(decoder.lastToneHz, reference.lastToneHz);
              if (signal == 0) expect(actual.single.$1, 'SOS');
              if (signal >= 2) expect(actual, isEmpty);
              reference.reset();
              decoder.reset();
              expect(decoder.lastToneHz, 0);
              expected.clear();
              actual.clear();
            }
          } finally {
            reference.dispose();
            decoder.dispose();
          }
        }
      },
    );

    test('dispose is idempotent and rejects subsequent processing', () {
      final decoder = CwDecoder();
      decoder.addSamples(_silence(20));
      decoder.dispose();
      decoder.dispose();
      expect(() => decoder.addSamples(Float64List(0)), throwsStateError);
      expect(() => decoder.processPcm16(Uint8List(0), 0, 0), throwsStateError);
      expect(decoder.flush, throwsStateError);
      expect(decoder.reset, throwsStateError);
    });

    test('reset discards buffered windows and a pending transmission', () {
      final expected = <(String, int)>[];
      final actual = <(String, int)>[];
      final reference = CwDecoder(
        useNative: false,
        onDecoded: (text, wpm) => expected.add((text, wpm)),
      );
      final decoder = CwDecoder(
        onDecoded: (text, wpm) => actual.add((text, wpm)),
      );
      try {
        final abandoned = _renderCw('PARIS', _tone(400, 0.4));
        decoder.addSamples(Float64List.sublistView(abandoned, 0, 17017));
        decoder.reset();
        decoder.flush();
        expect(actual, isEmpty);
        final samples = _renderCw('SOS', _tone(750, 0.2));
        reference.addSamples(samples);
        decoder.addSamples(samples);
        reference.flush();
        decoder.flush();
        expect(actual, expected);
        expect(actual.single.$1, 'SOS');
        expect(decoder.lastToneHz, reference.lastToneHz);
      } finally {
        reference.dispose();
        decoder.dispose();
      }
    });

    test('validates window geometry before allocating', () {
      expect(() => CwDecoder(probeStepHz: 0), throwsArgumentError);
      expect(() => CwDecoder(hopSize: 513), throwsArgumentError);
      expect(() => CwDecoder(windowSize: 0), throwsArgumentError);
    });
  });

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

    test('decodes a low-pitched tone near the bottom of the band', () {
      // The default band reaches down to ~300 Hz so machine-generated CW with a
      // low sidetone (e.g. 300 Hz) still decodes rather than being ignored.
      for (final hz in [300.0, 400.0, 500.0]) {
        final s = _renderCw('SOS', _tone(hz, 0.5));
        expect(_decode(s), 'SOS', reason: 'failed at ${hz.toInt()} Hz');
      }
    });

    test('decodes a steady moderate-volume tone', () {
      // A continuous, only moderately loud tone must not drive the adaptive
      // noise floor up to its own level and lock itself out.
      final s = _renderCw('PARIS', _tone(700, 0.1));
      expect(_decode(s), 'PARIS');
    });

    test('recovers after a loud noisy lead-in instead of going deaf', () {
      // Mirrors the recording that motivated this: a loud, spectrally messy
      // lead-in precedes the keying. If those non-tone frames feed the noise
      // floor it stays elevated into the message and swallows the opening
      // characters. Because frames above the detection threshold no longer shape
      // the floor, the moderate tone that follows still decodes in full.
      final pre = _silence(1500);
      _addNoise(pre, 1.5, 3); // loud broadband, rejected as non-tonal
      final msg = _renderCw('CQ CQ DE TEST', _tone(700, 0.3));
      expect(_decode(_concat([pre, msg])), 'CQ CQ DE TEST');
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

    test('reuses PCM storage across varying lengths, offsets and resets', () {
      final expected = <(String, int)>[];
      final actual = <(String, int)>[];
      final reference = CwDecoder(
        useNative: false,
        onDecoded: (t, w) => expected.add((t, w)),
      );
      final decoder = CwDecoder(onDecoded: (t, w) => actual.add((t, w)));
      const chunks = [2048, 1, 17, 640, 4096, 3, 128];
      final packet = Uint8List(4096 * 2 + 5);
      for (final (text, hz) in [('PARIS', 700.0), ('SOS', 400.0)]) {
        final samples = _renderCw(text, _tone(hz, 0.5));
        final quantized = Float64List(samples.length);
        for (int i = 0; i < samples.length; i++) {
          quantized[i] = (samples[i] * 32767).round() / 32768.0;
        }
        reference.addSamples(quantized);
        reference.flush();
        int position = 0;
        int block = 0;
        while (position < samples.length) {
          final count = math.min(
            chunks[block++ % chunks.length],
            samples.length - position,
          );
          packet.fillRange(0, packet.length, 0xa5);
          for (int i = 0; i < count; i++) {
            final value = (samples[position + i] * 32767).round();
            packet[3 + i * 2] = value & 0xff;
            packet[4 + i * 2] = (value >> 8) & 0xff;
          }
          decoder.processPcm16(packet, 3, count * 2 + 1);
          decoder.processPcm16(packet, 3, 0);
          decoder.processPcm16(packet, 3, 1);
          position += count;
        }
        decoder.flush();
        expect(actual, expected);
        expect(actual.last.$1, text);
        expect(decoder.lastToneHz, reference.lastToneHz);
        decoder.reset();
        reference.reset();
      }
    });

    test('clears Goertzel scratch between windows with custom probes', () {
      final results = <String>[];
      final decoder = CwDecoder(
        bandLowHz: 500,
        bandHighHz: 800,
        probeStepHz: 50,
        onDecoded: (text, _) => results.add(text),
      );
      for (final hz in [600.0, 750.0]) {
        decoder.addSamples(_renderCw('SOS', _tone(hz, 0.5)));
        decoder.addSamples(_silence(2000));
        expect(results, List.filled(results.length, 'SOS'));
        expect(results.length, hz == 600.0 ? 1 : 2);
        expect(decoder.lastToneHz, hz);
      }
      decoder.flush();
      expect(results, ['SOS', 'SOS']);
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
