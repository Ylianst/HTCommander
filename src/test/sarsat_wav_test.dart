/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sarsat/sarsat_1g_decoder.dart';
import 'package:htcommander/sarsat/sarsat_1g_demodulator.dart';

/// Reads a mono 16-bit PCM WAV, returning its samples and sample rate.
(Int16List, int) _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  int sampleRate = 32000;
  int pos = 12; // skip "RIFF"<size>"WAVE"
  int dataOffset = -1, dataLen = 0;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = bd.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      sampleRate = bd.getUint32(pos + 12, Endian.little);
    } else if (id == 'data') {
      dataOffset = pos + 8;
      dataLen = size;
      break;
    }
    pos += 8 + size + (size & 1);
  }
  final count = dataLen ~/ 2;
  final out = Int16List(count);
  for (int i = 0; i < count; i++) {
    out[i] = bd.getInt16(dataOffset + i * 2, Endian.little);
  }
  return (out, sampleRate);
}

void main() {
  // Real over-the-air-style recording of a 406 MHz self-test beacon
  // (FM-demodulated audio, 32 kHz mono). Exercises the production demodulator's
  // FM-demod (autocorrelation) path end-to-end on a genuine signal.
  test('decodes the real self-test beacon recording (FM-demod path)', () {
    final (pcm, fs) = _readWav('test/sarsat_samples/sarsat_selftest_beacon.wav');
    final frames = Sarsat1gDemodulator(fs).decode(pcm);

    expect(frames, isNotEmpty, reason: 'expected at least one decoded beacon');
    final f = frames.first;
    expect(f.length, 144);
    expect(f.crc1Ok, isTrue);
    expect(f.crc2Ok, isTrue);
    expect(f.isTest, isTrue);
    expect(f.countryCode, 227);
    expect(f.protocolCode, 9);
    expect(f.protocol, Sarsat1gProtocol.emergencyElt);
    expect(f.hexId, '1C72091A2B3FDFF');
    // Full ELT(DT) position (matches the online T.001 decoder).
    expect(f.hasPosition, isTrue);
    expect(f.latitude, closeTo(42.954, 5e-4));
    expect(f.longitude, closeTo(1.364, 5e-4));
  });
}
