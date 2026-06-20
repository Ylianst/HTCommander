/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

/// Windowing coefficient tables and matrices for SBC encoder analysis filter.
class SbcEncoderTables {
  SbcEncoderTables._();

  // ---------------------------------------------------------------------------
  // NOTE ON TWO C# SOURCE BUGS (both fixed here in the Dart port):
  //
  // Source of truth: reference/libsbc/src/sbc.c (analyze_4 / analyze_8). The
  // Dart encoder output is now byte-for-byte identical to libsbc.
  //
  // libsbc stores the analysis window as TWO separate tables, `window[2][n][5*2]`:
  //   - window[0] (w0): coefficients for the FIRST polyphase half.
  //   - window[1] (w1): coefficients for the SECOND half ("inverse parity,
  //     starting the previous block").
  // The analysis reads w0[i][idx+j] and w1[i][idx+j] (j = 0..4); the two tables
  // hold DIFFERENT values.
  //
  // BUG 1 (this file) - missing second window table.
  //   The C# port (reference/HTCommander/src/sbc) tried to merge the two tables
  //   into a single 20-wide row and read the second half from the same row at
  //   window[i][idx + 5 + j]. That cannot work: the first half needs row
  //   positions 0..8 and the second half needs positions 5..13, so they overlap
  //   at 5..8. The C# author worked around the conflict by repeating w0 with
  //   period 5, which makes window[i][idx + 5 + j] == window[i][idx + j]: the
  //   second half silently re-uses w0 and w1 is dropped entirely.
  //   Fix: keep the original w0 tables (`window4`/`window8`) and add the
  //   missing w1 tables (`window4b`/`window8b`); see SbcEncoder._analyze4/8.
  //
  // BUG 2 (see SbcEncoder._analyze4 / _analyze8) - spurious second-half term on
  //   the DC-symmetric output. The C# code added an extra w1 contribution to
  //   y3 (4 subbands) / y7 (8 subbands). In libsbc those outputs are
  //   y = x[1] * w0[1] only, with NO second-half term. The Dart port removes
  //   the extra term.
  //
  // Together these bugs aliased energy into the upper subbands and broke the
  // analysis filterbank (~5-9 dB SNR regardless of bitpool). With both fixed,
  // round-trip SNR is ~60-70 dB.
  //
  // TODO: The upstream C# implementation should be corrected the same way
  //       (add the second window table; drop the extra w1 term on y3/y7).
  // ---------------------------------------------------------------------------

  /// First-half windowing coefficients for 4 subbands (fixed 2.13).
  /// Mirrors libsbc analyze_4 `window[0]`. Period-5, doubled to 10 per row.
  static final List<Int16List> window4 = <Int16List>[
    Int16List.fromList(const <int>[
      0,
      358,
      4443,
      -4443,
      -358,
      0,
      358,
      4443,
      -4443,
      -358,
    ]),
    Int16List.fromList(const <int>[
      49,
      946,
      8082,
      -944,
      61,
      49,
      946,
      8082,
      -944,
      61,
    ]),
    Int16List.fromList(const <int>[
      18,
      670,
      6389,
      -2544,
      -100,
      18,
      670,
      6389,
      -2544,
      -100,
    ]),
    Int16List.fromList(const <int>[
      90,
      1055,
      9235,
      201,
      128,
      90,
      1055,
      9235,
      201,
      128,
    ]),
  ];

  /// Second-half windowing coefficients for 4 subbands (fixed 2.13).
  /// Mirrors libsbc analyze_4 `window[1]`. Period-5, doubled to 10 per row.
  static final List<Int16List> window4b = <Int16List>[
    Int16List.fromList(const <int>[
      126,
      848,
      9644,
      848,
      126,
      126,
      848,
      9644,
      848,
      126,
    ]),
    Int16List.fromList(const <int>[
      61,
      -944,
      8082,
      946,
      49,
      61,
      -944,
      8082,
      946,
      49,
    ]),
    Int16List.fromList(const <int>[
      128,
      201,
      9235,
      1055,
      90,
      128,
      201,
      9235,
      1055,
      90,
    ]),
    Int16List.fromList(const <int>[
      -100,
      -2544,
      6389,
      670,
      18,
      -100,
      -2544,
      6389,
      670,
      18,
    ]),
  ];

