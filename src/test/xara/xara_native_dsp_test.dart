// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/complex.dart';
import 'package:htcommander/hamlib/xara/dsp.dart';
import 'package:htcommander/hamlib/xara/fec.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_rx_frontend.dart';
import 'package:htcommander/hamlib/xara/native_dsp.dart';
import 'package:htcommander/hamlib/xara/resample.dart';
import 'package:htcommander/hamlib/xara/turbo_decoder.dart';

import 'xara_test_rng.dart';

Matcher _samplesCloseTo(Iterable<double> expected) =>
    pairwiseCompare<double, double>(
      expected,
      (a, b) => (a - b).abs() <= 4e-15,
      'samples within 4e-15',
    );

void main() {
  group(
    'native XARA numerical parity',
    () {
      test('FFT matches Dart in both directions, including offset views', () {
        final rng = TestRng(37);
        for (final n in [1, 2, 8, 128, 1024, 2048, 4096]) {
          final native = Fft(n), dart = Fft(n, useNative: false);
          final re = Float64List.fromList(
            List.generate(n + 4, (_) => rng.gauss()),
          );
          final im = Float64List.fromList(
            List.generate(n + 4, (_) => rng.gauss()),
          );
          final wantRe = Float64List.fromList(re),
              wantIm = Float64List.fromList(im);
          for (final inverse in [false, true]) {
            native.transform(
              Float64List.sublistView(re, 1, n + 1),
              Float64List.sublistView(im, 2, n + 2),
              inverse: inverse,
            );
            dart.transform(
              Float64List.sublistView(wantRe, 1, n + 1),
              Float64List.sublistView(wantIm, 2, n + 2),
              inverse: inverse,
            );
            expect(re, orderedEquals(wantRe));
            expect(im, orderedEquals(wantIm));
          }
        }
      });

      test('direct FFT preserves copy-back behavior for overlapping views', () {
        final rng = TestRng(44);
        for (final n in [1, 2, 128, 2048, 4096]) {
          for (final offset in [0, 1, n - 1]) {
            for (final inverse in [false, true]) {
              final input = Float64List.fromList(
                List.generate(n + offset + 2, (_) => rng.gauss()),
              );
              final want = Float64List.fromList(input);
              final re = Float64List.fromList(input.sublist(1, n + 1));
              final im = Float64List.fromList(
                input.sublist(offset + 1, offset + n + 1),
              );
              Fft(n, useNative: false).transform(re, im, inverse: inverse);
              want
                ..setRange(1, n + 1, re)
                ..setRange(offset + 1, offset + n + 1, im);
              Fft(n).transform(
                Float64List.sublistView(input, 1, n + 1),
                Float64List.sublistView(input, offset + 1, offset + n + 1),
                inverse: inverse,
              );
              expect(input, orderedEquals(want));
            }
          }
        }
      });

      test(
        'FIR preserves sample indices through empty chunks and history trims',
        () {
          final native = FrontEnd(), dart = FrontEnd(useNative: false);
          final rng = TestRng(38);
          for (int i = 0; i < 80; i++) {
            final n = [0, 1, 7, 479, 480, 1200][i % 6];
            final x = List.generate(n, (_) => rng.gauss());
            final (a, got) = native.process(x);
            final (b, want) = dart.process(x);
            expect(a, b);
            expect(got, _samplesCloseTo(want));
          }
        },
      );

      test('resampler preserves streaming phase, flush and output count', () {
        final rng = TestRng(39);
        for (final rates in [
          (32000.0, 48000.0),
          (48000.0, 32000.0),
          (44100.0, 48000.0),
          (96000.0, 48000.0),
          (12000.0, 48000.0),
        ]) {
          final native = Resampler(rates.$1, rates.$2);
          final dart = Resampler(rates.$1, rates.$2, useNative: false);
          for (int i = 0; i < 24; i++) {
            final n = [0, 1, 7, 320, 1000, 480][i % 6];
            final x = List.generate(n, (_) => rng.gauss());
            expect(native.process(x), _samplesCloseTo(dart.process(x)));
          }
          expect(native.flush(), _samplesCloseTo(dart.flush()));
        }
      });

      test(
        'STFT keeps one bounded history and preserves Dart pruning on gaps',
        () {
          final native = Stft(3), dart = Stft(3, useNative: false);
          final buffer = SampleTrack(2048, stride: 2);
          final rng = TestRng(42);
          final retained = native.retainedDifferenceBytes;
          final spectra = native.retainedSpectrumBytes;
          for (int i = 0; i < 80; i++) {
            final start = i == 45 ? buffer.end + 4000 : buffer.end;
            final samples = Float64List.fromList(
              List.generate(2 * [0, 7, 73, 300][i % 4], (_) => rng.gauss()),
            );
            buffer.append(start, samples);
            native.update(buffer);
            dart.update(buffer);
            expect(native.diffBase, dart.diffBase);
            expect(native.diffEnd, dart.diffEnd);
            expect(native.retainedDifferenceBytes, retained);
            expect(native.retainedSpectrumBytes, spectra);
          }
          expect(native.diffBase, greaterThan(0));
          expect(
            native.retainedDifferenceBytes,
            native.nativeRows!.storageBytes,
          );
          expect(
            spectra,
            lessThanOrEqualTo(2 * sym * 2 * nf * Float32List.bytesPerElement),
          );
        },
      );

      test(
        'fused spectrum insertion preserves float32 rounding and normalization',
        () {
          const capacity = 7, width = 16;
          const origin = 0x100000000;
          final native = createNativeRows(capacity, width)!;
          final reference = createNativeRows(capacity, width)!;
          final rng = TestRng(43);
          final pattern = createNativePattern(
            Int32List(width ~/ 2),
            Int32List.fromList(List.generate(width ~/ 2, (i) => 2 * i)),
            Float64List.fromList([
              for (int i = 0; i < width ~/ 2; i++) ...[1.0, 0.0],
            ]),
            width ~/ 2,
          )!;
          Float32List? previous;
          for (int j = 0; j < 50; j++) {
            if (j == 23) previous = null;
            final scale = [0.0, 1.0, 1e-35, 1e30, 1e-300][j % 5];
            final re = Float64List.fromList(
              List.generate(width ~/ 2, (_) => rng.gauss() * scale),
            );
            final im = Float64List.fromList(
              List.generate(width ~/ 2, (_) => rng.gauss() * scale),
            );
            if (j == 31) re[0] = double.infinity;
            if (j == 32) im[1] = double.nan;
            final want = Float32List(width);
            final diff = Float32List(width);
            for (int k = 0; k < width ~/ 2; k++) {
              want[2 * k] = re[k];
              want[2 * k + 1] = im[k];
              if (previous != null) {
                final ar = want[2 * k], ai = want[2 * k + 1];
                final br = previous[2 * k], bi = previous[2 * k + 1];
                final pr = ar * br + ai * bi, pi = ai * br - ar * bi;
                final norm = hypot(pr, pi) + 1e-30;
                diff[2 * k] = pr / norm;
                diff[2 * k + 1] = pi / norm;
              }
            }
            final row = Float32List(width);
            native.appendSpectrum(origin + j, re, im, row, previous);
            reference.append(origin + j, diff);
            expect(
              row,
              pairwiseCompare<double, double>(
                want,
                (a, b) => a == b || (a.isNaN && b.isNaN),
                'identical rounded spectra',
              ),
            );
            expect(
              pattern.terms(
                native,
                origin + math.max(0, j - capacity + 1),
                origin + j,
              ),
              pairwiseCompare<double, double>(
                pattern.terms(
                  reference,
                  origin + math.max(0, j - capacity + 1),
                  origin + j,
                ),
                (a, b) => a == b || (a.isNaN && b.isNaN),
                'identical correlation metrics',
              ),
            );
            previous = want;
          }
          expect(
            () => native.appendSpectrum(
              0,
              Float64List(7),
              Float64List(8),
              Float32List(width),
              null,
            ),
            throwsArgumentError,
          );
          final oversized = createNativeRows(2, 258)!;
          expect(
            () => oversized.appendSpectrum(
              0,
              Float64List(129),
              Float64List(129),
              Float32List(258),
              null,
            ),
            throwsArgumentError,
          );
        },
      );

      test(
        'batched correlation matches Dart across ring wrap and large indices',
        () {
          const capacity = 41, width = 16;
          final rows = createNativeRows(capacity, width)!;
          final rng = TestRng(40);
          final history = List.generate(
            100,
            (_) => Float32List.fromList(
              List.generate(width, (_) => rng.uniform() - 0.5),
            ),
          );
          // Absolute indices must not be narrowed to the native API's int32.
          const origin = 0x100000000;
          for (int i = 0; i < history.length; i++) {
            rows.append(origin + i, history[i]);
          }
          final offsets = Int32List.fromList([0, 3, 7, 5]);
          final bins = Int32List.fromList([0, 2, 14, 6]);
          final refs = Float64List.fromList(
            List.generate(8, (_) => rng.uniform()),
          );
          for (final markers in [2, 4]) {
            final pattern = createNativePattern(offsets, bins, refs, markers)!;
            final got = pattern.terms(rows, origin + 61, origin + 89);
            final want = <double>[];
            for (int j = 61; j <= 89; j++) {
              double ar = 0, ai = 0, br = 0, bi = 0;
              for (int c = 0; c < offsets.length; c++) {
                final row = history[j + offsets[c]];
                double dr = row[bins[c]], di = row[bins[c] + 1];
                if (c >= markers) {
                  final sr = dr * dr - di * di, si = 2 * dr * di;
                  dr = sr * sr - si * si;
                  di = 2 * sr * si;
                }
                final rr = refs[2 * c], ri = refs[2 * c + 1];
                if (c < markers) {
                  ar += dr * rr - di * ri;
                  ai += dr * ri + di * rr;
                } else {
                  br += dr * rr - di * ri;
                  bi += dr * ri + di * rr;
                }
              }
              want.add((ar * ar + ai * ai) / markers);
              want.add(
                markers == offsets.length
                    ? 0
                    : (br * br + bi * bi) / (offsets.length - markers),
              );
            }
            expect(got, orderedEquals(want));
            for (final threshold in [0.0, want[0], double.infinity]) {
              final gated = pattern.terms(rows, origin + 61, origin + 89, threshold);
              final expected = <double>[
                for (int i = 0; i < want.length; i += 2) ...[
                  want[i],
                  want[i] >= threshold ? want[i + 1] : 0.0,
                ],
              ];
              expect(gated, orderedEquals(expected));
            }
            expect(
              () => pattern.terms(rows, origin, origin + 1),
              throwsArgumentError,
            );
            expect(
              () => pattern.terms(rows, origin + 95, origin + 99),
              throwsArgumentError,
            );
          }
        },
      );

      test('marker gating preserves threshold equality and rejects NaN without affecting adjacent lanes', () {
        const capacity = 7, origin = 0x100000000;
        final rows = createNativeRows(capacity, 4)!;
        final markers = [double.nan, 0.0, 1.0, 2.0, 3.0, 0.0, 1.0];
        for (int i = 0; i < markers.length; i++) {
          rows.append(origin + i, Float32List.fromList([markers[i], 0.0, 0.1, 0.2]));
        }
        final pattern = createNativePattern(
          Int32List.fromList([0, 0]),
          Int32List.fromList([0, 2]),
          Float64List.fromList([1.0, 0.0, 1.0, 0.0]),
          1,
        )!;
        final full = pattern.terms(rows, origin, origin + 6);
        final gated = pattern.terms(rows, origin, origin + 6, 1.0);
        expect(full[0].isNaN, isTrue);
        expect(full[1], greaterThan(0.0), reason: 'unrestricted metrics remain available for NaN markers');
        for (int i = 0; i < markers.length; i++) {
          final chi = full[2 * i];
          if (chi.isNaN) {
            expect(gated[2 * i].isNaN, isTrue);
          } else {
            expect(gated[2 * i], chi);
          }
          expect(gated[2 * i + 1], chi >= 1.0 ? full[2 * i + 1] : 0.0);
        }
      });

      test(
        'turbo bits and CRC iteration counts match Dart across window boundaries',
        () {
          final rng = TestRng(41);
          for (final k in [24, 1021, 1022, 4096, 4100, 8192]) {
            final perm = List.generate(k, (i) => i)..shuffle(math.Random(k));
            final white = List.generate(k ~/ 2, (i) => i & 1);
            final frame = randomFrame(rng, k ~/ 8);
            final info = Uint8List.fromList(
              List.generate(k, (i) {
                final bit = i < 8 * frame.length
                    ? (frame[i ~/ 8] >> (7 - i % 8)) & 1
                    : 0;
                return bit ^ (i < white.length ? white[i] : 0);
              }),
            );
            for (final amplitude in [0.0, 3.0]) {
              final code = turboEncode(info, perm, 4, puncturedLen(k, 4));
              final llr = code
                  .map((b) => (1 - 2 * b) * amplitude + rng.gauss())
                  .toList();
              final sp = split(llr, perm, 4);
              for (final minIters in [null, 0, 2]) {
                final early = minIters == null
                    ? null
                    : (minIters, CrcCheck(white, frame.length));
                final got = const TurboDecoder().decode(
                  sp,
                  perm,
                  6,
                  0.7,
                  early,
                );
                final want = const TurboDecoder(
                  useNative: false,
                ).decode(sp, perm, 6, 0.7, early);
                expect(
                  got.bits,
                  want.bits,
                  reason: 'k=$k amp=$amplitude early=$minIters',
                );
                expect(
                  got.iterations,
                  want.iterations,
                  reason: 'k=$k amp=$amplitude early=$minIters',
                );
              }
            }
          }
        },
      );

      test('invalid turbo permutations cannot address native memory', () {
        final sp = Split(
          Float64List(7),
          Float64List(7),
          Float64List(7),
          Float64List(7),
        );
        for (final perm in [
          [0, 1, 2, 4],
          [0, 1, 2, -1],
          [0, 1, 2, 0x100000003],
        ]) {
          expect(
            () => const TurboDecoder().decode(sp, perm, 2, 0.7, null),
            throwsRangeError,
          );
        }
        expect(
          () => const TurboDecoder().decode(sp, [0, 0, 2, 3], 2, 0.7, null),
          throwsStateError,
        );
      });
    },
    skip: !nativeDspEnabled
        ? 'Native XARA is not enabled on this target'
        : false,
  );
}
