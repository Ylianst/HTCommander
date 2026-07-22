/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// gsm_bit_exact_test.dart - Verifies the pure-Dart GSM 06.10 codec against
// bit-exact reference vectors produced by libgsm (reference/libgsm).
//
// Generate the vectors first (see reference/libgsm/build_golden.sh):
//   wsl -e bash -lc "reference/libgsm/build_golden.sh"
// then:
//   flutter test test/gsm_bit_exact_test.dart
//

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/gsm/gsm_codec.dart';
import 'package:htcommander/gsm/gsm_frame.dart';

/// Resolves the vectors directory relative to the package root or this file.
Directory _vectorsDir() {
  for (final String p in <String>[
    'test/gsm_vectors',
    'src/test/gsm_vectors',
  ]) {
    final Directory d = Directory(p);
    if (d.existsSync()) return d;
  }
  // Fall back to a path relative to this test file.
  final String here = File.fromUri(Platform.script).parent.path;
  return Directory('$here/gsm_vectors');
}

Int16List _readPcm(File f) {
  final Uint8List bytes = f.readAsBytesSync();
  final ByteData bd = ByteData.sublistView(bytes);
  final Int16List out = Int16List(bytes.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little);
  }
  return out;
}

void main() {
  final Directory vdir = _vectorsDir();
  final File inputFile = File('${vdir.path}/input.pcm');
  final File goldenGsm = File('${vdir.path}/golden.gsm');
  final File goldenDec = File('${vdir.path}/golden_dec.pcm');

  final bool haveVectors = inputFile.existsSync() &&
      goldenGsm.existsSync() &&
      goldenDec.existsSync();

  group('GSM 06.10 bit-exact vs libgsm', () {
    test('reference vectors are present', () {
      expect(
        haveVectors,
        isTrue,
        reason: 'Missing reference vectors in ${vdir.path}. Generate them '
            'with: wsl -e bash -lc "reference/libgsm/build_golden.sh"',
      );
    }, skip: haveVectors ? false : 'reference vectors not generated yet');

    test('encoder output is byte-identical to libgsm', () {
      final Int16List pcm = _readPcm(inputFile);
      final Uint8List expected = goldenGsm.readAsBytesSync();

      expect(pcm.length % gsmFrameSamples, 0);
      expect(expected.length, (pcm.length ~/ gsmFrameSamples) * gsmFrameSize);

      final GsmEncoder enc = GsmEncoder();
      final Uint8List actual = enc.encode(pcm);

      expect(actual.length, expected.length);
      _expectBytesEqual(actual, expected, 'encoded frames');
    }, skip: haveVectors ? false : 'reference vectors not generated yet');

    test('decoder output is sample-identical to libgsm', () {
      final Uint8List gsmBytes = goldenGsm.readAsBytesSync();
      final Int16List expected = _readPcm(goldenDec);

      final GsmDecoder dec = GsmDecoder();
      final Int16List actual = dec.decode(gsmBytes);

      expect(actual.length, expected.length);
      _expectSamplesEqual(actual, expected, 'decoded samples');
    }, skip: haveVectors ? false : 'reference vectors not generated yet');
  });

  group('GSM 06.10 self-consistency', () {
    test('encode/decode round-trips without throwing', () {
      final Int16List pcm = Int16List(160 * 10);
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = ((i * 37) & 0x7fff) - 16384;
      }
      final GsmEncoder enc = GsmEncoder();
      final GsmDecoder dec = GsmDecoder();
      final Uint8List frames = enc.encode(pcm);
      expect(frames.length, 10 * gsmFrameSize);
      final Int16List out = dec.decode(frames);
      expect(out.length, pcm.length);
    });

    test('invalid magic returns null from decodeFrame', () {
      final Uint8List bad = Uint8List(gsmFrameSize); // magic nibble 0x0
      final GsmDecoder dec = GsmDecoder();
      expect(dec.decodeFrame(bad), isNull);
    });
  });
}

void _expectBytesEqual(Uint8List a, Uint8List b, String what) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      final int frame = i ~/ gsmFrameSize;
      final int off = i % gsmFrameSize;
      fail('$what differ at byte $i (frame $frame, offset $off): '
          'Dart=0x${a[i].toRadixString(16)} C=0x${b[i].toRadixString(16)}');
    }
  }
}

void _expectSamplesEqual(Int16List a, Int16List b, String what) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      final int frame = i ~/ gsmFrameSamples;
      final int off = i % gsmFrameSamples;
      fail('$what differ at sample $i (frame $frame, offset $off): '
          'Dart=${a[i]} C=${b[i]}');
    }
  }
}
