/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'tab_visibility.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_symbols.dart';
import '../dialogs/add_station_dialog.dart';
import '../dialogs/callsign_lookup_dialog.dart';
import '../gps/gps_data.dart';
import '../l10n/app_localizations.dart';
import '../models/aircraft.dart';
import '../models/radio_models.dart';
import '../models/station_info.dart';
import '../satellite/satellite_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';
import '../utils/map_tile_downloader.dart';
import '../utils/map_tile_provider.dart';
import '../utils/num_parsing.dart';
import 'radiosonde_marker.dart';
import 'sarsat_marker.dart';

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
    this.fromAprsIs = false,
    this.symbolTable = '',
    this.symbolCode = '',
    this.isTest = false,
  }) : track = <LatLng>[position];

  final String callsign;
  LatLng position;
  DateTime time;
  final bool isSelf;
  final List<LatLng> track;

  /// True when this marker is a SARSAT self-test beacon (drawn differently
  /// from a real distress beacon). Unused for non-SARSAT markers.
  bool isTest;

  /// APRS symbol table identifier (`/`, `\` or an overlay digit/letter) and
  /// symbol code for this station, used to draw the real APRS symbol instead
  /// of a generic pin. Empty when the station has no symbol information.
  String symbolTable;
  String symbolCode;

  /// True when the most recent position for this station came from APRS-IS
  /// (the internet) rather than from a radio. Used to filter internet traffic
  /// off the map.
  bool fromAprsIs;

  /// Appends a new point to the track when the position actually changed,
  /// matching the C# `AddMapMarker` route behaviour.
  void update(LatLng newPosition, DateTime newTime,
      {bool? fromAprsIs, String? symbolTable, String? symbolCode, bool? isTest}) {
    final last = track.isNotEmpty ? track.last : null;
    if (last == null ||
        last.latitude != newPosition.latitude ||
        last.longitude != newPosition.longitude) {
      track.add(newPosition);
    }
    position = newPosition;
    time = newTime;
    if (isTest != null) this.isTest = isTest;
    // `fromAprsIs` is sticky-false: a station is only treated as internet-only
    // while every packet for it has come from APRS-IS. Once it is heard on RF
    // (fromAprsIs == false) it stays visible even after the internet echoes the
    // same packet back (e.g. when we ourselves gate it up), so the "Show
    // Internet Traffic" filter never hides an RF-heard station.
    if (fromAprsIs != null) this.fromAprsIs = this.fromAprsIs && fromAprsIs;
    if (symbolTable != null && symbolTable.isNotEmpty) {
      this.symbolTable = symbolTable;
    }
    if (symbolCode != null && symbolCode.isNotEmpty) {
      this.symbolCode = symbolCode;
    }
  }
}

/// Map tab - geographic map display with OpenStreetMap
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

/// Returns true when [lat]/[lng] are finite and within valid WGS-84 ranges.
///
/// Markers or track points with non-finite (NaN/Infinity) or out-of-range
/// coordinates make flutter_map's Web Mercator projection produce infinite
/// pixel values, which freezes the map ("Not responding", issue #19). Such
/// positions are rejected before a marker/track is ever created.
bool _isValidLatLng(double lat, double lng) =>
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90.0 &&
    lat <= 90.0 &&
    lng >= -180.0 &&
    lng <= 180.0;

