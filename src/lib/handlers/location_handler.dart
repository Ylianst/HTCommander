/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import '../gps/gps_data.dart';
import '../services/data_broker_client.dart';

/// Publishes a manually configured location as a GPS fix.
///
/// When the user selects "Set manually" in the License tab (persisted on
/// device 0 as `ManualLocationEnabled` with `ManualLatitude`/`ManualLongitude`),
/// this handler injects a synthetic [GpsData] on device 1 under key `GpsData`,
/// exactly like the serial GPS handler. Every existing consumer of that fix
/// (the radio position beacon, APRS-IS range filter and satellite tracker)
/// therefore uses the manual location with no further changes.
///
/// The fix is re-emitted on a slow timer so a radio that connects after the
/// location was set still receives (and beacons) it. Works on every platform.
class LocationHandler {
  static const int _settingsDeviceId = 0;
  static const int _gpsDeviceId = 1;

  /// How often the manual fix is re-published. The radio applies its own
  /// SmartBeaconing throttle on top of this, so a slow cadence is enough to
  /// keep a late-connecting radio and the APRS-IS filter up to date.
  static const Duration _republishInterval = Duration(seconds: 15);

  final DataBrokerClient _broker = DataBrokerClient();
  Timer? _timer;
  bool _active = false;

  void init() {
    _broker.subscribeMultiple(
      deviceId: _settingsDeviceId,
      names: const [
        'ManualLocationEnabled',
        'ManualLatitude',
        'ManualLongitude',
      ],
      callback: _onSettingChanged,
    );
    _apply();
  }

  void _onSettingChanged(int deviceId, String name, Object? value) {
    _apply();
  }

  bool get _enabled =>
      (_broker.getValue<int>(_settingsDeviceId, 'ManualLocationEnabled', 0) ??
          0) ==
      1;

  void _apply() {
    if (_enabled) {
      _active = true;
      _publish();
      _timer ??= Timer.periodic(_republishInterval, (_) => _publish());
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsStatus',
        data: 'Manual',
        store: true,
      );
    } else if (_active) {
      // Was manual, now switched back to GPS: stop injecting and clear the
      // stale manual fix so live GPS (serial/radio) takes over cleanly.
      _active = false;
      _timer?.cancel();
      _timer = null;
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsData',
        data: null,
        store: true,
      );
    }
  }

  void _publish() {
    final lat =
        _broker.getValue<double>(_settingsDeviceId, 'ManualLatitude', 0.0) ??
            0.0;
    final lon =
        _broker.getValue<double>(_settingsDeviceId, 'ManualLongitude', 0.0) ??
            0.0;
    final gps = GpsData(
      latitude: lat,
      longitude: lon,
      fixQuality: 1,
      isFixed: true,
      gpsTime: DateTime.now().toUtc(),
    );
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      data: gps,
      store: true,
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
