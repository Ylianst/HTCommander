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
// dart_ldpc.dart - LDPC encoder and decoder for the DART modem.
//
// Implements IEEE 802.11n-style LDPC codes at block length 648.
// Supports rates 1/2, 2/3, 3/4, 5/6.
//
// Encoding: systematic — output is [information bits | parity bits].
// Decoding: min-sum belief propagation (iterative, soft-input soft-output).
//

import 'dart:typed_data';

/// LDPC code rate enumeration.
enum LdpcRate { r1_2, r2_3, r3_4, r5_6 }

/// LDPC code parameters for a given rate at block length 648.
class LdpcCode {
  /// Number of information bits (K).
  final int k;

  /// Total codeword length (N).
  final int n;

  /// Number of parity bits (M = N - K).
  int get m => n - k;

  /// Code rate.
  final LdpcRate rate;

  /// Parity-check matrix H stored in sparse form: for each check node (row),
  /// a list of variable-node (column) indices it connects to.
  final List<List<int>> checkNodeConnections;

  /// For each variable node (column), a list of check-node (row) indices.
  final List<List<int>> varNodeConnections;

  LdpcCode._({
    required this.k,
    required this.n,
    required this.rate,
    required this.checkNodeConnections,
    required this.varNodeConnections,
  });

  // --- Cached decoder edge structure (flat CSR form, built once) ---
  //
  // The message-passing decoder needs, for every check node, the flat index of
  // its edges, and for every variable node, the flat indices of the edges that
  // touch it. These depend only on the code, so they are computed once on first
  // use and reused for every decode — this is numerically identical to rebuilding
  // them on each call, it just avoids the per-decode allocation.
  Int32List? _checkEdgeStart;
  Int32List? _varEdgeStart;
  Int32List? _varEdgeIndex;
  int _totalEdges = -1;

  void _buildEdgeStructure() {
    final int mm = m;
    final int nn = n;

    // Prefix sum of check-node degrees: edges of check c occupy
    // [checkEdgeStart[c], checkEdgeStart[c+1]).
    final ces = Int32List(mm + 1);
    for (int c = 0; c < mm; c++) {
      ces[c + 1] = ces[c] + checkNodeConnections[c].length;
    }
    final int total = ces[mm];

    // Prefix sum of variable-node degrees.
    final ves = Int32List(nn + 1);
    for (int v = 0; v < nn; v++) {
      ves[v + 1] = ves[v] + varNodeConnections[v].length;
    }

    // Fill each variable's edge bucket in ascending (check, position) order —
    // the same order the previous List<_Edge> implementation used, so the
    // floating-point message summation order is unchanged (bit-identical).
    final vei = Int32List(total);
    final fill = Int32List(nn);
    for (int c = 0; c < mm; c++) {
      final conns = checkNodeConnections[c];
      final int base = ces[c];
      for (int j = 0; j < conns.length; j++) {
        final int v = conns[j];
        vei[ves[v] + fill[v]] = base + j;
        fill[v]++;
      }
    }

    _checkEdgeStart = ces;
    _varEdgeStart = ves;
    _varEdgeIndex = vei;
    _totalEdges = total;
  }

  /// Flat start index of each check node's edges (length m + 1).
  Int32List get checkEdgeStart {
    if (_checkEdgeStart == null) _buildEdgeStructure();
    return _checkEdgeStart!;
  }

  /// Flat start index of each variable node's edges (length n + 1).
  Int32List get varEdgeStart {
    if (_varEdgeStart == null) _buildEdgeStructure();
    return _varEdgeStart!;
  }

  /// For each variable node's edges (in [varEdgeStart] order), the flat edge
  /// index into the message arrays.
  Int32List get varEdgeIndex {
    if (_varEdgeIndex == null) _buildEdgeStructure();
    return _varEdgeIndex!;
  }

  /// Total number of edges in the Tanner graph.
  int get totalEdges {
    if (_totalEdges < 0) _buildEdgeStructure();
    return _totalEdges;
  }
}

/// LDPC encoder/decoder.
class DartLdpc {
  DartLdpc._();

  /// Maximum iterations for the decoder.
  static const int maxIterations = 50;

