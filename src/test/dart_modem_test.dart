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
// dart_modem_test.dart - Test harness for the DART modem.
//
// Usage:
//   dart run test/dart_modem_test.dart encode -m 2 -o output.wav "Hello, world!"
//   dart run test/dart_modem_test.dart decode output.wav
//   dart run test/dart_modem_test.dart loopback
//   dart run test/dart_modem_test.dart loopback --sbc
//   dart run test/dart_modem_test.dart sweep
//

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/dart_modem.dart';
import 'package:htcommander/hamlib/dart_ldpc.dart';
import 'package:htcommander/hamlib/dart_ofdm.dart';
import 'package:htcommander/hamlib/dart_constellation.dart';
import 'package:htcommander/hamlib/wav_file.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final command = args[0];
  final restArgs = args.sublist(1);

  switch (command) {
    case 'encode':
      _cmdEncode(restArgs);
      break;
    case 'decode':
      _cmdDecode(restArgs);
      break;
    case 'loopback':
      _cmdLoopback(restArgs);
      break;
    case 'ldpc':
      _cmdLdpcTest(restArgs);
      break;
    case 'fft':
      _cmdFftTest(restArgs);
      break;
    case 'constellation':
      _cmdConstellationTest(restArgs);
      break;
    case 'papr':
      _cmdPaprTest(restArgs);
      break;
    case 'stream':
      _cmdStreamTest(restArgs);
      break;
    default:
      print('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

void _printUsage() {
  print('DART Modem Test Tool');
  print('');
  print('Commands:');
  print('  encode -m <mode> -o <output.wav> [-s src] [-d dst] <message>');
  print('    Encode a text message to a WAV file.');
  print('    -m: mode 0-5 (default 2)');
  print('');
  print('  decode <input.wav>');
  print('    Decode a DART frame from a WAV file.');
  print('');
  print('  loopback [--sbc] [--noise <dB>] [--modes 0,1,2,3,4,5]');
  print('    Encode → [optional SBC/noise] → decode round-trip test.');
  print('');
  print('  ldpc');
  print('    Unit test LDPC encode/decode at all rates.');
  print('');
  print('  fft');
  print('    Unit test FFT/IFFT round-trip.');
  print('');
  print('  constellation');
  print('    Unit test constellation map/demap round-trip.');
  print('');
  print('  papr');
  print('    Compare PAPR of plain OFDM vs DFT-spread (SC-FDMA).');
}

// ============================================================================
// Command: encode
// ============================================================================

void _cmdEncode(List<String> args) {
  int modeIdx = 2;
  String output = 'dart_output.wav';
  String source = 'N0CALL';
  String dest = 'CQ';
  String message = '';

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-m':
        modeIdx = int.parse(args[++i]);
        break;
      case '-o':
        output = args[++i];
        break;
      case '-s':
        source = args[++i];
        break;
      case '-d':
        dest = args[++i];
        break;
      default:
        message = args.sublist(i).join(' ');
        i = args.length;
        break;
    }
  }

  if (message.isEmpty) {
    print('Error: no message specified');
    exit(1);
  }

  final mode = DartMode.values[modeIdx.clamp(0, 5)];
  final modeParams = DartModeParams.fromMode(mode);
  print('Encoding: "$message"');
  print('Mode: ${modeParams.description}');
  print('Source: $source → Dest: $dest');

  final modem = DartModem();
  final payload = Uint8List.fromList(message.codeUnits);
  final pcm = modem.encode(
    payload: payload,
    mode: mode,
    source: source,
    destination: dest,
  );

  final params = WavParams()
    ..sampleRate = modem.ofdmParams.sampleRate
    ..bitsPerSample = 16
    ..numChannels = 1;
  WavFile.write(output, pcm, params);

  final double durationMs = pcm.length * 1000.0 / modem.ofdmParams.sampleRate;
  print('Written: $output (${pcm.length} samples, ${durationMs.toStringAsFixed(1)} ms)');
}

