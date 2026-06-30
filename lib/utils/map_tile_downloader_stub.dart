/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Web stub: tile downloading is not supported on the web platform.
int countTilesInBounds(LatLng sw, LatLng ne, int minZoom, int maxZoom) => 0;

/// Web stub: tile downloading is not supported on the web platform.
Future<int> downloadTilesInBounds({
  required LatLng sw,
  required LatLng ne,
  required int minZoom,
  required int maxZoom,
  required void Function(int downloaded, int total) onProgress,
  required ValueNotifier<bool> cancel,
}) async => 0;
