/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'map_tile_provider_io.dart';

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
}) async {
  final dir = await CachedMapTileProvider.cacheDir();
  final client = http.Client();
  var downloaded = 0;
  var total = countTilesInBounds(sw, ne, minZoom, maxZoom);

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
          if (await file.exists()) {
            // Already cached, skip.
            downloaded++;
            onProgress(downloaded, total);
            continue;
          }

          final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
          try {
            final response = await client.get(
              Uri.parse(url),
              headers: {
                'User-Agent': 'HTCommander/1.0 (com.htcommander.app)',
              },
            );
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              await file.writeAsBytes(response.bodyBytes);
            }
          } catch (_) {
            // Skip failed tiles; user can retry later.
          }

          downloaded++;
          onProgress(downloaded, total);

          // Small delay to be nice to the tile server.
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  } finally {
    client.close();
  }
  return downloaded;
}

/// Converts a lat/lng to tile coordinates at the given zoom level.
(int x, int y) _latLngToTile(double lat, double lng, int zoom) {
  final n = 1 << zoom;
  final x = ((lng + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
  final latRad = lat * math.pi / 180.0;
  final y = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n)
      .floor()
      .clamp(0, n - 1);
  return (x, y);
}