// ============================================================================
// Command: decode
// ============================================================================

void _cmdDecode(List<String> args) {
  if (args.isEmpty) {
    print('Error: no input WAV file specified');
    exit(1);
  }

  final input = args[0];
  final (Int16List samples, WavParams wavParams) = WavFile.read(input);
  print('Read: $input (${samples.length} samples, '
      '${wavParams.sampleRate} Hz)');

  final modem = DartModem();
  final result = modem.decode(samples);

  if (result == null) {
    print('FAIL: No DART frame detected');
    exit(1);
  }

  final modeParams = DartModeParams.fromMode(
    DartMode.values[result.header.modeIndex.clamp(0, 5)],
  );
  print('Detected DART frame:');
  print('  Mode: ${result.header.modeIndex} (${modeParams.description})');
  print('  Source: ${result.header.source}');
  print('  Destination: ${result.header.destination}');
  print('  Seq#: ${result.header.seqNum}');
  print('  Payload (${result.payload.length} bytes): '
      '${String.fromCharCodes(result.payload)}');
  print('  CRC: ${result.crcOk ? "OK" : "FAIL"}');
}

// ============================================================================
// Command: loopback
// ============================================================================

void _cmdLoopback(List<String> args) {
  bool useSbc = false;
  double noisedB = double.infinity; // no noise by default
  double clip = 0; // 0 = no clipping; else fraction of peak to hard-limit at
  List<int> modes = [0, 1, 2, 3, 4, 5];

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sbc':
        useSbc = true;
        break;
      case '--noise':
        noisedB = double.parse(args[++i]);
        break;
      case '--clip':
        clip = double.parse(args[++i]);
        break;
      case '--modes':
        modes = args[++i].split(',').map(int.parse).toList();
        break;
    }
  }

  print('DART Modem Loopback Test');
  print('  SBC: ${useSbc ? "enabled" : "disabled"}');
  print('  Noise: ${noisedB.isFinite ? "${noisedB.toStringAsFixed(1)} dB SNR" : "none"}');
  print('  Clip: ${clip > 0 ? "${(clip * 100).toStringAsFixed(0)}% of peak" : "none"}');
  print('  Modes: $modes');
  print('');

  // Test messages of increasing length
  final testMessages = [
    'Hi',
    'Hello, World!',
    'The quick brown fox jumps over the lazy dog.',
    'DART modem test: ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 !@#\$%',
    List.generate(100, (i) => String.fromCharCode(0x41 + i % 26)).join(),
  ];

  int pass = 0;
  int fail = 0;

  for (final modeIdx in modes) {
    final mode = DartMode.values[modeIdx];
    final modeParams = DartModeParams.fromMode(mode);
    print('--- Mode $modeIdx: ${modeParams.description} ---');

    for (final msg in testMessages) {
      final payload = Uint8List.fromList(msg.codeUnits);
      final modem = DartModem();

      // Encode
      final pcm = modem.encode(
        payload: payload,
        mode: mode,
        source: 'N0CALL',
        destination: 'CQ',
        seqNum: 42,
      );

      // Optionally add noise
      Int16List processedPcm = pcm;
      if (noisedB.isFinite) {
        processedPcm = _addNoise(pcm, noisedB);
      }

      // Optionally apply hard amplitude clipping (simulates an aggressive
      // limiter / amplitude-hostile radio audio path).
      if (clip > 0) {
        processedPcm = _hardClip(processedPcm, clip);
      }

      // Optionally run through SBC
      if (useSbc) {
        processedPcm = _sbcRoundTrip(processedPcm);
      }

      // Decode
      final result = modem.decode(processedPcm);

      final bool ok = result != null &&
          result.crcOk &&
          String.fromCharCodes(result.payload) == msg;

      if (ok) {
        pass++;
        print('  PASS [${msg.length} bytes]');
      } else {
        fail++;
        if (result == null) {
          print('  FAIL [${msg.length} bytes]: no frame detected');
        } else if (!result.crcOk) {
          print('  FAIL [${msg.length} bytes]: CRC error');
        } else {
          print('  FAIL [${msg.length} bytes]: payload mismatch');
          print('    Expected: ${msg.substring(0, math.min(40, msg.length))}...');
          print('    Got:      ${String.fromCharCodes(result.payload).substring(0, math.min(40, result.payload.length))}...');
        }
      }
    }
    print('');
  }

  print('Results: $pass passed, $fail failed, ${pass + fail} total');
  exit(fail > 0 ? 1 : 0);
}

