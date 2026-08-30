/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialog_utils.dart';
import 'add_station_dialog.dart';
import '../callsign/callsign_country.dart';
import '../callsign/callsign_record.dart';
import '../l10n/app_localizations.dart';
import '../models/station_info.dart';
import '../services/callsign_lookup_service.dart';
import '../services/data_broker_client.dart';

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

  // When true the dialog shows the database download/update controls instead of
  // the callsign query, so only one action occupies the (small) screen at once.
  bool _showDatabase = false;

  // Per-source database download / update state.
  final Map<CallsignDbSource, bool> _dbBusy = {};
  final Map<CallsignDbSource, double?> _dbProgress = {};
  final Map<CallsignDbSource, String?> _dbStatusMessage = {};
  final Map<CallsignDbSource, bool> _dbStatusIsError = {};
  // True once a check found the database already current; disables the button.
  final Map<CallsignDbSource, bool> _dbUpToDate = {};

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
      _dbUpToDate[source] = false;
    });
    try {
      final manifest = await service.fetchManifest(source);
      final result = await service.update(
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
        // After any successful check/download the database is current, so the
        // button goes straight to a grayed-out "Up to date" rather than a
        // message.
        _dbStatusMessage[source] = null;
        _dbUpToDate[source] = true;
      });
      // Re-run the current query when new data landed.
      if (result != CallsignUpdateResult.upToDate &&
          _searched &&
          _searchedCallsign.isNotEmpty) {
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
    // The database view is only offered on platforms that support downloading a
    // license database; otherwise the toggle is hidden and only the query shows.
    final canManageDatabase = CallsignLookupService.instance.isSupported;
    final showDatabase = _showDatabase && canManageDatabase;

    // Same chrome as the Settings dialog: a rounded surface Dialog with a
    // constrained box, a title header, a scrollable body, and a footer button.
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showDatabase ? l10n.cslSectionTitle : l10n.cslTitle,
                      style: DialogStyles.titleStyle.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (canManageDatabase)
                    IconButton(
                      icon: Icon(
                        showDatabase ? Icons.search : Icons.storage_rounded,
                      ),
                      tooltip: showDatabase
                          ? l10n.cslTitle
                          : l10n.cslSectionTitle,
                      onPressed: () =>
                          setState(() => _showDatabase = !showDatabase),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: showDatabase
                      ? _buildDbControls(l10n, scheme)
                      : _buildQueryView(l10n, scheme),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!showDatabase && _hasResults) ...[
                    PopupMenuButton<StationType>(
                      icon: const Icon(Icons.person_add_alt_1),
                      tooltip: l10n.cslAddContact,
                      onSelected: _addAsContact,
                      itemBuilder: (context) => [
                        PopupMenuItem<StationType>(
                          value: StationType.generic,
                          child: Text(l10n.stationTypeOptionVoice),
                        ),
                        PopupMenuItem<StationType>(
                          value: StationType.aprs,
                          child: Text(l10n.stationTitleAprs),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _copyAll,
                      style: DialogStyles.secondaryButtonStyle(context),
                      child: Text(l10n.apdCopyAll),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (canManageDatabase) ...[
                    TextButton(
                      onPressed: () =>
                          setState(() => _showDatabase = !showDatabase),
                      style: DialogStyles.secondaryButtonStyle(context),
                      child: Text(
                        showDatabase
                            ? l10n.cslButtonLookup
                            : l10n.cslButtonDatabases,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueryView(AppLocalizations l10n, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
          decoration: _inputDecoration(labelText: l10n.cslFieldCallsign)
              .copyWith(
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _lookup,
                ),
              ),
          onSubmitted: (_) => _lookup(),
        ),
        if (_searched) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: _buildResult(l10n, scheme),
          ),
        ],
      ],
    );
  }

  /// Filled, borderless input styling used across the Settings dialog: a soft
  /// container fill, rounded corners, and a primary-coloured focus border.
  InputDecoration _inputDecoration({String? hintText, String? labelText}) {
    return DialogStyles.inputDecoration(
      context,
      hintText: hintText,
      labelText: labelText,
    );
  }

  /// Rounded, subtly-shadowed section card, matching the Settings dialog.
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
        const SizedBox(height: 14),
        _buildAutoUpdateToggle(l10n, scheme),
      ],
    );
  }

  /// "Auto-update on WiFi" preference. When enabled, installed databases are
  /// refreshed in the background while the app runs, but only over a
  /// non-metered connection so mobile data is never spent.
  Widget _buildAutoUpdateToggle(AppLocalizations l10n, ColorScheme scheme) {
    final service = CallsignLookupService.instance;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: _sectionDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: service.autoUpdateOnWifi,
          onChanged: (value) =>
              setState(() => service.autoUpdateOnWifi = value),
          title: Text(
            l10n.cslAutoUpdateWifi,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          subtitle: Text(
            l10n.cslAutoUpdateWifiSubtitle,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ),
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

    // Long-press (touch) or right-click (desktop) on an installed database
    // opens a context menu offering to delete it.
    final canDelete = installed && !busy;
    // Set after a check that found nothing to update; the button then reads
    // "Up to date" and is disabled until the user acts again.
    final upToDate = _dbUpToDate[source] ?? false;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: canDelete
          ? (details) => _showSourceMenu(source, details.globalPosition)
          : null,
      onSecondaryTapDown: canDelete
          ? (details) => _showSourceMenu(source, details.globalPosition)
          : null,
      child: Column(
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
                          ? _installedInfo(l10n, service, source)
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
                onPressed: (busy || upToDate)
                    ? null
                    : () => _downloadOrUpdate(source),
                child: Text(
                  upToDate
                      ? l10n.cslUpToDateButton
                      : (installed ? l10n.cslUpdate : l10n.cslDownload),
                ),
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
      ),
    );
  }

  /// "2026.07.11, 45.6M" — the installed version plus the on-disk size of the
  /// baseline and the overlay (if any) combined, in MB with one decimal.
  String _installedInfo(
    AppLocalizations l10n,
    CallsignLookupService service,
    CallsignDbSource source,
  ) {
    final version = service.installedVersion(source);
    final bytes = service.sizeBytes(source) + service.overlaySizeBytes(source);
    if (bytes <= 0) return l10n.cslInstalledInfo(version);
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return l10n.cslInstalledInfo('$version, ${mb}M');
  }

  /// Shows the per-database context menu (currently just Delete) at [position].
  Future<void> _showSourceMenu(CallsignDbSource source, Offset position) async {
    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              Text(l10n.cslDelete),
            ],
          ),
        ),
      ],
    );
    if (selected == 'delete') {
      await _deleteDatabase(source);
    }
  }

  /// Confirms and deletes the installed [source] database.
  Future<void> _deleteDatabase(CallsignDbSource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cslDeleteTitle),
        content: Text(l10n.cslDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CallsignLookupService.instance.delete(source);
    if (!mounted) return;
    setState(() {
      _dbBusy[source] = false;
      _dbProgress[source] = null;
      _dbStatusMessage[source] = null;
      _dbStatusIsError[source] = false;
      _dbUpToDate[source] = false;
    });
    // Re-run the current query now that the database is gone.
    if (_searched && _searchedCallsign.isNotEmpty) {
      _lookup();
    }
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
      children.add(
        _buildRow(scheme, _Row(l10n.cslFieldCountry, country.country)),
      );
      if (country.continentName.isNotEmpty) {
        children.add(
          _buildRow(
            scheme,
            _Row(l10n.cslFieldContinent, country.continentName),
          ),
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
    return [
      for (final row in _recordPairs(l10n, source, r)) _buildRow(scheme, row),
    ];
  }

  /// The license detail key/value pairs for [r], in display order.
  List<_Row> _recordPairs(
    AppLocalizations l10n,
    CallsignDbSource source,
    CallsignRecord r,
  ) {
    return <_Row>[
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
  }

  /// All currently displayed key/value pairs (callsign, country, and any
  /// license details), used for the "Copy All" action.
  List<_Row> _resultPairs(AppLocalizations l10n) {
    final country = _country;
    final result = _result;
    final pairs = <_Row>[_Row(l10n.cslFieldCallsign, _searchedCallsign)];
    if (country != null) {
      pairs.add(_Row(l10n.cslFieldCountry, country.country));
      if (country.continentName.isNotEmpty) {
        pairs.add(_Row(l10n.cslFieldContinent, country.continentName));
      }
    }
    if (result != null) {
      pairs.addAll(_recordPairs(l10n, result.source, result.record));
    }
    return pairs;
  }

  /// Whether the query view is currently showing result key/value pairs.
  bool get _hasResults =>
      _searched && !_loading && (_country != null || _result != null);

  /// Adds the looked-up callsign to the address book as a contact of [type].
  /// When a station of the same type and callsign already exists it is edited
  /// instead, filling in its name and description from the lookup only when they
  /// are currently empty. Otherwise a new contact is created, prefilled with the
  /// callsign (editable). APRS contacts keep a station id (SSID) typed in the
  /// lookup field, or default to zero when none was given.
  Future<void> _addAsContact(StationType type) async {
    final searched = _searchedCallsign.trim();
    final dash = searched.indexOf('-');
    final hasSsid = dash >= 0 && dash < searched.length - 1;
    final base = dash >= 0 ? searched.substring(0, dash) : searched;
    if (base.isEmpty) return;
    final String callsign;
    if (type == StationType.aprs) {
      callsign = hasSsid ? searched : '$base-0';
    } else {
      callsign = base;
    }

    final broker = DataBrokerClient();
    final stations = <StationInfo>[];
    final raw = broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          stations.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          stations.add(StationInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    // A trailing "-0" APRS SSID is equivalent to no SSID when matching.
    String noZero(String cs) =>
        cs.endsWith('-0') ? cs.substring(0, cs.length - 2) : cs;
    final target = noZero(callsign);
    final existingIndex = stations.indexWhere(
      (s) => s.stationType == type && noZero(s.callsign) == target,
    );

    StationInfo? result;
    if (existingIndex >= 0) {
      final existing = stations[existingIndex];
      // Fill name/description from the lookup only when currently empty; the
      // edit dialog does not auto-fill locked callsigns.
      final record = _result?.record;
      if (record != null) {
        if (existing.name.trim().isEmpty && record.name.isNotEmpty) {
          existing.name = record.name;
        }
        if (existing.description.trim().isEmpty && record.location.isNotEmpty) {
          existing.description = record.location;
        }
      }
      result = await showStationDialog(context, existing: existing);
    } else {
      result = await showStationDialog(
        context,
        fixedType: type,
        initialCallsign: callsign,
      );
    }
    if (result == null || !mounted) {
      broker.dispose();
      return;
    }

    final saved = result;
    stations.removeWhere(
      (s) => s.callsign == saved.callsign && s.stationType == saved.stationType,
    );
    stations.add(saved);
    broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
    broker.dispose();
  }

  /// Copies every displayed key/value pair as tab-separated lines, matching the
  /// Comms details dialog's "Copy All".
  void _copyAll() {
    final l10n = AppLocalizations.of(context);
    final sb = StringBuffer();
    for (final row in _resultPairs(l10n)) {
      sb.write(row.name);
      sb.write('\t');
      sb.write(row.value);
      sb.write('\r\n');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
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
            onPressed: () => Clipboard.setData(ClipboardData(text: row.value)),
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
