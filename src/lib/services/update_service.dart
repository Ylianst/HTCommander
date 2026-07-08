import 'dart:io' show Platform;

import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Whether this is a Mac App Store (sandboxed) build.
///
/// App Store builds must run in the App Sandbox, where the in-app self-updater
/// cannot replace the application bundle and self-modifying code is prohibited
/// by App Store Review. Updates for these builds are delivered by the App
/// Store instead. Set at build time with:
///
///   flutter build macos --dart-define=APP_STORE_BUILD=true
const bool kAppStoreBuild = bool.fromEnvironment(
  'APP_STORE_BUILD',
  defaultValue: false,
);

/// Provides access to the desktop self-update controller.
///
/// On non-desktop platforms the [controller] is `null` and all operations
/// are no-ops.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// The underlying controller. `null` on web, iOS, and Android.
  DesktopUpdaterController? controller;

  /// Absolute path of the diagnostics log written by the native install
  /// helper, or `null` when self-update is unsupported.
  String? logPath;

  /// URL of the hosted app-archive.json index.
  static const String _appArchiveUrl =
      'https://ylianst.github.io/HTCommander/app-archive.json';

  /// Initialise the update controller on desktop platforms.
  Future<void> init() async {
    // The App Store variant is updated by the App Store itself; the bundled
    // self-updater must stay disabled there.
    if (kAppStoreBuild ||
        kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    // Point the native install helper at a diagnostics log so that self-update
    // failures (which happen after the app quits) can be inspected afterwards.
    String? diagnosticsLogPath;
    try {
      final dir = await getApplicationSupportDirectory();
      diagnosticsLogPath =
          '${dir.path}${Platform.pathSeparator}update_diagnostics.log';
      logPath = diagnosticsLogPath;
    } catch (e) {
      debugPrint('UpdateService: could not resolve diagnostics log path: $e');
    }

    controller = DesktopUpdaterController(
      appArchiveUrl: Uri.parse(_appArchiveUrl),
      skipInitialVersionCheck: true,
      diagnosticsLogPath: diagnosticsLogPath,
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
