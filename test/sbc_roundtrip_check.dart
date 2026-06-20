// SBC encode -> decode round-trip quality check.
//
// ignore_for_file: avoid_print  (diagnostic script: printing is the point)
//
// Purpose:
//   Sanity-checks the SBC codec port end to end by encoding pure sine tones to
//   mSBC and decoding them back, then measuring the reconstruction SNR. It is a
//   regression guard for the analysis/synthesis filterbank: a broken analysis
//   window (see the history below) produces a flat ~5-9 dB SNR at every
//   bitpool, while a correct filterbank yields ~60-70 dB.
//
// Background (filterbank bugs that were fixed):
//   The C# source this port came from had two analysis-filter bugs (documented
//   in lib/sbc/sbc_encoder_tables.dart and lib/sbc/sbc_encoder.dart):
//     1. The second polyphase window table (w1) was missing - the single window
//        was repeated with period 5, so the second half silently re-used w0.
//     2. A spurious w1 term was added to the DC-symmetric output (y3 / y7).
//   Both aliased energy into the upper subbands. The reference implementation
//   is reference/libsbc/src/sbc.c (Google's libsbc).
//
// How to run:
//   dart run test/sbc_roundtrip_check.dart
//
// Expected output: SNR of roughly 60+ dB for each test frequency.
//
// Note: this is a standalone diagnostic script (prints results), not a
//   package:test suite. It is kept because it is handy for validating future
//   changes to the codec.

import 'dart:math';
import 'dart:typed_data';

import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

double snrFor(double freq) {
  const int sampleRate = 16000;
  const int frameSamples = 120; // mSBC: 15 blocks * 8 subbands
  const int numFrames = 40;
  final int total = frameSamples * numFrames;
  final Int16List pcm = Int16List(total);
  for (int i = 0; i < total; i++) {
    pcm[i] = (sin(2 * pi * freq * i / sampleRate) * 16000).round();
  }

  final SbcEncoder enc = SbcEncoder();
  final SbcDecoder dec = SbcDecoder();
  final List<int> outSamples = <int>[];
  for (int f = 0; f < numFrames; f++) {
    final Int16List chunk = Int16List.sublistView(
      pcm,
      f * frameSamples,
      (f + 1) * frameSamples,
    );
    final Uint8List? sbc = enc.encode(chunk, null, SbcFrame.createMsbc());
    if (sbc == null) {
      print('  encode returned null at frame $f');
      return double.nan;
    }
    final res = dec.decode(sbc);
    if (!res.success) {
      print('  decode failed at frame $f');
      return double.nan;
    }
    for (final int s in res.pcmLeft) {
      outSamples.add(s);
    }
  }

  // Find best alignment delay via cross-correlation.
  int bestDelay = 0;
  double bestCorr = -1e30;
  for (int d = 0; d < 200; d++) {
    double c = 0;
    for (int i = 0; i + d < total && i < outSamples.length; i++) {
      c += pcm[i].toDouble() * outSamples[i + d];
    }
    if (c > bestCorr) {
      bestCorr = c;
      bestDelay = d;
    }
  }

  // Compute SNR over aligned region, skipping filter warmup.
  const int skip = 240;
  double sig = 0, err = 0;
  for (int i = skip; i + bestDelay < outSamples.length && i < total; i++) {
    final double s = pcm[i].toDouble();
    final double o = outSamples[i + bestDelay].toDouble();
    sig += s * s;
    err += (s - o) * (s - o);
  }
  if (err == 0) return double.infinity;
  final double snr = 10 * (log(sig / err) / ln10);
  print('  freq=$freq delay=$bestDelay SNR=${snr.toStringAsFixed(2)} dB');
  return snr;
}

void main() {
  for (final double f in <double>[500, 1000, 2000, 4000]) {
    snrFor(f);
  }
}