  /// First-half windowing coefficients for 8 subbands (fixed 2.13).
  /// Mirrors libsbc analyze_8 `window[0]`. Period-5, doubled to 10 per row.
  static final List<Int16List> window8 = <Int16List>[
    Int16List.fromList(const <int>[
      0,
      185,
      2228,
      -2228,
      -185,
      0,
      185,
      2228,
      -2228,
      -185,
    ]),
    Int16List.fromList(const <int>[
      27,
      480,
      4039,
      -480,
      30,
      27,
      480,
      4039,
      -480,
      30,
    ]),
    Int16List.fromList(const <int>[
      5,
      263,
      2719,
      -1743,
      -115,
      5,
      263,
      2719,
      -1743,
      -115,
    ]),
    Int16List.fromList(const <int>[
      58,
      502,
      4764,
      290,
      69,
      58,
      502,
      4764,
      290,
      69,
    ]),
    Int16List.fromList(const <int>[
      11,
      343,
      3197,
      -1280,
      -54,
      11,
      343,
      3197,
      -1280,
      -54,
    ]),
    Int16List.fromList(const <int>[
      48,
      532,
      4612,
      96,
      65,
      48,
      532,
      4612,
      96,
      65,
    ]),
    Int16List.fromList(const <int>[
      18,
      418,
      3644,
      -856,
      -6,
      18,
      418,
      3644,
      -856,
      -6,
    ]),
    Int16List.fromList(const <int>[
      37,
      521,
      4367,
      -161,
      53,
      37,
      521,
      4367,
      -161,
      53,
    ]),
  ];

  /// Second-half windowing coefficients for 8 subbands (fixed 2.13).
  /// Mirrors libsbc analyze_8 `window[1]`. Period-5, doubled to 10 per row.
  static final List<Int16List> window8b = <Int16List>[
    Int16List.fromList(const <int>[
      66,
      424,
      4815,
      424,
      66,
      66,
      424,
      4815,
      424,
      66,
    ]),
    Int16List.fromList(const <int>[
      30,
      -480,
      4039,
      480,
      27,
      30,
      -480,
      4039,
      480,
      27,
    ]),
    Int16List.fromList(const <int>[
      69,
      290,
      4764,
      502,
      58,
      69,
      290,
      4764,
      502,
      58,
    ]),
    Int16List.fromList(const <int>[
      -115,
      -1743,
      2719,
      263,
      5,
      -115,
      -1743,
      2719,
      263,
      5,
    ]),
    Int16List.fromList(const <int>[
      65,
      96,
      4612,
      532,
      48,
      65,
      96,
      4612,
      532,
      48,
    ]),
    Int16List.fromList(const <int>[
      -54,
      -1280,
      3197,
      343,
      11,
      -54,
      -1280,
      3197,
      343,
      11,
    ]),
    Int16List.fromList(const <int>[
      53,
      -161,
      4367,
      521,
      37,
      53,
      -161,
      4367,
      521,
      37,
    ]),
    Int16List.fromList(const <int>[
      -6,
      -856,
      3644,
      418,
      18,
      -6,
      -856,
      3644,
      418,
      18,
    ]),
  ];

  /// Cosine matrix for 8-subband DCT (fixed-point 0.13 format).
  /// H(k,i) = sign(x(k,i)) * cos(abs(x(k,i)) * pi/16)
  /// where x(k,i) values are arranged for optimal encoding.
  static final List<Int16List> cosMatrix8 = <Int16List>[
    Int16List.fromList(const <int>[
      5793,
      6811,
      7568,
      8035,
      4551,
      3135,
      1598,
      8192,
    ]),
    Int16List.fromList(const <int>[
      -5793,
      -1598,
      3135,
      6811,
      -8035,
      -7568,
      -4551,
      8192,
    ]),
    Int16List.fromList(const <int>[
      -5793,
      -8035,
      -3135,
      4551,
      1598,
      7568,
      6811,
      8192,
    ]),
    Int16List.fromList(const <int>[
      5793,
      -4551,
      -7568,
      1598,
      6811,
      -3135,
      -8035,
      8192,
    ]),
    Int16List.fromList(const <int>[
      5793,
      4551,
      -7568,
      -1598,
      -6811,
      -3135,
      8035,
      8192,
    ]),
    Int16List.fromList(const <int>[
      -5793,
      8035,
      -3135,
      -4551,
      -1598,
      7568,
      -6811,
      8192,
    ]),
    Int16List.fromList(const <int>[
      -5793,
      1598,
      3135,
      -6811,
      8035,
      -7568,
      4551,
      8192,
    ]),
    Int16List.fromList(const <int>[
      5793,
      -6811,
      7568,
      -8035,
      -4551,
      3135,
      -1598,
      8192,
    ]),
  ];
}