// ============================================================================
// Command: ldpc - unit test LDPC encode/decode
// ============================================================================

void _cmdLdpcTest(List<String> args) {
  print('LDPC Encode/Decode Test');
  print('');

  final random = math.Random(12345);
  int pass = 0;
  int fail = 0;

  for (final rate in LdpcRate.values) {
    final code = DartLdpc.getCode(rate);
    print('Rate ${rate.name}: K=${code.k}, N=${code.n}, M=${code.m}');

    // Test 1: encode and verify syndrome
    final infoBits = Uint8List(code.k);
    for (int i = 0; i < code.k; i++) {
      infoBits[i] = random.nextInt(2);
    }
    final codeword = DartLdpc.encode(code, infoBits);

    // Check syndrome
    bool syndromeOk = true;
    for (int c = 0; c < code.m; c++) {
      int s = 0;
      for (final int v in code.checkNodeConnections[c]) {
        s ^= codeword[v];
      }
      if (s != 0) {
        syndromeOk = false;
        break;
      }
    }
    print('  Encode syndrome check: ${syndromeOk ? "PASS" : "FAIL"}');
    syndromeOk ? pass++ : fail++;

    // Test 2: decode with perfect LLRs (no noise)
    final llrPerfect = Float64List(code.n);
    for (int i = 0; i < code.n; i++) {
      llrPerfect[i] = codeword[i] == 0 ? 5.0 : -5.0;
    }
    final decoded = DartLdpc.decode(code, llrPerfect);
    bool decodePerfect = decoded != null;
    if (decodePerfect) {
      for (int i = 0; i < code.k; i++) {
        if (decoded[i] != infoBits[i]) {
          decodePerfect = false;
          break;
        }
      }
    }
    print('  Decode (no noise): ${decodePerfect ? "PASS" : "FAIL"}');
    decodePerfect ? pass++ : fail++;

    // Test 3: decode with moderate noise (SNR ~4 dB)
    final llrNoisy = Float64List(code.n);
    for (int i = 0; i < code.n; i++) {
      final double signal = codeword[i] == 0 ? 1.0 : -1.0;
      final double noise = random.nextDouble() * 0.8 - 0.4;
      llrNoisy[i] = (signal + noise) * 2.0; // scale to LLR
    }
    final decodedNoisy = DartLdpc.decode(code, llrNoisy);
    bool decodeNoisy = decodedNoisy != null;
    if (decodeNoisy) {
      for (int i = 0; i < code.k; i++) {
        if (decodedNoisy[i] != infoBits[i]) {
          decodeNoisy = false;
          break;
        }
      }
    }
    print('  Decode (noisy ~4dB): ${decodeNoisy ? "PASS" : "FAIL"}');
    decodeNoisy ? pass++ : fail++;

    print('');
  }

  print('Results: $pass passed, $fail failed');
  exit(fail > 0 ? 1 : 0);
}

// ============================================================================
// Command: fft - unit test FFT
// ============================================================================

