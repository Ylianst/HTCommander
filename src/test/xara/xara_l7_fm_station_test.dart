/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Layer 7 tests: the FM station. Complete stations exchange 48 kHz audio
through a simulated channel (XARA's `tests/common/air.rs`), so every layer
from modulator to session runs end to end. Ports `fm_audio_link.rs`,
`fm_digi_link.rs`, the FM/scheduler parts of `station_tx.rs` and the
station unit test.
*/

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/arq_host.dart';
import 'package:htcommander/hamlib/xara/compression.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_session.dart';
import 'package:htcommander/hamlib/xara/fm_station.dart';
import 'package:htcommander/hamlib/xara/kiss.dart' as kiss;
import 'package:htcommander/hamlib/xara/kiss_command.dart';
import 'package:htcommander/hamlib/xara/station.dart';

const double fsHz = 48000.0;
const int block = 480;

class AirRng {
  int _s;

  AirRng(this._s);

  double next() {
    _s ^= _s << 13;
    _s ^= _s >>> 7;
    _s ^= _s << 17;
    return (_s >>> 11) / 9007199254740992.0;
  }

  double gauss() {
    final double u = math.max(next(), 1e-300), v = next();
    return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
  }
}

Uint8List payload(int n, int seed) {
  final AirRng r = AirRng(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => (r.next() * 256.0).toInt()));
}

bool skipBufferBusy(Report r) => (r is ReportHost && r.event is HostBuffer) || r is ReportBusy;

class Air {
  final List<FmStation> st;
  final List<ListQueue<double>> wire;
  final List<ListQueue<double>> lag;
  final List<List<int>> ears;
  final double noise;
  final AirRng rng = AirRng(0x9E3779B97F4A7C15);
  final bool Function(Report) skip;
  final List<List<int>> got;
  final List<List<(double, Report)>> events;
  final List<List<(int, int)>> bursts;
  final List<(int, int)?> _onAir;
  int _pos = 0;

  Air(this.st, List<int> delay, this.ears, this.noise, this.skip)
      : wire = <ListQueue<double>>[for (final int d in delay) ListQueue<double>.of(List<double>.filled(d, 0.0))],
        lag = <ListQueue<double>>[for (int i = 0; i < st.length; i++) ListQueue<double>()],
        got = <List<int>>[for (int i = 0; i < st.length; i++) <int>[]],
        events = <List<(double, Report)>>[for (int i = 0; i < st.length; i++) <(double, Report)>[]],
        bursts = <List<(int, int)>>[for (int i = 0; i < st.length; i++) <(int, int)>[]],
        _onAir = List<(int, int)?>.filled(st.length, null);

  factory Air.pair(List<FmStation> st, List<int> delay, double noise, bool Function(Report) skip) =>
      Air(st, delay, <List<int>>[<int>[1], <int>[0]], noise, skip);

  int get n => st.length;

  double get secs => st[0].now / fsHz;

  void step() {
    final List<List<double>> heard = <List<double>>[
      for (int i = 0; i < n; i++)
        List<double>.generate(block, (_) => wire[i].isEmpty ? 0.0 : wire[i].removeFirst()),
    ];
    for (int i = 0; i < n; i++) {
      _track(i, heard[i]);
    }
    _pos += block;
    final List<List<double>> outs = <List<double>>[for (int i = 0; i < n; i++) List<double>.filled(block, 0.0)];
    for (int i = 0; i < n; i++) {
      for (int k = 0; k < block; k++) {
        double s = 0.0;
        for (final int j in ears[i]) {
          s += heard[j][k];
        }
        lag[i].add(s + noise * rng.gauss());
      }
      final List<double> input = List<double>.generate(block, (_) => lag[i].removeFirst());
      st[i].process(input, outs[i]);
      final double t = secs;
      while (true) {
        final Report? r = st[i].pop();
        if (r == null) break;
        if (r is ReportHost && r.event is HostData) {
          got[i].addAll((r.event as HostData).data);
        } else if (!skip(r)) {
          events[i].add((t, r));
        }
      }
    }
    for (int i = 0; i < n; i++) {
      wire[i].addAll(outs[i]);
    }
  }

