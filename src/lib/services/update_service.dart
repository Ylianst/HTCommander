import 'dart:io' show Platform;

import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Provides access to the desktop self-update controller.
///
/// On non-desktop platforms the [controller] is `null` and all operations
/// are no-ops.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// The underlying controller. `null` on web, iOS, and Android.
  DesktopUpdaterController? controller;

  /// URL of the hosted app-archive.json index.
  static const String _appArchiveUrl =
      'https://ylianst.github.io/HTCommander/app-archive.json';

  /// Initialise the update controller on desktop platforms.
  void init() {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    controller = DesktopUpdaterController(
      appArchiveUrl: Uri.parse(_appArchiveUrl),
      skipInitialVersionCheck: true,
    );
  }

  /// Manually trigger an update check. Returns the result on desktop,
  /// `null` otherwise.
  Future<ManualUpdateCheckResult?> checkForUpdates() async {
    return controller?.checkForUpdates();
  }

  /// Download the available update.
  Future<void> downloadUpdate() async {
    await controller?.downloadUpdate();
  }

  /// Install the staged update and restart the app.
  Future<void> restartApp() async {
    await controller?.restartApp();
  }

  /// Whether self-update is supported on this platform.
  bool get isSupported => controller != null;
}
