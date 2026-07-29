/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:satellite_observer/satellite_observer.dart' as so;

import '../gps/gps_data.dart';
import '../models/radio_models.dart';
import '../satellite/satellite_models.dart';
import '../satellite/tle_repository.dart';
import '../satellite/transponder_repository.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Data Broker handler that tracks amateur satellites.
///
/// It joins the cached TLEs with the FM transponder catalog to build the list
/// of satellites the radio can work, then every second computes each bird's
/// sub-point and look-angle from the observer and publishes them for the
/// satellite tab and map overlay. It also predicts upcoming passes for the
/// selected satellite.
///
/// Events published on device 0 (broadcast only):
///  - `SatelliteCatalog`      → `List<SatelliteInfo>` of workable FM birds.
///  - `SatellitePositions`    → `List<SatellitePosition>` (all catalog sats).
///  - `SatelliteNextPasses`   → `List<SatellitePass>`, next pass per sat (AOS-sorted).
///  - `SatellitePasses`       → `List<SatellitePass>` for the selected sat.
///  - `SatelliteGroundTrack`  → `List<List<double>>` of `[lat, lon]` for the selected sat.
///  - `SatelliteObserverKnown`→ `bool`, whether an observer location is set.
///
/// Events consumed on device 0:
///  - `SelectSatellite`   → NORAD id (`int`) of the sat to predict passes for.
///  - `SatelliteRefresh`  → any value; triggers a TLE + transponder refresh.
///  - `SatObserverLat` / `SatObserverLon` / `SatObserverAltM` → manual observer.
///  - `SatMinElevationDeg`→ minimum pass elevation (degrees).
class SatelliteHandler {
  static const int _settingsDeviceId = 0;
  static const int _gpsDeviceId = 1;

  static const Duration _tickInterval = Duration(seconds: 1);

  final DataBrokerClient _broker = DataBrokerClient();
  final TleRepository _tleRepo = TleRepository();
  final TransponderRepository _transponderRepo = TransponderRepository();

  /// Workable FM satellites, keyed by NORAD id.
  final Map<int, SatelliteInfo> _catalog = {};

  /// One reusable propagator/observer per satellite (rebuilt on location or
  /// catalog change; construction runs SGP4 init once, so it is cached).
  final Map<int, so.SatelliteObserver> _observers = {};

  Timer? _tick;
  bool _disposed = false;
  bool _enabled = false;
  bool _loaded = false;

  so.Observer? _observer;
  double? _lastObsLat;
  double? _lastObsLon;
  double _minElevationDeg = 10;
  int? _selectedNoradId;

  // Latest valid GPS fix reported by each connected radio (device id > 0).
  final Map<int, RadioPosition> _radioFixes = {};

  // Last-published state, re-emitted on `SatelliteResync` so a tab opened after
  // startup (these events are broadcast-only) gets the current snapshot.
  List<SatelliteInfo> _lastCatalog = const [];
  List<SatellitePass> _lastNextPasses = const [];
  List<SatellitePass> _lastSelectedPasses = const [];
  List<List<double>> _lastGroundTrack = const [];
  bool _lastObserverKnown = false;

  // Advances every tick; used to recompute the ground track periodically.
  int _tickCount = 0;

