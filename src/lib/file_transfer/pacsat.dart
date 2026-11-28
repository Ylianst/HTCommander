import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show listEquals;

const pacsatMaxBody = 1474560;
const pacsatMaxOriginal = 50000000;
const pacsatPieceSize = 245;

int _read(List<int> bytes, int offset, int size) {
  if (offset < 0 || offset + size > bytes.length) {
    throw const FormatException('Truncated PACSAT integer');
  }
  var value = 0;
  for (var i = 0; i < size; i++) {
    value |= bytes[offset + i] << (8 * i);
  }
  return value;
}

List<int> _write(int value, int size) {
  if (value < 0 || value >= 1 << (8 * size)) {
    throw const FormatException('PACSAT integer out of range');
  }
  return List.generate(size, (i) => (value >> (8 * i)) & 255);
}

int pacsatCrc(List<int> bytes) {
  var crc = 0;
  for (final byte in bytes) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = ((crc << 1) ^ ((crc & 0x8000) != 0 ? 0x1021 : 0)) & 65535;
    }
  }
  return crc;
}

Uint8List _withCrc(List<int> bytes) {
  final crc = pacsatCrc(bytes);
  return Uint8List.fromList([...bytes, crc >> 8, crc & 255]);
}

String normalizeFileCallsign(String value) {
  final call = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$').hasMatch(call)) {
    throw const FormatException('Invalid callsign or SSID');
  }
  return call.endsWith('-0') ? call.substring(0, call.length - 2) : call;
}

class FileHole {
  final int offset;
  final int length;
  const FileHole(this.offset, this.length);
  int get end => offset + length;
}

class PacsatRequest {
  final int command;
  final int fileId;
  final int pieceSize;
  final List<FileHole> holes;
  const PacsatRequest(this.command, this.fileId, {
    this.pieceSize = pacsatPieceSize,
    this.holes = const [],
  });

  Uint8List encode() {
    if (command < 0 || command > 2 || pieceSize < 1 ||
        pieceSize > pacsatPieceSize || (command != 2 && holes.isNotEmpty) ||
        holes.length > 49) {
      throw const FormatException('Invalid PACSAT request');
    }
    return Uint8List.fromList([
      0x10 | command, ..._write(fileId, 4), ..._write(pieceSize, 2),
      for (final hole in holes) ...[
        ..._write(hole.offset, 3), ..._write(hole.length, 2),
      ],
    ]);
  }

  factory PacsatRequest.decode(Uint8List bytes) {
    if (bytes.length < 7 || bytes.length > 256 ||
        (bytes[0] & 0xfc) != 0x10 || (bytes[0] & 3) == 3) {
      throw const FormatException('Invalid PACSAT request header');
    }
    final command = bytes[0] & 3;
    final size = _read(bytes, 5, 2);
    if (size < 1 || size > pacsatPieceSize ||
        (command != 2 && bytes.length != 7) ||
        (bytes.length - 7) % 5 != 0) {
      throw const FormatException('Invalid PACSAT request length or piece size');
    }
    final holes = <FileHole>[];
    for (var i = 7; i < bytes.length; i += 5) {
      final hole = FileHole(_read(bytes, i, 3), _read(bytes, i + 3, 2));
      if (hole.length == 0 || hole.end > 0x1000000) {
        throw const FormatException('Invalid PACSAT hole');
      }
      holes.add(hole);
    }
    return PacsatRequest(command, _read(bytes, 1, 4),
      pieceSize: size, holes: holes);
  }
}

class PacsatPiece {
  final bool directory;
  final bool last;
  final int fileId;
  final int fileType;
  final int offset;
  final int uploadTime;
  final Uint8List bytes;

  const PacsatPiece({
    required this.directory,
    required this.last,
    required this.fileId,
    required this.offset,
    required this.bytes,
    this.fileType = 0,
    this.uploadTime = 0,
  });

