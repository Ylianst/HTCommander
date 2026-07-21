/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// `Radio` from radio.dart collides with Material's Radio button widget, which
// this dialog does not use; hide it so the radio model type is unambiguous.
import 'dart:convert';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';

import '../handlers/digipeater_config.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../services/data_broker_client.dart';
import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';

/// Shows the digipeater configuration dialog. Lets the user enable the APRS
/// digipeater, choose the target radio, configure the digipeater identity
/// (SSID appended to the global callsign) and the repeating behaviour.
Future<void> showDigipeaterDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const DigipeaterDialog(),
  );
}

class DigipeaterDialog extends StatefulWidget {
  const DigipeaterDialog({super.key});

  @override
  State<DigipeaterDialog> createState() => _DigipeaterDialogState();
}

class _DigipeaterDialogState extends State<DigipeaterDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  final TextEditingController _maxHopsController = TextEditingController();
  final TextEditingController _dedupController = TextEditingController();
  final TextEditingController _aliasesController = TextEditingController();

  String _callsign = '';

  int _selectedDeviceId = -1;
  List<int> _radioIdsList = [];
  Map<int, String> _radioNames = {};

  bool _enabled = false;
  bool _fillInOnly = false;
  bool _handleWideN = true;
  bool _substituteOwnCall = true;

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
    _fillInOnly = config.fillInOnly;
    _handleWideN = config.handleWideN;
    _substituteOwnCall = config.substituteOwnCall;
    _maxHopsController.text = config.maxHops.toString();
    _dedupController.text = config.dedupSeconds.toString();
    _aliasesController.text = config.aliases.join(', ');

    // Prefer the persisted radio, else the currently selected radio.
    if (config.radioDeviceId > 0 &&
        _radioIdsList.contains(config.radioDeviceId)) {
      _selectedDeviceId = config.radioDeviceId;
    } else {
      _selectedDeviceId = _resolveCurrentRadioId();
    }

    // Reflect the real state: the checkbox is only checked when the selected
    // radio is actually locked for the digipeater, not merely when the config
    // says so (a persisted "enabled" may never have locked the radio if it was
    // not ready at startup).
    _enabled = _isDigipeaterActive(_selectedDeviceId);
  }

  @override
  void dispose() {
    _maxHopsController.dispose();
    _dedupController.dispose();
    _aliasesController.dispose();
    _broker.dispose();
    super.dispose();
  }

  DigipeaterConfig _loadConfig() {
    final raw = _broker.getValueDynamic(0, 'DigipeaterConfig', null);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return DigipeaterConfig.fromJson(decoded);
        }
      } catch (_) {
        // Fall through to defaults.
      }
    }
    if (raw is Map<String, dynamic>) return DigipeaterConfig.fromJson(raw);
    return const DigipeaterConfig();
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
    if (!ids.contains(_selectedDeviceId)) {
      _selectedDeviceId = ids.isNotEmpty ? ids.first : -1;
    }
  }

  int _resolveCurrentRadioId() {
    final selected =
        _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    if (selected > 0 && _radioIdsList.contains(selected)) return selected;
    return _radioIdsList.isNotEmpty ? _radioIdsList.first : -1;
  }

  bool _radioHasAprsChannel(int deviceId) {
    if (deviceId <= 0) return false;
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return false;
    return channels.any((c) => c.name == 'APRS');
  }

  /// Whether [deviceId] is currently locked for the digipeater usage.
  bool _isDigipeaterActive(int deviceId) {
    if (deviceId <= 0) return false;
    final lock = _broker.getJsonValue<RadioLockState>(
      deviceId,
      'LockState',
      (json) => RadioLockState.fromJson(json),
    );
    return lock != null && lock.isLocked && lock.usage == 'Digipeater';
  }

  bool get _hasCallsign => _callsign.isNotEmpty;

  bool get _hasAprsChannel => _radioHasAprsChannel(_selectedDeviceId);

  bool get _aliasesValid {
    for (final alias in _parsedAliases()) {
      if (AX25Address.parse(alias) == null) return false;
    }
    return true;
  }

  List<String> _parsedAliases() {
    return _aliasesController.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool get _canSave {
    if (!_hasCallsign) return false;
    if (!_aliasesValid) return false;
    // If enabling, a radio with an APRS channel is required.
    if (_enabled && (_selectedDeviceId <= 0 || !_hasAprsChannel)) return false;
    return true;
  }

  void _onSave() {
    final maxHops = (int.tryParse(_maxHopsController.text) ?? 2).clamp(1, 7);
    final dedup = (int.tryParse(_dedupController.text) ?? 30).clamp(0, 3600);

    final config = DigipeaterConfig(
      enabled: _enabled,
      radioDeviceId: _selectedDeviceId,
      fillInOnly: _fillInOnly,
      handleWideN: _handleWideN,
      maxHops: maxHops,
      substituteOwnCall: _substituteOwnCall,
      aliases: _parsedAliases(),
      dedupSeconds: dedup,
    );

    _broker.dispatch(
      deviceId: 0,
      name: 'DigipeaterConfig',
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
                  l10n.digipeaterTitle,
                  style: DialogStyles.titleStyle,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.digipeaterIntro, style: DialogStyles.bodyStyle),
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
            _warning(l10n.digipeaterNoCallsign),
            const SizedBox(height: 12),
          ],
          _buildRadioDropdown(),
          if (_enabled && _selectedDeviceId > 0 && !_hasAprsChannel) ...[
            const SizedBox(height: 8),
            _warning(l10n.digipeaterNoAprsChannel),
          ],
          const SizedBox(height: 16),
          _buildCheckbox(
            l10n.digipeaterEnable,
            _enabled,
            (v) => setState(() => _enabled = v),
            enabled: true,
          ),
          _buildCheckbox(
            l10n.digipeaterHandleWideN,
            _handleWideN,
            (v) => setState(() => _handleWideN = v),
          ),
          _buildCheckbox(
            l10n.digipeaterFillIn,
            _fillInOnly,
            (v) => setState(() => _fillInOnly = v),
          ),
          _buildCheckbox(
            l10n.digipeaterSubstituteCall,
            _substituteOwnCall,
            (v) => setState(() => _substituteOwnCall = v),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildMaxHopsField()),
              const SizedBox(width: 16),
              Expanded(child: _buildDedupField()),
            ],
          ),
          const SizedBox(height: 16),
          _buildAliasesField(),
        ],
      ),
    );
  }

  Widget _buildRadioDropdown() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.digipeaterRadio,
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _radioIdsList.contains(_selectedDeviceId)
            ? _selectedDeviceId
            : null,
        decoration: _inputDecoration(),
        items: [
          for (final id in _radioIdsList)
            DropdownMenuItem<int>(
              value: id,
              child: Text(
                _radioNames[id] ?? 'Radio $id',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _radioIdsList.isEmpty
            ? null
            : (value) {
                if (value != null) {
                  setState(() {
                    _selectedDeviceId = value;
                    // The lock is per-radio, so the checkbox must follow the
                    // newly selected radio's actual lock state.
                    _enabled = _isDigipeaterActive(value);
                  });
                }
              },
      ),
    );
  }

  Widget _buildMaxHopsField() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.digipeaterMaxHops,
      TextField(
        controller: _maxHopsController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecoration(),
      ),
    );
  }

  Widget _buildDedupField() {
    final l10n = AppLocalizations.of(context);
    return _labeled(
      l10n.digipeaterDedupSeconds,
      TextField(
        controller: _dedupController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecoration(),
      ),
    );
  }

  Widget _buildAliasesField() {
    final l10n = AppLocalizations.of(context);
    final invalid = !_aliasesValid;
    return _labeled(
      l10n.digipeaterAliases,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _aliasesController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9,\-\s]')),
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toUpperCase()),
              ),
            ],
            decoration: _inputDecoration(
              hintText: l10n.digipeaterAliasesHint,
              invalid: invalid,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (invalid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.digipeaterAliasesInvalid,
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

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
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

  InputDecoration _inputDecoration({
    String? hintText,
    bool invalid = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor:
          invalid ? scheme.errorContainer : scheme.surfaceContainerHighest,
      hintText: hintText,
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
