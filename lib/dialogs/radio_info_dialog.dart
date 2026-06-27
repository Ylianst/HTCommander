/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `RadioInfoForm`. Displays live radio information grouped
into Device Information, Device Status, Device Settings, BSS Settings and
Position sections. All data is read from the DataBroker (per-device `Info`,
`HtStatus`, `Settings`, `BssSettings`, `Position`) and the connected radio
list (`ConnectedRadios` on device 1), and the dialog updates in real time as
the broker dispatches new values.
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

  RadioDevInfo? _info;
  RadioHtStatus? _htStatus;
  RadioSettings? _settings;
  RadioBssSettings? _bssSettings;
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
          _info = null;
          _htStatus = null;
          _settings = null;
          _bssSettings = null;
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
    _info = _broker.getJsonValue<RadioDevInfo>(
      newDeviceId,
      'Info',
      (json) => RadioDevInfo.fromJson(json),
    );
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
    _bssSettings = _broker.getJsonValue<RadioBssSettings>(
      newDeviceId,
      'BssSettings',
      (json) => RadioBssSettings.fromJson(json),
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
      names: const [
        'Info',
        'HtStatus',
        'Settings',
        'BssSettings',
        'Position',
        'FriendlyName',
      ],
      callback: _onDeviceValueChanged,
    );
  }

  void _unsubscribeFromDevice(int deviceId) {
    if (deviceId <= 0) return;
    _broker.unsubscribe(deviceId, 'Info');
    _broker.unsubscribe(deviceId, 'HtStatus');
    _broker.unsubscribe(deviceId, 'Settings');
    _broker.unsubscribe(deviceId, 'BssSettings');
    _broker.unsubscribe(deviceId, 'Position');
    _broker.unsubscribe(deviceId, 'FriendlyName');
  }

  void _onDeviceValueChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (deviceId != _deviceId) return;
    setState(() {
      switch (name) {
        case 'Info':
          _info = data is Map<String, dynamic>
              ? RadioDevInfo.fromJson(data)
              : null;
          break;
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
        case 'BssSettings':
          _bssSettings = data is Map<String, dynamic>
              ? RadioBssSettings.fromJson(data)
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
          _buildSection('Device Information', _infoRows()),
          const SizedBox(height: 12),
          _buildSection('Device Status', _statusRows()),
          const SizedBox(height: 12),
          _buildSection('Device Settings', _settingsRows()),
          const SizedBox(height: 12),
          _buildSection('BSS Settings', _bssRows()),
          const SizedBox(height: 12),
          _buildSection('Position', _positionRows()),
        ],
      ),
    );
  }

  List<_InfoRow> _infoRows() {
    final i = _info;
    if (i == null) return const [_InfoRow('Status', 'No data')];

    String vendor = '${i.vendorId}';
    switch (i.vendorId) {
      case 1:
        vendor += ' - Vero';
        break;
      case 6:
        vendor += ' - BTech';
        break;
      case 255:
        vendor += ' - RadioOddity';
        break;
    }

    return [
      _row('Product ID', '${i.productId}'),
      _row('Vendor ID', vendor),
      _row('DMR Support', _presentStr(i.supportDmr)),
      _row('GMRS Support', _presentStr(i.gmrs)),
      _row('Hardware Speaker', _presentStr(i.haveHmSpeaker)),
      _row('Hardware Version', '${i.hwVer}'),
      _row('Software Version', i.softwareVersion),
      _row('Region Count', '${i.regionCount}'),
      _row('Medium Power', _supportedStr(i.supportMediumPower)),
      _row('Channel Count', '${i.channelCount}'),
      _row('NOAA', _supportedStr(i.supportNoaa)),
      _row('Radio', _supportedStr(i.supportRadio)),
      _row('VFO', _supportedStr(i.supportVfo)),
      _row('Freq Range Count', '${i.freqRangeCount}'),
    ];
  }

  List<_InfoRow> _statusRows() {
    final s = _htStatus;
    if (s == null) return const [_InfoRow('Status', 'No data')];
    return [
      _row('Power On', _boolStr(s.isPowerOn)),
      _row('In TX', _boolStr(s.isInTx)),
      _row('is_sq', _boolStr(s.isSq)),
      _row('In RX', _boolStr(s.isInRx)),
      _row('Double Channel', s.doubleChannel.name.toUpperCase()),
      _row('Scanning', _boolStr(s.isScan)),
      _row('Radio', _boolStr(s.isRadio)),
      _row('Current Channel ID', '${s.currChId + 1}'),
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
    final autoShareLocCh = s.autoShareLocCh == 0
        ? 'Current'
        : 'Channel ${s.autoShareLocCh}';
    return [
      _row('VFO A', 'Channel ${s.channelA + 1}'),
      _row('VFO B', 'Channel ${s.channelB + 1}'),
      _row('Scan', _boolStr(s.scan)),
      _row('AGHFP Call Mode', _boolStr(s.aghfpCallMode)),
      _row('Double Channel', '${s.doubleChannel}'),
      _row('Squelch Level', '${s.squelchLevel}'),
      _row('Tail elim', _boolStr(s.tailElim)),
      _row('Auto relay en', _boolStr(s.autoRelayEn)),
      _row('Auto power on', _boolStr(s.autoPowerOn)),
      _row('Keep AGHFP link', _boolStr(s.keepAghfpLink)),
      _row('Mic gain', '${s.micGain}'),
      _row('TX hold time', '${s.txHoldTime}'),
      _row('TX time limit', '${s.txTimeLimit}'),
      _row('Local Speaker', '${s.localSpeaker}'),
      _row('BT mic gain', '${s.btMicGain}'),
      _row('Adaptive Response', _boolStr(s.adaptiveResponse)),
      _row('DIS Tone', _boolStr(s.disTone)),
      _row('Power saving mode', _boolStr(s.powerSavingMode)),
      _row('Auto power off', '${s.autoPowerOff}'),
      _row('Auto share location ch', autoShareLocCh),
      _row('HW speaker', '${s.hmSpeaker}'),
      _row('Positioning system', '${s.positioningSystem}'),
      _row('Time offset', '${s.timeOffset}'),
      _row('Use freq range 2', _boolStr(s.useFreqRange2)),
      _row('PTT lock', _boolStr(s.pttLock)),
      _row('Leading sync bit en', _boolStr(s.leadingSyncBitEn)),
      _row('Pairing at power on', _boolStr(s.pairingAtPowerOn)),
      _row('Screen Timeout', '${s.screenTimeout}'),
      _row('VFO x', '${s.vfoX}'),
      _row('Imperial Units', _boolStr(s.imperialUnit)),
      _row('Weather Mode', '${s.wxMode}'),
      _row('NOAA Channel', '${s.noaaCh}'),
      _row('VFOl tx power', '${s.vfolTxPowerX}'),
      _row('VFO2 tx power', '${s.vfo2TxPowerX}'),
      _row('Dis digital mute', _boolStr(s.disDigitalMute)),
      _row('Signaling ecc en', _boolStr(s.signalingEccEn)),
      _row('Ch data lock', _boolStr(s.chDataLock)),
      _row('VFO1 mod freq', '${s.vfo1ModFreqX}'),
      _row('VFO2 mod freq', '${s.vfo2ModFreqX}'),
    ];
  }

  List<_InfoRow> _bssRows() {
    final b = _bssSettings;
    if (b == null) return const [_InfoRow('Settings', 'No data')];
    final shareInterval = b.locationShareInterval == 0
        ? 'Off'
        : '${b.locationShareInterval} second(s)';
    return [
      _row('Allow Position Check', _boolStr(b.allowPositionCheck)),
      _row('APRS Callsign', '${b.aprsCallsign}-${b.aprsSsid}'),
      _row('APRS Symbol', b.aprsSymbol),
      _row('Beacon Message', b.beaconMessage),
      _row('BSS User Id Lower', '${b.bssUserIdLower}'),
      _row('Location Share Interval', shareInterval),
      _row('Max Fwd Times', '${b.maxFwdTimes}'),
      _row('Packet Format', '${b.packetFormat}'),
      _row('PTT Release ID Info', b.pttReleaseIdInfo),
      _row('PTT Release Send BSS User Id', _boolStr(b.pttReleaseSendBssUserId)),
      _row('PTT Release Send Id Info', _boolStr(b.pttReleaseSendIdInfo)),
      _row('PTT Release Send Location', _boolStr(b.pttReleaseSendLocation)),
      _row('Send Pwr Voltage', _boolStr(b.sendPwrVoltage)),
      _row('Should Share Location', _boolStr(b.shouldShareLocation)),
      _row('Time To Live', '${b.timeToLive}'),
    ];
  }

  List<_InfoRow> _positionRows() {
    final p = _position;
    if (p == null) return const [_InfoRow('Status', 'No GPS data')];
    if (!p.locked) return const [_InfoRow('Status', 'No GPS lock')];
    final rows = <_InfoRow>[
      _row('Status', 'GPS locked'),
      _row('Latitude', _dmsStr(p.latitude, isLatitude: true)),
      _row('Longitude', _dmsStr(p.longitude, isLatitude: false)),
      _row('Accuracy', '${p.accuracy.toStringAsFixed(0)} meters'),
      _row('Altitude', '${p.altitude.toStringAsFixed(0)} meters'),
      _row('Speed', p.speed.toStringAsFixed(0)),
      _row('Heading', '${p.heading.toStringAsFixed(0)} degrees'),
    ];
    if (p.receivedTime != null) {
      rows.add(_row('Received Time', _formatTime(p.receivedTime!)));
    }
    if (p.timestamp != null) {
      rows.add(_row('GPS Time Local', _formatTime(p.timestamp!.toLocal())));
      rows.add(_row('GPS Time UTC', _formatTime(p.timestamp!.toUtc())));
    }
    return rows;
  }

  static String _boolStr(bool v) => v ? 'True' : 'False';

  static String _presentStr(bool v) => v ? 'Present' : 'Not-Present';

  static String _supportedStr(bool v) => v ? 'Supported' : 'Not-Supported';

  /// Formats a decimal degree value as degrees/minutes/seconds with a
  /// hemisphere suffix, matching the C# `ConvertLatitudeToDms` output.
  static String _dmsStr(double value, {required bool isLatitude}) {
    final direction = value >= 0
        ? (isLatitude ? 'N' : 'E')
        : (isLatitude ? 'S' : 'W');
    final abs = value.abs();
    final degrees = abs.floor();
    final minutesDecimal = (abs - degrees) * 60;
    final minutes = minutesDecimal.floor();
    final seconds = (minutesDecimal - minutes) * 60;
    return '$degrees\u00B0 $minutes\' ${seconds.toStringAsFixed(2)}" $direction';
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
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
