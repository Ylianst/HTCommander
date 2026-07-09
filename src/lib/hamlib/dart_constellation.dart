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
// dart_constellation.dart - Constellation mapper and soft demapper for DART.
//
// Supports BPSK, QPSK, 8PSK, and 16QAM.
// Mapper: bits → complex symbols (I/Q).
// Demapper: received I/Q + noise variance → per-bit LLRs (soft output).
//

import 'dart:math' as math;
import 'dart:typed_data';

/// A complex number (I + jQ).
class Complex {
  final double i;
  final double q;
  const Complex(this.i, this.q);

  Complex operator +(Complex other) => Complex(i + other.i, q + other.q);
  Complex operator -(Complex other) => Complex(i - other.i, q - other.q);
  Complex operator *(Complex other) =>
      Complex(i * other.i - q * other.q, i * other.q + q * other.i);
  Complex operator /(double scalar) => Complex(i / scalar, q / scalar);
  Complex scale(double s) => Complex(i * s, q * s);
  double get magnitude => math.sqrt(i * i + q * q);
  double get magnitudeSquared => i * i + q * q;
  double get phase => math.atan2(q, i);
  Complex get conjugate => Complex(i, -q);

  @override
  String toString() => '(${i.toStringAsFixed(3)} + ${q.toStringAsFixed(3)}j)';
}

/// Constellation type.
enum ConstellationType { bpsk, qpsk, psk8, qam16 }

/// Constellation definition: maps bit patterns to complex symbols.
class Constellation {
  /// Constellation type.
  final ConstellationType type;

  /// Bits per symbol.
  final int bitsPerSymbol;

  /// Constellation points indexed by Gray-coded bit pattern.
  final List<Complex> points;

  const Constellation._({
    required this.type,
    required this.bitsPerSymbol,
    required this.points,
  });

  /// Get a constellation by type.
  static Constellation get(ConstellationType type) {
    switch (type) {
      case ConstellationType.bpsk:
        return _bpsk;
      case ConstellationType.qpsk:
        return _qpsk;
      case ConstellationType.psk8:
        return _psk8;
      case ConstellationType.qam16:
        return _qam16;
    }
  }

  /// Map a group of bits to a complex symbol.
  /// [bits] is a list of 0/1 values, length == bitsPerSymbol.
  Complex map(List<int> bits) {
    int index = 0;
    for (int b = 0; b < bitsPerSymbol; b++) {
      index = (index << 1) | bits[b];
    }
    return points[index];
  }

  /// Map a bit stream to symbols. Length of [bits] must be a multiple of
  /// bitsPerSymbol.
  List<Complex> mapBits(Uint8List bits) {
    if (bits.length % bitsPerSymbol != 0) {
      throw ArgumentError(
        'Bit count ${bits.length} not a multiple of $bitsPerSymbol',
      );
    }
    final int numSymbols = bits.length ~/ bitsPerSymbol;
    final symbols = List<Complex>.filled(numSymbols, const Complex(0, 0));
    for (int s = 0; s < numSymbols; s++) {
      int index = 0;
      final int offset = s * bitsPerSymbol;
      for (int b = 0; b < bitsPerSymbol; b++) {
        index = (index << 1) | bits[offset + b];
      }
      symbols[s] = points[index];
    }
    return symbols;
  }

  /// Compute approximate LLRs for each bit from a received symbol.
  /// Uses max-log-MAP approximation:
  ///   LLR(b_k) ≈ min_{s: b_k=1} |r-s|² - min_{s: b_k=0} |r-s|²
  /// divided by noise variance (σ²). Positive → bit is 0, negative → bit is 1.
  Float64List softDemap(Complex received, double noiseVariance) {
    final llrs = Float64List(bitsPerSymbol);
    final double invVar = 1.0 / noiseVariance;

    for (int b = 0; b < bitsPerSymbol; b++) {
      double minDist0 = double.infinity;
      double minDist1 = double.infinity;

      for (int idx = 0; idx < points.length; idx++) {
        final double di = received.i - points[idx].i;
        final double dq = received.q - points[idx].q;
        final double dist = di * di + dq * dq;

        // Check if bit b of idx is 0 or 1
        final int bitVal = (idx >> (bitsPerSymbol - 1 - b)) & 1;
        if (bitVal == 0) {
          if (dist < minDist0) minDist0 = dist;
        } else {
          if (dist < minDist1) minDist1 = dist;
        }
      }

      llrs[b] = (minDist1 - minDist0) * invVar;
    }
    return llrs;
  }

