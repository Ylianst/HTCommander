/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:ui' as ui;

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

  /// Country codes whose weather conventions use imperial units
  /// (Fahrenheit, inches, mph). Everyone else defaults to metric.
  static const Set<String> _imperialCountries = {'US', 'LR', 'MM'};

  /// True when the operating system's regional settings indicate the metric
  /// system should be used. Determined from the primary system locale's
  /// country code: all countries except the US, Liberia and Myanmar use
  /// metric units for weather. Defaults to metric when no country is known.
  static bool get systemUsesMetric {
    final country = ui.PlatformDispatcher.instance.locale.countryCode;
    if (country == null || country.isEmpty) return true;
    return !_imperialCountries.contains(country.toUpperCase());
  }

  /// Converts a bearing in degrees to a 16-point compass abbreviation.
  static String _compass(int degrees) =>
      _compassPoints[((((degrees % 360) + 11.25) ~/ 22.5)) % 16];

  String? _windDescription({required bool metric}) {
    final hasSpeed = windSpeed != null && windSpeed! > 0;
    final hasGust = windGust != null && windGust! > 0;
    if (!hasSpeed && !hasGust) {
      // Report calm only when the station actually sent a (zero) wind value.
      if (windSpeed != null || windGust != null) return 'wind calm';
      return null;
    }
    final unit = metric ? 'km/h' : 'mph';
    int conv(int mph) => metric ? (mph * 1.609344).round() : mph;
    final sb = StringBuffer('wind');
    if (hasSpeed) {
      if (windDirection != null) sb.write(' ${_compass(windDirection!)}');
      sb.write(' ${conv(windSpeed!)} $unit');
    }
    if (hasGust) {
      sb.write(hasSpeed
          ? ' (gust ${conv(windGust!)} $unit)'
          : ' gust ${conv(windGust!)} $unit');
    }
    return sb.toString();
  }

  /// Builds a compact, human-readable weather summary.
  ///
  /// When [metric] is null the unit system is taken from the operating
  /// system's regional settings (see [systemUsesMetric]). Metric output uses
  /// °C, km/h, hPa and millimetres (e.g. "12°C, wind SW 6 km/h, humidity 91%,
  /// 1014.5 hPa"); imperial output uses °F, mph, mb and inches (e.g. "53°F,
  /// wind SW 4 mph, humidity 91%, 1014.5 mb").
  String toReadableString({bool? metric}) {
    final useMetric = metric ?? systemUsesMetric;
    final parts = <String>[];
    if (temperature != null) {
      if (useMetric) {
        final c = ((temperature! - 32) * 5 / 9).round();
        parts.add('$c°C');
      } else {
        parts.add('$temperature°F');
      }
    }
    final wind = _windDescription(metric: useMetric);
    if (wind != null) parts.add(wind);
    if (humidity != null) parts.add('humidity $humidity%');
    if (barometricPressure != null) {
      // 1 mb == 1 hPa, only the label changes.
      final unit = useMetric ? 'hPa' : 'mb';
      parts.add('${barometricPressure!.toStringAsFixed(1)} $unit');
    }
    if (rainLastHour != null && rainLastHour! > 0) {
      parts.add(useMetric
          ? 'rain ${_inToMm(rainLastHour!)} mm/h'
          : 'rain ${(rainLastHour! / 100).toStringAsFixed(2)} in/h');
    } else if (rainLast24Hours != null && rainLast24Hours! > 0) {
      parts.add(useMetric
          ? 'rain ${_inToMm(rainLast24Hours!)} mm/24h'
          : 'rain ${(rainLast24Hours! / 100).toStringAsFixed(2)} in/24h');
    } else if (rainSinceMidnight != null && rainSinceMidnight! > 0) {
      parts.add(useMetric
          ? 'rain ${_inToMm(rainSinceMidnight!)} mm today'
          : 'rain ${(rainSinceMidnight! / 100).toStringAsFixed(2)} in today');
    }
    if (snowLast24Hours != null && snowLast24Hours! > 0) {
      parts.add(useMetric
          ? 'snow ${(snowLast24Hours! * 2.54).toStringAsFixed(1)} cm/24h'
          : 'snow $snowLast24Hours in/24h');
    }
    if (luminosity != null) parts.add('$luminosity W/m²');
    return parts.join(', ');
  }

  /// Converts hundredths of an inch to millimetres, formatted to one decimal.
  static String _inToMm(int hundredthsInch) =>
      (hundredthsInch / 100 * 25.4).toStringAsFixed(1);

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
