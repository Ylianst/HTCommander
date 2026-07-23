import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'data_broker.dart';

/// Check if running on desktop platform
bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

/// Service to manage child windows for detached tabs
class WindowService {
  WindowService._();
  static final WindowService instance = WindowService._();

  /// Whether this instance is running in a child/detached window
  bool isChildWindow = false;

  /// Whether detaching is allowed (only in parent window on desktop)
  bool get canDetach => isDesktop && !isChildWindow;

  /// List of child window controllers we've created
  final List<WindowController> _childWindows = [];

  /// Subscription that watches for windows opening/closing so closed detached
  /// windows are dropped from tracking and the broker stops forwarding to them.
  StreamSubscription<void>? _windowsChangedSub;

  /// Get list of active child windows
  List<WindowController> get childWindows => List.unmodifiable(_childWindows);

  /// Host-side setup: react to detached windows closing so their broker push
  /// channels are removed promptly. Call once from the main window. Two
  /// mechanisms cover both graceful and abrupt closes:
  ///   * [DataBroker.onChildWindowDetached] fires when a window announces its
  ///     close (before its engine is destroyed).
  ///   * [onWindowsChanged] fires when the native window list changes, catching
  ///     windows that were force-closed without announcing.
  void initHost() {
    if (!isDesktop || isChildWindow) return;
    DataBroker.onChildWindowDetached = _handleChildDetached;
    _windowsChangedSub ??= onWindowsChanged.listen((_) => _reconcileChildren());
  }

  /// Drops a detached window that announced it is closing.
  void _handleChildDetached(String windowId) {
    DataBroker.unregisterChildWindow(windowId);
    _childWindows.removeWhere((w) => w.windowId == windowId);
  }

  /// Removes any tracked child windows that no longer exist (e.g. closed via
  /// the window's title-bar button without announcing).
  Future<void> _reconcileChildren() async {
    try {
      final existing =
          (await WindowController.getAll()).map((w) => w.windowId).toSet();
      final closed = _childWindows
          .where((w) => !existing.contains(w.windowId))
          .toList(growable: false);
      for (final w in closed) {
        DataBroker.unregisterChildWindow(w.windowId);
        _childWindows.removeWhere((c) => c.windowId == w.windowId);
      }
    } catch (_) {
      // Best-effort cleanup; ignore transient IPC failures.
    }
  }

  /// Create a new detached window for a tab
  /// [windowType] is the identifier for the tab (e.g., 'aprs', 'comms', 'terminal')
  Future<WindowController?> createWindow(String windowType) async {
    if (!isDesktop) return null;

    // Ensure we are watching for detached windows closing.
    initHost();

    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({'window': windowType}),
        hiddenAtLaunch: false,
      ),
    );

    // Register the child with the data broker so every dispatch on the main
    // window is forwarded to this detached window (and vice-versa).
    DataBroker.registerChildWindow(controller.windowId);

    _childWindows.add(controller);
    await controller.show();

    return controller;
  }

  /// Close all child windows
  Future<void> closeAllChildren() async {
    if (!isDesktop) return;

    // Get all current windows and close the ones we created
    try {
      final allWindows = await WindowController.getAll();
      for (final window in allWindows) {
        // Skip the main window (it won't have arguments or will have empty arguments)
        if (window.arguments.isNotEmpty) {
          try {
            await window.hide();
          } catch (e) {
            // Window might already be closed
          }
        }
      }
    } catch (e) {
      // Ignore errors during cleanup
    }

    for (final w in _childWindows) {
      DataBroker.unregisterChildWindow(w.windowId);
    }
    _childWindows.clear();
  }

  /// Remove a window from tracking (called when a child window closes)
  void removeWindow(WindowController controller) {
    DataBroker.unregisterChildWindow(controller.windowId);
    _childWindows.removeWhere((w) => w.windowId == controller.windowId);
  }
}

/// Global instance for easy access
final windowService = WindowService.instance;