void _cmdFftTest(List<String> args) {
  print('FFT/IFFT Round-Trip Test');
  print('');

  final random = math.Random(42);
  int pass = 0;
  int fail = 0;

  for (final int size in [16, 32, 64, 128]) {
    // Generate random complex input
    final input = List<Complex>.generate(
      size,
      (_) => Complex(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1),
    );

    // FFT then IFFT
    final freq = DartOfdm.fftPublic(input, inverse: false);
    final recovered = DartOfdm.fftPublic(freq, inverse: true);

    // Check error
    double maxError = 0;
    for (int i = 0; i < size; i++) {
      final double errI = (recovered[i].i - input[i].i).abs();
      final double errQ = (recovered[i].q - input[i].q).abs();
      maxError = math.max(maxError, math.max(errI, errQ));
    }

    final bool ok = maxError < 1e-10;
    print('  Size $size: max error = ${maxError.toStringAsExponential(2)} '
        '${ok ? "PASS" : "FAIL"}');
    ok ? pass++ : fail++;
  }

  print('');
  print('Results: $pass passed, $fail failed');
  exit(fail > 0 ? 1 : 0);
}

// ============================================================================
// Command: constellation - unit test constellation map/demap
// ============================================================================

void _cmdConstellationTest(List<String> args) {
  print('Constellation Map/Demap Test');
  print('');

  int pass = 0;
  int fail = 0;

  for (final type in ConstellationType.values) {
    final c = Constellation.get(type);
    print('  ${type.name} (${c.bitsPerSymbol} bits/symbol):');

    // Test all possible bit patterns
    bool allOk = true;
    for (int pattern = 0; pattern < (1 << c.bitsPerSymbol); pattern++) {
      final bits = List<int>.generate(
        c.bitsPerSymbol,
        (b) => (pattern >> (c.bitsPerSymbol - 1 - b)) & 1,
      );
      final symbol = c.map(bits);

      // Demap with no noise (should give strong LLRs with correct signs)
      final llrs = c.softDemap(symbol, 0.1);
      for (int b = 0; b < c.bitsPerSymbol; b++) {
        final int decidedBit = llrs[b] < 0 ? 1 : 0;
        if (decidedBit != bits[b]) {
          allOk = false;
          print('    FAIL: pattern $pattern, bit $b: expected ${bits[b]}, got $decidedBit');
        }
      }
    }
    if (allOk) {
      print('    All ${1 << c.bitsPerSymbol} patterns: PASS');
      pass++;
    } else {
      fail++;
    }

    // Check average power ≈ 1.0
    double avgPower = 0;
    for (final p in c.points) {
      avgPower += p.magnitudeSquared;
    }
    avgPower /= c.points.length;
    final bool powerOk = (avgPower - 1.0).abs() < 0.01;
    print('    Average power: ${avgPower.toStringAsFixed(4)} '
        '${powerOk ? "PASS" : "FAIL (expected ~1.0)"}');
    powerOk ? pass++ : fail++;
  }

  print('');
  print('Results: $pass passed, $fail failed');
  exit(fail > 0 ? 1 : 0);
}

// ============================================================================
// Command: stream - simulate the software-modem streaming RX (chunked PCM →
// rolling buffer → decode → consume via endSample). Mirrors _processDartSamples.
// ============================================================================

