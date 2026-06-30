/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

/// Web fallback: there is no local file system, so disk caching is not
/// possible. The browser handles HTTP caching itself, so offline mode simply
/// relies on whatever tiles the browser already cached.
TileProvider createMapTileProvider({required bool offline}) =>
    CancellableNetworkTileProvider();
