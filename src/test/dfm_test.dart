/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radiosonde/dfm_decoder.dart';
import 'package:htcommander/radiosonde/dfm_demodulator.dart';
import 'package:htcommander/radiosonde/radiosonde_fix.dart';
import 'package:htcommander/radiosonde/radiosonde_monitor.dart';

/// Reads a mono 16-bit PCM WAV, returning its samples and sample rate.
(Int16List, int) _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  int sampleRate = 48000;
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

const String _fixture = 'test/radiosonde_samples/DFM09.wav';
const String _fixture32k = 'test/radiosonde_samples/DFM09_32k.wav';

void main() {
  test('decodes the Graw DFM-09 recording (demod + frame parse)', () {
    final (pcm, fs) = _readWav(_fixture);
    expect(fs, 48000);

    final frames = DfmDemodulator(fs).demodulate(pcm);
    expect(frames.length, greaterThan(50),
        reason: 'expected many header-valid frames');

    final decoder = DfmDecoder();
    final fixes = <DfmFrame>[];
    for (final bits in frames) {
      final r = decoder.decodeFrame(bits);
      if (r != null) fixes.add(r);
    }
    expect(fixes, isNotEmpty, reason: 'expected at least one GPS fix');

    // The recording is a DFM-09 launched near Vienna, Austria.
    final f = fixes.last;
    expect(f.latitude, closeTo(48.213, 0.05));
    expect(f.longitude, closeTo(16.264, 0.05));
    expect(f.altitude, greaterThan(100));
    expect(f.satellites, greaterThan(0));
    expect(f.dateTimeUtc.year, 2017);

    // The sonde serial and type resolve from the config packets.
    final identified =
        fixes.where((x) => x.dfmType == 'DFM09' && x.sondeId.contains('523135'));
    expect(identified, isNotEmpty,
        reason: 'expected the DFM-09 serial 523135 to resolve');
  });

  test('streaming monitor decodes chunked PCM and emits a fix', () async {
    final (pcm, fs) = _readWav(_fixture);
    final monitor = RadiosondeMonitor(sampleRate: fs);
    final got = <RadiosondeFix>[];
    final sub = monitor.onDecoded.listen(got.add);

    // Feed the recording in small byte chunks like the live audio pipeline.
    final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    const chunk = 4096;
    for (int off = 0; off < bytes.length; off += chunk) {
      final len =
          (off + chunk <= bytes.length) ? chunk : bytes.length - off;
      monitor.processPcm16(bytes, off, len);
    }
    monitor.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(got, isNotEmpty, reason: 'monitor should emit at least one fix');
    expect(got.any((x) => x.latitude.abs() > 1 && x.longitude.abs() > 1), isTrue);

    await sub.cancel();
    monitor.dispose();
  });

  test('decodes at the live 32 kHz radio pipeline rate', () {
    final (pcm32, fs) = _readWav(_fixture32k);
    expect(fs, 32000);
    final frames = DfmDemodulator(fs).demodulate(pcm32);
    final decoder = DfmDecoder();
    final fixes = <DfmFrame>[];
    for (final bits in frames) {
      final r = decoder.decodeFrame(bits);
      if (r != null) fixes.add(r);
    }
    expect(fixes, isNotEmpty,
        reason: 'must decode at the 32 kHz live pipeline rate');
    expect(
      fixes.any((x) => x.dfmType == 'DFM09' && x.sondeId.contains('523135')),
      isTrue,
    );
  });

  test('rejects noise (no false fixes)', () {
    final rnd = List<int>.generate(48000 * 3, (i) => ((i * 1103515245 + 12345) % 65536) - 32768);
    final noise = Int16List.fromList(rnd);
    final frames = DfmDemodulator(48000).demodulate(noise);
    final decoder = DfmDecoder();
    for (final bits in frames) {
      final r = decoder.decodeFrame(bits);
      expect(r, isNull, reason: 'noise must not produce a GPS fix');
    }
  });
}
