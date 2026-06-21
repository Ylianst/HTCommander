/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/compression.dart';

/// Sharing mode for a torrent file (port of C# `TorrentFile.TorrentModes`).
enum TorrentMode { pause, sharing, request, error }

/// A file shared/transferred via the Torrent feature.
///
/// Direct port of the C# `TorrentFile`. A file's bytes are wrapped as
/// `[nameLen][name][fileBytes]`, compressed, prefixed with a 1-byte
/// [TorrentCompression] tag, hashed with SHA-256, and split into
/// fixed-size blocks. The first 12 bytes of the hash form [id]; the first 6
/// (with a station-file flag in the low bits of byte 5) form [shortId].
class TorrentFile {
  /// First 12 bytes of the SHA-256 hash of the compressed (tagged) payload.
  Uint8List? id;

  String callsign = '';
  int stationId = 0;
  String fileName = '';
  String description = '';

  /// Uncompressed size of the wrapped payload.
  int size = 0;

  /// Compressed size including the 1-byte compression tag.
  int compressedSize = 0;

  TorrentCompression compression = TorrentCompression.unknown;
  TorrentMode mode = TorrentMode.pause;
  bool completed = false;

  /// True when this object carries a station's advertised file list rather than
  /// an actual shared file.
  bool stationFile = false;

  /// Whether the last block has been received (used while downloading before
  /// the total block count is known for certain).
  bool receivedLastBlock = false;

  /// Per-block data; `null` entries are blocks not yet received.
  List<Uint8List?>? blocks;

  TorrentFile();

  Uint8List? _shortId;

  /// First 6 bytes of [id]; the low 2 bits of byte 5 are cleared and bit 1 is
  /// set when [stationFile] is true (matches the C# `ShortId` getter).
  Uint8List get shortId {
    final base = _shortId ??= () {
      final s = Uint8List(6);
      if (id != null) {
        s.setRange(0, 6, id!.sublist(0, id!.length < 6 ? id!.length : 6));
      }
      return s;
    }();
    base[5] = (base[5] & 0xFC) + (stationFile ? 2 : 0);
    return base;
  }

  /// Total number of blocks (0 when [blocks] is null).
  int get totalBlocks => blocks?.length ?? 0;

  /// Number of blocks received so far.
  int get receivedBlocks {
    final b = blocks;
    if (b == null) return 0;
    var count = 0;
    for (final block in b) {
      if (block != null) count++;
    }
    return count;
  }

  /// Download/sharing progress in the range 0..1.
  double get progress => totalBlocks > 0 ? receivedBlocks / totalBlocks : 0.0;

  /// Human-friendly source (callsign with optional station id).
  String get source => stationId > 0 ? '$callsign-$stationId' : callsign;

  /// Reassembles all blocks into the compressed (tagged) payload, or `null` if
  /// any block is still missing.
  Uint8List? getRawBlocks() {
    final b = blocks;
    if (b == null) return null;
    var totalSize = 0;
    for (final block in b) {
      if (block == null) return null;
      totalSize += block.length;
    }
    final out = Uint8List(totalSize);
    var offset = 0;
    for (final block in b) {
      out.setRange(offset, offset + block!.length, block);
      offset += block.length;
    }
    return out;
  }

  /// Returns the decoded file bytes, or `null` if incomplete.
  ///
  /// Reassembles the blocks, strips the compression tag, decompresses, then
  /// strips the `[nameLen][name]` header to recover the original file.
  Uint8List? getFileData() {
    final tagged = getRawBlocks();
    if (tagged == null) return null;
    final decompressed = Compression.decompressTagged(tagged);
    if (decompressed.isEmpty) return null;
    final nameLen = decompressed[0];
    if (decompressed.length < 1 + nameLen) return null;
    return Uint8List.sublistView(decompressed, 1 + nameLen);
  }

