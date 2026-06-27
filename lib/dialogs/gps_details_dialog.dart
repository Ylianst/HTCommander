/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.Dialogs.GpsDetailsForm`. Displays the live GPS
position reported by a connected radio, grouped into Fix, Position, Motion and
Time sections. All data is read from the DataBroker (per-device `Position` and
`GpsEnabled` keys) and the dialog refreshes in real time as the broker
dispatches new values.
*/

import 'package:flutter/material.dart';

import '../models/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the GPS Details dialog for the given [deviceId].
Future<void> showGpsDetailsDialog(
  BuildContext context, {
  required int deviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _GpsDetailsDialog(deviceId: deviceId),
  );
}

class _GpsDetailsDialog extends StatefulWidget {
  final int deviceId;
  const _GpsDetailsDialog({required this.deviceId});

  @override
  State<_GpsDetailsDialog> createState() => _GpsDetailsDialogState();
}

class _GpsDetailsDialogState extends State<_GpsDetailsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  RadioPosition? _position;
  bool _gpsEnabled = false;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();

    _gpsEnabled =
        _broker.getValue<bool>(widget.deviceId, 'GpsEnabled') ?? false;
    _position = _broker.getJsonValue<RadioPosition>(
      widget.deviceId,
      'Position',
      (json) => RadioPosition.fromJson(json),
    );
    if (_position != null) _lastUpdate = DateTime.now();

    _broker.subscribeMultiple(
      deviceId: widget.deviceId,
      names: const ['Position', 'GpsEnabled'],
      callback: _onBrokerEvent,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onBrokerEvent(int deviceId, String name, Object? data) {
    if (deviceId != widget.deviceId || !mounted) return;
    setState(() {
      switch (name) {
        case 'Position':
          if (data is Map<String, dynamic>) {
            _position = RadioPosition.fromJson(data);
            _lastUpdate = DateTime.now();
          } else if (data == null) {
            _position = null;
          }
          break;
        case 'GpsEnabled':
          _gpsEnabled = data as bool? ?? false;
          break;
      }
    });
  }

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
                  'GPS Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Flexible(child: _buildContent()),
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

  // ------------------------------------------------------------------
  // Section rows
  // ------------------------------------------------------------------

  List<_InfoRow> _fixRows() {
    if (!_gpsEnabled) return const [_InfoRow('Fix', 'GPS Disabled')];
    final p = _position;
    if (p == null) return const [_InfoRow('Fix', 'No Data')];
    return [_row('Fix', p.locked ? 'GPS Lock' : 'No GPS Lock')];
  }

  List<_InfoRow> _positionRows() {
    final p = _position;
    if (p == null) return const [_InfoRow('Position', 'No Data')];

    final rows = <_InfoRow>[];
    if (p.latitude != 0.0 || p.longitude != 0.0) {
      final latDir = p.latitude >= 0 ? 'N' : 'S';
      final lonDir = p.longitude >= 0 ? 'E' : 'W';
      final absLat = p.latitude.abs();
      final absLon = p.longitude.abs();

      rows.add(_row('Latitude', '${absLat.toStringAsFixed(6)}° $latDir'));
      rows.add(_row('Latitude (DMS)', '${_formatDms(absLat)} $latDir'));
      rows.add(_row('Longitude', '${absLon.toStringAsFixed(6)}° $lonDir'));
      rows.add(_row('Longitude (DMS)', '${_formatDms(absLon)} $lonDir'));
    } else {
      rows.add(_row('Latitude', '-'));
      rows.add(_row('Longitude', '-'));
    }

    final feet = p.altitude * 3.28084;
    rows.add(
      _row(
        'Altitude',
        '${p.altitude.toStringAsFixed(1)} m  '
            '(${feet.toStringAsFixed(1)} ft)',
      ),
    );
    return rows;
  }

  List<_InfoRow> _motionRows() {
    final p = _position;
    if (p == null) return const [_InfoRow('Motion', 'No Data')];

    final kmh = p.speed * 1.852;
    final mph = p.speed * 1.15078;
    return [
      _row(
        'Speed',
        '${p.speed.toStringAsFixed(1)} kn  '
            '(${kmh.toStringAsFixed(1)} km/h  /  ${mph.toStringAsFixed(1)} mph)',
      ),
      _row(
        'Heading',
        '${p.heading.toStringAsFixed(1)}°  (${_headingToCompass(p.heading)})',
      ),
    ];
  }

  List<_InfoRow> _timeRows() {
    final p = _position;
    final rows = <_InfoRow>[];
    if (p?.timestamp != null) {
      final t = p!.timestamp!.toUtc();
      rows.add(_row('GPS Time (UTC)', _formatTimeOfDay(t)));
      rows.add(_row('GPS Date', _formatDate(t)));
    } else {
      rows.add(_row('GPS Time (UTC)', '-'));
      rows.add(_row('GPS Date', '-'));
    }
    rows.add(
      _row(
        'Last Update',
        _lastUpdate != null ? _formatTimeOfDay(_lastUpdate!.toLocal()) : '-',
      ),
    );
    return rows;
  }

  // ------------------------------------------------------------------
  // Formatting helpers (ported from C# GpsDetailsForm)
  // ------------------------------------------------------------------

  /// Converts a positive decimal-degree value to a DDD° MM' SS.SS" string.
  static String _formatDms(double decDeg) {
    final deg = decDeg.truncate();
    final minFull = (decDeg - deg) * 60.0;
    final min = minFull.truncate();
    final sec = (minFull - min) * 60.0;
    return '$deg° ${min.toString().padLeft(2, '0')}\' '
        '${sec.toStringAsFixed(2)}"';
  }

  /// Returns a 16-point compass abbreviation for a true-north heading.
  static String _headingToCompass(double heading) {
    const pts = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', //
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    var index = (heading / 22.5).round() % 16;
    if (index < 0) index += 16;
    return pts[index];
  }

  static String _formatTimeOfDay(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final tenths = (t.millisecond ~/ 100);
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$tenths';
  }

  static String _formatDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day.toString().padLeft(2, '0')} '
        '${months[t.month - 1]} ${t.year}';
  }

  _InfoRow _row(String label, String value) => _InfoRow(label, value);

  // ------------------------------------------------------------------
  // Section builder (matches radio_info_dialog styling)
  // ------------------------------------------------------------------

  Widget _buildSection(String title, List<_InfoRow> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
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

  BoxDecoration _sectionDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// A single label/value pair shown inside an info section.
class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
