/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 5: ARQ wire codecs. Ports upstream `tests/kiss.rs`,
`tests/fm_broadcast.rs`, `tests/textcomp.rs` and the compression/link unit
tests, plus an independent Python-zlib oracle for the strict inflater.
*/

import 'dart:typed_data';

import 'package:archive/archive.dart' show Deflate;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/arq_util.dart';
import 'package:htcommander/hamlib/xara/ax25.dart' as ax25;
import 'package:htcommander/hamlib/xara/bits.dart';
import 'package:htcommander/hamlib/xara/compression.dart';
import 'package:htcommander/hamlib/xara/cq.dart' as cq;
import 'package:htcommander/hamlib/xara/crc.dart';
import 'package:htcommander/hamlib/xara/fm_broadcast.dart' as bc;
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/hf_code.dart';
import 'package:htcommander/hamlib/xara/hf_frame.dart';
import 'package:htcommander/hamlib/xara/hf_level.dart';
import 'package:htcommander/hamlib/xara/inflate.dart';
import 'package:htcommander/hamlib/xara/kiss.dart' as kiss;
import 'package:htcommander/hamlib/xara/textcomp.dart' as tc;
import 'package:htcommander/hamlib/xara/textcomp_dict.dart';

import 'xara_vectors.dart';

const HfRecord _l4 = HfRecord(4);

Uint8List _hv(Object? v) => hexDecode(v as String);

// --- KISS TCP framing helpers (upstream xara-host/src/kiss.rs) ---

Uint8List _escape(int cmd, List<int> data) {
  final List<int> out = <int>[0xC0, cmd];
  for (final int b in data) {
    if (b == 0xC0) {
      out.addAll(<int>[0xDB, 0xDC]);
    } else if (b == 0xDB) {
      out.addAll(<int>[0xDB, 0xDD]);
    } else {
      out.add(b);
    }
  }
  out.add(0xC0);
  return Uint8List.fromList(out);
}

List<int> _unescape(List<int> body) {
  final List<int> out = <int>[];
  int i = 0;
  while (i < body.length) {
    final int b = body[i];
    final int? n = i + 1 < body.length ? body[i + 1] : null;
    if (b == 0xDB && n == 0xDC) {
      out.add(0xC0);
      i += 2;
    } else if (b == 0xDB && n == 0xDD) {
      out.add(0xDB);
      i += 2;
    } else {
      out.add(b);
      i++;
    }
  }
  return out;
}

class _Deframer {
  final List<int> _acc = <int>[];
  bool _long = false;

  List<(int, List<int>)> feed(List<int> bytes) {
    final List<(int, List<int>)> out = <(int, List<int>)>[];
    for (final int b in bytes) {
      if (b != 0xC0) {
        if (_acc.length < 5000) {
          _acc.add(b);
        } else {
          _long = true;
        }
        continue;
      }
      final List<int> f = List<int>.of(_acc);
      _acc.clear();
      final bool long = _long;
      _long = false;
      if (f.isNotEmpty) {
        final int cmd = f[0];
        if (!long && cmd <= 2 && (cmd == 2 || f.length + 2 >= 19)) out.add((cmd, _unescape(f.sublist(1))));
      }
    }
    return out;
  }
}

(Uint8List, int) _codedHex(HfRecord level, List<int> frame) {
  final Uint8List bits = hfEncode(kiss.kissBw, level, frame);
  return (Bits(bits.map((b) => b == 1).toList()).pack(), bits.length);
}

class _Sent {
  final HfRecord level;
  final kiss.KissBuffer buf;
  final List<Uint8List> frames;

  _Sent(this.level, this.buf, this.frames);
}

_Sent _send(List<int> kissIn) {
  final List<(int, List<int>)> got = _Deframer().feed(kissIn);
  expect(got.length, 1);
  final (int cmd, List<int> data) = got[0];
  final kiss.KissBuffer buf = kiss.encode(kiss.KissCommand.fromByte(cmd)!, data);
  final (HfRecord level, List<Uint8List> fields) = kiss.fragments(buf);
  final HfControl ctrl = HfControl(hint: hfQueueHint(kiss.kissBw, level, 0));
  return _Sent(level, buf, fields.map((f) => kiss.frame(f, level, ctrl, 0)).toList());
}

Uint8List _receive(HfRecord level, List<Uint8List> frames) {
  final kiss.Reassembler r = kiss.Reassembler();
  Uint8List? out;
  for (int k = 0; k < frames.length; k++) {
    expect(crcOk(frames[k]), isTrue);
    final kiss.Push p = r.push(frames[k], level);
    if (p is kiss.PushMore) {
      expect(k + 1 < frames.length, isTrue);
    } else if (p is kiss.PushDone) {
      out = p.data;
    } else {
      fail('fragment $k dropped');
    }
  }
  final (kiss.KissCommand cmd, Uint8List data) = kiss.decode(out!)!;
  return _escape(cmd.byte, data);
}

