// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Run an AOT-compiled executable in separate processes for native/Dart RSS.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:htcommander/radiosonde/dfm_demodulator.dart';
import 'package:htcommander/radiosonde/imet_demodulator.dart';
import 'package:htcommander/radiosonde/lms6_demodulator.dart';
import 'package:htcommander/radiosonde/m10_demodulator.dart';
import 'package:htcommander/radiosonde/native_telemetry.dart';
import 'package:htcommander/radiosonde/rs41_demodulator.dart';
import 'package:htcommander/sarsat/sarsat_1g_decoder.dart';
import 'package:htcommander/sarsat/sarsat_1g_demodulator.dart';

void main(List<String> args) {
  if (args.length != 3 ||
      !['native', 'native-copy', 'dart'].contains(args[0]) ||
      ![
        'sonde',
        'sarsat',
        'sarsat-bch',
        'dfm',
        'rs41',
        'm10',
        'm20',
        'imet',
        'lms6',
      ].contains(args[1])) {
    throw ArgumentError(
      'Usage: benchmark_telemetry <native|native-copy|dart> '
      '<sonde|sarsat|sarsat-bch|dfm|rs41|m10|m20|imet|lms6> <mono-pcm16.wav>',
    );
  }
  final native = args[0] != 'dart';
  if (native && !nativeTelemetrySupported) {
    throw UnsupportedError(
      'Native telemetry is not available on this platform',
    );
  }
  final bytes = File(args[2]).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  int? rate;
  Int16List? samples;
  for (int p = 12; p + 8 <= bytes.length;) {
    final size = data.getUint32(p + 4, Endian.little);
    final id = String.fromCharCodes(bytes.sublist(p, p + 4));
    if (id == 'fmt ') {
      if (data.getUint16(p + 8, Endian.little) != 1 ||
          data.getUint16(p + 10, Endian.little) != 1 ||
          data.getUint16(p + 22, Endian.little) != 16) {
        throw FormatException('Expected mono PCM16 WAV');
      }
      rate = data.getUint32(p + 12, Endian.little);
    } else if (id == 'data') {
      if (rate == null) throw FormatException('Missing WAV format');
      final count = (size ~/ 2).clamp(0, rate * 6);
      samples = Int16List(count);
      for (int i = 0; i < count; i++) {
        samples[i] = data.getInt16(p + 8 + i * 2, Endian.little);
      }
      break;
    }
    p += 8 + size + (size & 1);
  }
  if (rate == null || samples == null) {
    throw FormatException('Missing WAV audio');
  }

  final dfm = DfmDemodulator(rate, useNative: native);
  final rs41 = Rs41Demodulator(rate, useNative: native);
  final m10 = M10Demodulator(rate, useNative: native);
  final m20 = M10Demodulator(
    rate,
    chipRate: 9600,
    frameBytes: 70,
    sync0: 0x45,
    sync1: 0x20,
    useNative: native,
  );
  final imet = ImetDemodulator(rate, useNative: native);
  final lms6 = Lms6Demodulator(rate, useNative: native);
  final sarsat = Sarsat1gDemodulator(rate, useNative: native);
  final bchFrames = <List<int>>[];
  if (args[1] == 'sarsat-bch') {
    final decoded = sarsat.decode(samples);
    if (decoded.isEmpty) throw StateError('Expected a valid benchmark beacon');
    final original = decoded.first.bits;
    if (original.length != 144) {
      throw StateError('BCH benchmark requires a 144-bit beacon');
    }
    for (final positions in [
      <int>[],
      [105],
      [104, 105],
      [103, 104, 105],
      [24, 41, 71, 100],
      [106, 114, 131],
    ]) {
      final bits = List<int>.from(original);
      for (final position in positions) {
        bits[position] ^= 1;
      }
      bchFrames.add(bits);
    }
  }
  final recording = args[0] == 'native'
      ? createNativeTelemetryRecording()
      : null;
  int run() {
    if (args[0] == 'native' && args[1] != 'sarsat-bch') {
      recording!.upload(samples!, rate!);
    }
    return switch (args[1]) {
      'sarsat' => sarsat.decode(samples!, recording: recording).length,
      'sarsat-bch' =>
        bchFrames
            .map(Sarsat1gDecoder.decode)
            .where((frame) => frame != null && frame.valid)
            .length,
      'dfm' => dfm.demodulate(samples!, recording: recording).length,
      'rs41' => rs41.demodulate(samples!, recording: recording).length,
      'm10' => m10.demodulate(samples!, recording: recording).length,
      'm20' => m20.demodulate(samples!, recording: recording).length,
      'imet' => imet.demodulate(samples!, recording: recording).length,
      'lms6' => lms6.demodulate(samples!, recording: recording).length,
      _ =>
        dfm.demodulate(samples!, recording: recording).length +
            rs41.demodulate(samples, recording: recording).length +
            m10.demodulate(samples, recording: recording).length +
            m20.demodulate(samples, recording: recording).length +
            imet.demodulate(samples, recording: recording).length +
            lms6.demodulate(samples, recording: recording).length,
    };
  }

  try {
    final found = run();
    final timings = <int>[];
    for (int i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      if (run() != found) throw StateError('Non-deterministic decoder output');
      timings.add(watch.elapsedMicroseconds);
    }
    timings.sort();
    stdout.writeln(
      jsonEncode({
        'backend': args[0],
        'decoder': args[1],
        'sampleRate': rate,
        'audioSeconds': samples.length / rate,
        'framesOrBytes': found,
        'medianMs': timings[1] / 1000,
        'peakRssMiB': ProcessInfo.maxRss / (1024 * 1024),
        if (bchFrames.isNotEmpty)
          'corrections': bchFrames.map((bits) {
            final frame = Sarsat1gDecoder.decode(bits)!;
            return {
              'bch1': frame.corrections1,
              'bch2': frame.corrections2,
              'hex': Sarsat1gDecoder.bitsToHex(frame.bits),
            };
          }).toList(),
      }),
    );
  } finally {
    recording?.dispose();
  }
}
