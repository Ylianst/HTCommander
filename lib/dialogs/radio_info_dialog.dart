/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `RadioInfoForm`. Displays live radio information grouped
into Device Status, Device Settings and Position sections. All data is read
from the DataBroker (per-device `HtStatus`, `Settings`, `Position`) and the
connected radio list (`ConnectedRadios` on device 1), and the dialog updates
in real time as the broker dispatches new values.
*/

import 'package:flutter/material.dart';

import '../models/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the Radio Information dialog. [initialDeviceId] selects which radio is
/// shown first; when omitted the first connected radio is used.
Future<void> showRadioInfoDialog(BuildContext context, {int? initialDeviceId}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RadioInfoDialog(initialDeviceId: initialDeviceId),
  );
}

class _RadioInfoDialog extends StatefulWidget {
  final int? initialDeviceId;
  const _RadioInfoDialog({this.initialDeviceId});

  @override
  State<_RadioInfoDialog> createState() => _RadioInfoDialogState();
}

class _RadioInfoDialogState extends State<_RadioInfoDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  /// The currently selected radio device id, or -1 when none is connected.
  int _deviceId = -1;

  List<ConnectedRadioInfo> _radios = const [];

  RadioHtStatus? _htStatus;
  RadioSettings? _settings;
  RadioPosition? _position;
  String _friendlyName = '';

  @override
  void initState() {
    super.initState();

    // Track the connected radio list so the selector stays in sync.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    _loadConnectedRadios();

    // Pick the initial device: the requested one if still connected, else the
    // first available radio.
    final requested = widget.initialDeviceId;
    if (requested != null && _radios.any((r) => r.deviceId == requested)) {
      _switchToDevice(requested);
    } else if (_radios.isNotEmpty) {
      _switchToDevice(_radios.first.deviceId);
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _loadConnectedRadios() {
    final radios =
        _broker.getJsonListValue<ConnectedRadioInfo>(
          1,
          'ConnectedRadios',
          (json) => ConnectedRadioInfo.fromJson(json),
        ) ??
        const [];
    // De-duplicate by device id - the broker list can contain repeated
    // entries, and the dropdown requires each value to be unique.
    final byId = <int, ConnectedRadioInfo>{};
    for (final radio in radios) {
      if (radio.deviceId > 0) {
        byId.putIfAbsent(radio.deviceId, () => radio);
      }
    }
    _radios = byId.values.toList();
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _loadConnectedRadios();
      // If the selected radio went away, fall back to the first available one.
      if (!_radios.any((r) => r.deviceId == _deviceId)) {
        if (_radios.isNotEmpty) {
          _switchToDevice(_radios.first.deviceId);
        } else {
          _unsubscribeFromDevice(_deviceId);
          _deviceId = -1;
          _htStatus = null;
          _settings = null;
          _position = null;
          _friendlyName = '';
        }
      }
    });
  }

  void _switchToDevice(int newDeviceId) {
    if (newDeviceId == _deviceId) return;
    if (_deviceId != -1) _unsubscribeFromDevice(_deviceId);

    _deviceId = newDeviceId;

    // Seed current values from the broker, then subscribe for live updates.
    _htStatus = _broker.getJsonValue<RadioHtStatus>(
      newDeviceId,
      'HtStatus',
      (json) => RadioHtStatus.fromJson(json),
    );
    _settings = _broker.getJsonValue<RadioSettings>(
      newDeviceId,
      'Settings',
      (json) => RadioSettings.fromJson(json),
    );
    _position = _broker.getJsonValue<RadioPosition>(
      newDeviceId,
      'Position',
      (json) => RadioPosition.fromJson(json),
    );
    _friendlyName =
        _broker.getValue<String>(newDeviceId, 'FriendlyName', '') ?? '';

    _broker.subscribeMultiple(
      deviceId: newDeviceId,
      names: const ['HtStatus', 'Settings', 'Position', 'FriendlyName'],
      callback: _onDeviceValueChanged,
    );
  }

  void _unsubscribeFromDevice(int deviceId) {
    if (deviceId <= 0) return;
    _broker.unsubscribe(deviceId, 'HtStatus');
    _broker.unsubscribe(deviceId, 'Settings');
    _broker.unsubscribe(deviceId, 'Position');
    _broker.unsubscribe(deviceId, 'FriendlyName');
  }

  void _onDeviceValueChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (deviceId != _deviceId) return;
    setState(() {
      switch (name) {
        case 'HtStatus':
          _htStatus = data is Map<String, dynamic>
              ? RadioHtStatus.fromJson(data)
              : null;
          break;
        case 'Settings':
          _settings = data is Map<String, dynamic>
              ? RadioSettings.fromJson(data)
              : null;
          break;
        case 'Position':
          _position = data is Map<String, dynamic>
              ? RadioPosition.fromJson(data)
              : null;
          break;
        case 'FriendlyName':
          _friendlyName = data is String ? data : '';
          break;
      }
    });
  }

  String _radioLabel(ConnectedRadioInfo radio) {
    if (radio.friendlyName.isNotEmpty) {
      return '${radio.friendlyName} (${radio.macAddress})';
    }
    return radio.macAddress.isNotEmpty
        ? radio.macAddress
        : 'Radio ${radio.deviceId}';
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
              // Title
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Radio Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              // Radio selector
              _buildRadioSelector(),
              const SizedBox(height: 12),
              // Scrollable content
              Expanded(child: _buildContent()),
              const SizedBox(height: 16),
              // Close button
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

  Widget _buildRadioSelector() {
    if (_radios.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: _sectionDecoration(),
        child: Text(
          'No radio connected',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final value = _radios.any((r) => r.deviceId == _deviceId)
        ? _deviceId
        : _radios.first.deviceId;

    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
      items: [
        for (final radio in _radios)
          DropdownMenuItem(
            value: radio.deviceId,
            child: Text(_radioLabel(radio)),
          ),
      ],
      onChanged: (newId) {
        if (newId != null) setState(() => _switchToDevice(newId));
      },
    );
  }

  Widget _buildContent() {
    if (_deviceId <= 0) {
      return Center(
        child: Text(
          'Connect a radio to view its information.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_friendlyName.isNotEmpty) ...[
            _buildSection('Radio', [_row('Name', _friendlyName)]),
            const SizedBox(height: 12),
          ],
          _buildSection('Device Status', _statusRows()),
          const SizedBox(height: 12),
          _buildSection('Device Settings', _settingsRows()),
          const SizedBox(height: 12),
          _buildSection('Position', _positionRows()),
        ],
      ),
    );
  }

  List<_InfoRow> _statusRows() {
    final s = _htStatus;
    if (s == null) return const [_InfoRow('Status', 'No data')];
    return [
      _row('Power On', _boolStr(s.isPowerOn)),
      _row('In TX', _boolStr(s.isInTx)),
      _row('In RX', _boolStr(s.isInRx)),
      _row('Squelch', _boolStr(s.isSq)),
      _row('Double Channel', s.doubleChannel.name.toUpperCase()),
      _row('Scanning', _boolStr(s.isScan)),
      _row('Radio', _boolStr(s.isRadio)),
      _row('Current Channel', '${s.currChId + 1}'),
      _row('GPS Locked', _boolStr(s.isGpsLocked)),
      _row('HFP Connected', _boolStr(s.isHfpConnected)),
      _row('AOC Connected', _boolStr(s.isAocConnected)),
      _row('RSSI', '${s.rssi}'),
      _row('Current Region', '${s.currRegion}'),
    ];
  }

  List<_InfoRow> _settingsRows() {
    final s = _settings;
    if (s == null) return const [_InfoRow('Settings', 'No data')];
    return [
      _row('VFO A', 'Channel ${s.channelA + 1}'),
      _row('VFO B', 'Channel ${s.channelB + 1}'),
      _row('Scan', _boolStr(s.scan)),
      _row('Double Channel', '${s.doubleChannel}'),
      _row('Squelch Level', '${s.squelchLevel}'),
      _row('PTT Lock', _boolStr(s.pttLock)),
      _row('NOAA Channel', '${s.noaaCh}'),
    ];
  }

  List<_InfoRow> _positionRows() {
    final p = _position;
    if (p == null) return const [_InfoRow('Status', 'No GPS data')];
    if (!p.locked) return const [_InfoRow('Status', 'No GPS lock')];
    return [
      _row('Status', 'GPS locked'),
      _row('Latitude', p.latitude.toStringAsFixed(6)),
      _row('Longitude', p.longitude.toStringAsFixed(6)),
      _row('Altitude', '${p.altitude.toStringAsFixed(0)} meters'),
      _row('Speed', p.speed.toStringAsFixed(1)),
      _row('Heading', '${p.heading.toStringAsFixed(0)} degrees'),
      if (p.timestamp != null) _row('GPS Time', _formatTime(p.timestamp!)),
    ];
  }

  static String _boolStr(bool v) => v ? 'Yes' : 'No';

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  _InfoRow _row(String label, String value) => _InfoRow(label, value);

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
