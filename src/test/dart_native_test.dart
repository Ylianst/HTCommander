// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/dart_constellation.dart';
import 'package:htcommander/hamlib/dart_fsk.dart';
import 'package:htcommander/hamlib/dart_ldpc.dart';
import 'package:htcommander/hamlib/dart_modem.dart';
import 'package:htcommander/hamlib/dart_ofdm.dart';
import 'package:htcommander/hamlib/dart_preamble.dart';
import 'package:htcommander/hamlib/native_dart_dsp.dart';

void main() {
  test(
    'reference PCM retains pre-native Windows wire fixtures for every mode',
    () {
      // Captured from the original Dart encoder before native acceleration.
      const fixtures = [
        (32176, 0xac588d44),
        (21484, 0x70aef440),
        (21484, 0x6ac4cc73),
        (17920, 0x0f5f997e),
        (16204, 0x8697641d),
        (16204, 0xf99f6bc7),
        (78916, 0xe1ece846),
      ];
      final payload = Uint8List.fromList(
        List.generate(73, (i) => (i * 41 + 17) & 255),
      );
      for (final mode in DartMode.values) {
        final pcm = DartModem(useNative: false).encode(
          payload: payload,
          mode: mode,
          source: 'N0CALL',
          destination: 'CQ',
          seqNum: 213,
        );
        int hash = 0x811c9dc5;
        for (final sample in pcm) {
          hash = ((hash ^ (sample & 255)) * 0x01000193) & 0xffffffff;
          hash = ((hash ^ ((sample >> 8) & 255)) * 0x01000193) & 0xffffffff;
        }
        expect((pcm.length, hash), fixtures[mode.index], reason: mode.name);
      }
    },
    skip: kIsWeb || !Platform.isWindows,
  );

  group('native DART parity', () {
    test(
      'SIMD PCM conversion preserves rounding, clipping and chunk edges',
      () {
        final samples = Float64List.fromList([
          0.49999999999999994,
          0.5,
          0.5000000000000001,
          -0.49999999999999994,
          -0.5,
          -0.5000000000000001,
          1.5,
          -1.5,
          32766.5,
          -32766.5,
          32767,
          -32768,
          1e300,
          -1e300,
          0,
          -0.0,
          7.5,
        ]);
        final out = Int16List(samples.length);
        nativeDartToPcm(samples, 1, out);
        expect(out, [
          for (final sample in samples) sample.round().clamp(-32767, 32767),
        ]);
        expect(
          () => nativeDartToPcm(
            Float64List.fromList([0, double.nan]),
            1,
            Int16List(2),
          ),
          throwsArgumentError,
        );
        expect(
          () => nativeDartToPcm(
            Float64List.fromList([double.infinity]),
            1,
            Int16List(1),
          ),
          throwsArgumentError,
        );
        final random = math.Random(119);
        final parts = [
          Float64List.fromList(
            List.generate(4095, (_) => random.nextDouble() * 4 - 2),
          ),
          Float64List(0),
          Float64List.fromList(
            List.generate(8193, (_) => random.nextDouble() * 4 - 2),
          ),
        ];
        for (final amplitude in [0.0, 0.8, 1.5, -0.8]) {
          expect(
            DartOfdm.toPcm(parts, amplitude: amplitude),
            DartOfdm.toPcm(parts, amplitude: amplitude, useNative: false),
          );
        }
        final allPcm = Int16List.fromList(
          List.generate(65536, (i) => i - 32768),
        );
        final slice = Int16List.sublistView(allPcm, 1, allPcm.length - 2);
        expect(
          DartOfdm.fromPcm(slice),
          DartOfdm.fromPcm(slice, useNative: false),
        );
      },
    );

    test('LDPC all rates, noisy blocks and iteration exhaustion', () {
      final random = math.Random(473);
      for (final rate in LdpcRate.values) {
        final code = DartLdpc.getCode(rate);
        final info = Uint8List.fromList(
          List.generate(code.k, (_) => random.nextInt(2)),
        );
        final encoded = DartLdpc.encode(code, info);
        expect(encoded, DartLdpc.encode(code, info, useNative: false));
        for (int scenario = 0; scenario < 3; scenario++) {
          final llr = Float64List.fromList([
            for (final bit in encoded)
              scenario == 2
                  ? random.nextDouble() * 4 - 2
                  : (bit == 0 ? 6.0 : -6.0) + random.nextDouble() - 0.5,
          ]);
          if (scenario == 1) {
            for (int i = 0; i < 5; i++) {
              llr[i * 67] *= -0.3;
            }
          }
          final nativeCorrections = Int32List.fromList([7]);
          final dartCorrections = Int32List.fromList([7]);
          final actual = DartLdpc.decode(code, llr, corrOut: nativeCorrections);
          final expected = DartLdpc.decode(
            code,
            llr,
            corrOut: dartCorrections,
            useNative: false,
          );
          expect(actual, expected, reason: '$rate scenario $scenario');
          expect(nativeCorrections, dartCorrections);
          if (scenario < 2) expect(actual, info);
        }
        // A subsequent call must neither retain messages nor mutate old output.
        expect(DartLdpc.encode(code, Uint8List(code.k)), everyElement(0));
        expect(encoded, DartLdpc.encode(code, info, useNative: false));
      }
    });

    test('shared SIMD FFT normalization and arbitrary-size DFT spreading', () {
      final random = math.Random(109);
      for (final n in [2, 16, 128, 256, 2048]) {
        final input = List.generate(
          n,
          (_) => Complex(random.nextDouble() - 0.5, random.nextDouble() - 0.5),
        );
        for (final inverse in [false, true]) {
          final actual = DartOfdm.fftPublic(input, inverse: inverse);
          final expected = DartOfdm.fftPublic(
            input,
            inverse: inverse,
            useNative: false,
          );
          _expectComplexClose(actual, expected);
        }
        _expectComplexClose(
          DartOfdm.fftPublic(
            DartOfdm.fftPublic(input, inverse: false),
            inverse: true,
          ),
          input,
        );
      }
      final params = DartOfdmParams();
      final native = DartOfdm(params);
      final reference = DartOfdm(params, useNative: false);
      for (final n in [1, 9, 17, 128, 129]) {
        final input = List.generate(
          n,
          (_) => Complex(random.nextDouble() - 0.5, random.nextDouble() - 0.5),
        );
        for (final inverse in [false, true]) {
          _expectComplexClose(
            native.dftSpread(input, inverse: inverse),
            reference.dftSpread(input, inverse: inverse),
          );
        }
      }
    });

    test('OFDM uses owned results and preserves equalization edge cases', () {
      final random = math.Random(901);
      for (final params in [
        DartOfdmParams(),
        DartOfdmParams(fftSize: 64, cpLength: 16),
        DartOfdmParams(fftSize: 256, cpLength: 0),
      ]) {
        final native = DartOfdm(params);
        final reference = DartOfdm(params, useNative: false);
        final symbols = List.generate(
          params.numDataCarriers,
          (_) => Complex(random.nextDouble(), random.nextDouble()),
        );
        final channel = List.generate(
          params.numDataCarriers,
          (i) => i < 2 ? Complex(i * 1e-8, 0) : Complex(0.7, i * 0.1),
        );
        for (final spread in [false, true]) {
          final samples = native.modulateSymbol(symbols, dftSpread: spread);
          final saved = Float64List.fromList(samples);
          _expectRealClose(
            samples,
            reference.modulateSymbol(symbols, dftSpread: spread),
          );
          for (final noise in [0.0, 0.07, double.nan]) {
            final actual = native.demodulateSymbol(
              samples,
              channel,
              dftSpread: spread,
              noiseVar: noise,
            );
            final savedSymbols = List<Complex>.of(actual);
            _expectComplexClose(
              actual,
              reference.demodulateSymbol(
                samples,
                channel,
                dftSpread: spread,
                noiseVar: noise,
              ),
            );
            native.modulateSymbol(symbols);
            _expectComplexClose(actual, savedSymbols);
          }
          _expectComplexClose(
            native.demodulateSymbolRaw(samples),
            reference.demodulateSymbolRaw(samples),
          );
          final shortReference = symbols.take(symbols.length - 1).toList();
          _expectComplexClose(
            native.estimateChannel(samples, shortReference),
            reference.estimateChannel(samples, shortReference),
          );
          expect(samples, saved);
        }
      }
    });

    test('correlation preserves FIFO lobes and search boundaries', () {
      final params = DartOfdmParams();
      final native = DartPreamble(ofdmParams: params);
      final reference = DartPreamble(ofdmParams: params, useNative: false);
      final preamble = reference.generate();
      final samples = Float64List(2 * preamble.length + 500);
      samples.setAll(63, preamble.map((v) => -v * 0.8));
      samples.setAll(preamble.length + 200, preamble);
      for (final start in [
        -1,
        0,
        62,
        63,
        64,
        preamble.length,
        samples.length,
      ]) {
        final actual = native.detectDetailed(samples, searchStart: start);
        final expected = reference.detectDetailed(samples, searchStart: start);
        expect(actual.position, expected.position, reason: 'start $start');
        expect(actual.correlation, closeTo(expected.correlation, 1e-12));
      }
      expect(native.detect(samples), 63);
      expect(native.detect(Float64List(native.preambleSamples - 1)), -1);
      expect(native.detect(Float64List(32000)), -1);
      final exact = Float64List.fromList(preamble);
      expect(native.detect(exact), 0);
      final random = math.Random(8);
      final noise = Float64List.fromList(
        List.generate(5000, (_) => random.nextDouble() - 0.5),
      );
      expect(native.detect(noise), reference.detect(noise));
    });

    test(
      'SIMD spectrum correlation matches direct normalized dot products',
      () {
        final random = math.Random(61);
        for (final length in [7, 256, 512]) {
          final reference = Float64List.fromList(
            List.generate(length, (_) => random.nextDouble() - 0.5),
          );
          final plan = NativeDartCorrelation.create(reference);
          // The reused FFT can be disabled independently of DART kernels.
          if (plan == null) continue;
          final samples = Float64List.fromList(
            List.generate(
              2 * plan.capacity + length,
              (_) => random.nextDouble() - 0.5,
            ),
          );
          double refEnergy = 0;
          for (final value in reference) {
            refEnergy += value * value;
          }
          for (final start in [0, plan.capacity - 1]) {
            final actual = plan.process(samples, start, plan.capacity);
            for (int p = 0; p < plan.capacity; p++) {
              double dot = 0, energy = 0;
              for (int i = 0; i < length; i++) {
                final sample = samples[start + p + i];
                dot += sample * reference[i];
                energy += sample * sample;
              }
              expect(
                actual[p],
                closeTo(dot.abs() / math.sqrt(energy * refEnergy), 1e-10),
              );
            }
          }
        }
      },
    );

    test('custom preamble lengths preserve direct-kernel fallbacks', () {
      for (final length in [7, 513, 2053]) {
        final params = DartOfdmParams();
        final native = DartPreamble(ofdmParams: params, zcLength: length);
        final reference = DartPreamble(
          ofdmParams: params,
          zcLength: length,
          useNative: false,
        );
        final samples = Float64List(native.preambleSamples + 130);
        samples.setAll(65, reference.generate());
        final actual = native.detectDetailed(samples, threshold: 0.99);
        final expected = reference.detectDetailed(samples, threshold: 0.99);
        expect(actual.position, expected.position);
        expect(actual.correlation, closeTo(expected.correlation, 1e-12));
      }
    });

    test('Mode F odd bits, partial symbols, soft output and SNR', () {
      final random = math.Random(83);
      for (final params in [
        DartFskParams(),
        DartFskParams(sampleRate: 48000, symbolRate: 100),
      ]) {
        final native = DartFsk(params);
        final reference = DartFsk(params, useNative: false);
        for (final count in [0, 1, 127, 648]) {
          final bits = Uint8List.fromList(
            List.generate(count, (_) => random.nextInt(2)),
          );
          final actual = native.modulate(bits);
          final expected = reference.modulate(bits);
          _expectRealClose(actual, expected);
          expect(native.demodulate(actual, 0, count), bits);
          for (int i = 0; i < actual.length; i++) {
            actual[i] += (random.nextDouble() - 0.5) * 0.1;
          }
          _expectRealClose(
            native.demodulateSoft(actual, 0, count),
            reference.demodulateSoft(actual, 0, count),
          );
          expect(
            native.estimateSnrDb(actual, 0, (count + 1) ~/ 2),
            closeTo(
              reference.estimateSnrDb(actual, 0, (count + 1) ~/ 2),
              1e-10,
            ),
          );
          final partial = Float64List.sublistView(
            actual,
            0,
            actual.length ~/ 2,
          );
          _expectRealClose(
            native.demodulateSoft(partial, 0, count),
            reference.demodulateSoft(partial, 0, count),
          );
        }
      }
    });

    test('custom OFDM parameters without payload pilots', () {
      final params = DartOfdmParams(fftSize: 256, cpLength: 16);
      final native = DartModem(params: params, pilotsEnabled: false);
      final reference = DartModem(
        params: params,
        pilotsEnabled: false,
        useNative: false,
      );
      final payload = Uint8List.fromList(List.generate(91, (i) => i));
      final nativePcm = native.encode(payload: payload, mode: DartMode.mode2);
      final dartPcm = reference.encode(payload: payload, mode: DartMode.mode2);
      expect(native.decode(dartPcm)?.payload, payload);
      expect(reference.decode(nativePcm)?.payload, payload);
    });

    test('batched Mode F quality reuses energies across partial chunks', () {
      final random = math.Random(715);
      final samples = Float64List.fromList(
        List.generate(6601, (_) => random.nextDouble() - 0.5),
      );
      for (final params in [
        DartFskParams(),
        DartFskParams(symbolRate: 1032),
        DartFskParams(symbolRate: 32000),
      ]) {
        final native = DartFsk(params);
        final reference = DartFsk(params, useNative: false);
        for (final start in [0, 17, samples.length - 1, samples.length + 4]) {
          final expectedSnr = reference.estimateSnrDb(samples, start, 4101);
          for (final decoder in [native, reference]) {
            final quality = Float64List(1);
            final actual = decoder.demodulateSoft(
              samples,
              start,
              8201,
              snrOut: quality,
            );
            _expectRealClose(
              actual,
              reference.demodulateSoft(samples, start, 8201),
            );
            expect(quality[0], closeTo(expectedSnr, 1e-10));
            decoder.demodulateSoft(Float64List(0), 0, 3, snrOut: quality);
            expect(quality[0], 0);
          }
        }
      }
    });

    for (final mode in DartMode.values) {
      test('$mode PCM compatibility and bidirectional interoperability', () {
        final native = DartModem();
        final reference = DartModem(useNative: false);
        for (final length in [0, 73, 257]) {
          final payload = Uint8List.fromList(
            List.generate(length, (i) => (i * 41 + 17) & 255),
          );
          final actual = native.encode(
            payload: payload,
            mode: mode,
            source: 'N0CALL',
            destination: 'CQ',
            seqNum: 213,
          );
          final expected = reference.encode(
            payload: payload,
            mode: mode,
            source: 'N0CALL',
            destination: 'CQ',
            seqNum: 213,
          );
          expect(actual.length, expected.length);
          for (int i = 0; i < actual.length; i++) {
            expect((actual[i] - expected[i]).abs(), lessThanOrEqualTo(1));
          }
          final nativeRx = native.decode(expected);
          final dartRx = reference.decode(actual);
          expect(nativeRx, isNotNull);
          expect(dartRx, isNotNull);
          expect(nativeRx!.payload, payload);
          expect(dartRx!.payload, payload);
          expect(nativeRx.header.seqNum, 213);
          expect(nativeRx.header.source, dartRx.header.source);
          expect(nativeRx.header.destination, dartRx.header.destination);
          // Both decoders must also agree after small deterministic audio noise.
          for (int i = 0; i < actual.length; i++) {
            actual[i] = actual[i] + (i * 13 % 41) - 20;
          }
          final noisyNative = native.decode(actual);
          final noisyDart = reference.decode(actual);
          expect(noisyNative?.payload, noisyDart?.payload);
          expect(noisyNative?.payload, payload);
        }
      });
    }
  }, skip: !nativeDartDspEnabled);
}

void _expectComplexClose(List<Complex> actual, List<Complex> expected) {
  expect(actual.length, expected.length);
  for (int i = 0; i < actual.length; i++) {
    expect(actual[i].i, closeTo(expected[i].i, 1e-10));
    expect(actual[i].q, closeTo(expected[i].q, 1e-10));
  }
}

void _expectRealClose(List<double> actual, List<double> expected) {
  expect(actual.length, expected.length);
  for (int i = 0; i < actual.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-10));
  }
}
