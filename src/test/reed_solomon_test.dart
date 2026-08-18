import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/reed_solomon.dart';

void main() {
  test('RS(255,231) corrects up to 12 errors', () {
    final rs = ReedSolomon(nroots: 24, fcr: 0);
    final rnd = Random(42);
    for (int trial = 0; trial < 20; trial++) {
      final cw = List<int>.filled(255, 0);
      for (int i = 24; i < 255; i++) {
        cw[i] = rnd.nextInt(256);
      }
      rs.encode(cw);
      final orig = List<int>.from(cw);

      // Inject 12 errors at distinct positions.
      final positions = <int>{};
      while (positions.length < 12) {
        positions.add(rnd.nextInt(255));
      }
      for (final p in positions) {
        cw[p] ^= 1 + rnd.nextInt(255);
      }
      final nerr = rs.decode(cw);
      expect(nerr, greaterThanOrEqualTo(0), reason: 'should be correctable');
      expect(cw, orig, reason: 'must recover the original codeword');
    }
  });

  test('RS(255,231) reports zero errors on a clean codeword', () {
    final rs = ReedSolomon(nroots: 24, fcr: 0);
    final cw = List<int>.filled(255, 0);
    for (int i = 24; i < 255; i++) {
      cw[i] = (i * 7) & 0xFF;
    }
    rs.encode(cw);
    expect(rs.decode(cw), 0);
  });

  test('RS(255,223) CCSDS (LMS6) corrects up to 16 errors', () {
    final rs = ReedSolomon(nroots: 32, fcr: 112, prim: 0x187, primPow: 11);
    final rnd = Random(7);
    for (int trial = 0; trial < 20; trial++) {
      final cw = List<int>.filled(255, 0);
      for (int i = 32; i < 255; i++) {
        cw[i] = rnd.nextInt(256);
      }
      rs.encode(cw);
      final orig = List<int>.from(cw);
      final positions = <int>{};
      while (positions.length < 16) {
        positions.add(rnd.nextInt(255));
      }
      for (final p in positions) {
        cw[p] ^= 1 + rnd.nextInt(255);
      }
      final nerr = rs.decode(cw);
      expect(nerr, greaterThanOrEqualTo(0));
      expect(cw, orig);
    }
  });
}
