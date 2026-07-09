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
// dart_debug_test.dart - Stage-by-stage debug harness for the DART modem.
// Traces each pipeline stage to isolate where the data path breaks.
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/dart_constellation.dart';
import 'package:htcommander/hamlib/dart_ofdm.dart';
import 'package:htcommander/hamlib/dart_preamble.dart';
import 'package:htcommander/hamlib/dart_modem.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main() {
  print('=== DART Pipeline Debug ===\n');

  _testOfdmRoundTrip();
  _testPreambleDetect();
  _testChannelEstimate();
  _testOfdmThroughChannel();
  _testHeaderOnly();
  _testQpskThroughSbc();
}

/// Test 1: OFDM modulate → demodulate with perfect (unity) channel.
void _testOfdmRoundTrip() {
  print('--- Test 1: OFDM modulate/demodulate (unity channel) ---');
  final params = DartOfdmParams();
  final ofdm = DartOfdm(params);
  print('  FFT size: ${params.fftSize}, active carriers: ${params.numDataCarriers}');
  print('  Active carrier indices: ${params.activeCarriers}');

  // Create known QPSK symbols
  final constellation = Constellation.get(ConstellationType.qpsk);
  final random = math.Random(1);
  final txSymbols = List<Complex>.generate(
    params.numDataCarriers,
    (_) => constellation.points[random.nextInt(4)],
  );

  // Modulate
  final timeDomain = ofdm.modulateSymbol(txSymbols);

  // Unity channel estimate
  final unityChannel = List<Complex>.filled(
    params.numDataCarriers,
    const Complex(1.0, 0.0),
  );

  // Demodulate
  final rxSymbols = ofdm.demodulateSymbol(timeDomain, unityChannel);

  // Compare
  double maxErr = 0;
  for (int i = 0; i < params.numDataCarriers; i++) {
    final double err = (rxSymbols[i] - txSymbols[i]).magnitude;
    maxErr = math.max(maxErr, err);
  }
  print('  Max symbol error: ${maxErr.toStringAsExponential(2)} '
      '${maxErr < 1e-9 ? "PASS" : "FAIL"}');
  print('');
}

/// Test 2: Preamble generation and detection.
void _testPreambleDetect() {
  print('--- Test 2: Preamble detect ---');
  final params = DartOfdmParams();
  final preamble = DartPreamble(ofdmParams: params);
  print('  Preamble samples: ${preamble.preambleSamples}');
  print('  ZC length: ${preamble.zcLength}');

  final preambleSamples = preamble.generate();

  // Embed preamble in a longer buffer with some leading silence
  const int leadSilence = 100;
  final buffer = Float64List(leadSilence + preambleSamples.length + 200);
  for (int i = 0; i < preambleSamples.length; i++) {
    buffer[leadSilence + i] = preambleSamples[i];
  }

  final int detectedPos = preamble.detect(buffer);
  print('  Expected position: $leadSilence, detected: $detectedPos '
      '${(detectedPos - leadSilence).abs() <= 2 ? "PASS" : "FAIL"}');
  print('');
}

/// Test 3: Channel estimation with unity channel.
void _testChannelEstimate() {
  print('--- Test 3: Channel estimate (unity channel) ---');
  final params = DartOfdmParams();
  final preamble = DartPreamble(ofdmParams: params);

  final preambleSamples = preamble.generate();

  // Estimate channel directly from the clean preamble
  final channelEst = preamble.estimateChannel(preambleSamples);

  // Should be ~unity (magnitude ~1, phase ~0) since no channel applied
  double avgMag = 0;
  double maxPhaseErr = 0;
  for (final h in channelEst) {
    avgMag += h.magnitude;
    maxPhaseErr = math.max(maxPhaseErr, h.phase.abs());
  }
  avgMag /= channelEst.length;
  print('  Avg |H|: ${avgMag.toStringAsFixed(3)} (expect ~1.0)');
  print('  Max phase error: ${maxPhaseErr.toStringAsFixed(3)} rad');
  print('  ${(avgMag - 1.0).abs() < 0.1 ? "PASS" : "FAIL"}');
  print('');
}

