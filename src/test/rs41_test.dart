import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/reed_solomon.dart';
import 'package:htcommander/radiosonde/rs41_decoder.dart';
import 'package:htcommander/radiosonde/rs41_demodulator.dart';
import 'package:htcommander/radiosonde/radiosonde_monitor.dart';
import 'package:htcommander/radiosonde/radiosonde_worker.dart';

int _crc16(Uint8List d, int start, int len) {
  int rem = 0xFFFF;
  for (int i = 0; i < len; i++) {
    rem ^= d[start + i] << 8;
    for (int j = 0; j < 8; j++) {
      rem = (rem & 0x8000) != 0 ? ((rem << 1) ^ 0x1021) & 0xFFFF : (rem << 1) & 0xFFFF;
    }
  }
  return rem;
}

void _setU16(Uint8List f, int p, int v) {
  f[p] = v & 0xFF;
  f[p + 1] = (v >> 8) & 0xFF;
}

void _setU32(Uint8List f, int p, int v) {
  f[p] = v & 0xFF;
  f[p + 1] = (v >> 8) & 0xFF;
  f[p + 2] = (v >> 16) & 0xFF;
  f[p + 3] = (v >> 24) & 0xFF;
}

void _setI32(Uint8List f, int p, int v) => _setU32(f, p, v & 0xFFFFFFFF);

/// Builds a valid dewhitened 320-byte RS41 frame with the given fields.
Uint8List _buildFrame({
  required String id,
  required int frnr,
  required int battByte,
  required int week,
  required int itowMs,
  required double lat,
  required double lon,
  required double alt,
  required int numSats,
}) {
  final f = Uint8List(320);
  for (int i = 0; i < 8; i++) {
    f[i] = rs41DewhitenedHeader[i];
  }

  // FRAME block @0x39 (id 0x79, len 0x28=40).
  f[0x039] = 0x79;
  f[0x03A] = 0x28;
  _setU16(f, 0x03B, frnr);
  for (int i = 0; i < 8; i++) {
    f[0x03D + i] = id.codeUnitAt(i);
  }
  f[0x045] = battByte;
  _setU16(f, 0x039 + 2 + 0x28, _crc16(f, 0x039 + 2, 0x28));

  // GPS1 block @0x93 (id 0x7C, len 0x1E=30).
  f[0x093] = 0x7C;
  f[0x094] = 0x1E;
  _setU16(f, 0x095, week);
  _setU32(f, 0x097, itowMs);
  _setU16(f, 0x093 + 2 + 0x1E, _crc16(f, 0x093 + 2, 0x1E));

  // GPS3 block @0x112 (id 0x7B, len 0x15=21). Geodetic -> ECEF.
  const a = 6378137.0;
  const b = 6356752.31424518;
  const e2 = (a * a - b * b) / (a * a);
  final latR = lat * math.pi / 180, lonR = lon * math.pi / 180;
  final nR = a / math.sqrt(1 - e2 * math.sin(latR) * math.sin(latR));
  final x = (nR + alt) * math.cos(latR) * math.cos(lonR);
  final y = (nR + alt) * math.cos(latR) * math.sin(lonR);
  final z = (nR * (1 - e2) + alt) * math.sin(latR);
  f[0x112] = 0x7B;
  f[0x113] = 0x15;
  _setI32(f, 0x114, (x * 100).round());
  _setI32(f, 0x118, (y * 100).round());
  _setI32(f, 0x11C, (z * 100).round());
  // velocity = 0
  f[0x126] = numSats;
  _setU16(f, 0x112 + 2 + 0x15, _crc16(f, 0x112 + 2, 0x15));

  // Reed-Solomon parity over message bytes (two interleaved codewords).
  final rs = ReedSolomon(nroots: 24, fcr: 0);
  final padded = Uint8List(518)..setRange(0, 320, f);
  final cw1 = List<int>.filled(255, 0);
  final cw2 = List<int>.filled(255, 0);
  for (int i = 0; i < 231; i++) {
    cw1[24 + i] = padded[56 + 2 * i];
    cw2[24 + i] = padded[56 + 2 * i + 1];
  }
  rs.encode(cw1);
  rs.encode(cw2);
  for (int i = 0; i < 24; i++) {
    f[8 + i] = cw1[i];
    f[32 + i] = cw2[i];
  }
  return f;
}

