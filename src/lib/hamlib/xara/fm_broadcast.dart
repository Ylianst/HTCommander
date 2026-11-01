/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM unconnected broadcasts (record 16): KISS buffers and CQ announcements.
*/

import 'dart:typed_data';

import 'ax25.dart' as ax25;
import 'cq.dart' as cq;
import 'fm_frame.dart';
import 'fm_level.dart';
import 'kiss.dart' as kiss;

const String cqDest = 'VCHAT';
const int broadcastHint = 1;

List<int>? _address(String call, bool last) {
  final ax25.Call? c = ax25.Call.parse(call);
  if (c == null || c.base.length > 6) return null;
  final List<int> a = List<int>.filled(7, 0x40);
  for (int i = 0; i < c.base.length; i++) {
    a[i] = (c.base.codeUnitAt(i) << 1) & 0xFF;
  }
  a[6] = 0x60 | (c.ssid << 1) | (last ? 1 : 0);
  return a;
}

Uint8List? cqAx25(String call, String? word) {
  final List<int>? d = _address(cqDest, false);
  final List<int>? s = _address(call, word == null);
  if (d == null || s == null) return null;
  final List<int> f = <int>[...d, ...s];
  if (word != null) {
    final List<int>? w = _address(word, true);
    if (w == null) return null;
    f.addAll(w);
  }
  f.addAll(<int>[ax25.uiCtrl, ax25.pidNoL3]);
  return Uint8List.fromList(f);
}

Uint8List? cqBuffer(String call, String? word) {
  final Uint8List? f = cqAx25(call, word);
  if (f == null) return null;
  try {
    return kiss.encode(kiss.KissCommand.ax25, f).bytes;
  } on ax25.Ax25Error {
    return null;
  }
}

int broadcastFrameLen(FmBandwidth bw) => bw.level(FmRecord.broadcast).frameBytes;

int room(FmBandwidth bw) => payloadLen(FmRecord.broadcast, broadcastFrameLen(bw), false)!;

Uint8List? frame(FmBandwidth bw, List<int> field) => field.length <= room(bw)
    ? buildData(FmRecord.broadcast, broadcastFrameLen(bw), field, false, broadcastHint, true, const Trailer())
    : null;

List<Uint8List>? frames(FmBandwidth bw, List<int> buffer) {
  final int count = kiss.countForField(buffer.length, room(bw));
  if (buffer.isEmpty || count > kiss.fmMaxFragments) return null;
  final List<Uint8List> out = <Uint8List>[];
  for (final Uint8List f in kiss.splitMasked(buffer, count, room(bw), kiss.fmCrcMask)) {
    final Uint8List? fr = frame(bw, f);
    if (fr == null) return null;
    out.add(fr);
  }
  return out;
}

sealed class Received {
  const Received();
}

class ReceivedCq extends Received {
  final cq.Cq value;

  const ReceivedCq(this.value);

  @override
  bool operator ==(Object other) => other is ReceivedCq && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Cq(${value.call})';
}

class ReceivedKiss extends Received {
  final kiss.KissCommand cmd;
  final Uint8List data;

  const ReceivedKiss(this.cmd, this.data);

  @override
  bool operator ==(Object other) {
    if (other is! ReceivedKiss || other.cmd != cmd || other.data.length != data.length) return false;
    for (int i = 0; i < data.length; i++) {
      if (other.data[i] != data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(cmd, Object.hashAll(data));

  @override
  String toString() => 'Kiss($cmd, ${data.length})';
}

Received? interpret(List<int> buffer) {
  final (kiss.KissCommand, Uint8List)? d = kiss.decode(buffer);
  if (d == null) return null;
  final (kiss.KissCommand cmd, Uint8List f) = d;
  if (cmd == kiss.KissCommand.ax25) {
    final ax25.Ax25Record r;
    try {
      r = ax25.parse(f, cmd);
    } on ax25.Ax25Error {
      return null;
    }
    if (r.dest == cqDest && r.ctrl == ax25.uiCtrl && r.pid == ax25.pidNoL3) {
      return ReceivedCq(cq.Cq(r.src));
    }
  }
  return ReceivedKiss(cmd, f);
}

Received? receive(List<int> frame) => BroadcastReassembler().push(frame);

class BroadcastReassembler {
  final kiss.Reassembler _r = kiss.Reassembler(crcMask: kiss.fmCrcMask);

  Received? push(List<int> frame) {
    final DataFrame? df = parseData(FmRecord.broadcast, frame, false);
    if (df == null) return null;
    final Uint8List d = df.data;
    final int? first = _r.first;
    if (first != null && d.isNotEmpty && (first ^ d[0]) & 0x7F != 0) _r.reset();
    final kiss.Push p = _r.join(d, d.length);
    return p is kiss.PushDone ? interpret(p.data) : null;
  }

  void reset() => _r.reset();
}
