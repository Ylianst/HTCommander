/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Radio firmware update dialog. Orchestrates the full update: cloud check,
download + assemble, then the two-phase GAIA VM flash (transfer, radio reboot,
reconnect, confirm). Only supported over Bluetooth Classic transports.
*/

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Radio;

import '../l10n/app_localizations.dart';
import '../radio/firmware_updater.dart';
import '../radio/radio.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker.dart';
import '../services/firmware_service.dart';
import 'dialog_utils.dart';

/// Shows the Radio Firmware Update dialog for the radio at [deviceId].
Future<void> showFirmwareUpdateDialog(BuildContext context, int deviceId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _FirmwareUpdateDialog(deviceId: deviceId),
  );
}

enum _Stage {
  idle,
  checking,
  available,
  downloading,
  confirm,
  flashing,
  rebooting,
  confirming,
  done,
  error,
}

class _FirmwareUpdateDialog extends StatefulWidget {
  final int deviceId;
  const _FirmwareUpdateDialog({required this.deviceId});

  @override
  State<_FirmwareUpdateDialog> createState() => _FirmwareUpdateDialogState();
}

class _FirmwareUpdateDialogState extends State<_FirmwareUpdateDialog> {
  final BluetoothService _bt = BluetoothService();

  /// Scroll controller for the release-notes panel (shared between the
  /// Scrollbar and its SingleChildScrollView so the bar has a position).
  final ScrollController _notesScrollController = ScrollController();

