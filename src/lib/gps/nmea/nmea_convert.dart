/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.NmeaConvert` helper class.
*/

/// Helper methods shared across NMEA sentence decoders.
class NmeaConvert {
  NmeaConvert._();

  /// Returns the field at [index] or an empty string when out of range.
  /// Mirrors the C# `fields.ElementAtOrDefault(index) ?? ""` pattern.
  static String at(List<String> fields, int index) =>
      (index >= 0 && index < fields.length) ? fields[index] : '';

  /// Converts a NMEA latitude/longitude value (e.g. "4807.038") and a
  /// hemisphere indicator ('N','S','E','W') to decimal degrees.
  static double? toDecimalDegrees(String value, String hemisphere) {
    if (value.isEmpty || hemisphere.isEmpty) return null;

    final raw = double.tryParse(value);
    if (raw == null) return null;

    // NMEA format: DDDMM.MMMMM  (degrees * 100 + minutes)
    final degrees = (raw / 100).truncate();
    final minutes = raw - degrees * 100;
    var dec = degrees + minutes / 60.0;

    if (hemisphere == 'S' || hemisphere == 'W') dec = -dec;

    return dec;
  }

  /// Parses a NMEA UTC time field (HHMMSS.sss) into a [Duration] since midnight.
  static Duration? toUtcTime(String value) {
    if (value.length < 6) return null;

    final h = int.tryParse(value.substring(0, 2));
    final m = int.tryParse(value.substring(2, 4));
    final s = double.tryParse(value.substring(4));
    if (h == null || m == null || s == null) return null;

    final seconds = s.truncate();
    final millis = ((s - seconds) * 1000).round();
    return Duration(
      hours: h,
      minutes: m,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  /// Parses a NMEA date field (DDMMYY) into a [DateTime] (date only, UTC).
  static DateTime? toDate(String value) {
    if (value.length < 6) return null;

    final day = int.tryParse(value.substring(0, 2));
    final month = int.tryParse(value.substring(2, 4));
    var year = int.tryParse(value.substring(4, 6));
    if (day == null || month == null || year == null) return null;

    year += year < 80 ? 2000 : 1900;

    try {
      return DateTime.utc(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static double? toDouble(String value) {
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  static int? toInt(String value) {
    if (value.isEmpty) return null;
    return int.tryParse(value);
  }

  /// Formats a nullable double with [digits] decimal places, or an empty
  /// string when null (mirrors C# string interpolation of a null `double?`).
  static String fixed(double? value, int digits) =>
      value == null ? '' : value.toStringAsFixed(digits);

  /// Formats a [Duration] as `hh:mm:ss` with optional fractional seconds.
  static String formatTime(Duration? time, {bool millis = false}) {
    if (time == null) return '';
    final h = time.inHours.remainder(24).toString().padLeft(2, '0');
    final m = time.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = time.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (millis) {
      final ms = time.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
      return '$h:$m:$s.$ms';
    }
    return '$h:$m:$s';
  }
}
