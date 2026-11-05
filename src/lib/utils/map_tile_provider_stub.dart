/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../services/data_broker.dart';
import 'map_tile_source.dart';

/// Web fallback: there is no local file system, so disk caching is not
/// possible. The browser handles HTTP caching itself, so offline mode simply
/// relies on whatever tiles the browser already cached.
TileProvider createMapTileProvider({
  required bool offline,
  MapTileSource source = const MapTileSource.openStreetMap(),
}) => source.isCustom ? _CustomWebTileProvider(source) : NetworkTileProvider();

// Browser HTTP caching remains in charge. Avoid network image diagnostics that
// include the full custom URL, which may contain an API key.
class _CustomWebTileProvider extends TileProvider {
  _CustomWebTileProvider(this.source);

  final MapTileSource source;
  final _client = http.Client();
  String? _lastStatus;
  bool _disposed = false;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => _CustomWebTileImage(this, coordinates, cancelLoading);

  Future<Uint8List> fetch(TileCoordinates tile, Future<void> cancel) async {
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse(source.tileUrl(tile.z, tile.x, tile.y)),
        abortTrigger: cancel,
      );
      final response = await _client.send(request);
      final bytes = await response.stream.toBytes();
      if (response.statusCode != 200 || bytes.isEmpty) {
        _report('HTTP ${response.statusCode} or empty response', isError: true);
        return TileProvider.transparentImage;
      }
      _report('tiles are loading normally', isError: false);
      return bytes;
    } on http.RequestAbortedException {
      return TileProvider.transparentImage;
    } on http.ClientException {
      _report(
        'tile request failed; check connectivity and CORS',
        isError: true,
      );
      return TileProvider.transparentImage;
    }
  }

  void _report(String status, {required bool isError}) {
    if (_disposed || status == _lastStatus) return;
    _lastStatus = status;
    DataBroker.dispatch(
      deviceId: 1,
      name: isError ? 'LogError' : 'LogInfo',
      data: 'Map: ${source.label}: $status.',
      store: false,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}

@immutable
class _CustomWebTileImage extends ImageProvider<_CustomWebTileImage> {
  const _CustomWebTileImage(this.provider, this.tile, this.cancel);

  final _CustomWebTileProvider provider;
  final TileCoordinates tile;
  final Future<void> cancel;

  @override
  SynchronousFuture<_CustomWebTileImage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CustomWebTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: '${provider.source.label} tile ${tile.z}/${tile.x}/${tile.y}',
  );

  Future<Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await provider.fetch(tile, cancel);
    return decode(await ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _CustomWebTileImage &&
      identical(other.provider, provider) &&
      other.tile == tile;

  @override
  int get hashCode => Object.hash(provider, tile);
}
