/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One-time migration of the on-disk application-support data left behind when
/// the Windows executable's `CompanyName` was renamed from `com.example` to
/// `com.meshcentral`.
///
/// On Windows `getApplicationSupportDirectory()` resolves to
/// `%APPDATA%\<CompanyName>\<ProductName>`, so the rename moved every piece of
/// persisted state — settings (`shared_preferences.json`), comms history, mail,
/// packets, crash logs, map tiles, satellite data, etc. — to a brand new,
/// empty folder, which looks to the user like a full settings reset. This
/// copies the old folder's contents into the new one on first launch of a build
/// that includes this migration.
///
/// macOS (bundle id `com.meshcentral.htcommander`) and Linux (binary name
/// `htcommander`) were unaffected by the rename, so this only runs on Windows.
/// The Android package rename cannot be recovered in-app because the old app's
/// private storage is inaccessible to the renamed package.
class SettingsMigration {
  /// The old Windows `CompanyName` (top-level `%APPDATA%` sub-folder).
  static const String _oldCompany = 'com.example';

  /// Marker written into the new support folder once migration has run so it is
  /// only ever attempted once.
  static const String _markerFileName = '.migrated_from_com_example';

  /// Preferences store file name (Windows file backend).
  static const String _prefsFileName = 'shared_preferences.json';

  /// Imports settings/data from the pre-rename support folder if present.
  ///
  /// Must be called before [DataBroker.initialize] (and therefore before
  /// `SharedPreferences.getInstance()`), so the merged preferences are picked
  /// up when the store is first loaded.
  static Future<void> run() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final newDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final marker = File('${newDir.path}$sep$_markerFileName');
      if (await marker.exists()) return;

      // Same %APPDATA% root and product name, only the company folder differs:
      //   %APPDATA%\com.meshcentral\htcommander  ->  %APPDATA%\com.example\htcommander
      final productName = _basename(newDir.path);
      final appDataRoot = newDir.parent.parent;
      final oldDir = Directory(
        '${appDataRoot.path}$sep$_oldCompany$sep$productName',
      );

      if (await oldDir.exists()) {
        await _copyMissing(oldDir, newDir);
        await _mergePreferences(oldDir, newDir);
        debugPrint('SettingsMigration: imported settings from ${oldDir.path}');
      }

      // Record the attempt (even when there was nothing to import) so later
      // launches skip the folder scan entirely.
      await marker.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (e) {
      debugPrint('SettingsMigration: failed: $e');
    }
  }

  /// Recursively copies every file from [src] into [dst] that does not already
  /// exist in [dst], never overwriting newer files the current build may have
  /// already written. The preferences store and the migration marker are
  /// skipped here; preferences are handled by [_mergePreferences].
  static Future<void> _copyMissing(Directory src, Directory dst) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    final sep = Platform.pathSeparator;
    await for (final entity in src.list(followLinks: false)) {
      final name = _basename(entity.path);
      if (entity is File) {
        if (name == _prefsFileName || name == _markerFileName) continue;
        final target = File('${dst.path}$sep$name');
        if (!await target.exists()) {
          await entity.copy(target.path);
        }
      } else if (entity is Directory) {
        await _copyMissing(entity, Directory('${dst.path}$sep$name'));
      }
    }
  }

  /// Merges the old preferences store into the new one. Keys only present in the
  /// old store are added; keys already present in the new store are left
  /// untouched so anything the user changed in the renamed build wins. When the
  /// new store is missing or unreadable, the old one is adopted wholesale.
  static Future<void> _mergePreferences(Directory oldDir, Directory newDir) async {
    final sep = Platform.pathSeparator;
    final oldPrefs = File('${oldDir.path}$sep$_prefsFileName');
    if (!await oldPrefs.exists()) return;

    Map<String, dynamic> oldMap;
    try {
      oldMap = jsonDecode(await oldPrefs.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final newPrefs = File('${newDir.path}$sep$_prefsFileName');
    if (!await newPrefs.exists()) {
      await newPrefs.writeAsString(jsonEncode(oldMap), flush: true);
      return;
    }

    Map<String, dynamic> newMap;
    try {
      newMap = jsonDecode(await newPrefs.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      // Unreadable new store: prefer the last good settings over nothing.
      await newPrefs.writeAsString(jsonEncode(oldMap), flush: true);
      return;
    }

    var changed = false;
    oldMap.forEach((key, value) {
      if (!newMap.containsKey(key)) {
        newMap[key] = value;
        changed = true;
      }
    });
    if (changed) await newPrefs.writeAsString(jsonEncode(newMap), flush: true);
  }

  /// Last path segment of [p], tolerant of both path separators.
  static String _basename(String p) {
    final parts = p
        .split(RegExp(r'[\\/]'))
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? p : parts.last;
  }
}
