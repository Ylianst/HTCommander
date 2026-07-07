/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Displays live GPS data received from the serial GPS handler.
Subscribes to device 0 for connection settings and device 1 for
GpsData updates, refreshing the UI in real time.

Ported from the C# HTCommander.Dialogs.GpsDetailsForm.
*/

import 'package:flutter/material.dart';

import '../gps/gps_data.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the Serial GPS Information dialog.
Future<void> showGpsSerialInfoDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _GpsSerialInfoDialog(),
  );
}

class _GpsSerialInfoDialog extends StatefulWidget {
  const _GpsSerialInfoDialog();

  @override
  State<_GpsSerialInfoDialog> createState() => _GpsSerialInfoDialogState();
}

class _GpsSerialInfoDialogState extends State<_GpsSerialInfoDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  String _port = 'None';
  int _baudRate = 4800;
  String _status = 'Not Configured';
  GpsData? _gpsData;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();

    _broker.subscribe(
      deviceId: 0,
      name: 'GpsSerialPort',
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'GpsBaudRate',
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'GpsData',
      callback: _onGpsDataChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'GpsStatus',
      callback: _onGpsStatusChanged,
    );

    // Seed from current broker state.
    _port = _broker.getValue<String>(0, 'GpsSerialPort', 'None') ?? 'None';
    _baudRate = _broker.getValue<int>(0, 'GpsBaudRate', 4800) ?? 4800;
    _status = _broker.getValue<String>(1, 'GpsStatus', 'Not Configured') ??
        'Not Configured';
    _gpsData = _broker.getJsonValue<GpsData>(
      1,
      'GpsData',
      (json) => GpsData.fromJson(json),
    );
    if (_gpsData != null) _lastUpdate = DateTime.now();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onSettingChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _port = _broker.getValue<String>(0, 'GpsSerialPort', 'None') ?? 'None';
      _baudRate = _broker.getValue<int>(0, 'GpsBaudRate', 4800) ?? 4800;
    });
  }

  void _onGpsStatusChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _status = data is String ? data : 'Unknown';
    });
  }

  void _onGpsDataChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      if (data is Map<String, dynamic>) {
        _gpsData = GpsData.fromJson(data);
        _lastUpdate = DateTime.now();
      } else if (data is GpsData) {
        _gpsData = data;
        _lastUpdate = DateTime.now();
      } else {
        _gpsData = null;
      }
    });
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'GPS Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Expanded(child: _buildContent()),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection('Connection', _connectionRows()),
          const SizedBox(height: 12),
          _buildSection('GPS Fix', _fixRows()),
          const SizedBox(height: 12),
          _buildSection('Position', _positionRows()),
          const SizedBox(height: 12),
          _buildSection('Motion', _motionRows()),
          const SizedBox(height: 12),
          _buildSection('Time', _timeRows()),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Row builders
  // --------------------------------------------------------------------------

  List<_InfoRow> _connectionRows() {
    final configured = _port.isNotEmpty && _port != 'None';
    String portStatus;
    if (!configured) {
      portStatus = 'Not Configured';
    } else if (_gpsData != null) {
      portStatus = 'Open \u2014 Receiving Data';
    } else {
      portStatus = _status;
    }
    return [
      _InfoRow('Serial Port', _port.isEmpty ? 'None' : _port),
      _InfoRow('Baud Rate', '$_baudRate baud'),
      _InfoRow('Port Status', portStatus),
    ];
  }

  List<_InfoRow> _fixRows() {
    final gps = _gpsData;
    if (gps == null) {
      return const [
        _InfoRow('Fix', 'No Data'),
        _InfoRow('Fix Quality', '-'),
        _InfoRow('Satellites', '-'),
      ];
    }

    String qualDesc;
    switch (gps.fixQuality) {
      case 1:
        qualDesc = 'GPS Fix (1)';
      case 2:
        qualDesc = 'DGPS Fix (2)';
      case 0:
        qualDesc = 'Invalid (0)';
      default:
        qualDesc = '${gps.fixQuality} (unknown)';
    }

    return [
      _InfoRow('Fix', gps.isFixed ? 'Active' : 'No Fix'),
      _InfoRow('Fix Quality', qualDesc),
      _InfoRow('Satellites', '${gps.satellites}'),
    ];
  }

  List<_InfoRow> _positionRows() {
    final gps = _gpsData;
    if (gps == null) {
      return const [
        _InfoRow('Latitude', '-'),
        _InfoRow('Longitude', '-'),
        _InfoRow('Altitude', '-'),
      ];
    }

    if (gps.latitude == 0.0 && gps.longitude == 0.0) {
      return const [
        _InfoRow('Latitude', '-'),
        _InfoRow('Latitude (DMS)', '-'),
        _InfoRow('Longitude', '-'),
        _InfoRow('Longitude (DMS)', '-'),
        _InfoRow('Altitude', '-'),
      ];
    }

    final latDir = gps.latitude >= 0 ? 'N' : 'S';
    final lonDir = gps.longitude >= 0 ? 'E' : 'W';
    final absLat = gps.latitude.abs();
    final absLon = gps.longitude.abs();

    return [
      _InfoRow('Latitude', '${absLat.toStringAsFixed(6)}\u00B0 $latDir'),
      _InfoRow('Latitude (DMS)', '${_formatDMS(absLat)} $latDir'),
      _InfoRow('Longitude', '${absLon.toStringAsFixed(6)}\u00B0 $lonDir'),
      _InfoRow('Longitude (DMS)', '${_formatDMS(absLon)} $lonDir'),
      _InfoRow(
        'Altitude',
        '${gps.altitude.toStringAsFixed(1)} m  '
            '(${(gps.altitude * 3.28084).toStringAsFixed(1)} ft)',
      ),
    ];
  }

  List<_InfoRow> _motionRows() {
    final gps = _gpsData;
    if (gps == null) {
      return const [
        _InfoRow('Speed', '-'),
        _InfoRow('Heading', '-'),
      ];
    }

    final kmh = gps.speed * 1.852;
    final mph = gps.speed * 1.15078;
    return [
      _InfoRow(
        'Speed',
        '${gps.speed.toStringAsFixed(1)} kn  '
            '(${kmh.toStringAsFixed(1)} km/h  /  '
            '${mph.toStringAsFixed(1)} mph)',
      ),
      _InfoRow(
        'Heading',
        '${gps.heading.toStringAsFixed(1)}\u00B0  '
            '(${_headingToCompass(gps.heading)})',
      ),
    ];
  }

  List<_InfoRow> _timeRows() {
    final gps = _gpsData;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final hasTime = gps != null && gps.gpsTime.isAfter(epoch);

    return [
      _InfoRow(
        'GPS Time (UTC)',
        hasTime ? _formatTimeOfDay(gps.gpsTime) : '-',
      ),
      _InfoRow(
        'GPS Date',
        hasTime ? _formatDate(gps.gpsTime) : '-',
      ),
      _InfoRow(
        'Last Update',
        _lastUpdate != null ? _formatTimeOfDay(_lastUpdate!) : '-',
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  /// Converts a positive decimal-degree value to DDD° MM' SS.SS" string.
  static String _formatDMS(double decDeg) {
    final deg = decDeg.truncate();
    final minFull = (decDeg - deg) * 60.0;
    final min = minFull.truncate();
    final sec = (minFull - min) * 60.0;
    return '$deg\u00B0 ${min.toString().padLeft(2, '0')}\' '
        '${sec.toStringAsFixed(2)}"';
  }

  /// Returns a 16-point compass abbreviation for a true-north heading.
  static String _headingToCompass(double heading) {
    const pts = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    var index = (heading / 22.5).round() % 16;
    if (index < 0) index += 16;
    return pts[index];
  }

  static String _formatTimeOfDay(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final tenths = t.millisecond ~/ 100;
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$tenths';
  }

  static String _formatDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day.toString().padLeft(2, '0')} '
        '${months[t.month - 1]} ${t.year}';
  }

  // --------------------------------------------------------------------------
  // Section UI (matches radio_info_dialog styling)
  // --------------------------------------------------------------------------

  Widget _buildSection(String title, List<_InfoRow> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 16, color: Colors.grey.shade200),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    rows[i].label,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[i].value,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A single label/value pair shown inside an info section.
class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
