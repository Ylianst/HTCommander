/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Bell-202 AFSK (1200 baud, 8N1) demodulator for InterMet iMet radiosondes from
FM-discriminator audio. A recursive sliding-DFT compares energy at the mark
(1200 Hz) and space (2200 Hz) tones to produce a per-sample bit decision; the
NRZ bit stream is then reconstructed from tone transitions and deframed as
async 8N1 bytes for [ImetDecoder]. Mirrors the reference `imet1rs_dft.c`.
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Recovers the iMet byte stream from FM-demodulated Bell-202 AFSK audio.
class ImetDemodulator {
  ImetDemodulator(this.sampleRate);

  final int sampleRate;

  static const int _baud = 1200;
  static const double _fSpace = 2200.0; // bit 0
  static const double _fMark = 1200.0; // bit 1

  /// Demodulates [pcm] and returns the recovered async byte stream.
  List<int> demodulate(Int16List pcm) {
    final n = pcm.length;
    final bitlen = sampleRate / _baud;
    final win = (2 * bitlen + 0.5).floor();
    if (n < win * 4) return const [];

    // Sample buffer normalized to [-1, 1].
    final x = Float64List(n);
    for (int i = 0; i < n; i++) {
      x[i] = pcm[i] / 32768.0;
    }

    // Recursive sliding-DFT at mark and space tones.
    final bit = Uint8List(n);
    double f1I = 0, f1Q = 0, f2I = 0, f2Q = 0; // running DFT sums
    final twoPi = 2 * math.pi;
    for (int i = 0; i < n; i++) {
      final xi = x[i];
      final x0 = i >= win ? x[i - win] : 0.0;
      // phase for current and outgoing sample (fractional to keep precision).
      final a1 = twoPi * (_frac(_fSpace * i / sampleRate));
      final a2 = twoPi * (_frac(_fMark * i / sampleRate));
      final b1 = twoPi * (_frac(_fSpace * (i - win) / sampleRate));
      final b2 = twoPi * (_frac(_fMark * (i - win) / sampleRate));
      f1I += xi * math.cos(a1) - x0 * math.cos(b1);
      f1Q += -xi * math.sin(a1) + x0 * math.sin(b1);
      f2I += xi * math.cos(a2) - x0 * math.cos(b2);
      f2Q += -xi * math.sin(a2) + x0 * math.sin(b2);
      final mag2 = f2I * f2I + f2Q * f2Q; // mark
      final mag1 = f1I * f1I + f1Q * f1Q; // space
      bit[i] = mag2 >= mag1 ? 1 : 0;
    }

    // Reconstruct the NRZ bit sequence from tone transitions.
    final bits = <int>[];
    int prev = bit[win];
    int prevPos = win;
    for (int i = win + 1; i < n; i++) {
      if (bit[i] != prev) {
        final cnt = ((i - prevPos) / bitlen).round();
        for (int c = 0; c < cnt; c++) {
          bits.add(prev);
        }
        prev = bit[i];
        prevPos = i;
      }
    }
    // Flush the trailing run (no terminating edge) so the final byte's high
    // bits + stop bit are present; cap to avoid a huge idle tail.
    final tail = ((n - 1 - prevPos) / bitlen).round();
    for (int c = 0; c < tail && c < 12; c++) {
      bits.add(prev);
    }

    // Deframe async 8N1: start(0) + 8 data (LSB-first) + stop(1).
    final bytes = <int>[];
    int p = 0;
    final len = bits.length;
    while (p + 9 < len) {
      if (bits[p] != 0) {
        p++;
        continue;
      }
      if (bits[p + 9] != 1) {
        p++;
        continue;
      }
      int byte = 0;
      for (int k = 0; k < 8; k++) {
        if (bits[p + 1 + k] == 1) byte |= 1 << k;
      }
      bytes.add(byte);
      p += 10;
    }
    return bytes;
  }

  static double _frac(double v) => v - v.floorToDouble();
}
