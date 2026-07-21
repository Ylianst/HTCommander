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
///   4  u16  formatVersion  = 2
///   6  u16  flags          (reserved, 0)
///   8  u32  recordCount
///   12 u32  keysOffset        (byte offset of the sorted keys block)
///   16 u32  lengthsOffset     (byte offset of the record-lengths block)
///   20 u32  recordsOffset     (byte offset of the records block)
///   24 u32  sourceDate        (FCC source date as YYYYMMDD, 0 if unknown)
///   28 u32  epochDate         (base date YYYYMMDD for expire day counts)
///   32 u16  stateCount        (number of state dictionary entries)
///   34 u16  classStatusCount  (number of class/status dictionary entries)
///   36 u32  stateOffset       (byte offset of the state dictionary)
///   40 u32  classStatusOffset (byte offset of the class/status dictionary)
///   44 u32  cityCount         (number of city dictionary entries)
///   48 u32  cityOffset        (byte offset of the city dictionary)
///   52 …    reserved (zero) up to byte 64
///
/// State dictionary: stateCount entries, 2 bytes each (ASCII state code,
/// 0-padded), referenced by each record's state index.
///
/// Class/status dictionary: classStatusCount entries, 2 bytes each
///   0  u8  operatorClass (ASCII class letter, or 0)
///   1  u8  status        (ASCII status letter, or 0)
///
/// City dictionary: cityCount entries, each `u8 len + UTF-8 bytes`, referenced
/// by each record's 24-bit city index.
///
/// Keys block: recordCount entries, 6 bytes each, sorted ascending by key
///   6 bytes  packed base-37 callsign (big-endian; padding sorts lowest)
///
/// Lengths block: recordCount entries, u16 each
///   u16  byte length of the matching record in the records block
///
/// Records section: variable-length records, in the same sorted order as the
/// keys. The callsign is not stored; it is reconstructed from the key.
///   name            u16 len + UTF-8 bytes
///   cityIndex       u24 (index into the city dictionary)
///   stateIndex      u8  (index into the state dictionary)
///   csIndex         u8  (index into the class/status dictionary)
///   zip             u32 (packed numeric ZIP; 0xFFFFFFFF = none)
///   expireDate      u16 (days since epochDate; 0 = unknown)
/// ```
class CallsignDatabase {
  /// File magic: ASCII "HCDB" little-endian.
  static const int magic = 0x42444348;

  /// Current supported format version.
  static const int formatVersion = 2;

  /// Size of the fixed header, in bytes.
  static const int headerSize = 64;

  /// Maximum number of callsign characters encoded in a key.
  static const int keyChars = 8;

  /// Size of a packed callsign key on disk, in bytes (base-37 of [keyChars]).
  static const int keyBytes = 6;

  /// Default base date (`YYYYMMDD`) that expire day-counts are measured from
  /// when building a database. Stored in the header so the reader never assumes
  /// a fixed epoch and the window can be slid in a future rebuild.
  static const int defaultEpochDate = 20000101;

  final RandomAccessFile? _raf;

  /// The whole file contents when opened from memory (web / tests). Null when
  /// opened from a [RandomAccessFile].
  final Uint8List? _bytes;

  /// The in-memory copy of the sorted keys block for binary search.
  final Uint8List _keys;

  /// Absolute file offset of each record; length is [recordCount] + 1, so
  /// record `i` occupies `[_offsets[i], _offsets[i + 1])`.
  final Uint32List _offsets;

  /// State codes indexed by the per-record state index.
  final List<String> _stateTable;

  /// Operator-class letters indexed by the per-record class/status index.
  final List<String> _classTable;

  /// Status letters indexed by the per-record class/status index.
  final List<String> _statusTable;

  /// City names indexed by the per-record city index.
  final List<String> _cityTable;

  /// Number of records in the database.
  final int recordCount;

  /// FCC source date as `YYYYMMDD`, or 0 when unknown.
  final int sourceDate;

  /// Base date (`YYYYMMDD`) that record expire day-counts are measured from.
  final int epochDate;

