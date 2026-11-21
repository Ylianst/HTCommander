import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/radio_speech.dart';

void main() {
  test(
    'speech gating bounds pre-roll and preserves both speech boundaries',
    () {
      final gate = SpeechAudioGate();
      for (var i = 0; i < 15; i++) {
        final update = gate.process(
          Float32List(512)..[0] = i.toDouble(),
          false,
        );
        expect(update.audio, isEmpty);
        expect(update.ended, isFalse);
      }
      final opened = gate.process(Float32List(512)..[0] = 15, true);
      expect(opened.audio.map((f) => f[0]), List.generate(11, (i) => i + 5));
      expect(gate.process(Float32List(512), true).audio, hasLength(1));
      expect(gate.process(Float32List(512), false).ended, isTrue);
      expect(gate.process(Float32List(512), false).ended, isFalse);
      gate.reset();
      expect(gate.process(Float32List(512), true).audio, hasLength(1));
    },
  );

  test(
    'backlog rejects excess audio and resumes only below its low-water mark',
    () {
      final queue = SpeechAudioBacklog();
      expect(queue.enqueue(16000 * 10), isTrue);
      expect(queue.enqueue(1), isFalse);
      expect(queue.milliseconds, 10000);
      queue.acknowledge(16000 * 4);
      expect(queue.overloaded, isTrue);
      expect(queue.enqueue(1), isFalse);
      queue.acknowledge(16000);
      expect(queue.overloaded, isFalse);
      expect(queue.milliseconds, 5000);
    },
  );

  test('only deliberate overlap removes matching boundary words', () {
    expect(appendSpeechText('Calling CQ', 'CQ again'), 'Calling CQ CQ again');
    expect(
      appendSpeechText('Calling CQ.', 'cq again', overlap: true),
      'Calling CQ. again',
    );
    expect(
      appendSpeechText('Check one two', 'one two three', overlap: true),
      'Check one two three',
    );
    expect(
      appendSpeechText('Calling CQ', 'different words', overlap: true),
      'Calling CQ different words',
    );
  });

  test(
    'normalizes complete phonetic callsigns without guessing ordinary text',
    () {
      expect(
        RadioSpeechVocabulary.normalizeCallsigns(
          'Calling kilo six alpha bravo charlie, from whiskey one alpha whiskey.',
        ),
        'Calling K6ABC, from W1AW.',
      );
      for (final text in [
        'Alpha Bravo, meet Mike at Hotel.',
        'one four six point five two megahertz',
        'kilo for alpha bravo charlie',
        'kilo six',
        'K6ABC calling CQ',
        '你好，收到。',
      ]) {
        expect(RadioSpeechVocabulary.normalizeCallsigns(text), text);
      }
    },
  );

  test('callsign hints are phonetic and reject malformed context', () {
    expect(
      RadioSpeechVocabulary.hotwords('K6ABC'),
      contains('kilo six alpha bravo charlie'),
    );
    expect(
      RadioSpeechVocabulary.hotwords('INVALID/PHRASE:99'),
      RadioSpeechVocabulary.hotwords(''),
    );
  });
}
