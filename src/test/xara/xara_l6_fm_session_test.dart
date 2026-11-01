/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Layer 6 tests: the FM ARQ session. Ports XARA's `fm_session.rs`,
`fm_vectors.rs`, `fm_lab_replay.rs`, `fm_link.rs`, the timing unit tests and
the FM part of `edge_inputs.rs`. The link simulator transcript must match the
upstream golden file `golden/fm_link.txt` byte for byte.
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/arq_host.dart';
import 'package:htcommander/hamlib/xara/arq_time.dart';
import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/compression.dart';
import 'package:htcommander/hamlib/xara/fm_adapt.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_session.dart';
import 'package:htcommander/hamlib/xara/fm_timing.dart';
import 'package:htcommander/hamlib/xara/textcomp.dart';

import 'xara_arq_sim.dart';
import 'xara_vectors.dart';

typedef Link = SimLink<FmTx, FmListen>;

// ---------------------------------------------------------------- helpers

List<FmOutput> drain(FmSession s) {
  final List<FmOutput> out = <FmOutput>[];
  while (true) {
    final FmOutput? o = s.pop();
    if (o == null) return out;
    out.add(o);
  }
}

List<int> ctrlCodes(List<FmOutput> out) => <int>[
      for (final FmOutput o in out)
        if (o case OutTx<FmTx, FmListen>(tx: FmTxCtrl(:final int code))) code,
    ];

Uint8List delivered(List<FmOutput> out) => Uint8List.fromList(<int>[
      for (final FmOutput o in out)
        if (o case OutHost<FmTx, FmListen>(event: HostData(:final Uint8List data))) ...data,
    ]);

String outDebug(List<FmOutput> out) => out.map(fmOutputDebug).join('\n');

int secs(double t) => (t * second).truncate();

String compDebug(Compression c) => switch (c) {
      Compression.off => 'Off',
      Compression.text => 'Text',
      Compression.files => 'Files',
    };

FmBandwidth mode(Object? v) => v == 'WIDE' ? FmBandwidth.wide : FmBandwidth.narrow;

int u(Object? v) => (v as num).toInt();

FmRecord rec(Object? v) => FmRecord.fromIndex(u(v))!;

double r4(double x) => (x * 1e4).round() / 1e4;

// ------------------------------------------------------- simulator adapter

class FmSim extends SimSess<FmTx, FmListen> {
  final FmSession s;

  FmSim(FmConfig c) : s = FmSession(c);

  @override
  int get latency => second ~/ 50;

  @override
  FmOutput? next() => s.pop();

  @override
  String goldenLine(FmOutput o) {
    if (o case OutTx<FmTx, FmListen>(tx: FmTxData(:final FmRecord record, :final List<Uint8List> frames, :final int lead))) {
      return 'Tx(Data { record: ${record.index}, frames: [${frames.map(digest).join(', ')}], lead: $lead })';
    }
    if (o case OutHost<FmTx, FmListen>(event: HostData(:final Uint8List data))) {
      return 'Host(Data(${digest(data)}))';
    }
    return fmOutputDebug(o);
  }

  @override
  int? deadline() => s.nextDeadline();

  @override
  void tick(int now) => s.poll(now);

  @override
  void txDone(int now) => s.onTxDone(now);

  @override
  String get stateName => s.state.debug;

  @override
  (int, int) airtime(FmTx tx) => switch (tx) {
        FmTxCtrl(:final int lead) => ((lead + 10) * 1024, 0),
        FmTxData(:final FmRecord record, :final List<Uint8List> frames, :final int lead) =>
          ((lead + frames.length * s.bandwidth.level(record).nsym) * 1152, 640),
      };

  @override
  String what(FmTx tx) {
    switch (tx) {
      case FmTxCtrl(:final int code, :final int lead):
        return 'c${code}l$lead';
      case FmTxData(:final FmRecord record, :final List<Uint8List> frames):
        final int c = record == FmRecord.start ? 5 : 4;
        final int z = frames.where((f) => record != FmRecord.connect && f[f.length - c] & 0x20 != 0).length;
        return 'L${record.index}x${frames.length}${z > 0 ? 'z' : ''}';
    }
  }

  @override
  Payload? air(FmTx tx) => switch (tx) {
        FmTxCtrl(:final int code, :final int lead) => PayloadCtrl(code, lead),
        FmTxData(:final FmRecord record, :final List<Uint8List> frames) =>
          PayloadData(record.index, List<Uint8List?>.of(frames)),
      };

  @override
  void arrive(SimLink<FmTx, FmListen> l, int i, int start, int end, Payload p) {
    if (l.st[i].busy.any((b) => b.$1 < end && b.$2 > start)) return;
    final FmListen? listen = l.st[i].listen;
    if (listen == null) return;
    final double snr = l.ch.snr;
    switch (p) {
      case PayloadCtrl(:final int code, :final int lead):
        if (listen.codes.contains(code)) {
          s.onCtrl(l.now, CtrlIn(code, 29 - lead, end));
        }
      case PayloadData(:final int level, :final List<Uint8List?> frames):
        final FmRecord record = FmRecord.fromIndex(level)!;
        if (listen.records.contains(record)) {
          final List<FrameIn> f = <FrameIn>[
            for (final Uint8List? b in frames) b != null ? FrameIn(true, b, snr) : FrameIn(false, Uint8List(0), 0.0),
          ];
          s.onData(l.now, DataIn(record, f, end));
        } else {
          final String t = (l.now / second).toStringAsFixed(2).padLeft(8);
          l.log.add('$t $i not listening for L${record.index} ([${listen.records.map((r) => r.index).join(', ')}])');
        }
    }
  }
}

FmSession sess(Link l, int i) => (l.st[i].s as FmSim).s;

Link newLink(FmConfig a, FmConfig b, Channel ch, int seed) => Link(FmSim(a), FmSim(b), ch, seed);

FmConfig cfg(FmBandwidth bw, String call, bool registered) {
  final FmConfig c = FmConfig(bw, call);
  c.host.registered = registered;
  c.host.compression = Compression.off;
  return c;
}

bool disconnected(Link l) =>
    l.st.every((s) => s.host.contains(hostDisconnected) && (s.s as FmSim).s.state == FmState.listen);

bool connectedNow(Link l) => l.st.every((s) => (s.s as FmSim).s.state != FmState.listen);

