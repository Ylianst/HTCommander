// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main() {
  final path = [
    'test',
    'sbc_vectors',
    'google.json',
  ].join(Platform.pathSeparator);
  final fixture =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final vectors = (fixture['vectors'] as List).cast<Map<String, dynamic>>();

  for (final vector in vectors) {
    final frame = SbcFrame()
      ..frequency = SbcFrequency.values[vector['frequency'] as int]
      ..mode = SbcMode.values[vector['mode'] as int]
      ..blocks = vector['blocks'] as int
      ..subbands = vector['subbands'] as int
      ..allocationMethod =
          SbcBitAllocationMethod.values[vector['allocation'] as int]
      ..bitpool = vector['bitpool'] as int
      ..isMsbc = vector['msbc'] as bool;
    final name = frame.isMsbc
        ? 'mSBC'
        : '${frame.mode.name}/${frame.subbands} bands/'
              '${frame.allocationMethod.name}/bitpool ${frame.bitpool}';

    test('Google golden encoder and decoder: $name', () {
      final encoder = SbcEncoder();
      final decoder = SbcDecoder();
      final left = Int16List.fromList((vector['pcmLeft'] as List).cast<int>());
      final right = vector['pcmRight'] == null
          ? null
          : Int16List.fromList((vector['pcmRight'] as List).cast<int>());
      final encoded = (vector['encoded'] as List).cast<List<dynamic>>();
      final decoded = (vector['decoded'] as List).cast<List<dynamic>>();
      for (int n = 0; n < encoded.length; n++) {
        final bytes = Uint8List.fromList(encoded[n].cast<int>());
        expect(encoder.encode(left, right, frame), bytes, reason: 'frame $n');
        final actual = decoder.decode(bytes);
        expect(actual.success, isTrue, reason: 'frame $n');
        final samples = actual.pcmRight == null
            ? actual.pcmLeft
            : List.generate(
                actual.pcmLeft.length * 2,
                (i) => i.isEven
                    ? actual.pcmLeft[i ~/ 2]
                    : actual.pcmRight![i ~/ 2],
              );
        expect(samples, decoded[n].cast<int>(), reason: 'frame $n');
      }
    });
  }
}