/// Luminance-inverting grayscale filter that turns the light OpenStreetMap
/// tiles into a dark-themed map. Colored markers and tracks are drawn above
/// the filtered tile layer so they keep their own colors.
const ColorFilter _darkMapTileFilter = ColorFilter.matrix(<double>[
  -0.2126, -0.7152, -0.0722, 0, 255, //
  -0.2126, -0.7152, -0.0722, 0, 255, //
  -0.2126, -0.7152, -0.0722, 0, 255, //
  0, 0, 0, 1, 0, //
]);

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
  final MapController _mapController = MapController();
  final DataBrokerClient _broker = DataBrokerClient();

  // APRS device id used for broker messages (matches the C# reference).
  static const int _aprsDeviceId = 1;

  // Map settings (loaded from DataBroker)
  bool _isOfflineMode = false;
  bool _showTracks = true;
  bool _showAirplanes = false;
  bool _showContactsOnly = false;
  bool _largeMarkers = true;

  /// When true, tracked amateur satellites are drawn on the map.
  bool _showSatellites = false;
  /// Mirrors the app-level 'Satellite support' setting; when false the whole
  /// satellite overlay (and its menu item) is hidden.
  bool _satelliteSupport = false;
  List<SatellitePosition> _satellites = const [];
  List<List<double>> _satGroundTrack = const [];
  int? _selectedSatId;

  /// When true, stations are drawn using their real APRS symbols instead of
  /// generic location pins.
  bool _showAprsSymbols = true;

  /// When false, APRS-IS (internet) stations are hidden from the map.
  bool _showAprsIs = true;

  /// When true the user is drawing a rectangle on the map to select a cache
  /// area. Interaction with markers/tracks is suppressed.
  bool _isSelectingCacheArea = false;
  LatLng? _cacheSelectionStart;
  LatLng? _cacheSelectionEnd;

  /// Tile provider for the map. Recreated only when [_isOfflineMode] changes so
  /// that normal rebuilds (marker/track updates) don't reset the tile cache or
  /// leak HTTP clients. In offline mode it serves only disk-cached tiles.
  late TileProvider _tileProvider = mapTileProvider(offline: _isOfflineMode);

  /// Current aircraft to display, received from the "Airplanes" broker event.
  List<Aircraft> _airplanes = [];

  /// Time filter in minutes (0 = show all). Markers/tracks older than this are
  /// hidden, mirroring the C# `MapTimeFilter` behaviour.
  int _markerTimeFilter = 0;

  /// Periodic timer that triggers a rebuild so markers that have aged past the
  /// time filter threshold are removed from the display.
  Timer? _filterRefreshTimer;

  /// Debounces persisting the map center/zoom so a zoom/pan gesture writes to
  /// SharedPreferences once when it settles instead of on every camera frame.
  Timer? _positionSaveTimer;

  /// APRS station markers keyed by callsign (red, or blue for "Self").
  final Map<String, _StationMarkerData> _aprsStations = {};

  /// Voice / BSS source-station markers keyed by source callsign (orange).
  final Map<String, _StationMarkerData> _voiceStations = {};

  /// SARSAT 406 distress-beacon markers keyed by 15-hex beacon ID (red SOS).
  final Map<String, _StationMarkerData> _sarsatBeacons = {};

  /// DFM radiosonde markers keyed by sonde ID (light-blue balloon).
  final Map<String, _StationMarkerData> _radiosondeBeacons = {};

  /// Guards against loading the historical APRS packet list more than once,
  /// mirroring the C# `_historicalPacketsLoaded` flag.
  bool _historicalPacketsLoaded = false;

  /// Guards against loading the persisted APRS-IS (internet) history more than
  /// once. Separate from [_historicalPacketsLoaded] because the RF history and
  /// the internet history are served by different handlers as two async
  /// batches.
  bool _historicalAprsIsLoaded = false;

  /// Latest fixed position from an external serial GPS receiver (device 1,
  /// `GpsData`). Null when there is no GPS or no valid fix. Mirrors the C#
  /// `MapTabUserControl` serial GPS marker (reserved key 0).
  GpsData? _serialGps;

  /// Latest GPS-locked positions reported by connected radios, keyed by device
  /// ID. Only contains radios that currently have a valid GPS lock. Mirrors the
  /// C# `MapTabUserControl.radioMarkers` (blue markers per device).
  final Map<int, RadioPosition> _radioPositions = {};

  /// Index for cycling through available GPS positions when repeatedly pressing
  /// "Center to GPS". Mirrors the C# `centerToGpsCycleIndex`.
  int _centerToGpsCycleIndex = 0;

  /// "Center to GPS" is available whenever at least one radio has a GPS lock or
  /// a serial GPS fix is present. Mirrors the C# `UpdateCenterToGpsButtonState`
  /// (`radioMarkers.Count > 0`, which includes the serial GPS marker).
  bool get _centerToGpsEnabled =>
      _radioPositions.isNotEmpty || _serialGps != null;

  /// Ordered list of GPS positions "Center to GPS" cycles through: one per
  /// connected radio with a lock (sorted by device id for a stable order),
  /// followed by the serial GPS fix. Mirrors the C# `radioMarkers` ordering
  /// (Bluetooth radios + serial GPS key 0).
  List<LatLng> get _centerToGpsTargets {
    final targets = <LatLng>[];
    final deviceIds = _radioPositions.keys.toList()..sort();
    for (final id in deviceIds) {
      final pos = _radioPositions[id]!;
      targets.add(LatLng(pos.latitude, pos.longitude));
    }
    final gps = _serialGps;
    if (gps != null) {
      targets.add(LatLng(gps.latitude, gps.longitude));
    }
    return targets;
  }

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

    // Receive satellite tracking updates from the SatelliteHandler.
    _broker.subscribe(
      deviceId: 0,
      name: 'SatellitePositions',
      callback: _onSatellitePositions,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SatelliteGroundTrack',
      callback: _onSatelliteGroundTrack,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SelectedSatelliteId',
      callback: _onSelectedSatelliteChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'ShowSatellitesOnMap',
      callback: _onShowSatellitesChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SatelliteSupport',
      callback: _onSatelliteSupportChanged,
    );
    // Ask the handler to re-emit its current snapshot (broadcast-only events).
    _broker.dispatch(
      deviceId: 0,
      name: 'SatelliteResync',
      data: null,
      store: false,
    );

    // Keep the APRS-IS visibility filter in sync with the APRS tab.
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsShowAprsIs',
      callback: (_, _, data) {
        final show = (data is int ? data : 1) == 1;
        if (show == _showAprsIs) return;
        if (mounted) setState(() => _showAprsIs = show);
      },
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

    // Persisted internet (APRS-IS) history, served by the APRS-IS manager.
    // Loaded so internet stations from previous sessions appear on the map and
    // are tagged `fromAprsIs` so the "Show Internet Traffic" filter hides them.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsIsStoreReady',
      callback: _onAprsIsStoreReady,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsIsPacketList',
      callback: _onAprsIsPacketList,
    );

    // Request the current packet list from the AprsHandler on-demand.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );

    // Request the persisted internet (APRS-IS) history on-demand.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsIsPackets',
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
    // The broker does not replay stored values to new subscribers, so load any
    // decoded-text history that already carries a location. Without this, a
    // voice/BSS/SARSAT marker decoded before the map tab was first built would
    // not appear until the next decode.
    _loadInitialDecodedTextHistory();

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
    // Reload positions whenever the set of connected radios changes so a radio
    // that locks GPS (or connects) after the map tab was first built still gets
    // its marker, even if no further live Position event arrives.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    // Load initial positions for any already connected radios that have a fix.
    _loadInitialRadioPositions();
  }

  /// Whether a radio position should be shown on the map. Shows the marker when
  /// the radio reports a GPS lock or carries real (non-zero) coordinates, so a
  /// valid position is never hidden by a missing/late `locked` flag.
  static bool _positionHasFix(RadioPosition pos) =>
      pos.locked || pos.latitude != 0 || pos.longitude != 0;

  /// Re-reads the stored position for every connected radio when the connected
  /// radio list changes.
  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(_loadInitialRadioPositions);
  }

  /// Loads the current position for every connected radio so the markers are
  /// present when switching to the Map tab. Mirrors the C#
  /// `LoadInitialRadioPositions`.
  void _loadInitialRadioPositions() {
    final radios = _broker.getValueDynamic(_aprsDeviceId, 'ConnectedRadios');
    if (radios is! List) return;
    final connectedIds = <int>{};
    for (final radio in radios) {
      if (radio is! Map) continue;
      final deviceId = radio['DeviceId'] as int? ?? radio['deviceId'] as int?;
      if (deviceId == null || deviceId <= 0) continue;
      connectedIds.add(deviceId);
      final posData = _broker.getValueDynamic(deviceId, 'Position');
      if (posData is Map) {
        final pos = RadioPosition.fromJson(Map<String, dynamic>.from(posData));
        if (_positionHasFix(pos)) {
          _radioPositions[deviceId] = pos;
        }
      }
    }
    // Drop positions for radios that are no longer connected.
    _radioPositions.removeWhere((id, _) => !connectedIds.contains(id));
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
      if (pos != null && _positionHasFix(pos)) {
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

  void _onSatellitePositions(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final list = data is List
        ? data.whereType<SatellitePosition>().toList()
        : const <SatellitePosition>[];
    setState(() => _satellites = list);
  }

  void _onSatelliteGroundTrack(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final track = <List<double>>[];
    if (data is List) {
      for (final e in data) {
        if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
          track.add([(e[0] as num).toDouble(), (e[1] as num).toDouble()]);
        }
      }
    }
    setState(() => _satGroundTrack = track);
  }

  void _onSelectedSatelliteChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final id = data is int ? data : (data is num ? data.toInt() : null);
    setState(() => _selectedSatId = id);
  }

  void _onShowSatellitesChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _showSatellites = (data as int?) == 1;
      if (!_showSatellites) {
        _satellites = const [];
        _satGroundTrack = const [];
      }
    });
  }

  void _onSatelliteSupportChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _satelliteSupport = (data as int?) == 1;
      if (!_satelliteSupport) {
        _satellites = const [];
        _satGroundTrack = const [];
      }
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

  /// The APRS-IS (internet) history store is ready - request the persisted
  /// internet packet list (once).
  void _onAprsIsStoreReady(int deviceId, String name, Object? data) {
    if (_historicalAprsIsLoaded) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsIsPackets',
      data: null,
      store: false,
    );
  }

  /// Loads persisted APRS-IS (internet) packets from the on-demand request,
  /// once. These packets are already tagged `fromAprsIs` by the APRS-IS
  /// manager, so the "Show Internet Traffic" filter can hide them.
  void _onAprsIsPacketList(int deviceId, String name, Object? data) {
    if (_historicalAprsIsLoaded) return;
    if (data is! List) return;
    _historicalAprsIsLoaded = true;

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
      _historicalAprsIsLoaded = false;
      return;
    }
    _aprsStations.clear();
    _historicalPacketsLoaded = false;
    _historicalAprsIsLoaded = false;
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
    if (!_isValidLatLng(lat, lng)) return false;

    // The sender callsign is the second AX.25 address (index 1).
    if (packet.addresses.length < 2) return false;
    final callsign = packet.addresses[1].callSignWithId;
    if (callsign.isEmpty) return false;

    final time = aprsPacket.timeStamp ?? packet.time;
    final point = LatLng(lat, lng);

    final existing = _aprsStations[callsign];
    if (existing != null) {
      existing.update(point, time,
          fromAprsIs: aprsPacket.fromAprsIs,
          symbolTable: aprsPacket.symbolTable,
          symbolCode: aprsPacket.symbol);
    } else {
      _aprsStations[callsign] = _StationMarkerData(
        callsign: callsign,
        position: point,
        time: time,
        isSelf: callsign == 'Self',
        fromAprsIs: aprsPacket.fromAprsIs,
        symbolTable: aprsPacket.symbolTable,
        symbolCode: aprsPacket.symbol,
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Voice / BSS source marker handlers (orange)
  // ---------------------------------------------------------------------------

  /// Loads the currently-stored decoded-text history and processes any entries
  /// that carry a location. Used at init because broker subscriptions do not
  /// replay the last stored value.
  void _loadInitialDecodedTextHistory() {
    final data =
        _broker.getValueDynamic(_aprsDeviceId, 'DecodedTextHistory', null);
    if (data is! List) return;
    for (final entry in data) {
      if (entry is Map) {
        _processVoiceEntry(entry);
        _processSarsatEntry(entry);
        _processRadiosondeEntry(entry);
      }
    }
  }

  /// Handles the DecodedTextHistory event - loads historical voice/BSS entries
  /// that carry a location. Mirrors the C# `OnDecodedTextHistory`.
  void _onDecodedTextHistory(int deviceId, String name, Object? data) {
    if (data is! List) return;
    var changed = false;
    for (final entry in data) {
      if (entry is Map) {
        changed = _processVoiceEntry(entry) || changed;
        changed = _processSarsatEntry(entry) || changed;
        changed = _processRadiosondeEntry(entry) || changed;
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
    final voiceChanged = _processVoiceEntry(data);
    final sarsatChanged = _processSarsatEntry(data);
    final radiosondeChanged = _processRadiosondeEntry(data);
    if ((voiceChanged || sarsatChanged || radiosondeChanged) && mounted) {
      setState(() {});
    }
  }

  /// Adds or updates an orange marker for a voice/BSS source station from a
  /// decoded-text entry map. Returns true when the marker set changed.
  bool _processVoiceEntry(Map<dynamic, dynamic> entry) {
    final source = entry['source'];
    if (source is! String || source.isEmpty) return false;

    final lat = asDouble(entry['latitude']);
    final lng = asDouble(entry['longitude']);
    if (lat == 0 && lng == 0) return false;
    if (!_isValidLatLng(lat, lng)) return false;

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

  /// Adds or updates a red "SOS" marker for a decoded SARSAT 406 beacon that
  /// carries a position, keyed by its 15-hex beacon ID. Returns true when the
  /// marker set changed.
  bool _processSarsatEntry(Map<dynamic, dynamic> entry) {
    if (entry['encoding'] != 'Sarsat') return false;
    final lat = asDouble(entry['latitude']);
    final lng = asDouble(entry['longitude']);
    if (lat == 0 && lng == 0) return false;
    if (!_isValidLatLng(lat, lng)) return false;
    final s = entry['sarsat'];
    final hexId = (s is Map ? s['hexId'] as String? : null) ?? 'Beacon';
    final isTest = s is Map && s['isTest'] == true;
    final time = _toDateTime(entry['time']);
    final point = LatLng(lat, lng);
    final existing = _sarsatBeacons[hexId];
    if (existing != null) {
      existing.update(point, time, isTest: isTest);
    } else {
      _sarsatBeacons[hexId] = _StationMarkerData(
        callsign: hexId,
        position: point,
        time: time,
        isSelf: false,
        isTest: isTest,
      );
    }
    return true;
  }

  /// Adds or updates a light-blue marker for a decoded DFM radiosonde that
  /// carries a position, keyed by its sonde ID. Returns true when the marker
  /// set changed.
  bool _processRadiosondeEntry(Map<dynamic, dynamic> entry) {
    if (entry['encoding'] != 'Radiosonde') return false;
    final lat = asDouble(entry['latitude']);
    final lng = asDouble(entry['longitude']);
    if (lat == 0 && lng == 0) return false;
    if (!_isValidLatLng(lat, lng)) return false;
    final r = entry['radiosonde'];
    final id = (r is Map ? r['sondeId'] as String? : null);
    final key = (id != null && id.isNotEmpty) ? id : 'Radiosonde';
    final time = _toDateTime(entry['time']);
    final point = LatLng(lat, lng);
    final existing = _radiosondeBeacons[key];
    if (existing != null) {
      existing.update(point, time);
    } else {
      _radiosondeBeacons[key] = _StationMarkerData(
        callsign: key,
        position: point,
        time: time,
        isSelf: false,
      );
    }
    return true;
  }

  static DateTime _toDateTime(Object? v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
  /// Starts or stops the periodic refresh timer depending on whether a time
  /// filter is active. When a filter is set, the timer fires every 60 seconds
  /// to remove markers that have aged past the threshold.
  void _updateFilterRefreshTimer() {
    _filterRefreshTimer?.cancel();
    _filterRefreshTimer = null;
    if (_markerTimeFilter > 0 && isTabVisible) {
      _filterRefreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) {
          if (mounted) setState(() {});
        },
      );
    }
  }

  @override
  void onTabVisibilityChanged(bool visible) {
    // Only run the marker-ageing refresh timer while the Map tab is on-screen.
    _updateFilterRefreshTimer();
  }

  /// True when [time] is within the active time filter window (or no filter).
  bool _passesTimeFilter(DateTime time) {
    if (_markerTimeFilter == 0) return true;
    final cutoff = time.add(Duration(minutes: _markerTimeFilter));
    return DateTime.now().compareTo(cutoff) <= 0;
  }

  @override
  void dispose() {
    _filterRefreshTimer?.cancel();
    _positionSaveTimer?.cancel();
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
    // double.tryParse accepts "NaN"/"Infinity", so a previously poisoned
    // MapLatitude/MapLongitude would otherwise reload here and crash the map on
    // every launch (recoverable only by clearing app data). Reject any
    // non-finite / out-of-range value and fall back to the default view.
    if (!_isValidLatLng(_initialLat, _initialLng)) {
      _initialLat = _defaultLat;
      _initialLng = _defaultLng;
    }
    _initialZoom =
        (DataBroker.getValue<int>(0, 'MapZoom', _defaultZoom.toInt()) ??
                _defaultZoom.toInt())
            .toDouble();
    if (!_initialZoom.isFinite) _initialZoom = _defaultZoom;

    // Load settings
    _isOfflineMode =
        (DataBroker.getValue<int>(0, 'MapOfflineMode', 0) ?? 0) == 1;
    _tileProvider = mapTileProvider(offline: _isOfflineMode);
    _showTracks = (DataBroker.getValue<int>(0, 'MapShowTracks', 1) ?? 1) == 1;
    _largeMarkers =
        (DataBroker.getValue<int>(0, 'MapLargeMarkers', 1) ?? 1) == 1;
    _showAprsSymbols =
        (DataBroker.getValue<int>(0, 'MapShowAprsSymbols', 1) ?? 1) == 1;
    _showAprsIs =
        (DataBroker.getValue<int>(0, 'AprsShowAprsIs', 1) ?? 1) == 1;
    _markerTimeFilter = DataBroker.getValue<int>(0, 'MapTimeFilter', 0) ?? 0;
    _updateFilterRefreshTimer();
    _showAirplanes =
        (DataBroker.getValue<int>(0, 'ShowAirplanesOnMap', 0) ?? 0) == 1;
    _showContactsOnly =
        (DataBroker.getValue<int>(0, 'MapShowContactsOnly', 0) ?? 0) == 1;
    _showSatellites =
        (DataBroker.getValue<int>(0, 'ShowSatellitesOnMap', 0) ?? 0) == 1;
    _satelliteSupport =
        (DataBroker.getValue<int>(0, 'SatelliteSupport', 0) ?? 0) == 1;
    _selectedSatId = DataBroker.getValue<int>(0, 'SelectedSatelliteId', null);
  }

  /// Called when the map position changes.
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    // During a zoom/pan gesture the layout can momentarily be zero-size (e.g.
    // while an APRS-beacon setState rebuilds the map), producing a non-finite
    // camera. Persisting that would write "NaN"/"Infinity" to storage (which
    // double.tryParse happily reloads on next launch) and camera.zoom.toInt()
    // throws on a non-finite value. Bail out so poison is never stored.
    final center = camera.center;
    if (!center.latitude.isFinite ||
        !center.longitude.isFinite ||
        !camera.zoom.isFinite) {
      return;
    }
    // Force the map to always stay north-up. Even though the rotate gesture is
    // disabled, other paths (keyboard/cursor rotation, restored state) can
    // leave the camera tilted with no UI to correct it (issue #30). Snap any
    // residual rotation back to zero after the current frame to avoid
    // re-entrancy with the in-progress position change.
    if (camera.rotation != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mapController.camera.rotation != 0) {
          _mapController.rotate(0);
        }
      });
    }
    // Debounce: a gesture fires this on every frame, so persist only once the
    // camera has settled to avoid a SharedPreferences write storm.
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _broker.dispatch(
        deviceId: 0,
        name: 'MapLatitude',
        data: center.latitude.toString(),
      );
      _broker.dispatch(
        deviceId: 0,
        name: 'MapLongitude',
        data: center.longitude.toString(),
      );
      _broker.dispatch(deviceId: 0, name: 'MapZoom', data: camera.zoom.toInt());
    });
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

  /// Centers the map on the next available GPS position, cycling through every
  /// connected radio's GPS lock and the serial GPS fix on repeated presses.
  /// Mirrors the C# `centerToGpsButton_Click`.
  void _centerToGps() {
    final targets = _centerToGpsTargets;
    if (targets.isEmpty) return;

    if (_centerToGpsCycleIndex >= targets.length) _centerToGpsCycleIndex = 0;
    final target = targets[_centerToGpsCycleIndex];
    _centerToGpsCycleIndex = (_centerToGpsCycleIndex + 1) % targets.length;

    _mapController.move(target, _mapController.camera.zoom);
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
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
              Text(l10n.mapOfflineMode),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'cache',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: !_isOfflineMode,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.mapCacheArea)],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'centerGps',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _centerToGpsEnabled,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.mapCenterGps)],
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
              Text(l10n.mapShowTracks),
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
              Text(l10n.mapShowMarkers),
              const Spacer(),
              Text(
                _markerFilterLabel(_markerTimeFilter),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
                Text(AppLocalizations.of(context).mapShowAirplanes),
              ],
            ),
          ),
        if (_satelliteSupport)
          PopupMenuItem<String>(
            value: 'satellites',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _showSatellites
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Show Satellites'),
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
              Text(AppLocalizations.of(context).mapLargeMarkers),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'showAprsIs',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showAprsIs
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).aprsShowAprsIs),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'aprsSymbols',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showAprsSymbols
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).mapShowAprsSymbols),
            ],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [const SizedBox(width: 20), Text(AppLocalizations.of(context).tabDetach)],
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
            // Recreate the tile provider so it stops/starts hitting the
            // network. The keyed TileLayer (see build) disposes the old
            // provider's HTTP client and reloads tiles in the new mode.
            _tileProvider = mapTileProvider(offline: _isOfflineMode);
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
        case 'satellites':
          setState(() {
            _showSatellites = !_showSatellites;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'ShowSatellitesOnMap',
            data: _showSatellites ? 1 : 0,
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
        case 'showAprsIs':
          setState(() {
            _showAprsIs = !_showAprsIs;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'AprsShowAprsIs',
            data: _showAprsIs ? 1 : 0,
          );
          break;
        case 'aprsSymbols':
          setState(() {
            _showAprsSymbols = !_showAprsSymbols;
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'MapShowAprsSymbols',
            data: _showAprsSymbols ? 1 : 0,
          );
          break;
        case 'centerGps':
          _centerToGps();
          break;
        case 'detach':
          windowService.createWindow('map');
          break;
        case 'cache':
          setState(() {
            _isSelectingCacheArea = true;
            _cacheSelectionStart = null;
            _cacheSelectionEnd = null;
          });
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

  /// Formats a [DateTime] for marker tooltips using OS locale (no seconds).
  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat.yMd().add_Hm().format(local);
  }

  /// Human-readable label for the active marker time filter (in minutes).
  String _markerFilterLabel(int minutes) {
    final l10n = AppLocalizations.of(context);
    switch (minutes) {
      case 0:
        return l10n.mapFilterAll;
      case 30:
        return l10n.mapFilterLast30;
      case 60:
        return l10n.mapFilterLastHour;
      case 360:
        return l10n.mapFilterLast6;
      case 720:
        return l10n.mapFilterLast12;
      case 1440:
        return l10n.mapFilterLast24;
    }
    return l10n.mapFilterAll;
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
        for (final (_, minutes) in _markerFilterOptions)
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
                Text(_markerFilterLabel(minutes)),
              ],
            ),
          ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<int>(
          value: -1,
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showContactsOnly
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).mapShowContactsOnly),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == -1) {
        setState(() {
          _showContactsOnly = !_showContactsOnly;
        });
        _broker.dispatch(
          deviceId: 0,
          name: 'MapShowContactsOnly',
          data: _showContactsOnly ? 1 : 0,
        );
        return;
      }
      if (value == _markerTimeFilter) return;
      setState(() {
        _markerTimeFilter = value;
      });
      _updateFilterRefreshTimer();
      _broker.dispatch(deviceId: 0, name: 'MapTimeFilter', data: value);
    });
  }

  /// Builds the airplane markers for aircraft that have a known position.
  List<Marker> _buildAirplaneMarkers() {
    final markers = <Marker>[];
    for (final aircraft in _airplanes) {
      if (!aircraft.hasPosition) continue;
      if (!_isValidLatLng(aircraft.latitude!, aircraft.longitude!)) continue;
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
        : (aircraft.hex ?? AppLocalizations.of(context).commonUnknown);
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

  /// Mean Earth radius in kilometres, used for the satellite footprint circle.
  static const double _earthRadiusKm = 6371.0;

  /// Builds a marker at each tracked satellite's sub-point. The selected bird
  /// is amber, others green when above the horizon and grey when below.
  List<Marker> _buildSatelliteMarkers() {
    final markers = <Marker>[];
    for (final sat in _satellites) {
      final selected = sat.noradId == _selectedSatId;
      final color = selected
          ? Colors.amber
          : (sat.isVisible ? Colors.green : Colors.grey);
      markers.add(
        Marker(
          point: LatLng(sat.latitudeDeg, sat.longitudeDeg),
          width: 120,
          height: 44,
          child: Tooltip(
            message:
                '${sat.name}\n'
                'az ${sat.azimuthDeg.round()}\u00b0 el ${sat.elevationDeg.round()}\u00b0\n'
                'alt ${sat.altitudeKm.round()} km',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.satellite_alt, color: color, size: 24),
                Text(
                  sat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// Builds the radio-horizon footprint circle for each tracked satellite.
  List<CircleMarker> _buildSatelliteFootprints() {
    final circles = <CircleMarker>[];
    for (final sat in _satellites) {
      final selected = sat.noradId == _selectedSatId;
      // Ground radius of the visibility circle for a satellite at altitude h:
      // R * acos(R / (R + h)).
      final radiusKm =
          _earthRadiusKm * math.acos(_earthRadiusKm / (_earthRadiusKm + sat.altitudeKm));
      final color = selected ? Colors.amber : Colors.green;
      circles.add(
        CircleMarker(
          point: LatLng(sat.latitudeDeg, sat.longitudeDeg),
          radius: radiusKm * 1000,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.08),
          borderColor: color.withValues(alpha: 0.5),
          borderStrokeWidth: selected ? 2 : 1,
        ),
      );
    }
    return circles;
  }

  /// Builds the selected satellite's ground track, split into separate
  /// polylines wherever the path crosses the \u00b1180\u00b0 antimeridian.
  List<Polyline> _buildSatelliteTrack() {
    final polylines = <Polyline>[];
    var segment = <LatLng>[];
    LatLng? prev;
    for (final p in _satGroundTrack) {
      final point = LatLng(p[0], p[1]);
      if (prev != null && (point.longitude - prev.longitude).abs() > 180) {
        if (segment.length > 1) {
          polylines.add(_trackPolyline(segment));
        }
        segment = <LatLng>[];
      }
      segment.add(point);
      prev = point;
    }
    if (segment.length > 1) polylines.add(_trackPolyline(segment));
    return polylines;
  }

  Polyline _trackPolyline(List<LatLng> points) => Polyline(
    points: points,
    color: Colors.amber.withValues(alpha: 0.7),
    strokeWidth: 2,
  );

  /// Returns the set of contact callsigns (upper-cased) from the Stations list.
  Set<String> _getContactCallsigns() {
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    final callsigns = <String>{};
    if (raw is List) {
      for (final item in raw) {
        final map = item is Map<String, dynamic>
            ? item
            : (item is Map ? Map<String, dynamic>.from(item) : null);
        if (map != null) {
          final cs = map['Callsign'] as String?;
          if (cs != null && cs.isNotEmpty) callsigns.add(cs.toUpperCase());
        }
      }
    }
    return callsigns;
  }

  /// Builds the station markers (APRS red/blue + voice/BSS orange) that pass
  /// the active time filter.
  List<Marker> _buildStationMarkers() {
    final markers = <Marker>[];
    final double size = _largeMarkers ? 30 : 20;
    final contactCallsigns =
        _showContactsOnly ? _getContactCallsigns() : null;

    // Theme-aware colours for the APRS symbol chips. The symbol itself is drawn
    // in a neutral high-contrast colour (dark on light themes, light on dark
    // themes) so it stays legible over the map tiles; the category colour
    // (blue/red/orange) is carried by the chip border and the spike instead.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color symbolChipBg = isDark ? const Color(0xFF262626) : Colors.white;
    final Color symbolFg = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final double spikeHeight = size * 0.55;

    void addStation(_StationMarkerData s, Color color) {
      if (!_passesTimeFilter(s.time)) return;
      // When "Show Contacts Only" is active, skip non-self stations that are
      // not in the contact list.
      if (contactCallsigns != null &&
          !s.isSelf &&
          !contactCallsigns.contains(s.callsign.toUpperCase())) {
        return;
      }
      // When the "Show APRS Symbols" option is enabled and this station has a
      // renderable symbol, draw the real APRS symbol inside a theme-aware chip
      // sitting on top of a small coloured spike whose tip marks the exact
      // position. Otherwise fall back to a generic pin whose tip marks it.
      final aprsSymbol = _showAprsSymbols && s.symbolCode.isNotEmpty
          ? aprsSymbolFor(s.symbolTable, s.symbolCode)
          : null;
      if (aprsSymbol != null && aprsSymbol.hasVisual) {
        markers.add(
          Marker(
            point: s.position,
            width: size,
            height: size + spikeHeight,
            alignment: Alignment.topCenter,
            child: _wrapStationMenu(
              s,
              Tooltip(
                message: '${s.callsign}\n${_formatTime(s.time)}',
                child: _buildAprsSymbolMarker(
                  table: s.symbolTable,
                  code: s.symbolCode,
                  size: size,
                  spikeHeight: spikeHeight,
                  spikeColor: color,
                  chipBg: symbolChipBg,
                  symbolColor: symbolFg,
                ),
              ),
            ),
          ),
        );
      } else {
        markers.add(
          Marker(
            point: s.position,
            width: size,
            height: size,
            alignment: Alignment.topCenter,
            child: _wrapStationMenu(
              s,
              Tooltip(
                message: '${s.callsign}\n${_formatTime(s.time)}',
                child: Icon(Icons.location_pin, color: color, size: size),
              ),
            ),
          ),
        );
      }
    }

    // APRS markers: blue for "Self", red otherwise. Internet (APRS-IS) stations
    // are hidden when the APRS-IS filter is off.
    for (final station in _aprsStations.values) {
      if (station.fromAprsIs && !_showAprsIs) continue;
      addStation(station, station.isSelf ? Colors.blue : Colors.red);
    }

    // Voice / BSS source markers: orange.
    for (final station in _voiceStations.values) {
      addStation(station, Colors.orange);
    }

    // SARSAT 406 distress beacons: a red "SOS" badge for a real distress signal,
    // an orange "TEST" badge for a self-test. Always shown (a distress signal
    // should stay visible regardless of the time filter).
    for (final beacon in _sarsatBeacons.values) {
      markers.add(
        Marker(
          point: beacon.position,
          width: size,
          height: size + spikeHeight,
          alignment: Alignment.topCenter,
          child: Tooltip(
            message: 'SARSAT ${beacon.callsign}'
                '${beacon.isTest ? ' (self-test)' : ''}'
                '\n${_formatTime(beacon.time)}',
            child: SarsatMarker(
              size: size,
              spikeHeight: spikeHeight,
              isTest: beacon.isTest,
            ),
          ),
        ),
      );
    }

    // Radiosonde markers: a light-blue "X" badge on a spike. Always shown.
    for (final beacon in _radiosondeBeacons.values) {
      markers.add(
        Marker(
          point: beacon.position,
          width: size,
          height: size + spikeHeight,
          alignment: Alignment.topCenter,
          child: Tooltip(
            message: '${beacon.callsign}\n${_formatTime(beacon.time)}',
            child: RadiosondeMarker(size: size, spikeHeight: spikeHeight),
          ),
        ),
      );
    }

    // External serial GPS marker (blue), shown whenever there is a valid fix.
    final gps = _serialGps;
    if (gps != null && _isValidLatLng(gps.latitude, gps.longitude)) {
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
      if (!_isValidLatLng(pos.latitude, pos.longitude)) return;
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
            child: Icon(
              Icons.location_pin,
              color: Colors.blue.shade900,
              size: size,
            ),
          ),
        ),
      );
    });

    // Paint markers north-to-south so that stations further south (lower
    // latitude) are drawn last and therefore appear on top. flutter_map renders
    // markers in list order, so the southernmost marker ends up overlapping the
    // symbols/spikes of the ones to its north.
    markers.sort((a, b) => b.point.latitude.compareTo(a.point.latitude));

    return markers;
  }

  /// Wraps a callsign station marker so a right-click (desktop) or long-press
  /// (touch) opens a context menu offering to message the station, center the
  /// map on it, or — when several stations overlap at the same spot — pick one
  /// from the list first.
  Widget _wrapStationMenu(_StationMarkerData station, Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) =>
          _showStationContextMenu(d.globalPosition, station),
      onLongPressStart: (d) =>
          _showStationContextMenu(d.globalPosition, station),
      child: child,
    );
  }

  /// Returns every currently-visible callsign station (APRS + voice/BSS) whose
  /// on-screen position is within a few pixels of [target], so overlapping
  /// markers can be disambiguated. The returned list always starts with
  /// [target].
  List<_StationMarkerData> _stationsNear(_StationMarkerData target) {
    final camera = _mapController.camera;
    final Offset anchor = camera.latLngToScreenOffset(target.position);
    const double thresholdPx = 22;
    final contactCallsigns =
        _showContactsOnly ? _getContactCallsigns() : null;
    final result = <_StationMarkerData>[target];

    bool hidden(_StationMarkerData s) =>
        contactCallsigns != null &&
        !s.isSelf &&
        !contactCallsigns.contains(s.callsign.toUpperCase());

    void consider(_StationMarkerData s) {
      if (identical(s, target)) return;
      if (!_passesTimeFilter(s.time) || hidden(s)) return;
      final Offset o = camera.latLngToScreenOffset(s.position);
      if ((o - anchor).distance <= thresholdPx) result.add(s);
    }

    for (final s in _aprsStations.values) {
      if (s.fromAprsIs && !_showAprsIs) continue;
      consider(s);
    }
    for (final s in _voiceStations.values) {
      consider(s);
    }
    return result;
  }

  /// Opens the station context menu at [globalPosition]. When several stations
  /// overlap the tapped one, a picker is shown first so the user can choose
  /// which station to act on.
  void _showStationContextMenu(
    Offset globalPosition,
    _StationMarkerData station,
  ) {
    final near = _stationsNear(station);
    if (near.length > 1) {
      _showOverlappingStationsMenu(globalPosition, near);
    } else {
      _showStationActionMenu(globalPosition, station);
    }
  }

  RelativeRect _menuPositionAt(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );
  }

  /// Lists the stations overlapping at the same spot (UIView32 style). Picking
  /// one opens that station's action menu.
  Future<void> _showOverlappingStationsMenu(
    Offset globalPosition,
    List<_StationMarkerData> stations,
  ) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showMenu<_StationMarkerData>(
      context: context,
      position: _menuPositionAt(globalPosition),
      items: [
        PopupMenuItem<_StationMarkerData>(
          enabled: false,
          height: 28,
          child: Text(
            l10n.mapStationsHere,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const PopupMenuDivider(height: 8),
        for (final s in stations)
          PopupMenuItem<_StationMarkerData>(
            value: s,
            height: 36,
            child: Text(s.callsign),
          ),
      ],
    );
    if (selected != null && mounted) {
      _showStationActionMenu(globalPosition, selected);
    }
  }

  /// Shows the per-station actions: message the station or center the map on
  /// it (zooming in to separate overlapping markers).
  Future<void> _showStationActionMenu(
    Offset globalPosition,
    _StationMarkerData station,
  ) async {
    final l10n = AppLocalizations.of(context);
    final bool isContact = _hasAprsContact(station.callsign);
    final action = await showMenu<String>(
      context: context,
      position: _menuPositionAt(globalPosition),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            station.callsign,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'message',
          height: 40,
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18),
              const SizedBox(width: 8),
              Text(l10n.mapStationMessage),
            ],
          ),
        ),
        if (!isContact)
          PopupMenuItem<String>(
            value: 'addContact',
            height: 40,
            child: Row(
              children: [
                const Icon(Icons.person_add_alt, size: 18),
                const SizedBox(width: 8),
                Text(l10n.mapStationAddContact),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'center',
          height: 40,
          child: Row(
            children: [
              const Icon(Icons.my_location, size: 18),
              const SizedBox(width: 8),
              Text(l10n.mapStationCenter),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'lookup',
          height: 40,
          child: Row(
            children: [
              const Icon(Icons.badge_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.callsignLookup),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'message':
        _messageStation(station);
        break;
      case 'addContact':
        _addStationContact(station);
        break;
      case 'center':
        _centerOnStation(station);
        break;
      case 'lookup':
        CallsignLookupDialog.show(context, initialCallsign: station.callsign);
        break;
    }
  }

  /// Whether an APRS-type contact already exists for [callsign] in the address
  /// book (device 0 `Stations`).
  bool _hasAprsContact(String callsign) {
    final target = callsign.toUpperCase();
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is! List) return false;
    for (final item in raw) {
      final map = item is Map<String, dynamic>
          ? item
          : (item is Map ? Map<String, dynamic>.from(item) : null);
      if (map == null) continue;
      final cs = (map['Callsign'] ?? map['callsign'] ?? '')
          .toString()
          .toUpperCase();
      if (cs != target) continue;
      final typeRaw = map['StationType'] ?? map['stationType'];
      final typeStr = '$typeRaw'.toLowerCase();
      final typeIndex = typeRaw is int ? typeRaw : int.tryParse(typeStr);
      if (typeIndex == 1 || typeStr == 'aprs') return true;
    }
    return false;
  }

  /// Opens the add-contact dialog pre-filled with [station]'s callsign as a new
  /// APRS contact and persists it to the address book (device 0 `Stations`).
  Future<void> _addStationContact(_StationMarkerData station) async {
    final result = await showStationDialog(
      context,
      existing: StationInfo(
        callsign: station.callsign,
        stationType: StationType.aprs,
      ),
    );
    if (result == null || !mounted) return;

    final stations = <StationInfo>[];
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          stations.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          stations.add(StationInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    stations.removeWhere(
      (s) =>
          s.callsign == result.callsign && s.stationType == result.stationType,
    );
    stations.add(result);
    _broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  /// Switches to the APRS tab and asks it to start a message to [station]. The
  /// APRS tab opens a Messenger conversation (if in Messenger mode) or pre-fills
  /// the destination in the classic feed. The message request is dispatched
  /// after a frame so the APRS tab is built and subscribed when it arrives.
  void _messageStation(_StationMarkerData station) {
    final callsign = station.callsign;
    _broker.dispatch(
      deviceId: 0,
      name: 'RequestSelectTab',
      data: 'APRS',
      store: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _broker.dispatch(
        deviceId: 0,
        name: 'AprsMessageStation',
        data: callsign,
        store: false,
      );
    });
  }

  /// Centers the map on [station], zooming in enough to separate stations that
  /// were overlapping at the previous zoom level.
  void _centerOnStation(_StationMarkerData station) {
    final currentZoom = _mapController.camera.zoom;
    final targetZoom = math.max(currentZoom, 16.0);
    _mapController.move(station.position, targetZoom);
  }

  /// Builds an APRS symbol marker: the station's symbol drawn inside a small
  /// rounded chip (theme-aware background) sitting on top of a coloured spike
  /// whose pointed tip marks the exact position. The [spikeColor] carries the
  /// station category (blue = self, red = others, orange = voice/BSS).
  Widget _buildAprsSymbolMarker({
    required String table,
    required String code,
    required double size,
    required double spikeHeight,
    required Color spikeColor,
    required Color chipBg,
    required Color symbolColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: chipBg,
            shape: BoxShape.circle,
            border: Border.all(color: spikeColor, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: aprsSymbolWidgetFor(
              table,
              code,
              size: size * 0.66,
              color: symbolColor,
              haloColor: chipBg,
            ),
          ),
        ),
        CustomPaint(
          size: Size(size * 0.5, spikeHeight),
          painter: _MarkerSpikePainter(spikeColor),
        ),
      ],
    );
  }

  /// Builds the track polylines for stations when "Show Tracks" is enabled.
  List<Polyline> _buildTracks() {
    final polylines = <Polyline>[];
    final contactCallsigns =
        _showContactsOnly ? _getContactCallsigns() : null;

    void addTrack(_StationMarkerData s, Color color) {
      if (s.track.length < 2) return;
      if (!_passesTimeFilter(s.time)) return;
      if (contactCallsigns != null &&
          !s.isSelf &&
          !contactCallsigns.contains(s.callsign.toUpperCase())) {
        return;
      }
      polylines.add(
        Polyline(
          points: List<LatLng>.from(s.track),
          color: color,
          strokeWidth: 2,
        ),
      );
    }

    for (final station in _aprsStations.values) {
      if (station.fromAprsIs && !_showAprsIs) continue;
      addTrack(station, station.isSelf ? Colors.blue : Colors.red);
    }
    for (final station in _voiceStations.values) {
      addTrack(station, Colors.orange);
    }

    return polylines;
  }

  // ---------------------------------------------------------------------------
  // Cache Area selection & download
  // ---------------------------------------------------------------------------

  /// Finishes the rectangle selection and shows a confirmation dialog before
  /// downloading tiles for the selected region.
  void _finishCacheAreaSelection() {
    final start = _cacheSelectionStart;
    final end = _cacheSelectionEnd;
    if (start == null || end == null) {
      setState(() => _isSelectingCacheArea = false);
      return;
    }

    final sw = LatLng(
      math.min(start.latitude, end.latitude),
      math.min(start.longitude, end.longitude),
    );
    final ne = LatLng(
      math.max(start.latitude, end.latitude),
      math.max(start.longitude, end.longitude),
    );

    final currentZoom = _mapController.camera.zoom.floor();
    final maxZoom = (currentZoom + 2).clamp(0, 18);
    final tileCount = countTilesInBounds(sw, ne, currentZoom, maxZoom);

    setState(() => _isSelectingCacheArea = false);

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).mapCacheTitle),
        content: Text(
          AppLocalizations.of(ctx).mapCachePrompt(
            tileCount,
            currentZoom,
            maxZoom,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx).settingsDownload),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        _downloadCacheArea(sw, ne, currentZoom, maxZoom);
      }
    });
  }

  /// Shows a progress dialog while downloading tiles for the selected region.
  void _downloadCacheArea(LatLng sw, LatLng ne, int minZoom, int maxZoom) {
    final progressNotifier = ValueNotifier<(int, int)>((0, 0));
    final cancelNotifier = ValueNotifier<bool>(false);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(AppLocalizations.of(ctx).mapDownloadingTitle),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progressNotifier,
            builder: (_, value, child) {
              final (done, total) = value;
              final pct = total > 0 ? done / total : 0.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: pct),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.of(ctx).mapTilesProgress(done, total)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelNotifier.value = true;
                Navigator.of(ctx).pop();
              },
              child: Text(AppLocalizations.of(ctx).commonCancel),
            ),
          ],
        ),
      ),
    );

    downloadTilesInBounds(
      sw: sw,
      ne: ne,
      minZoom: minZoom,
      maxZoom: maxZoom,
      onProgress: (done, total) => progressNotifier.value = (done, total),
      cancel: cancelNotifier,
    ).then((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // dismiss progress dialog
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final scheme = Theme.of(context).colorScheme;
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
                  // In offline mode no tiles are fetched from the internet, so
                  // render a neutral background behind the markers/tracks.
                  backgroundColor: _isOfflineMode
                      ? scheme.surfaceContainerHighest
                      : scheme.secondaryContainer,
                  // Keep the map permanently north-up: allow all touch gestures
                  // except rotation (e.g. two-finger twist on a touch screen).
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onPositionChanged: _onMapPositionChanged,
                ),
                children: [
                  // Map tiles. Online: fetched from OpenStreetMap and cached to
                  // disk. Offline: only previously-cached tiles are shown (no
                  // network access). Keyed by offline state so toggling fully
                  // resets the layer and disposes the old provider. In dark
                  // mode the light tiles are run through an inverting filter so
                  // the map matches the theme.
                  Builder(
                    builder: (context) {
                      final Widget tiles = TileLayer(
                        key: ValueKey(_isOfflineMode),
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.htcommander.app',
                        tileProvider: _tileProvider,
                      );
                      if (Theme.of(context).brightness == Brightness.dark) {
                        return ColorFiltered(
                          colorFilter: _darkMapTileFilter,
                          child: tiles,
                        );
                      }
                      return tiles;
                    },
                  ),
                  if (tracks.isNotEmpty) PolylineLayer(polylines: tracks),
                  if (stationMarkers.isNotEmpty)
                    MarkerLayer(markers: stationMarkers),
                  if (_showAirplanes && _airplanes.isNotEmpty)
                    MarkerLayer(markers: _buildAirplaneMarkers()),
                  if (_showSatellites && _satelliteSupport) ...[
                    if (_satellites.isNotEmpty)
                      CircleLayer(circles: _buildSatelliteFootprints()),
                    if (_satGroundTrack.length > 1)
                      PolylineLayer(polylines: _buildSatelliteTrack()),
                    if (_satellites.isNotEmpty)
                      MarkerLayer(markers: _buildSatelliteMarkers()),
                  ],
                  // Required OpenStreetMap licence attribution (OSM Tile Usage
                  // Policy §2). Kept always-visible in the bottom-right corner.
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
                          child: Builder(
                            builder: (context) {
                              final dark = Theme.of(context).brightness ==
                                  Brightness.dark;
                              return Text(
                                '© OpenStreetMap contributors',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: dark ? Colors.white : Colors.black87,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 2,
                                      color: dark ? Colors.black : Colors.white,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
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
              // Rectangle selection overlay for cache area
              if (_isSelectingCacheArea) ...[
                // Draw the selection rectangle on the map
                if (_cacheSelectionStart != null &&
                    _cacheSelectionEnd != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RectSelectionPainter(
                          start: _mapController.camera
                              .latLngToScreenOffset(_cacheSelectionStart!),
                          end: _mapController.camera
                              .latLngToScreenOffset(_cacheSelectionEnd!),
                        ),
                      ),
                    ),
                  ),
                // Gesture layer to capture drag
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      final latlng = _mapController.camera
                          .screenOffsetToLatLng(details.localPosition);
                      setState(() {
                        _cacheSelectionStart = latlng;
                        _cacheSelectionEnd = latlng;
                      });
                    },
                    onPanUpdate: (details) {
                      final latlng = _mapController.camera
                          .screenOffsetToLatLng(details.localPosition);
                      setState(() => _cacheSelectionEnd = latlng);
                    },
                    onPanEnd: (_) => _finishCacheAreaSelection(),
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                // Instruction banner
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context).mapDragToSelect,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => setState(
                              () => _isSelectingCacheArea = false,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 220;
          return Row(
            children: [
              // Map label
              Text(
                _isOfflineMode
                    ? AppLocalizations.of(context).mapOfflineMap
                    : AppLocalizations.of(context).tabMap,
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
                    child: Text(AppLocalizations.of(context).mapCenterGps),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      colorBlendMode: BlendMode.srcIn,
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

/// Paints a semi-transparent blue rectangle between two screen points to
/// visualise the cache-area selection.
class _RectSelectionPainter extends CustomPainter {
  _RectSelectionPainter({required this.start, required this.end});

  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(
      start,
      end,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RectSelectionPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}

/// Draws the small downward-pointing spike beneath an APRS symbol chip. The
/// tip sits at the bottom-center of the paint box, which is aligned to the
/// station's exact position on the map.
class _MarkerSpikePainter extends CustomPainter {
  _MarkerSpikePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final topHalf = w * 0.30;
    final path = ui.Path()
      ..moveTo(w / 2 - topHalf, 0)
      ..lineTo(w / 2 + topHalf, 0)
      ..lineTo(w / 2, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(color, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MarkerSpikePainter oldDelegate) =>
      color != oldDelegate.color;
}

