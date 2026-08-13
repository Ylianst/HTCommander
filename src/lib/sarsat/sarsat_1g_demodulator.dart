/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Coherent demodulator for COSPAS-SARSAT 406 MHz v1g beacons.
///
/// The 406 v1g signal is a carrier phase-modulated by ±1.1 rad, biphase-L
/// (Manchester) encoded at 400 bps. This demodulator recovers the bit stream
/// from a real-valued audio recording of that signal (e.g. an SSB/CW receiver
/// output, or a discriminator/`rtl_fm` feed) and hands complete frames to
/// [Sarsat1gDecoder].
///
/// Chain: DC block → carrier estimate → quadrature mix + low-pass → residual
/// carrier de-rotation → matched-filter sync search → biphase-L slicer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'sarsat_1g_decoder.dart';

class Sarsat1gDemodulator {
  final int sampleRate;

  /// Nominal audio carrier frequency (Hz). The demodulator searches ±250 Hz
  /// around this for the true residual carrier.
  final double nominalCarrierHz;

  Sarsat1gDemodulator(this.sampleRate, {this.nominalCarrierHz = 1400});

  static const int _symbolRate = 400;
  static const String _bitSync = '111111111111111';
  static const String _fsyncNormal = '000101111';

  /// Demodulates [pcm] and returns every distinct BCH-valid frame found.
  List<Sarsat1gFrame> decode(Int16List pcm) {
    final n = pcm.length;
    if (n < sampleRate ~/ 4) return const [];

    // 1. DC block.
    final x = Float64List(n);
    double mean = 0;
    for (int i = 0; i < n; i++) {
      mean += pcm[i];
    }
    mean /= n;
    for (int i = 0; i < n; i++) {
      x[i] = pcm[i] - mean;
    }

    // 2. Carrier estimate: residual-carrier magnitude peaks at the true fc.
    final fc = _estimateCarrier(x);

    // 3. Quadrature mix + low-pass to baseband I/Q.
    final w = 2 * math.pi * fc / sampleRate;
    final iRaw = Float64List(n);
    final qRaw = Float64List(n);
    for (int i = 0; i < n; i++) {
      final c = math.cos(w * i);
      final s = math.sin(w * i);
      iRaw[i] = x[i] * c;
      qRaw[i] = -x[i] * s;
    }
    // Low-pass with a boxcar sized to null the 2*fc image.
    final lp = math.max(3, (sampleRate / (2 * fc)).round());
    final iBb = _boxcar(iRaw, lp);
    final qBb = _boxcar(qRaw, lp);

    // 4. De-rotate by the residual-carrier phase so modulation sits about 0.
    double dcI = 0, dcQ = 0;
    for (int i = 0; i < n; i++) {
      dcI += iBb[i];
      dcQ += qBb[i];
    }
    final dcMag = math.sqrt(dcI * dcI + dcQ * dcQ);
    if (dcMag == 0) return const [];
    dcI /= dcMag;
    dcQ /= dcMag;
    final phase = Float64List(n);
    for (int i = 0; i < n; i++) {
      final ir = iBb[i] * dcI + qBb[i] * dcQ;
      final qr = qBb[i] * dcI - iBb[i] * dcQ;
      phase[i] = math.atan2(qr, ir);
    }

    // Prefix sums for O(1) half-bit averaging.
    final pref = Float64List(n + 1);
    for (int i = 0; i < n; i++) {
      pref[i + 1] = pref[i] + phase[i];
    }
    double meanRange(double lo, double hi) {
      int a = lo.round();
      int b = hi.round();
      if (a < 0) a = 0;
      if (b > n) b = n;
      if (b <= a) return 0;
      return (pref[b] - pref[a]) / (b - a);
    }

    // 5. Matched-filter sync search over the phase (both polarities).
    final anchors = _findSyncAnchors(phase);

    // 6. Slice + decode at each anchor.
    final results = <String, Sarsat1gFrame>{};
    final hb = sampleRate / (2 * _symbolRate);
    for (final s in anchors) {
      for (final polarity in const [1, -1]) {
        final bits = List<int>.filled(144, 0);
        for (int k = 0; k < 144; k++) {
          final b0 = meanRange(s + 2 * k * hb, s + (2 * k + 1) * hb);
          final b1 = meanRange(s + (2 * k + 1) * hb, s + (2 * k + 2) * hb);
          final one = polarity > 0 ? (b0 > b1) : (b0 < b1);
          bits[k] = one ? 1 : 0;
        }
        if (!Sarsat1gDecoder.hasSync(bits)) continue;
        final len = bits[24] == 1 ? 144 : 112;
        final frame = Sarsat1gDecoder.decode(bits.sublist(0, len));
        if (frame == null) continue;
        final ok = frame.crc1Ok && (len == 112 || frame.crc2Ok);
        if (!ok) continue;
        results[frame.bits.join()] = frame;
      }
    }
    return results.values.toList();
  }

