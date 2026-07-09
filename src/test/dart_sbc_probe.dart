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
// dart_sbc_probe.dart - Probe how the SBC codec affects DART preamble/signal.
// Measures codec delay and correlation degradation.
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/dart_ofdm.dart';
import 'package:htcommander/hamlib/dart_preamble.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

void main() {
  print('=== SBC Codec Probe ===\n');

  final params = DartOfdmParams();
  final preamble = DartPreamble(ofdmParams: params);
  final preambleSamples = preamble.generate();

  print('Preamble: ${preambleSamples.length} samples');
  print('SBC frame: 128 samples, delay = ${10 * 8} samples\n');

  // Build a signal: silence + preamble + silence
  const int leadSilence = 256;
  const int trailSilence = 256;
  final signal = Float64List(leadSilence + preambleSamples.length + trailSilence);
  for (int i = 0; i < preambleSamples.length; i++) {
    signal[leadSilence + i] = preambleSamples[i];
  }

  // Convert to PCM
  final pcm = _toPcm(signal);

  // Detect in clean signal
  final cleanFloat = _fromPcm(pcm);
  final int cleanPos = preamble.detect(cleanFloat);
  print('Clean detection: expected $leadSilence, got $cleanPos');

  // Run through SBC
  final sbcPcm = _sbcRoundTrip(pcm);
  print('SBC output: ${sbcPcm.length} samples (input ${pcm.length})');
  final sbcFloat = _fromPcm(sbcPcm);

  // Try detection at various thresholds
  for (final double thr in [0.6, 0.5, 0.4, 0.3, 0.2]) {
    final int pos = preamble.detect(sbcFloat, threshold: thr);
    print('  SBC detection @ threshold $thr: pos=$pos '
        '(shift from clean: ${pos >= 0 ? pos - cleanPos : "N/A"})');
  }

  // Measure raw correlation profile around the expected position
  print('\nCorrelation profile (SBC signal):');
  _correlationProfile(sbcFloat, preamble, leadSilence);
}

void _correlationProfile(Float64List signal, DartPreamble preamble, int expectedPos) {
  // We can't access the internal reference directly, so approximate by
  // checking detection in a narrow window.
  final int refLen = 127; // ZC length

  // Manually correlate using the generated preamble's first half
  final fullPreamble = preamble.generate();
  final ref = Float64List(refLen);
  for (int i = 0; i < refLen; i++) {
    ref[i] = fullPreamble[i];
  }

  double refEnergy = 0;
  for (int i = 0; i < refLen; i++) {
    refEnergy += ref[i] * ref[i];
  }

  double maxCorr = 0;
  int maxPos = -1;
  for (int start = math.max(0, expectedPos - 100);
      start < math.min(signal.length - refLen, expectedPos + 200);
      start++) {
    double corr = 0;
    double sigEnergy = 0;
    for (int i = 0; i < refLen; i++) {
      corr += signal[start + i] * ref[i];
      sigEnergy += signal[start + i] * signal[start + i];
    }
    final double denom = math.sqrt(sigEnergy * refEnergy);
    if (denom < 1e-10) continue;
    final double norm = corr.abs() / denom;
    if (norm > maxCorr) {
      maxCorr = norm;
      maxPos = start;
    }
  }
  print('  Peak correlation: ${maxCorr.toStringAsFixed(3)} at position $maxPos '
      '(expected ~$expectedPos)');
}

Int16List _toPcm(Float64List signal) {
  double peak = 0;
  for (final s in signal) {
    peak = math.max(peak, s.abs());
  }
  if (peak < 1e-10) peak = 1;
  final scale = 0.8 * 32767.0 / peak;
  final out = Int16List(signal.length);
  for (int i = 0; i < signal.length; i++) {
    out[i] = (signal[i] * scale).round().clamp(-32767, 32767);
  }
  return out;
}

Float64List _fromPcm(Int16List pcm) {
  final out = Float64List(pcm.length);
  for (int i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] / 32767.0;
  }
  return out;
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
