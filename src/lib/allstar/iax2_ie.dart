/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// iax2_ie.dart - Information Element (IE) encoding/decoding for IAX2 full
// frames. Each IE is a type-length-value triple: one octet id, one octet
// length, then that many data octets (RFC 5456 section 8.6).
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An ordered collection of IAX2 information elements. Preserves insertion
/// order because a NEW frame requires the VERSION IE to appear first.
class Iax2IeSet {
  final List<MapEntry<int, Uint8List>> _entries = <MapEntry<int, Uint8List>>[];

  Iax2IeSet();

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// Adds a raw IE. Data longer than 255 bytes is rejected (TLV length is one
  /// octet).
  void addRaw(int type, Uint8List data) {
    if (data.length > 255) {
      throw ArgumentError('IE 0x${type.toRadixString(16)} data too long');
    }
    _entries.add(MapEntry<int, Uint8List>(type & 0xFF, data));
  }

  /// Adds a UTF-8 string IE (CALLED NUMBER, USERNAME, CHALLENGE, MD5 RESULT...).
  void addString(int type, String value) =>
      addRaw(type, Uint8List.fromList(utf8.encode(value)));

  /// Adds a 16-bit big-endian IE (VERSION, AUTHMETHODS, REFRESH...).
  void addUint16(int type, int value) {
    final Uint8List d = Uint8List(2);
    ByteData.sublistView(d).setUint16(0, value & 0xFFFF, Endian.big);
    addRaw(type, d);
  }

  /// Adds a 32-bit big-endian IE (CAPABILITY, FORMAT...).
  void addUint32(int type, int value) {
    final Uint8List d = Uint8List(4);
    ByteData.sublistView(d).setUint32(0, value & 0xFFFFFFFF, Endian.big);
    addRaw(type, d);
  }

  /// Adds a value-less IE (e.g. AUTOANSWER).
  void addFlag(int type) => addRaw(type, Uint8List(0));

  /// Returns the raw bytes for the first IE of [type], or null if absent.
  Uint8List? raw(int type) {
    for (final MapEntry<int, Uint8List> e in _entries) {
      if (e.key == type) return e.value;
    }
    return null;
  }

  bool has(int type) => raw(type) != null;

  /// Returns the first [type] IE decoded as UTF-8, or null.
  String? getString(int type) {
    final Uint8List? d = raw(type);
    if (d == null) return null;
    return utf8.decode(d, allowMalformed: true);
  }

  /// Returns the first [type] IE as a big-endian unsigned integer (1, 2 or 4
  /// octets), or null.
  int? getUint(int type) {
    final Uint8List? d = raw(type);
    if (d == null) return null;
    int v = 0;
    for (final int b in d) {
      v = (v << 8) | (b & 0xFF);
    }
    return v;
  }

  /// Serializes all IEs into a contiguous byte buffer.
  Uint8List toBytes() {
    int total = 0;
    for (final MapEntry<int, Uint8List> e in _entries) {
      total += 2 + e.value.length;
    }
    final Uint8List out = Uint8List(total);
    int off = 0;
    for (final MapEntry<int, Uint8List> e in _entries) {
      out[off++] = e.key;
      out[off++] = e.value.length;
      out.setRange(off, off + e.value.length, e.value);
      off += e.value.length;
    }
    return out;
  }

  /// Parses IEs from [data] starting at [offset]. Truncated trailing bytes are
  /// ignored rather than throwing, matching lenient Asterisk behaviour.
  static Iax2IeSet parse(Uint8List data, [int offset = 0]) {
    final Iax2IeSet set = Iax2IeSet();
    int off = offset;
    while (off + 2 <= data.length) {
      final int type = data[off];
      final int len = data[off + 1];
      off += 2;
      if (off + len > data.length) break;
      set.addRaw(type, Uint8List.sublistView(data, off, off + len));
      off += len;
    }
    return set;
  }

  @override
  String toString() {
    final List<String> parts = <String>[];
    for (final MapEntry<int, Uint8List> e in _entries) {
      parts.add('0x${e.key.toRadixString(16)}(${e.value.length})');
    }
    return 'IE[${parts.join(',')}]';
  }
}

/// Computes the IAX2 MD5 challenge response: the lowercase hex MD5 digest of
/// the challenge string concatenated with the shared secret (RFC 5456 8.6.15).
String iax2Md5Response(String challenge, String secret) {
  return md5.convert(utf8.encode('$challenge$secret')).toString();
}
