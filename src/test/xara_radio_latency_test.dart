/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// XARA over an HT-like radio path: two XARA modems with the app's default
// latency and key-up settings, linked through a path that delays each burst
// and loses its first 240 ms to key-up (as measured on Bluetooth HTs). The
// station must count its key-up pre-roll in its latency, or replies land
// outside the ARQ windows and control codes are dropped.
//

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/xara_modem.dart';

const int _rate = 32000;

/// One radio direction: [lagMs] from PCM handed over to audio at the far
/// modem, with the first [lossMs] of every burst lost to key-up.
class RadioPath {
  final int lagMs;
  final int lossMs;
  final void Function(Uint8List) deliver;
  final _queue = <(DateTime, Uint8List)>[];
  Uint8List? _cur;
  int _pos = 0;

  RadioPath(this.lagMs, this.lossMs, this.deliver);

  void add(Uint8List pcm) {
    final int drop = (lossMs * _rate ~/ 1000) * 2;
    if (pcm.length <= drop) return;
    _queue.add((
      DateTime.now().add(Duration(milliseconds: lagMs + lossMs)),
      Uint8List.sublistView(pcm, drop),
    ));
  }

  void tick() {
    if (_cur == null &&
        _queue.isNotEmpty &&
        !DateTime.now().isBefore(_queue.first.$1)) {
      _cur = _queue.removeAt(0).$2;
      _pos = 0;
    }
    final c = _cur;
    if (c == null) return;
    final end = (_pos + 1280).clamp(0, c.length);
    deliver(Uint8List.fromList(c.sublist(_pos, end)));
    _pos = end;
    if (_pos >= c.length) _cur = null;
  }
}

/// Runs a caller and an answerer with the app's default latency settings over
/// [lagMs] radio paths, sends 400 bytes to the caller, and returns the link
/// events and the verdict of every received control code.
Future<
  ({
    int received,
    Map<String, List<String>> events,
    Map<String, List<String>> verdicts,
  })
>
runLink(int lagMs) async {
  final verdicts = {'caller': <String>[], 'answerer': <String>[]};
  final events = {'caller': <String>[], 'answerer': <String>[]};
  var received = 0;
  late final RadioPath toAnswerer, toCaller;
  XaraModem modem(String call, String who, void Function(Uint8List) tx) =>
      XaraModem(
        config: XaraModemConfig(callsign: call),
        onTransmit: tx,
        onEvent: (e) {
          switch (e['evt']) {
            case 'frame' when e['record'] == -1 && e['tx'] == false:
              final m = e['meta']! as Map;
              if (m['verdict'] is String) {
                verdicts[who]!.add(
                  '${m['verdict']} (${m['ticks']}/${m['window']} ticks, '
                  '${m['state']}, code ${e['code']})',
                );
              }
            case 'data':
              received += (e['data']! as Uint8List).length;
            case 'connected' ||
                'timedOut' ||
                'disconnected' ||
                'unableToConnect':
              events[who]!.add(e['evt']! as String);
          }
        },
      );
  final caller = modem('N1ABC', 'caller', (p) => toAnswerer.add(p));
  final answerer = modem('N0CALL', 'answerer', (p) => toCaller.add(p));
  toAnswerer = RadioPath(lagMs, 240, (c) => answerer.pushRx(c, 0, c.length));
  toCaller = RadioPath(lagMs, 240, (c) => caller.pushRx(c, 0, c.length));
  final clock = Timer.periodic(const Duration(milliseconds: 20), (_) {
    toAnswerer.tick();
    toCaller.tick();
  });
  try {
    caller.connect('N0CALL', const []);
    answerer.send(
      Uint8List.fromList(List<int>.generate(400, (i) => 65 + i % 26)),
    );
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (received < 400 && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return (received: received, events: events, verdicts: verdicts);
  } finally {
    clock.cancel();
    caller.dispose();
    answerer.dispose();
  }
}

void main() {
  test(
    'a link with 750 ms radio lag and key-up loss keeps its control codes',
    () async {
      final r = await runLink(750);
      expect(r.received, 400, reason: '${r.events} ${r.verdicts}');
      expect(r.events['caller'], ['connected']);
      expect(r.events['answerer'], ['connected']);
      // Before the key-up pre-roll was counted in the latency, this link timed
      // out with most replies dropped. Allow one drop for scheduling jitter when
      // the suite runs many real-time modems in parallel.
      for (final v in r.verdicts.values) {
        expect(v, isNotEmpty);
        expect(
          v.where((x) => !x.startsWith('accepted')).length,
          lessThanOrEqualTo(1),
          reason: '${r.verdicts}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a link with 1 s radio lag still connects and delivers', () async {
    final r = await runLink(1000);
    expect(r.received, 400, reason: '${r.events} ${r.verdicts}');
    expect(r.events['caller'], ['connected']);
    expect(r.events['answerer'], ['connected']);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