  Uint8List encode() {
    if (bytes.isEmpty || bytes.length > (directory ? 237 : pacsatPieceSize)) {
      throw const FormatException('Invalid PACSAT piece length');
    }
    return _withCrc([
      directory ? (last ? 0x60 : 0x40) : (last ? 0x22 : 0x02),
      ..._write(fileId, 4),
      if (directory) ...[
        ..._write(offset, 4), ..._write(uploadTime, 4), ..._write(uploadTime, 4),
      ] else ...[
        fileType, ..._write(offset, 3),
      ],
      ...bytes,
    ]);
  }

  factory PacsatPiece.decode(Uint8List bytes, {required bool directory}) {
    final headerSize = directory ? 17 : 9;
    if (bytes.length < headerSize + 3 || bytes.length > 256 ||
        pacsatCrc(bytes) != 0 ||
        (directory ? (bytes[0] & 0x9f) != 0 : (bytes[0] & 0xdf) != 2)) {
      throw const FormatException('Invalid PACSAT piece, flags or CRC');
    }
    return PacsatPiece(
      directory: directory, last: (bytes[0] & 0x20) != 0,
      fileId: _read(bytes, 1, 4),
      offset: _read(bytes, directory ? 5 : 6, directory ? 4 : 3),
      fileType: directory ? 0 : bytes[5],
      uploadTime: directory ? _read(bytes, 13, 4) : 0,
      bytes: Uint8List.sublistView(bytes, headerSize, bytes.length - 2),
    );
  }
}

class PacsatFile {
  final Uint8List header;
  final int fileId;
  final int size;
  final int fileType;
  final String name;
  final String destination;
  final int uploadTime;
  final int bodyChecksum;
  final Uint8List digest;
  final bool compressed;
  final int originalSize;

  const PacsatFile._({
    required this.header, required this.fileId, required this.size,
    required this.fileType, required this.name, required this.destination,
    required this.uploadTime, required this.bodyChecksum, required this.digest,
    required this.compressed, required this.originalSize,
  });
  int get bodySize => size - header.length;

  factory PacsatFile.fromBytes(Uint8List bytes) {
    var offset = 2;
    while (offset + 3 <= bytes.length && offset + 3 <= 65535) {
      final id = _read(bytes, offset, 2);
      final length = bytes[offset + 2];
      offset += 3;
      if (id == 0 && length == 0) {
        return PacsatFile.parse(Uint8List.sublistView(bytes, 0, offset));
      }
      offset += length;
    }
    throw const FormatException('Missing PACSAT file header');
  }