  CallsignDatabase._({
    required this._raf,
    required this._bytes,
    required this._keys,
    required this._offsets,
    required List<String> stateTable,
    required List<String> classTable,
    required List<String> statusTable,
    required List<String> cityTable,
    required this.recordCount,
    required this.sourceDate,
    required this.epochDate,
  })  : _stateTable = stateTable,
        _classTable = classTable,
        _statusTable = statusTable,
        _cityTable = cityTable;

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
      await raf.setPosition(h.keysOffset);
      final keys = await raf.read(h.recordCount * keyBytes);
      if (keys.length != h.recordCount * keyBytes) {
        throw const FormatException('Callsign database keys are truncated');
      }
      await raf.setPosition(h.lengthsOffset);
      final lengths = await raf.read(h.recordCount * 2);
      if (lengths.length != h.recordCount * 2) {
        throw const FormatException('Callsign database lengths are truncated');
      }
      await raf.setPosition(h.stateOffset);
      final stateBytes = await raf.read(h.stateCount * 2);
      await raf.setPosition(h.classStatusOffset);
      final csBytes = await raf.read(h.classStatusCount * 2);
      await raf.setPosition(h.cityOffset);
      final cityBytes = await raf.read(h.keysOffset - h.cityOffset);
      final offsets = _buildOffsets(lengths, h.recordCount, h.recordsOffset);
      final classTable = <String>[];
      final statusTable = <String>[];
      _readCsTable(csBytes, 0, h.classStatusCount, classTable, statusTable);
      return CallsignDatabase._(
        raf: raf,
        bytes: null,
        keys: keys,
        offsets: offsets,
        stateTable: _readStateTable(stateBytes, 0, h.stateCount),
        classTable: classTable,
        statusTable: statusTable,
        cityTable: _readCityTable(cityBytes, 0, h.cityCount),
        recordCount: h.recordCount,
        sourceDate: h.sourceDate,
        epochDate: h.epochDate,
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
    final keyBlockBytes = h.recordCount * keyBytes;
    if (h.keysOffset + keyBlockBytes > bytes.length) {
      throw const FormatException('Callsign database keys are truncated');
    }
    final lenBytes = h.recordCount * 2;
    if (h.lengthsOffset + lenBytes > bytes.length) {
      throw const FormatException('Callsign database lengths are truncated');
    }
    final keys = Uint8List.sublistView(
      bytes,
      h.keysOffset,
      h.keysOffset + keyBlockBytes,
    );
    final lengths = Uint8List.sublistView(
      bytes,
      h.lengthsOffset,
      h.lengthsOffset + lenBytes,
    );
    if (h.stateOffset + h.stateCount * 2 > bytes.length ||
        h.classStatusOffset + h.classStatusCount * 2 > bytes.length ||
        h.cityOffset > h.keysOffset ||
        h.keysOffset > bytes.length) {
      throw const FormatException('Callsign database dictionary is truncated');
    }
    final offsets = _buildOffsets(lengths, h.recordCount, h.recordsOffset);
    final classTable = <String>[];
    final statusTable = <String>[];
    _readCsTable(
      bytes,
      h.classStatusOffset,
      h.classStatusCount,
      classTable,
      statusTable,
    );
    return CallsignDatabase._(
      raf: null,
      bytes: bytes,
      keys: keys,
      offsets: offsets,
      stateTable: _readStateTable(bytes, h.stateOffset, h.stateCount),
      classTable: classTable,
      statusTable: statusTable,
      cityTable: _readCityTable(bytes, h.cityOffset, h.cityCount),
      recordCount: h.recordCount,
      sourceDate: h.sourceDate,
      epochDate: h.epochDate,
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
      keysOffset: data.getUint32(12, Endian.little),
      lengthsOffset: data.getUint32(16, Endian.little),
      recordsOffset: data.getUint32(20, Endian.little),
      sourceDate: data.getUint32(24, Endian.little),
      epochDate: data.getUint32(28, Endian.little),
      stateCount: data.getUint16(32, Endian.little),
      classStatusCount: data.getUint16(34, Endian.little),
      stateOffset: data.getUint32(36, Endian.little),
      classStatusOffset: data.getUint32(40, Endian.little),
      cityCount: data.getUint32(44, Endian.little),
      cityOffset: data.getUint32(48, Endian.little),
    );
  }

