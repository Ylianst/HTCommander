/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Rate-1/2, constraint-length-7 convolutional codec used by LMS6 radiosondes
(generator polynomials 0x4F and 0x6D). [encode] produces two output bits per
message bit; [deconv] is the reference hard-decision deconvolution decoder
(exact on error-free input), matching `deconv()` in lms6Xmod.c.
*/

library;

/// LMS6 convolutional codec (rate 1/2, K=7).
class ConvCodec {
  static const List<int> polyA = [1, 0, 0, 1, 1, 1, 1]; // 0x4F
  static const List<int> polyB = [1, 1, 0, 1, 1, 0, 1]; // 0x6D
  static const int m = 6; // L - 1

  /// Encodes [bits] (with [m] implicit leading zeros in the register) to twice
  /// as many output bits: raw[2k]=cA, raw[2k+1]=cB.
  static List<int> encode(List<int> bits) {
    final len = bits.length;
    final raw = List<int>.filled(2 * len, 0);
    for (int k = 0; k < len; k++) {
      int cA = 0, cB = 0;
      for (int j = 0; j <= m; j++) {
        final idx = k - m + j;
        final b = idx >= 0 ? bits[idx] : 0;
        cA ^= b & polyA[j];
        cB ^= b & polyB[j];
      }
      raw[2 * k] = cA;
      raw[2 * k + 1] = cB;
    }
    return raw;
  }

  /// Hard-decision deconvolution: recovers the message bits from [raw]
  /// (2 bits/symbol). Returns null if an inconsistency (bit error) is found.
  static List<int>? deconv(List<int> raw) {
    final total = raw.length;
    final maxBits = total ~/ 2;
    final bits = List<int>.filled(maxBits + m + 1, 0);
    int n = 0;
    while (2 * (m + n) + 1 < total) {
      final p0 = raw[2 * (m + n)];
      final p1 = raw[2 * (m + n) + 1];
      int bitA = 0, bitB = 0;
      for (int j = 0; j < m; j++) {
        bitA ^= bits[n + j] & polyA[j];
        bitB ^= bits[n + j] & polyB[j];
      }
      if ((bitA ^ p0) == polyA[m] && (bitB ^ p1) == polyB[m]) {
        bits[n + m] = 1;
      } else if ((bitA ^ p0) == 0 && (bitB ^ p1) == 0) {
        bits[n + m] = 0;
      } else {
        return null; // uncorrectable (needs Viterbi)
      }
      n++;
    }
    return bits.sublist(0, n + m);
  }
}