  factory PacsatFile.parse(Uint8List header) {
    if (header.length < 5 || header.length > 65535 ||
        header[0] != 0xaa || header[1] != 0x55) {
      throw const FormatException('Invalid PACSAT file header');
    }
    final items = <int, Uint8List>{};
    var offset = 2;
    var checksumOffset = -1;
    var terminated = false;
    var previous = 0;
    while (offset + 3 <= header.length) {
      final id = _read(header, offset, 2);
      final length = header[offset + 2];
      offset += 3;
      if (id == 0) {
        if (length != 0 || offset != header.length) {
          throw const FormatException('Invalid PACSAT header terminator');
        }
        terminated = true;
        break;
      }
      if (offset + length > header.length || items.containsKey(id) ||
          (previous < 0x0b && id != previous + 1) ||
          (id <= 0x0b && id <= previous)) {
        throw const FormatException('Truncated, duplicate or unordered PFH item');
      }
      if (id <= 0x0b) previous = id;
      items[id] = Uint8List.sublistView(header, offset, offset + length);
      if (id == 10) checksumOffset = offset;
      offset += length;
    }
    const widths = {1:4, 2:8, 3:3, 4:4, 5:4, 6:4, 7:1, 8:1, 9:2, 10:2, 11:2};
    for (final entry in widths.entries) {
      if (items[entry.key]?.length != entry.value) {
        throw const FormatException('Missing or invalid mandatory PFH item');
      }
    }
    if (!terminated || checksumOffset < 0 || items[0x14] == null ||
        items[0x8001]?.length != 32 || items[0x12]?.length != 4) {
      throw const FormatException('Incomplete APRSConnect file header');
    }
    var sum = 0;
    for (var i = 0; i < header.length; i++) {
      if (i != checksumOffset && i != checksumOffset + 1) sum += header[i];
    }
    if ((sum & 65535) != _read(items[10]!, 0, 2) ||
        _read(items[11]!, 0, 2) != header.length) {
      throw const FormatException('PFH checksum or body offset mismatch');
    }
    final size = _read(items[4]!, 0, 4);
    if (size < header.length || size - header.length > pacsatMaxBody) {
      throw const FormatException('File exceeds the PACSAT body limit');
    }
    final compression = items[0x19];
    if (compression != null && compression.length != 1) {
      throw const FormatException('Invalid compression item');
    }
    final compressed = compression != null && compression[0] != 0;
    if (compressed && (compression[0] != 255 ||
        ascii.decode(items[0x25] ?? []) != 'gzip (RFC 1952)' ||
        items[0x8003]?.length != 4)) {
      throw const FormatException('Unsupported PACSAT compression');
    }
    final original = compressed ? _read(items[0x8003]!, 0, 4) : size - header.length;
    if (original > pacsatMaxOriginal) {
      throw const FormatException('Uncompressed file exceeds 50 MB');
    }
    final name = items[0x8002] != null
        ? utf8.decode(items[0x8002]!)
        : ascii.decode(items[0x26] ?? []).trim();
    if (name.isEmpty) throw const FormatException('Missing file name');
    final dest = ascii.decode(items[0x14]!).trim().toUpperCase();
    return PacsatFile._(
      header: Uint8List.fromList(header), fileId: _read(items[1]!, 0, 4),
      size: size, fileType: items[8]![0], name: name,
      destination: dest == 'ALL' ? dest : normalizeFileCallsign(dest),
      uploadTime: _read(items[0x12]!, 0, 4),
      bodyChecksum: _read(items[9]!, 0, 2), digest: items[0x8001]!,
      compressed: compressed, originalSize: original,
    );
  }

  static Uint8List create({
    required int fileId, required String name, required String source,
    required String destination, required Uint8List content, required DateTime time,
  }) {
    if (content.length > pacsatMaxOriginal || utf8.encode(name).length > 255 ||
        name.isEmpty) {
      throw const FormatException('File size or name exceeds the supported limit');
    }
    final packed = gzip.encode(content);
    final compressed = packed.length <= content.length - 64 &&
        20 * packed.length <= 19 * content.length;
    final body = compressed ? packed : content;
    if (body.length > pacsatMaxBody) {
      throw const FormatException('Transmitted body exceeds 1,474,560 bytes');
    }
    final stamp = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    final text = name.toLowerCase().endsWith('.txt');
    final fallback = name.runes.map((c) => c >= 32 && c <= 126 ? c : 95).toList();
    final baseCall = normalizeFileCallsign(source).split('-').first;
    final fields = <int, List<int>>{
      1:_write(fileId,4), 2:List.filled(8,32), 3:List.filled(3,32),
      4:_write(0,4), 5:_write(stamp,4), 6:_write(stamp,4), 7:[0],
      8:[text ? 0 : 255], 9:_write(body.fold<int>(0,(a,b)=>a+b)&65535,2),
      10:[0,0], 11:[0,0], 0x10:ascii.encode(source),
      0x11:ascii.encode(baseCall.padRight(6)), 0x12:_write(stamp,4),
      0x13:[0], 0x14:ascii.encode(normalizeFileCallsign(destination)),
      0x15:List.filled(6,32), 0x16:_write(0,4), 0x17:_write(0,4),
      0x18:[0], 0x19:[compressed ? 255 : 0],
      if (!text) 0x24:ascii.encode(_mime(name)),
      if (compressed) 0x25:ascii.encode('gzip (RFC 1952)'),
      0x26:fallback, 0x8001:sha256.convert(body).bytes,
      if (fallback.any((c)=>c==95) && name.codeUnits.any((c)=>c>126 || c<32))
        0x8002:utf8.encode(name),
      if (compressed) 0x8003:_write(content.length,4),
    };
    List<int> build() => [
      0xaa,0x55,
      for (final entry in fields.entries) ...[
        ..._write(entry.key,2), entry.value.length, ...entry.value,
      ],
      0,0,0,
    ];
    final length = build().length;
    fields[4] = _write(length + body.length,4);
    fields[11] = _write(length,2);
    fields[10] = _write(build().fold<int>(0,(a,b)=>a+b)&65535,2);
    return Uint8List.fromList([...build(),...body]);
  }

