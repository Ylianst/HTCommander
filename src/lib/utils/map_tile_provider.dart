/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter_map/flutter_map.dart';

import 'map_tile_provider_stub.dart'
    if (dart.library.io) 'map_tile_provider_io.dart';

/// Returns the [TileProvider] used by the map.
///
/// On native platforms (desktop/mobile) this is a disk-caching provider:
///   * online — tiles are fetched from the network and stored on disk so they
///     can be reused later,
///   * offline ([offline] == true) — the network is never touched; only tiles
///     already saved on disk are shown (missing tiles render transparent over
///     the map background).
///
/// On the web there is no file system, so the standard cancellable network
/// provider is returned and the browser's own HTTP cache provides offline
/// tiles.
TileProvider mapTileProvider({required bool offline}) =>
    createMapTileProvider(offline: offline);