  /// Prefix-sums the record [lengths] into absolute file offsets. The returned
  /// list has [count] + 1 entries; the last is the end of the records block.
  static Uint32List _buildOffsets(
    Uint8List lengths,
    int count,
    int recordsOffset,
  ) {
    final data = ByteData.sublistView(lengths);
    final offsets = Uint32List(count + 1);
    var cursor = recordsOffset;
    for (var i = 0; i < count; i++) {
      offsets[i] = cursor;
      cursor += data.getUint16(i * 2, Endian.little);
    }
    offsets[count] = cursor;
    return offsets;
  }

  /// Reads [count] 2-byte state codes starting at [offset] in [buf].
  static List<String> _readStateTable(Uint8List buf, int offset, int count) {
    final list = List<String>.filled(count, '', growable: false);
    for (var i = 0; i < count; i++) {
      final a = buf[offset + i * 2];
      final b = buf[offset + i * 2 + 1];
      final chars = <int>[];
      if (a != 0) chars.add(a);
      if (b != 0) chars.add(b);
      list[i] = String.fromCharCodes(chars);
    }
    return list;
  }

  /// Reads [count] 2-byte (class, status) pairs starting at [offset] in [buf]
  /// into [classes] and [statuses].
  static void _readCsTable(
    Uint8List buf,
    int offset,
    int count,
    List<String> classes,
    List<String> statuses,
  ) {
    for (var i = 0; i < count; i++) {
      final cb = buf[offset + i * 2];
      final sb = buf[offset + i * 2 + 1];
      classes.add(cb == 0 ? '' : String.fromCharCode(cb));
      statuses.add(sb == 0 ? '' : String.fromCharCode(sb));
    }
  }

  /// Reads [count] `u8 len + UTF-8` city names starting at [offset] in [buf].
  static List<String> _readCityTable(Uint8List buf, int offset, int count) {
    final list = List<String>.filled(count, '', growable: false);
    var pos = offset;
    for (var i = 0; i < count; i++) {
      final len = buf[pos++];
      list[i] = utf8.decode(
        Uint8List.sublistView(buf, pos, pos + len),
        allowMalformed: true,
      );
      pos += len;
    }
    return list;
  }

  /// Sentinel stored for a missing or non-numeric ZIP.
  static const int _zipNone = 0xFFFFFFFF;

