/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// `Radio` from radio.dart is not used here, but hide it for consistency with
// the other APRS dialogs so the model type never collides with Material's
// Radio button widget.
import 'dart:convert';

import 'package:flutter/material.dart' hide Radio;

import '../aprs/aprs_symbols.dart';
import '../handlers/software_beacon_config.dart';
import '../services/data_broker_client.dart';
import '../l10n/app_localizations.dart';
import 'aprs_symbol_picker_dialog.dart';
import 'dialog_utils.dart';

/// Shows the software beacon configuration dialog. Lets the user configure the
/// app's own periodic APRS beacon: interval, symbol, message, whether to
/// include the current location and which connected radio to transmit over.
Future<void> showSoftwareBeaconDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const SoftwareBeaconDialog(),
  );
}

/// Beacon interval options in seconds. The first entry (0) disables the beacon.
const List<int> _intervalSeconds = [
  0,
  60,
  120,
  180,
  300,
  600,
  900,
  1200,
  1800,
  3600,
];

class SoftwareBeaconDialog extends StatefulWidget {
  const SoftwareBeaconDialog({super.key});

  @override
  State<SoftwareBeaconDialog> createState() => _SoftwareBeaconDialogState();
}

class _SoftwareBeaconDialogState extends State<SoftwareBeaconDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  final TextEditingController _messageController = TextEditingController();

  String _callsign = '';

  int _selectedRadioId = -1; // -1 = Internet only.
  List<int> _radioIdsList = [];
  Map<int, String> _radioNames = {};

  int _intervalIndex = 0;
  bool _includeLocation = true;
  String _symbolTable = '/';
  String _symbolCode = '-';

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    _callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    _loadRadios();

    final config = _loadConfig();
    _includeLocation = config.includeLocation;
    _symbolTable = config.symbolTable;
    _symbolCode = config.symbolCode;
    _messageController.text = config.message;
    _intervalIndex = _indexForInterval(config.intervalSeconds);

    if (config.radioDeviceId > 0 &&
        _radioIdsList.contains(config.radioDeviceId)) {
      _selectedRadioId = config.radioDeviceId;
    } else if (config.radioDeviceId <= 0) {
      _selectedRadioId = -1;
    } else {
      // Persisted radio no longer connected: fall back to Internet only.
      _selectedRadioId = -1;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _broker.dispose();
    super.dispose();
  }

  SoftwareBeaconConfig _loadConfig() {
    final raw = _broker.getValueDynamic(0, 'SoftwareBeaconConfig', null);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return SoftwareBeaconConfig.fromJson(decoded);
        }
      } catch (_) {
        // Fall through to defaults.
      }
    }
    if (raw is Map<String, dynamic>) return SoftwareBeaconConfig.fromJson(raw);
    return const SoftwareBeaconConfig();
  }

  int _indexForInterval(int seconds) {
    var index = 0;
    for (int i = 0; i < _intervalSeconds.length; i++) {
      if (seconds >= _intervalSeconds[i]) index = i;
    }
    return index;
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(_loadRadios);
  }

  void _loadRadios() {
    final raw = _broker.getValueDynamic(1, 'ConnectedRadios');
    final ids = <int>[];
    final names = <int, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['DeviceId'] is int) {
          final id = item['DeviceId'] as int;
          ids.add(id);
          names[id] = (item['FriendlyName'] as String?) ?? 'Radio $id';
        }
      }
    }
    _radioIdsList = ids;
    _radioNames = names;
    if (_selectedRadioId > 0 && !ids.contains(_selectedRadioId)) {
      _selectedRadioId = -1;
    }
  }

  bool get _hasCallsign => _callsign.isNotEmpty;

  bool get _canSave => _hasCallsign;

  Future<void> _pickSymbol() async {
    final chosen = await showAprsSymbolPicker(
      context,
      selectedTable: _symbolTable,
      selectedCode: _symbolCode,
    );
    if (chosen != null && mounted) {
      setState(() {
        _symbolTable = chosen.table;
        _symbolCode = chosen.code;
      });
    }
  }

  void _onSave() {
    final config = SoftwareBeaconConfig(
      intervalSeconds: _intervalSeconds[_intervalIndex],
      symbolTable: _symbolTable,
      symbolCode: _symbolCode,
      message: _messageController.text.trim(),
      includeLocation: _includeLocation,
      radioDeviceId: _selectedRadioId,
    );

    _broker.dispatch(
      deviceId: 0,
      name: 'SoftwareBeaconConfig',
      data: jsonEncode(config.toJson()),
      store: true,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  l10n.softwareBeaconTitle,
                  style: DialogStyles.titleStyle,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.softwareBeaconIntro,
                        style: DialogStyles.bodyStyle,
                      ),
                      const SizedBox(height: 16),
                      _buildSection(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSave ? _onSave : null,
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

  Widget _buildSection() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_hasCallsign) ...[
            _warning(l10n.softwareBeaconNoCallsign),
            const SizedBox(height: 12),
          ],
          _buildIntervalDropdown(),
          const SizedBox(height: 16),
          _buildRadioDropdown(),
          const SizedBox(height: 16),
          _buildSymbolField(),
          const SizedBox(height: 16),
          _buildMessageField(),
          const SizedBox(height: 8),
          _buildCheckbox(
            l10n.softwareBeaconIncludeLocation,
            _includeLocation,
            (v) => setState(() => _includeLocation = v),
          ),
        ],
      ),
    );
  }

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
        onChanged: (value) {
          if (value != null) setState(() => _intervalIndex = value);
        },
      ),
    );
  }

  Widget _buildRadioDropdown() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.softwareBeaconRadio,
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _radioIdsList.contains(_selectedRadioId)
            ? _selectedRadioId
            : -1,
        decoration: _inputDecoration(),
        items: [
          DropdownMenuItem<int>(
            value: -1,
            child: Text(
              l10n.softwareBeaconInternetOnly,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final id in _radioIdsList)
            DropdownMenuItem<int>(
              value: id,
              child: Text(
                _radioNames[id] ?? 'Radio $id',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _selectedRadioId = value);
        },
      ),
    );
  }

  Widget _buildSymbolField() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final symbol = aprsSymbolFor(_symbolTable, _symbolCode);
    final id = '$_symbolTable$_symbolCode';
    final name = aprsSymbolNameFor(_symbolTable, _symbolCode);
    return _labeled(
      l10n.softwareBeaconSymbol,
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _pickSymbol,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: (symbol?.hasVisual ?? false)
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: aprsSymbolWidgetFor(
                          _symbolTable,
                          _symbolCode,
                          color: scheme.onSurface,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  id,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageField() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.softwareBeaconMessage,
      TextField(
        controller: _messageController,
        maxLength: 60,
        decoration: _inputDecoration(hintText: l10n.softwareBeaconMessageHint)
            .copyWith(counterText: ''),
      ),
    );
  }

  Widget _warning(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(label),
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

  InputDecoration _inputDecoration({String? hintText}) {
    return DialogStyles.inputDecoration(
      context,
      hintText: hintText,
      focusColor: Colors.blue,
    );
  }

  BoxDecoration _sectionDecoration() {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}
