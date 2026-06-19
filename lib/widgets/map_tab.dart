import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Map tab - geographic map display with OpenStreetMap
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  bool _isOfflineMode = false;
  // Will be updated when GPS functionality is added
  // ignore: prefer_final_fields
  bool _centerToGpsEnabled = false;

  // Default map position (center of US)
  static const double _defaultLat = 39.8283;
  static const double _defaultLng = -98.5795;
  static const double _defaultZoom = 4.0;

  @override
  bool get wantKeepAlive => true;

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 18) {
      _mapController.move(_mapController.camera.center, currentZoom + 1);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > 3) {
      _mapController.move(_mapController.camera.center, currentZoom - 1);
    }
  }

  void _centerToGps() {
    // TODO: Implement GPS centering when radio position is available
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    // Compact menu item style
    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'offline',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _isOfflineMode
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Offline Mode'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'cache',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Cache Area...')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'centerGps',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _centerToGpsEnabled,
          child: const Row(
            children: [SizedBox(width: 20), Text('Center to GPS')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'tracks',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('✓', style: TextStyle(fontSize: 14)),
              ),
              Text('Show Tracks'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'markers',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Show Markers')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'airplanes',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Show Airplanes')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'largeMarkers',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('✓', style: TextStyle(fontSize: 14)),
              ),
              Text('Large Markers'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'offline':
          setState(() {
            _isOfflineMode = !_isOfflineMode;
          });
          break;
        case 'centerGps':
          _centerToGps();
          break;
        // TODO: Handle other menu items
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: [
        // Header bar matching C# UI
        _buildHeader(),
        // Map fills remaining space
        Expanded(
          child: Stack(
            children: [
              // OpenStreetMap
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: LatLng(_defaultLat, _defaultLng),
                  initialZoom: _defaultZoom,
                  minZoom: 3,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.htcommander.app',
                  ),
                ],
              ),
              // Zoom buttons overlay (top-left, below header)
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
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      color: const Color(0xFFC0C0C0), // Silver color like C# app
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Map label
          Text(
            _isOfflineMode ? 'Offline Map' : 'Map',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          // Center to GPS button
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _centerToGpsEnabled ? _centerToGps : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Center to GPS'),
            ),
          ),
          const SizedBox(width: 8),
          // Menu icon
          Builder(
            builder: (context) => InkWell(
              onTap: () => _showMenu(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/images/MenuIcon.png',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.menu, size: 24);
                  },
                ),
              ),
            ),
          ),
        ],
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
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
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
