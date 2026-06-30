/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:es_compression/brotli.dart';

/// Torrent compression algorithms.
///
/// The 1-byte wire tag written at the front of a compressed payload uses the
/// C# `TorrentFile.TorrentCompression` values (NOT the Dart enum ordinals):
///   Unknown = -1, None = 0, Deflate = 1, Brotli = 2
/// Use [CompressionWire.wireByte] / [CompressionWire.fromWireByte] for any
/// on-air or on-disk tag conversion rather than `index`.
enum TorrentCompression { unknown, none, deflate, brotli }

/// Maps [TorrentCompression] to/from the C# wire tag byte.
extension CompressionWire on TorrentCompression {
  /// The byte written as the compression tag (matches the C# enum values).
  int get wireByte {
    switch (this) {
      case TorrentCompression.none:
        return 0;
      case TorrentCompression.deflate:
        return 1;
      case TorrentCompression.brotli:
        return 2;
      case TorrentCompression.unknown:
        return 0xFF; // C# -1 as an unsigned byte; never actually transmitted.
    }
  }

  /// Decodes a compression tag byte back into a [TorrentCompression].
  static TorrentCompression fromWireByte(int b) {
    switch (b) {
      case 0:
        return TorrentCompression.none;
      case 1:
        return TorrentCompression.deflate;
      case 2:
        return TorrentCompression.brotli;
      default:
        return TorrentCompression.unknown;
    }
  }
}

/// Compression helpers used by the Torrent feature.
///
/// Port of the C# `Utils.Compress*/Decompress*` methods. Deflate uses *raw*
/// DEFLATE (no zlib header/checksum) to match .NET's `DeflateStream`, and
/// Brotli uses the native `es_compression` codec so the output is byte-for-byte
/// interoperable with the C# implementation.
class Compression {
  Compression._();

  // Raw DEFLATE (no zlib header) to match .NET DeflateStream.
  static final ZLibCodec _rawDeflate = ZLibCodec(raw: true);

  /// Compresses [data] with raw DEFLATE.
  static Uint8List compressDeflate(Uint8List data) {
    return Uint8List.fromList(_rawDeflate.encode(data));
  }

  /// Decompresses raw DEFLATE [data], optionally starting at [offset] for
  /// [length] bytes (defaults to the whole buffer).
  static Uint8List decompressDeflate(
    Uint8List data, [
    int offset = 0,
    int? length,
  ]) {
    final slice = (offset == 0 && length == null)
        ? data
        : Uint8List.sublistView(
            data,
            offset,
            length == null ? null : offset + length,
          );
    return Uint8List.fromList(_rawDeflate.decode(slice));
  }

  /// Compresses [data] with Brotli.
  static Uint8List compressBrotli(Uint8List data) {
    return Uint8List.fromList(brotli.encode(data));
  }

  /// Decompresses Brotli [data], optionally starting at [offset] for [length]
  /// bytes (defaults to the whole buffer).
  static Uint8List decompressBrotli(
    Uint8List data, [
    int offset = 0,
    int? length,
  ]) {
    final slice = (offset == 0 && length == null)
        ? data
        : Uint8List.sublistView(
            data,
            offset,
            length == null ? null : offset + length,
          );
    return Uint8List.fromList(brotli.decode(slice));
  }

  /// Result of [chooseBest]: the selected algorithm and the compressed bytes
  /// (NOT including the leading tag byte).
  static ({TorrentCompression compression, Uint8List data}) chooseBest(
    Uint8List raw,
  ) {
    Uint8List? deflated;
    Uint8List? brotlid;
    try {
      deflated = compressDeflate(raw);
    } catch (_) {
      deflated = null;
    }
    try {
      brotlid = compressBrotli(raw);
    } catch (_) {
      brotlid = null;
    }

    // Mirror the C# selection: prefer Deflate if it is strictly the smallest,
    // else Brotli if it is strictly the smallest, otherwise None.
    final rawLen = raw.length;
    final dLen = deflated?.length ?? (rawLen + 1);
    final bLen = brotlid?.length ?? (rawLen + 1);

    if (deflated != null && dLen < bLen && dLen < rawLen) {
      return (compression: TorrentCompression.deflate, data: deflated);
    } else if (brotlid != null && bLen < dLen && bLen < rawLen) {
      return (compression: TorrentCompression.brotli, data: brotlid);
    } else {
      return (compression: TorrentCompression.none, data: raw);
    }
  }

  /// Decompresses a tagged payload whose first byte is the [TorrentCompression]
  /// value (as produced by [tagAndPack]). Returns the original bytes.
  static Uint8List decompressTagged(Uint8List tagged) {
    if (tagged.isEmpty) return Uint8List(0);
    final compression = CompressionWire.fromWireByte(tagged[0]);
    switch (compression) {
      case TorrentCompression.deflate:
        return decompressDeflate(tagged, 1, tagged.length - 1);
      case TorrentCompression.brotli:
        return decompressBrotli(tagged, 1, tagged.length - 1);
      case TorrentCompression.none:
      case TorrentCompression.unknown:
        return Uint8List.sublistView(tagged, 1);
    }
  }

  /// Prepends the 1-byte compression tag to [data], producing the on-air /
  /// on-disk payload format used by the Torrent protocol.
  static Uint8List tagAndPack(TorrentCompression compression, Uint8List data) {
    final out = Uint8List(data.length + 1);
    out[0] = compression.wireByte;
    out.setRange(1, out.length, data);
    return out;
  }
}
