/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.SentenceDecoder` class.
*/

import 'nmea_parser.dart';
import 'sentences/gga_sentence.dart';
import 'sentences/gll_sentence.dart';
import 'sentences/gsa_sentence.dart';
import 'sentences/gsv_sentence.dart';
import 'sentences/rmc_sentence.dart';
import 'sentences/vtg_sentence.dart';
import 'sentences/zda_sentence.dart';

/// Routes a parsed NMEA sentence to the appropriate decoder and returns a
/// human-readable representation, or `null` for unsupported sentences.
class SentenceDecoder {
  SentenceDecoder._();

  /// Decodes a raw NMEA line and returns a formatted string, or `null` if the
  /// sentence type is not supported.
  static String? decode(String rawLine) {
    final parsed = NmeaParser.tryParse(rawLine);
    if (parsed == null) return null;

    final sentenceId = parsed.sentenceId;
    final fields = parsed.fields;

    // The talker ID is the first two characters (e.g. "GP", "GN", "GL").
    // The sentence type is the remaining characters.
    final type = sentenceId.length >= 5 ? sentenceId.substring(2) : sentenceId;

    try {
      switch (type) {
        case 'GGA':
          return GgaSentence.parse(fields).toString();
        case 'RMC':
          return RmcSentence.parse(fields).toString();
        case 'GSA':
          return GsaSentence.parse(fields).toString();
        case 'GSV':
          return GsvSentence.parse(fields).toString();
        case 'VTG':
          return VtgSentence.parse(fields).toString();
        case 'GLL':
          return GllSentence.parse(fields).toString();
        case 'ZDA':
          return ZdaSentence.parse(fields).toString();
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
