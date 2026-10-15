/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';

import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_util.dart';
import '../gps/gps_data.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../radio/utils.dart';
import '../services/data_broker_client.dart';
import 'software_beacon_config.dart';

/// A data handler that periodically transmits the app's own APRS beacon.
///
/// Unlike the radio's built-in beacon, the software beacon is fully controlled
/// by the app: it always uses the global station callsign + SSID, always sends
/// on the "APRS" channel in APRS format (position or status), and is always
/// gated to the Internet (APRS-IS) — in addition to the selected radio — by
/// echoing the frame on the `AprsFrame` event that the APRS-IS manager
/// up-gates.
class SoftwareBeaconHandler {
  static const int _aprsDeviceId = 1;

  /// SmartBeaconing parameters (classic APRS algorithm). Speeds are in knots to
  /// match the speed-over-ground reported in [GpsData].
  static const double _sbLowSpeedKnots = 5.0; // at/below: use the slow rate
  static const double _sbHighSpeedKnots = 60.0; // at/above: use the fast rate
  static const int _sbFastRateSecs = 60; // fastest interval between beacons
  static const double _sbTurnMinDegrees = 28.0; // min turn angle for corner peg
  static const double _sbTurnSlope = 26.0; // corner-peg sensitivity vs. speed
  static const int _sbTurnTimeSecs = 30; // min interval between corner pegs
  static const double _sbMinMoveMetres = 150.0; // distance that forces a beacon

  final DataBrokerClient _broker = DataBrokerClient();

  SoftwareBeaconConfig _config = const SoftwareBeaconConfig();
  Timer? _timer;
  bool _disposed = false;

  // SmartBeaconing state: position/heading/time of the last transmitted beacon.
  DateTime? _lastBeaconTime;
  double? _lastBeaconLat;
  double? _lastBeaconLon;
  double? _lastBeaconHeading;

  SoftwareBeaconConfig get config => _config;

  /// Initializes the handler: subscribes to config changes and loads any
  /// persisted configuration. Safe to call once at startup.
  void init() {
    _broker.subscribe(
      deviceId: 0,
      name: 'SoftwareBeaconConfig',
      callback: _onConfigChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SendSoftwareBeacon',
      callback: _onSendRequested,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'GpsData',
      callback: _onGpsChanged,
    );

    _loadConfig(_broker.getValueDynamic(0, 'SoftwareBeaconConfig', null));
    _restartTimer();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _broker.dispose();
  }

