// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/fec/native_reed_solomon.dart';
import 'package:htcommander/hamlib/fx25.dart';
import 'package:htcommander/hamlib/fx25_encode.dart';
import 'package:htcommander/hamlib/reed_solomon_codec.dart' as fx;
import 'package:htcommander/radiosonde/reed_solomon.dart' as sonde;

List<int> _damage(List<int> block, int count, Random random) {
  final positions = List.generate(255, (i) => i)..shuffle(random);
  for (final p in positions.take(count)) {
    block[p] ^= 1 + random.nextInt(255);
  }
  return positions.take(count).toList();
}

void main() {
  for (final ccsds in [false, true]) {
    sonde.ReedSolomon codec(bool native) => sonde.ReedSolomon(
      nroots: ccsds ? 32 : 24,
      fcr: ccsds ? 112 : 0,
      prim: ccsds ? 0x187 : 0x11d,
      primPow: ccsds ? 11 : 1,
      useNative: native,
    );
    final name = ccsds ? 'LMS6 CCSDS' : 'RS41';
    test('$name native/reference encode and correction boundaries', () {
      final native = codec(true);
      final reference = codec(false);
      addTearDown(native.dispose);
      final random = Random(ccsds ? 187 : 11);
      final roots = native.nroots;
      var failures = 0;
      for (int trial = 0; trial < 80; trial++) {
        // Alternate ordinary Lists with typed subviews and zero messages.
        final storage = Uint8List(259)..fillRange(0, 259, 0xa5);
        final a = trial.isEven
            ? List<int>.filled(255, 0)
            : Uint8List.sublistView(storage, 2, 257);
        a.fillRange(0, 255, 0);
        for (int i = roots; i < 255; i++) {
          a[i] = trial == 0 ? 0 : random.nextInt(256);
        }
        final b = List<int>.from(a);
        native.encode(a);
        reference.encode(b);
        expect(a, b, reason: '$name encoding $trial');
        final clean = List<int>.from(a);
        final errors = switch (trial % 4) {
          0 => 0,
          1 => roots ~/ 2,
          2 => roots ~/ 2 + 1,
          _ => random.nextInt(100),
        };
        _damage(a, errors, random);
        b.setAll(0, a);
        final actual = native.decode(a);
        final expected = reference.decode(b);
        expect(actual, expected, reason: '$name status trial $trial/$errors');
        expect(a, b, reason: '$name mutation trial $trial/$errors');
        if (errors <= roots ~/ 2) {
          expect(actual, errors);
          expect(a, clean);
        }
        if (errors > roots ~/ 2 && actual == -1) failures++;
        if (trial.isOdd) {
          expect(storage.take(2), [0xa5, 0xa5]);
          expect(storage.skip(257), [0xa5, 0xa5]);
        }
      }
      expect(failures, greaterThan(0));
      native.dispose();
      // Disposing the cached storage does not invalidate the codec.
      final zero = Uint8List(255);
      native.encode(zero);
      expect(native.decode(zero), 0);
    }, skip: !nativeReedSolomonSupported);

    test('$name invalid input is not an uncorrectable result', () {
      for (final native in [false, true]) {
        final rs = codec(native);
        addTearDown(rs.dispose);
        expect(() => rs.decode(List.filled(254, 0)), throwsArgumentError);
        expect(() => rs.encode(List.filled(255, 256)), throwsRangeError);
      }
    });

    test('$name clean read-only blocks do not require mutation', () {
      for (final native in [false, true]) {
        final rs = codec(native);
        addTearDown(rs.dispose);
        expect(rs.decode(List<int>.unmodifiable(List.filled(255, 0))), 0);
      }
    });
  }

  Fx25.init(0);
  for (final tag in [1, 5, 9]) {
    final rs = Fx25.getRs(tag);
    final roots = rs.nRoots;
    test('FX.25 $roots parity/correction/erasure differential', () {
      addTearDown(() => fx.ReedSolomon.dispose(rs));
      final random = Random(2500 + roots);
      var uncorrectable = 0;
      for (int trial = 0; trial < 100; trial++) {
        final original = Uint8List(255);
        for (int i = 0; i < 255 - roots; i++) {
          original[i] = trial == 0 ? 0 : random.nextInt(256);
        }
        final parity = Uint8List(roots + 2)..fillRange(0, roots + 2, 0x5a);
        final referenceParity = Uint8List(roots + 2)
          ..fillRange(0, roots + 2, 0x5a);
        fx.ReedSolomon.encode(rs, original, parity);
        Fx25Encode.encodeRs(rs, original, referenceParity, useNative: false);
        expect(parity, referenceParity);
        expect(parity.skip(roots), [0x5a, 0x5a]);
        final duplicateParity = Uint8List(roots);
        Fx25Encode.encodeRs(rs, original, duplicateParity);
        expect(duplicateParity, parity.take(roots));
        original.setRange(255 - roots, 255, parity);
        final storage = Uint8List(259)..fillRange(0, 259, 0xa5);
        final a = Uint8List.sublistView(storage, 2, 257)..setAll(0, original);
        final errors = switch (trial % 5) {
          0 => 0,
          1 => roots ~/ 2,
          2 => roots ~/ 2 + 1,
          3 => roots,
          _ => random.nextInt(100),
        };
        final positions = _damage(a, errors, random);
        final b = Uint8List.fromList(a);
        // The reference has historical multi-erasure behavior, so compare
        // results AND mutations rather than claiming ideal erasure capacity.
        final count = switch (trial % 4) {
          0 => 0,
          1 => positions.isEmpty ? 0 : 1,
          2 => min(positions.length, roots),
          _ => min(positions.length, min(roots, 4)),
        };
        final erasures = positions.take(count).toList();
        final copy = List<int>.from(erasures);
        final actual = fx.ReedSolomon.decode(rs, a, erasures, count);
        final expected = fx.ReedSolomon.decode(
          rs,
          b,
          erasures,
          count,
          useNative: false,
        );
        expect(actual, expected, reason: '$roots/$trial status ($count eras)');
        expect(a, b, reason: '$roots/$trial mutation ($count eras)');
        expect(erasures, copy);
        if (errors <= roots ~/ 2 && count <= 1) {
          expect(actual, errors);
          expect(a, original);
        }
        if (actual == -1) uncorrectable++;
        expect(storage.take(2), [0xa5, 0xa5]);
        expect(storage.skip(257), [0xa5, 0xa5]);
      }
      expect(uncorrectable, greaterThan(0));
    }, skip: !nativeReedSolomonSupported);

    test('FX.25 $roots erasure validation never returns -1', () {
      for (final native in [false, true]) {
        final block = Uint8List(255);
        expect(
          () => fx.ReedSolomon.decode(rs, block, null, 1, useNative: native),
          throwsArgumentError,
        );
        expect(
          () => fx.ReedSolomon.decode(rs, block, [255], 1, useNative: native),
          throwsRangeError,
        );
        expect(
          () => fx.ReedSolomon.decode(
            rs,
            block,
            null,
            roots + 1,
            useNative: native,
          ),
          throwsRangeError,
        );
        expect(
          () => fx.ReedSolomon.decode(
            rs,
            Uint8List(254),
            null,
            0,
            useNative: native,
          ),
          throwsRangeError,
        );
      }
    });

    test('FX.25 $roots clean, duplicate and excessive erasure parity', () {
      addTearDown(() => fx.ReedSolomon.dispose(rs));
      final random = Random(roots);
      final clean = Uint8List(255);
      for (int i = 0; i < 255 - roots; i++) {
        clean[i] = random.nextInt(256);
      }
      final parity = Uint8List(roots);
      fx.ReedSolomon.encode(rs, clean, parity, useNative: false);
      clean.setRange(255 - roots, 255, parity);
      for (final erasures in [
        <int>[254],
        <int>[0, 0],
        <int>[254, 0, 73],
        List.generate(roots, (i) => 254 - i),
      ]) {
        for (final damage in [false, true]) {
          final a = Uint8List.fromList(clean);
          if (damage) _damage(a, roots + 1, random);
          final b = Uint8List.fromList(a);
          final actual = fx.ReedSolomon.decode(
            rs,
            a,
            erasures,
            erasures.length,
          );
          final expected = fx.ReedSolomon.decode(
            rs,
            b,
            erasures,
            erasures.length,
            useNative: false,
          );
          expect(actual, expected);
          expect(a, b);
          if (!damage) {
            expect(actual, 0);
            expect(a, clean);
          }
        }
      }
    }, skip: !nativeReedSolomonSupported);

    test(
      'FX.25 $roots overlapping encode retains reference mutation order',
      () {
        final a = Uint8List.fromList(List.generate(255, (i) => i));
        final b = Uint8List.fromList(a);
        Fx25Encode.encodeRs(rs, a, Uint8List.sublistView(a, 2, roots + 2));
        Fx25Encode.encodeRs(
          rs,
          b,
          Uint8List.sublistView(b, 2, roots + 2),
          useNative: false,
        );
        expect(a, b);
      },
    );
  }

  test('FX.25 cached plans track edited codec tables', () {
    final rs = Fx25.getRs(1);
    final data = Uint8List(239)..[0] = 23;
    final a = Uint8List(16);
    final b = Uint8List(16);
    fx.ReedSolomon.encode(rs, data, a);
    final saved = rs.genPoly[3];
    try {
      rs.genPoly[3] ^= 1;
      fx.ReedSolomon.encode(rs, data, a);
      fx.ReedSolomon.encode(rs, data, b, useNative: false);
      expect(a, b);
    } finally {
      rs.genPoly[3] = saved;
      fx.ReedSolomon.dispose(rs);
    }
  }, skip: !nativeReedSolomonSupported);
}