  void _track(int i, List<double> heard) {
    for (int k = 0; k < heard.length; k++) {
      final int t = _pos + k;
      final (int, int)? b = _onAir[i];
      final bool on = heard[k] != 0.0;
      if (b == null && on) {
        _onAir[i] = (t, t);
      } else if (b != null && on) {
        _onAir[i] = (b.$1, t);
      } else if (b != null && !on && t - b.$2 >= block) {
        bursts[i].add((b.$1, b.$2 + 1));
        _onAir[i] = null;
      }
    }
  }

  bool runUntil(double s, bool Function(Air) done) {
    final double limit = secs + s;
    while (secs < limit) {
      if (done(this)) return true;
      step();
    }
    return done(this);
  }

  bool has(int i, Report r) => events[i].any((e) => e.$2 == r);

  int topTx(int i) {
    int top = 0;
    for (final (double, Report) e in events[i]) {
      final Report r = e.$2;
      if (r is ReportBitrate && r.tx && r.level > top) top = r.level;
    }
    return top;
  }

  String trace() {
    final List<String> v = <String>[
      for (int i = 0; i < n; i++)
        for (final (double t, Report r) in events[i])
          if (r is! ReportPtt) '${t.toStringAsFixed(2).padLeft(8)} $i $r',
    ]..sort();
    return v.join('\n');
  }
}

class Lead {
  final List<int> ms;
  final bool told;

  const Lead([this.ms = const <int>[0, 0], this.told = false]);
}

class Failure implements Exception {
  final String kind;
  final String detail;

  Failure(this.kind, this.detail);

  @override
  String toString() => '$kind:\n$detail';
}

FmConfig fmCfg(FmBandwidth bw, String call, int seed, bool registered) {
  final FmConfig c = FmConfig(bw, call)..seed = seed;
  c.host.registered = registered;
  c.host.compression = Compression.off;
  return c;
}

Air fmAir(List<FmBandwidth> bw, bool registered, double noise, Lead lead) {
  StationOptions opts(int i) => StationOptions(txLatency: lead.told ? lead.ms[i] * 48 : 0);
  return Air.pair(
    <FmStation>[
      FmStation(fmCfg(bw[0], 'N0CALL', 3, registered), opts(0)),
      FmStation(fmCfg(bw[1], 'N1CALL', 5, registered), opts(1)),
    ],
    <int>[for (int i = 0; i < 2; i++) 2400 + lead.ms[i] * 48],
    noise,
    skipBufferBusy,
  );
}

List<String> hostLines(Air a, int i) => <String>[
      for (final (double, Report) e in a.events[i])
        if (e.$2 is ReportLine)
          (e.$2 as ReportLine).text
        else if (e.$2 == const ReportHost(hostDisconnected))
          'DISCONNECTED',
    ];

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Air sessionLed(List<FmBandwidth> bw, bool registered, double noise, Uint8List pa, Uint8List pb, Lead lead) {
  final Air air = fmAir(bw, registered, noise, lead);
  air.st[1].send(pb);
  expect(air.st[0].connect('N0CALL', 'N1CALL', const <String>[]), isTrue);
  final FmBandwidth link = bw[0] == FmBandwidth.wide && bw[1] == FmBandwidth.wide ? FmBandwidth.wide : FmBandwidth.narrow;
  final Report line = ReportHost(HostConnected('N0CALL', 'N1CALL', const <String>[], LinkBwFm(link)));
  if (!air.runUntil(30.0, (a) => a.has(0, line) && a.has(1, line))) throw Failure('no link', air.trace());
  air.st[0].send(pa);
  final double secs = 60.0 + (pa.length + pb.length) / 60.0;
  if (!air.runUntil(secs, (a) => a.got[1].length >= pa.length && a.got[0].length >= pb.length)) {
    throw Failure('stalled', '${air.got[1].length}/${pa.length} and ${air.got[0].length}/${pb.length}:\n${air.trace()}');
  }
  expect(sameBytes(air.got[1], pa), isTrue);
  expect(sameBytes(air.got[0], pb), isTrue);
  air.st[0].disconnect();
  if (!air.runUntil(30.0, (a) => a.st.every((s) => s.idle))) throw Failure('no disconnect', air.trace());
  expect(hostLines(air, 0).last, 'DISCONNECTED', reason: air.trace());
  expect(hostLines(air, 1).last, 'DISCONNECTED', reason: air.trace());
  expect(air.st[1].state, FmState.listen);
  return air;
}

