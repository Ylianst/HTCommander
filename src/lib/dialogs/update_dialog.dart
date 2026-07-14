import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';
import 'dialog_utils.dart';

/// Dialog that lets the user check for updates, download, and install them.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _controller = UpdateService.instance.controller;
  bool _checking = false;
  String _status = '';
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    _controller?.addListener(_onStateChanged);
    // Start an immediate check when the dialog opens. This is scheduled for
    // after the first frame so that the localization (inherited) context is
    // available — calling AppLocalizations.of(context) directly in initState
    // throws and would leave the dialog blank.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForUpdates();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkForUpdates() async {
    if (_controller == null || _checking) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _status = l10n.updateChecking;
    });
    try {
      final result = await _controller.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _checkedOnce = true;
        _status = switch (result) {
          ManualUpdateCheckAvailable(:final descriptor) =>
            l10n.updateVersionAvailable(descriptor.version),
          ManualUpdateCheckFreshInstallRequired(:final descriptor) =>
            l10n.updateFreshDownload(descriptor.version),
          ManualUpdateCheckBlockedBySupportPolicy(:final descriptor) =>
            l10n.updateUnsupported(descriptor.version),
          ManualUpdateCheckUpToDate() => l10n.updateUpToDate,
          ManualUpdateCheckFailed(:final error) =>
            l10n.updateCheckFailed(error.toString()),
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkedOnce = true;
        _status = l10n.updateCheckFailed(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _downloadUpdate() async {
    if (_controller == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _status = l10n.updateDownloading);
    try {
      await _controller.downloadUpdate();
      if (!mounted) return;
      setState(() => _status = l10n.updateDownloaded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = l10n.updateDownloadFailed(e.toString()));
    }
  }

  Future<void> _installUpdate() async {
    if (_controller == null) return;
    final l10n = AppLocalizations.of(context);
    try {
      await _controller.restartApp();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = l10n.updateInstallFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller?.state;
    final isDownloading = state is UpdateDownloading;
    final isReadyToInstall = state is UpdateReadyToInstall;
    final canDownload =
        state is UpdateAvailable || state is UpdateBlockedBySupportPolicy;

    double? progress;
    if (state is UpdateDownloading && state.totalBytes > 0) {
      progress = state.receivedBytes / state.totalBytes;
    }

    final logPath = UpdateService.instance.logPath;
    final l10n = AppLocalizations.of(context);

    return HTDialog(
      title: l10n.updateTitle,
      maxWidth: 450,
      maxHeight: 300,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status, style: DialogStyles.bodyStyle),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
          if (_checking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if ((isReadyToInstall || state is UpdateInstalling) &&
              logPath != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              l10n.updateDiagnosticsLog(logPath),
              style: DialogStyles.bodyStyle.copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
      actions: [
        if (canDownload && !isDownloading)
          TextButton(
            onPressed: _downloadUpdate,
            child: Text(l10n.settingsDownload),
          ),
        if (isReadyToInstall)
          TextButton(
            onPressed: _installUpdate,
            child: Text(l10n.updateInstallRestart),
          ),
        if (!_checking && _checkedOnce && !canDownload && !isReadyToInstall)
          TextButton(
            onPressed: _checkForUpdates,
            child: Text(l10n.updateCheckAgain),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
