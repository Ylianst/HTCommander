/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Parsed APRS weather fields.
///
/// APRS weather data can appear either as a stand-alone weather report (data
/// type `_`) or appended to a position report whose symbol is the weather
/// station symbol (`_`). All values are optional: a field is only set when it
/// was actually present in the packet.
class WeatherData {
  /// Wind direction in degrees (0-360).
  int? windDirection;

  /// Sustained (one-minute) wind speed in mph.
  int? windSpeed;

  /// Peak wind gust over the last 5 minutes, in mph.
  int? windGust;

  /// Temperature in degrees Fahrenheit (may be negative).
  int? temperature;

  /// Rainfall over the last hour, in hundredths of an inch.
  int? rainLastHour;

  /// Rainfall over the last 24 hours, in hundredths of an inch.
  int? rainLast24Hours;

  /// Rainfall since local midnight, in hundredths of an inch.
  int? rainSinceMidnight;

  /// Relative humidity in percent (1-100).
  int? humidity;

  /// Barometric pressure in tenths of a millibar/hPa.
  int? barometricPressureTenths;

  /// Solar luminosity in watts per square metre.
  int? luminosity;

  /// Snowfall over the last 24 hours, in inches.
  int? snowLast24Hours;

  /// Raw rain counter (implementation specific).
  int? rainRaw;

  /// Barometric pressure in millibars/hPa, or null when not reported.
  double? get barometricPressure =>
      barometricPressureTenths == null ? null : barometricPressureTenths! / 10.0;

  /// True when at least one weather value was parsed.
  bool get hasData =>
      windDirection != null ||
      windSpeed != null ||
      windGust != null ||
      temperature != null ||
      rainLastHour != null ||
      rainLast24Hours != null ||
      rainSinceMidnight != null ||
      humidity != null ||
      barometricPressureTenths != null ||
      luminosity != null ||
      snowLast24Hours != null ||
      rainRaw != null;