_Sent _checkCase(Map<String, dynamic> c) {
  final String name = c['name'] as String;
  final _Sent s = _send(_hv(c['kiss_tcp_in_hex']));
  expect(s.buf.bytes, _hv(c['vara_kiss_buffer_hex']), reason: name);
  expect(s.level.value, c['level'], reason: name);
  expect(kiss.codeForLevel(s.level), c['announce_code'], reason: name);
  final List<dynamic> want = c['frames'] as List<dynamic>;
  expect(s.frames.length, want.length, reason: name);
  expect(s.frames.length, c['fragments'], reason: name);
  for (int i = 0; i < want.length; i++) {
    final Uint8List f = s.frames[i];
    final dynamic w = want[i];
    expect(f, _hv(w['frame_hex']), reason: '$name frame ${w['index']}');
    final Uint8List field = _hv(w['field_hex']);
    expect(f.sublist(0, field.length), field, reason: name);
    expect(f[f.length - 3], w['control_byte'], reason: name);
    final (Uint8List bits, int n) = _codedHex(s.level, f);
    expect(n, w['coded_tx_bits'], reason: name);
    expect(bits, _hv(w['coded_tx_bits_hex']), reason: name);
  }
  expect(_receive(s.level, s.frames), _hv(c['receiver_kiss_tcp_out_hex']), reason: name);
  return s;
}

List<Uint8List> _lFrames(HfRecord level, List<int> bytes, int count) {
  final HfControl ctrl = HfControl(hint: hfQueueHint(kiss.kissBw, level, 0));
  return kiss.split(bytes, count, kiss.payloadField(level)).map((f) => kiss.frame(f, level, ctrl, 0)).toList();
}

List<kiss.Push> _reassemble(kiss.Reassembler r, HfRecord level, List<Uint8List> frames) =>
    frames.map((f) => r.push(f, level)).toList();

// --- textcomp helpers ---

Uint8List _pack(List<bool> bits) {
  final List<bool> b = List<bool>.of(bits);
  final bool p = !b.last;
  final int n = 8 - b.length % 8;
  for (int i = 0; i < n; i++) {
    b.add(p);
  }
  return Bits(b).pack();
}

Uint8List _varaExpansion(int state, String w) {
  final List<bool> bits = <bool>[for (int i = 2; i >= 0; i--) ((state - 1) >> i) & 1 == 1];
  bits.addAll(w.codeUnits.map((c) => c == 0x31));
  for (int n = bits.length; n >= 4; n--) {
    final (Uint8List, int)? d = tc.decompress(_pack(bits.sublist(0, n)));
    if (d != null) return d.$1;
  }
  return Uint8List(0);
}

(bool, Uint8List) _stream(Uint8List frame) {
  final int ctrl = frame[frame.length - 3];
  List<int> field = frame.sublist(0, frame.length - ((ctrl & 2) != 0 ? 4 : 3));
  if (ctrl & 1 == 0) field = field.sublist(0, field.lastIndexOf(0x14));
  return ((ctrl & 0x20) != 0, Uint8List.fromList(field));
}

Uint8List _chunk(bool deflated, List<int> body) =>
    Uint8List.fromList(<int>[(deflated ? 1 : 0) << 7 | (body.length >> 8), body.length & 0xFF, ...body]);

