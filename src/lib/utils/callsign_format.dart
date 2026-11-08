/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Amateur radio callsign format: a 1-3 character prefix containing at least
/// one letter, a separating digit, then a 1-4 letter suffix, optionally
/// followed by an AX.25 SSID (-0 to -15). The base callsign is limited to the
/// 6 characters an AX.25 address can carry.
///
/// Keep in sync with `isValidCallsign` in bbs_web_page.dart.
final RegExp _callsignPattern = RegExp(
  r'^([A-Z0-9]{1,3})[0-9][A-Z]{1,4}(?:-(?:[0-9]|1[0-5]))?$',
);

/// Normalizes [input] (trimmed, upper case) and returns it if it is a valid
/// amateur radio callsign, or `null` otherwise.
String? normalizeAmateurCallsign(String? input) {
  if (input == null) return null;
  final call = input.trim().toUpperCase();
  final match = _callsignPattern.firstMatch(call);
  if (match == null) return null;
  final dash = call.indexOf('-');
  final base = dash < 0 ? call : call.substring(0, dash);
  if (base.length > 6) return null;
  if (!RegExp(r'[A-Z]').hasMatch(match.group(1)!)) return null;
  return call;
}

/// Whether [input] is a valid amateur radio callsign (see
/// [normalizeAmateurCallsign]).
bool isValidAmateurCallsign(String? input) =>
    normalizeAmateurCallsign(input) != null;
