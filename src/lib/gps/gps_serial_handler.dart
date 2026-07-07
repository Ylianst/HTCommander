/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.Gps.GpsSerialHandler` class.
*/

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/serial/serial_port.dart';
import '../services/data_broker_client.dart';
import 'gps_data.dart';

/// Data Broker handler that reads NMEA sentences from a GPS serial port.
///
/// Reads the `GpsSerialPort` and `GpsBaudRate` settings from device 0 (as
/// configured in the Settings dialog). Parses incoming NMEA sentences and
/// dispatches a [GpsData] object on device 1 under key `GpsData`, along with a
/// `GpsStatus` string describing the current connection state.
///
/// Serial port access is only available on desktop platforms (Windows, macOS
/// and Linux). On other platforms the handler is inert.
class GpsSerialHandler {
  /// Device id that owns persisted application settings.
  static const int _settingsDeviceId = 0;

  /// Device id used for GPS data and status events.
  static const int _gpsDeviceId = 1;

  final DataBrokerClient _broker = DataBrokerClient();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSub;

  /// Identifies the open attempt currently in progress so a stale async open
  /// can detect that the settings changed underneath it.
  int _openToken = 0;

  final StringBuffer _lineBuffer = StringBuffer();
  String _currentPortName = 'None';
  int _currentBaudRate = 4800;
  GpsData _gpsData = GpsData();
  bool _isCommunicating = false;
  bool _disposed = false;

  /// Whether serial port access is available on the current platform.
  static bool get _serialSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Initializes the handler: subscribes to broker events and applies the
  /// current settings. Safe to call once at startup.
  void init() {
    if (!_serialSupported) {
      // Serial GPS is only supported on desktop platforms.
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsStatus',
        data: 'Unsupported',
        store: true,
      );
      return;
    }

    // Subscribe to GPS serial port / baud rate setting changes on device 0.
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'GpsSerialPort',
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'GpsBaudRate',
      callback: _onSettingChanged,
    );

    // Read current settings and open port if already configured.
    _currentPortName =
        _broker.getValue<String>(_settingsDeviceId, 'GpsSerialPort', 'None') ??
        'None';
    _currentBaudRate =
        _broker.getValue<int>(_settingsDeviceId, 'GpsBaudRate', 4800) ?? 4800;
    _startPort(_currentPortName, _currentBaudRate);
  }

  // ------------------------------------------------------------------
  // Settings change handler
  // ------------------------------------------------------------------

  void _onSettingChanged(int deviceId, String name, Object? value) {
    final newPort =
        _broker.getValue<String>(_settingsDeviceId, 'GpsSerialPort', 'None') ??
        'None';
    final newBaud =
        _broker.getValue<int>(_settingsDeviceId, 'GpsBaudRate', 4800) ?? 4800;

    // Only restart if something actually changed.
    if (newPort == _currentPortName && newBaud == _currentBaudRate) return;

    _currentPortName = newPort;
    _currentBaudRate = newBaud;

    // Close previous port (dispatches "Disconnected").
    _stopPort();

    final portConfigured = newPort.isNotEmpty && newPort != 'None';
    if (portConfigured) {
      // Override "Disconnected" with "Connecting" while the open is in progress.
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsStatus',
        data: 'Connecting',
        store: true,
      );
      _startPort(_currentPortName, _currentBaudRate);
    } else {
      // Port explicitly set to None — override to "Disabled".
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsStatus',
        data: 'Disabled',
        store: true,
      );
    }
  }

  // ------------------------------------------------------------------
  // Serial port lifecycle
  // ------------------------------------------------------------------

  void _startPort(String portName, int baudRate) {
    if (portName.isEmpty || portName == 'None') return;

    final token = ++_openToken;

    // Open after a short delay so the UI never blocks on a slow open, and so
    // the previous port handle has time to be fully released by the driver.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_disposed || token != _openToken) return;

      SerialPort? port;
      try {
        port = SerialPort(portName);
        if (!port.openReadWrite()) {
          port.dispose();
          throw const _SerialOpenException();
        }

        final config = SerialPortConfig()
          ..baudRate = baudRate
          ..bits = 8
          ..parity = SerialPortParity.none
          ..stopBits = 1
          ..setFlowControl(SerialPortFlowControl.none)
          ..dtr = SerialPortDtr.on
          ..rts = SerialPortRts.on;
        port.config = config;
        config.dispose();
      } catch (_) {
        try {
          port?.close();
        } catch (_) {}
        try {
          port?.dispose();
        } catch (_) {}
        if (!_disposed && token == _openToken) {
          _broker.dispatch(
            deviceId: _gpsDeviceId,
            name: 'GpsStatus',
            data: 'PortError',
            store: true,
          );
        }
        return;
      }

      // Staleness check: settings may have changed while opening.
      if (_disposed || token != _openToken) {
        try {
          port.close();
        } catch (_) {}
        try {
          port.dispose();
        } catch (_) {}
        return;
      }

      _port = port;
      try {
        final reader = SerialPortReader(port);
        _reader = reader;
        _readerSub = reader.stream.listen(
          _onDataReceived,
          onError: (_) {},
          cancelOnError: false,
        );
      } catch (_) {
        _broker.dispatch(
          deviceId: _gpsDeviceId,
          name: 'GpsStatus',
          data: 'PortError',
          store: true,
        );
      }
    });
  }

  void _stopPort() {
    // Invalidate any in-flight open.
    _openToken++;

    try {
      _readerSub?.cancel();
    } catch (_) {}
    _readerSub = null;

    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;

    final port = _port;
    _port = null;
    if (port != null) {
      // Close the port handle asynchronously. Some USB-serial drivers block
      // CloseHandle for a noticeable period after recent I/O, which would
      // freeze the UI if done synchronously.
      Future(() {
        try {
          if (port.isOpen) port.close();
        } catch (_) {}
        try {
          port.dispose();
        } catch (_) {}
      });
    }

    _lineBuffer.clear();
    _gpsData = GpsData();
    _isCommunicating = false;

    // Clear stale GPS data and update status immediately.
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      data: null,
      store: true,
    );
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsStatus',
      data: 'Disconnected',
      store: true,
    );
  }

  // ------------------------------------------------------------------
  // Serial data reception
  // ------------------------------------------------------------------

  void _onDataReceived(Uint8List data) {
    if (_disposed || _port == null) return;

    try {
      for (final byte in data) {
        final ch = byte & 0x7f; // NMEA is 7-bit ASCII
        if (ch == 0x0a) {
          // '\n'
          // Strip trailing CR if present.
          var line = _lineBuffer.toString();
          _lineBuffer.clear();
          if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
          if (line.isNotEmpty) _processNmeaLine(line);
        } else {
          _lineBuffer.write(String.fromCharCode(ch));
        }
      }
    } catch (_) {
      // Ignore read errors.
    }
  }

  // ------------------------------------------------------------------
  // NMEA processing
  // ------------------------------------------------------------------

  void _processNmeaLine(String line) {
    // NMEA sentences start with '$' and end with '*XX' checksum.
    if (line.length < 6 || line[0] != '\$') return;

    // Validate checksum.
    final starIdx = line.lastIndexOf('*');
    if (starIdx > 0 && starIdx < line.length - 1) {
      if (!_validateChecksum(line, starIdx)) return;
      line = line.substring(0, starIdx); // strip checksum suffix
    }

    final fields = line.split(',');
    if (fields.length < 2) return;

    // First valid sentence — notify listeners the device is alive.
    if (!_isCommunicating) {
      _isCommunicating = true;
      _broker.dispatch(
        deviceId: _gpsDeviceId,
        name: 'GpsStatus',
        data: 'Communicating',
        store: true,
      );
    }

    // Accept both GP (single-constellation) and GN (multi-constellation).
    final type = fields[0].length >= 6 ? fields[0].substring(1) : '';

    if (type == 'GPRMC' || type == 'GNRMC') {
      _parseRmc(fields);
    } else if (type == 'GPGGA' || type == 'GNGGA') {
      _parseGga(fields);
    }
  }

  /// Validates the NMEA XOR checksum. Returns true when the computed checksum
  /// matches the two hex digits after '*'.
  static bool _validateChecksum(String sentence, int starIdx) {
    try {
      var computed = 0;
      for (var i = 1; i < starIdx; i++) {
        computed ^= sentence.codeUnitAt(i);
      }
      final hexStr = sentence.substring(starIdx + 1, starIdx + 3);
      final expected = int.parse(hexStr, radix: 16);
      return computed == expected;
    } catch (_) {
      return false;
    }
  }

  // $GPRMC / $GNRMC
  // $GPRMC,hhmmss.ss,A,ddmm.mmmm,N,dddmm.mmmm,E,speed,heading,ddmmyy,,...
  void _parseRmc(List<String> f) {
    // Minimum field count for a useful RMC sentence.
    if (f.length < 10) return;

    // Status: A = active (valid fix), V = void.
    final isFixed = f.length > 2 && f[2] == 'A';
    _gpsData.isFixed = isFixed;

    if (f[1].isNotEmpty && f[1].length >= 6) {
      _gpsData.gpsTime = _parseNmeaDateTime(f[1], f.length > 9 ? f[9] : '');
    }

    if (f[3].isNotEmpty && f[4].isNotEmpty) {
      var lat = _nmeaDegreesToDecimal(f[3]);
      if (f[4] == 'S') lat = -lat;
      _gpsData.latitude = lat;
    }

    if (f[5].isNotEmpty && f[6].isNotEmpty) {
      var lon = _nmeaDegreesToDecimal(f[5]);
      if (f[6] == 'W') lon = -lon;
      _gpsData.longitude = lon;
    }

    if (f[7].isNotEmpty) {
      final speed = double.tryParse(f[7]);
      if (speed != null) _gpsData.speed = speed;
    }

    if (f[8].isNotEmpty) {
      final heading = double.tryParse(f[8]);
      if (heading != null) _gpsData.heading = heading;
    }

    _dispatchGpsData();
  }

  // $GPGGA / $GNGGA
  // $GPGGA,hhmmss.ss,ddmm.mmmm,N,dddmm.mmmm,E,q,ss,hdop,alt,M,...
  void _parseGga(List<String> f) {
    if (f.length < 10) return;

    if (f[2].isNotEmpty && f[3].isNotEmpty) {
      var lat = _nmeaDegreesToDecimal(f[2]);
      if (f[3] == 'S') lat = -lat;
      _gpsData.latitude = lat;
    }

    if (f[4].isNotEmpty && f[5].isNotEmpty) {
      var lon = _nmeaDegreesToDecimal(f[4]);
      if (f[5] == 'W') lon = -lon;
      _gpsData.longitude = lon;
    }

    if (f[6].isNotEmpty) {
      final fixQuality = int.tryParse(f[6]);
      if (fixQuality != null) _gpsData.fixQuality = fixQuality;
    }

    if (f[7].isNotEmpty) {
      final sats = int.tryParse(f[7]);
      if (sats != null) _gpsData.satellites = sats;
    }

    if (f.length > 9 && f[9].isNotEmpty) {
      final alt = double.tryParse(f[9]);
      if (alt != null) _gpsData.altitude = alt;
    }

    _dispatchGpsData();
  }

  void _dispatchGpsData() {
    _broker.dispatch(
      deviceId: _gpsDeviceId,
      name: 'GpsData',
      data: _gpsData,
      store: true,
    );
  }

  // ------------------------------------------------------------------
  // NMEA helpers
  // ------------------------------------------------------------------

  /// Converts an NMEA coordinate string (ddmm.mmmm or dddmm.mmmm) to decimal
  /// degrees.
  static double _nmeaDegreesToDecimal(String nmea) {
    if (nmea.isEmpty) return 0.0;

    final raw = double.tryParse(nmea);
    if (raw == null) return 0.0;

    // Integer part contains degrees × 100, fractional part contains minutes.
    final degrees = (raw / 100).truncate();
    final minutes = raw - degrees * 100.0;
    return degrees + minutes / 60.0;
  }

  /// Parses NMEA time (hhmmss or hhmmss.ss) and date (ddmmyy) strings into a
  /// UTC [DateTime].
  static DateTime _parseNmeaDateTime(String timeStr, String dateStr) {
    try {
      final h = int.parse(timeStr.substring(0, 2));
      final m = int.parse(timeStr.substring(2, 4));
      final s = double.parse(timeStr.substring(4));
      final sec = s.truncate();
      final ms = ((s - sec) * 1000).truncate();

      if (dateStr.length == 6) {
        final day = int.parse(dateStr.substring(0, 2));
        final mon = int.parse(dateStr.substring(2, 4));
        final yr = 2000 + int.parse(dateStr.substring(4, 6));
        return DateTime.utc(yr, mon, day, h, m, sec, ms);
      }

      final today = DateTime.now().toUtc();
      return DateTime.utc(today.year, today.month, today.day, h, m, sec, ms);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  // ------------------------------------------------------------------
  // Disposal
  // ------------------------------------------------------------------

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_serialSupported) _stopPort();
    _broker.dispose();
  }
}

/// Internal marker exception used to signal a failed serial port open.
class _SerialOpenException implements Exception {
  const _SerialOpenException();
}
