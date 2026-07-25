/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../utils/map_tile_provider.dart';

/// Shows a dialog with a map permanently centered on [latitude]/[longitude]
/// with a red marker at that location. Mirrors the C# APRS "Show Location..."
/// feature.
Future<void> showAprsLocationDialog(
  BuildContext context, {
  required double latitude,
  required double longitude,
  String? title,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AprsLocationDialog(
      latitude: latitude,
      longitude: longitude,
      title: title,
    ),
  );
}

/// A dialog that displays a map always centered on a fixed location with a red
/// marker at the center. Provides the same zoom in/out buttons as the map tab
/// and disables map rotation.
class AprsLocationDialog extends StatefulWidget {
  const AprsLocationDialog({
    super.key,
    required this.latitude,
    required this.longitude,
    this.title,
  });

  final double latitude;
  final double longitude;
  final String? title;

  @override
  State<AprsLocationDialog> createState() => _AprsLocationDialogState();
}

class _AprsLocationDialogState extends State<AprsLocationDialog> {
  final MapController _mapController = MapController();
  final DataBrokerClient _broker = DataBrokerClient();
  late final TileProvider _tileProvider = mapTileProvider(offline: false);

  static const double _defaultZoom = 14.0;

  /// Zoom level restored from persistent storage (device 0), so the dialog
  /// reopens at the same zoom the user last left it.
  late final double _initialZoom =
      (DataBroker.getValue<int>(0, 'AprsLocationZoom', _defaultZoom.toInt()) ??
              _defaultZoom.toInt())
          .toDouble()
          .clamp(3, 18)
          .toDouble();

  LatLng get _center => LatLng(widget.latitude, widget.longitude);

  @override
  void dispose() {
    _tileProvider.dispose();
    super.dispose();
  }

  /// Persists the current zoom level so the dialog reopens at the same zoom.
  void _saveZoom(double zoom) {
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsLocationZoom',
      data: zoom.round(),
    );
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 18) {
      final newZoom = currentZoom + 1;
      _mapController.move(_center, newZoom);
      _saveZoom(newZoom);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > 3) {
      final newZoom = currentZoom - 1;
      _mapController.move(_center, newZoom);
      _saveZoom(newZoom);
    }
  }

  /// Keeps the map permanently centered on the message location: if the user
  /// pans, snap the center back to the fixed location. Also persists the zoom
  /// level so the dialog reopens where the user left it.
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _saveZoom(camera.zoom);
    final center = camera.center;
    if (center.latitude != widget.latitude ||
        center.longitude != widget.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_center, camera.zoom);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header bar
            Container(
              height: 40,
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title ?? AppLocalizations.of(context).locationTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    splashRadius: 16,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Map
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: _initialZoom,
                      minZoom: 3,
                      maxZoom: 18,
                      backgroundColor: scheme.secondaryContainer,
                      // Keep the map permanently north-up: allow all gestures
                      // except rotation.
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onPositionChanged: _onMapPositionChanged,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'HTCommander/1.0 (amateur-radio-app; github.com/Ylianst/HTCommander)',
                        tileProvider: _tileProvider,
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _center,
                            width: 30,
                            height: 30,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Zoom buttons overlay (top-left)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Column(
                      children: [
                        _buildZoomButton('+', _zoomIn),
                        const SizedBox(height: 4),
                        _buildZoomButton('−', _zoomOut),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButton(String label, VoidCallback onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