/// Test 4: Full OFDM symbol through preamble-estimated channel.
void _testOfdmThroughChannel() {
  print('--- Test 4: Data symbol through preamble channel estimate ---');
  final params = DartOfdmParams();
  final ofdm = DartOfdm(params);
  final preamble = DartPreamble(ofdmParams: params);

  // Generate preamble + one data OFDM symbol
  final constellation = Constellation.get(ConstellationType.bpsk);
  final random = math.Random(7);
  final txBits = List<int>.generate(params.numDataCarriers, (_) => random.nextInt(2));
  final txSymbols = txBits.map((b) => constellation.points[b]).toList();

  final preambleSamples = preamble.generate();
  final dataSamples = ofdm.modulateSymbol(txSymbols);

  // Concatenate
  final full = Float64List(preambleSamples.length + dataSamples.length);
  full.setRange(0, preambleSamples.length, preambleSamples);
  full.setRange(preambleSamples.length, full.length, dataSamples);

  // Estimate channel from preamble
  final channelEst = preamble.estimateChannel(full);

  // Demodulate the data symbol
  final dataStart = preamble.preambleSamples;
  final dataSlice = Float64List.sublistView(full, dataStart, dataStart + params.symbolLength);
  final rxSymbols = ofdm.demodulateSymbol(dataSlice, channelEst);

  // Decode bits
  int bitErrors = 0;
  for (int i = 0; i < params.numDataCarriers; i++) {
    final int rxBit = rxSymbols[i].i < 0 ? 1 : 0;
    if (rxBit != txBits[i]) bitErrors++;
  }
  print('  Bit errors: $bitErrors / ${params.numDataCarriers} '
      '${bitErrors == 0 ? "PASS" : "FAIL"}');

  // Show first few symbols
  print('  First 3 TX bits: ${txBits.take(3).toList()}');
  print('  First 3 RX symbols: ${rxSymbols.take(3).map((s) => s.toString()).toList()}');
  print('');
}

/// Test 5: Header encode → decode via full modem (no channel impairment).
void _testHeaderOnly() {
  print('--- Test 5: Full modem header round-trip ---');

  final header = DartHeader(
    modeIndex: 2,
    payloadLength: 13,
    seqNum: 42,
    flags: 0x04,
    source: 'N0CALL',
    destination: 'CQ',
  );

  // Serialize and deserialize header directly (no radio)
  final bits = header.toBits();
  print('  Header bits length: ${bits.length}');
  final decoded = DartHeader.fromBits(bits);
  if (decoded == null) {
    print('  Direct header serialize/deserialize: FAIL (CRC)');
  } else {
    final bool ok = decoded.modeIndex == header.modeIndex &&
        decoded.payloadLength == header.payloadLength &&
        decoded.seqNum == header.seqNum &&
        decoded.source == header.source &&
        decoded.destination == header.destination;
    print('  Direct header serialize/deserialize: ${ok ? "PASS" : "FAIL"}');
    if (!ok) {
      print('    mode: ${header.modeIndex} vs ${decoded.modeIndex}');
      print('    len: ${header.payloadLength} vs ${decoded.payloadLength}');
      print('    seq: ${header.seqNum} vs ${decoded.seqNum}');
      print('    src: "${header.source}" vs "${decoded.source}"');
      print('    dst: "${header.destination}" vs "${decoded.destination}"');
    }
  }

  // Now full modem encode → decode
  final modem = DartModem();
  final payload = Uint8List.fromList('Hello, World!'.codeUnits);
  final pcm = modem.encode(
    payload: payload,
    mode: DartMode.mode0,
    source: 'N0CALL',
    destination: 'CQ',
    seqNum: 42,
  );
  print('  Encoded PCM: ${pcm.length} samples');

  final result = modem.decode(pcm);
  if (result == null) {
    print('  Full modem decode: FAIL (no frame / header decode failed)');
  } else {
    print('  Full modem decode: header OK, mode=${result.header.modeIndex}, '
        'payloadLen=${result.header.payloadLength}');
    print('  Payload: "${String.fromCharCodes(result.payload)}"');
    print('  CRC: ${result.crcOk ? "OK" : "FAIL"}');
  }
  print('');
}

