/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

XARA port, layer 1: CRC, callsign hash/packing, VB Rnd, whitening/phasor
sequences, XorShift, bit codecs and Rust numeric semantics. Expected values
come from the upstream XARA vectors and unit tests unless noted otherwise.
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/bits.dart';
import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/crc.dart';
import 'package:htcommander/hamlib/xara/numeric.dart';
import 'package:htcommander/hamlib/xara/rnd.dart';
import 'package:htcommander/hamlib/xara/seq.dart' as seq;
import 'package:htcommander/hamlib/xara/xorshift.dart';

import 'xara_vectors.dart';

VbRnd _setup(List<dynamic> steps) {
  final VbRnd r = VbRnd();
  for (final Object? s in steps) {
    final String step = s as String;
    if (step == 'rnd(-1)') {
      r.rnd(-1.0);
    } else {
      final String arg = step.substring('randomize('.length, step.length - 1);
      r.randomize(double.parse(arg));
    }
  }
  return r;
}

String _bitstr(List<int> bits) => bits.map((b) => b.toString()).join();

Uint8List _packbits(List<int> bits) {
  final Uint8List out = Uint8List((bits.length + 7) ~/ 8);
  for (int i = 0; i < bits.length; i++) {
    if (bits[i] != 0) out[i >> 3] |= 0x80 >> (i & 7);
  }
  return out;
}

Uint8List _mod128(List<Uint8List> rows) => Uint8List.fromList([
      for (final Uint8List r in rows)
        for (final int x in r) x % 128,
    ]);

Uint8List _fromCodes(List<int> c) {
  int v = 0;
  for (final int x in c) {
    v = (v << 6) | x;
  }
  return Uint8List.fromList([for (int i = 5; i >= 0; i--) (v >> (8 * i)) & 0xFF]);
}

