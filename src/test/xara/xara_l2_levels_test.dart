/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 2: HF/FM level tables, puncturing, turbo encoder framing and
the generated permutation/marker (.dat) tables.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/dat.dart';
import 'package:htcommander/hamlib/xara/dsp.dart';
import 'package:htcommander/hamlib/xara/fec.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/hf_level.dart';
import 'package:htcommander/hamlib/xara/numeric.dart';

import 'xara_vectors.dart';

void _close(double a, Object? b, String what) {
  expect(b, isNotNull, reason: '$what: null');
  final double v = (b as num).toDouble();
  expect((a - v).abs() < 1e-6 * math.max(v.abs(), 1.0), isTrue, reason: '$what: $a vs $v');
}

Uint8List _u16be(List<int> v) {
  final Uint8List out = Uint8List(v.length * 2);
  for (int i = 0; i < v.length; i++) {
    expect(v[i] >= 0 && v[i] <= 0xFFFF, isTrue);
    out[2 * i] = v[i] >> 8;
    out[2 * i + 1] = v[i] & 0xFF;
  }
  return out;
}

void main() {
  group('hf levels', () {
    test('all records match levels.json', () {
      final Map<String, dynamic> c = loadVector('levels');
      for (final HfBandwidth bw in HfBandwidth.values) {
        final String key = bw.hz.toString();
        expect(bw.numLevels, c['num_levels'][key]);
        final List<int> offs = datOffsets(bw);
        for (final HfRecord r in HfRecord.all()) {
          final HfLevel l = bw.level(r);
          final Map<String, dynamic> v = c['modes'][key][r.value.toString()] as Map<String, dynamic>;
          final String w = '$key L${r.value}';
          int u(String k) => (v[k] as num).toInt();
          switch (l.kind) {
            case HfWaveKind.fsk:
              expect(v['kind'], 'FSK', reason: w);
              expect([l.symbols, l.fskSps, l.first, l.last, l.step],
                  [u('S'), u('sps'), u('first'), u('last'), u('step')], reason: w);
            case HfWaveKind.psk:
              expect(v['kind'], 'PSK', reason: w);
              expect([l.spf, l.markers, l.nc], [u('spf'), u('markers'), u('nc')], reason: w);
              expect(l.carriersHz, ints(v['fc']), reason: w);
              _close(l.pulse!.span, v['pulse_span'], w);
            case HfWaveKind.ofdm:
              expect(v['kind'], 'OFDM', reason: w);
              expect([l.spf, l.markers, l.nc, l.first],
                  [u('spf'), u('markers'), u('nc'), u('first')], reason: w);
          }
          expect(l.sps, u('sps'), reason: w);
          expect([l.bps, l.rate], [u('bps'), u('rate')], reason: w);
          expect(l.extra, v['extra'], reason: w);
          expect(l.skipOnStepDown ? 1 : 0, u('skip_on_step_down'), reason: w);
          _close(l.snrThrDb, v['thr'], w);
          _close(l.paprDb, v['papr_db'], w);
          expect(
            [l.n, l.k, l.pad, l.otherLen, offs[r.index], l.frameBytes, l.payload, l.leadIn, l.dataSymbols],
            [u('N'), u('K'), u('pad'), u('other'), u('offset'), u('frameBytes'), u('payload'), u('lead'), u('nsym')],
            reason: w,
          );
          _close(l.symbolPeriod, v['T'], w);
          _close(l.airtime, v['airtime'], w);
          _close(l.netBps, v['netbps'], w);
        }
      }
    });

    test('dat record offsets', () {
      final Map<String, dynamic> c = loadVector('dat_tables');
      for (final HfBandwidth bw in HfBandwidth.values) {
        final List<int> offs = datOffsets(bw);
        (c[bw.hz.toString()]['records'] as Map<String, dynamic>).forEach((rs, rec) {
          final HfRecord r = HfRecord.of(int.parse(rs))!;
          final HfLevel l = bw.level(r);
          expect(offs[r.index], hexOrU(rec['offset']), reason: '${bw.hz} $rs');
          expect([l.n, l.k, l.otherLen], [hexOrU(rec['N']), hexOrU(rec['K']), hexOrU(rec['other_len'])],
              reason: '${bw.hz} $rs');
        });
      }
    });

    test('records, helpers and limits', () {
      expect(HfRecord.of(0), isNull);
      expect(HfRecord.of(18), isNull);
      expect(HfRecord.one.down(), HfRecord.one);
      expect(const HfRecord(5).up(2), const HfRecord(7));
      expect(HfRecord.max.up(1), isNull);
      expect(HfRecord.clamped(99, const HfRecord(13)), const HfRecord(13));
      expect(HfRecord.clamped(-5, const HfRecord(13)), HfRecord.one);
      expect(HfRecord.all().length, 17);
      expect(HfBandwidth.hz2300.levels.length, 16);
      expect(HfBandwidth.parse('2750'), HfBandwidth.hz2750);
      expect(HfBandwidth.parse('2700'), isNull);
      expect(HfBandwidth.hz500.passband, (1250.0, 1750.0));
      expect(startLevelMax(HfBandwidth.hz500), const HfRecord(7));
      expect(startLevelMax(HfBandwidth.hz2750), const HfRecord(6));
      for (final HfBandwidth bw in HfBandwidth.values) {
        final HfRecord q = qamLimit(bw);
        expect(bw.level(q).isQam, isFalse);
        for (final HfRecord r in HfRecord.all()) {
          if (r.value > q.value) expect(bw.level(r).isQam, isTrue, reason: '${bw.hz} ${r.value}');
        }
        expect(bw.ampNorm(HfRecord.one), toF32(1.41));
      }
    });

    test('puncturing fits every level', () {
      for (final HfBandwidth bw in HfBandwidth.values) {
        for (final HfLevel l in bw.table) {
          expect(puncturedLen(l.k, l.puncturePeriodValue) <= l.n, isTrue);
          expect(l.pad, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('fm levels', () {
    test('levels table matches fm/levels.json', () {
      final List<dynamic> recs = loadDoc('fm/levels')['records'] as List<dynamic>;
      expect(recs.length, 34);
      for (final dynamic r in recs) {
        final FmBandwidth bw = r['mode'] == 'NARROW' ? FmBandwidth.narrow : FmBandwidth.wide;
        final FmRecord rec = FmRecord.fromIndex((r['record'] as num).toInt())!;
        final FmLevel l = bw.level(rec);
        final String id = '${bw.name} ${rec.index}';
        expect(l.frameBytes, r['frame_bytes'], reason: id);
        expect(l.spf, r['spf'], reason: id);
        expect(l.frameTicks, r['frame_ticks'], reason: id);
        _close(l.snrThrDb, r['snr_threshold_db'], id);
        _close(l.widePenaltyDb, r['wide_penalty_db'], id);
        if (r['decode_allow_ticks'] != null) expect(l.decodeAllow, r['decode_allow_ticks'], reason: id);
        if (r['net_bitrate'] != null) {
          expect(asI64(roundTiesEven(l.netBps)), r['net_bitrate'], reason: id);
        }
        final int used = puncturedLen(l.layout.k, l.puncturePeriodValue);
        expect(used <= l.n && l.n - used <= 2, isTrue, reason: '$id: $used of ${l.n}');
        expect((r['frame_ms'] as num).toDouble(), l.frameTicks * 128 / 48.0, reason: id);
      }
    });

    test('records and levels', () {
      expect(FmRecord.connect.keyed, isFalse);
      expect(FmRecord.broadcast.keyed, isFalse);
      expect(FmRecord.short.keyed, isTrue);
      expect(FmRecord.connect.dataLevel, isNull);
      expect(FmRecord.short.level, DataLevel.one);
      expect(FmRecord.start.level, DataLevel.one);
      expect(FmRecord.broadcast.level, isNull);
      expect(const FmRecord(13).dataLevel, const DataLevel(13));
      expect(FmRecord.fromIndex(17), isNull);
      expect(DataLevel.of(14), isNull);
      expect(DataLevel.max.up(1), isNull);
      expect(DataLevel.one.down(), DataLevel.one);
      expect(DataLevel.clamped(40, const DataLevel(11)), const DataLevel(11));
      expect(FmBandwidth.narrow.levels.length, 11);
      expect(FmBandwidth.wide.topLevel, const DataLevel(13));
      expect(fmMaxSpf, 201);
      final FmLevel l = FmBandwidth.wide.dataLevel(const DataLevel(9));
      expect(l.nc, 116);
      expect(l.bins.first, 6);
      expect(l.bins.last, 6 + 115);
      expect(l.isQam, isTrue);
      expect(FmBandwidth.narrow.dataLevel(const DataLevel(3)).bins.toList().sublist(0, 3), [10, 11, 12]);
      expect(fmQamPilot(10, 2), isTrue);
      expect(fmQamPilot(11, 3), isTrue);
      expect(fmQamPilot(11, 2), isFalse);
      expect(fmQamPilot(10, 11), isTrue);
    });

    test('gain', () {
      expect(fmGain(10.0, 0.0), closeTo(math.pow(10, -12 / 20), 1e-15));
      final FmLevel l = FmBandwidth.narrow.level(FmRecord.connect);
      expect(l.gain(-5.0), closeTo(dbAmp(-(toF32(8.6) + 2.0 + (10.0 - toF32(8.6)) / 1000.0 + 5.0)), 1e-15));
    });

    test('layouts', () {
      for (final FmBandwidth bw in FmBandwidth.values) {
        for (final FmLayout f in bw.layouts) {
          expect(f.otherLen, f.nc * (f.markers + f.spf - 1));
          expect(f.n, greaterThan(f.k));
        }
      }
    });
  });

  group('fec', () {
    test('puncture periods and lengths', () {
      expect([2, 3, 4, 5, 6, 7].map(puncturePeriod).toList(), [1, 2, 4, 6, 8, 10]);
      expect(() => puncturePeriod(8), throwsArgumentError);
      expect(puncturedLen(96, 1), 300);
      for (final int p in [2, 4, 6, 8, 10]) {
        for (final int k in [0, 1, 2, 3, 5, 96, 297, 4755]) {
          final Uint8List info = Uint8List(k);
          int count = 0;
          for (int t = 0; t < k; t++) {
            count += 1 + (t % p == 0 ? 1 : 0) + (t % p == p ~/ 2 ? 1 : 0);
          }
          expect(puncturedLen(k, p), count + 12, reason: 'k=$k p=$p');
          expect(turboEncode(info, List<int>.generate(k, (i) => i), p, puncturedLen(k, p)).length,
              puncturedLen(k, p));
        }
      }
    });

    test('turbo encoder structure', () {
      final math.Random rng = math.Random(7);
      for (final int p in [1, 2, 4, 6, 8, 10]) {
        const int k = 200;
        final Uint8List info = Uint8List.fromList(List<int>.generate(k, (_) => rng.nextInt(2)));
        final List<int> perm = List<int>.generate(k, (i) => i)..shuffle(rng);
        final int used = puncturedLen(k, p);
        final Uint8List out = turboEncode(info, perm, p, used + 5);
        expect(out.sublist(used), everyElement(0), reason: 'padding');
        int o = 0;
        for (int t = 0; t < k; t++) {
          expect(out[o++], info[t], reason: 'systematic p=$p t=$t');
          if (p == 1 || t % p == 0) o++;
          if (p == 1 || t % p == p ~/ 2) o++;
        }
        expect(o, used - 12);
        expect(() => turboEncode(info, perm, p, used - 1), throwsStateError);
      }
    });

    test('rsc tail terminates the encoder', () {
      final math.Random rng = math.Random(11);
      for (int trial = 0; trial < 50; trial++) {
        final int k = 1 + rng.nextInt(64);
        final Uint8List info = Uint8List.fromList(List<int>.generate(k, (_) => rng.nextInt(2)));
        final Uint8List out = turboEncode(info, List<int>.generate(k, (i) => k - 1 - i), 1, 3 * k + 12);
        int r0 = 0, r1 = 0, r2 = 0;
        for (int t = 0; t < k + 3; t++) {
          final int u = out[t < k ? 3 * t : 3 * k + 4 * (t - k)];
          final int a = u ^ r0 ^ r1;
          final int parity = out[t < k ? 3 * t + 1 : 3 * k + 4 * (t - k) + 1];
          expect(parity, a ^ r2 ^ r0);
          r0 = r1;
          r1 = r2;
          r2 = a;
        }
        expect([r0, r1, r2], [0, 0, 0], reason: 'k=$k');
      }
    });

    test('frame bits, whitening and interleave', () {
      expect(frameBits([0xA5, 0x01], 12), [1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0]);
      expect(frameBits([0xFF], 10), [1, 1, 1, 1, 1, 1, 1, 1, 0, 0]);
      expect(frameBits([0xFF, 0xFF], 4), [1, 1, 1, 1]);
      final List<int> bits = [1, 0, 1, 1];
      whiten(bits, [1, 1, 0]);
      expect(bits, [0, 1, 1, 1]);
      expect(interleave([10, 20, 30], [2, 0, 1]), [30, 10, 20]);
    });
  });

  group('dsp', () {
    test('quantise', () {
      expect(quantise(0.0), 0.0);
      expect(quantise(2.0), 1.0);
      expect(quantise(-2.0), -1.0);
      expect(quantise(0.5 / 32767), 0.0);
      expect(quantise(1.5 / 32767), 2 / 32767);
      expect(quantise(2.5 / 32767), 2 / 32767);
      expect(quantise(-1.5 / 32767), -2 / 32767);
      expect(quantise(0.3) * 32767, (0.3 * 32767).roundToDouble());
      expect(quantise(-0.0).isNegative, isTrue);
    });

    test('db_amp', () {
      expect(dbAmp(0), 1.0);
      expect(dbAmp(20), closeTo(10.0, 1e-12));
      expect(dbAmp(-6.0206), closeTo(0.5, 1e-5));
    });
  });

  group('dat tables', () {
    test('hf records match per-record hashes', () {
      final Map<String, dynamic> c = loadVector('dat_tables');
      for (final HfBandwidth bw in HfBandwidth.values) {
        final List<RecordTables> t = hfTables(bw);
        final Map<String, dynamic> records = c[bw.hz.toString()]['records'] as Map<String, dynamic>;
        expect(records.length, 17);
        records.forEach((rs, rec) {
          final RecordTables x = t[int.parse(rs) - 1];
          final String w = '${bw.hz} r$rs';
          expect(sha256Hex(_u16be(x.chan)), rec['sha256_chan_u16be'], reason: '$w chan');
          expect(sha256Hex(_u16be(x.turbo)), rec['sha256_turbo_u16be'], reason: '$w turbo');
          expect(sha256Hex(_u16be(x.other)), rec['sha256_other_u16be'], reason: '$w other');
        });
      }
    });

    test('hf files', () {
      final Map<String, dynamic> c = loadVector('dat_tables');
      for (final (HfBandwidth bw, String sha) in const [
        (HfBandwidth.hz500, '020cf75a54c772ade64cdb45b52053beef3223b5bdb4847da1354d03627ed956'),
        (HfBandwidth.hz2300, '2c823ce719944dccf90194129b7c95f91b9add7c33a46bb0c80b8401d0edcfe5'),
        (HfBandwidth.hz2750, 'e3e516f70f7710dc7992196573ce0141f5604d978e2701dced26eb06de3aede6'),
      ]) {
        final Map<String, dynamic> v = c[bw.hz.toString()] as Map<String, dynamic>;
        final Uint8List d = hfDat(bw);
        expect(d.length, v['table_segment_len']);
        expect((d[d.length - 2] << 8) | d[d.length - 1], hexU32(v['crc_stored_be']));
        expect(sha256Hex(d), sha, reason: '${bw.hz}');
      }
    });

    test('fm files', () {
      for (final (FmBandwidth bw, int len, String sha) in const [
        (FmBandwidth.narrow, 1984786, 'ab420598450972b6050030d8762431b39c092a5a0bf17a3c03e413e578f1efa2'),
        (FmBandwidth.wide, 3302010, 'c777f8992ccf3fc8362d2311ff35e610cd478f36a1f31c1025b2466b3d2b7e3d'),
      ]) {
        final Uint8List d = fmDat(bw);
        expect(d.length, len, reason: bw.name);
        expect(sha256Hex(d), sha, reason: bw.name);
      }
    });

    test('table invariants', () {
      for (final FmBandwidth bw in FmBandwidth.values) {
        final List<RecordTables> t = fmTablesCached(bw);
        expect(identical(t, fmTablesCached(bw)), isTrue);
        for (int i = 0; i < t.length; i++) {
          final FmLayout f = bw.layouts[i];
          expect(t[i].chan.length, f.n);
          expect(t[i].turbo.length, f.k);
          expect(t[i].other.length, f.otherLen);
          expect((t[i].chan.toList()..sort()), List<int>.generate(f.n, (j) => j));
          final List<List<bool>> map = markerMap(t[i].other, f.nc, f.markers, f.spf - 1);
          expect(map.length, f.nc);
          for (final List<bool> row in map) {
            expect(row.where((b) => b).length, f.markers);
          }
        }
      }
    });
  });
}
