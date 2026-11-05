/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'map_tile_provider_io.dart';
import 'map_tile_source.dart';
import '../services/data_broker.dart';

/// Calculates the number of tiles needed to cover a bounding box at the given
/// zoom levels (from [minZoom] to [maxZoom] inclusive).
int countTilesInBounds(LatLng sw, LatLng ne, int minZoom, int maxZoom) {
  var total = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final (x1, y1) = _latLngToTile(sw.latitude, sw.longitude, z);
    final (x2, y2) = _latLngToTile(ne.latitude, ne.longitude, z);
    final xMin = math.min(x1, x2);
    final xMax = math.max(x1, x2);
    final yMin = math.min(y1, y2);
    final yMax = math.max(y1, y2);
    total += (xMax - xMin + 1) * (yMax - yMin + 1);
  }
  return total;
}

/// Downloads all tiles in the bounding box defined by [sw] (south-west) and
/// [ne] (north-east) for zoom levels [minZoom] to [maxZoom] inclusive.
///
/// Calls [onProgress] with (downloaded, total) after each tile.
/// Returns the number of tiles successfully downloaded (skips already-cached).
/// If [cancel] becomes true the download stops early.
Future<int> downloadTilesInBounds({
  required LatLng sw,
  required LatLng ne,
  required int minZoom,
  required int maxZoom,
  required void Function(int downloaded, int total) onProgress,
  required ValueNotifier<bool> cancel,
  MapTileSource source = const MapTileSource.openStreetMap(),
}) async {
  final dir = await CachedMapTileProvider.cacheDir(source: source);
  final provider = CachedMapTileProvider(offline: false, source: source);
  var downloaded = 0;
  var processed = 0;
  final total = countTilesInBounds(sw, ne, minZoom, maxZoom);

  try {
    for (var z = minZoom; z <= maxZoom; z++) {
      final (x1, y1) = _latLngToTile(sw.latitude, sw.longitude, z);
      final (x2, y2) = _latLngToTile(ne.latitude, ne.longitude, z);
      final xMin = math.min(x1, x2);
      final xMax = math.max(x1, x2);
      final yMin = math.min(y1, y2);
      final yMax = math.max(y1, y2);

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          if (cancel.value) return downloaded;

          final file = File('${dir.path}/${z}_${x}_$y.png');
          if (await file.exists() && await file.length() > 0) {
            // Already cached, skip.
            downloaded++;
            onProgress(++processed, total);
            continue;
          }

          final bytes = await provider.fetchTile(source.tileUrl(z, x, y), {
            'User-Agent': kOsmTileUserAgent,
          });
          if (cancel.value) return downloaded;
          if (bytes == null) {
            throw const FileSystemException('Unable to download map tile.');
          }
          try {
            await file.writeAsBytes(bytes);
          } on FileSystemException {
            DataBroker.dispatch(
              deviceId: 1,
              name: 'LogError',
              data: 'Map: unable to save downloaded tiles to the local cache.',
              store: false,
            );
            rethrow;
          }

          downloaded++;
          onProgress(++processed, total);

          // Small delay to be nice to the tile server.
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  } finally {
    provider.dispose();
  }
  return downloaded;
}

/// Converts a lat/lng to tile coordinates at the given zoom level.
(int x, int y) _latLngToTile(double lat, double lng, int zoom) {
  final n = 1 << zoom;
  final x = ((lng + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
  final latRad = lat * math.pi / 180.0;
  final y =
      ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
              2.0 *
              n)
          .floor()
          .clamp(0, n - 1);
  return (x, y);
}