  /// Cache of built codes, keyed by rate. The parity-check matrix depends only
  /// on the rate, so it is built once and reused — [getCode] is called for
  /// every encoded and decoded block.
  static final Map<LdpcRate, LdpcCode> _codeCache = <LdpcRate, LdpcCode>{};

  /// Get the code for a given rate (built once, then cached).
  static LdpcCode getCode(LdpcRate rate) {
    final cached = _codeCache[rate];
    if (cached != null) return cached;
    final LdpcCode code = switch (rate) {
      LdpcRate.r1_2 => _buildCode(rate, 324, 648),
      LdpcRate.r2_3 => _buildCode(rate, 432, 648),
      LdpcRate.r3_4 => _buildCode(rate, 486, 648),
      LdpcRate.r5_6 => _buildCode(rate, 540, 648),
    };
    _codeCache[rate] = code;
    return code;
  }

  /// Encode information bits into a codeword (systematic: info | parity).
  /// [infoBits] must have length == code.k.
  /// Returns a Uint8List of length code.n (each element is 0 or 1).
  ///
  /// Uses O(M) accumulator encoding, which exploits the dual-diagonal parity
  /// structure built by [_buildCode]. For check row i:
  ///   syndrome_i = XOR of info bits connected to check i
  ///   p[0]       = syndrome_0
  ///   p[i]       = syndrome_i XOR p[i-1]   (i >= 1)
  /// This is exact and always succeeds, at every rate.
  static Uint8List encode(LdpcCode code, Uint8List infoBits) {
    if (infoBits.length != code.k) {
      throw ArgumentError(
        'Expected ${code.k} info bits, got ${infoBits.length}',
      );
    }

    final int k = code.k;
    final int m = code.m;
    final codeword = Uint8List(code.n);
    codeword.setRange(0, k, infoBits);

    // Compute the information syndrome for each check row (info bits only).
    final syndrome = Uint8List(m);
    for (int row = 0; row < m; row++) {
      int s = 0;
      for (final int col in code.checkNodeConnections[row]) {
        if (col < k) {
          s ^= infoBits[col];
        }
      }
      syndrome[row] = s;
    }

    // Accumulate parity bits: p[i] = syndrome[i] XOR p[i-1].
    int prev = 0;
    for (int i = 0; i < m; i++) {
      final int p = syndrome[i] ^ prev;
      codeword[k + i] = p;
      prev = p;
    }

    return codeword;
  }
  /// [llr] is an array of log-likelihood ratios (length code.n).
  /// Positive LLR → bit is likely 0, negative → bit is likely 1.
  /// Returns decoded information bits (length code.k), or null if decoding
  /// failed (max iterations reached without valid codeword).
  ///
  /// If [corrOut] (a 1-element array) is provided, the number of bit errors the
  /// decoder corrected — positions where the raw channel hard-decision differs
  /// from the final decoded codeword — is added to `corrOut[0]`.
  static Uint8List? decode(LdpcCode code, Float64List llr, {Int32List? corrOut}) {
    if (llr.length != code.n) {
      throw ArgumentError('Expected ${code.n} LLRs, got ${llr.length}');
    }

    final int numChecks = code.m;
    final int numVars = code.n;

    // Messages from variable nodes to check nodes: q[v][index_in_varNode_list]
    // Messages from check nodes to variable nodes: r[c][index_in_checkNode_list]
    // We use flat arrays indexed by edge for efficiency.

    // Edge structure (check/variable adjacency, flat CSR form) depends only on
    // the code, so it is built once and cached on [code] rather than rebuilt on
    // every decode. This is numerically identical to rebuilding it each call.
    final checkEdgeStart = code.checkEdgeStart;
    final varEdgeStart = code.varEdgeStart;
    final varEdgeIndex = code.varEdgeIndex;
    final int totalEdges = code.totalEdges;

    // r[edgeIndex] = check-to-variable message
    final r = Float64List(totalEdges);
    // q[edgeIndex] = variable-to-check message (initialized to channel LLR)
    final q = Float64List(totalEdges);

    // Initialize q messages to channel LLRs
    for (int c = 0; c < numChecks; c++) {
      final conns = code.checkNodeConnections[c];
      final int base = checkEdgeStart[c];
      for (int j = 0; j < conns.length; j++) {
        q[base + j] = llr[conns[j]];
      }
    }

    // Iterative decoding
    final hardDecision = Uint8List(numVars);

    for (int iter = 0; iter < maxIterations; iter++) {
      // --- Check node update (min-sum) ---
      for (int c = 0; c < numChecks; c++) {
        final int deg = code.checkNodeConnections[c].length;
        final int base = checkEdgeStart[c];

        // For each edge j in check node c:
        // r[c→v_j] = sign(product of signs excluding j) * min(|q| excluding j)
        // Efficient: compute total sign product and global min/second-min.
        int totalSign = 0; // count of negative signs (XOR parity)
        double minAbs = double.infinity;
        double secondMinAbs = double.infinity;
        int minIdx = 0;

        for (int j = 0; j < deg; j++) {
          final double val = q[base + j];
          if (val < 0) totalSign ^= 1;
          final double absVal = val.abs();
          if (absVal < minAbs) {
            secondMinAbs = minAbs;
            minAbs = absVal;
            minIdx = j;
          } else if (absVal < secondMinAbs) {
            secondMinAbs = absVal;
          }
        }

        for (int j = 0; j < deg; j++) {
          // Sign: total sign XOR this edge's sign
          int sign = totalSign;
          if (q[base + j] < 0) sign ^= 1;

          // Magnitude: min excluding j
          final double mag = (j == minIdx) ? secondMinAbs : minAbs;

          // Scale factor for min-sum (approximation to sum-product)
          r[base + j] = (sign == 1 ? -1.0 : 1.0) * mag * 0.75;
        }
      }

      // --- Variable node update ---
      for (int v = 0; v < numVars; v++) {
        final int vs = varEdgeStart[v];
        final int ve = varEdgeStart[v + 1];

        // Total LLR = channel + sum of all incoming check messages
        double totalLlr = llr[v];
        for (int e = vs; e < ve; e++) {
          totalLlr += r[varEdgeIndex[e]];
        }

        // Hard decision
        hardDecision[v] = totalLlr < 0 ? 1 : 0;

        // Outgoing messages: total - incoming from target check
        for (int e = vs; e < ve; e++) {
          final int edgeIdx = varEdgeIndex[e];
          q[edgeIdx] = totalLlr - r[edgeIdx];
        }
      }

      // --- Check if valid codeword ---
      if (_checkSyndrome(code, hardDecision)) {
        if (corrOut != null) corrOut[0] += _countCorrections(llr, hardDecision);
        return Uint8List.fromList(hardDecision.sublist(0, code.k));
      }
    }

    // Failed to converge — return hard decision anyway (caller checks CRC)
    if (corrOut != null) corrOut[0] += _countCorrections(llr, hardDecision);
    return Uint8List.fromList(hardDecision.sublist(0, code.k));
  }

