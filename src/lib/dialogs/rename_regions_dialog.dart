/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Lets the user rename the radio's regions. The current region names are read
from the DataBroker (per-device `RegionNames` value, populated by the radio's
READ_REGION_NAME replies). Edited names are written back to the radio via the
`SetRegionName` event, which the radio handles with a WRITE_REGION_NAME command.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Maximum number of characters a region name may contain (matches the radio's
/// 10-byte region name field).
const int _kMaxRegionNameLength = 10;

/// Shows the Rename Regions dialog. [deviceId] selects which radio's regions
/// are edited; [regionCount] is the number of regions the radio reports.
Future<void> showRenameRegionsDialog(
  BuildContext context, {
  required int deviceId,
  required int regionCount,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _RenameRegionsDialog(deviceId: deviceId, regionCount: regionCount),
  );
}

class _RenameRegionsDialog extends StatefulWidget {
  final int deviceId;
  final int regionCount;
  const _RenameRegionsDialog({
    required this.deviceId,
    required this.regionCount,
  });

  @override
  State<_RenameRegionsDialog> createState() => _RenameRegionsDialogState();
}

class _RenameRegionsDialogState extends State<_RenameRegionsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  /// One controller per region, seeded with the current name.
  late final List<TextEditingController> _controllers;

  /// The names as last seen from the radio, used to detect edits on save.
  late List<String> _originalNames;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.regionCount,
      (_) => TextEditingController(),
    );
    _originalNames = List<String>.filled(widget.regionCount, '');
    _applyRegionNames(_readRegionNames());

    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'RegionNames',
      callback: _onRegionNamesChanged,
    );
  }

  @override
  void dispose() {
    _broker.unsubscribe(widget.deviceId, 'RegionNames');
    for (final c in _controllers) {
      c.dispose();
    }
    _broker.dispose();
    super.dispose();
  }

  /// Reads the current region names list from the broker.
  List<String?> _readRegionNames() {
    final data = _broker.getValueDynamic(widget.deviceId, 'RegionNames');
    if (data is List) {
      return data.map((e) => e is String ? e : null).toList();
    }
    return const [];
  }

  void _onRegionNamesChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != widget.deviceId) return;
    if (data is List) {
      setState(() {
        _applyRegionNames(data.map((e) => e is String ? e : null).toList());
      });
    }
  }

  /// Copies the radio's region names into the text fields. Only updates a field
  /// when its underlying value changed, so a live refresh does not clobber an
  /// edit the user is in the middle of typing.
  void _applyRegionNames(List<String?> names) {
    for (int i = 0; i < widget.regionCount; i++) {
      final radioName = (i < names.length ? names[i] : null) ?? '';
      if (_originalNames[i] != radioName) {
        _originalNames[i] = radioName;
        // Only overwrite the field if the user hasn't diverged from the old
        // radio value (i.e. the field still matches what the radio had).
        _controllers[i].text = radioName;
      }
    }
  }

  void _onSave() {
    for (int i = 0; i < widget.regionCount; i++) {
      final newName = _controllers[i].text.trim();
      if (newName != _originalNames[i]) {
        _broker.dispatch(
          deviceId: widget.deviceId,
          name: 'SetRegionName',
          data: {'index': i, 'name': newName},
          store: false,
        );
      }
    }
    Navigator.of(context).pop();
  }

  // --- Styling helpers (mirrors SettingsDialog) --------------------------

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      counterText: '',
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                l10n.regionsTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.regionsMaxChars(_kMaxRegionNameLength),
                style: DialogStyles.bodyStyle,
              ),
              const SizedBox(height: 16),
              // Region name fields
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _sectionDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < widget.regionCount; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  l10n.regionLabel(i + 1),
                                  style: DialogStyles.labelStyle,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _controllers[i],
                                  maxLength: _kMaxRegionNameLength,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(
                                      _kMaxRegionNameLength,
                                    ),
                                  ],
                                  decoration: _inputDecoration(
                                    hintText: l10n.regionLabel(i + 1),
                                  ),
                                  style: DialogStyles.bodyStyle,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSave,
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
}