  /// Initializes the handler: loads cached/seed data, wires up broker
  /// subscriptions, starts the per-second tracking loop, and kicks off a
  /// background online refresh. Safe to call once at startup.
  Future<void> init() async {
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'SelectSatellite',
      callback: _onSelectSatellite,
    );
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'SatelliteRefresh',
      callback: _onRefreshRequested,
    );
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'SatelliteResync',
      callback: _onResyncRequested,
    );
    _broker.subscribeMultiple(
      deviceId: _settingsDeviceId,
      names: const ['SatObserverLat', 'SatObserverLon', 'SatObserverAltM'],
      callback: _onObserverSettingChanged,
    );
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'SatMinElevationDeg',
      callback: _onMinElevationChanged,
    );
    _broker.subscribe(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      callback: _onGpsDataChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Position',
      callback: _onRadioPositionChanged,
    );
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'SatelliteSupport',
      callback: _onSupportChanged,
    );

    _minElevationDeg =
        (_broker.getValue<num>(_settingsDeviceId, 'SatMinElevationDeg', 10) ??
                10)
            .toDouble();
    _selectedNoradId =
        _broker.getValue<int>(_settingsDeviceId, 'SelectedSatelliteId', null);

    // Satellite tracking is opt-in; do no work (and no network fetch) until the
    // user enables it in the Application settings.
    if ((_broker.getValue<int>(_settingsDeviceId, 'SatelliteSupport', 0) ?? 0) ==
        1) {
      await _enable();
    }
  }

  /// Loads data (once), builds the catalog, starts the per-second tracking loop
  /// and kicks off a background refresh. Called on startup when enabled and
  /// whenever the user turns satellite support on.
  Future<void> _enable() async {
    if (_enabled) return;
    _enabled = true;
    if (!_loaded) {
      await _tleRepo.load();
      await _transponderRepo.load();
      _loaded = true;
    }
    if (_disposed || !_enabled) return;
    _rebuildCatalog();
    _resolveObserver();
    _rebuildObservers();
    _publishCatalog();
    _recomputeAllNextPasses();
    _recomputePasses();
    _startTicking();

    // Refresh from the network in the background; repositories self-gate to
    // respect the upstream rate limits, so this is cheap when data is fresh.
    unawaited(_refresh());
  }

  /// Stops tracking and clears all published state so any open UI empties.
  void _disable() {
    _enabled = false;
    _tick?.cancel();
    _tick = null;
    _catalog.clear();
    _observers.clear();
    _publishCatalog();
    _recomputeAllNextPasses();
    _recomputePasses();
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatellitePositions',
      data: const <SatellitePosition>[],
      store: false,
    );
  }

  void _onSupportChanged(int deviceId, String name, Object? data) {
    final on = (data is num ? data.toInt() : 0) == 1;
    if (on == _enabled) return;
    if (on) {
      unawaited(_enable());
    } else {
      _disable();
    }
  }

  // --- Broker event handlers ------------------------------------------------

  void _onSelectSatellite(int deviceId, String name, Object? data) {
    final id = data is int ? data : (data is num ? data.toInt() : null);
    if (id == _selectedNoradId) return;
    _selectedNoradId = id;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SelectedSatelliteId',
      data: id,
      store: true,
    );
    _recomputePasses();
  }

  void _onRefreshRequested(int deviceId, String name, Object? data) {
    unawaited(_refresh());
  }

  void _onResyncRequested(int deviceId, String name, Object? data) {
    // Re-emit the cached snapshot for a UI that subscribed after startup.
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteCatalog',
      data: _lastCatalog,
      store: false,
    );
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteNextPasses',
      data: _lastNextPasses,
      store: false,
    );
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatellitePasses',
      data: _lastSelectedPasses,
      store: false,
    );
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteGroundTrack',
      data: _lastGroundTrack,
      store: false,
    );
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteObserverKnown',
      data: _lastObserverKnown,
      store: false,
    );
  }

  void _onObserverSettingChanged(int deviceId, String name, Object? data) {
    _applyObserverIfChanged();
  }

  void _onMinElevationChanged(int deviceId, String name, Object? data) {
    final v = data is num ? data.toDouble() : null;
    if (v == null || v == _minElevationDeg) return;
    _minElevationDeg = v;
    _recomputeAllNextPasses();
    _recomputePasses();
  }

  void _onGpsDataChanged(int deviceId, String name, Object? data) {
    // A manual observer location, if set, always wins over the live GPS fix.
    if (_hasManualObserver()) return;
    _applyObserverIfChanged();
  }

  void _onRadioPositionChanged(int deviceId, String name, Object? data) {
    if (deviceId <= 0) return; // Ignore device 0 (settings) and invalid ids.
    RadioPosition? pos;
    if (data is RadioPosition) {
      pos = data;
    } else if (data is Map) {
      pos = RadioPosition.fromJson(Map<String, dynamic>.from(data));
    }
    if (pos != null &&
        (pos.locked || pos.latitude != 0 || pos.longitude != 0)) {
      _radioFixes[deviceId] = pos;
    } else {
      _radioFixes.remove(deviceId);
    }
    // Priority (manual > serial GPS > radio GPS) is resolved in
    // _resolveObserver; the throttle there absorbs the ~1 Hz updates.
    if (_enabled) _applyObserverIfChanged();
  }

  // --- Data building --------------------------------------------------------

  void _rebuildCatalog() {
    _catalog.clear();
    final transponders = _transponderRepo.byNorad;
    for (final tle in _tleRepo.tles) {
      final transponder = transponders[tle.noradId];
      if (transponder == null || !transponder.isWorkableFm) continue;
      _catalog[tle.noradId] =
          SatelliteInfo(tle: tle, transponder: transponder);
    }
  }

  void _rebuildObservers() {
    _observers.clear();
    final observer = _observer;
    if (observer == null) return;
    for (final info in _catalog.values) {
      try {
        final elements = so.GpElements.fromTle(
          info.tle.line1,
          info.tle.line2,
          name: info.tle.name,
        );
        _observers[info.noradId] = so.SatelliteObserver(
          elements: elements,
          observer: observer,
        );
      } catch (e) {
        debugPrint('SatelliteHandler: bad elements for ${info.name}: $e');
      }
    }
  }

  bool _hasManualObserver() {
    final lat = _broker.getValue<num>(_settingsDeviceId, 'SatObserverLat', null);
    final lon = _broker.getValue<num>(_settingsDeviceId, 'SatObserverLon', null);
    return lat != null && lon != null && (lat != 0 || lon != 0);
  }

  /// Recomputes the observer and, only when it moved meaningfully (or appeared
  /// or disappeared), rebuilds propagators and pass predictions.
  void _applyObserverIfChanged() {
    if (!_resolveObserver()) return;
    _rebuildObservers();
    _recomputeAllNextPasses();
    _recomputePasses();
  }

  /// Resolves the observer from a manual setting or the latest GPS fix. Returns
  /// true when the effective observer changed enough to warrant recomputation
  /// (sub-kilometre GPS jitter is ignored).
  bool _resolveObserver() {
    double? lat;
    double? lon;
    double altM = 0;
    final mLat =
        _broker.getValue<num>(_settingsDeviceId, 'SatObserverLat', null);
    final mLon =
        _broker.getValue<num>(_settingsDeviceId, 'SatObserverLon', null);
    if (mLat != null && mLon != null && (mLat != 0 || mLon != 0)) {
      lat = mLat.toDouble();
      lon = mLon.toDouble();
      altM = (_broker.getValue<num>(_settingsDeviceId, 'SatObserverAltM', 0) ?? 0)
          .toDouble();
    } else {
      final gps = _broker.getValue<GpsData>(_gpsDeviceId, 'GpsData', null);
      if (gps != null &&
          gps.isFixed &&
          (gps.latitude != 0 || gps.longitude != 0)) {
        lat = gps.latitude;
        lon = gps.longitude;
        altM = gps.altitude;
      } else {
        // Last automatic fallback: any radio reporting a GPS fix.
        for (final pos in _radioFixes.values) {
          if (pos.locked || pos.latitude != 0 || pos.longitude != 0) {
            lat = pos.latitude;
            lon = pos.longitude;
            altM = pos.altitude;
            break;
          }
        }
      }
    }

    if (lat == null || lon == null) {
      final had = _observer != null;
      _observer = null;
      _lastObsLat = null;
      _lastObsLon = null;
      if (had) _publishObserverKnown(false);
      return had;
    }

    if (_observer != null &&
        _lastObsLat != null &&
        _lastObsLon != null &&
        (lat - _lastObsLat!).abs() < 0.01 &&
        (lon - _lastObsLon!).abs() < 0.01) {
      return false;
    }

    final obs = _makeObserver(lat, lon, altM);
    if (obs == null) return false;
    _observer = obs;
    _lastObsLat = lat;
    _lastObsLon = lon;
    _publishObserverKnown(true);
    return true;
  }

  so.Observer? _makeObserver(double lat, double lon, double altM) {
    try {
      return so.Observer(
        latitudeDeg: lat,
        longitudeDeg: lon,
        altitudeMeters: altM,
      );
    } catch (e) {
      debugPrint('SatelliteHandler: invalid observer $lat,$lon: $e');
      return null;
    }
  }

  // --- Tracking loop --------------------------------------------------------

  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(_tickInterval, (_) => _computeAndPublishPositions());
    _computeAndPublishPositions();
  }

  void _computeAndPublishPositions() {
    if (_disposed || _observers.isEmpty) return;
    final now = DateTime.now().toUtc();
    final positions = <SatellitePosition>[];
    for (final entry in _observers.entries) {
      final info = _catalog[entry.key];
      if (info == null) continue;
      try {
        final sub = entry.value.subPointAt(now);
        final look = entry.value.lookAngleAt(now);
        positions.add(
          SatellitePosition(
            noradId: info.noradId,
            name: info.name,
            latitudeDeg: sub.latitudeDeg,
            longitudeDeg: sub.longitudeDeg,
            altitudeKm: sub.altitudeKm,
            azimuthDeg: look.azimuthDeg,
            elevationDeg: look.elevationDeg,
            rangeKm: look.rangeKm,
            rangeRateKmS: look.rangeRateKmS,
            utc: now,
          ),
        );
      } catch (e) {
        // Skip a satellite whose propagation fails this tick.
      }
    }
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatellitePositions',
      data: positions,
      store: false,
    );

    // Refresh the selected satellite's ground track roughly twice a minute.
    if (_tickCount++ % 30 == 0) _recomputeGroundTrack();
  }

  void _recomputePasses() {
    final id = _selectedNoradId;
    final observer = _observers[id];
    final info = id == null ? null : _catalog[id];
    if (id == null || observer == null || info == null) {
      _broker.dispatch(
        deviceId: _settingsDeviceId,
        name: 'SatellitePasses',
        data: const <SatellitePass>[],
        store: false,
      );
      return;
    }

    final now = DateTime.now().toUtc();
    final passes = <SatellitePass>[];
    try {
      final found = observer.passes(
        from: now,
        to: now.add(const Duration(hours: 48)),
        minElevationDeg: _minElevationDeg,
      );
      for (final p in found) {
        passes.add(
          SatellitePass(
            noradId: info.noradId,
            name: info.name,
            aos: p.rise.utc,
            los: p.set.utc,
            maxElevationDeg: p.peakElevationDeg,
            aosAzimuthDeg: p.rise.lookAngle.azimuthDeg,
            losAzimuthDeg: p.set.lookAngle.azimuthDeg,
          ),
        );
      }
    } catch (e) {
      debugPrint('SatelliteHandler: pass prediction failed for ${info.name}: $e');
    }

    _lastSelectedPasses = passes;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatellitePasses',
      data: passes,
      store: false,
    );
    _recomputeGroundTrack();
  }

  /// Samples the selected satellite's sub-point over roughly one orbit centred
  /// on now and publishes it as a list of `[lat, lon]` for the map ground
  /// track. Empty when nothing is selected or no observer is set.
  void _recomputeGroundTrack() {
    final id = _selectedNoradId;
    final observer = _observers[id];
    if (id == null || observer == null) {
      _lastGroundTrack = const [];
      _broker.dispatch(
        deviceId: _settingsDeviceId,
        name: 'SatelliteGroundTrack',
        data: const <List<double>>[],
        store: false,
      );
      return;
    }

    final now = DateTime.now().toUtc();
    final track = <List<double>>[];
    for (var m = -50; m <= 50; m++) {
      final t = now.add(Duration(minutes: m));
      try {
        final sub = observer.subPointAt(t);
        track.add([sub.latitudeDeg, sub.longitudeDeg]);
      } catch (_) {
        // Skip a sample whose propagation fails.
      }
    }

    _lastGroundTrack = track;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteGroundTrack',
      data: track,
      store: false,
    );
  }

  /// Computes the single next pass for every catalog satellite and publishes
  /// them AOS-sorted for the satellite list. Runs only on observer / catalog /
  /// min-elevation changes, never per tick.
  void _recomputeAllNextPasses() {
    final now = DateTime.now().toUtc();
    final result = <SatellitePass>[];
    for (final entry in _observers.entries) {
      final info = _catalog[entry.key];
      if (info == null) continue;
      try {
        final p = entry.value.nextPass(
          after: now,
          minElevationDeg: _minElevationDeg,
        );
        if (p == null) continue;
        result.add(
          SatellitePass(
            noradId: info.noradId,
            name: info.name,
            aos: p.rise.utc,
            los: p.set.utc,
            maxElevationDeg: p.peakElevationDeg,
            aosAzimuthDeg: p.rise.lookAngle.azimuthDeg,
            losAzimuthDeg: p.set.lookAngle.azimuthDeg,
          ),
        );
      } catch (e) {
        // Skip a satellite whose pass search fails.
      }
    }
    result.sort((a, b) => a.aos.compareTo(b.aos));
    _lastNextPasses = result;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteNextPasses',
      data: result,
      store: false,
    );
  }

  void _publishCatalog() {
    final list = _catalog.values.toList(growable: false);
    _lastCatalog = list;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteCatalog',
      data: list,
      store: false,
    );
  }

  void _publishObserverKnown(bool known) {
    _lastObserverKnown = known;
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'SatelliteObserverKnown',
      data: known,
      store: false,
    );
  }

  Future<void> _refresh() async {
    if (!_enabled) return;
    final tleChanged = await _tleRepo.refresh();
    final transpondersChanged = await _transponderRepo.refresh();
    if (!tleChanged && !transpondersChanged) return;
    _rebuildCatalog();
    _rebuildObservers();
    _publishCatalog();
    _recomputeAllNextPasses();
    _recomputePasses();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tick?.cancel();
    _tick = null;
    _broker.dispose();
  }
}
