/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 3: FM transmit path. Generated PCM is compared by SHA-256 of
the int16 output against the upstream vectors (bit-exact audio).
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/complex.dart';
import 'package:htcommander/hamlib/xara/crc.dart';
import 'package:htcommander/hamlib/xara/dat.dart';
import 'package:htcommander/hamlib/xara/fm_code.dart';
import 'package:htcommander/hamlib/xara/fm_constellation.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';

import 'xara_vectors.dart';

FmBandwidth _mode(Object? v) => switch (v) {
      'NARROW' => FmBandwidth.narrow,
      'WIDE' => FmBandwidth.wide,
      _ => throw ArgumentError('$v'),
    };

FmRecord _rec(int i) => FmRecord.fromIndex(i)!;

List<Tones> _rows(String s) => s
    .split(RegExp(r'\s+'))
    .where((r) => r.isNotEmpty)
    .map((r) => r.split('+').map(int.parse).toList())
    .toList();

Uint8List _le(Int16List v) => v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes);

void _check(String id, Int16List got, Map<String, dynamic> want, int every) {
  expect(got.length, want['n_samples'], reason: '$id: length');
  final List<int> fp = ints(want['fingerprint']);
  int worst = 0;
  for (int i = 0, j = 0; i < got.length && j < fp.length; i += every, j++) {
    worst = math.max(worst, (got[i] - fp[j]).abs());
  }
  expect(sha256Hex(_le(got)), want['sha256_int16le'], reason: '$id: fingerprint off by $worst LSB');
}

Int16List _dataPcm(Modulator m, Map<String, dynamic> c, double drive) {
  final FmRecord record = _rec((c['record'] as num).toInt());
  final int key = (c['key'] as num).toInt();
  final List<List<int>> frames = (c['frames_hex'] as List).map((h) => hexDecode(h as String)).toList();
  final List<int> draws = c['draws'] == null ? <int>[] : ints(c['draws']);
  final int lead = draws.length ~/ m.bw.level(record).nc;
  int i = 0;
  int rand(int n) {
    final int v = draws[i++];
    expect(v < n, isTrue);
    return v;
  }

  final Int16List pcm =
      toI16(m.transmission(record, key, frames, lead, TxOptions(driveDb: drive), rand));
  expect(i, draws.length, reason: 'all lead draws consumed');
  return pcm;
}