void _cmdStreamTest(List<String> args) {
  print('DART Streaming RX Test (chunked reception + frame consumption)');
  print('');

  final modem = DartModem();
  final messages = ['first frame', 'second one is longer here', 'third!'];

  // Build a continuous PCM stream: silence + frame + silence + frame + ...
  final stream = <int>[];
  stream.addAll(List<int>.filled(1500, 0));
  for (final m in messages) {
    final pcm = modem.encode(
      payload: Uint8List.fromList(m.codeUnits),
      mode: DartMode.mode2,
      seqNum: 0,
    );
    stream.addAll(pcm);
    stream.addAll(List<int>.filled(1500, 0)); // inter-frame gap
  }
  print('Total stream: ${stream.length} samples, ${messages.length} frames');

  // Feed the stream in small chunks through a rolling-buffer decoder, exactly
  // like SoftwareModem._processDartSamples does.
  final rolling = <int>[];
  final decoded = <String>[];
  const int chunk = 1024;
  int sinceDecode = 0;

  for (int off = 0; off < stream.length; off += chunk) {
    final end = math.min(off + chunk, stream.length);
    for (int i = off; i < end; i++) {
      rolling.add(stream[i]);
    }
    sinceDecode += (end - off);
    if (sinceDecode < 4000) continue;
    sinceDecode = 0;

    while (rolling.length > 2000) {
      final result = modem.decode(Int16List.fromList(rolling));
      if (result == null) break;
      if (result.crcOk) decoded.add(String.fromCharCodes(result.payload));
      final consume = result.endSample.clamp(0, rolling.length);
      if (consume <= 0) break;
      rolling.removeRange(0, consume);
    }
  }
  // Final drain.
  while (rolling.length > 2000) {
    final result = modem.decode(Int16List.fromList(rolling));
    if (result == null) break;
    if (result.crcOk) decoded.add(String.fromCharCodes(result.payload));
    final consume = result.endSample.clamp(0, rolling.length);
    if (consume <= 0) break;
    rolling.removeRange(0, consume);
  }

  int pass = 0;
  int fail = 0;
  print('Decoded ${decoded.length} frames:');
  for (int i = 0; i < messages.length; i++) {
    final got = i < decoded.length ? decoded[i] : '<missing>';
    final ok = got == messages[i];
    print('  ${ok ? "PASS" : "FAIL"} "$got"');
    ok ? pass++ : fail++;
  }

  print('');
  print('Results: $pass passed, $fail failed');
  exit(fail > 0 ? 1 : 0);
}

// ============================================================================
// Command: papr - compare PAPR of plain OFDM vs DFT-spread (SC-FDMA)
// ============================================================================

void _cmdPaprTest(List<String> args) {
  print('PAPR: plain OFDM vs DFT-spread (SC-FDMA)');
  print('');

  final params = DartOfdmParams();
  final ofdm = DartOfdm(params);
  final random = math.Random(2026);
  const int numSymbols = 2000;

  // Test each constellation
  for (final type in ConstellationType.values) {
    final c = Constellation.get(type);

    double peakPlain = 0, sumSqPlain = 0;
    double peakScfdma = 0, sumSqScfdma = 0;
    int sampleCount = 0;

    // Track per-symbol PAPR for percentile reporting
    final paprPlain = <double>[];
    final paprScfdma = <double>[];

    for (int s = 0; s < numSymbols; s++) {
      // Random data symbols for the active carriers
      final data = List<Complex>.generate(
        params.numDataCarriers,
        (_) => c.points[random.nextInt(c.points.length)],
      );

      final plain = ofdm.modulateSymbol(data, dftSpread: false);
      final scfdma = ofdm.modulateSymbol(data, dftSpread: true);

      paprPlain.add(_symbolPapr(plain));
      paprScfdma.add(_symbolPapr(scfdma));

      for (final v in plain) {
        final double p = v * v;
        sumSqPlain += p;
        if (p > peakPlain) peakPlain = p;
      }
      for (final v in scfdma) {
        final double p = v * v;
        sumSqScfdma += p;
        if (p > peakScfdma) peakScfdma = p;
      }
      sampleCount += plain.length;
    }

    final double avgPlain = sumSqPlain / sampleCount;
    final double avgScfdma = sumSqScfdma / sampleCount;
    final double paprPlainDb = 10 * _log10(peakPlain / avgPlain);
    final double paprScfdmaDb = 10 * _log10(peakScfdma / avgScfdma);

    // 99th-percentile per-symbol PAPR (more representative than absolute peak)
    paprPlain.sort();
    paprScfdma.sort();
    final int idx99 = (numSymbols * 0.99).floor();
    final double p99Plain = 10 * _log10(paprPlain[idx99]);
    final double p99Scfdma = 10 * _log10(paprScfdma[idx99]);

    print('  ${type.name.padRight(6)}: '
        'plain PAPR ${paprPlainDb.toStringAsFixed(1)} dB (99%: ${p99Plain.toStringAsFixed(1)}), '
        'SC-FDMA ${paprScfdmaDb.toStringAsFixed(1)} dB (99%: ${p99Scfdma.toStringAsFixed(1)}), '
        'gain ${(p99Plain - p99Scfdma).toStringAsFixed(1)} dB');
  }

  print('');
  print('Lower PAPR = less headroom needed = safer against the FM limiter/AGC.');
}