  /// Count positions where the raw channel hard-decision (sign of the input
  /// LLR) differs from the decoded codeword — i.e. the bit errors corrected.
  static int _countCorrections(Float64List llr, Uint8List hardDecision) {
    int count = 0;
    for (int i = 0; i < hardDecision.length; i++) {
      final int channelBit = llr[i] < 0 ? 1 : 0;
      if (channelBit != hardDecision[i]) count++;
    }
    return count;
  }

  /// Check if the hard decision satisfies all parity checks (syndrome == 0).
  static bool _checkSyndrome(LdpcCode code, Uint8List bits) {
    for (int c = 0; c < code.m; c++) {
      int syndrome = 0;
      for (final int v in code.checkNodeConnections[c]) {
        syndrome ^= bits[v];
      }
      if (syndrome != 0) return false;
    }
    return true;
  }

  /// Build an LDPC code with a quasi-cyclic structure (802.11n style).
  /// The parity-check matrix is constructed from a base matrix expanded by
  /// a lifting factor Z.
  static LdpcCode _buildCode(LdpcRate rate, int k, int n) {
    final int m = n - k;
    final int z = _liftingFactor(rate);
    final baseMatrix = _getBaseMatrix(rate);
    final int baseColsInfo = k ~/ z;

    // Expand H = [ H_info | H_parity ].
    //
    // H_info: the information columns (0 .. K-1) come from the IEEE 802.11n
    // base matrix, expanded as quasi-cyclic circulants — this gives the codes
    // their good waterfall performance.
    //
    // H_parity: the parity columns (K .. N-1) are built as a bit-level
    // dual-diagonal (IRA accumulator) matrix instead of the 802.11n parity
    // circulants. A dual-diagonal parity part is always full rank, so every
    // rate (including R3/4, whose 802.11n parity submatrix is rank-deficient
    // under naive inversion) is guaranteed encodable in O(M) via a running
    // accumulator. Encoder and decoder both use this same H, so they stay
    // consistent.
    final checkNodeConnections = List<List<int>>.generate(m, (_) => []);
    final varNodeConnections = List<List<int>>.generate(n, (_) => []);

    // --- Information part (quasi-cyclic, from 802.11n base matrix) ---
    for (int br = 0; br < m ~/ z; br++) {
      for (int bc = 0; bc < baseColsInfo; bc++) {
        final int shift = baseMatrix[br][bc];
        if (shift < 0) continue; // -1 means no connection

        for (int i = 0; i < z; i++) {
          final int row = br * z + i;
          final int col = bc * z + ((i + shift) % z);
          checkNodeConnections[row].add(col);
          varNodeConnections[col].add(row);
        }
      }
    }

    // --- Parity part (bit-level dual-diagonal / accumulator) ---
    // Check row i connects to parity column (k + i), and additionally to
    // (k + i - 1) for i >= 1. This makes H_parity lower-bidiagonal.
    for (int i = 0; i < m; i++) {
      final int diag = k + i;
      checkNodeConnections[i].add(diag);
      varNodeConnections[diag].add(i);
      if (i >= 1) {
        final int sub = k + i - 1;
        checkNodeConnections[i].add(sub);
        varNodeConnections[sub].add(i);
      }
    }

    return LdpcCode._(
      k: k,
      n: n,
      rate: rate,
      checkNodeConnections: checkNodeConnections,
      varNodeConnections: varNodeConnections,
    );
  }

