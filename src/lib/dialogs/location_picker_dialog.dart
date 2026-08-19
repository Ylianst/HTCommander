/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../utils/map_tile_provider.dart';

/// Opens a dialog letting the user pick a location on the map. Returns the
/// chosen [LatLng] when the user confirms, or null when cancelled.
Future<LatLng?> showLocationPickerDialog(
  BuildContext context, {
  required double latitude,
  required double longitude,
}) {
  return showDialog<LatLng>(
    context: context,
    builder: (context) => LocationPickerDialog(
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

/// A map dialog with a fixed centre pin. The user pans/zooms the map so the pin
/// sits on the desired spot; pressing OK returns the map centre.
class LocationPickerDialog extends StatefulWidget {
  const LocationPickerDialog({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  final MapController _mapController = MapController();
  final DataBrokerClient _broker = DataBrokerClient();
  late final TileProvider _tileProvider = mapTileProvider(offline: false);

  static const String _zoomStorageKey = 'ManualLocationZoom';

  late final double _initialZoom =
      (DataBroker.getValue<int>(0, _zoomStorageKey, 12) ?? 12)
          .toDouble()
          .clamp(3, 18)
          .toDouble();

  // A stored (0, 0) usually means "no location yet"; start on a neutral world
  // view rather than the Gulf of Guinea.
  late LatLng _center = (widget.latitude == 0 && widget.longitude == 0)
      ? const LatLng(20, 0)
      : LatLng(widget.latitude, widget.longitude);

  late final double _initialZoomEffective =
      (widget.latitude == 0 && widget.longitude == 0) ? 2 : _initialZoom;

  @override
  void dispose() {
    _tileProvider.dispose();
    super.dispose();
  }

  void _saveZoom(double zoom) {
    _broker.dispatch(deviceId: 0, name: _zoomStorageKey, data: zoom.round());
  }

  void _zoomIn() {
    final z = _mapController.camera.zoom;
    if (z < 18) {
      _mapController.move(_mapController.camera.center, z + 1);
      _saveZoom(z + 1);
    }
  }

  void _zoomOut() {
    final z = _mapController.camera.zoom;
    if (z > 3) {
      _mapController.move(_mapController.camera.center, z - 1);
      _saveZoom(z - 1);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _center = camera.center;
    _saveZoom(camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
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
                      l10n.locationPickerTitle,
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
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: _initialZoomEffective,
                      minZoom: 3,
                      maxZoom: 18,
                      backgroundColor: scheme.secondaryContainer,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onPositionChanged: _onMapPositionChanged,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'HTCommander/1.0 (amateur-radio-app; github.com/Ylianst/HTCommander)',
                        tileProvider: _tileProvider,
                      ),
                      // Required OpenStreetMap licence attribution.
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://www.openstreetmap.org/copyright',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Text(
                                '© OpenStreetMap contributors',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black87,
                                  shadows: [
                                    Shadow(blurRadius: 2, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Fixed centre pin: the map moves under it, so it always marks
                  // the map centre that OK will return. Offset up by half its
                  // height so the tip points at the exact centre.
                  const IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 30),
                      child: Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
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
            // Footer with hint + actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.locationPickerHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_mapController.camera.center),
                    child: Text(l10n.commonOk),
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
    return SizedBox(
      width: 32,
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