/// Peak-to-average power ratio (linear) of one time-domain symbol.
double _symbolPapr(Float64List samples) {
  double peak = 0, sumSq = 0;
  for (final v in samples) {
    final double p = v * v;
    sumSq += p;
    if (p > peak) peak = p;
  }
  final double avg = sumSq / samples.length;
  return avg > 1e-20 ? peak / avg : 1.0;
}

double _log10(double x) => math.log(x) / math.ln10;

// ============================================================================
// Helpers
// ============================================================================

/// Hard-clip PCM to a fraction of its peak, simulating an aggressive limiter or
/// amplitude-hostile radio audio path. Destroys amplitude information while
/// preserving zero-crossings/frequency — the exact scenario Mode F is built for.
Int16List _hardClip(Int16List pcm, double fraction) {
  int peak = 1;
  for (final s in pcm) {
    final int a = s.abs();
    if (a > peak) peak = a;
  }
  final int limit = (peak * fraction).round().clamp(1, 32767);
  final out = Int16List(pcm.length);
  for (int i = 0; i < pcm.length; i++) {
    out[i] = pcm[i].clamp(-limit, limit);
  }
  return out;
}

/// Add AWGN to PCM samples at a given SNR (dB).
Int16List _addNoise(Int16List pcm, double snrDb) {
  final random = math.Random(99);
  // Compute signal power
  double signalPower = 0;
  for (int i = 0; i < pcm.length; i++) {
    signalPower += pcm[i] * pcm[i];
  }
  signalPower /= pcm.length;

  final double noisePower = signalPower / math.pow(10, snrDb / 10);
  final double noiseStd = math.sqrt(noisePower);

  final output = Int16List(pcm.length);
  for (int i = 0; i < pcm.length; i++) {
    // Box-Muller for Gaussian noise
    final double u1 = random.nextDouble().clamp(1e-10, 1.0);
    final double u2 = random.nextDouble();
    final double noise = noiseStd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    output[i] = (pcm[i] + noise).round().clamp(-32767, 32767);
  }
  return output;
}

/// Round-trip PCM through the SBC codec (simulates Bluetooth audio).
Int16List _sbcRoundTrip(Int16List pcm) {
  // SBC config matching the radio's Bluetooth link:
  // 32 kHz mono, 16 blocks, 8 subbands, loudness allocation, bitpool 18.
  final SbcFrame frame = SbcFrame()
    ..frequency = SbcFrequency.freq32K
    ..mode = SbcMode.mono
    ..allocationMethod = SbcBitAllocationMethod.loudness
    ..blocks = 16
    ..subbands = 8
    ..bitpool = 18;

  final encoder = SbcEncoder();
  final decoder = SbcDecoder();

  final int samplesPerFrame = frame.blocks * frame.subbands; // 128
  final outSamples = <int>[];

  for (int off = 0; off < pcm.length; off += samplesPerFrame) {
    final frameBuf = Int16List(samplesPerFrame);
    for (int i = 0; i < samplesPerFrame; i++) {
      final int idx = off + i;
      frameBuf[i] = idx < pcm.length ? pcm[idx] : 0;
    }

    final encoded = encoder.encode(frameBuf, null, frame);
    if (encoded == null) {
      // Encode failed — pass through
      for (int i = 0; i < samplesPerFrame && off + i < pcm.length; i++) {
        outSamples.add(pcm[off + i]);
      }
      continue;
    }

    final result = decoder.decode(encoded);
    if (!result.success) {
      for (int i = 0; i < samplesPerFrame && off + i < pcm.length; i++) {
        outSamples.add(pcm[off + i]);
      }
      continue;
    }

    outSamples.addAll(result.pcmLeft);
  }

  return Int16List.fromList(outSamples);
}
