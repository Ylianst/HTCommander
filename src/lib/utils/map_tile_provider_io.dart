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
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../services/data_broker.dart';
import '../services/tls_ca_bundle.dart';

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

/// User-Agent sent on every OpenStreetMap tile request.
///
/// The OSM Tile Usage Policy requires a stable, identifiable User-Agent that
/// names the application and provides a contact URL; relying on a library
/// default (e.g. "flutter_map (...)") is explicitly not permitted.
const String kOsmTileUserAgent =
    'HTCommander/1.0 (+https://github.com/Ylianst/HTCommander)';

/// See [createMapTileProvider].
class CachedMapTileProvider extends TileProvider {
  CachedMapTileProvider({required this.offline});

  /// When true, no network requests are made; only cached tiles are returned.
  final bool offline;

  // Primary client uses the operating-system trust store (honoring any
  // corporate/antivirus proxy roots). Created lazily so offline providers,
  // which never touch the network, don't allocate one.
  http.Client? _client;

  // Fallback client bound to the bundled Mozilla CA roots, created only after
  // the primary client hits a TLS handshake failure (i.e. an outdated or broken
  // OS trust store). Mirrors the fallback used by CallsignLookupService.
  http.Client? _fallbackClient;

  // Reports tile-loading health to the Debug tab. Shared across provider
  // instances so toggling offline/online or rebuilding the Map tab does not
  // reset the reported state.
  static final _TileLoadLogger _logger = _TileLoadLogger();

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
      // Force our own identifiable User-Agent (OSM policy §3.1/§3.4), replacing
      // any library-default header flutter_map may have injected.
      headers: {...headers, 'User-Agent': kOsmTileUserAgent},
      offline: offline,
      provider: this,
    );
  }

  /// Downloads a single tile, transparently retrying with the bundled Mozilla
  /// CA roots on a TLS handshake failure (an OS trust store that can't verify
  /// the OpenStreetMap certificate chain). Returns the PNG bytes, or null when
  /// the tile could not be fetched. Every outcome is reported to the Debug tab
  /// (deduplicated) so tile-loading problems can be diagnosed from user reports.
  Future<Uint8List?> fetchTile(String url, Map<String, String> headers) async {
    final client = _client ??= http.Client();
    try {
      final bytes = await _download(client, url, headers);
      if (bytes.isEmpty) {
        _logger.onNetworkError('empty tile response');
        return null;
      }
      _logger.onSuccess();
      return bytes;
    } on _TileHttpException catch (e) {
      // A definite HTTP-level rejection (e.g. 403/429): a different CA would
      // not help, so don't attempt the TLS fallback.
      _logger.onHttpError(e.statusCode);
      return null;
    } on HandshakeException catch (e) {
      return _fetchViaFallback(url, headers, e);
    } catch (e) {
      _logger.onNetworkError(e);
      return null;
    }
  }

  /// Retries a tile download using the bundled CA roots after the OS trust
  /// store rejected the certificate chain. Returns null when the fallback is
  /// unavailable or also fails.
  Future<Uint8List?> _fetchViaFallback(
    String url,
    Map<String, String> headers,
    Object cause,
  ) async {
    final context = await bundledCaRootsContext();
    if (context == null) {
      _logger.onTlsFailure(cause, bundledRootsAvailable: false);
      return null;
    }
    try {
      final client = _fallbackClient ??= IOClient(HttpClient(context: context));
      final bytes = await _download(client, url, headers);
      if (bytes.isEmpty) {
        _logger.onNetworkError('empty tile response');
        return null;
      }
      _logger.onFallbackSuccess();
      return bytes;
    } on _TileHttpException catch (e) {
      _logger.onHttpError(e.statusCode);
      return null;
    } catch (e) {
      _logger.onTlsFailure(e, bundledRootsAvailable: true);
      return null;
    }
  }

  static Future<Uint8List> _download(
    http.Client client,
    String url,
    Map<String, String> headers,
  ) async {
    final response = await client.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw _TileHttpException(response.statusCode);
    }
    return response.bodyBytes;
  }

  @override
  void dispose() {
    _client?.close();
    _fallbackClient?.close();
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
    required this.provider,
  });

  final String url;
  final TileCoordinates coordinates;
  final Map<String, String> headers;
  final bool offline;
  final CachedMapTileProvider provider;

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
    // Network/TLS failures (and their logging) are handled by the provider,
    // which falls back to the bundled CA roots when the OS trust store can't
    // verify the certificate chain.
    final bytes = await provider.fetchTile(url, headers);
    if (bytes != null) {
      unawaited(_writeCache(file, bytes));
      return bytes;
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

/// A tile request that returned a non-200 HTTP status.
class _TileHttpException implements Exception {
  const _TileHttpException(this.statusCode);
  final int statusCode;
}

/// Reports map tile-loading health to the Debug tab (device 1 `LogInfo` /
/// `LogError`) so users can diagnose and report tiles not loading.
///
/// Deduplicated on purpose: with many tiles fetched per pan/zoom, only state
/// transitions and distinct error conditions are logged rather than one line
/// per tile. A steady healthy or failing state produces a single entry.
class _TileLoadLogger {
  // null = unknown, true = tiles loading, false = tiles failing.
  bool? _healthy;

  // Signature of the last failure, so a persistent error is logged only once.
  String? _lastErrorSignature;

  // True once tiles are being served via the bundled-CA fallback client.
  bool _fallbackActive = false;

  /// A tile downloaded successfully over the primary (OS trust store) client.
  void onSuccess() {
    if (_healthy == true && !_fallbackActive) return;
    final recovering = _healthy == false;
    _healthy = true;
    _fallbackActive = false;
    _lastErrorSignature = null;
    _log(
      recovering
          ? 'Map: OpenStreetMap tiles are loading again.'
          : 'Map: OpenStreetMap tiles are loading normally.',
      isError: false,
    );
  }

  /// A tile downloaded successfully, but only via the bundled CA roots because
  /// the OS trust store rejected the certificate chain.
  void onFallbackSuccess() {
    _healthy = true;
    _lastErrorSignature = null;
    if (_fallbackActive) return;
    _fallbackActive = true;
    _log(
      'Map: the operating system could not verify the OpenStreetMap '
      'certificate; tiles are now loading using the app\'s bundled CA roots.',
      isError: false,
    );
  }

  void onHttpError(int statusCode) {
    _fail(
      'http:$statusCode',
      'Map: OpenStreetMap returned HTTP $statusCode for a tile request; '
      'tiles cannot be shown.',
    );
  }

  void onNetworkError(Object error) {
    _fail(
      'net:$error',
      'Map: unable to download OpenStreetMap tiles ($error). Check the '
      'internet connection or firewall.',
    );
  }

  void onTlsFailure(Object cause, {required bool bundledRootsAvailable}) {
    _fail(
      'tls:$bundledRootsAvailable',
      bundledRootsAvailable
          ? 'Map: TLS verification of the OpenStreetMap certificate failed '
              'even with the bundled CA roots ($cause); tiles cannot be shown.'
          : 'Map: TLS verification of the OpenStreetMap certificate failed and '
              'no bundled CA roots are available ($cause); tiles cannot be '
              'shown.',
    );
  }

  void _fail(String signature, String message) {
    _healthy = false;
    _fallbackActive = false;
    if (_lastErrorSignature == signature) return;
    _lastErrorSignature = signature;
    _log(message, isError: true);
  }

  void _log(String message, {required bool isError}) {
    DataBroker.dispatch(
      deviceId: 1,
      name: isError ? 'LogError' : 'LogInfo',
      data: message,
      store: false,
    );
  }
}