/// Test 6: QPSK OFDM symbols through SBC to see scatter/phase rotation.
void _testQpskThroughSbc() {
  print('--- Test 6: QPSK scatter through SBC ---');
  final params = DartOfdmParams();
  final ofdm = DartOfdm(params);
  final preamble = DartPreamble(ofdmParams: params);

  final constellation = Constellation.get(ConstellationType.qpsk);
  final random = math.Random(3);

  // Build: guard + preamble + 4 QPSK data symbols + guard
  const int guard = 256;
  final preambleSamples = preamble.generate();

  final txSymbolsList = <List<Complex>>[];
  final dataOfdm = <Float64List>[];
  for (int s = 0; s < 4; s++) {
    final syms = List<Complex>.generate(
      params.numDataCarriers,
      (_) => constellation.points[random.nextInt(4)],
    );
    txSymbolsList.add(syms);
    dataOfdm.add(ofdm.modulateSymbol(syms));
  }

  final parts = <Float64List>[
    Float64List(guard),
    preambleSamples,
    ...dataOfdm,
    Float64List(guard),
  ];
  final pcm = DartOfdm.toPcm(parts);

  // Through SBC
  final sbcPcm = _sbcRoundTrip(pcm);
  final sbcFloat = DartOfdm.fromPcm(sbcPcm);

  // Detect and estimate channel
  final int pos = preamble.detect(sbcFloat);
  print('  Preamble detected at: $pos');
  if (pos < 0) {
    print('  FAIL: no preamble');
    print('');
    return;
  }

  final slice = Float64List.sublistView(sbcFloat, pos, sbcFloat.length);
  final channelEst = preamble.estimateChannel(slice);

  // Demodulate first data symbol
  final dataStart = pos + preamble.preambleSamples;
  final dataSlice = Float64List.sublistView(
    sbcFloat, dataStart, dataStart + params.symbolLength);
  final rx = ofdm.demodulateSymbol(dataSlice, channelEst);

  // Compare phase/magnitude vs TX
  print('  TX symbol 0 (first 3 carriers): '
      '${txSymbolsList[0].take(3).map((s) => s.toString()).toList()}');
  print('  RX symbol 0 (first 3 carriers): '
      '${rx.take(3).map((s) => s.toString()).toList()}');

  // Measure average phase rotation and magnitude
  double avgPhaseErr = 0;
  double avgMagRatio = 0;
  int count = 0;
  for (int i = 0; i < params.numDataCarriers; i++) {
    final double txPhase = txSymbolsList[0][i].phase;
    final double rxPhase = rx[i].phase;
    double dPhase = rxPhase - txPhase;
    while (dPhase > math.pi) {
      dPhase -= 2 * math.pi;
    }
    while (dPhase < -math.pi) {
      dPhase += 2 * math.pi;
    }
    avgPhaseErr += dPhase.abs();
    if (txSymbolsList[0][i].magnitude > 0.01) {
      avgMagRatio += rx[i].magnitude / txSymbolsList[0][i].magnitude;
      count++;
    }
  }
  avgPhaseErr /= params.numDataCarriers;
  avgMagRatio /= count;
  print('  Avg phase error: ${(avgPhaseErr * 180 / math.pi).toStringAsFixed(1)}°');
  print('  Avg magnitude ratio: ${avgMagRatio.toStringAsFixed(3)}');
  print('');
}

Int16List _sbcRoundTrip(Int16List pcm) {
  final frame = SbcFrame()
    ..frequency = SbcFrequency.freq32K
    ..mode = SbcMode.mono
    ..allocationMethod = SbcBitAllocationMethod.loudness
    ..blocks = 16
    ..subbands = 8
    ..bitpool = 18;

  final encoder = SbcEncoder();
  final decoder = SbcDecoder();
  final int samplesPerFrame = frame.blocks * frame.subbands;
  final outSamples = <int>[];

  for (int off = 0; off < pcm.length; off += samplesPerFrame) {
    final frameBuf = Int16List(samplesPerFrame);
    for (int i = 0; i < samplesPerFrame; i++) {
      final int idx = off + i;
      frameBuf[i] = idx < pcm.length ? pcm[idx] : 0;
    }
    final encoded = encoder.encode(frameBuf, null, frame);
    if (encoded == null) continue;
    final result = decoder.decode(encoded);
    if (!result.success) continue;
    outSamples.addAll(result.pcmLeft);
  }
  return Int16List.fromList(outSamples);
}
