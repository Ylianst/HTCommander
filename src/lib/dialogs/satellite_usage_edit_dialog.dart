/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../satellite/satellite_models.dart';

/// Opens the editor for a single satellite usage (a frequency / transponder).
///
/// When [existing] is null a new usage is created for [noradId]; otherwise it is
/// edited in place. Returns the resulting [SatelliteTransponder], or null when
/// the dialog is cancelled. Frequencies are shown and entered in MHz and stored
/// in Hz.
Future<SatelliteTransponder?> showSatelliteUsageEditDialog(
  BuildContext context, {
  required int noradId,
  SatelliteTransponder? existing,
}) {
  return showDialog<SatelliteTransponder>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _SatelliteUsageEditDialog(noradId: noradId, existing: existing),
  );
}

/// Common usage categories offered in the dropdown; `Other` reveals a free-text
/// field so any label can be used.
const List<String> _usagePresets = [
  'Repeater',
  'APRS',
  'SSTV',
  'Voice',
  'Beacon',
  'Telemetry',
  'Other',
];

class _SatelliteUsageEditDialog extends StatefulWidget {
  final int noradId;
  final SatelliteTransponder? existing;

  const _SatelliteUsageEditDialog({required this.noradId, this.existing});

  @override
  State<_SatelliteUsageEditDialog> createState() =>
      _SatelliteUsageEditDialogState();
}

class _SatelliteUsageEditDialogState extends State<_SatelliteUsageEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _customUsage;
  late final TextEditingController _name;
  late final TextEditingController _downlink;
  late final TextEditingController _uplink;
  late final TextEditingController _mode;
  late final TextEditingController _ctcss;
  late final TextEditingController _infoUrl;

  late String _usage;
  late bool _inverting;
  late bool _active;

  static String _mhz(int? hz) =>
      hz == null ? '' : (hz / 1000000).toStringAsFixed(4);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final usage = e?.usage ?? 'Repeater';
    final isPreset = _usagePresets.contains(usage);
    _usage = isPreset ? usage : 'Other';
    _customUsage = TextEditingController(text: isPreset ? '' : usage);
    _name = TextEditingController(text: e?.name ?? '');
    _downlink = TextEditingController(text: _mhz(e?.downlinkHz));
    _uplink = TextEditingController(text: _mhz(e?.uplinkHz));
    _mode = TextEditingController(text: e?.mode.isNotEmpty == true ? e!.mode : 'FM');
    _ctcss = TextEditingController(
      text: e?.ctcssHz == null ? '' : e!.ctcssHz!.toStringAsFixed(1),
    );
    _infoUrl = TextEditingController(text: e?.infoUrl ?? '');
    _inverting = e?.inverting ?? false;
    _active = e == null ? true : e.status.toLowerCase() != 'inactive';
  }

  @override
  void dispose() {
    _customUsage.dispose();
    _name.dispose();
    _downlink.dispose();
    _uplink.dispose();
    _mode.dispose();
    _ctcss.dispose();
    _infoUrl.dispose();
    super.dispose();
  }

  int? _parseMhz(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return (v * 1000000).round();
  }

  String? _validateFreq(String? value, {required bool required}) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return required ? 'Required' : null;
    final v = double.tryParse(t);
    if (v == null) return 'Enter a number in MHz';
    if (v <= 0 || v > 3000) return 'Out of range';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final usage = _usage == 'Other'
        ? (_customUsage.text.trim().isEmpty ? 'Other' : _customUsage.text.trim())
        : _usage;
    final name = _name.text.trim();
    final result = SatelliteTransponder(
      noradId: widget.noradId,
      name: name.isEmpty ? usage : name,
      usage: usage,
      uplinkHz: _parseMhz(_uplink.text),
      downlinkHz: _parseMhz(_downlink.text),
      mode: _mode.text.trim().isEmpty ? 'FM' : _mode.text.trim(),
      ctcssHz: double.tryParse(_ctcss.text.trim()),
      inverting: _inverting,
      status: _active ? 'active' : 'inactive',
      infoUrl: _infoUrl.text.trim().isEmpty ? null : _infoUrl.text.trim(),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 600;
    final title = widget.existing == null ? 'Add usage' : 'Edit usage';
    return AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: Text(title),
      content: SizedBox(
        width: compact ? MediaQuery.of(context).size.width : 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _usage,
                  decoration: const InputDecoration(labelText: 'Usage'),
                  items: [
                    for (final u in _usagePresets)
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setState(() => _usage = v ?? _usage),
                ),
                if (_usage == 'Other') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _customUsage,
                    decoration: const InputDecoration(
                      labelText: 'Custom usage label',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _downlink,
                  decoration: const InputDecoration(
                    labelText: 'Downlink / RX (MHz)',
                    helperText: 'Frequency you receive on',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: (v) => _validateFreq(v, required: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _uplink,
                  decoration: const InputDecoration(
                    labelText: 'Uplink / TX (MHz)',
                    helperText: 'Leave blank for receive-only',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: (v) => _validateFreq(v, required: false),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _mode,
                        decoration: const InputDecoration(labelText: 'Mode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ctcss,
                        decoration: const InputDecoration(
                          labelText: 'CTCSS (Hz)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _infoUrl,
                  decoration: const InputDecoration(
                    labelText: 'Info link (optional)',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inverting (linear transponder)'),
                  value: _inverting,
                  onChanged: (v) => setState(() => _inverting = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