  double _estimateCarrier(Float64List x) {
    final n = x.length;
    double bestF = nominalCarrierHz;
    double bestMag = -1;
    for (double f = nominalCarrierHz - 250; f <= nominalCarrierHz + 250; f += 1.0) {
      final w = 2 * math.pi * f / sampleRate;
      double si = 0, sq = 0;
      for (int i = 0; i < n; i++) {
        si += x[i] * math.cos(w * i);
        sq += x[i] * math.sin(w * i);
      }
      final mag = si * si + sq * sq;
      if (mag > bestMag) {
        bestMag = mag;
        bestF = f;
      }
    }
    return bestF;
  }

  static Float64List _boxcar(Float64List x, int len) {
    final n = x.length;
    final out = Float64List(n);
    if (len <= 1) {
      out.setAll(0, x);
      return out;
    }
    double acc = 0;
    for (int i = 0; i < n; i++) {
      acc += x[i];
      if (i >= len) acc -= x[i - len];
      final count = i < len ? i + 1 : len;
      out[i] = acc / count;
    }
    return out;
  }

  // Correlate the 24-bit sync waveform against the phase; return candidate
  // frame-start sample offsets (peaks of |correlation|).
  List<double> _findSyncAnchors(Float64List phase) {
    final n = phase.length;
    final hb = sampleRate / (2 * _symbolRate);
    final syncBits = _bitSync + _fsyncNormal;
    final tmplLen = (syncBits.length * 2 * hb).round();
    // Build ±1 template at sample resolution.
    final tmpl = Float64List(tmplLen);
    for (int i = 0; i < tmplLen; i++) {
      final half = (i / hb).floor(); // which half-bit
      final bitIdx = half >> 1;
      final firstHalf = (half & 1) == 0;
      final one = syncBits[bitIdx] == '1';
      // '1' -> [+,-], '0' -> [-,+]
      final level = (one == firstHalf) ? 1.0 : -1.0;
      tmpl[i] = level;
    }
    final corr = Float64List(n - tmplLen);
    double maxAbs = 0;
    for (int s = 0; s < corr.length; s++) {
      double acc = 0;
      for (int i = 0; i < tmplLen; i++) {
        acc += phase[s + i] * tmpl[i];
      }
      corr[s] = acc;
      final a = acc.abs();
      if (a > maxAbs) maxAbs = a;
    }
    final thr = maxAbs * 0.5;
    final guard = tmplLen ~/ 2;
    final peaks = <double>[];
    int i = 0;
    while (i < corr.length) {
      if (corr[i].abs() >= thr) {
        int j = i;
        double bestV = corr[i].abs();
        int bestIdx = i;
        while (j < corr.length && j < i + guard) {
          if (corr[j].abs() > bestV) {
            bestV = corr[j].abs();
            bestIdx = j;
          }
          j++;
        }
        peaks.add(bestIdx.toDouble());
        i = bestIdx + guard;
      } else {
        i++;
      }
    }
    return peaks;
  }
}

/// Generates an ideal 406 v1g audio signal from a frame's bits. Used to verify
/// the demodulator by round-trip (and to characterise it under noise).
class Sarsat1gModulator {
  /// Builds PCM for [frameBits] (must start with the 15-bit sync + frame sync).
  ///
  /// A `'1'` bit is transmitted as biphase-L half-bits (+delta, -delta) of
  /// carrier phase; a `'0'` as (-delta, +delta) — matching the demodulator.
  static Int16List modulate(
    List<int> frameBits, {
    required int sampleRate,
    double carrierHz = 1400,
    double deltaRad = 1.1,
    int preambleMs = 120,
    double amplitude = 12000,
    double noiseStdDev = 0,
    int seed = 1,
  }) {
    final hb = sampleRate / 800.0; // samples per half-bit (400 bps)
    final preamble = (sampleRate * preambleMs / 1000).round();
    final total = preamble + (frameBits.length * 2 * hb).round();
    final out = Int16List(total);
    final rnd = math.Random(seed);
    final w = 2 * math.pi * carrierHz / sampleRate;
    for (int i = 0; i < total; i++) {
      double ph = 0;
      if (i >= preamble) {
        final halfIndex = ((i - preamble) / hb).floor();
        final bitIdx = halfIndex >> 1;
        if (bitIdx < frameBits.length) {
          final firstHalf = (halfIndex & 1) == 0;
          final one = frameBits[bitIdx] == 1;
          final positiveFirst = one; // '1' -> +delta first
          ph = (firstHalf == positiveFirst) ? deltaRad : -deltaRad;
        }
      }
      double v = amplitude * math.cos(w * i + ph);
      if (noiseStdDev > 0) {
        v += _gaussian(rnd) * noiseStdDev;
      }
      out[i] = v.clamp(-32768, 32767).round();
    }
    return out;
  }

  static double _gaussian(math.Random r) {
    final u1 = r.nextDouble().clamp(1e-12, 1.0);
    final u2 = r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