/// Modulates a dewhitened frame to FM-demod NRZ audio (whiten + LSB-first bits).
/// RS41 frames are transmitted back-to-back (no gap), which the symbol-rate
/// recovery relies on.
Int16List _modulate(List<Uint8List> frames, int fs, {double snr = 0}) {
  final sps = fs / 4800;
  final samplesPerFrame = (320 * 8 * sps).round();
  final total = frames.length * samplesPerFrame + fs ~/ 5;
  final out = Int16List(total);
  final rnd = math.Random(7);
  int pos = fs ~/ 20; // lead-in
  const amp = 9000.0;
  double noiseAmp = 0;
  if (snr > 0) noiseAmp = amp / snr;
  for (final f in frames) {
    for (int byteIdx = 0; byteIdx < 320; byteIdx++) {
      final wire = f[byteIdx] ^ rs41Mask[byteIdx % rs41Mask.length];
      for (int bit = 0; bit < 8; bit++) {
        final level = ((wire >> bit) & 1) != 0 ? amp : -amp; // LSB-first
        final start = pos + ((byteIdx * 8 + bit) * sps).round();
        final end = pos + ((byteIdx * 8 + bit + 1) * sps).round();
        for (int s = start; s < end && s < total; s++) {
          double v = level;
          if (noiseAmp > 0) v += (rnd.nextDouble() * 2 - 1) * noiseAmp;
          out[s] = v.clamp(-32767, 32767).toInt();
        }
      }
    }
    pos += samplesPerFrame;
  }
  return out;
}

