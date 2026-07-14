/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// `Radio` from radio.dart collides with Material's Radio button widget, which
// this dialog does not use; hide it so the radio model type is unambiguous.
import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';

import '../radio/ax25_address.dart';
import '../radio/radio.dart';
import '../radio/radio_models.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker_client.dart';
import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';

/// Shows the beacon settings dialog used to configure a connected radio's
/// beacon/BSS settings (callsign, message, interval, packet format, channel and
/// location-sharing flags).
///
/// Mirrors the C# `EditBeaconSettingsForm` from the reference application.
Future<void> showEditBeaconSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const EditBeaconSettingsDialog(),
  );
}

/// Beacon interval options (label + value in seconds), matching the C# form.
const List<int> _intervalSeconds = [
  0,
  10,
  20,
  30,
  40,
  50,
  60,
  120,
  180,
  240,
  300,
  360,
  420,
  480,
  540,
  600,
  900,
  1200,
  1500,
  1800,
];

const List<String> _packetFormatLabels = ['BSS', 'APRS'];

class EditBeaconSettingsDialog extends StatefulWidget {
  const EditBeaconSettingsDialog({super.key});

  @override
  State<EditBeaconSettingsDialog> createState() =>
      _EditBeaconSettingsDialogState();
}

class _EditBeaconSettingsDialogState extends State<EditBeaconSettingsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final BluetoothService _bluetooth = BluetoothService();

  final TextEditingController _callsignController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  int _selectedDeviceId = -1;
  String _radioName = '';

  // Channel dropdown: parallel labels/values (value == auto_share_loc_ch).
  List<String> _channelLabels = [];
  List<int> _channelValues = [];
  int _channelIndex = 0;

  int _packetFormatIndex = 0;
  int _intervalIndex = 0;
  bool _shareLocation = false;
  bool _sendVoltage = false;
  bool _allowPositionCheck = false;

  bool _controlsEnabled = false;
  bool _callsignValid = false;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _callsignController.addListener(_onCallsignChanged);

    final deviceId = _resolveCurrentRadioId();

    // If no radio is connected, close after the first frame.
    if (deviceId <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    _selectRadio(deviceId);
  }

  @override
  void dispose() {
    _callsignController.removeListener(_onCallsignChanged);
    _callsignController.dispose();
    _messageController.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;

    // The dialog is bound to the currently selected radio; if it is no longer
    // connected there is nothing to configure, so close.
    final connectedIds = _radioIds(
      _broker.getValueDynamic(1, 'ConnectedRadios'),
    );
    if (!connectedIds.contains(_selectedDeviceId)) {
      Navigator.of(context).pop();
    }
  }

  /// Resolves the currently selected radio, falling back to the first connected
  /// radio (mirrors the resolution used elsewhere in the app).
  int _resolveCurrentRadioId() {
    final connectedIds = _radioIds(
      _broker.getValueDynamic(1, 'ConnectedRadios'),
    );
    final selected =
        _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    if (selected > 0 && connectedIds.contains(selected)) return selected;
    return connectedIds.isNotEmpty ? connectedIds.first : -1;
  }

  List<int> _radioIds(Object? data) {
    final ids = <int>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map && item['DeviceId'] is int) {
          ids.add(item['DeviceId'] as int);
        }
      }
    }
    return ids;
  }

  String _friendlyNameForDevice(int deviceId) {
    final raw = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['DeviceId'] == deviceId) {
          return (item['FriendlyName'] as String?) ?? 'Radio $deviceId';
        }
      }
    }
    return 'Radio $deviceId';
  }

  void _selectRadio(int deviceId) {
    final radio = _bluetooth.radioInstance(deviceId);
    final bss = radio?.bssSettings;
    final radioName = _friendlyNameForDevice(deviceId);
    if (radio == null || bss == null) {
      setState(() {
        _selectedDeviceId = deviceId;
        _radioName = radioName;
        _controlsEnabled = false;
      });
      return;
    }

    _loadChannelOptions(radio);

    setState(() {
      _selectedDeviceId = deviceId;
      _radioName = radioName;
      _controlsEnabled = true;
      _packetFormatIndex = bss.packetFormat.clamp(
        0,
        _packetFormatLabels.length - 1,
      );
      _callsignController.text = '${bss.aprsCallsign}-${bss.aprsSsid}';
      _messageController.text = bss.beaconMessage;
      _shareLocation = bss.shouldShareLocation;
      _sendVoltage = bss.sendPwrVoltage;
      _allowPositionCheck = bss.allowPositionCheck;
      _intervalIndex = _intervalIndexForSeconds(bss.locationShareInterval);
    });
    _onCallsignChanged();
  }

  /// Builds the channel dropdown options for [radio]. The first entry is the
  /// "Current" option (value 0), followed by every named channel
  /// (value == channelId + 1). Selection follows RadioSettings.autoShareLocCh.
  void _loadChannelOptions(Radio radio) {
    final labels = <String>['Current (Not Recommended)'];
    final values = <int>[0];

    final channels = radio.channels;
    if (channels != null) {
      for (final ch in channels) {
        if (ch != null && ch.name.isNotEmpty) {
          labels.add(ch.name);
          values.add(ch.channelId + 1);
        }
      }
    }

    final currentValue = radio.settings?.autoShareLocCh ?? 0;
    int index = 0;
    for (int i = 0; i < values.length; i++) {
      if (values[i] == currentValue) {
        index = i;
        break;
      }
    }

    _channelLabels = labels;
    _channelValues = values;
    _channelIndex = index;
  }

  static int _intervalIndexForSeconds(int seconds) {
    int index = 0;
    for (int i = 0; i < _intervalSeconds.length; i++) {
      if (seconds >= _intervalSeconds[i]) index = i;
    }
    return index;
  }

  void _onCallsignChanged() {
    final valid = AX25Address.parse(_callsignController.text) != null;
    if (valid != _callsignValid) {
      setState(() => _callsignValid = valid);
    } else {
      _callsignValid = valid;
    }
  }

  bool get _canSave =>
      _controlsEnabled && _callsignValid && _selectedDeviceId > 0;

  void _onSave() {
    final radio = _bluetooth.radioInstance(_selectedDeviceId);
    final current = radio?.bssSettings;
    if (radio == null || current == null) return;

    final addr = AX25Address.parse(_callsignController.text);
    if (addr == null) return;

    // Make an independent copy of the current settings to preserve the fields
    // the dialog does not edit (mirrors the C# copy-then-modify approach).
    final src = current.toByteArray();
    final prefixed = Uint8List(src.length + 5);
    prefixed.setRange(5, 5 + src.length, src);
    final newSettings = RadioBssSettings.fromBytes(prefixed);

    newSettings.aprsCallsign = addr.address;
    newSettings.aprsSsid = addr.ssid;
    newSettings.packetFormat = _packetFormatIndex;
    newSettings.beaconMessage = _messageController.text;
    newSettings.shouldShareLocation = _shareLocation;
    newSettings.sendPwrVoltage = _sendVoltage;
    newSettings.allowPositionCheck = _allowPositionCheck;
    if (_intervalIndex >= 0 && _intervalIndex < _intervalSeconds.length) {
      newSettings.locationShareInterval = _intervalSeconds[_intervalIndex];
    }

    _broker.dispatch(
      deviceId: _selectedDeviceId,
      name: 'SetBssSettings',
      data: newSettings,
      store: false,
    );

    // Write auto_share_loc_ch into the radio settings (byte 5, low 5 bits).
    final settings = radio.settings;
    if (settings != null) {
      int channelValue = 0;
      if (_channelIndex >= 0 && _channelIndex < _channelValues.length) {
        channelValue = _channelValues[_channelIndex];
      }
      final settingsData = settings.toByteArrayWith();
      if (settingsData.length > 5) {
        settingsData[5] = (settingsData[5] & 0xE0) | (channelValue & 0x1F);
        _broker.dispatch(
          deviceId: _selectedDeviceId,
          name: 'WriteSettings',
          data: settingsData,
          store: false,
        );
      }
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  AppLocalizations.of(context).aprsBeaconSettings,
                  style: DialogStyles.titleStyle,
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).beaconIntro,
                        style: DialogStyles.bodyStyle,
                      ),
                      if (_radioName.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context).beaconRadio(_radioName),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildBeaconSection(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSave ? _onSave : null,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonOk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeaconSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(AppLocalizations.of(context).beaconSection),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildChannelDropdown()),
              const SizedBox(width: 16),
              Expanded(child: _buildPacketFormatDropdown()),
            ],
          ),
          const SizedBox(height: 16),
          _buildIntervalDropdown(),
          const SizedBox(height: 16),
          _buildCallsignField(),
          const SizedBox(height: 16),
          _buildMessageField(),
          const SizedBox(height: 8),
          _buildCheckbox(
            AppLocalizations.of(context).beaconShareLocation,
            _shareLocation,
            (v) => setState(() => _shareLocation = v),
          ),
          _buildCheckbox(
            AppLocalizations.of(context).beaconSendVoltage,
            _sendVoltage,
            (v) => setState(() => _sendVoltage = v),
          ),
          _buildCheckbox(
            AppLocalizations.of(context).beaconAllowPositionCheck,
            _allowPositionCheck,
            (v) => setState(() => _allowPositionCheck = v),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelDropdown() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.packetsColChannel,
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _channelLabels.isEmpty ? null : _channelIndex,
        decoration: _inputDecoration(),
        items: [
          for (int i = 0; i < _channelLabels.length; i++)
            DropdownMenuItem<int>(
              value: i,
              child: Text(
                _channelValues[i] == 0
                    ? l10n.beaconChannelCurrent
                    : _channelLabels[i],
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _controlsEnabled
            ? (value) {
                if (value != null) setState(() => _channelIndex = value);
              }
            : null,
      ),
    );
  }

  Widget _buildPacketFormatDropdown() {
    return _labeled(
      AppLocalizations.of(context).beaconPacketFormat,
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _packetFormatIndex,
        decoration: _inputDecoration(),
        items: [
          for (int i = 0; i < _packetFormatLabels.length; i++)
            DropdownMenuItem<int>(
              value: i,
              child: Text(_packetFormatLabels[i]),
            ),
        ],
        onChanged: _controlsEnabled
            ? (value) {
                if (value != null) setState(() => _packetFormatIndex = value);
              }
            : null,
      ),
    );
  }

  /// Localized label for the beacon interval at [index] into [_intervalSeconds].
  String _intervalLabel(int index) {
    final seconds = _intervalSeconds[index];
    final l10n = AppLocalizations.of(context);
    if (seconds == 0) return l10n.riOff;
    if (seconds < 60) return l10n.beaconEverySeconds(seconds);
    return l10n.beaconEveryMinutes(seconds ~/ 60);
  }

  Widget _buildIntervalDropdown() {
    return _labeled(
      AppLocalizations.of(context).beaconInterval,
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _intervalIndex,
        decoration: _inputDecoration(),
        items: [
          for (int i = 0; i < _intervalSeconds.length; i++)
            DropdownMenuItem<int>(value: i, child: Text(_intervalLabel(i))),
        ],
        onChanged: _controlsEnabled
            ? (value) {
                if (value != null) setState(() => _intervalIndex = value);
              }
            : null,
      ),
    );
  }

  Widget _buildCallsignField() {
    final l10n = AppLocalizations.of(context);
    final invalid = _controlsEnabled && !_callsignValid;
    return _labeled(
      l10n.beaconAprsCallsign,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _callsignController,
            enabled: _controlsEnabled,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toUpperCase()),
              ),
            ],
            decoration: _inputDecoration(
              hintText: l10n.beaconCallsignHint,
              invalid: invalid,
            ),
          ),
          if (invalid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.beaconCallsignInvalid,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageField() {
    return _labeled(
      AppLocalizations.of(context).beaconAprsMessage,
      TextField(
        controller: _messageController,
        enabled: _controlsEnabled,
        maxLength: 18,
        decoration: _inputDecoration(counterText: ''),
      ),
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: _controlsEnabled ? (v) => onChanged(v ?? false) : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: _controlsEnabled ? () => onChanged(!value) : null,
            child: Text(
              label,
              style: TextStyle(color: _controlsEnabled ? null : Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DialogStyles.labelStyle),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade800,
      ),
    );
  }

  InputDecoration _inputDecoration({
    String? hintText,
    String? counterText,
    bool invalid = false,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: invalid ? const Color(0xFFFFE4E1) : Colors.grey.shade100,
      hintText: hintText,
      counterText: counterText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );
  }

  // Helper for section card styling
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
