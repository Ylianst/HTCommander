/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Loads XARA reference vectors (copied from the upstream repository's
`vectors/` directory, MIT License) for the pure-Dart port tests.
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Map<String, Object?> _cache = <String, Object?>{};

/// Returns the whole decoded `test/xara/vectors/<name>.json` document.
Map<String, dynamic> loadDoc(String name) {
  return (_cache['doc:$name'] ??= jsonDecode(
    File('test/xara/vectors/$name.json').readAsStringSync(),
  )) as Map<String, dynamic>;
}

/// Returns the `content` object of `test/xara/vectors/<name>.json`.
Map<String, dynamic> loadVector(String name) =>
    loadDoc(name)['content'] as Map<String, dynamic>;

int hexOrU(Object? v) => v is String ? hexU32(v) : (v as num).toInt();

int hexU32(Object? v) =>
    int.parse((v as String).replaceFirst('0x', ''), radix: 16);

List<int> words(Object? v) =>
    (v as String).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(int.parse).toList();

List<int> ints(Object? v) => (v as List).map((e) => (e as num).toInt()).toList();

Uint8List hexDecode(String s) {
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

String hexEncode(List<int> b) =>
    b.map((x) => (x & 0xFF).toRadixString(16).padLeft(2, '0')).join();

String sha256Hex(List<int> b) => sha256.convert(b).toString();

Uint8List latin1Bytes(String s) => Uint8List.fromList(latin1.encode(s));