  _Stage _stage = _Stage.idle;
  String _statusText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _notesScrollController.dispose();
    super.dispose();
  }

  // Progress (null value = indeterminate).
  String _progressLabel = '';
  double? _progressValue;

  FirmwareUpdateInfo? _updateInfo;
  FirmwareBundle? _bundle;

  /// True while the operation must not be interrupted (radio is being written
  /// or rebooted). Disables closing the dialog.
  bool get _isBusy =>
      _stage == _Stage.checking ||
      _stage == _Stage.downloading ||
      _stage == _Stage.flashing ||
      _stage == _Stage.rebooting ||
      _stage == _Stage.confirming;

  Radio? get _radio => _bt.radioInstance(widget.deviceId);

  String get _currentVersion => _formatVersion(_radio?.info?.softVer);

  /// Format the radio's packed software version (matches RadioInfo display).
  static String _formatVersion(int? softVer) {
    if (softVer == null) return 'unknown';
    return '${(softVer >> 8) & 0xF}.${(softVer >> 4) & 0xF}.${softVer & 0xF}';
  }

  // ── Flow steps ────────────────────────────────────────────────────────────

  Future<void> _performCheck() async {
    final l10n = AppLocalizations.of(context);
    final radio = _radio;
    if (radio == null) {
      _fail(l10n.fwErrNotConnected);
      return;
    }
    final productId = radio.info?.productId;
    if (productId == null) {
      _fail(l10n.fwErrNoDeviceInfo);
      return;
    }
    setState(() {
      _stage = _Stage.checking;
      _statusText = l10n.fwStatusChecking;
      _errorText = null;
    });

    try {
      // Only the radio's product ID is sent; the server returns the latest
      // firmware for that product.
      final info = await FirmwareService.checkUpdate(
        productId: productId,
        log: _log,
      );
      if (!mounted) return;
      if (info == null) {
        _fail(l10n.fwErrNoServerInfo);
        return;
      }
      setState(() {
        _updateInfo = info;
        _stage = _Stage.available;
        _statusText = l10n.fwUpdateAvailable(info.displayVersion);
      });
    } catch (e) {
      _fail(l10n.fwErrCheckFailed('$e'));
    }
  }

  /// Load a firmware image from a local file, bypassing the cloud check and
  /// download/assemble steps. The file must already be an assembled, ready-to-
  /// flash firmware image (not a BSDIFF40 patch).
  Future<void> _loadFromFile() async {
    final l10n = AppLocalizations.of(context);
    final radio = _radio;
    if (radio == null) {
      _fail(l10n.fwErrNotConnected);
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: l10n.fwPickTitle,
        withData: true,
      );
      final picked = result?.files.single;
      final bytes = picked?.bytes;
      if (bytes == null) return; // cancelled or unreadable
      if (!mounted) return;

      final bundle = FirmwareBundle(bytes);
      setState(() {
        _bundle = bundle;
        _updateInfo = null;
        _stage = _Stage.confirm;
        _statusText = l10n.fwLoaded(
          picked!.name,
          _formatBytes(bundle.size),
          bundle.md5Hex.substring(0, 8),
        );
      });
    } catch (e) {
      _fail(l10n.fwErrLoadFailed('$e'));
    }
  }

  /// Save the assembled firmware image to disk in the same raw format the
  /// "From File…" option loads. The version is included in the default file
  /// name when known.
  Future<void> _saveToFile() async {
    final l10n = AppLocalizations.of(context);
    final bundle = _bundle;
    if (bundle == null) return;
    try {
      final version = _updateInfo?.displayVersion;
      final productId = _radio?.info?.productId;

      final parts = <String>['firmware'];
      if (productId != null) parts.add('$productId');
      if (version != null && version != 'unknown') parts.add(version);
      final defaultName = '${parts.join('_')}.bin';

      final path = await FilePicker.saveFile(
        dialogTitle: l10n.fwSaveTitle,
        fileName: defaultName,
        bytes: bundle.data,
      );
      if (path == null) return; // cancelled
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fwSavedTo(path))),
      );
    } catch (e) {
      _fail(l10n.fwErrSaveFailed('$e'));
    }
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    final info = _updateInfo;
    if (info == null) return;
    setState(() {
      _stage = _Stage.downloading;
      _statusText = l10n.fwStatusDownloading;
      _progressLabel = l10n.fwProgressStarting;
      _progressValue = null;
    });

    try {
      final bundle = await FirmwareService.downloadFirmware(
        info,
        progress: _onAcquireProgress,
      );
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _stage = _Stage.confirm;
        _statusText = l10n.fwReady(
          _formatBytes(bundle.size),
          bundle.md5Hex.substring(0, 8),
        );
      });
    } catch (e) {
      _fail(l10n.fwErrDownloadFailed('$e'));
    }
  }

  Future<void> _flash() async {
    final l10n = AppLocalizations.of(context);
    final radio = _radio;
    final bundle = _bundle;
    if (radio == null || bundle == null) {
      _fail(l10n.fwErrNotConnected);
      return;
    }

    final mac = radio.macAddress;
    final name = radio.friendlyName;

    // Phase 1 — transfer.
    setState(() {
      _stage = _Stage.flashing;
      _statusText = l10n.fwStatusWriting;
      _progressLabel = l10n.fwProgressTransferring;
      _progressValue = 0;
    });

    try {
      final updater = FirmwareUpdater(radio, bundle, progress: _onFlashProgress);
      await updater.transfer();
    } catch (e) {
      _fail(l10n.fwErrTransferFailed('$e'));
      return;
    }

    if (!mounted) return;

    // Phase 1 → 2 — reboot & reconnect.
    setState(() {
      _stage = _Stage.rebooting;
      _statusText = l10n.fwStatusRebooting;
      _progressLabel = l10n.fwProgressWaitingRestart;
      _progressValue = null;
    });

    Radio? newRadio;
    try {
      newRadio = await _bt.reconnectAfterReboot(mac, name);
    } catch (e) {
      _fail(l10n.fwErrReconnectFailed('$e'));
      return;
    }
    if (!mounted) return;
    if (newRadio == null) {
      _fail(
        l10n.fwErrReconnectNull,
      );
      return;
    }

    // Phase 2 — confirm.
    setState(() {
      _stage = _Stage.confirming;
      _statusText = l10n.fwStatusFinalising;
      _progressLabel = l10n.fwProgressConfirming;
      _progressValue = null;
    });

    try {
      await FirmwareUpdater.confirm(newRadio, bundle);
    } catch (e) {
      _fail(l10n.fwErrConfirmFailed('$e'));
      return;
    }
    if (!mounted) return;

    setState(() {
      _stage = _Stage.done;
      _statusText = l10n.fwStatusComplete;
    });
  }

  // ── Progress callbacks ────────────────────────────────────────────────────

  void _onAcquireProgress(String stage, int done, int total) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      final label = switch (stage) {
        'patch' => l10n.fwProgressDownloadPatch,
        'base' => l10n.fwProgressDownloadBase,
        'assemble' => l10n.fwProgressAssemble,
        _ => stage,
      };
      _progressLabel = total > 0
          ? l10n.fwProgressBytes(
              label, _formatBytes(done), _formatBytes(total))
          : '$label…';
      _progressValue = total > 0 ? done / total : null;
    });
  }

  void _onFlashProgress(String stage, int done, int total) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _progressLabel = l10n.fwProgressTransferringBytes(
          _formatBytes(done), _formatBytes(total));
      _progressValue = total > 0 ? done / total : null;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _errorText = message;
    });
  }

  /// Writes a line to the application debug log (shown in the Debug tab).
  void _log(String message) {
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: '[Firmware] $message',
      store: false,
    );
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Section card styling, matching the Settings / Radio Information dialogs.
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
    return PopScope(
      canPop: !_isBusy,
      child: Dialog(
        backgroundColor: const Color(0xFFF5F5F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 540),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppLocalizations.of(context).fwTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _sectionDecoration(),
                      child: _buildContent(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final action in _buildActions())
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: action,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);
    final statusText =
        _statusText.isEmpty ? l10n.fwStatusInitial : _statusText;
    final children = <Widget>[
      Text(l10n.fwCurrentFirmware(_currentVersion),
          style: DialogStyles.labelStyle),
      const SizedBox(height: 12),
    ];

    if (_stage == _Stage.error) {
      children.add(
        SelectableText(
          _errorText ?? l10n.fwErrGeneric,
          style: DialogStyles.bodyStyle.copyWith(color: Colors.red.shade800),
        ),
      );
    } else {
      if (statusText.isNotEmpty) {
        children.add(Text(statusText, style: DialogStyles.bodyStyle));
      }

      // Inline online-check disclosure (idle).
      if (_stage == _Stage.idle) {
        children.addAll([
          const SizedBox(height: 10),
          Text(
            l10n.fwIdleDisclosure,
            style: DialogStyles.bodyStyle.copyWith(fontSize: 12),
          ),
        ]);
      }

      // Release notes for an available update.
      final releaseNotes = _updateInfo?.releaseNotes.trim() ?? '';
      if (_stage == _Stage.available && releaseNotes.isNotEmpty) {
        children.addAll([
          const SizedBox(height: 16),
          Text(
            l10n.fwWhatsNew,
            style: DialogStyles.bodyStyle.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Scrollbar(
                controller: _notesScrollController,
                child: SingleChildScrollView(
                  controller: _notesScrollController,
                  child: SelectableText(
                    releaseNotes.replaceAll('\r\n', '\n'),
                    style: DialogStyles.bodyStyle.copyWith(fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }

      if (_stage == _Stage.confirm) {
        children.addAll([
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Text(
              l10n.fwConfirmWarning,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ]);
      }

      if (_progressValue != null || _isBusy) {
        children.addAll([
          const SizedBox(height: 16),
          if (_progressLabel.isNotEmpty)
            Text(
              _progressLabel,
              style: DialogStyles.bodyStyle.copyWith(fontSize: 12),
            ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progressValue,
              minHeight: 8,
              backgroundColor: Colors.grey.shade400,
            ),
          ),
        ]);
      }

      if (_stage == _Stage.done) {
        children.addAll([
          const SizedBox(height: 12),
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
        ]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Widget> _buildActions() {
    final l10n = AppLocalizations.of(context);
    final close = TextButton(
      onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
      style: DialogStyles.secondaryButtonStyle(context),
      child: Text(_stage == _Stage.done ? l10n.commonClose : l10n.commonCancel),
    );

    switch (_stage) {
      case _Stage.idle:
        return [
          close,
          TextButton(
            onPressed: _loadFromFile,
            style: DialogStyles.secondaryButtonStyle(context),
            child: Text(l10n.fwFromFile),
          ),
          ElevatedButton(
            onPressed: _performCheck,
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(l10n.fwCheckForUpdate),
          ),
        ];
      case _Stage.available:
        return [
          close,
          ElevatedButton(
            onPressed: _download,
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(l10n.fwDownload),
          ),
        ];
      case _Stage.confirm:
        return [
          close,
          TextButton(
            onPressed: _saveToFile,
            style: DialogStyles.secondaryButtonStyle(context),
            child: Text(l10n.fwSave),
          ),
          ElevatedButton(
            onPressed: _flash,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.fwFlashNow),
          ),
        ];
      case _Stage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.secondaryButtonStyle(context),
            child: Text(l10n.commonClose),
          ),
          ElevatedButton(
            onPressed: _performCheck,
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(l10n.fwRetry),
          ),
        ];
      case _Stage.checking:
      case _Stage.downloading:
      case _Stage.flashing:
      case _Stage.rebooting:
      case _Stage.confirming:
        return [close];
      case _Stage.done:
        return [
          if (_bundle != null)
            TextButton(
              onPressed: _saveToFile,
              style: DialogStyles.secondaryButtonStyle(context),
              child: Text(l10n.fwSave),
            ),
          close,
        ];
    }
  }
}
