/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Port of XARA's ARQ link simulator (`crates/xara-arq/tests/sim`): two sans-IO
sessions joined by a discrete-event channel with configurable loss. Traces use
Rust Debug formatting so they can be diffed against upstream golden files.
*/

import 'dart:collection';
import 'dart:typed_data';

import 'package:htcommander/hamlib/xara/arq_host.dart';
import 'package:htcommander/hamlib/xara/arq_time.dart';

class SimRng {
  int _s;

  SimRng(this._s);

  double uniform() {
    _s ^= _s << 13;
    _s ^= _s >>> 7;
    _s ^= _s << 17;
    return (_s >>> 11) / 9007199254740992.0;
  }
}

class Channel {
  final double snr;
  final double frameLoss;
  final double ctrlLoss;
  final double miss;

  const Channel(this.snr, this.frameLoss, this.ctrlLoss, this.miss);
}

const Channel clean = Channel(40.0, 0.0, 0.0, 0.0);

sealed class Payload {
  const Payload();
}

class PayloadCtrl extends Payload {
  final int code;
  final int lead;

  const PayloadCtrl(this.code, this.lead);
}

class PayloadData extends Payload {
  final int level;
  final List<Uint8List?> frames;

  const PayloadData(this.level, this.frames);
}

/// Adapter between a session type and the simulator.
abstract class SimSess<T, L> {
  int get latency;
  Output<T, L>? next();
  String goldenLine(Output<T, L> o);
  int? deadline();
  void tick(int now);
  void txDone(int now);
  String get stateName;
  (int, int) airtime(T tx);
  String what(T tx);
  Payload? air(T tx);
  void arrive(SimLink<T, L> l, int i, int start, int end, Payload p);
}

class Station<T, L> {
  final SimSess<T, L> s;
  L? listen;
  final List<HostEvent> host = <HostEvent>[];
  int got = 0;
  int progress = 0;
  final List<(int, int)> busy = <(int, int)>[];
  final List<String> sent = <String>[];
  bool deaf = false;

  Station(this.s);

  Uint8List rx() => Uint8List.fromList(<int>[
        for (final HostEvent h in host)
          if (h is HostData) ...h.data,
      ]);

  List<int> levels() => <int>[
        for (final String t in sent)
          if (t.startsWith('L')) int.parse(t.substring(1).split('x').first),
      ];

  int get busyUntil => busy.isEmpty ? 0 : busy.last.$2;
}

sealed class _Ev {}

class _TxDone extends _Ev {
  final int i;

  _TxDone(this.i);
}

class _Arrive extends _Ev {
  final int i;
  final int start;
  final int end;
  final Payload p;

  _Arrive(this.i, this.start, this.end, this.p);
}

String digest(List<int> b) {
  int h = 0x811c9dc5;
  for (final int x in b) {
    h = ((h ^ x) * 0x01000193) & 0xFFFFFFFF;
  }
  return '<${b.length} bytes ${h.toRadixString(16).padLeft(8, '0')}>';
}