void main() {
  final frame = _buildFrame(
    id: 'P1234567',
    frnr: 1234,
    battByte: 27,
    week: 2185,
    itowMs: 43200000, // 12:00:00
    lat: 52.0,
    lon: 13.0,
    alt: 100.0,
    numSats: 9,
  );

  test('radiosonde worker orders buffered flushes and preserves source attribution', () async {
    const rate = 48000;
    final samples = _modulate([frame, frame, frame], rate);
    final pcm = Uint8List(samples.length * 2);
    final bytes = ByteData.sublistView(pcm);
    for (int i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, samples[i], Endian.little);
    }
    final errors = <Object>[];
    final worker = RadiosondeWorker(
      sampleRate: rate,
      onError: (error, _) => errors.add(error),
    );
    final reference = RadiosondeMonitor(sampleRate: rate);
    addTearDown(worker.dispose);
    addTearDown(reference.dispose);
    final actual = <RadiosondeReception>[];
    final expected = <Object>[];
    worker.onDecoded.listen(actual.add);
    reference.onDecoded.listen(expected.add);
    // Two radio runs are queued without waiting for either buffered decode.
    for (final deviceId in [101, 202]) {
      worker.processPcm16(
        pcm,
        0,
        pcm.length,
        deviceId: deviceId,
        channelName: 'sonde$deviceId',
      );
      worker.flush(deviceId);
      reference.processPcm16(pcm, 0, pcm.length);
      reference.flush();
    }
    await worker.idle.timeout(const Duration(seconds: 30));
    expect(errors, isEmpty);
    expect(actual, isNotEmpty);
    expect(actual.length, expected.length);
    final first = actual.where((event) => event.deviceId == 101).toList();
    final second = actual.where((event) => event.deviceId == 202).toList();
    expect(first, isNotEmpty);
    expect(second.length, first.length);
    expect(first.every((event) => event.channelName == 'sonde101'), isTrue);
    expect(second.every((event) => event.channelName == 'sonde202'), isTrue);
    expect(actual.take(first.length).every((event) => event.deviceId == 101), isTrue);
    for (final event in actual.where((event) => event.fix.sondeType == 'RS41')) {
      expect(event.fix.id, 'P1234567');
      expect(event.fix.frameNumber, 1234);
      expect(event.fix.latitude, closeTo(52.0, 1e-4));
      expect(event.fix.longitude, closeTo(13.0, 1e-4));
    }
  });

  test('decodes a synthesized RS41 frame end-to-end', () {
    // Frame parse directly (RS + CRC + geodetic).
    final f = Rs41Decoder().decodeFrame(frame);
    expect(f, isNotNull);
    expect(f!.id, 'P1234567');
    expect(f.frameNumber, 1234);
    expect(f.batteryVolts, closeTo(2.7, 1e-6));
    expect(f.satellites, 9);
    expect(f.latitude, closeTo(52.0, 1e-4));
    expect(f.longitude, closeTo(13.0, 1e-4));
    expect(f.altitude, closeTo(100.0, 1.0));
    expect(f.dateTimeUtc.hour, 12);
  });

  test('RS ECC recovers a frame with byte errors', () {
    final corrupted = Uint8List.fromList(frame);
    // Inject up to 12 byte errors into codeword 1 (even message bytes).
    for (int i = 0; i < 10; i++) {
      corrupted[56 + 2 * (i * 3)] ^= 0x5A;
    }
    final f = Rs41Decoder().decodeFrame(corrupted);
    expect(f, isNotNull, reason: 'RS should correct the injected errors');
    expect(f!.latitude, closeTo(52.0, 1e-4));
  });

  test('native RS41 matches Dart at both radio rates with noise and inversion', () {
    for (final rate in [32000, 48000]) {
      final pcm = _modulate([frame, frame, frame], rate, snr: 6);
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = 1000 - pcm[i];
      }
      final reference = Rs41Demodulator(rate, useNative: false).demodulate(pcm);
      expect(reference, isNotEmpty);
      expect(Rs41Demodulator(rate).demodulate(pcm), reference);
    }
  });

  test('native score blocks preserve peaks crossing block boundaries', () {
    const rate = 32000;
    final pcm = _modulate([frame, frame], rate);
    for (final headerOffset in [4094, 4095, 4096, 4097]) {
      final padding = headerOffset - rate ~/ 20;
      final shifted = Int16List(pcm.length + padding)
        ..setRange(padding, padding + pcm.length, pcm);
      final reference =
          Rs41Demodulator(rate, useNative: false).demodulate(shifted);
      expect(reference, isNotEmpty);
      expect(Rs41Demodulator(rate).demodulate(shifted), reference);
    }
  });

  test('demodulates RS41 from clean audio (48kHz)', () {
    final pcm = _modulate([frame, frame, frame, frame], 48000);
    final frames = Rs41Demodulator(48000).demodulate(pcm);
    expect(frames, isNotEmpty, reason: 'demod should recover frames');
    final dec = Rs41Decoder();
    Rs41Frame? got;
    for (final fr in frames) {
      got = dec.decodeFrame(fr) ?? got;
    }
    expect(got, isNotNull);
    expect(got!.id, 'P1234567');
    expect(got.latitude, closeTo(52.0, 1e-4));
    expect(got.longitude, closeTo(13.0, 1e-4));
  });

  test('demodulates RS41 with additive noise', () {
    final pcm = _modulate([frame, frame, frame, frame, frame], 48000, snr: 6);
    final frames = Rs41Demodulator(48000).demodulate(pcm);
    final dec = Rs41Decoder();
    Rs41Frame? got;
    for (final fr in frames) {
      got = dec.decodeFrame(fr) ?? got;
    }
    expect(got, isNotNull, reason: 'should decode at least one noisy frame');
    expect(got!.id, 'P1234567');
  });
}
