/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../callsign/callsign_record.dart';
import '../l10n/app_localizations.dart';
import '../services/callsign_lookup_service.dart';

/// Dialog that shows offline FCC amateur license details for a callsign.
///
/// Performs the lookup asynchronously against [CallsignLookupService] and
/// renders the result as a two-column list, matching the style of
/// [AprsDetailsDialog].
class CallsignLookupDialog extends StatefulWidget {
  final String callsign;

  const CallsignLookupDialog({super.key, required this.callsign});

  /// Shows the lookup dialog for [callsign].
  static Future<void> show(BuildContext context, String callsign) {
    return showDialog<void>(
      context: context,
      builder: (context) => CallsignLookupDialog(callsign: callsign),
    );
  }

  @override
  State<CallsignLookupDialog> createState() => _CallsignLookupDialogState();
}

class _CallsignLookupDialogState extends State<CallsignLookupDialog> {
  bool _loading = true;
  CallsignRecord? _record;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final record = await CallsignLookupService.instance.lookup(widget.callsign);
    if (!mounted) return;
    setState(() {
      _record = record;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = CallsignLookupService.instance;

    return AlertDialog(
      title: Text(l10n.cslTitle),
      content: SizedBox(
        width: 420,
        child: _buildBody(l10n, scheme, service),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ColorScheme scheme,
    CallsignLookupService service,
  ) {
    if (!service.isSupported) {
      return _message(l10n.cslUnsupported, scheme);
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(l10n.cslLookingUp(widget.callsign))),
          ],
        ),
      );
    }
    if (!service.isAvailable) {
      return _message(l10n.cslNoDatabase, scheme);
    }
    final record = _record;
    if (record == null) {
      return _message(l10n.cslNotFound(widget.callsign), scheme);
    }
    return _buildRecord(l10n, scheme, record);
  }

  Widget _message(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }

  Widget _buildRecord(
    AppLocalizations l10n,
    ColorScheme scheme,
    CallsignRecord r,
  ) {
    final rows = <_Row>[
      _Row(l10n.cslFieldCallsign, r.callsign),
      if (r.name.isNotEmpty) _Row(l10n.cslFieldName, r.name),
      if (r.operatorClassName.isNotEmpty)
        _Row(l10n.cslFieldClass, r.operatorClassName),
      if (r.statusName.isNotEmpty) _Row(l10n.cslFieldStatus, r.statusName),
      if (r.location.isNotEmpty) _Row(l10n.cslFieldLocation, r.location),
      if (r.expireDateFormatted.isNotEmpty)
        _Row(l10n.cslFieldExpires, r.expireDateFormatted),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) _buildRow(scheme, row),
      ],
    );
  }

  Widget _buildRow(ColorScheme scheme, _Row row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              row.name,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(row.value)),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: MaterialLocalizations.of(context).copyButtonLabel,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: row.value)),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final String name;
  final String value;
  const _Row(this.name, this.value);
}
