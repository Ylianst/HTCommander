/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'callsign_record.dart';

/// Reader and writer for the HTCommander offline callsign database (`.cdb`).
///
/// The format is a compact, read-only, self-hosted file derived from the FCC
/// ULS amateur license dump. It is designed for fast on-disk lookups with no
/// external database dependency: a sorted fixed-size index is loaded fully into
/// memory (a few MB) and binary-searched, then a single seek+read fetches the
/// variable-length record.
///
/// All multi-byte integers are little-endian.
///
/// ```
/// Header (64 bytes)
///   0  u32  magic          = 0x42444348  ("HCDB")
///   4  u16  formatVersion  = 1
///   6  u16  flags          (reserved, 0)
///   8  u32  recordCount
///   12 u32  indexOffset    (byte offset of the index section)
///   16 u32  recordsOffset  (byte offset of the records section)
///   20 u32  sourceDate     (FCC source date as YYYYMMDD, 0 if unknown)
///   24 …    reserved (zero) up to byte 64
///
/// Index section: recordCount entries, 12 bytes each, sorted ascending by key
///   0  8 bytes  key    (uppercase base callsign, ASCII, right-padded with 0)
///   8  u32      offset (absolute file offset of the record)
///
/// Records section: variable-length records, each encoded as
///   callsign        u16 len + UTF-8 bytes
///   name            u16 len + UTF-8 bytes
///   city            u16 len + UTF-8 bytes
///   state           u16 len + UTF-8 bytes
///   zip             u16 len + UTF-8 bytes
///   operatorClass   u8  (ASCII class letter, or 0)
///   status          u8  (ASCII status letter, or 0)
///   expireDate      u32 (YYYYMMDD, or 0)
/// ```
class CallsignDatabase {
  /// File magic: ASCII "HCDB" little-endian.
  static const int magic = 0x42444348;

  /// Current supported format version.
  static const int formatVersion = 1;

  /// Size of the fixed header, in bytes.
  static const int headerSize = 64;

  /// Size of a single index entry, in bytes (8-byte key + 4-byte offset).
  static const int indexEntrySize = 12;

  /// Length of the fixed callsign key in an index entry, in bytes.
  static const int keyLength = 8;

  final RandomAccessFile? _raf;

  /// The whole file contents when opened from memory (web / tests). Null when
  /// opened from a [RandomAccessFile].
  final Uint8List? _bytes;

  /// The in-memory copy of the index section for binary search.
  final Uint8List _index;

  /// Number of records in the database.
  final int recordCount;

  /// FCC source date as `YYYYMMDD`, or 0 when unknown.
  final int sourceDate;

  CallsignDatabase._({
    required this._raf,
    required this._bytes,
    required this._index,
    required this.recordCount,
    required this.sourceDate,
  });

