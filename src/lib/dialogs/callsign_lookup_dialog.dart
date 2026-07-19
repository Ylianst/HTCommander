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

/// Standalone, experimental offline callsign lookup dialog.
///
/// Lets the user type a callsign and view the matching FCC amateur license
/// details from the offline database. Opened from the Debug tab menu.
class CallsignLookupDialog extends StatefulWidget {
  /// Optional callsign to prefill and look up immediately.
  final String? initialCallsign;

  const CallsignLookupDialog({super.key, this.initialCallsign});

  /// Shows the lookup dialog. When [initialCallsign] is provided it is prefilled
  /// and looked up right away.
  static Future<void> show(BuildContext context, {String? initialCallsign}) {
    return showDialog<void>(
      context: context,
      builder: (context) =>
          CallsignLookupDialog(initialCallsign: initialCallsign),
    );
  }

  @override
  State<CallsignLookupDialog> createState() => _CallsignLookupDialogState();
}

class _CallsignLookupDialogState extends State<CallsignLookupDialog> {
  late final TextEditingController _controller;

  bool _searched = false;
  bool _loading = false;
  String _searchedCallsign = '';
  CallsignRecord? _record;

  // Database download / update state.
  bool _dbBusy = false;
  double? _dbProgress; // 0..1, or null when indeterminate / installing
  String? _dbStatusMessage;
  bool _dbStatusIsError = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCallsign ?? '');
    if ((widget.initialCallsign ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final callsign = _controller.text.trim();
    if (callsign.isEmpty) return;
    setState(() {
      _searched = true;
      _loading = true;
      _searchedCallsign = callsign;
      _record = null;
    });
    final record = await CallsignLookupService.instance.lookup(callsign);
    if (!mounted) return;
    setState(() {
      _record = record;
      _loading = false;
    });
  }

  Future<void> _downloadOrUpdate() async {
    final l10n = AppLocalizations.of(context);
    final service = CallsignLookupService.instance;
    setState(() {
      _dbBusy = true;
      _dbProgress = 0;
      _dbStatusMessage = null;
      _dbStatusIsError = false;
    });
    try {
      final manifest = await service.fetchManifest();
      if (service.isAvailable && service.installedVersion == manifest.version) {
        if (!mounted) return;
        setState(() {
          _dbBusy = false;
          _dbStatusMessage = l10n.cslUpToDate;
        });
        return;
      }
      await service.download(
        manifest,
        progress: (received, total) {
          if (!mounted) return;
          setState(() => _dbProgress = total > 0 ? received / total : null);
        },
      );
      if (!mounted) return;
      setState(() {
        _dbBusy = false;
        _dbProgress = null;
        _dbStatusMessage = null;
      });
      // Re-run the current query now that data is available.
      if (_searched && _searchedCallsign.isNotEmpty) {
        _lookup();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dbBusy = false;
        _dbProgress = null;
        _dbStatusMessage = l10n.cslDownloadFailed(e.toString());
        _dbStatusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.cslTitle)),
          _experimentalBadge(scheme),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              decoration: InputDecoration(
                labelText: l10n.cslFieldCallsign,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _lookup,
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 16),
            _buildResult(l10n, scheme),
            const Divider(height: 24),
            _buildDbControls(l10n, scheme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _experimentalBadge(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'EXPERIMENTAL',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onTertiaryContainer,
        ),
      ),
    );
  }

  Widget _buildDbControls(AppLocalizations l10n, ColorScheme scheme) {
    final service = CallsignLookupService.instance;
    if (!service.isSupported) return const SizedBox.shrink();
    final installed = service.isAvailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                installed
                    ? l10n.cslInstalledInfo(
                        service.installedVersion,
                        service.recordCount.toString(),
                      )
                    : l10n.cslNotInstalled,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _dbBusy ? null : _downloadOrUpdate,
              child: Text(installed ? l10n.cslUpdate : l10n.cslDownload),
            ),
          ],
        ),
        if (_dbBusy) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _dbProgress),
          const SizedBox(height: 6),
          Text(
            _dbProgress != null
                ? l10n.cslDownloading((_dbProgress! * 100).toStringAsFixed(0))
                : l10n.cslInstalling,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        if (_dbStatusMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _dbStatusMessage!,
            style: TextStyle(
              color: _dbStatusIsError ? scheme.error : scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResult(AppLocalizations l10n, ColorScheme scheme) {
    final service = CallsignLookupService.instance;
    if (!service.isSupported) {
      return _message(l10n.cslUnsupported, scheme);
    }
    if (!service.isAvailable) {
      return _message(l10n.cslNoDatabase, scheme);
    }
    if (!_searched) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(l10n.cslLookingUp(_searchedCallsign))),
          ],
        ),
      );
    }
    final record = _record;
    if (record == null) {
      return _message(l10n.cslNotFound(_searchedCallsign), scheme);
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

/// Uppercases text as it is typed (callsigns are always upper-case).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
