/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Receiver plumbing shared by the HF and FM receivers: events, transmission
assembly (single/double frames, lost frame 1) and mute/noise tracking.
*/

import 'dsp.dart';

class DecodeStats {
  int decodes = 0;
  int crcOk = 0;

  void count(bool ok) {
    decodes++;
    if (ok) crcOk++;
  }
}

bool continuesAfter(SampleTrack buf, (int, int) after, (int, int) frame, double noise) {
  final double a = buf.meanPower(after.$1, after.$2);
  final double f = buf.meanPower(frame.$1, frame.$2);
  final double fn = f - noise;
  return a - noise > 0.3 * (fn > 1e-30 ? fn : 1e-30) && f > 4.0 * noise;
}

class Muted {
  final List<(int, int)> _spans = <(int, int)>[];

  void mute(SampleTrack buf, double fs, int a, int b) {
    final int keep = buf.end - 8 * fs.toInt();
    _spans.removeWhere((s) => !(s.$2 > keep));
    _spans.add((a - 64, b + 64));
  }

  bool _overlaps(int a, int b) => _spans.any((s) => a < s.$2 && b > s.$1);

  List<double>? quietBlocks(SampleTrack buf, double fs, int block) {
    final int from = buf.base > buf.end - 6 * fs.toInt() ? buf.base : buf.end - 6 * fs.toInt();
    final int total = buf.end - from;
    final List<double> p = <double>[];
    for (int i = 0; i + 1 <= total ~/ block; i++) {
      final int a = from + block * i;
      if (_overlaps(a, a + block)) continue;
      p.add(buf.meanPower(a, a + block));
    }
    if (p.length < 4) return null;
    p.sort(totalCmp);
    return p;
  }
}

abstract class RxFrame {
  bool get ok;
  int get t;
  int get tEnd;
}

class Transmission<R, F extends RxFrame> {
  final R record;
  final int expected;
  final bool complete;
  final int tEnd;
  final List<F> frames;

  const Transmission(this.record, this.expected, this.complete, this.tEnd, this.frames);

  List<bool> get oks => frames.map((f) => f.ok).toList();
}

sealed class RxEvent<C, R, F extends RxFrame> {
  const RxEvent();
}

class CtrlEv<C, R, F extends RxFrame> extends RxEvent<C, R, F> {
  final C ctrl;

  const CtrlEv(this.ctrl);
}

class FrameEv<C, R, F extends RxFrame> extends RxEvent<C, R, F> {
  final F frame;

  const FrameEv(this.frame);
}

class TxEv<C, R, F extends RxFrame> extends RxEvent<C, R, F> {
  final Transmission<R, F> tx;

  const TxEv(this.tx);
}

class Pending<R, F extends RxFrame, W> {
  final R record;
  final int t;
  final List<F> frames;
  bool two;
  final W wait;

  Pending(this.record, this.t, this.frames, this.two, this.wait);
}

class Assembly<R, F extends RxFrame, W> {
  int nframes;
  Pending<R, F, W>? cur;
  int doneUntil = -4611686018427387904;
  int? txEnd48;

  Assembly(this.nframes);
}