  /// Opens the database at [path], reading the header and loading the index
  /// section into memory. Keeps the file open for record reads until [close]
  /// is called.
  ///
  /// Throws a [FormatException] when the file is not a valid database.
  static Future<CallsignDatabase> open(String path) async {
    final raf = await File(path).open();
    try {
      final header = await raf.read(headerSize);
      final h = _parseHeader(header);
      final indexBytes = h.recordCount * indexEntrySize;
      await raf.setPosition(h.indexOffset);
      final index = await raf.read(indexBytes);
      if (index.length != indexBytes) {
        throw const FormatException('Callsign database index is truncated');
      }
      return CallsignDatabase._(
        raf: raf,
        bytes: null,
        index: index,
        recordCount: h.recordCount,
        sourceDate: h.sourceDate,
      );
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  /// Opens the database from an in-memory [bytes] buffer (used on platforms
  /// without file access and in tests).
  static CallsignDatabase openBytes(Uint8List bytes) {
    final h = _parseHeader(bytes);
    final indexBytes = h.recordCount * indexEntrySize;
    if (h.indexOffset + indexBytes > bytes.length) {
      throw const FormatException('Callsign database index is truncated');
    }
    final index = Uint8List.sublistView(
      bytes,
      h.indexOffset,
      h.indexOffset + indexBytes,
    );
    return CallsignDatabase._(
      raf: null,
      bytes: bytes,
      index: index,
      recordCount: h.recordCount,
      sourceDate: h.sourceDate,
    );
  }

  static _Header _parseHeader(Uint8List header) {
    if (header.length < headerSize) {
      throw const FormatException('Callsign database header is too small');
    }
    final data = ByteData.sublistView(header);
    if (data.getUint32(0, Endian.little) != magic) {
      throw const FormatException('Not a callsign database (bad magic)');
    }
    final version = data.getUint16(4, Endian.little);
    if (version != formatVersion) {
      throw FormatException('Unsupported callsign database version $version');
    }
    return _Header(
      recordCount: data.getUint32(8, Endian.little),
      indexOffset: data.getUint32(12, Endian.little),
      recordsOffset: data.getUint32(16, Endian.little),
      sourceDate: data.getUint32(20, Endian.little),
    );
  }

  /// Looks up [callsign] (SSID is ignored). Returns the matching
  /// [CallsignRecord], or null when not found.
  Future<CallsignRecord?> lookup(String callsign) async {
    final key = _makeKey(callsign);
    if (key == null) return null;
    final offset = _findOffset(key);
    if (offset == null) return null;
    return _readRecord(offset);
  }

  /// Builds the 8-byte lookup key for [callsign]: uppercase, strip any SSID and
  /// non-alphanumeric characters, then right-pad/truncate to [keyLength] bytes.
  /// Returns null when the callsign has no usable characters.
  static Uint8List? _makeKey(String callsign) {
    final upper = callsign.toUpperCase();
    final key = Uint8List(keyLength);
    var n = 0;
    for (var i = 0; i < upper.length && n < keyLength; i++) {
      final c = upper.codeUnitAt(i);
      if (c == 0x2D) break; // '-' begins the SSID; stop here.
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUpper = c >= 0x41 && c <= 0x5A;
      if (isDigit || isUpper) {
        key[n++] = c;
      }
    }
    if (n == 0) return null;
    return key;
  }

  /// Binary-searches the in-memory index for [key], returning the record
  /// offset or null when not present.
  int? _findOffset(Uint8List key) {
    var lo = 0;
    var hi = recordCount - 1;
    final index = _index;
    final data = ByteData.sublistView(index);
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final base = mid * indexEntrySize;
      final cmp = _compareKey(index, base, key);
      if (cmp == 0) {
        return data.getUint32(base + keyLength, Endian.little);
      } else if (cmp < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// Compares the [keyLength]-byte key stored at [base] in [index] against
  /// [key]. Returns <0, 0 or >0.
  static int _compareKey(Uint8List index, int base, Uint8List key) {
    for (var i = 0; i < keyLength; i++) {
      final a = index[base + i];
      final b = key[i];
      if (a != b) return a - b;
    }
    return 0;
  }

  Future<CallsignRecord> _readRecord(int offset) async {
    // Records are small; read a generous window then parse. Using a bounded
    // read avoids a second round-trip for the length in the common case.
    final reader = _RecordReader(await _readAt(offset, _maxRecordBytes));
    final callsign = reader.readString();
    final name = reader.readString();
    final city = reader.readString();
    final state = reader.readString();
    final zip = reader.readString();
    final operatorClass = reader.readCharByte();
    final status = reader.readCharByte();
    final expireDate = reader.readUint32();
    return CallsignRecord(
      callsign: callsign,
      name: name,
      city: city,
      state: state,
      zip: zip,
      operatorClass: operatorClass,
      status: status,
      expireDate: expireDate,
    );
  }

  /// Upper bound on a single encoded record. Field lengths are bounded by the
  /// FCC schema (name <= 200, address parts small), so 1 KB is safe.
  static const int _maxRecordBytes = 1024;

  Future<Uint8List> _readAt(int offset, int length) async {
    final bytes = _bytes;
    if (bytes != null) {
      final end = (offset + length) > bytes.length ? bytes.length : offset + length;
      return Uint8List.sublistView(bytes, offset, end);
    }
    final raf = _raf!;
    await raf.setPosition(offset);
    return raf.read(length);
  }

  /// Closes the underlying file handle, if any.
  Future<void> close() async {
    await _raf?.close();
  }

  // ── Writer ────────────────────────────────────────────────────────────────

  /// Encodes [records] into the binary database format. Records are sorted by
  /// their lookup key. Used by tests and any Dart-side database builder; the
  /// production database is built by the offline tool
  /// `tools/build_fcc_db.py`, which must produce the identical layout.
  static Uint8List build(List<CallsignRecord> records, {int sourceDate = 0}) {
    // Sort by key bytes, dropping records whose callsign yields no key.
    final keyed = <MapEntry<Uint8List, CallsignRecord>>[];
    for (final r in records) {
      final key = _makeKey(r.callsign);
      if (key != null) keyed.add(MapEntry(key, r));
    }
    keyed.sort((a, b) => _compareKeyBytes(a.key, b.key));

    // Encode records section first to compute offsets.
    final recordsBuilder = BytesBuilder();
    final offsets = <int>[];
    final recordsOffset = headerSize + keyed.length * indexEntrySize;
    for (final entry in keyed) {
      offsets.add(recordsOffset + recordsBuilder.length);
      recordsBuilder.add(_encodeRecord(entry.value));
    }
    final recordsBytes = recordsBuilder.toBytes();

    final total = recordsOffset + recordsBytes.length;
    final out = Uint8List(total);
    final data = ByteData.sublistView(out);

    // Header.
    data.setUint32(0, magic, Endian.little);
    data.setUint16(4, formatVersion, Endian.little);
    data.setUint16(6, 0, Endian.little);
    data.setUint32(8, keyed.length, Endian.little);
    data.setUint32(12, headerSize, Endian.little);
    data.setUint32(16, recordsOffset, Endian.little);
    data.setUint32(20, sourceDate, Endian.little);

    // Index.
    var pos = headerSize;
    for (var i = 0; i < keyed.length; i++) {
      out.setRange(pos, pos + keyLength, keyed[i].key);
      data.setUint32(pos + keyLength, offsets[i], Endian.little);
      pos += indexEntrySize;
    }

    // Records.
    out.setRange(recordsOffset, total, recordsBytes);
    return out;
  }

  static int _compareKeyBytes(Uint8List a, Uint8List b) {
    for (var i = 0; i < keyLength; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }

  static Uint8List _encodeRecord(CallsignRecord r) {
    final b = BytesBuilder();
    _writeString(b, r.callsign);
    _writeString(b, r.name);
    _writeString(b, r.city);
    _writeString(b, r.state);
    _writeString(b, r.zip);
    b.addByte(_charByte(r.operatorClass));
    b.addByte(_charByte(r.status));
    final expire = ByteData(4)..setUint32(0, r.expireDate, Endian.little);
    b.add(expire.buffer.asUint8List());
    return b.toBytes();
  }

  static void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    final len = bytes.length > 0xFFFF ? 0xFFFF : bytes.length;
    b.addByte(len & 0xFF);
    b.addByte((len >> 8) & 0xFF);
    b.add(len == bytes.length ? bytes : bytes.sublist(0, len));
  }

  static int _charByte(String s) => s.isEmpty ? 0 : s.codeUnitAt(0) & 0xFF;
}

class _Header {
  final int recordCount;
  final int indexOffset;
  final int recordsOffset;
  final int sourceDate;
  const _Header({
    required this.recordCount,
    required this.indexOffset,
    required this.recordsOffset,
    required this.sourceDate,
  });
}

/// Sequential reader over an encoded record buffer.
class _RecordReader {
  final Uint8List _b;
  final ByteData _d;
  int _pos = 0;
  _RecordReader(this._b) : _d = ByteData.sublistView(_b);

  String readString() {
    final len = _b[_pos] | (_b[_pos + 1] << 8);
    _pos += 2;
    final s = utf8.decode(
      Uint8List.sublistView(_b, _pos, _pos + len),
      allowMalformed: true,
    );
    _pos += len;
    return s;
  }

  String readCharByte() {
    final c = _b[_pos++];
    return c == 0 ? '' : String.fromCharCode(c);
  }

  int readUint32() {
    final v = _d.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }
}
