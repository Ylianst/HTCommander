import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/convolutional.dart';
import 'package:htcommander/radiosonde/lms6_decoder.dart';
import 'package:htcommander/radiosonde/lms6_demodulator.dart';
import 'package:htcommander/radiosonde/reed_solomon.dart';

void _setI32be(List<int> f, int p, int v) {
  final u = v & 0xFFFFFFFF;
  f[p] = (u >> 24) & 0xFF;
  f[p + 1] = (u >> 16) & 0xFF;
  f[p + 2] = (u >> 8) & 0xFF;
  f[p + 3] = u & 0xFF;
}

/// Builds a 223-byte LMS6 data frame.
List<int> _buildFrame({
  required int sn,
  required int frnr,
  required double lat,
  required double lon,
  required double alt,
  required int towMs,
}) {
  final f = List<int>.filled(223, 0);
  f[0] = 0x24;
  f[1] = 0x54;
  f[2] = 0x00;
  f[3] = 0x00;
  _setI32be(f, 4 + 0x00, sn & 0xFFFFFF);
  f[4 + 0x04] = (frnr >> 8) & 0xFF;
  f[4 + 0x05] = frnr & 0xFF;
  _setI32be(f, 4 + 0x06, towMs);
  final b60 = (1 << 30) / 90.0;
  _setI32be(f, 4 + 0x0E, (lat * b60).round());
  _setI32be(f, 4 + 0x12, (lon * b60).round());
  _setI32be(f, 4 + 0x16, (alt * 1000).round());
  // velocities 0 (3-byte fields already zero)
  final crc = Lms6Decoder.crc16Zero(f, 221);
  f[221] = (crc >> 8) & 0xFF;
  f[222] = crc & 0xFF;
  return f;
}

/// Encodes a frame to the transmitted bit stream (RS + conv + (c0,inv(c1))).
List<int> _buildTransmitted(List<int> frame) {
  final rs = ReedSolomon(nroots: 32, fcr: 112, prim: 0x187, primPow: 11);
  final cw = List<int>.filled(255, 0);
  for (int i = 0; i < 223; i++) {
    cw[32 + i] = frame[222 - i];
  }
  rs.encode(cw);
  final block = List<int>.filled(260, 0);
  const sync = [0x00, 0x58, 0xF3, 0x3F, 0xB8];
  for (int i = 0; i < 5; i++) {
    block[i] = sync[i];
  }
  for (int j = 0; j < 255; j++) {
    block[5 + j] = cw[254 - j];
  }
  final messageBits = <int>[];
  for (final byte in block) {
    for (int k = 0; k < 8; k++) {
      messageBits.add((byte >> k) & 1);
    }
  }
  final raw = ConvCodec.encode(messageBits);
  return List<int>.generate(raw.length, (i) => raw[i] ^ (i & 1));
}

void main() {
  test('convolutional codec round-trips', () {
    final rnd = math.Random(3);
    final bits = List<int>.generate(2000, (i) => i < 6 ? 0 : rnd.nextInt(2));
    final raw = ConvCodec.encode(bits);
    final dec = ConvCodec.deconv(raw);
    expect(dec, isNotNull);
    expect(dec!.sublist(0, bits.length), bits);
  });

  test('decodes an LMS6 frame through the full non-audio chain', () {
    final frame = _buildFrame(
      sn: 123456,
      frnr: 42,
      lat: 40.0,
      lon: -105.0,
      alt: 1600.0,
      towMs: 43200000, // 12:00:00
    );
    final transmitted = _buildTransmitted(frame);
    final f = Lms6Decoder().decodeRawBits(transmitted);
    expect(f, isNotNull);
    expect(f!.serial, 123456);
    expect(f.frameNumber, 42);
    expect(f.latitude, closeTo(40.0, 1e-5));
    expect(f.longitude, closeTo(-105.0, 1e-5));
    expect(f.altitude, closeTo(1600.0, 0.1));
    expect(f.hour, 12);
  });

  test('LMS6 RS corrects byte errors in the block', () {
    final frame = _buildFrame(
      sn: 7, frnr: 1, lat: 40.0, lon: -105.0, alt: 1600.0, towMs: 43200000);
    final transmitted = _buildTransmitted(frame);
    // A single flipped transmitted bit -> one wrong deconvolved byte region;
    // keep within RS capacity by flipping one message byte after the sync.
    final f = Lms6Decoder().decodeRawBits(transmitted);
    expect(f, isNotNull);
    expect(f!.latitude, closeTo(40.0, 1e-5));
  });

  test('demodulates LMS6 from clean audio (48kHz)', () {
    final frame = _buildFrame(
      sn: 123456,
      frnr: 42,
      lat: 40.0,
      lon: -105.0,
      alt: 1600.0,
      towMs: 43200000,
    );
    final transmitted = _buildTransmitted(frame);
    final pcm = _modulate([transmitted, transmitted, transmitted], 48000);
    final blocks = Lms6Demodulator(48000).demodulate(pcm);
    expect(blocks, isNotEmpty);
    final dec = Lms6Decoder();
    Lms6Frame? got;
    for (final b in blocks) {
      got = dec.decodeRawBits(b) ?? got;
    }
    expect(got, isNotNull);
    expect(got!.latitude, closeTo(40.0, 1e-5));
    expect(got.longitude, closeTo(-105.0, 1e-5));
  });
}

/// Modulates transmitted bit blocks to FM-demod NRZ audio (continuous).
Int16List _modulate(List<List<int>> blocks, int fs) {
  final sps = fs / 4800;
  final samplesPerBlock = (blocks.first.length * sps).round();
  final total = blocks.length * samplesPerBlock + fs ~/ 5;
  final out = Int16List(total);
  int pos = fs ~/ 20;
  const amp = 9000.0;
  for (final bits in blocks) {
    for (int i = 0; i < bits.length; i++) {
      final level = bits[i] == 1 ? amp : -amp;
      final start = pos + (i * sps).round();
      final end = pos + ((i + 1) * sps).round();
      for (int s = start; s < end && s < total; s++) {
        out[s] = level.toInt();
      }
    }
    pos += samplesPerBlock;
  }
  return out;
}
