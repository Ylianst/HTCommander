import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/m10_decoder.dart';
import 'package:htcommander/radiosonde/m10_demodulator.dart';

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

void _setU32be(Uint8List f, int p, int v) => _setI32be(f, p, v);

void _setI16be(Uint8List f, int p, int v) {
  final u = v & 0xFFFF;
  f[p] = (u >> 8) & 0xFF;
  f[p + 1] = u & 0xFF;
}

Uint8List _buildM10({
  required double lat,
  required double lon,
  required double alt,
  required int week,
  required int towMs,
  required int sats,
}) {
  final f = Uint8List(101);
  f[0] = 0x64;
  f[1] = 0x9F;
  final b60 = (1 << 30) / 90.0;
  _setI32be(f, 0x0E, (lat * b60).round());
  _setI32be(f, 0x12, (lon * b60).round());
  _setI32be(f, 0x16, (alt * 1000).round());
  _setU32be(f, 0x0A, towMs);
  _setI16be(f, 0x20, week);
  f[0x1E] = sats;
  f[0x1F] = 18;
  _setI16be(f, 0x04, 0); // vE
  _setI16be(f, 0x06, 0); // vN
  _setI16be(f, 0x08, 0); // vU
  // SN bytes (arbitrary).
  for (int i = 0; i < 5; i++) {
    f[0x5D + i] = 0x11 + i;
  }
  final cs = _checkM10(f, 0x63);
  f[0x63] = (cs >> 8) & 0xFF;
  f[0x64] = cs & 0xFF;
  return f;
}

/// Modulates M10 frames to FM-demod audio (MSB-first bits -> differential
/// encode -> Manchester chips), continuous (no gap).
Int16List _modulate(List<Uint8List> frames, int fs) {
  const chipRate = 9615;
  final sps = fs / chipRate;
  final chipsPerFrame = 101 * 8 * 2;
  final samplesPerFrame = (chipsPerFrame * sps).round();
  final total = frames.length * samplesPerFrame + fs ~/ 5;
  final out = Int16List(total);
  int pos = fs ~/ 20;
  const amp = 9000.0;
  for (final f in frames) {
    // out bits MSB-first.
    final bits = <int>[];
    for (final byte in f) {
      for (int k = 7; k >= 0; k--) {
        bits.add((byte >> k) & 1);
      }
    }
    // differential encode -> raw.
    int prev = 0;
    final raw = <int>[];
    for (final b in bits) {
      final r = b == 1 ? prev : 1 - prev;
      prev = r;
      raw.add(r);
    }
    // manchester chips.
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

void main() {
  final frame = _buildM10(
    lat: 48.5,
    lon: 2.3,
    alt: 1500.0,
    week: 2185,
    towMs: 43200000,
    sats: 8,
  );

  test('parses a synthesized M10 frame', () {
    final f = M10Decoder().decodeFrame(frame);
    expect(f, isNotNull);
    expect(f!.latitude, closeTo(48.5, 1e-4));
    expect(f.longitude, closeTo(2.3, 1e-4));
    expect(f.altitude, closeTo(1500.0, 0.1));
    expect(f.satellites, 8);
    expect(f.dateTimeUtc.hour, 12);
  });

  test('rejects a frame with a corrupted checksum', () {
    final bad = Uint8List.fromList(frame);
    bad[0x10] ^= 0xFF;
    expect(M10Decoder().decodeFrame(bad), isNull);
  });

  test('demodulates M10 from clean audio (48kHz)', () {
    final pcm = _modulate([frame, frame, frame, frame], 48000);
    final frames = M10Demodulator(48000).demodulate(pcm);
    expect(frames, isNotEmpty);
    final dec = M10Decoder();
    M10Frame? got;
    for (final fr in frames) {
      got = dec.decodeFrame(fr) ?? got;
    }
    expect(got, isNotNull);
    expect(got!.latitude, closeTo(48.5, 1e-4));
    expect(got.longitude, closeTo(2.3, 1e-4));
  });

  test('differential decode is inversion-invariant', () {
    final pcm = _modulate([frame, frame, frame], 48000);
    for (int i = 0; i < pcm.length; i++) {
      pcm[i] = (-pcm[i]).clamp(-32767, 32767);
    }
    final frames = M10Demodulator(48000).demodulate(pcm);
    final dec = M10Decoder();
    M10Frame? got;
    for (final fr in frames) {
      got = dec.decodeFrame(fr) ?? got;
    }
    expect(got, isNotNull, reason: 'inverted signal must still decode');
    expect(got!.latitude, closeTo(48.5, 1e-4));
  });
}