void main() {
  group('crc', () {
    test('check value', () {
      expect(crc16Genibus('123456789'.codeUnits), 0xD64E);
    });

    test('vectors', () {
      final Map<String, dynamic> c = loadVector('crc_hash_pack');
      final Map<String, dynamic> crcs = c['crc16_genibus'] as Map<String, dynamic>;
      expect(crcs, isNotEmpty);
      crcs.forEach((name, v) {
        expect(crc16Genibus(hexDecode(v['hex'] as String)), hexU32(v['crc']),
            reason: name);
      });
    });

    test('crcOk', () {
      final List<int> body = 'N0CALL'.codeUnits;
      final int crc = crc16Genibus(body);
      final List<int> frame = [...body, crc >> 8, crc & 0xFF];
      expect(crcOk(frame), isTrue);
      expect(crcOk([...frame]..[0] ^= 1), isFalse);
      expect(crcOk([...body.take(0), crc >> 8, crc & 0xFF]), isFalse);
      final int e = crc16Genibus([0x41]);
      expect(crcOk([0x41, e >> 8, e & 0xFF]), isTrue);
      expect(crcOk(const <int>[]), isFalse);
    });

    test('sub-range matches slice', () {
      final List<int> data = List<int>.generate(300, (i) => (i * 37) & 0xFF);
      expect(crc16Genibus(data, 10, 200), crc16Genibus(data.sublist(10, 200)));
    });
  });

  group('call', () {
    test('spec examples', () {
      expect(callHash('N0CALL'.codeUnits), 0xD80986);
      expect(callHash(const <int>[]), 0);
      expect(packCall('N0CALL'.codeUnits), [0x39, 0xb0, 0xc1, 0x30, 0xc0, 0x00]);
      expect(packCall('AB1CD-1'.codeUnits), [0x04, 0x27, 0x03, 0x10, 0x00, 0x01]);
      expect(packCall('N0CALL-T'.codeUnits), [0x39, 0xb0, 0xc1, 0x30, 0xc0, 0x10]);
    });

    test('ssid round trip', () {
      for (final String c in [
        'N0CALL', 'AB1CD-1', 'AB1CD-11', 'N0CALL-T', 'N0CALL-R', 'N0CALL-X',
        'N0CALL-L', 'W1AW-15', 'VE3ABCD-9',
      ]) {
        expect(unpackCall(packCall(c.codeUnits)), c);
      }
    });

    test('ssid as VARA sends it', () {
      const List<int> n0call = [14, 27, 3, 1, 12, 12, 0];
      for (final (String ssid, int code) in const [
        ('2', 2), ('10', 10), ('15', 15), ('T', 16), ('R', 17), ('X', 18),
        ('L', 19), ('19', 19),
      ]) {
        expect(packCall('N0CALL-$ssid'.codeUnits), _fromCodes([...n0call, code]),
            reason: ssid);
      }
      for (final String bad in ['0', '20', '255', '256', 'Q', '', '-1']) {
        expect(packCall('N0CALL-$bad'.codeUnits), _fromCodes([...n0call, 0]),
            reason: bad);
      }
      expect(packCall('N0CALL-+5'.codeUnits), _fromCodes([...n0call, 5]));
    });

    test('ssid codes', () {
      expect(ssidCode('T'), 0x10);
      expect(ssidCode('L'), 0x13);
      expect(ssidCode('255'), 255);
      expect(ssidCode('256'), isNull);
      expect(ssidCode('+7'), 7);
      expect(ssidCode(' 7'), isNull);
      expect(ssidCode(''), isNull);
      expect(withSsid('N0CALL', 0), 'N0CALL');
      expect(withSsid('N0CALL', 0x12), 'N0CALL-X');
      expect(withSsid('N0CALL', 42), 'N0CALL-42');
    });

    test('long and lowercase calls', () {
      expect(unpackCall(packCall('ABCDEFGH'.codeUnits)), 'ABCDEFG-8');
      expect(unpackCall(packCall('n0call'.codeUnits)), ' 0');
      expect(unpackCall(const [1, 2, 3, 4, 5]), isNull);
    });

    test('vectors', () {
      final Map<String, dynamic> c = loadVector('crc_hash_pack');
      (c['call_hash'] as Map<String, dynamic>).forEach((call, v) {
        final Uint8List b = latin1Bytes(call);
        expect(crc16Genibus(b), hexU32(v['crc_call']), reason: call);
        expect(callHash(b), hexU32(v['hash']), reason: call);
      });
      (c['packed_call'] as Map<String, dynamic>).forEach((call, v) {
        expect(hexEncode(packCall(latin1Bytes(call))), v['hex'], reason: call);
      });
    });

    test('alphabet table items', () {
      final Map<String, dynamic> c = loadVector('alphabet_table');
      (c['call_hash'] as Map<String, dynamic>).forEach((call, h) {
        expect(callHash(call.codeUnits), hexU32(h), reason: call);
      });
      (c['packed_call'] as Map<String, dynamic>).forEach((call, p) {
        expect(hexEncode(packCall(call.codeUnits)), p, reason: call);
      });
    });

    test('US calls', () {
      for (final String c in ['N0CALL', 'K1AB', 'W1AW', 'KB1ABC', 'AA1AB', 'K1ABC-5']) {
        expect(isUsCall(c), isTrue, reason: c);
      }
      for (final String c in ['VE3ABC', 'AM1AB', 'N12ABC', 'NAB', 'N0CALLX', 'AB12', 'N0-AL', 'AN12AB']) {
        expect(isUsCall(c), isFalse, reason: c);
      }
      expect(isUsCall('AA12AB'), isFalse);
      expect(isUsCall('AA1A'), isTrue);
      expect(isUsCall('AL1AB'), isTrue);
      expect(isUsCall('AA1ABC'), isFalse);
      expect(isUsCall('NA1ABC'), isFalse);
      expect(isUsCall('KA1ABC'), isTrue);
    });
  });

  group('rnd', () {
    test('spec examples', () {
      final VbRnd r = VbRnd();
      expect(r.nextF32(), toF32(0.7055475));
      expect(r.state, 0xB49EC3);
    });

    test('sequences', () {
      final Map<String, dynamic> c = loadVector('rnd');
      final Map<String, dynamic> seqs = c['sequences'] as Map<String, dynamic>;
      expect(seqs, isNotEmpty);
      seqs.forEach((name, s) {
        final VbRnd r0 = _setup(s['setup'] as List<dynamic>);
        expect(r0.state, hexU32(s['state0']), reason: name);
        final VbRnd r = r0.copy();
        for (final dynamic d in s['draws'] as List<dynamic>) {
          expect(r.nextF32(), (d[0] as num).toDouble(), reason: name);
          expect(r.state, hexU32(d[1]), reason: name);
        }
        (s as Map<String, dynamic>).forEach((key, want) {
          final RegExpMatch? m = RegExp(r'^randint_(\d+)_x48$').firstMatch(key);
          if (m == null) return;
          final VbRnd r = r0.copy();
          final int n = int.parse(m.group(1)!);
          expect(List<int>.generate(48, (_) => r.randInt(n)), ints(want),
              reason: '$name $key');
        });
      });
    });

    test('negative and zero', () {
      final Map<String, dynamic> c = loadVector('rnd');
      (c['rnd_negative'] as Map<String, dynamic>).forEach((x, want) {
        final VbRnd r = VbRnd();
        expect(r.rnd(double.parse(x)), (want['value'] as num).toDouble(), reason: 'rnd($x)');
        expect(r.state, hexU32(want['state']), reason: 'rnd($x)');
      });
      final Map<String, dynamic> z = c['rnd_zero'] as Map<String, dynamic>;
      final VbRnd r = VbRnd();
      expect(r.nextF32(), (z['rnd'] as num).toDouble());
      expect(r.rnd(0.0), (z['rnd0'] as num).toDouble());
      expect(r.rnd(0.0), (z['rnd0_again'] as num).toDouble());
      expect(r.state, hexU32(z['state']));
    });

    test('randomize', () {
      final Map<String, dynamic> c = loadVector('rnd');
      (c['randomize_after_rnd_minus1'] as Map<String, dynamic>).forEach((d, want) {
        expect(VbRnd.stream(double.parse(d)).state, hexU32(want), reason: 'randomize($d)');
      });
    });

    test('seed_rnd', () {
      final Map<String, dynamic> c = loadVector('rnd');
      (c['seed_rnd'] as Map<String, dynamic>).forEach((xs, want) {
        final int x = int.parse(xs);
        final VbRnd r = VbRnd();
        r.rnd(0.25);
        r.seedRnd(x);
        expect(x ~/ 32768 + 1, (want['rnd_calls'] as num).toInt());
        expect(r.state, hexU32(want['state']), reason: 'seed_rnd($x)');
        expect(List<int>.generate(8, (_) => r.randInt(6)), ints(want['next_randint6_x8']),
            reason: 'seed_rnd($x)');
      });
    });

    test('float32 edges', () {
      final Map<String, dynamic> c = loadVector('rnd');
      final List<dynamic> edges = c['rand_int_float32_edges'] as List<dynamic>;
      expect(edges, isNotEmpty);
      for (final dynamic e in edges) {
        final VbRnd r = VbRnd.fromState(hexU32(e['state_before']));
        final int got = r.randInt((e['n'] as num).toInt());
        expect(r.state, hexU32(e['state_after']), reason: '$e');
        expect(got, (e['rand_int'] as num).toInt(), reason: '$e');
      }
    });

    test('retreat inverts advance', () {
      final VbRnd r = VbRnd.fromState(0x123456);
      for (int i = 0; i < 1000; i++) {
        final int s = r.state;
        r.advance();
        r.retreat();
        expect(r.state, s);
        r.advance();
      }
      final VbRnd a = VbRnd();
      for (int i = 0; i < 50; i++) {
        a.advance();
      }
      for (int i = 0; i < 50; i++) {
        a.retreat();
      }
      expect(a.state, VbRnd.startState);
    });

    test('state stays within 24 bits', () {
      final VbRnd r = VbRnd.fromState(0xFFFFFFFF);
      expect(r.state, 0xFFFFFF);
      for (int i = 0; i < 10000; i++) {
        final double v = r.nextF32();
        expect(v >= 0 && v < 1, isTrue);
        expect(r.state >>> 24, 0);
      }
    });
  });

  group('sequences', () {
    test('whitening', () {
      final Map<String, dynamic> c = loadVector('sequences');
      final Map<String, dynamic> w = c['whitening'] as Map<String, dynamic>;
      final Uint8List bits = seq.whitening(seq.hfSeed);
      expect(bits.length, (w['n'] as num).toInt());
      expect(bits.fold<int>(0, (a, b) => a + b), (w['ones'] as num).toInt());
      expect(_bitstr(bits.sublist(0, 256)), w['first_256']);
      expect(_bitstr(bits.sublist(10000, 10064)), w['bits_10000_10063']);
      expect(_bitstr(bits.sublist(149936)), w['bits_149936_149999']);
      expect(sha256Hex(_packbits(bits)), w['sha256_packbits']);
      final Uint8List fm = seq.whitening(seq.fmSeed);
      expect(_bitstr(fm.sublist(0, 256)), c['fm_whitening_randomize43_first_256']);
    });

    test('psk phasors', () {
      final Map<String, dynamic> v =
          loadVector('sequences')['psk_phasor_index'] as Map<String, dynamic>;
      final List<Uint8List> d = seq.pskPhasorIndex();
      final List<dynamic> rows = v['rows'] as List<dynamic>;
      expect(rows.length, d.length);
      for (int i = 0; i < rows.length; i++) {
        expect(d[i].map((x) => x % 128).toList(), words(rows[i]), reason: 'row $i');
      }
      expect(sha256Hex(_mod128(d)), v['sha256_int8']);
    });

    test('data.dat and ofdm phasors', () {
      final Map<String, dynamic> c = loadVector('sequences');
      expect(sha256Hex(seq.dataDat()), c['data_dat']['sha256']);
      final Map<String, dynamic> v = c['ofdm_phasor_index'] as Map<String, dynamic>;
      final List<Uint8List> d = seq.ofdmPhasorIndex();
      expect(sha256Hex(_mod128(d)), v['sha256_int8']);
      final List<dynamic> bins = v['bins_8_12_m_0_15'] as List<dynamic>;
      for (int k = 8; k < 13; k++) {
        expect(d[k].sublist(0, 16).map((x) => x % 128).toList(), words(bins[k - 8]),
            reason: 'bin $k');
      }
      expect(d[8].sublist(400, 421).map((x) => x % 128).toList(), words(v['bin_8_m_400_420']));
    });
  });

  group('xorshift', () {
    // Expected values from an independent arbitrary-precision Python model.
    final List<(int, List<int>, List<int>, List<int>, List<double>)> cases = [
      (0, [1082269761, 1152992998833853505, -7269227409276787159, -768720241707614171, -8787613929710185883, -670945072575735807],
          [0, 1, 0, 37, 335201, 12421195694], [0, 0, 3, 2992, 23397],
          [5.866995778092132e-11, 0.06250387570981197, 0.6059343925285465]),
      (3, [3246809283, 3458978961873255618, -5970913881654538693, -8073310190798786457, 2989467004630237895, -5052797415611061758],
          [0, 0, 0, 103, 50655, 573239970087], [0, 0, 2, 3254, 40971],
          [1.7600987334276397e-10, 0.18751162525223186, 0.6763161098893146]),
      (-7046029254386353131, [-2586341971585708627, 7273575876580499574, 8865281517519135030, 3485510186621062260, 3236705911238380268, -7561511002437846151],
          [0, 0, 0, 116, 522404, 886070111068], [0, 0, 3, 441, 77175],
          [0.8597941207808165, 0.39430133835633674, 0.48058787404949177]),
      (-2691343689449507777, [-2483561819712510697, -4871399682289622883, -1754607195921908324, 4402181658423684967, -4048659175002702727, 7296229628970462913],
          [0, 1, 6, 103, 622501, 209414368599], [0, 0, 3, 685, 37651],
          [0.8653658439782821, 0.7359208940708197, 0.9048825533161383]),
    ];

    test('matches the u64 reference model', () {
      for (final (int seed, List<int> s, List<int> up, List<int> be, List<double> un) in cases) {
        final XorShift a = XorShift(seed);
        expect(List<int>.generate(s.length, (_) => a.nextU64()), s, reason: '$seed');
        final XorShift b = XorShift(seed);
        expect([for (final int n in const [0, 1, 6, 255, 1000003, 1 << 40]) b.upto(n)], up,
            reason: '$seed');
        final XorShift c = XorShift(seed);
        expect([for (final int n in const [0, 1, 7, 4096, 99991]) c.below(n)], be,
            reason: '$seed');
        final XorShift d = XorShift(seed);
        expect(List<double>.generate(3, (_) => d.uniform()), un, reason: '$seed');
      }
    });

    test('copy preserves state', () {
      final XorShift a = XorShift(42);
      for (int i = 0; i < 7; i++) {
        a.nextU64();
      }
      final XorShift b = a.copy();
      expect(List<int>.generate(20, (_) => b.nextU64()),
          List<int>.generate(20, (_) => a.nextU64()));
    });
  });

  group('bits', () {
    test('push and pack', () {
      final Bits b = Bits()..push(0x5, 3)..push(0xAB, 8)..push(1, 1);
      expect(b.length, 12);
      expect(b.pack(), [0xB5, 0x70]);
      expect(Bits.unpack([0xB5, 0x70]).bits.sublist(0, 12), b.bits);
      final Bits top = Bits()..push(-1, 64);
      expect(top.bits.every((x) => x), isTrue);
      expect(Reader(top.bits).take(64), -1);
    });

    test('push_bfi keeps the high bits', () {
      expect((Bits()..pushBfi(0, 4)).bits, [false, false, false, false]);
      expect((Bits()..pushBfi(5, 4)).pack(), [0x50]);
      expect((Bits()..pushBfi(0x1FF, 4)).pack(), [0xF0]);
      expect((Bits()..pushBfi(0x100, 4)).pack(), [0x80]);
      expect((Bits()..pushBfi(-1, 7)).pack(), [0xFE]);
      expect((Bits()..pushBfi(0x4000000000000000, 3)).pack(), [0x80]);
    });

    test('text7 round trip and padding', () {
      for (final String s in ['', 'A', 'Hello', 'Hello, world', '~~~', 'x\u007f']) {
        final Bits b = Bits()..pushText7(s.codeUnits);
        expect(b.length % 8, 0, reason: s);
        expect(b.length, greaterThan(s.length * 7), reason: s);
        expect(Reader(Bits.unpack(b.pack()).bits).text7(), s.codeUnits, reason: s);
      }
      expect(Reader(<bool>[]).text7(), isNull);
    });

    test('reader', () {
      final Reader r = Reader(Bits.unpack([0xA5]).bits);
      expect(r.bit(), isTrue);
      expect(r.take(3), 2);
      expect(r.text(2), '01');
      expect(r.remaining, 2);
      expect(r.take(3), isNull);
      expect(r.text(3), isNull);
      expect(r.take(2), 1);
      expect(r.bit(), isNull);
      expect(r.remaining, 0);
    });

    test('vb_val', () {
      expect(vbVal('123'.codeUnits), 123);
      expect(vbVal(' 1 2 3x9'.codeUnits), 123);
      expect(vbVal('x12'.codeUnits), 0);
      expect(vbVal(''.codeUnits), 0);
      expect(vbVal('18446744073709551615'.codeUnits), -1);
      expect(vbVal('99999999999999999999999'.codeUnits), -1);
      expect(vbVal('9223372036854775808'.codeUnits), -9223372036854775808);
    });
  });

  group('rust numerics', () {
    test('round ties even', () {
      expect(roundTiesEven(0.5), 0.0);
      expect(roundTiesEven(1.5), 2.0);
      expect(roundTiesEven(2.5), 2.0);
      expect(roundTiesEven(-2.5), -2.0);
      expect(roundTiesEven(-3.5), -4.0);
      expect(roundTiesEven(2.4999999), 2.0);
      expect(roundTiesEven(1e300), 1e300);
    });

    test('saturating casts', () {
      expect(asU32(double.nan), 0);
      expect(asU32(-3.7), 0);
      expect(asU32(3.99), 3);
      expect(asU32(1e20), 0xFFFFFFFF);
      expect(asI64(-3.7), -3);
      expect(asI64(double.infinity), 0x7FFFFFFFFFFFFFFF);
      expect(asI64(double.negativeInfinity), -0x8000000000000000);
      expect(asI64(double.nan), 0);
    });

    test('f32 helpers', () {
      expect(toF32(0.1), isNot(0.1));
      expect(toF32(toF32(0.1)), toF32(0.1));
      expect(f32Bits(-1.0), 0xBF800000);
      expect(f64Bits(292.0) >>> 32, 0x40724000);
      expect(compareU64(-1, 1), 1);
      expect(compareU64(1, 2), -1);
      expect(bitWidthU64(0), 0);
      expect(bitWidthU64(-1), 64);
    });
  });
}
