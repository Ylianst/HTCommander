/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Integration tests for the XARA host driver: two stations, each behind an
XaraDriver, talk over a simulated HTCommander radio path. Audio is 32 kHz
PCM16, transmit bursts are played out in real time after a key-up latency,
receive audio arrives late and only while the squelch is open, and a radio
hears nothing while it is transmitting.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/arq_host.dart';
import 'package:htcommander/hamlib/xara/compression.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_session.dart';
import 'package:htcommander/hamlib/xara/fm_station.dart';
import 'package:htcommander/hamlib/xara/kiss_command.dart';
import 'package:htcommander/hamlib/xara/station.dart';
import 'package:htcommander/hamlib/xara/xara_driver.dart';

const int host = 32000;

class AirBurst {
  final int start;
  final Int16List pcm;

  AirBurst(this.start, this.pcm);

  int get end => start + pcm.length;
}

/// Wall clock in host samples; each radio plays its bursts after [txLag] and
/// the other side hears them [rxLag] later, delivered in [chunk]-sample pieces.
class RadioPath {
  final List<XaraDriver> d;
  final int txLag, rxLag, chunk;
  final List<List<AirBurst>> air = <List<AirBurst>>[<AirBurst>[], <AirBurst>[]];
  final List<List<int>> got = <List<int>>[<int>[], <int>[]];
  final List<List<Report>> events = <List<Report>>[<Report>[], <Report>[]];
  int now = 0;
  final double noise;
  final math.Random _rng = math.Random(1);

  RadioPath(this.d, {this.txLag = 9600, this.rxLag = 4800, this.chunk = 640, this.noise = 0.0});

  bool _onAir(int i, int t) => air[i].any((a) => t >= a.start && t < a.end);

  void step() {
    now += chunk;
    for (int i = 0; i < 2; i++) {
      // Audio that was on air from the other radio during (now - chunk, now], heard rxLag later.
      final int from = now - chunk - rxLag, to = now - rxLag;
      final Int16List heard = Int16List(chunk);
      bool any = false;
      for (final AirBurst a in air[1 - i]) {
        for (int t = math.max(from, a.start); t < math.min(to, a.end); t++) {
          if (!_onAir(i, t)) {
            heard[t - from] = a.pcm[t - a.start];
            any = true;
          }
        }
      }
      if (any) {
        if (noise > 0) {
          for (int k = 0; k < chunk; k++) {
            heard[k] = (heard[k] + noise * 32767 * (_rng.nextDouble() * 2 - 1)).round().clamp(-32768, 32767);
          }
        }
        d[i].pushRx(heard, now * 3 ~/ 2);
      }
      for (final Int16List b in d[i].tick(now * 3 ~/ 2)) {
        final int start = math.max(now + txLag, air[i].isEmpty ? 0 : air[i].last.end);
        air[i].add(AirBurst(start, b));
      }
      while (true) {
        final Report? r = d[i].pop();
        if (r == null) break;
        if (r is ReportHost && r.event is HostData) {
          got[i].addAll((r.event as HostData).data);
        } else {
          events[i].add(r);
        }
      }
    }
  }

  bool runUntil(double secs, bool Function(RadioPath) done) {
    final int limit = now + (secs * host).toInt();
    while (now < limit) {
      if (done(this)) return true;
      step();
    }
    return done(this);
  }

  bool has(int i, Report r) => events[i].contains(r);

  String trace() => <String>[
        for (int i = 0; i < 2; i++)
          for (final Report r in events[i])
            if (r is! ReportPtt && r is! ReportBusy) '$i $r',
      ].join('\n');
}

FmStation station(String call, int seed, int latency48) {
  final FmConfig c = FmConfig(FmBandwidth.narrow, call)..seed = seed;
  c.host.compression = Compression.off;
  return FmStation(c, StationOptions(txLatency: latency48));
}

Uint8List bytes(int n, int seed) {
  final math.Random r = math.Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

bool same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('xara driver', () {
    test('a burst is rendered whole at the host rate', () {
      final XaraDriver d = XaraDriver(station('N0CALL', 1, 0));
      expect(d.station.connect('N0CALL', 'N1CALL', const <String>[]), isTrue);
      final List<Int16List> b = <Int16List>[];
      for (int w = 0; w < 48000 && b.isEmpty; w += 480) {
        b.addAll(d.tick(w));
      }
      expect(b.length, 1);
      // Record 0 burst: lead-in + one frame, plus the silent overhang, at 32 kHz.
      expect(b[0].length, greaterThan(32000 ~/ 2));
      expect(b[0].any((v) => v != 0), isTrue);
      expect(d.station.transmitting, isFalse);
    });

    test('the station stays a jitter delay behind the wall clock', () {
      final XaraDriver d = XaraDriver(station('N0CALL', 1, 0));
      d.tick(96000);
      expect(d.station.now, inInclusiveRange(96000 - 12000 - 480, 96000 - 12000));
    });

    test('an active receive run waits for late audio', () {
      final XaraDriver d = XaraDriver(station('N0CALL', 1, 0));
      d.tick(48000);
      final int t0 = d.station.now;
      d.pushRx(Int16List(320), 48000);
      d.tick(48000 + 4800);
      // Only the 480 samples that arrived could be processed; the rest is awaited.
      expect(d.station.now - t0, lessThanOrEqualTo(960));
      d.tick(48000 + 48000);
      expect(d.station.now, greaterThan(48000 + 48000 - 12000 - 480));
    });

    test('two stations link and transfer over the simulated radio path', () {
      const int lat48 = (9600 + 4800) * 3 ~/ 2;
      final RadioPath p = RadioPath(<XaraDriver>[
        XaraDriver(station('N0CALL', 3, lat48)),
        XaraDriver(station('N1CALL', 5, lat48)),
      ]);
      final Uint8List a = bytes(2000, 1), b = bytes(700, 2);
      p.d[1].station.send(b);
      expect(p.d[0].station.connect('N0CALL', 'N1CALL', const <String>[]), isTrue);
      final Report line =
          ReportHost(HostConnected('N0CALL', 'N1CALL', const <String>[], const LinkBwFm(FmBandwidth.narrow)));
      expect(p.runUntil(30.0, (p) => p.has(0, line) && p.has(1, line)), isTrue, reason: p.trace());
      p.d[0].station.send(a);
      expect(p.runUntil(120.0, (p) => p.got[1].length >= a.length && p.got[0].length >= b.length), isTrue,
          reason: '${p.got[1].length}/${a.length} ${p.got[0].length}/${b.length}\n${p.trace()}');
      expect(same(p.got[1], a), isTrue);
      expect(same(p.got[0], b), isTrue);
      p.d[0].station.disconnect();
      expect(p.runUntil(30.0, (p) => p.d.every((x) => x.station.state == FmState.listen && x.station.idle)), isTrue,
          reason: p.trace());
      expect(p.has(0, const ReportHost(hostDisconnected)), isTrue);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('unconnected KISS frames cross the radio path', () {
      final RadioPath p = RadioPath(<XaraDriver>[
        XaraDriver(station('N0CALL', 3, 0)),
        XaraDriver(station('N1CALL', 5, 0)),
      ], noise: 0.002);
      p.d[1].station.setKissRx(true);
      final Uint8List frame = Uint8List.fromList('hello over xara'.codeUnits);
      expect(p.d[0].station.kiss(KissCommand.generic, frame), isTrue);
      bool heard(RadioPath p) => p.events[1].any((r) => r is ReportKiss && same(r.data, frame));
      expect(p.runUntil(10.0, heard), isTrue, reason: p.trace());
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
