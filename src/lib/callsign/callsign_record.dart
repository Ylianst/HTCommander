/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// A single amateur radio license record looked up from the offline callsign
/// database (derived from the FCC ULS amateur license dump).
///
/// Fields mirror the compact subset stored in the binary database. Any field
/// may be empty when the source record does not provide it.
class CallsignRecord {
  /// The full callsign as licensed (e.g. `K7VZT`). No SSID.
  final String callsign;

  /// Licensee name (entity name, or "First Last" for individuals).
  final String name;

  /// FCC operator class code letter, or empty when unknown.
  /// One of: `N` (Novice), `T` (Technician), `P` (Technician Plus),
  /// `G` (General), `A` (Advanced), `E` (Amateur Extra).
  final String operatorClass;

  /// FCC license status code letter, or empty when unknown.
  /// Commonly `A` (Active), `E` (Expired), `C` (Cancelled).
  final String status;

  /// Licensee city.
  final String city;

  /// Two-letter US state/territory code.
  final String state;

  /// ZIP / postal code.
  final String zip;

  /// License expiration date as an integer `YYYYMMDD`, or 0 when unknown.
  final int expireDate;

  const CallsignRecord({
    required this.callsign,
    this.name = '',
    this.operatorClass = '',
    this.status = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.expireDate = 0,
  });

  /// Human-readable operator class name for the FCC [operatorClass] letter.
  String get operatorClassName => switch (operatorClass.toUpperCase()) {
        'N' => 'Novice',
        'T' => 'Technician',
        'P' => 'Technician Plus',
        'G' => 'General',
        'A' => 'Advanced',
        'E' => 'Amateur Extra',
        _ => '',
      };

  /// Human-readable license status for the FCC [status] letter.
  String get statusName => switch (status.toUpperCase()) {
        'A' => 'Active',
        'E' => 'Expired',
        'C' => 'Cancelled',
        'T' => 'Terminated',
        'L' => 'Pending Legal Status',
        _ => '',
      };

  /// The expiration date formatted as `YYYY-MM-DD`, or empty when unknown.
  String get expireDateFormatted {
    if (expireDate <= 0) return '';
    final y = expireDate ~/ 10000;
    final m = (expireDate ~/ 100) % 100;
    final d = expireDate % 100;
    if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return '';
    final mm = m.toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  /// City, state and ZIP joined into a single display line.
  String get location {
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (state.isNotEmpty) parts.add(state);
    final head = parts.join(', ');
    if (zip.isNotEmpty) {
      return head.isEmpty ? zip : '$head $zip';
    }
    return head;
  }

  @override
  String toString() =>
      'CallsignRecord($callsign, $name, $operatorClass, $status, $location)';
}