  /// Packs a ZIP string into a u32: the numeric value of a 5- or 9-digit ZIP,
  /// or [_zipNone] when empty or not a plain 5/9-digit code.
  static int _packZip(String zip) {
    if (zip.isEmpty) return _zipNone;
    var digits = 0;
    var n = 0;
    for (var i = 0; i < zip.length; i++) {
      final c = zip.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        if (c == 0x2D || c == 0x20) continue; // ignore hyphen / space
        return _zipNone; // any other character: not a plain numeric ZIP
      }
      digits = digits * 10 + (c - 0x30);
      n++;
    }
    if (n != 5 && n != 9) return _zipNone;
    return digits;
  }

  /// Reverses [_packZip], zero-padding to 5 or 9 digits.
  static String _unpackZip(int v) {
    if (v == _zipNone) return '';
    return v.toString().padLeft(v < 100000 ? 5 : 9, '0');
  }

  /// Looks up [callsign] (SSID is ignored). Returns the matching
  /// [CallsignRecord], or null when not found.
  Future<CallsignRecord?> lookup(String callsign) async {
    final key = _packKey(callsign);
    if (key == null) return null;
    final index = _findIndex(key);
    if (index == null) return null;
    return _readRecord(index);
  }

  /// Packs a callsign into a sortable base-37 key, or null when it has no
  /// usable characters. Character codes are: padding = 0, '0'-'9' = 1-10,
  /// 'A'-'Z' = 11-36, with the real characters in the high base-37 digits so
  /// the packed integers sort identically to the zero-padded callsigns.
  static int? _packKey(String callsign) {
    final upper = callsign.toUpperCase();
    var value = 0;
    var n = 0;
    for (var i = 0; i < upper.length && n < keyChars; i++) {
      final c = upper.codeUnitAt(i);
      if (c == 0x2D) break; // '-' begins the SSID; stop here.
      int code;
      if (c >= 0x30 && c <= 0x39) {
        code = c - 0x30 + 1;
      } else if (c >= 0x41 && c <= 0x5A) {
        code = c - 0x41 + 11;
      } else {
        continue;
      }
      value = value * 37 + code;
      n++;
    }
    if (n == 0) return null;
    for (; n < keyChars; n++) {
      value *= 37;
    }
    return value;
  }

  /// Reverses [_packKey] back into the callsign string.
  static String _unpackKey(int value) {
    final codes = List<int>.filled(keyChars, 0);
    for (var i = keyChars - 1; i >= 0; i--) {
      codes[i] = value % 37;
      value ~/= 37;
    }
    final chars = <int>[];
    for (final code in codes) {
      if (code == 0) break; // padding; the rest are padding too.
      chars.add(code <= 10 ? 0x30 + code - 1 : 0x41 + code - 11);
    }
    return String.fromCharCodes(chars);
  }

  /// Reads the packed key for record [index] from the in-memory keys block.
  int _keyAt(int index) {
    final base = index * keyBytes;
    var v = 0;
    for (var i = 0; i < keyBytes; i++) {
      v = (v << 8) | _keys[base + i];
    }
    return v;
  }

  /// Binary-searches the in-memory keys block for [packedKey], returning the
  /// record index or null when not present.
  int? _findIndex(int packedKey) {
    var lo = 0;
    var hi = recordCount - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final k = _keyAt(mid);
      if (k == packedKey) {
        return mid;
      } else if (k < packedKey) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  Future<CallsignRecord> _readRecord(int index) async {
    final start = _offsets[index];
    final length = _offsets[index + 1] - start;
    final reader = _RecordReader(await _readAt(start, length));
    final name = reader.readString16();
    final cityIndex = reader.readUint24();
    final stateIndex = reader.readByte();
    final csIndex = reader.readByte();
    final zip = _unpackZip(reader.readUint32());
    final expireDate = _daysToDate(reader.readUint16(), epochDate);
    return CallsignRecord(
      callsign: _unpackKey(_keyAt(index)),
      name: name,
      city: cityIndex < _cityTable.length ? _cityTable[cityIndex] : '',
      state: stateIndex < _stateTable.length ? _stateTable[stateIndex] : '',
      zip: zip,
      operatorClass:
          csIndex < _classTable.length ? _classTable[csIndex] : '',
      status: csIndex < _statusTable.length ? _statusTable[csIndex] : '',
      expireDate: expireDate,
    );
  }

  /// Converts a stored `days since epoch` value back to a `YYYYMMDD` integer.
  /// A value of 0 means "unknown" and maps back to 0.
  static int _daysToDate(int days, int epochDate) {
    if (days == 0) return 0;
    final base = _dateFromYyyymmdd(epochDate);
    if (base == null) return 0;
    final dt = base.add(Duration(days: days));
    return dt.year * 10000 + dt.month * 100 + dt.day;
  }

  /// Converts a `YYYYMMDD` date to `days since [epochDate]`, or 0 (unknown)
  /// when the date is missing or outside the representable u16 window.
  static int _dateToDays(int yyyymmdd, int epochDate) {
    if (yyyymmdd == 0) return 0;
    final base = _dateFromYyyymmdd(epochDate);
    final date = _dateFromYyyymmdd(yyyymmdd);
    if (base == null || date == null) return 0;
    final days = date.difference(base).inDays;
    if (days < 1 || days > 0xFFFF) return 0;
    return days;
  }

  /// Parses a `YYYYMMDD` integer into a UTC [DateTime], or null when invalid.
  static DateTime? _dateFromYyyymmdd(int v) {
    if (v <= 0) return null;
    final y = v ~/ 10000;
    final m = (v ~/ 100) % 100;
    final d = v % 100;
    if (y < 1 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime.utc(y, m, d);
  }

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
  static Uint8List build(
    List<CallsignRecord> records, {
    int sourceDate = 0,
    int epochDate = defaultEpochDate,
  }) {
    // Sort by key bytes, dropping records whose callsign yields no key.
    final keyed = <MapEntry<int, CallsignRecord>>[];
    for (final r in records) {
      final key = _packKey(r.callsign);
      if (key != null) keyed.add(MapEntry(key, r));
    }
    keyed.sort((a, b) => a.key.compareTo(b.key));

    // Build the state, class/status and city dictionaries as records are
    // encoded. Records reference each by an index.
    final stateList = <String>[];
    final stateIndex = <String, int>{};
    final csList = <int>[]; // packed (classByte << 8) | statusByte
    final csIndex = <int, int>{};
    final cityList = <String>[];
    final cityIndex = <String, int>{};
    int internState(String s) => stateIndex.putIfAbsent(s, () {
          stateList.add(s);
          return stateList.length - 1;
        });
    int internCs(int packed) => csIndex.putIfAbsent(packed, () {
          csList.add(packed);
          return csList.length - 1;
        });
    int internCity(String s) => cityIndex.putIfAbsent(s, () {
          cityList.add(s);
          return cityList.length - 1;
        });

    // Encode the records section, capturing each record's byte length.
    final recordsBuilder = BytesBuilder();
    final lengths = <int>[];
    for (final entry in keyed) {
      final r = entry.value;
      final si = internState(r.state);
      final ci = internCs(
        (_charByte(r.operatorClass) << 8) | _charByte(r.status),
      );
      final cityI = internCity(r.city);
      final enc = _encodeRecord(r, epochDate, cityI, si, ci);
      lengths.add(enc.length);
      recordsBuilder.add(enc);
    }
    final recordsBytes = recordsBuilder.toBytes();

    if (stateList.length > 0xFFFF ||
        csList.length > 0xFFFF ||
        cityList.length > 0xFFFFFF) {
      throw StateError('dictionary too large for the database format');
    }

    // Encode the city dictionary blob (u8 len + UTF-8 per entry).
    final cityBuilder = BytesBuilder();
    for (final s in cityList) {
      _writeString8(cityBuilder, s);
    }
    final cityBytes = cityBuilder.toBytes();

    final count = keyed.length;
    final stateOffset = headerSize;
    final csOffset = stateOffset + stateList.length * 2;
    final cityOffset = csOffset + csList.length * 2;
    final keysOffset = cityOffset + cityBytes.length;
    final lengthsOffset = keysOffset + count * keyBytes;
    final recordsOffset = lengthsOffset + count * 2;
    final total = recordsOffset + recordsBytes.length;

    final out = Uint8List(total);
    final data = ByteData.sublistView(out);

    // Header.
    data.setUint32(0, magic, Endian.little);
    data.setUint16(4, formatVersion, Endian.little);
    data.setUint16(6, 0, Endian.little);
    data.setUint32(8, count, Endian.little);
    data.setUint32(12, keysOffset, Endian.little);
    data.setUint32(16, lengthsOffset, Endian.little);
    data.setUint32(20, recordsOffset, Endian.little);
    data.setUint32(24, sourceDate, Endian.little);
    data.setUint32(28, epochDate, Endian.little);
    data.setUint16(32, stateList.length, Endian.little);
    data.setUint16(34, csList.length, Endian.little);
    data.setUint32(36, stateOffset, Endian.little);
    data.setUint32(40, csOffset, Endian.little);
    data.setUint32(44, cityList.length, Endian.little);
    data.setUint32(48, cityOffset, Endian.little);

    // State dictionary (2 bytes each).
    var spos = stateOffset;
    for (final s in stateList) {
      out[spos] = s.isNotEmpty ? s.codeUnitAt(0) & 0xFF : 0;
      out[spos + 1] = s.length > 1 ? s.codeUnitAt(1) & 0xFF : 0;
      spos += 2;
    }

    // Class/status dictionary (2 bytes each).
    var cpos = csOffset;
    for (final packed in csList) {
      out[cpos] = (packed >> 8) & 0xFF;
      out[cpos + 1] = packed & 0xFF;
      cpos += 2;
    }

    // City dictionary.
    out.setRange(cityOffset, cityOffset + cityBytes.length, cityBytes);

    // Keys block (6-byte big-endian packed keys).
    var kpos = keysOffset;
    for (var i = 0; i < count; i++) {
      var v = keyed[i].key;
      for (var j = keyBytes - 1; j >= 0; j--) {
        out[kpos + j] = v & 0xFF;
        v >>= 8;
      }
      kpos += keyBytes;
    }

    // Lengths block.
    var lpos = lengthsOffset;
    for (var i = 0; i < count; i++) {
      data.setUint16(lpos, lengths[i], Endian.little);
      lpos += 2;
    }

    // Records block.
    out.setRange(recordsOffset, total, recordsBytes);
    return out;
  }

  static Uint8List _encodeRecord(
    CallsignRecord r,
    int epochDate,
    int cityIndex,
    int stateIndex,
    int csIndex,
  ) {
    // The callsign is reconstructed from the key; city, state and class/status
    // are dictionary indices; the ZIP is packed numerically.
    final b = BytesBuilder();
    _writeString16(b, r.name);
    b.addByte(cityIndex & 0xFF);
    b.addByte((cityIndex >> 8) & 0xFF);
    b.addByte((cityIndex >> 16) & 0xFF);
    b.addByte(stateIndex & 0xFF);
    b.addByte(csIndex & 0xFF);
    final zip = _packZip(r.zip);
    b.addByte(zip & 0xFF);
    b.addByte((zip >> 8) & 0xFF);
    b.addByte((zip >> 16) & 0xFF);
    b.addByte((zip >> 24) & 0xFF);
    final days = _dateToDays(r.expireDate, epochDate);
    b.addByte(days & 0xFF);
    b.addByte((days >> 8) & 0xFF);
    return b.toBytes();
  }

  static void _writeString16(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    final len = bytes.length > 0xFFFF ? 0xFFFF : bytes.length;
    b.addByte(len & 0xFF);
    b.addByte((len >> 8) & 0xFF);
    b.add(len == bytes.length ? bytes : bytes.sublist(0, len));
  }

  static void _writeString8(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    final len = bytes.length > 0xFF ? 0xFF : bytes.length;
    b.addByte(len);
    b.add(len == bytes.length ? bytes : bytes.sublist(0, len));
  }

  static int _charByte(String s) => s.isEmpty ? 0 : s.codeUnitAt(0) & 0xFF;
}

class _Header {
  final int recordCount;
  final int keysOffset;
  final int lengthsOffset;
  final int recordsOffset;
  final int sourceDate;
  final int epochDate;
  final int stateCount;
  final int classStatusCount;
  final int stateOffset;
  final int classStatusOffset;
  final int cityCount;
  final int cityOffset;
  const _Header({
    required this.recordCount,
    required this.keysOffset,
    required this.lengthsOffset,
    required this.recordsOffset,
    required this.sourceDate,
    required this.epochDate,
    required this.stateCount,
    required this.classStatusCount,
    required this.stateOffset,
    required this.classStatusOffset,
    required this.cityCount,
    required this.cityOffset,
  });
}

/// Sequential reader over an encoded record buffer.
class _RecordReader {
  final Uint8List _b;
  final ByteData _d;
  int _pos = 0;
  _RecordReader(this._b) : _d = ByteData.sublistView(_b);

  String readString16() {
    final len = _b[_pos] | (_b[_pos + 1] << 8);
    _pos += 2;
    final s = utf8.decode(
      Uint8List.sublistView(_b, _pos, _pos + len),
      allowMalformed: true,
    );
    _pos += len;
    return s;
  }

  int readByte() {
    return _b[_pos++];
  }

  int readUint16() {
    final v = _d.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int readUint24() {
    final v = _b[_pos] | (_b[_pos + 1] << 8) | (_b[_pos + 2] << 16);
    _pos += 3;
    return v;
  }

  int readUint32() {
    final v = _d.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }
}
