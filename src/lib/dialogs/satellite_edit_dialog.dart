/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../satellite/satellite_models.dart';
import 'satellite_usage_edit_dialog.dart';

/// Result of the satellite editor: the edited [info] plus whether its orbit
/// should be pinned (the online TLE must not overwrite it).
class SatelliteEditResult {
  final SatelliteInfo info;
  final bool pinOrbit;
  const SatelliteEditResult(this.info, this.pinOrbit);
}

/// Opens the editor for a whole satellite: its name, orbital elements (TLE) and
/// the list of usages (frequencies). When [existing] is null a new satellite is
/// created. Returns a [SatelliteEditResult], or null when cancelled.
Future<SatelliteEditResult?> showSatelliteEditDialog(
  BuildContext context, {
  SatelliteInfo? existing,
}) {
  return showDialog<SatelliteEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SatelliteEditDialog(existing: existing),
  );
}

class _SatelliteEditDialog extends StatefulWidget {
  final SatelliteInfo? existing;

  const _SatelliteEditDialog({this.existing});

  @override
  State<_SatelliteEditDialog> createState() => _SatelliteEditDialogState();
}

class _SatelliteEditDialogState extends State<_SatelliteEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final List<SatelliteTransponder> _usages;
  String? _usageError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.tle.name ?? '');
    _line1 = TextEditingController(text: e?.tle.line1 ?? '');
    _line2 = TextEditingController(text: e?.tle.line2 ?? '');
    _usages = List<SatelliteTransponder>.of(e?.transponders ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _line1.dispose();
    _line2.dispose();
    super.dispose();
  }

  /// Parses the current name + TLE lines into a [SatelliteTle], or null when the
  /// lines don't form a valid three-line element.
  SatelliteTle? _parseTle() {
    final tles = SatelliteTle.parseThreeLine(
      '${_name.text.trim()}\n${_line1.text.trim()}\n${_line2.text.trim()}',
    );
    return tles.isEmpty ? null : tles.first;
  }

  int _currentNorad() => _parseTle()?.noradId ?? widget.existing?.noradId ?? 0;

  String? _validateLine(String? value, String prefix) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return 'Required';
    if (!t.startsWith(prefix)) return 'Must start with "$prefix"';
    return null;
  }

  Future<void> _addUsage() async {
    final norad = _currentNorad();
    final usage = await showSatelliteUsageEditDialog(context, noradId: norad);
    if (usage == null) return;
    setState(() {
      _usages.add(usage);
      _usageError = null;
    });
  }

  Future<void> _editUsage(int index) async {
    final usage = await showSatelliteUsageEditDialog(
      context,
      noradId: _currentNorad(),
      existing: _usages[index],
    );
    if (usage == null) return;
    setState(() => _usages[index] = usage);
  }

  void _deleteUsage(int index) => setState(() => _usages.removeAt(index));

  void _submit() {
    final valid = _formKey.currentState!.validate();
    final tle = _parseTle();
    setState(() {
      _usageError = _usages.isEmpty ? 'Add at least one usage.' : null;
    });
    if (!valid || tle == null || _usages.isEmpty) return;

    // Re-key each usage to the (possibly new) NORAD id so a pasted TLE and its
    // usages stay consistent.
    final usages = [
      for (final u in _usages)
        SatelliteTransponder(
          noradId: tle.noradId,
          name: u.name,
          usage: u.usage,
          uplinkHz: u.uplinkHz,
          downlinkHz: u.downlinkHz,
          mode: u.mode,
          ctcssHz: u.ctcssHz,
          inverting: u.inverting,
          status: u.status,
          infoUrl: u.infoUrl,
        ),
    ];

    final original = widget.existing?.tle;
    final orbitChanged = original == null ||
        original.line1.trim() != tle.line1 ||
        original.line2.trim() != tle.line2 ||
        original.name.trim() != tle.name;

    Navigator.of(context).pop(
      SatelliteEditResult(
        SatelliteInfo(tle: tle, transponders: usages),
        orbitChanged,
      ),
    );
  }

  String _usageSummary(SatelliteTransponder t) {
    String mhz(int? hz) => hz == null ? '—' : (hz / 1000000).toStringAsFixed(3);
    final rx = mhz(t.downlinkHz);
    final tx = t.uplinkHz == null ? 'RX only' : '${mhz(t.uplinkHz)} TX';
    return '$rx RX  •  $tx';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 600;
    final media = MediaQuery.of(context).size;
    final isNew = widget.existing == null;

    return AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: Text(isNew ? 'Add satellite' : 'Edit satellite'),
      content: SizedBox(
        width: compact ? media.width : 520,
        height: compact ? media.height - 120 : 560,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Orbital elements (TLE)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _line1,
                        decoration: const InputDecoration(
                          labelText: 'TLE line 1',
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        validator: (v) => _validateLine(v, '1 '),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _line2,
                        decoration: const InputDecoration(
                          labelText: 'TLE line 2',
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        validator: (v) => _validateLine(v, '2 '),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'NORAD ${_currentNorad() == 0 ? '—' : _currentNorad()}. '
                        'Paste a two-line element from Celestrak or AMSAT.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Usages & frequencies',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addUsage,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      if (_usageError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _usageError!,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ),
                      if (_usages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No usages yet.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      else
                        for (var i = 0; i < _usages.length; i++)
                          Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _usages[i].usage,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(_usageSummary(_usages[i])),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    tooltip: 'Edit usage',
                                    onPressed: () => _editUsage(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    tooltip: 'Delete usage',
                                    onPressed: () => _deleteUsage(i),
                                  ),
                                ],
                              ),
                              onTap: () => _editUsage(i),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
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
