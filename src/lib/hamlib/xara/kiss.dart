/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
VARA unconnected (KISS) buffers: generic text codec, fragmentation into HF
frames and fragment reassembly.
*/

import 'dart:typed_data';

import 'ax25.dart' as ax25;
import 'bits.dart';
import 'crc.dart';
import 'cq.dart' as cq;
import 'hf_frame.dart';
import 'hf_level.dart';
import 'kiss_command.dart';

export 'kiss_command.dart';

const HfBandwidth kissBw = HfBandwidth.hz500;
const int maxFragments = 18;
const int fmMaxFragments = 10;
const int rxBuffer = 5000;
const int rxMaxFragments = 255;
const int maxQueuedBytes = 5000;

/// HF control codes announcing a KISS transmission at levels 1, 2 and 4.
const int kissL1 = 45;
const int kissL2 = 47;
const int kissL4 = 58;
const List<int> kissCodes = <int>[kissL1, kissL2, kissL4];

class KissTooLong implements Exception {
  const KissTooLong();

  @override
  bool operator ==(Object other) => other is KissTooLong;

  @override
  int get hashCode => 0;
}

Uint8List genericEncode(List<int> data) {
  final Bits b = Bits();
  final bool seven = data.every((c) => c <= 0x7F);
  if (seven) {
    b.pushText7(data);
  } else {
    for (final int c in data) {
      b.push(c, 8);
    }
  }
  return Uint8List.fromList(<int>[0x20 | (seven ? 1 : 0), ...b.pack()]);
}

Uint8List genericDecode(List<int> buf) {
  if (buf.isEmpty) return Uint8List(0);
  final List<int> body = buf.sublist(1);
  if (buf[0] & 1 == 0) return Uint8List.fromList(body);
  final List<int>? t = Reader(Bits.unpack(body).bits).text7();
  return Uint8List.fromList(t ?? const <int>[]);
}

class KissBuffer {
  final Uint8List bytes;
  final ax25.AprsType aprsType;

  const KissBuffer(this.bytes, this.aprsType);
}

/// Throws [ax25.Ax25Error] for unencodable AX.25 frames.
KissBuffer encode(KissCommand cmd, List<int> data) {
  switch (cmd) {
    case KissCommand.ax25:
    case KissCommand.ax25Long:
      final (Uint8List bytes, ax25.Ax25Record rec) = ax25.encode(data, cmd);
      return KissBuffer(bytes, rec.aprsType);
    case KissCommand.generic:
      return KissBuffer(genericEncode(data), ax25.AprsType.text);
  }
}

(KissCommand, Uint8List)? decode(List<int> buf) {
  if (buf.isEmpty) return null;
  switch ((buf[0] >> 4) & 3) {
    case 2:
      return (KissCommand.generic, genericDecode(buf));
    case 0:
    case 1:
      return ax25.decode(buf);
  }
  return null;
}

const HfRecord _l2 = HfRecord(2);
const HfRecord _l4 = HfRecord(4);

int codeForLevel(HfRecord level) => switch (level.value) {
      1 => kissL1,
      2 => kissL2,
      _ => kissL4,
    };

HfRecord? levelForCode(int code) => switch (code) {
      kissL1 => HfRecord.one,
      kissL2 => _l2,
      kissL4 => _l4,
      _ => null,
    };

int payloadField(HfRecord level) => level == cq.cqRecord ? cq.cqPayload : kissBw.level(level).payload;

int frameLen(HfRecord level) => kissBw.level(level).frameBytes;

int _fragsNeeded(int total, int field) {
  final int over = total + 1 - field;
  return (over > 0 ? (over + field - 2) ~/ (field - 1) : 0) + 1;
}

HfRecord chooseLevel(int total, ax25.AprsType aprsType) {
  final int limit = aprsType.hasPosition ? 3 : 2;
  for (final HfRecord l in const <HfRecord>[HfRecord.one, _l2]) {
    if (_fragsNeeded(total, payloadField(l)) <= limit) return l;
  }
  return _l4;
}

int fragmentCount(int total, HfRecord level) => countForField(total, payloadField(level));

int countForField(int total, int field) => total <= field ? 1 : _fragsNeeded(total, field);

const int hfCrcMask = 0xF0;
const int fmCrcMask = 0xF8;

int crcNibble(List<int> buf) => crcBits(buf, hfCrcMask);

