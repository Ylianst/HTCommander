/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Displays live GPS data received from the serial GPS handler.
Subscribes to device 0 for connection settings and device 1 for
GpsData updates, refreshing the UI in real time.

Ported from the C# HTCommander.Dialogs.GpsDetailsForm.
*/

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gps/gps_data.dart';
import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
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
                  l10n.gpsInfoTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
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
                    child: Text(l10n.commonOk),
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
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection(l10n.gpsSectionConnection, _connectionRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.gpsSectionFix, _fixRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.gpsSectionPosition, _positionRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.gpsSectionMotion, _motionRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.gpsSectionTime, _timeRows()),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Row builders
  // --------------------------------------------------------------------------

  List<_InfoRow> _connectionRows() {
    final l10n = AppLocalizations.of(context);
    final configured = _port.isNotEmpty && _port != 'None';
    String portStatus;
    if (!configured) {
      portStatus = l10n.gpsNotConfigured;
    } else if (_gpsData != null) {
      portStatus = l10n.gpsOpenReceiving;
    } else {
      portStatus = _friendlyStatus(_status);
    }
    return [
      _InfoRow(l10n.settingsSerialPort, _port.isEmpty ? l10n.settingsNone : _port),
      _InfoRow(l10n.settingsBaudRate, '$_baudRate baud'),
      _InfoRow(l10n.gpsPortStatus, portStatus),
    ];
  }

  /// Maps internal status codes to human-readable descriptions.
  String _friendlyStatus(String status) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case 'PermissionDenied':
        return defaultTargetPlatform == TargetPlatform.linux
            ? l10n.gpsPermDeniedLinux
            : l10n.gpsPermDenied;
      case 'PortError':
        return l10n.gpsPortError;
      default:
        return status;
    }
  }

  List<_InfoRow> _fixRows() {
    final l10n = AppLocalizations.of(context);
    final gps = _gpsData;
    if (gps == null) {
      return [
        _InfoRow(l10n.gpsFix, l10n.gpsNoData),
        _InfoRow(l10n.gpsFixQuality, '-'),
        _InfoRow(l10n.gpsSatellites, '-'),
      ];
    }

    String qualDesc;
    switch (gps.fixQuality) {
      case 1:
        qualDesc = l10n.gpsQualGps;
      case 2:
        qualDesc = l10n.gpsQualDgps;
      case 0:
        qualDesc = l10n.gpsQualInvalid;
      default:
        qualDesc = l10n.gpsQualUnknown(gps.fixQuality);
    }

    return [
      _InfoRow(l10n.gpsFix, gps.isFixed ? l10n.gpsActive : l10n.gpsNoFix),
      _InfoRow(l10n.gpsFixQuality, qualDesc),
      _InfoRow(l10n.gpsSatellites, '${gps.satellites}'),
    ];
  }

  List<_InfoRow> _positionRows() {
    final l10n = AppLocalizations.of(context);
    final gps = _gpsData;
    if (gps == null) {
      return [
        _InfoRow(l10n.gpsLatitude, '-'),
        _InfoRow(l10n.gpsLongitude, '-'),
        _InfoRow(l10n.gpsAltitude, '-'),
      ];
    }

    if (gps.latitude == 0.0 && gps.longitude == 0.0) {
      return [
        _InfoRow(l10n.gpsLatitude, '-'),
        _InfoRow(l10n.gpsLatitudeDms, '-'),
        _InfoRow(l10n.gpsLongitude, '-'),
        _InfoRow(l10n.gpsLongitudeDms, '-'),
        _InfoRow(l10n.gpsAltitude, '-'),
      ];
    }

    final latDir = gps.latitude >= 0 ? 'N' : 'S';
    final lonDir = gps.longitude >= 0 ? 'E' : 'W';
    final absLat = gps.latitude.abs();
    final absLon = gps.longitude.abs();

    return [
      _InfoRow(l10n.gpsLatitude, '${absLat.toStringAsFixed(6)}\u00B0 $latDir'),
      _InfoRow(l10n.gpsLatitudeDms, '${_formatDMS(absLat)} $latDir'),
      _InfoRow(l10n.gpsLongitude, '${absLon.toStringAsFixed(6)}\u00B0 $lonDir'),
      _InfoRow(l10n.gpsLongitudeDms, '${_formatDMS(absLon)} $lonDir'),
      _InfoRow(
        l10n.gpsAltitude,
        '${gps.altitude.toStringAsFixed(1)} m  '
            '(${(gps.altitude * 3.28084).toStringAsFixed(1)} ft)',
      ),
    ];
  }

  List<_InfoRow> _motionRows() {
    final l10n = AppLocalizations.of(context);
    final gps = _gpsData;
    if (gps == null) {
      return [
        _InfoRow(l10n.gpsSpeed, '-'),
        _InfoRow(l10n.gpsHeading, '-'),
      ];
    }

    final kmh = gps.speed * 1.852;
    final mph = gps.speed * 1.15078;
    return [
      _InfoRow(
        l10n.gpsSpeed,
        '${gps.speed.toStringAsFixed(1)} kn  '
            '(${kmh.toStringAsFixed(1)} km/h  /  '
            '${mph.toStringAsFixed(1)} mph)',
      ),
      _InfoRow(
        l10n.gpsHeading,
        '${gps.heading.toStringAsFixed(1)}\u00B0  '
            '(${_headingToCompass(gps.heading)})',
      ),
    ];
  }

  List<_InfoRow> _timeRows() {
    final l10n = AppLocalizations.of(context);
    final gps = _gpsData;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final hasTime = gps != null && gps.gpsTime.isAfter(epoch);

    return [
      _InfoRow(
        l10n.gpsTimeUtc,
        hasTime ? _formatTimeOfDay(gps.gpsTime) : '-',
      ),
      _InfoRow(
        l10n.gpsDate,
        hasTime ? _formatDate(gps.gpsTime) : '-',
      ),
      _InfoRow(
        l10n.gpsLastUpdate,
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
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
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 16, color: scheme.outlineVariant),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    rows[i].label,
                    style: TextStyle(color: scheme.onSurfaceVariant),
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
