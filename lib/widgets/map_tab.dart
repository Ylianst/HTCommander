/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../gps/gps_data.dart';
import '../models/aircraft.dart';
import '../models/radio_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Holds the latest known position, time and track points for a single
/// station rendered on the map (APRS red/blue markers or voice/BSS orange
/// markers). Mirrors the per-callsign marker + GMapRoute bookkeeping the C#
/// `MapTabUserControl` performed with `mapRoutes` and the markers overlay.
class _StationMarkerData {
  _StationMarkerData({
    required this.callsign,
    required this.position,
    required this.time,
    required this.isSelf,
  }) : track = <LatLng>[position];

  final String callsign;
  LatLng position;
  DateTime time;
  final bool isSelf;
  final List<LatLng> track;

  /// Appends a new point to the track when the position actually changed,
  /// matching the C# `AddMapMarker` route behaviour.
  void update(LatLng newPosition, DateTime newTime) {
    final last = track.isNotEmpty ? track.last : null;
    if (last == null ||
        last.latitude != newPosition.latitude ||
        last.longitude != newPosition.longitude) {
      track.add(newPosition);
    }
    position = newPosition;
    time = newTime;
  }
}

/// Map tab - geographic map display with OpenStreetMap
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final DataBrokerClient _broker = DataBrokerClient();

  // APRS device id used for broker messages (matches the C# reference).
  static const int _aprsDeviceId = 1;

  // Map settings (loaded from DataBroker)
  bool _isOfflineMode = false;
  bool _showTracks = true;
  bool _showAirplanes = false;
  bool _largeMarkers = true;

  /// Current aircraft to display, received from the "Airplanes" broker event.
  List<Aircraft> _airplanes = [];

  /// Time filter in minutes (0 = show all). Markers/tracks older than this are
  /// hidden, mirroring the C# `MapTimeFilter` behaviour.
  int _markerTimeFilter = 0;

  /// APRS station markers keyed by callsign (red, or blue for "Self").
  final Map<String, _StationMarkerData> _aprsStations = {};

  /// Voice / BSS source-station markers keyed by source callsign (orange).
  final Map<String, _StationMarkerData> _voiceStations = {};

  /// Guards against loading the historical APRS packet list more than once,
  /// mirroring the C# `_historicalPacketsLoaded` flag.
  bool _historicalPacketsLoaded = false;

  /// Latest fixed position from an external serial GPS receiver (device 1,
  /// `GpsData`). Null when there is no GPS or no valid fix. Mirrors the C#
  /// `MapTabUserControl` serial GPS marker (reserved key 0).
  GpsData? _serialGps;

  /// Latest GPS-locked positions reported by connected radios, keyed by device
  /// ID. Only contains radios that currently have a valid GPS lock. Mirrors the
  /// C# `MapTabUserControl.radioMarkers` (blue markers per device).
  final Map<int, RadioPosition> _radioPositions = {};

  /// "Center to GPS" is available whenever we have a serial GPS fix.
  bool get _centerToGpsEnabled => _serialGps != null;

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

    // Receive aircraft updates from the AirplaneHandler.
    _broker.subscribe(
      deviceId: 0,
      name: 'Airplanes',
      callback: _onAirplanesChanged,
    );

    // Keep airplane visibility in sync with the setting.
    _broker.subscribe(
      deviceId: 0,
      name: 'ShowAirplanesOnMap',
      callback: _onShowAirplanesChanged,
    );

    // --- APRS markers (mirrors the C# APRS Marker Code region) ---
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsFrame',
      callback: _onAprsFrame,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsStoreReady',
      callback: _onAprsStoreReady,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsPacketList',
      callback: _onAprsPacketList,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsPacketsCleared',
      callback: _onAprsPacketsCleared,
    );

    // Request the current packet list from the AprsHandler on-demand.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );

    // --- Voice / BSS source markers (orange) ---
    // Historical decoded-text entries (with location) and real-time updates.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'DecodedTextHistory',
      callback: _onDecodedTextHistory,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TextReady',
      callback: _onTextReady,
    );

    // --- External serial GPS marker (mirrors the C# MapTabUserControl) ---
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'GpsData',
      callback: _onSerialGpsDataChanged,
    );
    // Load the initial serial GPS position if it is already communicating.
    final initialGps = _broker.getValue<GpsData>(
      _aprsDeviceId,
      'GpsData',
      null,
    );
    if (initialGps != null && initialGps.isFixed) {
      _serialGps = initialGps;
    }

    // --- Radio GPS position markers (mirrors the C# MapTabUserControl) ---
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Position',
      callback: _onRadioPositionChanged,
    );
    // Load initial positions for any already connected radios that have a lock.
    _loadInitialRadioPositions();
  }

  /// Loads the current GPS-locked position for every connected radio so the
  /// markers are present when switching to the Map tab. Mirrors the C#
  /// `LoadInitialRadioPositions`.
  void _loadInitialRadioPositions() {
    final radios = _broker.getValueDynamic(_aprsDeviceId, 'ConnectedRadios');
    if (radios is! List) return;
    for (final radio in radios) {
      if (radio is! Map) continue;
      final deviceId = radio['DeviceId'] as int? ?? radio['deviceId'] as int?;
      if (deviceId == null || deviceId <= 0) continue;
      final posData = _broker.getValueDynamic(deviceId, 'Position');
      if (posData is Map) {
        final pos = RadioPosition.fromJson(Map<String, dynamic>.from(posData));
        if (pos.locked) {
          _radioPositions[deviceId] = pos;
        }
      }
    }
  }

  /// Handles radio `Position` updates. Keeps a marker for every radio that has
  /// a valid GPS lock and removes it otherwise, matching the C#
  /// `OnPositionChanged`.
  void _onRadioPositionChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (deviceId <= 0) {
      return; // Ignore device 0 (app settings) and invalid ids.
    }
    RadioPosition? pos;
    if (data is RadioPosition) {
      pos = data;
    } else if (data is Map) {
      pos = RadioPosition.fromJson(Map<String, dynamic>.from(data));
    }
    setState(() {
      if (pos != null && pos.locked) {
        _radioPositions[deviceId] = pos;
      } else {
        _radioPositions.remove(deviceId);
      }
    });
  }

  /// Handles serial GPS updates. Shows the marker when there is a valid fix and
  /// removes it otherwise, matching the C# `OnSerialGpsDataChanged`.
  void _onSerialGpsDataChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    GpsData? gps;
    if (data is GpsData) {
      gps = data;
    } else if (data is Map) {
      gps = GpsData.fromJson(Map<String, dynamic>.from(data));
    }
    setState(() {
      _serialGps = (gps != null && gps.isFixed) ? gps : null;
    });
  }

  void _onAirplanesChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final List<Aircraft> airplanes;
    if (data is List<Aircraft>) {
      airplanes = data;
    } else if (data is List) {
      airplanes = data.whereType<Aircraft>().toList();
    } else {
      airplanes = const [];
    }
    setState(() => _airplanes = airplanes);
  }

  void _onShowAirplanesChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _showAirplanes = (data as int?) == 1;
      if (!_showAirplanes) _airplanes = const [];
    });
  }

  // ---------------------------------------------------------------------------
  // APRS marker handlers
  // ---------------------------------------------------------------------------

  /// The APRS store is ready - request the packet list (once).
  void _onAprsStoreReady(int deviceId, String name, Object? data) {
    if (_historicalPacketsLoaded) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );
  }

  /// Loads APRS packets from the on-demand request (history), once.
  void _onAprsPacketList(int deviceId, String name, Object? data) {
    if (_historicalPacketsLoaded) return;
    if (data is! List) return;
    _historicalPacketsLoaded = true;

    var changed = false;
    for (final item in data) {
      if (item is AprsPacket) {
        changed = _processAprsPacket(item) || changed;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// Handles a single incoming APRS frame from the broker.
  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (data is! AprsFrameEventArgs) return;
    if (_processAprsPacket(data.aprsPacket) && mounted) {
      setState(() {});
    }
  }

  /// Handles the `AprsPacketsCleared` event - removes all APRS station markers
  /// and tracks from the map and redraws.
  void _onAprsPacketsCleared(int deviceId, String name, Object? data) {
    if (_aprsStations.isEmpty) {
      _historicalPacketsLoaded = false;
      return;
    }
    _aprsStations.clear();
    _historicalPacketsLoaded = false;
    if (mounted) setState(() {});
  }

  /// Extracts the callsign/position/time from an [AprsPacket] and updates the
  /// per-callsign marker + track. Returns true when the marker set changed.
  /// Mirrors the C# `ProcessAprsPacketForMap` + `AddMapMarker`.
  bool _processAprsPacket(AprsPacket aprsPacket) {
    final packet = aprsPacket.packet;
    if (packet == null) return false;
    if (!aprsPacket.position.isValid()) return false;

    final lat = aprsPacket.position.coordinateSet.latitude.value;
    final lng = aprsPacket.position.coordinateSet.longitude.value;
    if (lat == 0 && lng == 0) return false;

    // The sender callsign is the second AX.25 address (index 1).
    if (packet.addresses.length < 2) return false;
    final callsign = packet.addresses[1].callSignWithId;
    if (callsign.isEmpty) return false;

    final time = aprsPacket.timeStamp ?? packet.time;
    final point = LatLng(lat, lng);

    final existing = _aprsStations[callsign];
    if (existing != null) {
      existing.update(point, time);
    } else {
      _aprsStations[callsign] = _StationMarkerData(
        callsign: callsign,
        position: point,
        time: time,
        isSelf: callsign == 'Self',
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Voice / BSS source marker handlers (orange)
  // ---------------------------------------------------------------------------

  /// Handles the DecodedTextHistory event - loads historical voice/BSS entries
  /// that carry a location. Mirrors the C# `OnDecodedTextHistory`.
  void _onDecodedTextHistory(int deviceId, String name, Object? data) {
    if (data is! List) return;
    var changed = false;
    for (final entry in data) {
      if (entry is Map) {
        changed = _processVoiceEntry(entry) || changed;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// Handles the TextReady event - processes real-time voice/BSS entries that
  /// carry a location. Mirrors the C# `OnTextReady`.
  void _onTextReady(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    // Only process completed entries (matches the C# guard).
    final completed = data['completed'];
    if (completed is bool && !completed) return;
    if (_processVoiceEntry(data) && mounted) {
      setState(() {});
    }
  }

  /// Adds or updates an orange marker for a voice/BSS source station from a
  /// decoded-text entry map. Returns true when the marker set changed.
  bool _processVoiceEntry(Map<dynamic, dynamic> entry) {
    final source = entry['source'];
    if (source is! String || source.isEmpty) return false;

    final lat = _toDouble(entry['latitude']);
    final lng = _toDouble(entry['longitude']);
    if (lat == 0 && lng == 0) return false;

    final time = _toDateTime(entry['time']);
    final point = LatLng(lat, lng);

    final existing = _voiceStations[source];
    if (existing != null) {
      existing.update(point, time);
    } else {
      _voiceStations[source] = _StationMarkerData(
        callsign: source,
        position: point,
        time: time,
        isSelf: false,
      );
    }
    return true;
  }

  static double _toDouble(Object? v) => v is num ? v.toDouble() : 0.0;

  static DateTime _toDateTime(Object? v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  /// True when [time] is within the active time filter window (or no filter).
  bool _passesTimeFilter(DateTime time) {
    if (_markerTimeFilter == 0) return true;
    final cutoff = time.add(Duration(minutes: _markerTimeFilter));
    return DateTime.now().compareTo(cutoff) <= 0;
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
    final gps = _serialGps;
    if (gps == null) return;
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(
      LatLng(gps.latitude, gps.longitude),
      currentZoom < 12 ? 14 : currentZoom,
    );
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

    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + button.size.height,
      offset.dx + button.size.width,
      offset.dy,
    );

    showMenu<String>(
      context: context,
      position: position,
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
              const SizedBox(width: 20),
              const Text('Show Markers'),
              const Spacer(),
              Text(
                _markerFilterLabel(_markerTimeFilter),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const Icon(Icons.arrow_right, size: 18),
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
          // Open the cascading time-filter submenu, anchored at the same
          // position as the main menu (mirrors the C# "Show Markers" submenu).
          if (context.mounted) _showMarkerFilterMenu(context, position);
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

  /// Time-filter options shown under "Show Markers", mirroring the C#
  /// `MapTabUserControl` submenu (label, minutes; 0 = show all).
  static const List<(String, int)> _markerFilterOptions = [
    ('All', 0),
    ('Last 30 Minutes', 30),
    ('Last Hour', 60),
    ('Last 6 Hours', 360),
    ('Last 12 Hours', 720),
    ('Last 24 Hours', 1440),
  ];

  /// Human-readable label for the active marker time filter (in minutes).
  String _markerFilterLabel(int minutes) {
    for (final (label, value) in _markerFilterOptions) {
      if (value == minutes) return label;
    }
    return 'All';
  }

  /// Opens the cascading "Show Markers" time-filter submenu. Selecting an
  /// option updates `MapTimeFilter` so only recent markers/tracks are shown.
  void _showMarkerFilterMenu(BuildContext context, RelativeRect position) {
    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<int>(
      context: context,
      position: position,
      items: [
        for (final (label, minutes) in _markerFilterOptions)
          PopupMenuItem<int>(
            value: minutes,
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _markerTimeFilter == minutes
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                Text(label),
              ],
            ),
          ),
      ],
    ).then((minutes) {
      if (minutes == null || minutes == _markerTimeFilter) return;
      setState(() {
        _markerTimeFilter = minutes;
      });
      _broker.dispatch(deviceId: 0, name: 'MapTimeFilter', data: minutes);
    });
  }

  /// Builds the airplane markers for aircraft that have a known position.
  List<Marker> _buildAirplaneMarkers() {
    final markers = <Marker>[];
    for (final aircraft in _airplanes) {
      if (!aircraft.hasPosition) continue;
      markers.add(
        Marker(
          point: LatLng(aircraft.latitude!, aircraft.longitude!),
          width: 40,
          height: 40,
          child: _buildAirplaneMarker(aircraft),
        ),
      );
    }
    return markers;
  }

  Widget _buildAirplaneMarker(Aircraft aircraft) {
    final label = (aircraft.flight != null && aircraft.flight!.isNotEmpty)
        ? aircraft.flight!
        : (aircraft.hex ?? 'Unknown');
    // The Material "flight" glyph points straight up (north), so rotate it
    // directly by the reported track (0° = north, increasing clockwise).
    final angle = (aircraft.track ?? 0) * math.pi / 180;
    return Tooltip(
      message:
          'Flight: $label\n'
          'Altitude: ${aircraft.getAltitudeDisplay()} ft',
      child: Transform.rotate(
        angle: angle,
        child: const Icon(Icons.flight, color: Color(0xFF1565C0), size: 26),
      ),
    );
  }

  /// Builds the station markers (APRS red/blue + voice/BSS orange) that pass
  /// the active time filter.
  List<Marker> _buildStationMarkers() {
    final markers = <Marker>[];
    final double size = _largeMarkers ? 30 : 20;

    void addStation(_StationMarkerData s, Color color) {
      if (!_passesTimeFilter(s.time)) return;
      markers.add(
        Marker(
          point: s.position,
          width: size,
          height: size,
          alignment: Alignment.topCenter,
          child: Tooltip(
            message: '${s.callsign}\n${s.time.toLocal()}',
            child: Icon(Icons.location_pin, color: color, size: size),
          ),
        ),
      );
    }

    // APRS markers: blue for "Self", red otherwise.
    for (final station in _aprsStations.values) {
      addStation(station, station.isSelf ? Colors.blue : Colors.red);
    }

    // Voice / BSS source markers: orange.
    for (final station in _voiceStations.values) {
      addStation(station, Colors.orange);
    }

    // External serial GPS marker (blue), shown whenever there is a valid fix.
    final gps = _serialGps;
    if (gps != null) {
      markers.add(
        Marker(
          point: LatLng(gps.latitude, gps.longitude),
          width: size,
          height: size,
          child: Tooltip(
            message:
                'Serial GPS\n'
                '${gps.latitude.toStringAsFixed(5)}\u00B0, '
                '${gps.longitude.toStringAsFixed(5)}\u00B0',
            child: Icon(Icons.my_location, color: Colors.blue, size: size),
          ),
        ),
      );
    }

    // Connected radio GPS markers (blue), one per radio with a valid GPS lock.
    _radioPositions.forEach((deviceId, pos) {
      final friendlyName =
          _broker.getValue<String>(deviceId, 'FriendlyName') ??
          'Radio $deviceId';
      markers.add(
        Marker(
          point: LatLng(pos.latitude, pos.longitude),
          width: size,
          height: size,
          alignment: Alignment.topCenter,
          child: Tooltip(
            message:
                '$friendlyName\n'
                '${pos.latitude.toStringAsFixed(5)}\u00B0, '
                '${pos.longitude.toStringAsFixed(5)}\u00B0',
            child: Icon(Icons.location_pin, color: Colors.blue, size: size),
          ),
        ),
      );
    });

    return markers;
  }

  /// Builds the track polylines for stations when "Show Tracks" is enabled.
  List<Polyline> _buildTracks() {
    final polylines = <Polyline>[];

    void addTrack(_StationMarkerData s, Color color) {
      if (s.track.length < 2) return;
      if (!_passesTimeFilter(s.time)) return;
      polylines.add(
        Polyline(
          points: List<LatLng>.from(s.track),
          color: color,
          strokeWidth: 2,
        ),
      );
    }

    for (final station in _aprsStations.values) {
      addTrack(station, station.isSelf ? Colors.blue : Colors.red);
    }
    for (final station in _voiceStations.values) {
      addTrack(station, Colors.orange);
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final tracks = _showTracks ? _buildTracks() : const <Polyline>[];
    final stationMarkers = _buildStationMarkers();
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
                    // Cancels tile requests that are no longer needed (e.g.
                    // when panning/zooming quickly), which notably improves
                    // performance on the web where browsers cap simultaneous
                    // connections per host.
                    tileProvider: CancellableNetworkTileProvider(),
                  ),
                  if (tracks.isNotEmpty) PolylineLayer(polylines: tracks),
                  if (stationMarkers.isNotEmpty)
                    MarkerLayer(markers: stationMarkers),
                  if (_showAirplanes && _airplanes.isNotEmpty)
                    MarkerLayer(markers: _buildAirplaneMarkers()),
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