int crcBits(List<int> buf, int mask) => (crc16Genibus(buf) >> 8) & mask;

/// Splits [buf] into fragment fields. Throws [KissTooLong].
(HfRecord, List<Uint8List>) fragments(KissBuffer buf) {
  final Uint8List b = buf.bytes;
  final HfRecord level = chooseLevel(b.length, buf.aprsType);
  final int count = fragmentCount(b.length, level);
  if (count > maxFragments) throw const KissTooLong();
  return (level, split(b, count, payloadField(level)));
}

List<Uint8List> split(List<int> b, int count, int field) => splitMasked(b, count, field, hfCrcMask);

List<Uint8List> splitMasked(List<int> b, int count, int field, int crcMask) {
  if (b.isEmpty) return <Uint8List>[];
  final int hdr = b[0];
  int rest = 1;
  final List<Uint8List> out = <Uint8List>[];
  while (out.isEmpty || rest < b.length) {
    final List<int> f = <int>[hdr | 0x80];
    if (out.isEmpty && count > 1) f.add(((count - 2) & 0xFF) | crcBits(b, crcMask));
    final int room = field - f.length;
    if (room < 0 || (room == 0 && rest < b.length)) return <Uint8List>[];
    final int n = b.length - rest < room ? b.length - rest : room;
    f.addAll(b.sublist(rest, rest + n));
    rest += n;
    if (rest >= b.length) f[0] &= 0x7F;
    out.add(Uint8List.fromList(f));
  }
  return out;
}

Uint8List frame(List<int> field, HfRecord level, HfControl ctrl, int marker) =>
    buildFrame(frameLen(level), field, ctrl, null, marker);

sealed class Push {
  const Push();
}

class PushDropped extends Push {
  const PushDropped();

  @override
  bool operator ==(Object other) => other is PushDropped;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'Dropped';
}

class PushMore extends Push {
  const PushMore();

  @override
  bool operator ==(Object other) => other is PushMore;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'More';
}

class PushDone extends Push {
  final Uint8List data;

  const PushDone(this.data);

  @override
  bool operator ==(Object other) {
    if (other is! PushDone || other.data.length != data.length) return false;
    for (int i = 0; i < data.length; i++) {
      if (other.data[i] != data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(data);

  @override
  String toString() => 'Done(${data.length})';
}

class Reassembler {
  final List<int> _buf = <int>[];
  int _nfrag = 0;
  int _count = 0;
  final int crcMask;
  bool _overflow = false;

  Reassembler({this.crcMask = hfCrcMask});

  Push push(List<int> f, HfRecord level) {
    final int field = payloadField(level);
    if (f.length != frameLen(level)) return const PushDropped();
    final (HfControl _, bool _, bool full) = HfControl.fromByte(f[f.length - 3]);
    final int n = full ? field : _lastIndex(f, field, hfTerminator);
    return join(f, n);
  }

  static int _lastIndex(List<int> f, int end, int v) {
    for (int i = end - 1; i >= 0; i--) {
      if (f[i] == v) return i;
    }
    return 0;
  }

  Push join(List<int> f, int n) {
    if (n <= 0 || n > f.length) return const PushDropped();
    final List<int> d = f.sublist(0, n);
    final bool more = d[0] & 0x80 != 0;
    if (_overflow) {
      _overflow = more;
      return const PushDropped();
    }
    int start = 1;
    if (_buf.isEmpty) {
      if (more) {
        if (f.length < 2) return const PushDropped();
        start = 2;
        _count = f[1];
      }
      _nfrag = 0;
      _buf.add(d[0]);
    }
    final List<int> tail = d.sublist(start < n ? start : n);
    if (_buf.length + tail.length > rxBuffer || _nfrag >= rxMaxFragments) {
      reset();
      _overflow = more;
      return const PushDropped();
    }
    _buf.addAll(tail);
    _nfrag++;
    if (more) return const PushMore();
    final Uint8List out = Uint8List.fromList(_buf);
    _buf.clear();
    out[0] = d[0];
    if (_nfrag >= 2 && crcBits(out, crcMask) != _count & crcMask) return const PushDropped();
    return PushDone(out);
  }

  int? get first => _buf.isEmpty ? null : _buf[0];

  void reset() {
    _buf.clear();
    _nfrag = 0;
    _overflow = false;
  }
}