  Uint8List verify(Uint8List wholeFile) {
    if (wholeFile.length != size ||
        !listEquals(header, wholeFile.sublist(0, header.length))) {
      throw const FormatException('File header or length mismatch');
    }
    final body = Uint8List.sublistView(wholeFile,header.length);
    if ((body.fold<int>(0,(a,b)=>a+b)&65535) != bodyChecksum ||
        !listEquals(digest,sha256.convert(body).bytes)) {
      throw const FormatException('File checksum or SHA-256 mismatch');
    }
    if (!compressed) return Uint8List.fromList(body);
    final output = _BoundedBytes(originalSize);
    final decoder = gzip.decoder.startChunkedConversion(output);
    decoder.add(body);
    decoder.close();
    final decoded = output.bytes.takeBytes();
    if (decoded.length != originalSize) {
      throw const FormatException('Inflated file length mismatch');
    }
    return decoded;
  }
}

class _BoundedBytes implements Sink<List<int>> {
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  _BoundedBytes(this.limit);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit || bytes.length + data.length > pacsatMaxOriginal) {
      throw const FormatException('Inflated file exceeds its advertised size');
    }
    bytes.add(data);
  }
  @override
  void close() {}
}

String _mime(String name) => switch(name.toLowerCase().split('.').last) {
  'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'gif' => 'image/gif',
  'pdf' => 'application/pdf', 'csv' => 'text/csv', 'json' => 'application/json',
  _ => 'application/octet-stream',
};

class PacsatBuffer {
  final Uint8List bytes;
  List<FileHole> missing;
  PacsatBuffer(int length) : bytes = Uint8List(length),
    missing = length == 0 ? [] : [FileHole(0,length)];
  int get received => bytes.length - missing.fold<int>(0,(n,h)=>n+h.length);
  bool get complete => missing.isEmpty;

  void add(int offset, List<int> data) {
    final end = offset + data.length;
    if (offset < 0 || end > bytes.length) {
      throw const FormatException('PACSAT piece outside file');
    }
    for (var i=0;i<data.length;i++) {
      if (!missing.any((h)=>offset+i>=h.offset && offset+i<h.end) &&
          bytes[offset+i]!=data[i]) {
        throw const FormatException('Conflicting PACSAT file bytes');
      }
    }
    final next = <FileHole>[];
    for (final h in missing) {
      if (end <= h.offset || offset >= h.end) {
        next.add(h);
      } else {
        if (h.offset < offset) next.add(FileHole(h.offset,offset-h.offset));
        if (h.end > end) next.add(FileHole(end,h.end-end));
      }
    }
    if (next.length > 4096) throw const FormatException('Too many file holes');
    bytes.setRange(offset,end,data);
    missing = next;
  }

  List<FileHole> requestHoles() => [
    for (final hole in missing)
      for (var at=hole.offset;at<hole.end;at+=65535)
        FileHole(at,(hole.end-at).clamp(1,65535)),
  ];
}
