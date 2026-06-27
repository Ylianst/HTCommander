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
  ) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
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

    // Offline mode never touches the network. Tiles that were never cached are
    // shown transparent so the map background (and any markers) remain visible.
    if (offline) return TileProvider.transparentImage;

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
