import 'package:flutter/material.dart';

import 'data_broker.dart';

/// Manages the application's active [ThemeMode] (system / light / dark).
///
/// The selected theme is persisted via the [DataBroker] under the `ThemeMode`
/// key on device 0 (the same store used by the settings dialog). The stored
/// value is one of `system` (follow the OS setting), `light` or `dark`. The
/// active [ThemeMode] is exposed as a [ValueNotifier] so that the top-level
/// `MaterialApp` can rebuild whenever the theme changes.
class ThemeController {
  ThemeController._();

  /// Singleton instance shared across the application.
  static final ThemeController instance = ThemeController._();

  /// DataBroker key used to persist the selected theme mode.
  static const String storageKey = 'ThemeMode';

  /// Stored value meaning "follow the operating system setting".
  static const String systemTag = 'system';

  /// Stored value meaning "always use the light theme".
  static const String lightTag = 'light';

  /// Stored value meaning "always use the dark theme".
  static const String darkTag = 'dark';

  /// The active theme mode. Defaults to [ThemeMode.system].
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Loads the persisted theme selection and applies it to [themeMode]. Call
  /// once during application startup before building the `MaterialApp`.
  void load() {
    final tag = DataBroker.getValue<String>(0, storageKey, systemTag) ??
        systemTag;
    themeMode.value = _modeForTag(tag);
  }

  /// The persisted theme tag (`system`, `light` or `dark`).
  String get themeTag => _tagForMode(themeMode.value);

  /// Updates the active theme and persists the choice.
  void setThemeMode(String tag) {
    themeMode.value = _modeForTag(tag);
    DataBroker.dispatch(deviceId: 0, name: storageKey, data: tag);
  }

  ThemeMode _modeForTag(String tag) {
    switch (tag) {
      case lightTag:
        return ThemeMode.light;
      case darkTag:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _tagForMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return lightTag;
      case ThemeMode.dark:
        return darkTag;
      case ThemeMode.system:
        return systemTag;
    }
  }
}
