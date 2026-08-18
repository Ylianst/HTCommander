import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/m10_demodulator.dart';
import 'package:htcommander/radiosonde/m20_decoder.dart';

int _checkM10(Uint8List msg, int len) {
  int update(int c, int b) {
    final c1 = c & 0xFF;
    b = ((b >> 1) | ((b & 1) << 7)) & 0xFF;
    b ^= (b >> 2) & 0xFF;
    final t6 = (c & 1) ^ ((c >> 2) & 1) ^ ((c >> 4) & 1);
    final t7 = ((c >> 1) & 1) ^ ((c >> 3) & 1) ^ ((c >> 5) & 1);
    final t = (c & 0x3F) | (t6 << 6) | (t7 << 7);
    int s = (c >> 7) & 0xFF;
    s ^= (s >> 2) & 0xFF;
    return ((c1 << 8) | ((b ^ t ^ s) & 0xFF)) & 0xFFFF;
  }

  int c = 0;
  for (int i = 0; i < len; i++) {
    c = update(c, msg[i]);
  }
  return c & 0xFFFF;
}

void _setI32be(Uint8List f, int p, int v) {
  final u = v & 0xFFFFFFFF;
  f[p] = (u >> 24) & 0xFF;
  f[p + 1] = (u >> 16) & 0xFF;
  f[p + 2] = (u >> 8) & 0xFF;
  f[p + 3] = u & 0xFF;
}

void _setU24be(Uint8List f, int p, int v) {
  f[p] = (v >> 16) & 0xFF;
  f[p + 1] = (v >> 8) & 0xFF;
  f[p + 2] = v & 0xFF;
}

void _setI16be(Uint8List f, int p, int v) {
  final u = v & 0xFFFF;
  f[p] = (u >> 8) & 0xFF;
  f[p + 1] = u & 0xFF;
}

Uint8List _buildM20({
  required double lat,
  required double lon,
  required double alt,
  required int week,
  required int gpssec,
}) {
  final f = Uint8List(70);
  f[0] = 0x45;
  f[1] = 0x20;
  _setI32be(f, 0x1C, (lat * 1e6).round());
  _setI32be(f, 0x20, (lon * 1e6).round());
  _setU24be(f, 0x08, (alt * 100).round());
  _setU24be(f, 0x0F, gpssec);
  _setI16be(f, 0x1A, week);
  _setI16be(f, 0x0B, 0); // vE
  _setI16be(f, 0x0D, 0); // vN
  _setI16be(f, 0x18, 0); // vU
  f[0x12] = 0x40; // SN bytes
  f[0x13] = 0x02;
  f[0x14] = 0x01;
  final cs = _checkM10(f, 0x44);
  f[0x44] = (cs >> 8) & 0xFF;
  f[0x45] = cs & 0xFF;
  return f;
}

Int16List _modulate(List<Uint8List> frames, int fs) {
  const chipRate = 9600;
  final sps = fs / chipRate;
  final chipsPerFrame = 70 * 8 * 2;
  final samplesPerFrame = (chipsPerFrame * sps).round();
  final total = frames.length * samplesPerFrame + fs ~/ 5;
  final out = Int16List(total);
  int pos = fs ~/ 20;
  const amp = 9000.0;
  for (final f in frames) {
    final bits = <int>[];
    for (final byte in f) {
      for (int k = 7; k >= 0; k--) {
        bits.add((byte >> k) & 1);
      }
    }
    int prev = 0;
    final raw = <int>[];
    for (final b in bits) {
      final r = b == 1 ? prev : 1 - prev;
      prev = r;
      raw.add(r);
    }
    final chips = <double>[];
    for (final r in raw) {
      if (r == 1) {
        chips
          ..add(-amp)
          ..add(amp);
      } else {
        chips
          ..add(amp)
          ..add(-amp);
      }
    }
    for (int j = 0; j < chips.length; j++) {
      final start = pos + (j * sps).round();
      final end = pos + ((j + 1) * sps).round();
      for (int s = start; s < end && s < total; s++) {
        out[s] = chips[j].toInt();
      }
    }
    pos += samplesPerFrame;
  }
  return out;
}

M10Demodulator _m20Demod(int fs) =>
    M10Demodulator(fs, chipRate: 9600, frameBytes: 70, sync0: 0x45, sync1: 0x20);

void main() {
  final frame = _buildM20(
    lat: 48.5,
    lon: 2.3,
    alt: 1500.0,
    week: 2185,
    gpssec: 43200,
  );

  test('parses a synthesized M20 frame', () {
    final f = M20Decoder().decodeFrame(frame);
    expect(f, isNotNull);
    expect(f!.latitude, closeTo(48.5, 1e-5));
    expect(f.longitude, closeTo(2.3, 1e-5));
    expect(f.altitude, closeTo(1500.0, 0.1));
    expect(f.dateTimeUtc.hour, 12);
  });

  test('rejects a frame with a corrupted checksum', () {
    final bad = Uint8List.fromList(frame);
    bad[0x1C] ^= 0xFF;
    expect(M20Decoder().decodeFrame(bad), isNull);
  });

  test('demodulates M20 from clean audio (48kHz)', () {
    final pcm = _modulate([frame, frame, frame, frame], 48000);
    final frames = _m20Demod(48000).demodulate(pcm);
    expect(frames, isNotEmpty);
    final dec = M20Decoder();
    M20Frame? got;
    for (final fr in frames) {
      got = dec.decodeFrame(fr) ?? got;
    }
    expect(got, isNotNull);
    expect(got!.latitude, closeTo(48.5, 1e-5));
    expect(got.longitude, closeTo(2.3, 1e-5));
  });
}
