import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter/material.dart';

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
    // Start an immediate check when the dialog opens.
    _checkForUpdates();
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
    setState(() {
      _checking = true;
      _status = 'Checking for updates...';
    });
    try {
      final result = await _controller.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _checkedOnce = true;
        _status = switch (result) {
          ManualUpdateCheckAvailable(:final descriptor) =>
            'Version ${descriptor.version} is available.',
          ManualUpdateCheckFreshInstallRequired(:final descriptor) =>
            'Version ${descriptor.version} requires a fresh download.',
          ManualUpdateCheckBlockedBySupportPolicy(:final descriptor) =>
            'This version is no longer supported. Update to ${descriptor.version}.',
          ManualUpdateCheckUpToDate() => 'You are running the latest version.',
          ManualUpdateCheckFailed(:final error) =>
            'Update check failed: $error',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkedOnce = true;
        _status = 'Update check failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _downloadUpdate() async {
    if (_controller == null) return;
    setState(() => _status = 'Downloading update...');
    try {
      await _controller.downloadUpdate();
      if (!mounted) return;
      setState(() => _status = 'Update downloaded. Ready to install.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Download failed: $e');
    }
  }

  Future<void> _installUpdate() async {
    if (_controller == null) return;
    try {
      await _controller.restartApp();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Install failed: $e');
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

    return HTDialog(
      title: 'Software Update',
      maxWidth: 450,
      maxHeight: 300,
      content: Expanded(
        child: Column(
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
          ],
        ),
      ),
      actions: [
        if (canDownload && !isDownloading)
          TextButton(
            onPressed: _downloadUpdate,
            child: const Text('Download'),
          ),
        if (isReadyToInstall)
          TextButton(
            onPressed: _installUpdate,
            child: const Text('Install & Restart'),
          ),
        if (!_checking && _checkedOnce && !canDownload && !isReadyToInstall)
          TextButton(
            onPressed: _checkForUpdates,
            child: const Text('Check Again'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