void main() {
  group('kiss', () {
    test('generic cases', () {
      final List<dynamic> cases = loadDoc('kiss/generic')['cases'] as List<dynamic>;
      for (final dynamic c in cases) {
        _checkCase(c as Map<String, dynamic>);
        expect(kiss.genericEncode(_hv(c['data_hex'])), _hv(c['vara_kiss_buffer_hex']));
      }
      expect(cases.length, 5);
    });

    test('ax25 cases', () {
      final List<dynamic> cases = loadDoc('kiss/ax25')['cases'] as List<dynamic>;
      for (final dynamic c in cases) {
        final String name = c['name'] as String;
        final _Sent s = _checkCase(c as Map<String, dynamic>);
        final Uint8List frame = _hv(c['ax25_frame_hex']);
        final kiss.KissCommand cmd = kiss.KissCommand.fromByte(c['kiss_command'] as int)!;
        final ax25.Ax25Record rec = ax25.parse(frame, cmd);
        final dynamic r = c['record'];
        expect(rec.dest, r['dest'], reason: name);
        expect(rec.src, r['src'], reason: name);
        expect(rec.digis, (r['digis'] as List).cast<String>(), reason: name);
        expect(rec.aprsType.code, r['aprs_type'], reason: name);
        expect(rec.alias, r['alias_index'], reason: name);
        expect(s.buf.aprsType.code, r['aprs_type'], reason: name);
        final String bits = (c['bit_fields'] as List).map((f) => f['bits'] as String).join();
        final List<int> packed = <int>[
          for (int i = 0; i < bits.length; i += 8) int.parse(bits.substring(i, i + 8), radix: 2),
        ];
        expect(s.buf.bytes.sublist(1), packed, reason: name);
        final (kiss.KissCommand, Uint8List) out = ax25.decode(s.buf.bytes)!;
        expect(out.$2, _hv(c['receiver_ax25_frame_hex']), reason: name);
        expect(hexEncode(out.$2) == hexEncode(frame), c['receiver_equals_input'], reason: name);
      }
      expect(cases.length, 12);
    });

    test('lab kiss frames', () {
      final Map<String, dynamic> lab = loadDoc('kiss/vara_lab');
      final List<dynamic> cases = lab['cases'] as List<dynamic>;
      for (final dynamic c in cases) {
        final String name = c['name'] as String;
        expect(c['ok'], isTrue, reason: name);
        final dynamic o = c['observed'];
        final _Sent s = _send(_hv(c['kiss_tcp_in_hex']));
        expect(kiss.codeForLevel(s.level), o['announce_code'], reason: name);
        final List<Uint8List> want = (o['frames_hex'] as List).map(_hv).toList();
        expect(s.frames, want, reason: name);
        expect(_receive(s.level, want), _hv(o['receiver_kiss_tcp_out_hex']), reason: name);
      }
      expect(cases.length, 17);
      final dynamic z = lab['extra_z_timestamp'];
      final _Sent s = _send(_hv(z['kiss_tcp_in_hex']));
      final List<Uint8List> want = (z['observed']['frames_hex'] as List).map(_hv).toList();
      expect(s.frames, want);
      expect(s.buf.aprsType, ax25.AprsType.text);
      expect(_receive(s.level, want), _hv(z['observed']['receiver_kiss_tcp_out_hex']));
    });

    test('cq cases', () {
      for (final dynamic c in loadDoc('kiss/cqframe')['cases'] as List<dynamic>) {
        final String cmd = c['host_cmd'] as String;
        final List<String> args = cmd.split(' ');
        final Uint8List f = cq.frame(args[1], HfBandwidth.parse(args[2]) ?? HfBandwidth.hz2750)!;
        expect(f.sublist(0, 6), _hv(c['payload_hex']), reason: cmd);
        expect(f, _hv(c['frame_hex']), reason: cmd);
        expect(f.length, kiss.frameLen(cq.cqRecord));
        final (Uint8List bits, int n) = _codedHex(cq.cqRecord, f);
        expect(bits, _hv(c['coded_tx_bits_hex']), reason: cmd);
        expect(n, c['coded_tx_bits'], reason: cmd);
        expect('${cq.parse(f)!.hostLine}\r', c['receiver_host_line'], reason: cmd);
      }
      final List<dynamic> cases = loadDoc('kiss/xara_lab')['cq'] as List<dynamic>;
      for (final dynamic c in cases) {
        final String cmd = c['host_cmd'] as String;
        final List<String> args = cmd.split(' ');
        final Uint8List f = cq.frame(args[1], HfBandwidth.parse(args[2]) ?? HfBandwidth.hz2750)!;
        expect(f, _hv(c['frame_hex']), reason: cmd);
        final List<String> lines = (c['receiver_lines'] as List).cast<String>();
        if (c['receiver_chat'] != false) {
          expect(lines.last, cq.parse(f)!.hostLine, reason: cmd);
          expect(lines.last, cmd, reason: cmd);
        }
      }
      expect(cases.length, 6);
      final Uint8List p = cq.payload('N0CALL', HfBandwidth.hz500)!;
      p[cq.cqPayload - 1] &= ~0x30;
      expect(cq.parse(p)!.hostLine, 'CQFRAME N0CALL ');
      expect(cq.payload('n0call', HfBandwidth.hz500), isNull);
      expect(cq.parse(const <int>[1, 2]), isNull);
    });

    test('deframer rules', () {
      final _Deframer d = _Deframer();
      final List<(int, List<int>)> one = d.feed(<int>[0xC0, 0xC0, 0x02, 0x41, 0xDB, 0xDC, 0xC0]);
      expect(one.length, 1);
      expect(one[0].$1, 2);
      expect(one[0].$2, <int>[0x41, 0xC0]);
      expect(d.feed(<int>[0xC0, 0x01, 0x0A, 0xC0, 0xC0, 0x12, 0x41, 0xC0, 0xC0, 0x06, 0x41, 0xC0]), isEmpty);
      expect(d.feed(<int>[0xC0, 0x00, ...List<int>.filled(15, 0x40), 0xC0]), isEmpty);
      expect(d.feed(<int>[0xC0, 0x00, ...List<int>.filled(16, 0x40), 0xC0]).length, 1);
    });

    test('generic round trips', () {
      for (final List<int> data in <List<int>>[
        'A'.codeUnits,
        'Hello'.codeUnits,
        'CQ CQ DE!'.codeUnits,
        List<int>.filled(30, 0x14),
        List<int>.generate(256, (i) => i),
        List<int>.filled(700, 0x78),
      ]) {
        final kiss.KissBuffer buf = kiss.KissBuffer(kiss.genericEncode(data), ax25.AprsType.text);
        final (HfRecord level, List<Uint8List> fields) = kiss.fragments(buf);
        final HfControl ctrl = HfControl(hint: hfQueueHint(kiss.kissBw, level, 0));
        final List<Uint8List> frames = fields.map((f) => kiss.frame(f, level, ctrl, 0x5A)).toList();
        expect(_receive(level, frames), _escape(2, data));
      }
      for (final List<int> short in <List<int>>[<int>[], <int>[0x21], <int>[0x20]]) {
        expect(kiss.genericDecode(short), isEmpty);
      }
      final kiss.KissBuffer big = kiss.KissBuffer(kiss.genericEncode(List<int>.filled(800, 0x80)), ax25.AprsType.text);
      expect(() => kiss.fragments(big), throwsA(const kiss.KissTooLong()));
    });

    test('split is total', () {
      expect(kiss.split(<int>[], 1, 9), isEmpty);
      expect(kiss.split('abc'.codeUnits, 2, 2), isEmpty);
      expect(kiss.split('abc'.codeUnits, 1, 1), isEmpty);
      expect(kiss.split('abc'.codeUnits, 3, 0), isEmpty);
      expect(kiss.split('a'.codeUnits, 2, 1), isEmpty);
      expect(kiss.split('a'.codeUnits, 1, 1), [Uint8List.fromList('a'.codeUnits)]);
      expect(kiss.split('abc'.codeUnits, 1, 2), [
        Uint8List.fromList(<int>[0x61 | 0x80, 0x62]),
        Uint8List.fromList('ac'.codeUnits),
      ]);
    });

    test('call tokens', () {
      for (final String call in const [
        'WIDE1-1', 'WIDE2', 'PNW2-1', 'MW1', 'OR2-1', 'WA1-1', 'ALL', 'CQ', 'APIN21', 'APWW15', 'APDR47', 'APBPQ1',
        'APJYC1', 'APOPYT', 'APU25N', 'APVARA', 'APRS', 'APX200', 'N0CALL', 'K1A-15', 'AB1CD-7',
      ]) {
        final Bits b = Bits();
        ax25.tokenEncode(call, 6, b);
        final Reader r = Reader(b.bits);
        expect(ax25.tokenDecode(r, 6), call);
        expect(r.pos, b.length, reason: call);
      }
      final Bits b = Bits();
      ax25.tokenEncode('WIDE2-2', 6, b);
      expect(ax25.tokenDecode(Reader(b.bits), 6), 'WIDE2-10');
      expect(() => ax25.tokenEncode('N0C@LL', 6, b), throwsA(isA<ax25.Ax25BadCall>()));
    });

    test('call parse', () {
      expect(ax25.Call.parse('N0CALL-15'), const ax25.Call('N0CALL', 15));
      expect(ax25.Call.parse('N0CALL'), const ax25.Call('N0CALL', 0));
      for (final String bad in ['N0CALL-16', 'N0CALL-', 'n0call', 'TOOLONG1', '', '-1', 'N0C@LL']) {
        expect(ax25.Call.parse(bad), isNull, reason: bad);
      }
    });

    test('eighteen fragments wrap the count nibble', () {
      List<int>? data;
      for (int b = 0x80; b <= 0xFF; b++) {
        final List<int> d = List<int>.filled(740, b);
        if (kiss.crcNibble(kiss.genericEncode(d)) & 0x10 != 0) {
          data = d;
          break;
        }
      }
      final kiss.KissBuffer buf = kiss.KissBuffer(kiss.genericEncode(data!), ax25.AprsType.text);
      final (HfRecord level, List<Uint8List> fields) = kiss.fragments(buf);
      expect([level.value, fields.length], [4, kiss.maxFragments]);
      expect(fields[0][1] & 0x0F, 0);
      expect(_receive(_l4, _lFrames(_l4, buf.bytes, kiss.maxFragments)), _escape(2, data));
    });

    test('reassembly has no eighteen fragment cap', () {
      final List<int> data = List<int>.filled(900, 0x80);
      final List<Uint8List> frames = _lFrames(_l4, kiss.genericEncode(data), 2);
      expect(frames.length, 22);
      expect(_receive(_l4, frames), _escape(2, data));
    });

    test('reassembly holds at most 5000 bytes', () {
      final Uint8List fits = kiss.genericEncode(List<int>.filled(kiss.rxBuffer - 1, 0x80));
      expect(fits.length, kiss.rxBuffer);
      final kiss.Reassembler r = kiss.Reassembler();
      expect(_reassemble(r, _l4, _lFrames(_l4, fits, 2)).last, kiss.PushDone(fits));
      List<Uint8List> frames = _lFrames(_l4, kiss.genericEncode(List<int>.filled(kiss.rxBuffer, 0x80)), 2);
      List<kiss.Push> got = _reassemble(r, _l4, frames);
      int cut = got.indexOf(const kiss.PushDropped());
      expect(cut, frames.length - 1);
      expect(got.sublist(0, cut).every((p) => p == const kiss.PushMore()), isTrue);
      frames = _lFrames(_l4, kiss.genericEncode(List<int>.filled(kiss.rxBuffer + 200, 0x80)), 2);
      got = _reassemble(r, _l4, frames);
      cut = got.indexOf(const kiss.PushDropped());
      expect(cut < frames.length - 1, isTrue);
      expect(got.sublist(0, cut).every((p) => p == const kiss.PushMore()), isTrue);
      expect(got.sublist(cut).every((p) => p == const kiss.PushDropped()), isTrue);
      final Uint8List ok = kiss.genericEncode('after the flood'.codeUnits);
      expect(_reassemble(r, _l4, _lFrames(_l4, ok, 1)).last, kiss.PushDone(ok));
    });

    test('reassembly holds at most 255 fragments', () {
      final int field = kiss.payloadField(HfRecord.one);
      int len(int n) => 1 + (field - 2) + (n - 1) * (field - 1);
      final Uint8List fits = kiss.genericEncode(List<int>.filled(len(kiss.rxMaxFragments) - 1, 0x80));
      List<Uint8List> frames = _lFrames(HfRecord.one, fits, 2);
      expect(frames.length, kiss.rxMaxFragments);
      expect(fits.length < kiss.rxBuffer, isTrue);
      final kiss.Reassembler r = kiss.Reassembler();
      expect(_reassemble(r, HfRecord.one, frames).last, kiss.PushDone(fits));
      frames = _lFrames(HfRecord.one, kiss.genericEncode(List<int>.filled(len(kiss.rxMaxFragments + 1) - 1, 0x80)), 2);
      expect(frames.length, kiss.rxMaxFragments + 1);
      final List<kiss.Push> got = _reassemble(r, HfRecord.one, frames);
      expect(got.sublist(0, kiss.rxMaxFragments).every((p) => p == const kiss.PushMore()), isTrue);
      expect(got.last, const kiss.PushDropped());
    });

    test('reassembly ignores the announced count', () {
      final Uint8List data = kiss.genericEncode(List<int>.filled(150, 0x71));
      final List<Uint8List> frames = _lFrames(_l4, data, 4);
      expect(frames.length, 4);
      kiss.Reassembler r = kiss.Reassembler();
      expect(r.push(frames[0], _l4), const kiss.PushMore());
      expect(r.push(frames[1], _l4), const kiss.PushMore());
      expect(r.push(frames[3], _l4), const kiss.PushDropped());
      r = kiss.Reassembler();
      expect(_lFrames(_l4, data, 5).map((f) => r.push(f, _l4)).toList().last, kiss.PushDone(data));
      r = kiss.Reassembler();
      expect(frames.map((f) => r.push(f, _l4)).toList().last, kiss.PushDone(data));
    });

    test('announce codes and levels', () {
      expect(kiss.levelForCode(kiss.kissL1), HfRecord.one);
      expect(kiss.levelForCode(kiss.kissL4), _l4);
      expect(kiss.levelForCode(1), isNull);
      expect(kiss.codeForLevel(const HfRecord(3)), kiss.kissL4);
    });
  });

  group('fm broadcast', () {
    List<dynamic> cases() => loadDoc('fm/rec16_lab')['cases'] as List<dynamic>;

    test('record 16 frames match VARA FM', () {
      final List<dynamic> c = cases();
      Uint8List want(int i) => _hv(c[i]['frame_hex']);
      final Uint8List k = kiss.encode(kiss.KissCommand.generic, 'Hello'.codeUnits).bytes;
      expect(bc.frame(FmBandwidth.narrow, k), want(0));
      expect(bc.frame(FmBandwidth.narrow, bc.cqBuffer('N0CALL', null)!), want(1));
      expect(bc.frame(FmBandwidth.narrow, bc.cqBuffer('N0CALL-5', 'NARROW')!), want(2));
      expect(bc.receive(want(0)), bc.ReceivedKiss(kiss.KissCommand.generic, Uint8List.fromList('Hello'.codeUnits)));
      expect(bc.receive(want(1)), const bc.ReceivedCq(cq.Cq('N0CALL')));
      expect(bc.receive(want(2)), const bc.ReceivedCq(cq.Cq('N0CALL-5')));
      final Uint8List bad = want(1)..[3] ^= 1;
      expect(bc.receive(bad), isNull);
    });

    test('record 16 room', () {
      expect(bc.room(FmBandwidth.narrow), 106);
      expect(bc.frame(FmBandwidth.narrow, List<int>.filled(107, 0x21)), isNull);
      expect(bc.cqBuffer('TOOLONG1', null), isNull);
      expect(bc.cqBuffer('N0CALL', 'bad word'), isNull);
    });

    test('record 16 fragments match VARA FM', () {
      final dynamic v = cases()[3];
      final Uint8List data = _hv(v['kiss_data_hex']);
      final List<Uint8List> want = (v['frames_hex'] as List).map(_hv).toList();
      final Uint8List buf = kiss.encode(kiss.KissCommand.generic, data).bytes;
      expect(bc.frames(FmBandwidth.narrow, buf), want);
      bc.BroadcastReassembler r = bc.BroadcastReassembler();
      expect(r.push(want[0]), isNull);
      expect(r.push(want[1]), isNull);
      expect(r.push(want[2]), bc.ReceivedKiss(kiss.KissCommand.generic, data));
      r = bc.BroadcastReassembler();
      expect(r.push(want[0]), isNull);
      expect(r.push(want[2]), isNull);
      expect(r.push(want[0]), isNull);
      expect(r.push(want[1]), isNull);
      expect(r.push(want[2]), bc.ReceivedKiss(kiss.KissCommand.generic, data));
    });

    List<Uint8List> r16(FmBandwidth bw, List<int> buf) =>
        kiss.splitMasked(buf, 2, bc.room(bw), kiss.fmCrcMask).map((f) => bc.frame(bw, f)!).toList();

    test('record 16 reassembly is bounded by 5000 bytes', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final bc.BroadcastReassembler r = bc.BroadcastReassembler();
      Uint8List data = Uint8List.fromList(List<int>.filled(2500, 0x80));
      List<Uint8List> frames = r16(bw, kiss.encode(kiss.KissCommand.generic, data).bytes);
      expect(frames.length > kiss.maxFragments + 1, isTrue);
      expect(frames.map(r.push).toList().last, bc.ReceivedKiss(kiss.KissCommand.generic, data));
      data = Uint8List.fromList(List<int>.filled(kiss.rxBuffer - 1, 0x80));
      expect(r16(bw, kiss.encode(kiss.KissCommand.generic, data).bytes).map(r.push).toList().last,
          bc.ReceivedKiss(kiss.KissCommand.generic, data));
      final Uint8List over = kiss.encode(kiss.KissCommand.generic, List<int>.filled(kiss.rxBuffer + 300, 0x80)).bytes;
      expect(r16(bw, over).every((f) => r.push(f) == null), isTrue);
      data = Uint8List.fromList(List<int>.filled(300, 0x80));
      frames = bc.frames(bw, kiss.encode(kiss.KissCommand.generic, data).bytes)!;
      expect(frames.map(r.push).toList().last, bc.ReceivedKiss(kiss.KissCommand.generic, data));
    });

    test('record 16 sends at most ten fragments', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final int max = 1 + (bc.room(bw) - 2) + (kiss.fmMaxFragments - 1) * (bc.room(bw) - 1);
      Uint8List buf(int n) => kiss.encode(kiss.KissCommand.generic, List<int>.filled(n - 1, 0x80)).bytes;
      expect(bc.frames(bw, buf(max))!.length, kiss.fmMaxFragments);
      expect(bc.frames(bw, buf(max + 1)), isNull);
    });

    test('record 16 fragments carry a five bit crc', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      Uint8List? data;
      for (int b = 0; b <= 255; b++) {
        final Uint8List d = Uint8List.fromList(List<int>.filled(300, b));
        if (kiss.crcBits(kiss.encode(kiss.KissCommand.generic, d).bytes, kiss.fmCrcMask) & 0x08 != 0) {
          data = d;
          break;
        }
      }
      final Uint8List buf = kiss.encode(kiss.KissCommand.generic, data!).bytes;
      final List<Uint8List> frames = bc.frames(bw, buf)!;
      bc.BroadcastReassembler r = bc.BroadcastReassembler();
      expect(frames.map(r.push).toList().last, bc.ReceivedKiss(kiss.KissCommand.generic, data));
      final List<Uint8List> nibble =
          kiss.split(buf, frames.length, bc.room(bw)).map((f) => bc.frame(bw, f)!).toList();
      r = bc.BroadcastReassembler();
      expect(nibble.every((f) => r.push(f) == null), isTrue);
    });

    test('record 16 counts above nine spill into the crc bits', () {
      const FmBandwidth bw = FmBandwidth.narrow;
      final List<bool> seen = <bool>[false, false];
      for (int b = 0x80; b <= 0xFF; b++) {
        final Uint8List buf = kiss.encode(kiss.KissCommand.generic, List<int>.filled(1000, b)).bytes;
        final List<Uint8List> frames = bc.frames(bw, buf)!;
        expect(frames.length, kiss.fmMaxFragments);
        final int spill = ((frames.length - 2) & 0xFF) & ~kiss.crcBits(buf, kiss.fmCrcMask) & kiss.fmCrcMask;
        final bc.BroadcastReassembler r = bc.BroadcastReassembler();
        final bc.Received? got = frames.map(r.push).toList().last;
        expect(got != null, spill == 0);
        seen[spill == 0 ? 1 : 0] = true;
      }
      expect(seen, [true, true]);
    });
  });

  group('textcomp', () {
    test('dictionary is a verbatim copy of upstream', () {
      // SHA-256 of the file as stored in git (LF line endings).
      expect(sha256Hex(textcompDict.codeUnits),
          'b5e9b7cf32598b7aecf91871c6514a696ba433aef82e0b9054a50bd2ff690495');
    });

    test('decodes like VARA', () {
      final Map<String, dynamic> v = loadDoc('textcomp_blackbox');
      final List<String> fps = (v['fingerprints'] as List).cast<String>();
      int n = 0;
      for (final dynamic p in v['decode'] as List<dynamic>) {
        final String w = '${p['u']}${fps[p['f'] as int]}';
        expect(_varaExpansion(p['s'] as int, w), _hv(p['out']), reason: '$p');
        n++;
      }
      for (final dynamic p in v['check'] as List<dynamic>) {
        expect(_varaExpansion(p['s'] as int, p['w'] as String), _hv(p['out']), reason: '$p');
        n++;
      }
      expect(n >= 1300, isTrue, reason: '$n');
    });

    test('encodes like VARA', () {
      int n = 0;
      for (final dynamic e in loadDoc('textcomp_blackbox')['encode'] as List<dynamic>) {
        final Uint8List text = _hv(e['text']);
        int pos = 0;
        for (final dynamic f in e['frames'] as List<dynamic>) {
          final (bool comp, Uint8List data) = _stream(_hv(f));
          if (!comp) {
            expect(text.sublist(pos, pos + data.length), data);
            pos += data.length;
            continue;
          }
          final int start = (data[0] >> 5) + 1;
          final int end = text.length < pos + 3 * 89 + 39 ? text.length : pos + 3 * 89 + 39;
          final tc.Encoded c = tc.compress(text.sublist(pos, end), 89, start);
          expect(c.bytes, data, reason: 'text at $pos');
          expect(tc.decompress(c.bytes)!.$1, text.sublist(pos, pos + c.consumed));
          pos += c.consumed;
          n++;
        }
        expect(pos, text.length);
      }
      expect(n >= 55, isTrue, reason: '$n');
    });

    test('round trip', () {
      for (final dynamic e in loadDoc('textcomp_blackbox')['encode'] as List<dynamic>) {
        final Uint8List text = _hv(e['text']);
        for (int start = 1; start <= 8; start++) {
          for (final int cap in const [8, 20, 47, 88, 89, 400]) {
            final tc.Encoded c = tc.compress(text, cap, start);
            expect(c.bytes.length <= cap, isTrue, reason: 'cap $cap');
            expect(tc.decompress(c.bytes)!.$1, text.sublist(0, c.consumed), reason: 'start $start cap $cap');
          }
        }
      }
    });

    test('decodes VARA on-air frames', () {
      int n = 0;
      for (final dynamic f in loadDoc('textcomp_frames')['onair'] as List<dynamic>) {
        if (f['b5'] != 1) continue;
        expect(tc.decompress(_hv(f['data_hex']))!.$1, _hv(f['text_hex']), reason: '${f['run']} t=${f['t']}');
        n++;
      }
      expect(n, 15);
    });

    test('helpers and malformed input', () {
      expect(tc.decompress(const <int>[]), isNull);
      expect(tc.decompress(const <int>[0xFF]), isNull);
      expect(tc.inputWindow(89), 3 * 89 + 39);
      final List<int> text = 'Hello Hello Hello from the Internet Hello again '.codeUnits;
      expect(tc.fitsFrames(text, 1, 100, 99, tc.startState), isTrue);
      final tc.Encoded ff = tc.fillFrame(text, 10, tc.startState);
      expect(ff.bytes.length <= 10, isTrue);
      expect(tc.decompress(ff.bytes)!.$1, text.sublist(0, ff.consumed));
      expect(tc.compress(text, 89, 99).bytes, tc.compress(text, 89, tc.startState).bytes);
    });
  });

  group('compression', () {
    test('files chunks round trip', () {
      final List<int> text = List<int>.generate(44 * 40, (i) => 'the quick brown fox jumps over the lazy dog '.codeUnitAt(i % 44));
      final FilesReader r = FilesReader();
      expect(r.push(filesChunk(text)), [Uint8List.fromList(text)]);
      expect(r.push(filesChunk('xy'.codeUnits)), [Uint8List.fromList('xy'.codeUnits)]);
      final Uint8List c = filesChunk(text);
      expect(c[0] & 0x80, 0x80);
      final Uint8List raw = filesChunk(List<int>.generate(50, (i) => (i * 97 + 13) & 0xFF));
      expect(raw[0] & 0x80, 0);
    });

    test('bad deflate is dropped', () {
      final FilesReader r = FilesReader();
      final List<int> s = <int>[..._chunk(true, List<int>.filled(20, 0xFF)), ..._chunk(false, 'next'.codeUnits)];
      expect(r.push(s), [Uint8List.fromList('next'.codeUnits)]);
    });

    test('inflate is capped', () {
      final Uint8List fits = Deflate(List<int>.filled(maxInflated, 0)).getBytes();
      final Uint8List bomb = Deflate(List<int>.filled(maxInflated + 1, 0)).getBytes();
      final FilesReader r = FilesReader();
      expect(r.push(_chunk(true, fits)), [Uint8List(maxInflated)]);
      expect(r.push(_chunk(true, bomb)), isEmpty);
      expect(r.push(_chunk(false, 'ok'.codeUnits)), [Uint8List.fromList('ok'.codeUnits)]);
    });

    test('partial chunks wait for the rest', () {
      final FilesReader r = FilesReader();
      final Uint8List c = filesChunk(List<int>.filled(1000, 0x41));
      expect(r.push(c.sublist(0, 1)), isEmpty);
      expect(r.push(c.sublist(1, 5)), isEmpty);
      expect(r.push(c.sublist(5)), [Uint8List.fromList(List<int>.filled(1000, 0x41))]);
    });

    test('stager flushes 32500-byte chunks and on demand', () {
      final FilesStager s = FilesStager();
      final List<int> out = <int>[];
      s.push(100, List<int>.filled(70000, 0x41), out);
      expect(s.length, 70000 - 2 * filesChunkLen);
      expect(s.deadline, 100 + filesPause);
      expect(s.due(100 + filesPause - 1), isFalse);
      expect(s.due(100 + filesPause), isTrue);
      s.flush(out);
      expect(s.isEmpty, isTrue);
      expect(s.deadline, isNull);
      final List<Uint8List> blocks = FilesReader().push(out);
      expect(blocks.map((b) => b.length).toList(), [filesChunkLen, filesChunkLen, 70000 - 2 * filesChunkLen]);
      final List<int> q = List<int>.filled(70000, 0x42, growable: true);
      chunkQueue(q);
      expect(FilesReader().push(q).map((b) => b.length).toList(), [filesChunkLen, filesChunkLen, 5000]);
      expect(Compression.fromBits(2), Compression.files);
      expect(Compression.fromBits(3), Compression.off);
      expect(Compression.text.bits, 1);
    });

    test('strict inflate matches Python zlib', () {
      final Map<String, dynamic> v = loadDoc('inflate_python');
      final List<dynamic> cases = v['cases'] as List<dynamic>;
      expect(cases.length, 49);
      for (final dynamic c in cases) {
        final int len = c['len'] as int;
        final Uint8List? out = inflateRaw(_hv(c['deflate_hex']), maxInflated);
        if (len > maxInflated) {
          expect(out, isNull, reason: '${c['name']} exceeds cap');
          expect(inflateRaw(_hv(c['deflate_hex']), len)!.length, len, reason: c['name'] as String);
        } else {
          expect(out, isNotNull, reason: c['name'] as String);
          expect(out!.length, len, reason: c['name'] as String);
          expect(sha256Hex(out), c['sha256'], reason: c['name'] as String);
        }
      }
      (v['bad'] as Map<String, dynamic>).forEach((name, hex) {
        expect(inflateRaw(_hv(hex), maxInflated), isNull, reason: name);
      });
      expect(inflateRaw(_hv(v['good_copy']['deflate_hex']), 10), Uint8List.fromList('AAAA'.codeUnits));
      expect(inflateRaw(_hv(v['good_copy']['deflate_hex']), 3), isNull);
    });

    test('archive deflate output inflates with the strict decoder', () {
      for (final int n in const [0, 1, 100, 5000, 32500]) {
        final List<int> d = List<int>.generate(n, (i) => (i * i + 7 * i) & 0xFF);
        expect(inflateRaw(Deflate(d).getBytes(), 50000), Uint8List.fromList(d));
      }
    });
  });

  group('link helpers', () {
    test('b2f snoop', () {
      final B2fSnoop s = B2fSnoop();
      s.observe('FS YY\r'.codeUnits);
      expect(s.fs, isTrue);
      s.clearFs();
      expect(s.fs, isFalse);
      s.observe('FS \r'.codeUnits);
      expect(s.fs, isFalse);
      expect(s.takeQuit(), isFalse);
      s.observe('FQ\r'.codeUnits);
      expect(s.takeQuit(), isTrue);
      expect(s.takeQuit(), isFalse);
    });

    test('reorder places data around gaps', () {
      final Reorder r = Reorder();
      expect(r.put('ab'.codeUnits, 0), 'ab'.codeUnits);
      expect(r.put('cd'.codeUnits, 2), isEmpty);
      expect(r.put('xy'.codeUnits, 0), 'xycd'.codeUnits);
      expect(r.put('q'.codeUnits, 1), isEmpty);
      r.clear();
      expect(r.put('z'.codeUnits, 0), 'z'.codeUnits);
    });

    test('queue hints', () {
      expect(queueHintBy(3, 5, [(0, 2, const [(1, 3)]), (0, 1, const [(1, 3)])], 6, (l, k) => l == 2), 0);
      expect(queueHintBy(1, 5, [(0, 2, const [(1, 3)]), (0, 1, const [(1, 3)])], 6, (l, k) => l == 1 && k == 2), 1);
      expect(queueHintBy(1, 5, [(0, 2, const [(1, 3), (2, 4)])], 6, (l, k) => l == 3), 4);
      expect(queueHintBy(1, 5, [(0, 2, const [(1, 3)])], 6, (l, k) => false), 6);
      expect(hfQueueHint(HfBandwidth.hz500, HfRecord.one, 0), 2);
      expect(hfQueueHint(HfBandwidth.hz500, const HfRecord(5), 0), 0);
      expect(hfQueueHintText(HfBandwidth.hz2300, const HfRecord(3), 'hello'.codeUnits, tc.startState), 0);
    });

    test('hf frames and headers', () {
      final Uint8List f = buildFrame(20, 'abc'.codeUnits, const HfControl(reply: 1, hint: 3), null, 0x55);
      expect(f.length, 20);
      expect(crcOk(f), isTrue);
      expect(f.sublist(0, 5), [0x61, 0x62, 0x63, hfTerminator, 0x55]);
      final (HfControl c, bool last, bool full) = HfControl.fromByte(f[17]);
      expect([c.reply, c.hint, last, full], [1, 3, false, false]);
      const HfHeader h = HfHeader(call: 'N0CALL-7', valid: true, registered: true, comp: 2, reply: 1, offer: 9);
      expect(HfHeader.parse(h.toFrame(15, 2, 1)), h);
      expect(HfHeader.parse(const <int>[1, 2, 3]), isNull);
      expect(termMarker('N0CALL'.codeUnits), 0x09);
      expect(payloadCapacity(2, true), 0);
    });
  });
}
