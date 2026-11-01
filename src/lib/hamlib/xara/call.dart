/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Callsign hashing and 6-bit packing.
*/

import 'dart:convert';
import 'dart:typed_data';

import 'crc.dart';

final RegExp _u8Digits = RegExp(r'^\+?[0-9]+$');

int callHash(List<int> call) {
  if (call.isEmpty) return 0;
  final int c1 = crc16Genibus(call);
  final int start = call.length < 3 ? 0 : call.length - 3;
  final int c2 = crc16Genibus(call, start);
  return ((c2 >> 8) << 16) | c1;
}

/// Parses an SSID suffix: `T`/`R`/`X`/`L` or a decimal u8 (Rust `str::parse`).
int? ssidCode(String ssid) {
  switch (ssid) {
    case 'T':
      return 0x10;
    case 'R':
      return 0x11;
    case 'X':
      return 0x12;
    case 'L':
      return 0x13;
  }
  if (!_u8Digits.hasMatch(ssid)) return null;
  final int? v = int.tryParse(ssid.startsWith('+') ? ssid.substring(1) : ssid);
  return v != null && v <= 255 ? v : null;
}

String withSsid(String base, int code) {
  switch (code) {
    case 0:
      return base;
    case 0x10:
      return '$base-T';
    case 0x11:
      return '$base-R';
    case 0x12:
      return '$base-X';
    case 0x13:
      return '$base-L';
    default:
      return '$base-$code';
  }
}

Uint8List packCall(List<int> call) {
  final int dash = call.indexOf(0x2D);
  List<int> base = call;
  int ssid = 0;
  if (dash >= 0) {
    base = call.sublist(0, dash);
    int? code;
    try {
      code = ssidCode(utf8.decode(call.sublist(dash + 1)));
    } on FormatException {
      code = null;
    }
    ssid = (code != null && code >= 1 && code <= 0x13) ? code : 0;
  }
  final List<int> codes = base.map((c) {
    if (c >= 0x41 && c <= 0x5A) return c - 0x41 + 1;
    if (c >= 0x30 && c <= 0x39) return c - 0x30 + 27;
    return 0;
  }).toList();
  while (codes.length < 7) {
    codes.add(0);
  }
  codes.add(ssid);
  int bits = 0;
  for (int i = 0; i < 8; i++) {
    bits = (bits << 6) | (codes[i] & 63);
  }
  final Uint8List out = Uint8List(6);
  for (int i = 0; i < 6; i++) {
    out[i] = (bits >> (8 * (5 - i))) & 0xFF;
  }
  return out;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isAlnum(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

bool isUsCall(String call) {
  final List<int> base = utf8.encode(call.split('-').first);
  final int n = base.length;
  final List<int> digits = [
    for (int i = 0; i < n; i++)
      if (_isDigit(base[i])) i,
  ];
  if (n < 4 ||
      n > 6 ||
      !'NKWA'.codeUnits.contains(base[0]) ||
      digits.length != 1 ||
      digits[0] < 1 ||
      digits[0] > 2) {
    return false;
  }
  if (!base.every(_isAlnum)) return false;
  if (base[0] == 0x41 && base[1] >= 0x4D && base[1] <= 0x5A) return false;
  final int pre = digits[0];
  final int suf = n - digits[0] - 1;
  if (pre == 2 && suf == 3) return base[0] == 0x4B || base[0] == 0x57;
  if (pre == 2 && suf == 2 && base[0] == 0x41) {
    return base[1] >= 0x41 && base[1] <= 0x4C;
  }
  return true;
}

String? unpackCall(List<int> b) {
  if (b.length < 6) return null;
  int v = 0;
  for (int i = 0; i < 6; i++) {
    v = (v << 8) | (b[i] & 0xFF);
  }
  final StringBuffer base = StringBuffer();
  for (int i = 7; i >= 1; i--) {
    final int c = (v >> (6 * i)) & 63;
    if (c >= 1 && c <= 26) {
      base.writeCharCode(0x41 + c - 1);
    } else if (c >= 27 && c <= 36) {
      base.writeCharCode(0x30 + c - 27);
    } else {
      base.write(' ');
    }
  }
  return withSsid(base.toString().trimRight(), v & 0x1F);
}