/// Groups detected frames into single- or double-frame transmissions.
mixin Assemble<C, R, F extends RxFrame, H, W> {
  int get pairTol;
  bool get emitBad;
  bool get closeOnMiss;
  bool get lostNeedsOk;

  Assembly<R, F, W> get asm;
  SampleTrack get track;
  bool has(R record);
  int span(R record);
  F? decode(R record, int t, int index, H hint);
  bool pairs(Pending<R, F, W> cur, R record);
  int frame1End(Pending<R, F, W> cur);
  F? lost(R record, int back, int t, int span);
  W wait(R record, F r, H hint);
  int expectedFrames(Pending<R, F, W> cur);
  void finished(List<F> frames);

  bool holds(Pending<R, F, W> cur, int t) => false;
  bool keep(F r) => true;
  bool settled(F r) => false;

  List<RxEvent<C, R, F>> onDet(R record, int t, H hint) {
    final List<RxEvent<C, R, F>> ev = <RxEvent<C, R, F>>[];
    if (!has(record) || t < asm.doneUntil - 64) return ev;
    final int sp = span(record);
    final Pending<R, F, W>? cur = asm.cur;
    if (cur != null) {
      if (cur.record == record && (t - (cur.t + sp)).abs() <= pairTol && pairs(cur, record)) {
        return frame2(record, t, hint, ev);
      }
      if (t < frame1End(cur) - 64) {
        if (cur.frames[0].ok) return ev;
        final F? r = decode(record, t, 0, hint);
        if (r == null) return ev;
        if (r.ok || emitBad) ev.add(FrameEv<C, R, F>(r));
        if (r.ok) begin(record, r, hint, ev);
        return ev;
      }
      if (holds(cur, t)) return ev;
      ev.addAll(finalize());
    }
    if (asm.nframes == 2) {
      final int back = t - sp;
      if (back - 8 >= track.base && t > asm.doneUntil) {
        final F? rb = decode(record, back, 0, hint);
        if (rb != null && rb.ok) {
          ev.add(FrameEv<C, R, F>(rb));
          start(record, rb, hint);
          return frame2(record, t, hint, ev);
        }
      }
      final F? lostFrame = lost(record, back, t, sp);
      if (lostFrame != null) {
        final F? r = decode(record, t, 1, hint);
        if (r != null && (r.ok || !lostNeedsOk)) {
          start(record, lostFrame, hint);
          return close(r, true, ev);
        }
        if (!lostNeedsOk) return ev;
      }
    }
    final F? r = decode(record, t, 0, hint);
    if (r == null) return ev;
    if (!keep(r)) return ev;
    if (r.ok || emitBad) ev.add(FrameEv<C, R, F>(r));
    begin(record, r, hint, ev);
    return ev;
  }

  void begin(R record, F r, H hint, List<RxEvent<C, R, F>> ev) {
    final bool s = settled(r);
    start(record, r, hint);
    if (s) ev.addAll(finalize());
  }

  void start(R record, F r, H hint) {
    final W w = wait(record, r, hint);
    asm.cur = Pending<R, F, W>(record, r.t, <F>[r], asm.nframes == 2, w);
  }

  List<RxEvent<C, R, F>> frame2(R record, int t, H hint, List<RxEvent<C, R, F>> ev) {
    final F? r = decode(record, t, 1, hint);
    if (r != null) return close(r, true, ev);
    if (closeOnMiss) ev.addAll(finalize());
    return ev;
  }

  List<RxEvent<C, R, F>> close(F r, bool emitBadFrame, List<RxEvent<C, R, F>> ev) {
    final Pending<R, F, W>? cur = asm.cur;
    asm.cur = null;
    if (cur == null) return ev;
    if (r.ok || emitBadFrame) ev.add(FrameEv<C, R, F>(r));
    cur.frames.add(r);
    ev.addAll(finish(cur));
    return ev;
  }

  List<RxEvent<C, R, F>> finalize() {
    final Pending<R, F, W>? cur = asm.cur;
    asm.cur = null;
    return cur == null ? <RxEvent<C, R, F>>[] : finish(cur);
  }

  List<RxEvent<C, R, F>> finish(Pending<R, F, W> cur) {
    final int sp = span(cur.record);
    final F last = cur.frames.last;
    asm.doneUntil = last.t + sp - 32;
    final int expected = expectedFrames(cur);
    final bool complete = cur.frames.every((f) => f.ok) && cur.frames.length >= expected;
    finished(cur.frames);
    return <RxEvent<C, R, F>>[
      TxEv<C, R, F>(Transmission<R, F>(cur.record, expected, complete, last.tEnd, cur.frames)),
    ];
  }
}