void checkBytes(Link l, List<int> got, List<int> want) {
  if (got.length == want.length) {
    bool same = true;
    for (int i = 0; i < got.length; i++) {
      if (got[i] != want[i]) {
        same = false;
        break;
      }
    }
    if (same) return;
  }
  int i = 0;
  while (i < got.length && i < want.length && got[i] == want[i]) {
    i++;
  }
  fail('got ${got.length} of ${want.length} bytes, first difference at $i\n${l.tail(150)}');
}

class Run {
  final FmBandwidth bw;
  final bool registered;
  final Compression comp;
  final Channel ch;
  final int seed;

  const Run(this.bw, this.registered, this.comp, this.ch, this.seed);
}

Run run(FmBandwidth bw, bool registered) => Run(bw, registered, Compression.off, clean, 1);

Link? transfer(Run r, Uint8List a, Uint8List b, double limit) {
  final FmConfig ca = cfg(r.bw, 'N0CALL', r.registered);
  ca.host.compression = r.comp;
  final Link l = newLink(ca, cfg(r.bw, 'N1CALL', false), r.ch, r.seed);
  if (b.isNotEmpty) sess(l, 1).send(0, b);
  sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
  l.flush();
  l.runUntil(120.0, simConnected);
  if (!simConnected(l)) {
    final int lost = l.log.where((x) => x.endsWith('lost on air') || x.endsWith('corrupted')).length;
    expect(lost, greaterThanOrEqualTo(2), reason: 'no link\n${l.log.join('\n')}');
    return null;
  }
  sess(l, 0).send(l.now, a);
  l.flush();
  l.runUntil(limit, (l) => (l.st[1].got >= a.length && l.st[0].got >= b.length) || !connectedNow(l));
  final Uint8List ra = l.st[1].rx(), rb = l.st[0].rx();
  if (ra.length < a.length || rb.length < b.length) {
    checkBytes(l, ra, a.sublist(0, ra.length < a.length ? ra.length : a.length));
    checkBytes(l, rb, b.sublist(0, rb.length < b.length ? rb.length : b.length));
    expect(r.ch.frameLoss > 0.0 || r.ch.ctrlLoss > 0.0, isTrue, reason: 'clean transfer stalled\n${l.tail(80)}');
    l.slow = true;
    return l;
  }
  checkBytes(l, ra, a);
  checkBytes(l, rb, b);
  sess(l, 0).disconnect(l.now);
  l.flush();
  l.runUntil(120.0, disconnected);
  expect(disconnected(l), isTrue, reason: l.tail(40));
  return l;
}

Uint8List text(int n, int seed) => simText(
      const <String>['the', 'message', 'Winlink', 'station', 'N0CALL', 'report', '\r\n', 'Subject: '],
      n,
      seed,
    );

Link scripted(FmConfig ca, FmConfig cb, Channel ch, int seed, Uint8List a, Uint8List b, (int, int)? abort) {
  final Link l = newLink(ca, cb, ch, seed);
  if (b.isNotEmpty) sess(l, 1).send(0, b);
  sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
  l.flush();
  l.runUntil(120.0, simConnected);
  if (!simConnected(l)) return l;
  sess(l, 0).send(l.now, a);
  l.flush();
  if (abort != null) {
    final (int who, int k) = abort;
    int data(Link l) => l.st.expand((s) => s.sent).where((t) => t.startsWith('L')).length;
    final int n = data(l) + k;
    l.runUntil(600.0, (l) => data(l) >= n);
    sess(l, who).abort(l.now);
  } else {
    l.runUntil(600.0, (l) => (l.st[1].got >= a.length && l.st[0].got >= b.length) || !connectedNow(l));
    sess(l, 0).disconnect(l.now);
  }
  l.flush();
  l.runUntil(300.0, (l) => l.st.every((s) => (s.s as FmSim).s.state == FmState.listen));
  return l;
}

Link up(int seed) {
  const FmBandwidth n = FmBandwidth.narrow;
  final Link l = newLink(cfg(n, 'N0CALL', false), cfg(n, 'N1CALL', false), clean, seed);
  sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
  l.flush();
  l.runUntil(30.0, (l) => l.st.every((s) => (s.s as FmSim).s.state == FmState.idle));
  return l;
}

Link b2f(int seed, List<String> msgs) {
  final Link l = up(seed);
  final int now = l.now;
  for (final String m in msgs) {
    sess(l, 0).send(now, m.codeUnits);
  }
  l.flush();
  l.runUntil(60.0, disconnected);
  return l;
}

Channel lossy(int seed) => switch (seed % 3) {
      0 => const Channel(25.0, 0.15, 0.1, 0.05),
      1 => const Channel(15.0, 0.3, 0.2, 0.1),
      _ => const Channel(40.0, 0.05, 0.3, 0.02),
    };

// ------------------------------------------------------ fm_session.rs

(FmSession, int) textReceiver() {
  final FmConfig c = FmConfig(FmBandwidth.narrow, 'N0CALL');
  c.host.registered = true;
  c.host.compression = Compression.text;
  final FmSession s = FmSession(c);
  expect(s.connect(0, null, 'N1CALL', const <String>[]), isTrue);
  drain(s);
  s.onTxDone(second);
  const int t = second + second ~/ 2;
  s.onCtrl(t, const CtrlIn(FmCode.connectReplyNarrow, 1, t));
  expect(ctrlCodes(drain(s)), <int>[FmCode.goAhead]);
  expect(s.state, FmState.receiving);
  s.onTxDone(2 * second);
  return (s, 3 * second);
}

DataIn startFrame(List<int> data) {
  final int len = FmBandwidth.narrow.level(FmRecord.start).frameBytes;
  final Uint8List bytes = buildData(FmRecord.start, len, data, true, 2, false, const Trailer(leadReport: 1));
  return DataIn(FmRecord.start, <FrameIn>[FrameIn(true, bytes, 30.0)], 3 * second);
}

// --------------------------------------------------- fm_lab_replay.rs

FmSession caller() {
  final FmSession s = FmSession(FmConfig(FmBandwidth.narrow, 'N0CALL'));
  expect(s.connect(0, null, 'N1CALL', const <String>[]), isTrue);
  drain(s);
  s.onTxDone(secs(8.0));
  s.onCtrl(secs(9.0), CtrlIn(FmCode.connectReplyNarrow, 1, secs(9.0)));
  expect(ctrlCodes(drain(s)), <int>[FmCode.goAhead]);
  s.onTxDone(secs(9.9));
  return s;
}

