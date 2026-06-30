/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Native (desktop/mobile) tile provider that caches OpenStreetMap tiles to
/// disk so the map keeps working without an internet connection.
///
///   * Online: tiles are served from the on-disk cache when present, otherwise
///     fetched from the network and saved for later offline use.
///   * Offline ([offline] == true): the network is never contacted. Tiles
///     already in the cache are shown; tiles that were never cached render as a
///     transparent image (the map background shows through).
TileProvider createMapTileProvider({required bool offline}) =>
    CachedMapTileProvider(offline: offline);

/// See [createMapTileProvider].
class CachedMapTileProvider extends TileProvider {
  CachedMapTileProvider({required this.offline});

  /// When true, no network requests are made; only cached tiles are returned.
  final bool offline;

  final http.Client _client = http.Client();

  // Resolved once per process; the cache directory is shared by every provider
  // instance regardless of online/offline state.
  static Future<Directory>? _cacheDirFuture;

  static Future<Directory> cacheDir() {
    return _cacheDirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/map_tile_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }();
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      url: getTileUrl(coordinates, options),
      coordinates: coordinates,
      headers: headers,
      offline: offline,
      client: _client,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

@immutable
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({
    required this.url,
    required this.coordinates,
    required this.headers,
    required this.offline,
    required this.client,
  });

  final String url;
  final TileCoordinates coordinates;
  final Map<String, String> headers;
  final bool offline;
  final http.Client client;

  @override
  SynchronousFuture<_CachedTileImage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: url,
  );

  Future<Codec> _load(_CachedTileImage key, ImageDecoderCallback decode) async {
    final bytes = await _resolveBytes();
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _resolveBytes() async {
    final dir = await CachedMapTileProvider.cacheDir();
    final file = File(
      '${dir.path}/${coordinates.z}_${coordinates.x}_${coordinates.y}.png',
    );

    // Serve from the on-disk cache whenever the tile is already present.
    if (await file.exists()) {
      try {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) return cached;
      } catch (_) {
        // Corrupt/locked cache entry: fall through to network or transparent.
      }
    }

    // Offline mode never touches the network. When the exact tile was never
    // cached, try to synthesize it by zooming into a cached lower-zoom
    // ("parent") tile so the map stays filled (blurrier) instead of blank.
    // If no usable ancestor is cached either, fall back to a transparent tile
    // so the map background (and any markers) remain visible.
    if (offline) {
      final upscaled = await _ancestorTileBytes(dir);
      return upscaled ?? TileProvider.transparentImage;
    }

    // Online: fetch from the network and populate the cache for offline use.
    try {
      final response = await client.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        unawaited(_writeCache(file, response.bodyBytes));
        return response.bodyBytes;
      }
    } catch (_) {
      // Network failure (e.g. connectivity lost): fall back to transparent.
    }
    return TileProvider.transparentImage;
  }

  /// Attempts to build this tile from a cached lower-zoom ancestor ("parent")
  /// tile by cropping the quadrant that this tile covers and scaling it up to a
  /// full tile. Returns PNG bytes, or null when no usable ancestor is cached.
  ///
  /// Only used in offline mode to fill gaps where the exact-zoom tile was never
  /// cached: the result is blurry (over-zoomed) but keeps the map continuous
  /// instead of showing blank squares. Walks up several zoom levels, preferring
  /// the closest (sharpest) cached ancestor.
  Future<Uint8List?> _ancestorTileBytes(Directory dir) async {
    const maxLevels = 5;
    for (var k = 1; k <= maxLevels; k++) {
      final z = coordinates.z - k;
      if (z < 0) break;

      final factor = 1 << k; // tiles-per-side covered by one ancestor tile
      final px = coordinates.x >> k;
      final py = coordinates.y >> k;
      final file = File('${dir.path}/${z}_${px}_$py.png');
      if (!await file.exists()) continue;

      Uint8List parentBytes;
      try {
        parentBytes = await file.readAsBytes();
      } catch (_) {
        continue;
      }
      if (parentBytes.isEmpty) continue;

      try {
        final codec = await instantiateImageCodec(parentBytes);
        final frame = await codec.getNextFrame();
        final src = frame.image;

        // Sub-rectangle of the parent tile that this tile corresponds to.
        final size = src.width.toDouble();
        final sub = size / factor;
        final subX = (coordinates.x - (px << k)).toDouble();
        final subY = (coordinates.y - (py << k)).toDouble();
        final srcRect = Rect.fromLTWH(subX * sub, subY * sub, sub, sub);
        final dstRect = Rect.fromLTWH(0, 0, size, size);

        final recorder = PictureRecorder();
        Canvas(recorder).drawImageRect(
          src,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        final outImage = await picture.toImage(src.width, src.height);
        final byteData = await outImage.toByteData(format: ImageByteFormat.png);

        src.dispose();
        codec.dispose();
        picture.dispose();
        outImage.dispose();

        if (byteData != null) return byteData.buffer.asUint8List();
      } catch (_) {
        // Could not decode/scale this ancestor; try the next level up.
        continue;
      }
    }
    return null;
  }

  Future<void> _writeCache(File file, Uint8List bytes) async {
    try {
      await file.writeAsBytes(bytes);
    } catch (_) {
      // Ignore cache write failures; they only affect future offline use.
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CachedTileImage &&
          other.url == url &&
          other.offline == offline);

  @override
  int get hashCode => Object.hash(url, offline);
}