  /// Checks completion state:
  ///   * 1 = all blocks present and the SHA-256 of the reassembled payload
  ///         matches [id] (complete + valid).
  ///   * 2 = all blocks present but the hash does not match (error).
  ///   * 0 = still incomplete.
  int isCompleted() {
    final tagged = getRawBlocks();
    if (tagged == null) return 0;
    if (id == null) return 0;
    final hash = sha256.convert(tagged).bytes;
    final len = id!.length;
    for (var i = 0; i < len; i++) {
      if (hash[i] != id![i]) return 2;
    }
    return 1;
  }

  /// Builds the JSON-friendly map dispatched to the UI on the DataBroker,
  /// matching the C# `PublishFileUpdate`/`PublishFilesUpdate` shape.
  Map<String, dynamic> toBrokerMap() {
    return {
      'Id': id == null ? null : base64Encode(id!),
      'ShortId': base64Encode(shortId),
      'Callsign': callsign,
      'StationId': stationId,
      'FileName': fileName,
      'Description': description,
      'Size': size,
      'CompressedSize': compressedSize,
      'Compression': _compressionName(compression),
      'Mode': _modeName(mode),
      'Completed': completed,
      'StationFile': stationFile,
      'TotalBlocks': totalBlocks,
      'ReceivedBlocks': receivedBlocks,
      'Progress': progress,
    };
  }

  /// Full persistence map (includes block data) for saving to disk.
  Map<String, dynamic> toStorageMap() {
    final map = toBrokerMap();
    map['ReceivedLastBlock'] = receivedLastBlock;
    map['Blocks'] = blocks
        ?.map((b) => b == null ? null : base64Encode(b))
        .toList();
    return map;
  }

  /// Restores a [TorrentFile] from a [toStorageMap] map.
  static TorrentFile fromStorageMap(Map<String, dynamic> map) {
    final file = TorrentFile()
      ..id = _decodeBytes(map['Id'])
      ..callsign = (map['Callsign'] as String?) ?? ''
      ..stationId = (map['StationId'] as int?) ?? 0
      ..fileName = (map['FileName'] as String?) ?? ''
      ..description = (map['Description'] as String?) ?? ''
      ..size = (map['Size'] as int?) ?? 0
      ..compressedSize = (map['CompressedSize'] as int?) ?? 0
      ..compression = _compressionFromName(map['Compression'] as String?)
      ..mode = _modeFromName(map['Mode'] as String?)
      ..completed = (map['Completed'] as bool?) ?? false
      ..stationFile = (map['StationFile'] as bool?) ?? false
      ..receivedLastBlock = (map['ReceivedLastBlock'] as bool?) ?? false;
    final blocksRaw = map['Blocks'] as List<dynamic>?;
    if (blocksRaw != null) {
      file.blocks = blocksRaw
          .map((b) => b == null ? null : _decodeBytes(b))
          .toList();
    }
    return file;
  }

  static Uint8List? _decodeBytes(dynamic value) {
    if (value == null) return null;
    if (value is String) return Uint8List.fromList(base64Decode(value));
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  static String _compressionName(TorrentCompression c) {
    switch (c) {
      case TorrentCompression.unknown:
        return 'Unknown';
      case TorrentCompression.none:
        return 'None';
      case TorrentCompression.deflate:
        return 'Deflate';
      case TorrentCompression.brotli:
        return 'Brotli';
    }
  }

  static TorrentCompression _compressionFromName(String? name) {
    switch (name) {
      case 'None':
        return TorrentCompression.none;
      case 'Deflate':
        return TorrentCompression.deflate;
      case 'Brotli':
        return TorrentCompression.brotli;
      default:
        return TorrentCompression.unknown;
    }
  }

  static String _modeName(TorrentMode m) {
    switch (m) {
      case TorrentMode.pause:
        return 'Pause';
      case TorrentMode.sharing:
        return 'Sharing';
      case TorrentMode.request:
        return 'Request';
      case TorrentMode.error:
        return 'Error';
    }
  }

  static TorrentMode _modeFromName(String? name) {
    switch (name) {
      case 'Sharing':
        return TorrentMode.sharing;
      case 'Request':
        return TorrentMode.request;
      case 'Error':
        return TorrentMode.error;
      case 'Pause':
      default:
        return TorrentMode.pause;
    }
  }
}