class SimLink<T, L> {
  final List<Station<T, L>> st;
  int now = 0;
  final SplayTreeMap<(int, int), _Ev> _q =
      SplayTreeMap<(int, int), _Ev>((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  int _seq = 0;
  final Channel ch;
  final SimRng _rng;
  final List<String> log = <String>[];
  final List<String> trace = <String>[];
  bool slow = false;

  SimLink(SimSess<T, L> a, SimSess<T, L> b, this.ch, int seed)
      : st = <Station<T, L>>[Station<T, L>(a), Station<T, L>(b)],
        _rng = SimRng(seed | 1) {
    flush();
  }

  void _push(int t, _Ev e) {
    _seq++;
    _q[(t, _seq)] = e;
  }

  String _secs(int t) => (t / second).toStringAsFixed(2).padLeft(8);

  void flush() {
    for (int i = 0; i < 2; i++) {
      while (true) {
        final Output<T, L>? o = st[i].s.next();
        if (o == null) break;
        trace.add('$now $i ${st[i].s.goldenLine(o)}');
        switch (o) {
          case OutListen<T, L>(:final L listen):
            st[i].listen = listen;
          case OutHost<T, L>(:final HostEvent event):
            if (event is HostData) {
              st[i].got += event.data.length;
              st[i].progress = now;
              log.add('${_secs(now)} $i host data ${event.data.length}');
            } else if (event is! HostSn && event is! HostBuffer && event is! HostRxFrame) {
              log.add('${_secs(now)} $i host ${event.debug}');
            }
            st[i].host.add(event);
          case OutTx<T, L>(:final T tx):
            _transmit(i, tx);
        }
      }
    }
  }

  void _transmit(int i, T tx) {
    final int start = now > st[i].busyUntil ? now : st[i].busyUntil;
    final (int sig, int tail) = st[i].s.airtime(tx);
    final int end = start + sig, done = start + sig + tail;
    st[i].busy.add((start, done));
    _push(done, _TxDone(i));
    final String w = st[i].s.what(tx);
    log.add('${_secs(start)} $i TX $w (${st[i].s.stateName})');
    st[i].sent.add(w);
    final Payload? a = st[i].s.air(tx);
    Payload? p;
    if (a is PayloadCtrl) {
      if (_rng.uniform() >= ch.ctrlLoss) p = a;
    } else if (a is PayloadData) {
      if (_rng.uniform() >= ch.miss) {
        p = PayloadData(a.level, <Uint8List?>[for (final Uint8List? f in a.frames) f != null && _rng.uniform() >= ch.frameLoss ? f : null]);
      }
    }
    if (p is PayloadData && p.frames.any((f) => f == null)) {
      log.add('         $i    ${p.frames.where((f) => f == null).length} frame(s) corrupted');
    } else if (p == null) {
      log.add('         $i    lost on air');
    }
    if (p != null) _push(end + st[i].s.latency, _Arrive(1 - i, start, end, p));
  }

  bool step(int limit) {
    (int, int)? dl;
    for (int i = 0; i < 2; i++) {
      final int? t = st[i].s.deadline();
      if (t != null && (dl == null || t < dl.$1)) dl = (t, i);
    }
    final (int, int)? ev = _q.isEmpty ? null : _q.firstKey();
    if (ev != null && (dl == null || ev.$1 <= dl.$1) && ev.$1 <= limit) {
      final _Ev e = _q.remove(ev)!;
      if (ev.$1 > now) now = ev.$1;
      switch (e) {
        case _TxDone(:final int i):
          st[i].s.txDone(now);
        case _Arrive(:final int i, :final int start, :final int end, :final Payload p):
          if (!st[i].deaf) st[i].s.arrive(this, i, start, end, p);
      }
    } else if (dl != null && dl.$1 <= limit) {
      if (dl.$1 > now) now = dl.$1;
      st[dl.$2].s.tick(now);
    } else {
      return false;
    }
    flush();
    return true;
  }

  void runUntil(double secs, bool Function(SimLink<T, L>) done) {
    final int limit = now + (secs * second).truncate();
    while (!done(this) && step(limit)) {}
  }

  String tail(int n) => log.sublist(log.length > n ? log.length - n : 0).join('\n');
}

Uint8List simPayload(int n, int seed) {
  final SimRng r = SimRng(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => (r.uniform() * 256.0).toInt()));
}

Uint8List simText(List<String> words, int n, int seed) {
  final SimRng r = SimRng(seed);
  final List<int> out = <int>[];
  while (out.length < n) {
    out.addAll(words[(r.uniform() * words.length).toInt()].codeUnits);
    out.add(0x20);
  }
  return Uint8List.fromList(out.sublist(0, n));
}

bool simConnected<T, L>(SimLink<T, L> l) => l.st.every((s) => s.host.any((h) => h is HostConnected));

String transcript<T, L>(List<(String, SimLink<T, L>)> cases) {
  final StringBuffer out = StringBuffer();
  for (final (String name, SimLink<T, L> l) in cases) {
    out.write('## $name\n');
    for (final String t in l.trace) {
      out.write('$t\n');
    }
  }
  return out.toString();
}
