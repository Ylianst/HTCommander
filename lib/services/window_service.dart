import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:desktop_multi_window/desktop_multi_window.dart';

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
  bool _isChildWindow = false;
  bool get isChildWindow => _isChildWindow;
  set isChildWindow(bool value) => _isChildWindow = value;

  /// Whether detaching is allowed (only in parent window on desktop)
  bool get canDetach => isDesktop && !_isChildWindow;

  /// List of child window controllers we've created
  final List<WindowController> _childWindows = [];

  /// Get list of active child windows
  List<WindowController> get childWindows => List.unmodifiable(_childWindows);

  /// Create a new detached window for a tab
  /// [windowType] is the identifier for the tab (e.g., 'aprs', 'voice', 'terminal')
  Future<WindowController?> createWindow(String windowType) async {
    if (!isDesktop) return null;

    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({'window': windowType}),
        hiddenAtLaunch: false,
      ),
    );

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

    _childWindows.clear();
  }

  /// Remove a window from tracking (called when a child window closes)
  void removeWindow(WindowController controller) {
    _childWindows.removeWhere((w) => w.windowId == controller.windowId);
  }
}

/// Global instance for easy access
final windowService = WindowService.instance;