  static const List<String> _compassPoints = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];

  /// Converts a bearing in degrees to a 16-point compass abbreviation.
  static String _compass(int degrees) =>
      _compassPoints[((((degrees % 360) + 11.25) ~/ 22.5)) % 16];

  String? _windDescription() {
    final hasSpeed = windSpeed != null && windSpeed! > 0;
    final hasGust = windGust != null && windGust! > 0;
    if (!hasSpeed && !hasGust) {
      // Report calm only when the station actually sent a (zero) wind value.
      if (windSpeed != null || windGust != null) return 'wind calm';
      return null;
    }
    final sb = StringBuffer('wind');
    if (hasSpeed) {
      if (windDirection != null) sb.write(' ${_compass(windDirection!)}');
      sb.write(' $windSpeed mph');
    }
    if (hasGust) sb.write(hasSpeed ? ' (gust $windGust mph)' : ' gust $windGust mph');
    return sb.toString();
  }

  /// Builds a compact, human-readable weather summary such as
  /// "53°F, wind SW 4 mph, humidity 91%, 1014.5 mb".
  String toReadableString() {
    final parts = <String>[];
    if (temperature != null) parts.add('$temperature°F');
    final wind = _windDescription();
    if (wind != null) parts.add(wind);
    if (humidity != null) parts.add('humidity $humidity%');
    if (barometricPressure != null) {
      parts.add('${barometricPressure!.toStringAsFixed(1)} mb');
    }
    if (rainLastHour != null && rainLastHour! > 0) {
      parts.add('rain ${(rainLastHour! / 100).toStringAsFixed(2)} in/h');
    } else if (rainLast24Hours != null && rainLast24Hours! > 0) {
      parts.add('rain ${(rainLast24Hours! / 100).toStringAsFixed(2)} in/24h');
    } else if (rainSinceMidnight != null && rainSinceMidnight! > 0) {
      parts.add('rain ${(rainSinceMidnight! / 100).toStringAsFixed(2)} in today');
    }
    if (snowLast24Hours != null && snowLast24Hours! > 0) {
      parts.add('snow $snowLast24Hours in/24h');
    }
    if (luminosity != null) parts.add('$luminosity W/m²');
    return parts.join(', ');
  }

  /// Parses APRS weather fields from [data].
  ///
  /// [windDirection] and [windSpeed] may be supplied when the wind was already
  /// decoded from a position report's course/speed slot. Returns null when no
  /// weather field could be found.
  static WeatherData? parse(String data, {int? windDirection, int? windSpeed}) {
    final w = WeatherData()
      ..windDirection = windDirection
      ..windSpeed = windSpeed;
    bool found = windDirection != null || windSpeed != null;

    var i = 0;

    // Stand-alone weather reports encode the wind as 'c<dir>' immediately
    // followed by 's<speed>'.
    if (i + 4 <= data.length && data[i] == 'c') {
      final dir = _int(data, i + 1, 3);
      if (dir != null) {
        w.windDirection = dir;
        found = true;
      }
      i += 4;
      if (i + 4 <= data.length && data[i] == 's') {
        final spd = _int(data, i + 1, 3);
        if (spd != null) {
          w.windSpeed = spd;
          found = true;
        }
        i += 4;
      }
    }

    while (i < data.length) {
      final ch = data[i];
      var consumed = 1;
      switch (ch) {
        case 'g': // wind gust (mph)
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.windGust = v;
            found = true;
            consumed = 4;
          }
          break;
        case 't': // temperature (degrees F, may be negative)
          final v = _temp(data, i + 1);
          if (v != null) {
            w.temperature = v;
            found = true;
            consumed = 4;
          }
          break;
        case 'r': // rain last hour (1/100 in)
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.rainLastHour = v;
            found = true;
            consumed = 4;
          }
          break;
        case 'p': // rain last 24 hours (1/100 in)
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.rainLast24Hours = v;
            found = true;
            consumed = 4;
          }
          break;
        case 'P': // rain since midnight (1/100 in)
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.rainSinceMidnight = v;
            found = true;
            consumed = 4;
          }
          break;
        case 'h': // humidity (%, 00 = 100)
          final v = _int(data, i + 1, 2);
          if (v != null) {
            w.humidity = v == 0 ? 100 : v;
            found = true;
            consumed = 3;
          }
          break;
        case 'b': // barometric pressure (1/10 mbar)
          final v = _int(data, i + 1, 5);
          if (v != null) {
            w.barometricPressureTenths = v;
            found = true;
            consumed = 6;
          }
          break;
        case 'L': // luminosity 0-999 W/m^2
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.luminosity = v;
            found = true;
            consumed = 4;
          }
          break;
        case 'l': // luminosity 1000+ W/m^2
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.luminosity = 1000 + v;
            found = true;
            consumed = 4;
          }
          break;
        case 's': // snowfall last 24 hours (in)
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.snowLast24Hours = v;
            found = true;
            consumed = 4;
          }
          break;
        case '#': // raw rain counter
          final v = _int(data, i + 1, 3);
          if (v != null) {
            w.rainRaw = v;
            found = true;
            consumed = 4;
          }
          break;
        default:
          consumed = 1;
      }
      i += consumed;
    }

    return found ? w : null;
  }

  /// Reads [count] characters at [start] and parses them as an integer,
  /// tolerating spaces used for right-justification. Returns null when the
  /// value is missing (e.g. "..." placeholders) or not numeric.
  static int? _int(String s, int start, int count) {
    if (start + count > s.length) return null;
    final sub = s.substring(start, start + count).trim();
    if (sub.isEmpty) return null;
    return int.tryParse(sub);
  }

  /// Reads a 3-character temperature value, allowing a leading minus sign.
  static int? _temp(String s, int start) {
    if (start + 3 > s.length) return null;
    final sub = s.substring(start, start + 3).trim();
    if (sub.isEmpty) return null;
    return int.tryParse(sub);
  }
}
