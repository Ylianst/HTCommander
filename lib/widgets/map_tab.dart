import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Map tab - geographic map display with OpenStreetMap
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final DataBrokerClient _broker = DataBrokerClient();

  // Map settings (loaded from DataBroker)
  bool _isOfflineMode = false;
  bool _showTracks = true;
  bool _showMarkers = true;
  bool _showAirplanes = false;
  bool _largeMarkers = true;
  // ignore: unused_field
  int _markerTimeFilter = 0; // 0 = all, otherwise minutes (for future use)

  // Will be updated when GPS functionality is added
  // ignore: prefer_final_fields
  bool _centerToGpsEnabled = false;

  // Default map position (center of US)
  static const double _defaultLat = 39.8283;
  static const double _defaultLng = -98.5795;
  static const double _defaultZoom = 4.0;

  // Loaded map position
  late double _initialLat;
  late double _initialLng;
  late double _initialZoom;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  /// Load map settings from DataBroker (device 0 = persistent).
  void _loadSettings() {
    // Load position and zoom
    final latStr =
        DataBroker.getValue<String>(0, 'MapLatitude', _defaultLat.toString()) ??
        _defaultLat.toString();
    final lngStr =
        DataBroker.getValue<String>(
          0,
          'MapLongitude',
          _defaultLng.toString(),
        ) ??
        _defaultLng.toString();
    _initialLat = double.tryParse(latStr) ?? _defaultLat;
    _initialLng = double.tryParse(lngStr) ?? _defaultLng;
    _initialZoom =
        (DataBroker.getValue<int>(0, 'MapZoom', _defaultZoom.toInt()) ??
                _defaultZoom.toInt())
            .toDouble();

    // Load settings
    _isOfflineMode =
        (DataBroker.getValue<int>(0, 'MapOfflineMode', 0) ?? 0) == 1;
    _showTracks = (DataBroker.getValue<int>(0, 'MapShowTracks', 1) ?? 1) == 1;
    _largeMarkers =
        (DataBroker.getValue<int>(0, 'MapLargeMarkers', 1) ?? 1) == 1;
    _markerTimeFilter = DataBroker.getValue<int>(0, 'MapTimeFilter', 0) ?? 0;
    _showAirplanes =
        (DataBroker.getValue<int>(0, 'ShowAirplanesOnMap', 0) ?? 0) == 1;
  }

  /// Called when the map position changes.
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    // Save position to DataBroker (device 0 persists to storage)
    _broker.dispatch(
      deviceId: 0,
      name: 'MapLatitude',
      data: camera.center.latitude.toString(),
    );
    _broker.dispatch(
      deviceId: 0,
      name: 'MapLongitude',
      data: camera.center.longitude.toString(),
    );
    _broker.dispatch(deviceId: 0, name: 'MapZoom', data: camera.zoom.toInt());
  }

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

    // Check if airplane server is configured
    final airplaneServer =
        DataBroker.getValue<String>(0, 'AirplaneServer', '') ?? '';
    final showAirplanesOption = airplaneServer.isNotEmpty;

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
          enabled: !_isOfflineMode,
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
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showTracks
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Tracks'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'markers',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showMarkers
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Markers'),
            ],
          ),
        ),
        if (showAirplanesOption)
          PopupMenuItem<String>(
            value: 'airplanes',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _showAirplanes
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Show Airplanes'),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'largeMarkers',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _largeMarkers
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Large Markers'),
            ],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Detach...')],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'offline':
          setState(() {
            _isOfflineMode = !_isOfflineMode;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'MapOfflineMode',
            data: _isOfflineMode ? 1 : 0,
          );
          break;
        case 'tracks':
          setState(() {
            _showTracks = !_showTracks;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'MapShowTracks',
            data: _showTracks ? 1 : 0,
          );
          break;
        case 'markers':
          setState(() {
            _showMarkers = !_showMarkers;
          });
          // Note: showMarkers doesn't have a DataBroker key in C# reference,
          // but we can add one for consistency
          break;
        case 'airplanes':
          setState(() {
            _showAirplanes = !_showAirplanes;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'ShowAirplanesOnMap',
            data: _showAirplanes ? 1 : 0,
          );
          break;
        case 'largeMarkers':
          setState(() {
            _largeMarkers = !_largeMarkers;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'MapLargeMarkers',
            data: _largeMarkers ? 1 : 0,
          );
          break;
        case 'centerGps':
          _centerToGps();
          break;
        case 'detach':
          windowService.createWindow('map');
          break;
        case 'cache':
          // TODO: Implement cache area functionality
          break;
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
                options: MapOptions(
                  initialCenter: LatLng(_initialLat, _initialLng),
                  initialZoom: _initialZoom,
                  minZoom: 3,
                  maxZoom: 18,
                  onPositionChanged: _onMapPositionChanged,
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
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 220;
          return Row(
            children: [
              // Map label
              Text(
                _isOfflineMode ? 'Offline Map' : 'Map',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Center to GPS button
              if (showButton) ...[
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
              ],
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
          );
        },
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