bool _sameRows(List<Tones> a, List<Tones> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (int j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}

void main() {
  group('fft', () {
    test('matches a direct DFT', () {
      final math.Random rng = math.Random(3);
      for (final int n in [1, 2, 8, 64, 1024]) {
        final Float64List re = Float64List.fromList(List<double>.generate(n, (_) => rng.nextDouble() - 0.5));
        final Float64List im = Float64List.fromList(List<double>.generate(n, (_) => rng.nextDouble() - 0.5));
        for (final bool inverse in [false, true]) {
          final Float64List r = Float64List.fromList(re);
          final Float64List q = Float64List.fromList(im);
          Fft.plan(n).transform(r, q, inverse: inverse);
          final double sign = inverse ? 1.0 : -1.0;
          for (final int k in {0, 1 % n, n ~/ 3, n - 1}) {
            double sr = 0, si = 0;
            for (int t = 0; t < n; t++) {
              final double a = sign * 2 * math.pi * k * t / n;
              sr += re[t] * math.cos(a) - im[t] * math.sin(a);
              si += re[t] * math.sin(a) + im[t] * math.cos(a);
            }
            expect(r[k], closeTo(sr, 1e-9), reason: 'n=$n k=$k inv=$inverse');
            expect(q[k], closeTo(si, 1e-9), reason: 'n=$n k=$k inv=$inverse');
          }
        }
      }
      expect(() => Fft(12), throwsArgumentError);
    });

    test('hypot and complex ops', () {
      expect(hypot(3, 4), 5.0);
      expect(hypot(1e200, 1e200), closeTo(math.sqrt2 * 1e200, 1e186));
      expect(hypot(1e-200, 0), 1e-200);
      expect(hypot(double.infinity, double.nan), double.infinity);
      expect(const Cx(1, 2) * const Cx(3, -1), const Cx(5, 5));
      expect(const Cx(1, 2).conj(), const Cx(1, -2));
      expect(Cx.polar(2, math.pi / 2).re, closeTo(0, 1e-15));
    });
  });

  group('fm constellations', () {
    test('match fm_constellations.json', () {
      final Map<String, dynamic> cs = loadDoc('fm_constellations')['constellations'] as Map<String, dynamic>;
      expect(cs.length, 8);
      cs.forEach((name, c) {
        final int bps = (c['bps'] as num).toInt();
        final List<dynamic> pts = c['points'] as List<dynamic>;
        final List<Cx> t = fmConstellation(bps);
        expect(t.length, pts.length, reason: name);
        final double tol = bps <= 2 ? 1e-14 : 0.0;
        for (int v = 0; v < pts.length; v++) {
          final double i = (pts[v][0] as num).toDouble();
          final double q = (pts[v][1] as num).toDouble();
          expect((t[v].re - i).abs() <= tol && (t[v].im - q).abs() <= tol, isTrue,
              reason: '$name v $v: ${t[v]} vs ($i, $q)');
        }
      });
      expect(fmConstellation(9), isEmpty);
    });
  });

  group('fm frames', () {
    test('record 0 spec vector', () {
      final Uint8List f = Record0.connect('N0CALL', 'N1CALL', '', '', false, false).toBytes()!;
      expect(hexEncode(f), '004e3043414c4c2000202020202020200020202020202020004e3143414c4c200000080700f8f3');
      final Record0 r = Record0.connect('N0CALL-7', 'N1CALL-T', 'N9DIG', '', true, true)
          .copyWith(kind: Kind.ping, hop: 1, compression: 1, aes: true, chainSnr: snrByte(12.3));
      expect(Record0.parse(r.toBytes()!), r);
      expect(Record0.connect('N0CALL', 'TOOLONGCALL', '', '', false, false).toBytes(), isNull);
      expect([snrByte(-3.0), snrByte(0.5), snrByte(40.0)], [1, 4, 245]);
      expect(Record0.connect('n0call', 'N1CALL', '', '', false, false).toBytes(), f);
      expect(Record0.connect('N0CALL-Q', 'N1CALL', '', '', false, false).toBytes(), isNull);
      expect(Record0.connect('N\u0131CALL', 'N1CALL', '', '', false, false).toBytes(), isNull);
      expect(Record0.parse(f.sublist(1)), isNull);
      expect(Record0.parse([...f]..[3] ^= 1), isNull);
    });

    test('lab frames', () {
      final Map<String, dynamic> v = loadDoc('fm/lab_frames');
      for (final dynamic c in v['record0'] as List<dynamic>) {
        final Uint8List f = hexDecode(c['frame_hex'][0] as String);
        final Record0 r = Record0.parse(f)!;
        final dynamic p = c['record0'];
        expect(r.source, p['source']);
        expect(r.target, p['target']);
        expect(r.via1, p['via1']);
        expect(r.hop, p['hop']);
        expect(r.wide, p['wide'] == 1);
        expect(r.toBytes(), f);
      }
      int n = 0;
      for (final dynamic c in v['cases'] as List<dynamic>) {
        final FmRecord record = _rec((c['record'] as num).toInt());
        final FmBandwidth bw = c['mode'] == 'WIDE' ? FmBandwidth.wide : FmBandwidth.narrow;
        final List<dynamic> hexes = c['frame_hex'] as List<dynamic>;
        final List<dynamic> fields = c['fields'] as List<dynamic>;
        for (int i = 0; i < hexes.length; i++) {
          final Uint8List f = hexDecode(hexes[i] as String);
          final dynamic fl = fields[i];
          expect(f.length, bw.level(record).frameBytes);
          final DataFrame d = parseData(record, f, false)!;
          expect(d.data.length, fl['data_len']);
          expect(d.control.hint, fl['hint']);
          expect(d.control.last, fl['last'] == 1);
          expect(d.control.full, fl['full'] == 1);
          final int p = payloadLen(record, f.length, false)!;
          expect(hexEncode(f.sublist(p + 1, f.length - 2)), fl['trailer']);
          expect(buildData(record, f.length, d.data, d.control.compressed, d.control.hint, d.control.last, d.trailer), f);
          n++;
        }
      }
      expect(n, 85);
    });

    test('data layouts', () {
      for (final FmRecord record in [1, 2, 14, 15, 16].map(_rec)) {
        final int len = FmBandwidth.narrow.level(record).frameBytes;
        for (final bool vias in [false, true]) {
          if (vias && record == FmRecord.broadcast) continue;
          final Trailer t = Trailer(leadReport: 27, level: 2, chainSnr: vias ? 99 : null);
          for (final int n in [0, 1, 5, 400]) {
            final List<int> data = List<int>.generate(n, (i) => i % 3 == 0 ? 0x14 : i & 0xFF);
            final Uint8List f = buildData(record, len, data, false, 5, true, t);
            expect(f.length, len);
            final DataFrame d = parseData(record, f, vias)!;
            final int room = payloadLen(record, len, vias)!;
            expect(d.data, data.sublist(0, math.min(n, room)));
            expect(d.control.full, n >= room);
            if (record != FmRecord.broadcast) {
              expect(d.trailer, t.copyWith(level: record == FmRecord.start ? 2 : 0));
            }
          }
        }
      }
    });

    test('payload lengths match fm/levels.json', () {
      for (final dynamic r in loadDoc('fm/levels')['records'] as List<dynamic>) {
        final FmBandwidth bw = _mode(r['mode']);
        final FmRecord rec = _rec((r['record'] as num).toInt());
        final int fb = bw.level(rec).frameBytes;
        expect(payloadLen(rec, fb, false), r['payload_direct'], reason: '${bw.name} ${rec.index}');
        if (r['payload_with_vias'] != null) {
          expect(payloadLen(rec, fb, true), r['payload_with_vias'], reason: '${bw.name} ${rec.index}');
        }
      }
      expect(payloadLen(FmRecord.connect, 3, false), isNull);
    });

    test('control byte, trailer restamp and malformed input', () {
      for (int b = 0; b < 64; b++) {
        expect(Control.fromByte(b).byte, b);
      }
      final int len = FmBandwidth.narrow.level(const FmRecord(1)).frameBytes;
      final Uint8List f = buildData(const FmRecord(1), len, [1, 2, 3], true, 3, false, const Trailer(leadReport: 5));
      expect(Trailer.read(const FmRecord(1), f, false), const Trailer(leadReport: 5));
      final Uint8List re = const Trailer(leadReport: 9, chainSnr: 40).restamp(const FmRecord(1), f)!;
      expect(re.length, f.length);
      expect(crcOk(re), isTrue);
      expect(Trailer.read(const FmRecord(1), re, true), const Trailer(leadReport: 9, chainSnr: 40));
      expect(parseData(const FmRecord(1), [...f]..[4] ^= 0xFF, false), isNull);
      expect(parseData(FmRecord.connect, f, false), isNull);
      final Uint8List noTerm = buildData(const FmRecord(1), len, [], false, 0, false, const Trailer());
      final List<int> bad = noTerm.sublist(0, noTerm.length - 2)..[0] = 0;
      final int crc = crc16Genibus(bad);
      expect(parseData(const FmRecord(1), [...bad, crc >> 8, crc & 0xFF], false), isNull);
      expect(() => buildData(FmRecord.connect, 39, [], false, 0, false, const Trailer()), throwsArgumentError);
    });

    test('record 0 relay keeps received compression and aes bits', () {
      final Uint8List raw = Record0.connect('N0CALL', 'N1CALL', 'N9DIG', '', false, false).toBytes()!;
      raw[34] = 0xC0 | 0x08 | 0x04 | 0x31;
      final int n = raw.length - 2;
      final int crc = crc16Genibus(raw, 0, n);
      raw[n] = crc >> 8;
      raw[n + 1] = crc & 0xFF;
      final Record0 r = Record0.parse(raw)!;
      expect([r.registered, r.compression], [false, 2]);
      expect(r.toBytes()![34], 0x48);
      expect(r.restamp(raw)[34], 0xCC);
    });
  });

  group('fm control', () {
    test('codebooks', () {
      final Map<String, dynamic> c = loadVector('fm/ctrl_codebooks');
      final List<Tones> lead = <Tones>[
        for (final dynamic r in c['leadin_table'] as List<dynamic>) ..._rows(r as String),
      ];
      expect(_sameRows(lead, leadIn), isTrue);
      final List<Codeword> tamper = codes(tamperKey);
      (c['tamper_codebook_codes_1_22'] as Map<String, dynamic>).forEach((k, r) {
        expect(_sameRows(_rows(r as String), tamper[int.parse(k) - 1]), isTrue, reason: 'tamper $k');
      });
      int n = 0;
      for (final dynamic st in c['codebooks'] as List<dynamic>) {
        (st['sides'] as Map<String, dynamic>).forEach((side, info) {
          final int kd = hexU32(info['key_codes_1_22']);
          final int ku = hexU32(info['key_codes_23_24']);
          expect(kd, callHash((info['key_call_1_22'] as String).codeUnits));
          expect(ku, callHash((info['key_call_23_24'] as String).codeUnits));
          final Codebook cb = Codebook(kd, ku);
          (st['codes'][side]['fm'] as Map<String, dynamic>).forEach((code, r) {
            expect(_sameRows(_rows(r as String), cb.code(int.parse(code))), isTrue,
                reason: '${st['station']} $side $code');
            n++;
          });
        });
      }
      expect(n, 10 * 24);
    });

    test('on air', () {
      final Map<String, dynamic> v = loadDoc('fm/lab_ctrl');
      final Codebook cb = Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits);
      int n = 0;
      (v['codes'] as Map<String, dynamic>).forEach((code, e) {
        if (e['rows_codebook'] is String) {
          expect(_sameRows(_rows(e['rows_codebook'] as String), cb.code(int.parse(code))), isTrue, reason: 'code $code');
          n++;
        }
      });
      expect(n, 14);
      final List<dynamic> rows = v['code24_wide']['rows'] as List<dynamic>;
      for (int i = 0; i < rows.length; i++) {
        final List<int> want = ints(rows[i])..sort();
        final List<int> got = [...cb.code(24)[i]]..sort();
        expect(got, want, reason: 'code 24 row ${i + 2}');
      }
    });

    test('lead-in adaptation', () {
      LeadIn l = LeadIn();
      expect([l.report(8), l.report(29 - 11 + 7), l.report(29 - 8 + 7)], [11, 8, 8]);
      l = LeadIn();
      expect([l.report(1), l.dataSymbols], [1, 1]);
      l = LeadIn();
      expect(l.report(2), 2);
      expect(LeadIn().dataSymbols, 25);
      l = LeadIn();
      for (final int r in [1, 1, 1]) {
        l.report(r);
      }
      expect(l.report(29), 2);
      expect(l.report(29), 2);
      expect(dataLeadIn(23), 21);
      expect(connectLeadIn, 21);
    });

    test('frame rows and synth', () {
      final Codebook cb = Codebook.forLink('N0CALL'.codeUnits, 'N1CALL'.codeUnits);
      expect(cb.frameRows(5, 0).length, codeRows);
      expect(cb.frameRows(5, 28).length, codeRows + leadRows);
      expect(_sameRows(cb.frameRows(5, 3).sublist(0, 3), leadIn.sublist(25)), isTrue);
      expect(() => cb.frameRows(5, 29), throwsArgumentError);
      expect(frameAudio(cb, 5, 2, -5.0).length, (codeRows + 2) * ctrlSymbol);
      expect(Codebook(1, 2), Codebook(1, 2));
      expect(Side.source.other, Side.target);
    });
  });

  group('fm tx', () {
    test('lab transmissions are bit-exact', () {
      final List<dynamic> cases = loadVector('fm/fm_tx')['l4'] as List<dynamic>;
      final List<Modulator> mods = [Modulator(FmBandwidth.narrow), Modulator(FmBandwidth.wide)];
      int n = 0;
      for (final dynamic c in cases) {
        final Modulator m = mods[_mode(c['mode']) == FmBandwidth.wide ? 1 : 0];
        final String id = '${c['run']} ${c['dir']} #${c['idx']} rec ${c['record']}';
        _check(id, _dataPcm(m, c as Map<String, dynamic>, -5.0), c, 1009);
        n++;
      }
      expect(n, 99);
    });

    test('all records are bit-exact', () {
      final List<dynamic> cases = loadVector('fm/fm_tx')['levels'] as List<dynamic>;
      final List<Modulator> mods = [Modulator(FmBandwidth.narrow), Modulator(FmBandwidth.wide)];
      for (final dynamic c in cases) {
        final FmBandwidth bw = _mode(c['mode']);
        final Modulator m = mods[bw == FmBandwidth.wide ? 1 : 0];
        final FmRecord record = _rec((c['record'] as num).toInt());
        final String id = '${bw.name} rec ${record.index} lead ${c['lead']}';
        _check(id, _dataPcm(m, c as Map<String, dynamic>, -5.0), c, 1009);
        final RecordTables t = fmCodeTables(bw)[record.index];
        expect(ints(c['perm_entry_bytes']), [2 + (t.chan.length > 65536 ? 1 : 0), 2 + (t.turbo.length > 65536 ? 1 : 0)],
            reason: id);
      }
      expect(cases.length, 39);
    });

    test('control frames are bit-exact', () {
      final List<dynamic> cases = loadVector('fm/fm_tx')['ctrl'] as List<dynamic>;
      for (final dynamic c in cases) {
        final Codebook cb = Codebook.forLink((c['upstream'] as String).codeUnits, (c['downstream'] as String).codeUnits);
        final int code = (c['code'] as num).toInt();
        final int lead = (c['lead'] as num).toInt();
        _check('code $code lead $lead', toI16(frameAudio(cb, code, lead, -5.0)), c as Map<String, dynamic>, 1009);
      }
      expect(cases.length, 72);
    });

    test('tune block is the VARA FM tune tone', () {
      for (final double d in [-30.0, -5.0, 0.0]) {
        final Float64List x = tuneBlock(d);
        expect(x.length, 1024);
        final double rms = math.sqrt(x.fold<double>(0, (a, v) => a + v * v) / 1024);
        expect((20.0 * math.log(rms) / math.ln10 - (d - tuneBackoffDb)).abs() < 1e-9, isTrue);
        expect((x[0] - math.sqrt2 * math.pow(10, (d - 5.007) / 20.0)).abs() < 1e-12, isTrue);
        expect(x.every((v) => v.abs() < 1.0), isTrue);
      }
      final Float64List x = tuneBlock(-5.0);
      for (int n = 0; n < 1024; n++) {
        expect((x[n] - math.cos(2.0 * math.pi * 1500.0 * n / 48000.0) * x[0]).abs() < 1e-12, isTrue);
      }
    });

    test('pre-signal, phasor cache and toI16 saturation', () {
      final Modulator m = Modulator(FmBandwidth.narrow);
      final Float64List a = m.transmission(FmRecord.connect, 0, [List<int>.filled(39, 0)], 0,
          const TxOptions(driveDb: -5, preSignal: true), (_) => 0);
      expect(a.length, (preSignalSymbols + 28) * 1152);
      expect(identical(phasors(123), phasors(123)), isTrue);
      expect(phasors(null).length, fmBins);
      expect(phasors(null)[0].length, phasorRows);
      expect(recordKey(FmRecord.connect, 5), isNull);
      expect(recordKey(const FmRecord(3), 5), 5);
      expect(toI16([1.0, -1.0, 2.0, -2.0, 0.5 / 32767, 1.5 / 32767]), [32767, -32767, 32767, -32768, 0, 2]);
    });
  });
}