List<Map<String, dynamic>> labCases(String run, String dir) => <Map<String, dynamic>>[
      for (final dynamic c in loadDoc('fm/lab_frames')['cases'] as List)
        if (c['run'] == run && c['dir'] == dir && c['record'] != 0) c as Map<String, dynamic>,
    ];

List<Uint8List> labFrames(Map<String, dynamic> c) {
  final Object? h = c['frame_hex'];
  return h is List ? <Uint8List>[for (final Object? x in h) hexDecode(x as String)] : <Uint8List>[hexDecode(h as String)];
}

(Uint8List, List<List<Uint8List>>) replay(String run, List<(int, int)> polls, List<int> acks) {
  final List<Map<String, dynamic>> cs = labCases(run, 'ba');
  final FmSession s = caller();
  final List<int> got = <int>[], codes = <int>[];
  final List<List<Uint8List>> pay = <List<Uint8List>>[];
  for (final Map<String, dynamic> c in cs) {
    final int tEnd = secs((c['t'] as num).toDouble() + 11.0);
    final String rule = (c['rule'] as String?) ?? '';
    final int idx = u(c['idx']);
    final List<Uint8List> fr = labFrames(c);
    final List<int> lens = <int>[for (final dynamic f in c['fields'] as List) u(f['data_len'])];
    pay.add(<Uint8List>[for (int i = 0; i < fr.length && i < lens.length; i++) fr[i].sublist(0, lens[i])]);
    bool lost(int i) => switch (rule) {
          'zero@0.6-5.38' => i == 0,
          'zero@5.38-11' => i == 1,
          _ => false,
        };
    final DataIn d = DataIn(
      FmRecord.fromIndex(u(c['record']))!,
      <FrameIn>[for (int i = 0; i < fr.length; i++) FrameIn(!lost(i), fr[i], 40.0)],
      tEnd,
    );
    if (rule != 'mute') s.onData(tEnd, d);
    final List<FmOutput> out = drain(s);
    got.addAll(delivered(out));
    codes.addAll(ctrlCodes(out));
    s.onTxDone(tEnd + second ~/ 4);
    for (final (int, int) p in polls.where((p) => p.$1 == idx)) {
      final int t = tEnd + 2 * second;
      s.onCtrl(t, CtrlIn(p.$2, 1, t));
      codes.addAll(ctrlCodes(drain(s)));
      s.onTxDone(t + second ~/ 4);
    }
  }
  expect(codes, acks, reason: run);
  return (Uint8List.fromList(got), pay);
}

// --------------------------------------------------- fm_vectors.rs (lab)

(double, double)? zeroed(String rule) {
  if (!rule.startsWith('zero@')) return null;
  final List<String> p = rule.substring(5).split('-');
  if (p.length != 2) return null;
  final double? a = double.tryParse(p[0]), b = double.tryParse(p[1]);
  return a == null || b == null ? null : (a, b);
}

bool labLost(String rule, int fi, int nf, bool Function(double, double) singleLost) {
  if (rule == 'mute') return true;
  final (double, double)? z = zeroed(rule);
  if (z == null) return false;
  final (double t1, double t2) = z;
  const double f2 = 5.376;
  return nf == 2 ? (t1 < f2 && fi == 0) || (t2 > f2 + 0.6 && fi == 1) : singleLost(t1, t2);
}

double burstSecs(FmBandwidth bw, FmRecord record, int lead, int frames) =>
    (lead + frames * bw.level(record).nsym) * 1152.0 / 48000.0;

/// Rust `format!("{:.4}", x)` (round half to even on the exact binary value).
String f4(double x) => x.toStringAsFixed(4);

// ------------------------------------------------------- timing.rs tests

bool exchange(Timing t, int reply) {
  final bool ok = reply <= t.ctrlWindow();
  if (ok) {
    t.ctrl(reply);
  } else {
    t.miss();
  }
  return ok;
}