  /// Lifting factor Z for block length 648.
  static int _liftingFactor(LdpcRate rate) {
    // 802.11n uses Z=27 for N=648
    return 27;
  }

  /// Base matrix (prototype) for IEEE 802.11n LDPC, N=648.
  /// Each entry is a cyclic shift value (0..Z-1) or -1 (no connection).
  /// Rows = M/Z, Cols = N/Z = 24.
  ///
  /// Only the information columns (0 .. K/Z-1) of these matrices are used by
  /// [_buildCode]; the parity columns are replaced with a dual-diagonal
  /// accumulator structure so every rate is guaranteed encodable.
  static List<List<int>> _getBaseMatrix(LdpcRate rate) {
    switch (rate) {
      case LdpcRate.r1_2:
        return _baseMatrixR12;
      case LdpcRate.r2_3:
        return _baseMatrixR23;
      case LdpcRate.r3_4:
        return _baseMatrixR34;
      case LdpcRate.r5_6:
        return _baseMatrixR56;
    }
  }

  // IEEE 802.11n LDPC base matrices for N=648 (Z=27, 24 columns).
  // Rate 1/2: 12 rows × 24 columns
  static const _baseMatrixR12 = [
    [0, -1, -1, -1, 0, 0, -1, -1, 0, -1, -1, 0, 1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [22, 0, -1, -1, 17, -1, 0, 0, 12, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [6, -1, 0, -1, 10, -1, -1, -1, 24, -1, 0, -1, -1, -1, 0, 0, -1, -1, -1, -1, -1, -1, -1, -1],
    [2, -1, -1, 0, 20, -1, -1, -1, 25, 0, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1, -1, -1, -1],
    [23, -1, -1, -1, 3, -1, -1, -1, 0, -1, 9, 11, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1, -1, -1],
    [24, -1, 23, 1, 17, -1, 3, -1, 10, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1, -1],
    [25, -1, -1, -1, 8, -1, -1, -1, 7, 18, -1, -1, 0, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1],
    [13, 24, -1, -1, 0, -1, 8, -1, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1],
    [7, 20, -1, 16, 22, 10, -1, -1, 23, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, -1],
    [11, -1, -1, -1, 19, -1, -1, -1, 13, -1, 3, 17, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1],
    [25, -1, 8, -1, 23, 18, -1, 14, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0],
    [3, -1, -1, -1, 16, -1, -1, 2, 25, 5, -1, -1, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0],
  ];

  // Rate 2/3: 8 rows × 24 columns
  static const _baseMatrixR23 = [
    [25, 26, 14, -1, 20, -1, 2, -1, 4, -1, -1, 8, -1, 16, -1, 18, 1, 0, -1, -1, -1, -1, -1, -1],
    [10, 9, 15, 11, -1, 0, -1, 1, -1, -1, 18, -1, 8, -1, 10, -1, -1, 0, 0, -1, -1, -1, -1, -1],
    [16, 2, 20, 26, 21, -1, 6, -1, 1, 26, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1, -1],
    [10, 13, 5, 0, -1, 3, -1, 7, -1, -1, 26, -1, -1, 13, -1, 16, -1, -1, -1, 0, 0, -1, -1, -1],
    [23, 14, 24, -1, 12, -1, 19, -1, 17, -1, -1, -1, 20, -1, 21, -1, 0, -1, -1, -1, 0, 0, -1, -1],
    [6, 22, 9, 20, -1, 25, -1, 17, -1, 8, -1, 14, -1, 18, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1],
    [14, 23, 21, 11, 20, -1, 24, -1, 18, -1, 19, -1, -1, -1, -1, 22, -1, -1, -1, -1, -1, -1, 0, 0],
    [17, 11, 11, 20, -1, 21, -1, 26, -1, 3, -1, -1, 18, -1, 26, -1, 1, -1, -1, -1, -1, -1, -1, 0],
  ];

  // Rate 3/4: 6 rows × 24 columns
  static const _baseMatrixR34 = [
    [16, 17, 22, 24, 9, 3, 14, -1, 4, 2, 7, -1, 26, -1, 2, -1, 21, -1, 1, 0, -1, -1, -1, -1],
    [25, 12, 12, 3, 3, 26, 6, 21, -1, 15, 22, -1, 15, -1, 4, -1, -1, 16, -1, 0, 0, -1, -1, -1],
    [25, 18, 26, 16, 22, 23, 9, -1, 0, -1, 4, -1, -1, 21, 6, 1, -1, -1, -1, -1, 0, 0, -1, -1],
    [9, 7, 0, 1, 17, -1, -1, 7, 3, -1, -1, 12, -1, 10, 13, 24, -1, -1, -1, -1, -1, 0, 0, -1],
    [24, 5, 26, 7, 1, -1, -1, 15, 24, 15, -1, 8, -1, 13, -1, 13, -1, 11, -1, -1, -1, -1, 0, 0],
    [2, 2, 19, 14, 24, 1, 15, 19, -1, 21, -1, 2, -1, 24, -1, 3, -1, 2, 1, -1, -1, -1, -1, 0],
  ];

  // Rate 5/6: 4 rows × 24 columns
  static const _baseMatrixR56 = [
    [17, 13, 8, 21, 9, 3, 18, 12, 10, 0, 4, 15, 19, 2, 5, 10, 26, 19, 13, 13, 1, 0, -1, -1],
    [3, 12, 11, 14, 11, 25, 5, 18, 0, 9, 2, 26, 26, 10, 24, 7, 14, 20, 4, 2, -1, 0, 0, -1],
    [22, 16, 4, 3, 10, 21, 12, 5, 21, 14, 19, 5, -1, 8, 5, 18, 11, 5, 5, 15, 0, -1, 0, 0],
    [7, 7, 14, 14, 4, 16, 16, 24, 24, 10, 1, 7, 15, 6, 10, 26, 8, 18, 21, 14, 1, -1, -1, 0],
  ];
}
