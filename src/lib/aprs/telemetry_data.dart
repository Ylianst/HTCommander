/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Parsed APRS "Base91 Comment Telemetry" values.
///
/// This extension (specified by aprs.fi / Ham::APRS::FAP) embeds
/// machine-readable telemetry inside the comment field of a position packet,
/// delimited at both ends by the `|` character. Each value is encoded as two
/// APRS-base91 characters, giving a range of 0..8280:
///
/// ```
/// |<seq><ch1>[<ch2>..<ch5>][<bin>]|
/// ```
///
/// where `seq` is the sequence counter, `ch1`..`ch5` are up to five analog
/// channels and the optional trailing `bin` value holds eight binary channels
/// (B1 in the LSB through B8).
class TelemetryData {
  /// Telemetry sequence counter (0..8280).
  int sequence = 0;

  /// Analog channel values in transmission order (1..5 entries).
  final List<int> analog = <int>[];

  /// Raw binary-channel integer (0..255) when the optional binary channel was
  /// present, otherwise null. Bit 0 (LSB) is B1, bit 7 is B8.
  int? binaryBits;

  /// The eight binary channels (B1..B8) as booleans, or an empty list when no
  /// binary channel was transmitted.
  List<bool> get binary {
    final bits = binaryBits;
    if (bits == null) return const <bool>[];
    return List<bool>.generate(8, (i) => (bits & (1 << i)) != 0);
  }

  /// True when at least one analog channel was parsed.
  bool get hasData => analog.isNotEmpty;

  /// Builds a compact, human-readable summary such as
  /// "#7544: 1472, 1564, 1656 [10000000]".
  String toReadableString() {
    final sb = StringBuffer('#$sequence: ');
    sb.write(analog.join(', '));
    final bits = binaryBits;
    if (bits != null) {
      sb.write(' [');
      // B1 is the LSB; display B1..B8 left-to-right.
      for (var i = 0; i < 8; i++) {
        sb.write((bits & (1 << i)) != 0 ? '1' : '0');
      }
      sb.write(']');
    }
    return sb.toString();
  }

  /// Parses a Base91 telemetry payload (the text found between the surrounding
  /// `|` delimiters, e.g. `ss1122`). Returns null when [payload] is not a
  /// valid telemetry sequence.
  ///
  /// A valid payload has an even length between 4 and 14 characters and
  /// contains only APRS-base91 characters (`!`..`{`, code units 33..123). It
  /// consists of a sequence counter plus one to five analog channels and an
  /// optional trailing binary channel.
  static TelemetryData? parse(String payload) {
    final int len = payload.length;
    // Minimum: sequence + 1 channel (4 chars). Maximum: sequence + 5 channels
    // + binary channel (14 chars). Every value uses two characters.
    if (len < 4 || len > 14 || len.isOdd) return null;

    for (var i = 0; i < len; i++) {
      final c = payload.codeUnitAt(i);
      if (c < 33 || c > 123) return null;
    }

    int decode(int index) {
      final c0 = payload.codeUnitAt(index) - 33;
      final c1 = payload.codeUnitAt(index + 1) - 33;
      return (c0 * 91) + c1;
    }

    final t = TelemetryData();
    t.sequence = decode(0);

    // The number of two-character values after the sequence counter.
    final int valueCount = (len ~/ 2) - 1;

    // With six values present the last one is the binary channel; up to five
    // analog channels precede it.
    final int analogCount = valueCount > 5 ? 5 : valueCount;
    for (var v = 0; v < analogCount; v++) {
      t.analog.add(decode((v + 1) * 2));
    }
    if (valueCount > 5) {
      t.binaryBits = decode((analogCount + 1) * 2) & 0xFF;
    }

    return t.hasData ? t : null;
  }
}
