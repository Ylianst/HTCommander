/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../gps/gps_data.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';

enum _Source { none, manual, phone }

/// Publishes a manually configured location, or the device's own location
/// service, as a GPS fix.
///
/// When the user selects "Set manually" in the License tab (persisted on
/// device 0 as `ManualLocationEnabled` with `ManualLatitude`/`ManualLongitude`),
/// this handler injects a synthetic [GpsData] on device 1 under key `GpsData`,
/// exactly like the serial GPS handler. Every existing consumer of that fix
/// (the radio position beacon, APRS-IS range filter and satellite tracker)
/// therefore uses the manual location with no further changes.
///
/// The user can instead opt in to the device's location service
/// (`PhoneLocationEnabled`); fixes from the OS (or browser) are published the
/// same way. The OS permission is requested by the settings dialog; this
/// handler only checks it and never prompts.
///
/// The fix is re-emitted on a slow timer so a radio that connects after the
/// location was set still receives (and beacons) it.
class LocationHandler {
  static const int _settingsDeviceId = 0;
  static const int _gpsDeviceId = 1;

  /// How often the current fix is re-published. The radio applies its own
  /// SmartBeaconing throttle on top of this, so a slow cadence is enough to
  /// keep a late-connecting radio and the APRS-IS filter up to date.
  static const Duration _republishInterval = Duration(seconds: 15);

  static const double _metersPerSecondToKnots = 1.943844;

  /// Whether the device location option is available. Disabled on the
  /// host-served web build because its settings are shared with the host.
  static bool get deviceGpsSupported => kIsWeb
      ? !HostBridge.isHosted
      : defaultTargetPlatform != TargetPlatform.fuchsia;

  /// Whether the OS has a settings page [Geolocator.openAppSettings] can open.
  static bool get canOpenLocationSettings =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Linux (GeoClue) and some browsers report [LocationPermission.unableToDetermine];
  /// treat that as usable and let the position stream surface any failure.
  static bool isPermissionUsable(LocationPermission p) =>
      p == LocationPermission.whileInUse ||
      p == LocationPermission.always ||
      p == LocationPermission.unableToDetermine;

  final DataBrokerClient _broker = DataBrokerClient();
  Timer? _timer;
  _Source _source = _Source.none;
  StreamSubscription<Position>? _phoneSub;
  GpsData? _lastPhoneFix;

  /// Incremented whenever the phone source is started or stopped so a stale
  /// async permission check can tell it was superseded.
  int _phoneToken = 0;

  void init() {
    _broker.subscribeMultiple(
      deviceId: _settingsDeviceId,
      names: const [
        'ManualLocationEnabled',
        'ManualLatitude',
        'ManualLongitude',
        'PhoneLocationEnabled',
      ],
      callback: _onSettingChanged,
    );
    _apply();
  }

  void _onSettingChanged(int deviceId, String name, Object? value) {
    _apply();
  }

  bool _isOn(String name) =>
      (_broker.getValue<int>(_settingsDeviceId, name, 0) ?? 0) == 1;

  _Source get _desiredSource {
    if (_isOn('ManualLocationEnabled')) return _Source.manual;
    if (deviceGpsSupported && _isOn('PhoneLocationEnabled')) {
      return _Source.phone;
    }
    return _Source.none;
  }

  void _apply() {
    final desired = _desiredSource;
    final previous = _source;
    _source = desired;

    if (desired != _Source.phone) _stopPhone();

    switch (desired) {
      case _Source.manual:
        _publishManual();
        _timer ??= Timer.periodic(_republishInterval, (_) => _republish());
        _setStatus('Manual');
      case _Source.phone:
        if (previous != _Source.phone) {
          // Drop any manual fix until the phone reports its first position.
          if (previous == _Source.manual) _clearFix();
          _startPhone();
        }
        _timer ??= Timer.periodic(_republishInterval, (_) => _republish());
      case _Source.none:
        if (previous != _Source.none) {
          // Switched back to GPS: stop injecting and clear the stale fix so
          // live GPS (serial/radio) takes over cleanly.
          _timer?.cancel();
          _timer = null;
          _clearFix();
        }
    }
  }

  void _republish() {
    switch (_source) {
      case _Source.manual:
        _publishManual();
      case _Source.phone:
        final fix = _lastPhoneFix;
        if (fix != null) _publish(fix);
      case _Source.none:
        break;
    }
  }

  void _publishManual() {
    final lat =
        _broker.getValue<double>(_settingsDeviceId, 'ManualLatitude', 0.0) ??
        0.0;
    final lon =
        _broker.getValue<double>(_settingsDeviceId, 'ManualLongitude', 0.0) ??
        0.0;
    _publish(
      GpsData(
        latitude: lat,
        longitude: lon,
        fixQuality: 1,
        isFixed: true,
        gpsTime: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _startPhone() async {
    final token = ++_phoneToken;
    _setStatus('Connecting');
    try {
      final permission = await Geolocator.checkPermission();
      if (token != _phoneToken) return;
      if (!isPermissionUsable(permission)) {
        _setStatus('Permission Denied');
        return;
      }
      _phoneSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            _onPhonePosition,
            onError: (Object e) {
              if (token == _phoneToken) _setStatus('Error: $e');
            },
          );
    } catch (e) {
      if (token == _phoneToken) _setStatus('Error: $e');
    }
  }

  void _stopPhone() {
    _phoneToken++;
    _phoneSub?.cancel();
    _phoneSub = null;
    _lastPhoneFix = null;
  }

  void _onPhonePosition(Position p) {
    if (_source != _Source.phone) return;
    if (!p.latitude.isFinite || !p.longitude.isFinite) return;
    final fix = GpsData(
      latitude: p.latitude,
      longitude: p.longitude,
      altitude: p.altitude.isFinite ? p.altitude : 0.0,
      speed: p.speed.isFinite && p.speed > 0
          ? p.speed * _metersPerSecondToKnots
          : 0.0,
      heading: p.heading.isFinite && p.heading >= 0 ? p.heading % 360 : 0.0,
      fixQuality: 1,
      isFixed: true,
      gpsTime: p.timestamp.toUtc(),
    );
    _lastPhoneFix = fix;
    _publish(fix);
    _setStatus('Device Location');
  }

  void _publish(GpsData gps) {
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      data: gps,
      store: true,
    );
  }

  void _clearFix() {
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      data: null,
      store: true,
    );
  }

  void _setStatus(String status) {
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsStatus',
      data: status,
      store: true,
    );
  }

  void dispose() {
    _stopPhone();
    _timer?.cancel();
    _timer = null;
  }
}
