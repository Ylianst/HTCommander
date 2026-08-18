import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/imet_decoder.dart';
import 'package:htcommander/radiosonde/imet_demodulator.dart';

List<int> _buildGpsPacket({
  required double lat,
  required double lon,
  required int alt,
  required int sats,
  required int hr,
  required int min,
  required int sec,
}) {
  final p = List<int>.filled(18, 0);
  p[0] = 0x01; // SOH
  p[1] = 0x02; // PKT_GPS
  final bd = ByteData(8);
  bd.setFloat32(0, lat, Endian.little);
  bd.setFloat32(4, lon, Endian.little);
  for (int i = 0; i < 4; i++) {
    p[0x02 + i] = bd.getUint8(i);
    p[0x06 + i] = bd.getUint8(4 + i);
  }
  final altN = alt + 5000;
  p[0x0A] = altN & 0xFF;
  p[0x0B] = (altN >> 8) & 0xFF;
  p[0x0C] = sats;
  p[0x0D] = hr;
  p[0x0E] = min;
  p[0x0F] = sec;
  final crc = ImetDecoder.crc16(p, 0, 0x10);
  p[0x10] = (crc >> 8) & 0xFF;
  p[0x11] = crc & 0xFF;
  return p;
}

// 8N1 bit stream for a byte list, with a mark preamble.
List<int> _framing(List<int> bytes) {
  final bits = <int>[];
  for (int i = 0; i < 40; i++) {
    bits.add(1); // preamble (mark idle)
  }
  for (final b in bytes) {
    bits.add(0); // start
    for (int k = 0; k < 8; k++) {
      bits.add((b >> k) & 1); // LSB first
    }
    bits.add(1); // stop
  }
  for (int i = 0; i < 20; i++) {
    bits.add(1); // trailing mark
  }
  return bits;
}

/// AFSK NCO modulator: bit1 -> 1200 Hz, bit0 -> 2200 Hz.
Int16List _modulate(List<int> bits, int fs) {
  final bitlen = fs / 1200;
  final total = (bits.length * bitlen).ceil() + fs ~/ 10;
  final out = Int16List(total);
  double phase = 0;
  const amp = 9000.0;
  int idx = fs ~/ 20;
  for (final bit in bits) {
    final freq = bit == 1 ? 1200.0 : 2200.0;
    final dph = 2 * math.pi * freq / fs;
    final end = idx + bitlen.round();
    for (int s = idx; s < end && s < total; s++) {
      out[s] = (amp * math.sin(phase)).toInt();
      phase += dph;
      if (phase > 2 * math.pi) phase -= 2 * math.pi;
    }
    idx = end;
  }
  return out;
}

void main() {
  final packet = _buildGpsPacket(
    lat: 48.5,
    lon: 2.3,
    alt: 1500,
    sats: 8,
    hr: 12,
    min: 34,
    sec: 56,
  );

  test('parses an iMet GPS packet (CRC + float32)', () {
    final frames = ImetDecoder().decodeStream(packet);
    expect(frames, hasLength(1));
    final f = frames.first;
    expect(f.latitude, closeTo(48.5, 1e-4));
    expect(f.longitude, closeTo(2.3, 1e-4));
    expect(f.altitude, 1500);
    expect(f.satellites, 8);
    expect(f.hour, 12);
    expect(f.minute, 34);
    expect(f.second, 56);
  });

  test('rejects a GPS packet with a bad CRC', () {
    final bad = List<int>.from(packet);
    bad[0x02] ^= 0xFF;
    expect(ImetDecoder().decodeStream(bad), isEmpty);
  });

  test('demodulates iMet from clean AFSK audio (48kHz)', () {
    final bits = _framing(packet);
    final pcm = _modulate(bits, 48000);
    final bytes = ImetDemodulator(48000).demodulate(pcm);
    final frames = ImetDecoder().decodeStream(bytes);
    expect(frames, isNotEmpty, reason: 'should recover the GPS packet');
    final f = frames.first;
    expect(f.latitude, closeTo(48.5, 1e-4));
    expect(f.longitude, closeTo(2.3, 1e-4));
    expect(f.altitude, 1500);
  });
}
