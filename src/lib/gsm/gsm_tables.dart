// gsm_tables.dart - Constant tables for the GSM 06.10 codec.
//
// Ported verbatim from libgsm 1.0.22 table.c (section 4.4 of GSM 06.10).
// Source of truth: reference/libgsm/src/table.c.

import 'dart:typed_data';

/// Table 4.1 Quantization of the Log.-Area Ratios.
final Int16List gsmA =
    Int16List.fromList(const <int>[20480, 20480, 20480, 20480, 13964, 15360, 8534, 9036]);
final Int16List gsmB =
    Int16List.fromList(const <int>[0, 0, 2048, -2560, 94, -1792, -341, -1144]);
final Int16List gsmMic =
    Int16List.fromList(const <int>[-32, -32, -16, -16, -8, -8, -4, -4]);
final Int16List gsmMac =
    Int16List.fromList(const <int>[31, 31, 15, 15, 7, 7, 3, 3]);

/// Table 4.2 Tabulation of 1/A[1..8].
final Int16List gsmInvA =
    Int16List.fromList(const <int>[13107, 13107, 13107, 13107, 19223, 17476, 31454, 29708]);

/// Table 4.3a Decision level of the LTP gain quantizer.
final Int16List gsmDlb =
    Int16List.fromList(const <int>[6554, 16384, 26214, 32767]);

/// Table 4.3b Quantization levels of the LTP gain quantizer.
final Int16List gsmQlb =
    Int16List.fromList(const <int>[3277, 11469, 21299, 32767]);

/// Table 4.4 Coefficients of the weighting filter.
final Int16List gsmH =
    Int16List.fromList(const <int>[-134, -374, 0, 2054, 5741, 8192, 5741, 2054, 0, -374, -134]);

/// Table 4.5 Normalized inverse mantissa used to compute xM/xmax.
final Int16List gsmNrfac =
    Int16List.fromList(const <int>[29128, 26215, 23832, 21846, 20165, 18725, 17476, 16384]);

/// Table 4.6 Normalized direct mantissa used to compute xM/xmax.
final Int16List gsmFac =
    Int16List.fromList(const <int>[18431, 20479, 22527, 24575, 26623, 28671, 30719, 32767]);