  /// Return the nearest constellation point to [received] (hard decision).
  /// Used for EVM / signal-quality measurement.
  Complex nearestPoint(Complex received) {
    double bestDist = double.infinity;
    Complex best = points[0];
    for (final p in points) {
      final double di = received.i - p.i;
      final double dq = received.q - p.q;
      final double dist = di * di + dq * dq;
      if (dist < bestDist) {
        bestDist = dist;
        best = p;
      }
    }
    return best;
  }

  // --- Constellation definitions (Gray-coded, unit average power) ---

  // BPSK: 1 bit/symbol, points at ±1
  static const _bpsk = Constellation._(
    type: ConstellationType.bpsk,
    bitsPerSymbol: 1,
    points: [
      Complex(1.0, 0.0), // bit 0
      Complex(-1.0, 0.0), // bit 1
    ],
  );

  // QPSK: 2 bits/symbol, Gray coded
  // Average power = 1.0 (each point at 1/√2)
  static final _qpsk = Constellation._(
    type: ConstellationType.qpsk,
    bitsPerSymbol: 2,
    points: [
      Complex(_invSqrt2, _invSqrt2), // 00
      Complex(_invSqrt2, -_invSqrt2), // 01
      Complex(-_invSqrt2, _invSqrt2), // 10
      Complex(-_invSqrt2, -_invSqrt2), // 11
    ],
  );

  // 8PSK: 3 bits/symbol, Gray coded, unit circle
  static final _psk8 = Constellation._(
    type: ConstellationType.psk8,
    bitsPerSymbol: 3,
    points: _build8Psk(),
  );

  // 16QAM: 4 bits/symbol, Gray coded, normalized to unit average power
  static final _qam16 = Constellation._(
    type: ConstellationType.qam16,
    bitsPerSymbol: 4,
    points: _build16Qam(),
  );

  static final double _invSqrt2 = 1.0 / math.sqrt(2.0);

  /// Build 8PSK constellation (Gray coded on unit circle).
  /// Gray code ordering: 000,001,011,010,110,111,101,100
  static List<Complex> _build8Psk() {
    // Gray code mapping: symbol index → phase index
    const grayOrder = [0, 1, 3, 2, 6, 7, 5, 4];
    final points = List<Complex>.filled(8, const Complex(0, 0));
    for (int i = 0; i < 8; i++) {
      final double angle = grayOrder[i] * math.pi / 4.0;
      points[i] = Complex(math.cos(angle), math.sin(angle));
    }
    return points;
  }

  /// Build 16QAM constellation (Gray coded, unit average power).
  /// 4×4 grid at ±1, ±3 (normalized by √10 for unit average power).
  static List<Complex> _build16Qam() {
    // Gray code for each axis: 0→-3, 1→-1, 3→+1, 2→+3
    const axisMap = [-3.0, -1.0, 1.0, 3.0];
    // Gray code order for 2 bits: 00→0, 01→1, 11→2, 10→3
    const grayToIndex = [0, 1, 3, 2];

    final double norm = 1.0 / math.sqrt(10.0); // normalizes average power to 1
    final points = List<Complex>.filled(16, const Complex(0, 0));

    for (int bits = 0; bits < 16; bits++) {
      final int iGray = (bits >> 2) & 0x3;
      final int qGray = bits & 0x3;
      final double iVal = axisMap[grayToIndex[iGray]] * norm;
      final double qVal = axisMap[grayToIndex[qGray]] * norm;
      points[bits] = Complex(iVal, qVal);
    }
    return points;
  }
}