  void _onConfigChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _loadConfig(data);
    _restartTimer();
    // Give the user immediate feedback when they enable/update the beacon.
    if (_config.enabled) _sendBeacon();
  }

  /// Sends a one-time beacon on user request and reports the outcome on the
  /// `SoftwareBeaconSent` event (data: bool) so the UI can give feedback.
  void _onSendRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final sent = _sendBeacon();
    _broker.dispatch(
      deviceId: 0,
      name: 'SoftwareBeaconSent',
      data: sent,
      store: false,
    );
  }

  /// SmartBeaconing: when enabled, a new GPS fix may trigger an early beacon
  /// before the configured interval elapses if the station has moved enough.
  void _onGpsChanged(int deviceId, String name, Object? data) {
    if (_disposed || !_config.enabled) return;
    if (!_config.smartBeacon || !_config.includeLocation) return;
    final gps = _currentFix();
    if (gps == null) return;
    if (_shouldSmartBeacon(gps, DateTime.now())) _sendBeacon();
  }

  void _loadConfig(Object? data) {
    if (data is SoftwareBeaconConfig) {
      _config = data;
      return;
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          _config = SoftwareBeaconConfig.fromJson(decoded);
          return;
        }
      } catch (_) {
        // Ignore malformed configuration.
      }
    }
    if (data is Map<String, dynamic>) {
      _config = SoftwareBeaconConfig.fromJson(data);
      return;
    }
    _config = const SoftwareBeaconConfig();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_config.enabled) return;
    _timer = Timer.periodic(
      Duration(seconds: _config.intervalSeconds),
      (_) => _sendBeacon(),
    );
  }

  /// Builds and transmits one beacon over the selected radio (if any) and, via
  /// the `AprsFrame` echo, to APRS-IS. Returns false when nothing was sent.
  bool _sendBeacon() {
    if (_disposed || !_config.isActive) return false;

    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    if (callsign.isEmpty) return false;
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final srcCallsign = stationId > 0 ? '$callsign-$stationId' : callsign;

    final destAddr = AX25Address.parse('APRS');
    final srcAddr = AX25Address.parse(srcCallsign);
    if (destAddr == null || srcAddr == null) return false;

    final info = _buildInformationField();
    if (info == null) return false;

    final now = DateTime.now();
    final packet = AX25Packet(
      addresses: [destAddr, srcAddr],
      dataStr: info,
      type: FrameType.uFrameUi,
      command: true,
      time: now,
    );
    packet.pid = 240;
    packet.incoming = false;
    packet.sent = false;
    packet.authState = AuthState.none;
    packet.channelName = 'APRS';

    // Resolve the radio to transmit over: the configured preferred radio when
    // it is connected and has an APRS channel, otherwise the first connected
    // radio that does. When none qualifies the beacon is Internet-only.
    final txRadioId = _resolveTxRadio();
    if (txRadioId > 0) {
      final channelId = _getAprsChannelId(txRadioId);
      if (channelId >= 0) {
        packet.channelId = channelId;
        _broker.dispatch(
          deviceId: txRadioId,
          name: 'TransmitDataFrame',
          data: TransmitDataFrameData(
            packet: packet,
            channelId: channelId,
            regionId: -1,
          ),
          store: false,
        );
      }
    }

    // Echo the outgoing beacon so it shows in the APRS tab and is up-gated to
    // APRS-IS by the APRS-IS manager.
    final aprsPacket = AprsPacket.parse(packet);
    if (aprsPacket != null) {
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(aprsPacket, packet, null),
        store: false,
      );
    }

    _recordBeaconState(now);
    // Measure the configured interval from this beacon so an early SmartBeacon
    // push does not cause an extra beacon right after on the periodic tick.
    _restartTimer();
    return true;
  }

  /// Remembers the time, position and heading of the beacon just sent so the
  /// SmartBeaconing logic can measure movement since then.
  void _recordBeaconState(DateTime now) {
    _lastBeaconTime = now;
    if (_config.includeLocation) {
      final gps = _currentFix();
      if (gps != null) {
        _lastBeaconLat = gps.latitude;
        _lastBeaconLon = gps.longitude;
        _lastBeaconHeading = gps.heading;
        return;
      }
    }
    _lastBeaconLat = null;
    _lastBeaconLon = null;
    _lastBeaconHeading = null;
  }

  /// Classic APRS SmartBeaconing decision: beacon early when moving fast, on a
  /// sharp turn (corner pegging) or after moving a significant distance. The
  /// configured interval remains the slowest (maximum) beacon rate.
  bool _shouldSmartBeacon(GpsData gps, DateTime now) {
    // No reference beacon yet, or the last beacon had no position fix: let the
    // periodic timer send the next one and establish a reference.
    if (_lastBeaconTime == null ||
        _lastBeaconLat == null ||
        _lastBeaconLon == null) {
      return false;
    }

    final secsSinceLast = now.difference(_lastBeaconTime!).inSeconds;
    // Never beacon faster than the fast rate, regardless of movement.
    if (secsSinceLast < _sbFastRateSecs) return false;

    final speed = gps.speed;
    final slowRateSecs = _config.intervalSeconds;

    // Corner pegging: beacon early on a sharp heading change. Heading is
    // unreliable when nearly stationary, so only apply it above the low speed.
    if (speed > _sbLowSpeedKnots &&
        _lastBeaconHeading != null &&
        !_lastBeaconHeading!.isNaN) {
      final turnThreshold = _sbTurnMinDegrees + _sbTurnSlope / speed;
      final headingChange = _headingDelta(_lastBeaconHeading!, gps.heading);
      if (headingChange > turnThreshold && secsSinceLast >= _sbTurnTimeSecs) {
        return true;
      }
    }

    // Distance trigger: beacon as soon as we have moved a significant distance
    // from the last beacon position. This covers sources (e.g. manual/phone
    // location) that do not report a reliable speed.
    final movedMetres = RadioUtils.haversineMetres(
      _lastBeaconLat!,
      _lastBeaconLon!,
      gps.latitude,
      gps.longitude,
    );
    if (movedMetres >= _sbMinMoveMetres) return true;

    // Speed-adaptive rate: faster when moving quickly, slower when stopped.
    final int beaconRateSecs;
    if (speed <= _sbLowSpeedKnots) {
      beaconRateSecs = slowRateSecs;
    } else if (speed >= _sbHighSpeedKnots) {
      beaconRateSecs = _sbFastRateSecs;
    } else {
      final rate = (_sbFastRateSecs * _sbHighSpeedKnots / speed).round();
      beaconRateSecs = rate.clamp(_sbFastRateSecs, slowRateSecs);
    }
    return secsSinceLast >= beaconRateSecs;
  }

  /// Smallest absolute difference between two headings in degrees (0-180).
  static double _headingDelta(double a, double b) {
    var diff = (a - b).abs() % 360.0;
    if (diff > 180.0) diff = 360.0 - diff;
    return diff;
  }

  /// Builds the APRS information field: a position report when location is
  /// enabled and a fix is available, otherwise a status report.
  String? _buildInformationField() {
    final message = _config.message.trim();
    if (_config.includeLocation) {
      final gps = _currentFix();
      if (gps != null) {
        final lat = AprsUtil.convertLatToNmea(gps.latitude);
        final lon = AprsUtil.convertLonToNmea(gps.longitude);
        // '=' = position without timestamp, messaging-capable.
        return '=$lat${_config.symbolTable}$lon${_config.symbolCode}$message';
      }
    }
    // Status report (no position). Skip entirely when there is nothing to say.
    if (message.isEmpty) return null;
    return '>$message';
  }

  /// Returns the current GPS/manual fix (device 1 `GpsData`) when valid.
  GpsData? _currentFix() {
    final gps = _broker.getJsonValue<GpsData>(
      1,
      'GpsData',
      (json) => GpsData.fromJson(json),
    );
    if (gps == null || !gps.isFixed) return null;
    if (gps.latitude == 0 && gps.longitude == 0) return null;
    return gps;
  }

  int _resolveTxRadio() {
    final preferred = _config.radioDeviceId;
    // A non-positive id means the user chose "Internet only": never use RF.
    if (preferred <= 0) return -1;
    final connected = _connectedRadioIds();
    if (connected.contains(preferred) && _getAprsChannelId(preferred) >= 0) {
      return preferred;
    }
    // The preferred radio is gone (e.g. reconnected with a new device id):
    // fall back to the first connected radio that has an APRS channel.
    for (final id in connected) {
      if (_getAprsChannelId(id) >= 0) return id;
    }
    return -1;
  }

  List<int> _connectedRadioIds() {
    final ids = <int>[];
    final raw = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['DeviceId'] is int) {
          ids.add(item['DeviceId'] as int);
        }
      }
    }
    return ids;
  }

  /// Returns the channel id of the "APRS" channel for [radioDeviceId], or -1.
  int _getAprsChannelId(int radioDeviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      radioDeviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return -1;
    for (final channel in channels) {
      if (channel.name == 'APRS') return channel.channelId;
    }
    return -1;
  }
}