Air session(List<FmBandwidth> bw, bool registered, double noise, Uint8List pa, Uint8List pb) =>
    sessionLed(bw, registered, noise, pa, pb, const Lead());

List<String> kissLines(Air a, int i) => <String>[
      for (final (double, Report) e in a.events[i])
        ...switch (e.$2) {
          ReportLine(:final String text) => <String>[text],
          ReportKiss(:final KissCommand cmd, :final Uint8List data) => <String>['KISS ${cmd.byte} ${String.fromCharCodes(data)}'],
          ReportHost(:final HostEvent event) when event == hostPending => <String>['PENDING'],
          ReportHost(:final HostEvent event) when event == hostCancelPending => <String>['CANCELPENDING'],
          ReportPtt(:final bool on) => <String>['PTT $on'],
          ReportBitrate(:final int level, :final int bps, :final bool tx) => <String>['BITRATE $level $bps $tx'],
          _ => const <String>[],
        },
    ];

Air led(List<int> ms, bool told) =>
    sessionLed(const <FmBandwidth>[FmBandwidth.narrow, FmBandwidth.narrow], true, 0.002, payload(8000, 12),
        payload(1500, 13), Lead(ms, told));

double pttOffAt(Air a, int i) => a.events[i].lastWhere((e) => e.$2 == const ReportPtt(false)).$1;

Air trio(FmBandwidth bw, bool registered) {
  final FmStation d = FmStation(fmCfg(bw, 'N9DIG', 7, registered), StationOptions());
  d.setDigipeater('N2CALL');
  return Air(
    <FmStation>[
      FmStation(fmCfg(bw, 'N0CALL', 3, registered), StationOptions()),
      d,
      FmStation(fmCfg(bw, 'N1CALL', 5, registered), StationOptions()),
    ],
    const <int>[2400, 2400, 2400],
    const <List<int>>[<int>[1], <int>[0, 2], <int>[1]],
    0.0,
    skipBufferBusy,
  );
}

(List<double>, List<Report>) runSilent(FmStation st, int n) {
  final List<double> out = List<double>.filled(n, 0.0);
  st.process(List<double>.filled(n, 0.0), out);
  final List<Report> rep = <Report>[];
  while (true) {
    final Report? r = st.pop();
    if (r == null) break;
    rep.add(r);
  }
  return (out, rep);
}

int secondCallAt(FmStation st) {
  expect(st.connect('N0CALL', 'N1CALL', const <String>[]), isTrue);
  int keyed = 0;
  final List<double> one = <double>[0.0];
  for (int t = 0; t < 48000 * 10; t++) {
    final List<double> out = <double>[0.0];
    st.process(one, out);
    bool sawKey = false;
    while (true) {
      final Report? r = st.pop();
      if (r == null) break;
      if (r == const ReportPtt(true)) sawKey = true;
    }
    if (sawKey) {
      keyed++;
      if (keyed == 2) return t;
    }
  }
  fail('no retry');
}

const List<FmBandwidth> nn = <FmBandwidth>[FmBandwidth.narrow, FmBandwidth.narrow];
const List<FmBandwidth> ww = <FmBandwidth>[FmBandwidth.wide, FmBandwidth.wide];
const Timeout slow = Timeout(Duration(minutes: 20));