void main() {
  group('fm session', () {
    test('compressed frame is expanded and acked', () {
      final (FmSession s, int now) = textReceiver();
      final List<int> msg = 'the message '.codeUnits;
      final Encoded e = compress(msg, 10, 1);
      s.onData(now, startFrame(e.bytes));
      final List<FmOutput> out = drain(s);
      expect(delivered(out), msg.sublist(0, e.consumed));
      expect(ctrlCodes(out), <int>[FmCode.ackStay]);
    });

    test('compressed frame that does not expand is nacked', () {
      final (FmSession s, int now) = textReceiver();
      s.onData(now, startFrame(<int>[0]));
      final List<FmOutput> out = drain(s);
      expect(delivered(out), isEmpty, reason: outDebug(out));
      expect(ctrlCodes(out), <int>[FmCode.nack]);
    });

    test('compressed frame with a lost frame 2 is still expanded', () {
      final (FmSession s, int now) = textReceiver();
      final List<int> msg = r'[WL2K-5.0-B2FWIHJM$]'.codeUnits + <int>[13];
      final Encoded e = compress(msg, 30, 1);
      final DataIn d = startFrame(e.bytes);
      d.frames.add(FrameIn(false, Uint8List(0), 0.0));
      s.onData(now, d);
      final List<FmOutput> out = drain(s);
      expect(delivered(out), msg.sublist(0, e.consumed), reason: outDebug(out));
    });

    test('sessions without a callsign do not panic', () {
      final FmConfig c = FmConfig(FmBandwidth.narrow, 'N0CALL');
      c.host.mycalls.clear();
      final FmSession s = FmSession(c);
      s.connect(0, null, 'N1CALL', const <String>[]);
      drain(s);
    });
  });

  group('fm timing', () {
    test('drifting control replies stay inside the window', () {
      final Timing t = Timing(FmBandwidth.wide, 0);
      t.ctrl(372);
      int missed = 0;
      for (int k = 0; k < 200; k++) {
        if (!exchange(t, 166 + 8 * k)) missed++;
      }
      expect(missed, lessThanOrEqualTo(2));
    });

    test('a window left behind widens until it catches up', () {
      final Timing t = Timing(FmBandwidth.wide, 0);
      t.ctrl(372);
      for (int i = 0; i < 20; i++) {
        t.ctrl(200);
      }
      int tries = -1;
      for (int i = 0; i < 10; i++) {
        if (exchange(t, 400)) {
          tries = i;
          break;
        }
      }
      expect(tries, 4);
      final List<bool> ok = <bool>[for (int i = 0; i < 30; i++) exchange(t, 400)];
      expect(ok.sublist(15).every((o) => o), isTrue, reason: '$ok');
    });

    test('a measured reply clears the misses', () {
      final Timing t = Timing(FmBandwidth.wide, 0);
      t.ctrl(372);
      t.ctrl(200);
      final int base = t.ctrlWindow();
      t.miss();
      t.miss();
      expect(t.ctrlWindow(), base + 2 * missTicks);
      expect(t.dataWindow(FmRecord.start), t.window[FmRecord.start.index] + 2 * missTicks);
      t.ctrl(200);
      expect(t.ctrlWindow(), base);
    });
  });

  group('fm vectors', () {
    test('level tables match VARA', () {
      int n = 0;
      for (final dynamic r in loadDoc('fm/levels')['records'] as List) {
        final FmBandwidth bw = mode(r['mode']);
        final FmRecord record = rec(r['record']);
        final FmLevel l = bw.level(record);
        final String ctx = '$r';
        expect(l.frameBytes, u(r['frame_bytes']), reason: ctx);
        expect(l.spf, u(r['spf']), reason: ctx);
        expect(payload(bw, record, false), u(r['payload_direct']), reason: ctx);
        if (r['payload_with_vias'] != null) {
          expect(payload(bw, record, true), u(r['payload_with_vias']), reason: ctx);
        }
        expect(frameTicks(bw, record), u(r['frame_ticks']), reason: ctx);
        expect(thr(bw, record), (r['snr_threshold_db'] as num).toDouble(), reason: ctx);
        expect(decodeAllow(bw, record), u(r['decode_allow_ticks']), reason: ctx);
        expect(widePenalty(bw, record), (r['wide_penalty_db'] as num).toDouble(), reason: ctx);
        expect(roundTiesEvenInt(l.netBps), u(r['net_bitrate']), reason: ctx);
        n++;
      }
      expect(n, 34);
    });

    test('queue hint matches VARA', () {
      final List<dynamic> cases = loadDoc('fm/hint')['cases'] as List;
      for (final dynamic c in cases) {
        final int h = queueHint(mode(c['mode']), rec(c['level']), u(c['queued_after']), c['vias'] as bool);
        expect(h, u(c['hint']), reason: '$c');
      }
      expect(cases.length, 77);
    });

    test('ack decisions match VARA', () {
      final Map<String, dynamic> v = loadDoc('fm/ack');
      int n = 0;
      for (final dynamic s in v['sequences'] as List) {
        final FmBandwidth bw = mode(s['mode']);
        final bool reg = s['registered'] as bool;
        final Adaptation ad = Adaptation();
        int lvl = 15;
        for (final dynamic st in s['steps'] as List) {
          if ((st as Map).containsKey('event')) {
            ad.frameLost();
            lvl = lvl == 14 || lvl == 15 ? 1 : (lvl - 1 < 1 ? 1 : lvl - 1);
            continue;
          }
          expect(lvl, u(st['level']), reason: '$st');
          final Heard h = Heard(FmRecord.fromIndex(lvl)!, u(st['hint']), st['complete'] as bool);
          final Decision d = frameOkAndDecide(bw, ad, h, (st['snr'] as num).toDouble(), reg);
          final String ctx = '${s['name']} $st';
          expect(d.code, u(st['code']), reason: ctx);
          expect(d.level, rec(st['next_level']), reason: ctx);
          expect(d.stayReset, st['explicit_stay_reset'] as bool, reason: ctx);
          expect(r4(d.held), (st['held_snr'] as num).toDouble(), reason: ctx);
          const List<String> keys = <String>['m0', 'm1', 'm2', 'm3', 'm6'];
          for (int i = 0; i < keys.length; i++) {
            expect(r4(d.m[i]), (st[keys[i]] as num).toDouble(), reason: '$ctx ${keys[i]}');
          }
          expect(r4(ad.ratio()), (st['ratio'] as num).toDouble(), reason: ctx);
          lvl = d.level.index;
          n++;
        }
      }
      for (final dynamic c in v['sender'] as List) {
        expect(senderLevelAfter(rec(c['level']), u(c['code'])), rec(c['next_level']), reason: '$c');
        n++;
      }
      expect(n, greaterThanOrEqualTo(70));
    });

    test('timing windows match VARA', () {
      final Map<String, dynamic> v = loadDoc('fm/timing');
      int n = 0;
      for (final dynamic c in v['cases'] as List) {
        final FmBandwidth bw = mode(c['mode']);
        final int vias = u(c['vias']);
        final int top = bw.numLevels;
        expect(callerConnectWindow(bw, vias, false), u(c['caller_connect_window']));
        expect(callerConnectWindow(bw, vias, true), u(c['caller_connect_window_activescan']));
        Timing t = Timing(bw, vias);
        t.ack(400, FmRecord.connect);
        dynamic s = c['seed_from_23_24_at_400_ticks'];
        expect(t.window.sublist(1, top + 1), ints(s['ack_window']), reason: '$c');
        expect(t.ctrlWindow(), u(s['ctrl_window']), reason: '$c');
        expect(t.window.sublist(14, 16), ints(s['ack_window_rec14_15']), reason: '$c');
        t = Timing(bw, vias);
        t.ctrl(350);
        s = c['seed_from_14_at_350_ticks'];
        expect(t.window.sublist(1, top + 1), ints(s['ack_window']), reason: '$c');
        expect(t.ctrlWindow(), u(s['ctrl_window']), reason: '$c');
        for (final dynamic w in c['receiver_sync_window'] as List) {
          final (double lo, double hi) = receiverSyncWindow(bw, rec(w['level']), vias, false);
          expect((lo, hi), ((w['lo'] as num).toDouble(), (w['hi'] as num).toDouble()), reason: '$c');
          n++;
        }
        for (final dynamic w in (c['receiver_sync_window_double'] as List?) ?? const <dynamic>[]) {
          final (double lo, double hi) = receiverSyncWindow(bw, rec(w['level']), 0, true);
          expect((lo, hi), ((w['lo'] as num).toDouble(), (w['hi'] as num).toDouble()), reason: '$c');
          n++;
        }
        n += 5;
      }
      final Timing t = Timing(FmBandwidth.narrow, 0);
      t.ack(400, FmRecord.connect);
      for (final dynamic s in v['ack_sequence_narrow_direct'] as List) {
        t.ack(u(s['ack_ticks']), rec(s['level']));
        expect(t.mean.sublist(1, 12), ints(s['means']), reason: '$s');
        expect(t.window.sublist(1, 12), ints(s['windows']), reason: '$s');
        expect(t.window.sublist(14, 16), ints(s['rec14_15']), reason: '$s');
        expect(t.ctrlWindow(), u(s['ctrl_window']), reason: '$s');
        n++;
      }
      expect(n, greaterThanOrEqualTo(60));
    });

    test('queue hints match lab frames', () {
      final Map<String, dynamic> v = loadDoc('fm/lab_frames');
      final Map<String, int> total = <String, int>{
        for (final MapEntry<String, dynamic> e in (v['checks']['delivered_bytes'] as Map<String, dynamic>).entries)
          e.key: u(e.value['delivered']),
      };
      total['f17_poor:ba'] = 3000;
      final Map<String, int> got = <String, int>{};
      int n = 0, ok = 0;
      for (final dynamic c in v['cases'] as List) {
        final FmRecord record = rec(c['record']);
        final String key = '${c['run']}:${c['dir']}';
        final int? tot = total[key];
        if (tot == null) continue;
        if (record == FmRecord.connect || record == FmRecord.broadcast) continue;
        final FmBandwidth bw = mode(c['mode']);
        final String rule = (c['rule'] as String?) ?? '';
        final List<dynamic> fields = c['fields'] as List;
        final int nf = fields.length;
        final int base = got[key] ?? 0;
        int taken = 0;
        for (int fi = 0; fi < nf; fi++) {
          final dynamic f = fields[fi];
          taken += u(f['data_len']);
          final int q = tot - (base + taken) < 0 ? 0 : tot - (base + taken);
          final int h = queueHint(bw, record, q, false);
          n++;
          if (h == u(f['hint'])) ok++;
          expect(h, u(f['hint']), reason: '$key idx ${c['idx']} frame $fi q $q');
          final bool last = q == 0 && (nf == 1 || fi == 1);
          expect(last ? 1 : 0, u(f['last']), reason: '$key idx ${c['idx']}');
        }
        int g = 0;
        for (int fi = 0; fi < nf; fi++) {
          if (!labLost(rule, fi, nf, (t1, t2) => t2 - t1 > 0.1)) g += u(fields[fi]['data_len']);
        }
        got[key] = (got[key] ?? 0) + g;
      }
      expect((ok, n), (74, 74));
    });

    test('ack decisions match lab frames', () {
      final Map<String, dynamic> v = loadDoc('fm/lab_frames');
      final Map<String, (int, List<bool>)> info = <String, (int, List<bool>)>{};
      for (final dynamic c in v['cases'] as List) {
        final String k = '${c['run']}|${f4((c['t'] as num).toDouble())}';
        info[k] = (u(c['leadin']), <bool>[for (final dynamic f in c['fields'] as List) f['last'] == 1]);
      }
      final Map<String, Adaptation> ads = <String, Adaptation>{};
      int n = 0, ok = 0;
      for (final dynamic c in v['checks']['ack_decisions']['cases'] as List) {
        final String run = c['run'] as String;
        final FmBandwidth bw = run == 'f10_wide' ? FmBandwidth.wide : FmBandwidth.narrow;
        final Adaptation ad = ads.putIfAbsent('$run|${c['rx']}', Adaptation.new);
        final int obs = u(c['obs']);
        final FmRecord record = rec(c['record']);
        final int nf = u(c['frames']);
        final String rule = (c['rule'] as String?) ?? '';
        n++;
        if (rule == 'mute') {
          ad.frameLost();
          if (obs == 2) ok++;
          continue;
        }
        final (int lead, List<bool> lasts) = info['$run|${f4((c['t'] as num).toDouble())}']!;
        final double dur = burstSecs(bw, record, lead, nf);
        final List<bool> good = <bool>[for (int i = 0; i < nf; i++) !labLost(rule, i, nf, (t1, _) => t1 <= 0.75 * dur)];
        final double sn = (c['sn'] as num).toDouble();
        final int hint = u(c['hint']);
        if (nf == 2) {
          if (good[0]) {
            ad.frameOk(sn, asLevel(record), bw.numLevels);
          } else {
            ad.frameLost();
          }
          if (!good[1]) ad.frameLost();
        }
        final int pred;
        if (nf == 2 && good[0] && !good[1]) {
          pred = 11;
        } else if (nf == 1 && !good[0]) {
          pred = 2;
        } else if (lasts.last) {
          ad.frameOk(sn, asLevel(record), bw.numLevels);
          pred = 4;
        } else {
          pred = frameOkAndDecide(bw, ad, Heard(record, hint, good[0]), sn, false).code;
        }
        expect(pred, obs, reason: '$c');
        if (pred == obs) ok++;
      }
      expect((ok, n), (68, 68));
    });

    test('windows match lab timing', () {
      final List<dynamic> ev = loadDoc('fm/lab_timing')['events'] as List;
      const FmBandwidth bw = FmBandwidth.narrow;
      int ticks(double s) => (s * second).truncate() ~/ tick + detectHold;
      final int w3 = callerConnectWindow(bw, 0, false);
      final dynamic retry = ev.firstWhere((e) => e['what'] == 'caller CONNECT retry, direct');
      final double obs = (retry['observed_s_after_rec0_end'] as num).toDouble();
      expect((obs - w3 * tick / second - 0.02).abs(), lessThan(0.1), reason: '$obs');
      final Timing t = Timing(bw, 0);
      t.ack(400, FmRecord.connect);
      t.ctrl(128);
      t.ack(129, FmRecord.start);
      final int w2 = t.dataWindow(FmRecord.fromIndex(2)!);
      final dynamic b = ev.firstWhere((e) => (e['what'] as String).startsWith('ACK window boundary'));
      int n = 0;
      for (final dynamic c in b['cases'] as List) {
        final double end = (c['ack_end_after_data_end_s'] as num).toDouble();
        expect(ticks(end) <= w2, c['accepted'] as bool, reason: '$c w2 $w2');
        n++;
      }
      final dynamic wd = ev.firstWhere((e) => e['what'] == 'disconnect watchdog, direct');
      expect(((wd['observed_s'] as num).toDouble() - watchdog(0) / second).abs(), lessThan(0.2));
      expect(<int>[watchdog(0), watchdog(1), watchdog(2)], <int>[16400 * 48, 22400 * 48, 31400 * 48]);
      expect(n, 3);
    });
  });

  group('fm lab replay', () {
    Uint8List cat(List<List<int>> parts) => Uint8List.fromList(parts.expand((p) => p).toList());

    test('f13 frame 1 resend reassembles like VARA', () {
      final (Uint8List got, List<List<Uint8List>> p) = replay('f13_mute_f1', const <(int, int)>[], <int>[7, 1, 1, 10, 1, 4]);
      final Uint8List want = cat(<List<int>>[
        p[0][0], p[1][0], p[2][0], p[4][0], p[5][0], p[5][1].sublist(0, 37), p[3][1], p[5][1].sublist(37),
      ]);
      expect(want.length, 3000);
      expect(got, want);
    });

    test('f05 frame 2 resend reassembles like VARA', () {
      final (Uint8List got, List<List<Uint8List>> p) =
          replay('f05_mute_f2', const <(int, int)>[], <int>[7, 1, 1, 11, 1, 1, 4]);
      final Uint8List want = cat(<List<int>>[p[0][0], p[1][0], p[2][0], p[3][0], p[4][0], p[5][0], p[6][0]]);
      expect(want.length, 3000);
      expect(got, want);
    });

    test('f04 lost ack is repeated, not redelivered', () {
      final (Uint8List got, List<List<Uint8List>> p) =
          replay('f04_mute_ack', const <(int, int)>[(3, 13)], <int>[7, 1, 1, 1, 6, 4]);
      final Uint8List want = cat(<List<int>>[p[0][0], p[1][0], p[2][0], p[3][0], p[3][1], p[4][0]]);
      expect(want.length, 3000);
      expect(got, want);
    });

    test('f03 lost data is resent once', () {
      final (Uint8List got, List<List<Uint8List>> p) =
          replay('f03_mute_data', const <(int, int)>[(4, 12)], <int>[7, 1, 2, 1, 1, 1, 1, 4]);
      final Uint8List want = cat(<List<int>>[
        p[0][0], p[1][0], p[3][0], p[4][0], p[5][0], p[5][1], p[6][0], p[6][1], p[7][0],
      ]);
      expect(want.length, 3000);
      expect(got, want);
    });
  });

  group('fm link', () {
    test('link start matches lab sequence', () {
      final Link l = up(1);
      expect(l.st[0].sent, <String>['L0x1', 'c14l28', 'c4l1', 'c20l1'], reason: l.log.join('\n'));
      expect(l.st[1].sent, <String>['c23l28', 'L15x1', 'c14l28', 'c21l28']);
      final List<HostEvent> t = l.st[1].host.where((h) => h is! HostSn).toList();
      expect(t.sublist(0, 4), <HostEvent>[
        hostUnencrypted,
        hostPending,
        const HostConnected('N0CALL', 'N1CALL', <String>[], LinkBwFm(FmBandwidth.narrow)),
        const HostRegistered(false),
      ]);
      l.runUntil(200.0, disconnected);
      expect(disconnected(l), isTrue, reason: l.tail(30));
      expect(l.st[0].sent.where((c) => c == 'c20l1').length, 7, reason: '${l.st[0].sent}');
      final List<String> s0 = l.st[0].sent;
      expect(s0.sublist(s0.length - 2), <String>['c3l1', 'c3l1']);
      expect(l.st[0].host.contains(const HostLog('stopped sending due to CMS failure')), isTrue);
    });

    test('unregistered 3k from target follows lab ladder', () {
      final Link l = newLink(cfg(FmBandwidth.narrow, 'N0CALL', false), cfg(FmBandwidth.narrow, 'N1CALL', false), clean, 2);
      final Uint8List data = simPayload(3000, 5);
      sess(l, 1).send(0, data);
      sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
      l.flush();
      l.runUntil(120.0, (l) => l.st[0].got >= 3000);
      l.runUntil(3.0, (_) => false);
      checkBytes(l, l.st[0].rx(), data);
      expect(l.st[1].sent.sublist(0, 7), <String>['c23l28', 'L15x1', 'L2x1', 'L2x1', 'L2x2', 'L1x1', 'c14l28'],
          reason: l.tail(40));
      expect(l.st[0].sent.sublist(1, 6), <String>['c14l28', 'c7l1', 'c1l1', 'c1l1', 'c6l1']);
    });

    test('small queue takes record 14', () {
      final Link l = newLink(cfg(FmBandwidth.narrow, 'N0CALL', false), cfg(FmBandwidth.narrow, 'N1CALL', false), clean, 2);
      sess(l, 1).send(0, simPayload(100, 5));
      sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
      l.flush();
      l.runUntil(60.0, (l) => l.st[0].got >= 100);
      expect(l.st[1].sent.sublist(0, 3), <String>['c23l28', 'L15x1', 'L14x1']);
      expect(l.st[0].sent.sublist(1, 4), <String>['c14l28', 'c1l1', 'c4l1']);
    });

    test('clean links both ways', () {
      for (final FmBandwidth bw in FmBandwidth.values) {
        for (final bool reg in <bool>[false, true]) {
          final Link l = transfer(run(bw, reg), simPayload(40000, 1), simPayload(9000, 2), 3000.0)!;
          final int top = l.st[0].levels().where((r) => r < 14).reduce((a, b) => a > b ? a : b);
          final int want = reg ? (bw == FmBandwidth.wide ? 13 : 11) : 2;
          expect(top, want, reason: '$bw reg $reg\n${l.st[0].sent}');
          expect(l.st[0].sent.any((t) => t.endsWith('x2')), isTrue, reason: 'never went two-frame');
          expect(l.st[1].host.contains(HostRegistered(reg)), isTrue);
        }
      }
    });

    test('lossy channels deliver exactly', () {
      int linked = 0, slow = 0;
      for (int seed = 1; seed <= 600; seed++) {
        final Channel ch = lossy(seed);
        final FmBandwidth bw = seed % 2 == 0 ? FmBandwidth.wide : FmBandwidth.narrow;
        const List<int> sizes = <int>[9000, 89, 335, 1, 0, 2873, 334 * 4];
        final int sa = sizes[seed % 7];
        final Uint8List a = simPayload(sa < 1 ? 1 : sa, seed);
        final Uint8List b = simPayload(sizes[(seed ~/ 7) % 7], seed + 1);
        final Link? l = transfer(Run(bw, seed % 4 < 2, Compression.off, ch, seed), a, b, 3000.0);
        if (l != null) {
          linked++;
          if (l.slow) slow++;
        }
      }
      expect(linked, greaterThanOrEqualTo(520), reason: '$linked of 600 linked');
      expect(slow * 4 <= linked, isTrue, reason: '$slow of $linked transfers unfinished');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('mild loss completes', () {
      int done = 0, n = 0;
      for (int seed = 1; seed <= 200; seed++) {
        const Channel ch = Channel(30.0, 0.05, 0.05, 0.01);
        final FmBandwidth bw = seed % 2 == 0 ? FmBandwidth.wide : FmBandwidth.narrow;
        final Run r = Run(bw, seed % 3 == 0, Compression.off, ch, seed + 1000);
        final Uint8List a = simPayload(6000, seed), b = simPayload(700, seed + 1);
        final Link? l = transfer(r, a, b, 3000.0);
        if (l != null) {
          n++;
          if (_eq(l.st[1].rx(), a) && _eq(l.st[0].rx(), b)) done++;
        }
      }
      expect(n >= 195 && done * 100 >= n * 97, isTrue, reason: '$done of $n complete');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('compression on registered links', () {
      for (final Compression comp in <Compression>[Compression.text, Compression.files]) {
        int linked = 0, unfinished = 0;
        for (int seed = 1; seed <= 40; seed++) {
          final Channel ch = seed == 1 ? clean : const Channel(30.0, 0.1, 0.1, 0.02);
          final Run r = Run(FmBandwidth.narrow, true, comp, ch, seed);
          final Uint8List a = text(12000, seed), b = text(1500, seed + 9);
          final Link? l = transfer(r, a, b, 3000.0);
          if (l == null) continue;
          linked++;
          if (!_eq(l.st[1].rx(), a) || !_eq(l.st[0].rx(), b)) unfinished++;
          if (seed == 1) {
            expect(l.st[0].sent.any((t) => t.endsWith('z')) || comp == Compression.files, isTrue, reason: '$comp');
            expect(_eq(l.st[1].rx(), a) && _eq(l.st[0].rx(), b), isTrue, reason: '$comp clean');
          }
        }
        expect(linked, greaterThanOrEqualTo(38), reason: '$comp: $linked of 40 linked');
        expect(unfinished, lessThanOrEqualTo(2), reason: '$comp: $unfinished of $linked transfers unfinished');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('unregistered link never compresses', () {
      final Link l = transfer(Run(FmBandwidth.narrow, false, Compression.text, clean, 3), text(4000, 1), Uint8List(0), 600.0)!;
      expect(l.st[0].sent.any((t) => t.endsWith('z')), isFalse);
    });

    test('connect to silence gives up on the watchdog', () {
      final Link l = newLink(cfg(FmBandwidth.narrow, 'N0CALL', false), cfg(FmBandwidth.narrow, 'N1CALL', false), clean, 1);
      l.st[1].deaf = true;
      sess(l, 0).connect(0, null, 'N1CALL', const <String>[]);
      l.flush();
      l.runUntil(60.0, (l) => l.st[0].host.contains(hostDisconnected));
      expect(l.st[0].sent, List<String>.filled(5, 'L0x1'));
      final double t = l.now / second;
      expect((t - 16.4).abs(), lessThan(0.1), reason: '$t');
      expect(l.st[0].host.contains(hostTimedOut), isTrue);
    });

    test('unregistered via is refused at the target', () {
      final FmSession t = FmSession(cfg(FmBandwidth.narrow, 'N1CALL', false));
      Record0 r = Record0.connect('N0CALL', 'N1CALL', 'N9DIG', '', false, false);
      DataIn frame(Record0 r) => DataIn(FmRecord.connect, <FrameIn>[FrameIn(true, r.toBytes()!, 30.0)], second);
      t.onData(second, frame(r));
      expect(t.state, FmState.listen);
      r = r.copyWith(hop: 1);
      t.onData(second, frame(r));
      List<FmOutput> out = drain(t);
      expect(out.any((o) => o is OutTx<FmTx, FmListen> && o.tx == const FmTxCtrl(3, 28)), isTrue, reason: outDebug(out));
      expect(out.any((o) => o is OutHost<FmTx, FmListen> && o.event == const HostSn(0.0)), isTrue);
      expect(out.any((o) => o is OutHost<FmTx, FmListen> && o.event is HostConnected), isFalse);
      t.onTxDone(2 * second);
      out = drain(t);
      expect(out.any((o) => o is OutTx<FmTx, FmListen>), isFalse, reason: outDebug(out));
      expect(out.any((o) => o is OutHost<FmTx, FmListen> && o.event == hostCancelPending), isTrue);
      expect(out.any((o) => o is OutHost<FmTx, FmListen> && o.event == hostDisconnected), isFalse);
      expect(t.state, FmState.listen);
    });

    test('caller via keys side zero by via1', () {
      final FmSession c = FmSession(cfg(FmBandwidth.narrow, 'N0CALL', false));
      expect(c.connect(0, null, 'N1CALL', const <String>['N9DIG']), isTrue);
      expect(c.key, callHash('N9DIG'.codeUnits));
      final List<FmOutput> out = drain(c);
      final Uint8List f = out
          .whereType<OutTx<FmTx, FmListen>>()
          .map((o) => o.tx)
          .whereType<FmTxData>()
          .first
          .frames[0];
      final Record0 r0 = Record0.parse(f)!;
      expect((r0.hop, r0.via1, r0.registered), (0, 'N9DIG', false));
    });

    test('watchdog ends a dead link without qrt', () {
      final Link l = up(1);
      l.st[1].deaf = true;
      final int t0 = l.now;
      l.runUntil(60.0, (l) => sess(l, 0).state == FmState.listen);
      final double dt = (l.now - t0) / second;
      expect(dt > 10.0 && dt < 30.0, isTrue, reason: '$dt');
      expect(l.st[0].host.contains(hostTimedOut), isTrue, reason: l.tail(20));
      expect(l.st[0].sent.isNotEmpty && l.st[0].sent.last.startsWith('c3'), isFalse);
    });

    test('b2f FQ ends the session', () {
      final Link l = b2f(4, <String>['FF\r', 'FQ\r']);
      expect(disconnected(l), isTrue, reason: l.log.join('\n'));
      expect(String.fromCharCodes(l.st[1].rx()), 'FF\rFQ\r');
      final List<String> s0 = l.st[0].sent;
      expect(s0.sublist(s0.length - 2), <String>['c3l1', 'c3l1'], reason: '$s0');
    });

    test('golden transcript', () {
      FmConfig with_(FmBandwidth bw, String call, bool registered, Compression compression, bool chat) {
        final FmConfig c = FmConfig(bw, call);
        c.host.registered = registered;
        c.host.compression = compression;
        c.host.chat = chat;
        return c;
      }

      const FmBandwidth n = FmBandwidth.narrow;
      final List<(String, Link)> cases = <(String, Link)>[];
      void add(String name, Link l) => cases.add((name, l));
      for (final FmBandwidth bw in FmBandwidth.values) {
        for (final bool reg in <bool>[false, true]) {
          final Link l = scripted(with_(bw, 'N0CALL', reg, Compression.off, false), cfg(bw, 'N1CALL', false), clean, 1,
              simPayload(8000, 1), simPayload(2000, 2), null);
          add('clean ${fmBwDebug(bw)} registered $reg', l);
        }
      }
      for (final Compression comp in <Compression>[Compression.text, Compression.files]) {
        add('clean ${compDebug(comp)}',
            scripted(with_(n, 'N0CALL', true, comp, false), cfg(n, 'N1CALL', false), clean, 2, text(8000, 1), text(1500, 2), null));
      }
      add(
          'clean chat',
          scripted(with_(n, 'N0CALL', true, Compression.text, true), with_(n, 'N1CALL', false, Compression.off, true), clean, 3,
              text(1500, 3), text(400, 4), null));
      const List<int> sizes = <int>[5000, 89, 335, 1, 0, 2873, 1336];
      for (int seed = 1; seed <= 8; seed++) {
        final FmBandwidth bw = seed % 2 == 0 ? FmBandwidth.wide : FmBandwidth.narrow;
        final int sa = sizes[seed % 7];
        final Uint8List a = simPayload(sa < 1 ? 1 : sa, seed), b = simPayload(sizes[seed * 3 % 7], seed + 1);
        final FmConfig c = with_(bw, 'N0CALL', seed % 4 < 2, Compression.off, false);
        add('lossy off $seed', scripted(c, cfg(bw, 'N1CALL', false), lossy(seed), seed, a, b, null));
      }
      for (int seed = 13; seed <= 20; seed++) {
        final Compression comp = seed < 17 ? Compression.text : Compression.files;
        final int sa = sizes[seed % 7];
        Uint8List a = text(sa < 1 ? 1 : sa, seed);
        if (seed % 4 == 0) a = Uint8List.fromList(<int>[...a, ...simPayload(300, seed)]);
        final Uint8List b = text(sizes[seed * 3 % 7], seed + 1);
        final FmConfig c = with_(n, 'N0CALL', true, comp, false);
        add('lossy ${compDebug(comp)} $seed', scripted(c, cfg(n, 'N1CALL', false), lossy(seed), seed, a, b, null));
      }
      for (int who = 0; who < 2; who++) {
        for (final int k in <int>[1, 2, 4, 7]) {
          final FmConfig c = with_(n, 'N0CALL', true, Compression.off, false);
          final Link l = scripted(c, cfg(n, 'N1CALL', false), clean, 7, simPayload(4000, 6), simPayload(1500, 7), (who, k));
          add('clean abort by $who after $k frames', l);
        }
      }
      for (int seed = 30; seed <= 37; seed++) {
        final (int, int) abort = (seed % 2, 1 + seed % 7);
        final Compression comp = <Compression>[Compression.off, Compression.text, Compression.files][seed % 3];
        final FmConfig c = with_(n, 'N0CALL', true, comp, false);
        final Link l = scripted(c, cfg(n, 'N1CALL', false), lossy(seed), seed, text(5000, seed), text(1500, seed + 1), abort);
        add('lossy ${compDebug(comp)} abort Some((${abort.$1}, ${abort.$2})) $seed', l);
      }
      final Link idle = newLink(cfg(n, 'N0CALL', false), cfg(n, 'N1CALL', false), clean, 1);
      sess(idle, 0).connect(0, null, 'N1CALL', const <String>[]);
      idle.flush();
      idle.runUntil(200.0, disconnected);
      add('idle polls to qrt', idle);
      add('b2f fq', b2f(4, <String>['FF\r', 'FQ\r']));
      add('b2f fq alone', b2f(5, <String>['FQ\r']));
      final Link wd = up(1);
      wd.st[1].deaf = true;
      wd.runUntil(60.0, (l) => sess(l, 0).state == FmState.listen);
      add('watchdog', wd);

      final String got = transcript(cases);
      File('${Directory.systemTemp.path}/fm_link.txt.new').writeAsStringSync(got);
      final String want = File('test/xara/vectors/golden/fm_link.txt').readAsStringSync().replaceAll('\r', '');
      final List<(String, List<String>)> g = sections(got), w = sections(want);
      expect(g.map((s) => s.$1).toList(), w.map((s) => s.$1).toList());
      int exact = 0;
      for (int k = 0; k < g.length; k++) {
        // Files compression uses miniz_oxide's Deflate upstream; any valid
        // Deflate stream interoperates, but the bytes (and thus the run)
        // differ, so those sections cannot be compared line for line.
        if (g[k].$1.contains('Files')) continue;
        final List<String> a = g[k].$2, b = w[k].$2;
        int i = 0;
        while (i < a.length && i < b.length && a[i] == b[i]) {
          i++;
        }
        if (i < a.length || i < b.length) {
          fail('fm_link.txt differs in "${g[k].$1}" at line ${i + 1}\n got: ${i < a.length ? a[i] : '<end>'}\n'
              'want: ${i < b.length ? b[i] : '<end>'}');
        }
        exact++;
      }
      expect(exact, 36);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

List<(String, List<String>)> sections(String t) {
  final List<(String, List<String>)> out = <(String, List<String>)>[];
  for (final String line in t.split('\n')) {
    if (line.startsWith('## ')) {
      out.add((line, <String>[]));
    } else if (line.isNotEmpty) {
      out.last.$2.add(line);
    }
  }
  return out;
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int roundTiesEvenInt(double x) {
  final double f = x.floorToDouble();
  final double d = x - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}
