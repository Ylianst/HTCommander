/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../callsign/callsign_country.dart';
import '../callsign/callsign_record.dart';
import '../l10n/app_localizations.dart';
import '../services/callsign_lookup_service.dart';

/// Standalone offline callsign lookup dialog.
///
/// Lets the user type a callsign and view the matching amateur license details
/// from the offline databases (US/FCC and Canada/ISED), and download or update
/// each database. Opened from the Debug tab menu.
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
  CallsignLookupResult? _result;
  CountryInfo? _country;

  // Per-source database download / update state.
  final Map<CallsignDbSource, bool> _dbBusy = {};
  final Map<CallsignDbSource, double?> _dbProgress = {};
  final Map<CallsignDbSource, String?> _dbStatusMessage = {};
  final Map<CallsignDbSource, bool> _dbStatusIsError = {};

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
      _result = null;
      // Country resolves instantly from the bundled in-memory table and works
      // offline on every platform, regardless of the license databases.
      _country = CallsignCountryLookup.instance.lookup(callsign);
    });
    final result = await CallsignLookupService.instance.lookup(callsign);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _downloadOrUpdate(CallsignDbSource source) async {
    final l10n = AppLocalizations.of(context);
    final service = CallsignLookupService.instance;
    setState(() {
      _dbBusy[source] = true;
      _dbProgress[source] = 0;
      _dbStatusMessage[source] = null;
      _dbStatusIsError[source] = false;
    });
    try {
      final manifest = await service.fetchManifest(source);
      if (service.isSourceAvailable(source) &&
          service.installedVersion(source) == manifest.version) {
        if (!mounted) return;
        setState(() {
          _dbBusy[source] = false;
          _dbStatusMessage[source] = l10n.cslUpToDate;
        });
        return;
      }
      await service.download(
        source,
        manifest,
        progress: (received, total) {
          if (!mounted) return;
          setState(
            () => _dbProgress[source] = total > 0 ? received / total : null,
          );
        },
      );
      if (!mounted) return;
      setState(() {
        _dbBusy[source] = false;
        _dbProgress[source] = null;
        _dbStatusMessage[source] = null;
      });
      // Re-run the current query now that data is available.
      if (_searched && _searchedCallsign.isNotEmpty) {
        _lookup();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dbBusy[source] = false;
        _dbProgress[source] = null;
        _dbStatusMessage[source] = l10n.cslDownloadFailed(e.toString());
        _dbStatusIsError[source] = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.cslTitle),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SizedBox(
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
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _lookup,
                  ),
                ),
                onSubmitted: (_) => _lookup(),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildResult(l10n, scheme),
                ),
              ),
              const Divider(height: 16),
              _buildDbControls(l10n, scheme),
            ],
          ),
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

  Widget _buildDbControls(AppLocalizations l10n, ColorScheme scheme) {
    final service = CallsignLookupService.instance;
    if (!service.isSupported) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final source in CallsignDbSource.values) ...[
          if (source != CallsignDbSource.values.first)
            const SizedBox(height: 10),
          _buildSourceControl(l10n, scheme, source),
        ],
      ],
    );
  }

  Widget _buildSourceControl(
    AppLocalizations l10n,
    ColorScheme scheme,
    CallsignDbSource source,
  ) {
    final service = CallsignLookupService.instance;
    final installed = service.isSourceAvailable(source);
    final busy = _dbBusy[source] ?? false;
    final progress = _dbProgress[source];
    final statusMessage = _dbStatusMessage[source];
    final statusIsError = _dbStatusIsError[source] ?? false;
    final label = switch (source) {
      CallsignDbSource.us => l10n.cslSourceUs,
      CallsignDbSource.canada => l10n.cslSourceCanada,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    installed
                        ? l10n.cslInstalledInfo(
                            service.installedVersion(source),
                            service.recordCount(source).toString(),
                          )
                        : l10n.cslNotInstalled,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: busy ? null : () => _downloadOrUpdate(source),
              child: Text(installed ? l10n.cslUpdate : l10n.cslDownload),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 6),
          Text(
            progress != null
                ? l10n.cslDownloading((progress * 100).toStringAsFixed(0))
                : l10n.cslInstalling,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        if (statusMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            statusMessage,
            style: TextStyle(
              color: statusIsError ? scheme.error : scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResult(AppLocalizations l10n, ColorScheme scheme) {
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

    final country = _country;
    final result = _result;
    if (country == null && result == null) {
      return _message(l10n.cslNotFound(_searchedCallsign), scheme);
    }

    final children = <Widget>[
      _buildRow(scheme, _Row(l10n.cslFieldCallsign, _searchedCallsign)),
    ];

    // Country / DXCC entity is always shown when known (offline, all platforms).
    if (country != null) {
      children.add(_buildRow(scheme, _Row(l10n.cslFieldCountry, country.country)));
      if (country.continentName.isNotEmpty) {
        children.add(
          _buildRow(scheme, _Row(l10n.cslFieldContinent, country.continentName)),
        );
      }
    }

    // Extra license details, only when a database provided a record. The header
    // and fields shown depend on which country's database matched.
    if (result != null) {
      final heading = switch (result.source) {
        CallsignDbSource.us => l10n.cslUsDetails,
        CallsignDbSource.canada => l10n.cslCaDetails,
      };
      children.add(const Divider(height: 16));
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            heading,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
      children.addAll(_recordRows(l10n, scheme, result.source, result.record));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _message(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }

  List<Widget> _recordRows(
    AppLocalizations l10n,
    ColorScheme scheme,
    CallsignDbSource source,
    CallsignRecord r,
  ) {
    final rows = <_Row>[
      if (r.name.isNotEmpty) _Row(l10n.cslFieldName, r.name),
      // US records carry an operator class + license status; Canadian records
      // carry a set of qualifications and never expire.
      if (source == CallsignDbSource.us) ...[
        if (r.operatorClassName.isNotEmpty)
          _Row(l10n.cslFieldClass, r.operatorClassName),
        if (r.statusName.isNotEmpty) _Row(l10n.cslFieldStatus, r.statusName),
      ] else ...[
        if (r.qualificationsName.isNotEmpty)
          _Row(l10n.cslFieldQualifications, r.qualificationsName),
      ],
      if (r.location.isNotEmpty) _Row(l10n.cslFieldLocation, r.location),
      if (source == CallsignDbSource.us && r.expireDateFormatted.isNotEmpty)
        _Row(l10n.cslFieldExpires, r.expireDateFormatted),
    ];
    return [for (final row in rows) _buildRow(scheme, row)];
  }

  Widget _buildRow(ColorScheme scheme, _Row row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              row.name,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              row.value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 15),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