void main() {
  group('fm station', () {
    test('link level is a data level', () {
      final FmStation st = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions());
      expect(st.session.level, FmRecord.start);
      expect(st.link().level, 1);
    });

    test('tune keys and unkeys the PTT', () {
      final FmStation st = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions(driveDb: -10.0));
      expect(st.tune(true), isTrue);
      final (List<double> x, List<Report> rep) = runSilent(st, 4800);
      expect(rep.contains(const ReportPtt(true)), isTrue);
      final double peak = x.fold(0.0, (m, v) => math.max(m, v.abs()));
      expect(peak, FmStation.tuneTone(-10.0).fold(0.0, (double m, v) => math.max(m, v.abs())));
      expect(st.tune(false), isTrue);
      final (List<double> y, List<Report> rep2) = runSilent(st, 480);
      expect(rep2.contains(const ReportPtt(false)), isTrue);
      expect(y.every((v) => v == 0.0), isTrue);
    });

    test('a PTT lead holds the PTT report until the audio is out', () {
      for (final (int start, int? now) in <(int, int?)>[(4800, null), (0, 4800), (1000, 4800)]) {
        final FmStation st = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions(txLatency: start));
        if (now != null) st.setTxLatency(now, 0);
        expect(st.options.txLatency, 4800);
        expect(st.tune(true), isTrue);
        expect(runSilent(st, 4800).$2.contains(const ReportPtt(true)), isTrue);
        expect(st.tune(false), isTrue);
        final (List<double> x, List<Report> rep) = runSilent(st, 4800);
        expect(x.every((v) => v == 0.0), isTrue);
        expect(!rep.contains(const ReportPtt(false)) && st.ptt && !st.idle, isTrue);
        expect(runSilent(st, 1).$2, <Report>[const ReportPtt(false)]);
        expect(!st.ptt && st.idle, isTrue);
      }
    });

    test('the PTT drops when the audio ends, not a capture lag later', () {
      final FmStation st =
          FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions(txLatency: 4800, rxLag: 1000));
      expect(st.tune(true), isTrue);
      expect(runSilent(st, 4800).$2.contains(const ReportPtt(true)), isTrue);
      expect(st.tune(false), isTrue);
      expect(!runSilent(st, 3800).$2.contains(const ReportPtt(false)) && st.ptt, isTrue);
      expect(runSilent(st, 1).$2, <Report>[const ReportPtt(false)]);
      st.setTxLatency(4800, 4800);
      expect(st.tune(true), isTrue);
      runSilent(st, 480);
      expect(st.tune(false), isTrue);
      expect(runSilent(st, 1).$2, <Report>[const ReportPtt(false)]);
    });

    test('the reply window opens when the PTT tail ends', () {
      FmStation fm(int t) => FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions(pttTail: t));
      expect(secondCallAt(fm(4800)) - secondCallAt(fm(0)), 4800);
    }, timeout: slow);

    test('tune refused outside listen', () {
      final FmStation st = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions());
      expect(st.connect('N0CALL', 'N1CALL', const <String>[]), isTrue);
      expect(st.state, FmState.calling);
      expect(st.tune(true), isFalse);
    });

    test('data before a link is bounded by the TX ring', () {
      final FmStation st = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions());
      st.send(List<int>.filled(txRingBytes - 10, 0x55));
      st.send(List<int>.filled(30, 0x55));
      expect(st.buffered, txRingBytes);
    });

    test('KISS queue is bounded', () {
      final FmStation fm = FmStation(FmConfig(FmBandwidth.narrow, 'N0CALL'), StationOptions());
      expect(fm.kiss(KissCommand.generic, List<int>.filled(200, 0x61)), isTrue);
      expect(fm.kiss(KissCommand.generic, 'queued next'.codeUnits), isTrue);
      expect(fm.kiss(KissCommand.generic, List<int>.filled(kiss.maxQueuedBytes, 0x61)), isFalse);
    });
  });

  group('fm audio link', () {
    test('narrow unregistered over audio', () {
      final Air air = session(nn, false, 0.002, payload(2500, 1), payload(900, 2));
      expect(air.topTx(0), 2, reason: air.trace());
      expect(air.has(1, const ReportHost(HostRegistered(false))), isTrue);
    }, timeout: slow);

    test('wide unregistered over audio', () {
      final Air air = session(ww, false, 0.002, payload(2500, 3), payload(600, 4));
      expect(air.topTx(0), 2, reason: air.trace());
    }, timeout: slow);

    test('wide caller, narrow target links narrow', () {
      session(const <FmBandwidth>[FmBandwidth.wide, FmBandwidth.narrow], false, 0.002, payload(400, 5), Uint8List(0));
    }, timeout: slow);

    test('registered links climb over audio', () {
      for (final (FmBandwidth bw, int min) in <(FmBandwidth, int)>[(FmBandwidth.narrow, 6), (FmBandwidth.wide, 7)]) {
        final Air air = session(<FmBandwidth>[bw, bw], true, 0.001, payload(40000, 6), payload(1500, 7));
        expect(air.topTx(0) >= min, isTrue, reason: '$bw\n${air.trace()}');
      }
    }, timeout: slow);

    test('noisy links over audio', () {
      for (final (FmBandwidth bw, double noise, int min, double max) in <(FmBandwidth, double, int, double)>[
        (FmBandwidth.narrow, 0.02, 6, 40.0),
        (FmBandwidth.wide, 0.02, 6, 40.0),
        (FmBandwidth.narrow, 0.05, 6, 45.0),
        (FmBandwidth.narrow, 0.3, 2, 120.0),
      ]) {
        final Air air = session(<FmBandwidth>[bw, bw], true, noise, payload(8000, 8), payload(500, 9));
        expect(air.topTx(0) >= min && air.secs < max, isTrue,
            reason: '$bw noise $noise: ${air.secs.toStringAsFixed(1)} s\n${air.trace()}');
      }
    }, timeout: slow);

    test('lead-in adapts after the first report', () {
      final Air air = session(nn, false, 0.002, payload(1000, 10), payload(300, 11));
      final List<String> leads = <String>[
        for (final (double, Report) e in air.events[0])
          if (e.$2 is ReportTrace && (e.$2 as ReportTrace).text.startsWith('tx c'))
            (e.$2 as ReportTrace).text.split(' ').take(3).join(' '),
      ];
      expect(leads[0], 'tx c14 lead', reason: '$leads');
      expect(
          air.events[0].any((e) =>
              e.$2 is ReportTrace &&
              (e.$2 as ReportTrace).text.startsWith('tx c') &&
              (e.$2 as ReportTrace).text.contains('lead 1 ')),
          isTrue,
          reason: '$leads');
    }, timeout: slow);

    test('record 16 KISS and CQ over audio', () {
      final Air a = fmAir(nn, false, 0.0, const Lead());
      a.st[1].setKissRx(true);
      a.st[1].refreshListen();
      a.st[1].update((c) => c.host.chat = true);
      expect(a.st[0].kiss(KissCommand.generic, 'Hello'.codeUnits), isTrue);
      expect(a.st[0].cqFrame('N0CALL', null), isFalse);
      expect(a.runUntil(6.0, (a) => kissLines(a, 1).contains('KISS 2 Hello')), isTrue);
      expect(a.runUntil(2.0, (a) => a.st[0].idle), isTrue);
      expect(kissLines(a, 0), <String>['PENDING', 'BITRATE 1 566 true', 'PTT true', 'PTT false', 'CANCELPENDING']);
      expect(a.st[0].cqFrame('N0CALL-5', 'NARROW'), isTrue);
      expect(a.runUntil(6.0, (a) => kissLines(a, 1).any((l) => l.startsWith('CQFRAME'))), isTrue);
      expect(kissLines(a, 1).contains('CQFRAME N0CALL-5'), isTrue);
      a.st[1].setKissRx(false);
      a.st[1].refreshListen();
      expect(a.runUntil(2.0, (a) => a.st[0].idle), isTrue);
      final int n = kissLines(a, 1).length;
      expect(a.st[0].cqFrame('N0CALL', null), isTrue);
      a.runUntil(5.0, (_) => false);
      expect(kissLines(a, 1).length, n);
      expect(a.st[0].idle, isTrue);
      expect(a.st[1].state, FmState.listen);
    }, timeout: slow);

    test('PTT lead 500 ms at both ends', () {
      final Air a = led(<int>[500, 500], true);
      expect(a.topTx(0) >= 6 && a.secs < 45.0, isTrue, reason: '${a.secs.toStringAsFixed(1)} s\n${a.trace()}');
    }, timeout: slow);

    test('PTT lead 700 ms at both ends no longer slows the link', () {
      final Air before = led(<int>[700, 700], false), after = led(<int>[700, 700], true);
      expect(after.secs + 5.0 < before.secs, isTrue,
          reason: 'unaware ${before.secs.toStringAsFixed(1)} s, aware ${after.secs.toStringAsFixed(1)} s');
    }, timeout: slow);

    test('PTT lead 1000 ms at both ends', () {
      final Air after = led(<int>[1000, 1000], true);
      expect(after.secs < 50.0, isTrue, reason: 'aware ${after.secs.toStringAsFixed(1)} s');
      bool slowLink;
      String what;
      try {
        final Air b = led(<int>[1000, 1000], false);
        slowLink = b.secs > 2.0 * after.secs;
        what = '${b.secs.toStringAsFixed(1)} s';
      } on Failure catch (f) {
        slowLink = f.kind == 'stalled';
        what = f.kind;
      }
      expect(slowLink, isTrue, reason: 'unaware: $what, aware ${after.secs.toStringAsFixed(1)} s');
    }, timeout: slow);

    test('record 16 PTT report waits for the delayed audio', () {
      final List<double> off = <double>[];
      for (final int ms in <int>[0, 300]) {
        final Air a = fmAir(nn, false, 0.0, Lead(<int>[ms, 0], true));
        a.st[1].setKissRx(true);
        a.st[1].refreshListen();
        expect(a.st[0].kiss(KissCommand.generic, 'Hello'.codeUnits), isTrue);
        expect(a.runUntil(6.0, (a) => kissLines(a, 1).contains('KISS 2 Hello')), isTrue);
        expect(a.runUntil(2.0, (a) => a.st[0].idle), isTrue);
        expect(kissLines(a, 0), <String>['PENDING', 'BITRATE 1 566 true', 'PTT true', 'PTT false', 'CANCELPENDING']);
        off.add(pttOffAt(a, 0));
      }
      expect((off[1] - off[0] - 0.3).abs() < 0.015, isTrue, reason: '$off');
    }, timeout: slow);

    test('record 16 is still received after sending one with a PTT release delay', () {
      final Air a = fmAir(nn, false, 0.0, Lead(<int>[300, 0], true));
      a.st[0].setKissRx(true);
      a.st[1].setKissRx(true);
      expect(a.st[0].kiss(KissCommand.generic, 'Hello'.codeUnits), isTrue);
      expect(a.runUntil(6.0, (a) => kissLines(a, 1).contains('KISS 2 Hello')), isTrue);
      expect(a.runUntil(2.0, (a) => a.st[0].idle && a.st[1].idle), isTrue);
      expect(a.st[1].kiss(KissCommand.generic, 'Back'.codeUnits), isTrue);
      expect(a.runUntil(6.0, (a) => kissLines(a, 0).contains('KISS 2 Back')), isTrue, reason: a.trace());
    }, timeout: slow);
  });

  group('fm digi link', () {
    test('digipeated link over audio', () {
      final Air air = trio(FmBandwidth.narrow, true);
      final Uint8List pa = payload(1500, 1), pb = payload(700, 2);
      air.st[2].send(pb);
      expect(air.st[0].connect('N0CALL', 'N1CALL', const <String>['N2CALL']), isTrue);
      final Report line =
          ReportHost(HostConnected('N0CALL', 'N1CALL', const <String>['N2CALL'], const LinkBwFm(FmBandwidth.narrow)));
      expect(air.runUntil(40.0, (a) => a.has(0, line) && a.has(2, line)), isTrue, reason: 'no link:\n${air.trace()}');
      expect(air.st[1].digipeating, isTrue);
      expect(air.has(1, const ReportHost(hostPending)), isTrue);
      air.st[0].send(pa);
      final bool done = air.runUntil(240.0, (a) => a.got[2].length >= pa.length && a.got[0].length >= pb.length);
      expect(done, isTrue,
          reason: 'stalled at ${air.got[2].length}/${pa.length} ${air.got[0].length}/${pb.length}:\n${air.trace()}');
      expect(sameBytes(air.got[2], pa), isTrue);
      expect(sameBytes(air.got[0], pb), isTrue);
      expect(air.got[1], isEmpty);
      air.st[0].disconnect();
      expect(air.runUntil(40.0, (a) => a.st.every((s) => s.idle)), isTrue, reason: 'no disconnect:\n${air.trace()}');
      expect(air.st[2].state, FmState.listen);
      expect(air.has(1, const ReportHost(hostCancelPending)), isTrue);
      expect(air.has(1, const ReportHost(hostDisconnected)), isFalse);
    }, timeout: slow);

    test('digipeater ignores other paths', () {
      final Air air = trio(FmBandwidth.narrow, true);
      expect(air.st[0].connect('N0CALL', 'N1CALL', const <String>['N7CALL']), isTrue);
      air.runUntil(15.0, (_) => false);
      expect(air.st[1].digipeating, isFalse, reason: air.trace());
    }, timeout: slow);
  });
}
