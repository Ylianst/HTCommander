// Helpers for coercing dynamic JSON values into numbers.

/// Coerce a dynamic JSON value to a double.
///
/// Accepts [num] and numeric [String] values; anything else yields [fallback].
double asDouble(Object? v, [double fallback = 0.0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

/// Coerce a dynamic JSON value to a nullable double.
///
/// Accepts [num] and numeric [String] values; anything else yields null.
double? asDoubleOrNull(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Coerce a dynamic JSON value to an int.
///
/// Accepts [num] and numeric [String] values; anything else yields [fallback].
int asInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// Coerce a dynamic JSON value to a nullable int.
///
/// Accepts [num] and numeric [String] values; anything else yields null.
int? asIntOrNull(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
