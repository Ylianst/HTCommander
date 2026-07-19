/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/callsign_lookup_service.dart';

/// Settings section for managing the offline US amateur callsign database:
/// download, update, and delete. Self-contained state so it can be embedded in
/// the settings dialog without threading download progress through the parent.
class CallsignDbSettingsSection extends StatefulWidget {
  const CallsignDbSettingsSection({super.key});

  @override
  State<CallsignDbSettingsSection> createState() =>
      _CallsignDbSettingsSectionState();
}

class _CallsignDbSettingsSectionState extends State<CallsignDbSettingsSection> {
  final CallsignLookupService _service = CallsignLookupService.instance;

  bool _busy = false;
  double? _progress; // 0..1, or null when indeterminate / installing
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _downloadOrUpdate() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _progress = 0;
      _statusMessage = null;
      _statusIsError = false;
    });
    try {
      final manifest = await _service.fetchManifest();
      if (_service.isAvailable && _service.installedVersion == manifest.version) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _statusMessage = l10n.cslUpToDate;
        });
        return;
      }
      await _service.download(
        manifest,
        progress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _statusMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _statusMessage = l10n.cslDownloadFailed(e.toString());
        _statusIsError = true;
      });
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cslDeleteTitle),
        content: Text(l10n.cslDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cslDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.delete();
    if (!mounted) return;
    setState(() {
      _statusMessage = null;
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final installed = _service.isAvailable;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cslSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.cslSectionIntro,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(
            installed
                ? l10n.cslInstalledInfo(
                    _service.installedVersion,
                    _service.recordCount.toString(),
                  )
                : l10n.cslNotInstalled,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 6),
                  Text(
                    _progress != null
                        ? l10n.cslDownloading(
                            (_progress! * 100).toStringAsFixed(0))
                        : l10n.cslInstalling,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusIsError ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
          Row(
            children: [
              ElevatedButton(
                onPressed: _busy ? null : _downloadOrUpdate,
                child: Text(installed ? l10n.cslUpdate : l10n.cslDownload),
              ),
              if (installed) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: Text(l10n.cslDelete),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
