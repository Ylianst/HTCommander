/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Writes uncaught startup and runtime errors to an on-disk log file so a user can
send diagnostics even when the application fails before its UI (and therefore
the Debug tab) is ever shown. Works on every non-web platform (Windows, macOS,
Linux, Android, iOS) using the platform application-support directory.
*/

import 'dart:async';
import 'dart:io' show File, FileMode, Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Appends timestamped diagnostics to `htcommander_crash.log` in the platform
/// application-support directory.
///
/// The logger is safe to use before [init] completes: messages logged early are
/// buffered in memory and flushed to disk as soon as the file path resolves, so
/// a crash during startup initialization is still captured. All file writes are
/// synchronous and flushed so nothing is lost if the process aborts immediately
/// afterwards.
class CrashLogger {
  CrashLogger._();

  /// The single shared instance.
  static final CrashLogger instance = CrashLogger._();

  /// The GitHub repository crash reports are filed against.
  static const String githubRepo = 'Ylianst/HTCommander';

  static const String _fileName = 'htcommander_crash.log';

  /// Rotate the log once it grows past this size so it never accumulates
  /// unbounded across many launches.
  static const int _maxBytes = 512 * 1024;

  File? _file;
  bool _initialized = false;

  /// Lines logged before the on-disk path resolved, flushed on [init].
  final List<String> _pending = <String>[];

  /// The resolved crash log file path, or null on web / before [init].
  String? get filePath => _file?.path;

  /// Returns the last [maxChars] characters of the crash log file (trimmed to a
  /// whole-line boundary), or an empty string if the file is missing/unreadable.
  /// Used to embed recent errors and stack traces into a crash report.
  Future<String> readTail({int maxChars = 3000}) async {
    final file = _file;
    if (file == null) return '';
    try {
      if (!await file.exists()) return '';
      String content = await file.readAsString();
      if (content.length > maxChars) {
        content = content.substring(content.length - maxChars);
        final firstNewline = content.indexOf('\n');
        if (firstNewline >= 0) content = content.substring(firstNewline + 1);
      }
      return content.trimRight();
    } catch (_) {
      return '';
    }
  }

  String get _platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  /// Resolves the log file, rotates it if oversized, flushes any buffered lines
  /// and writes a startup banner. Never throws: diagnostics logging must not be
  /// able to crash the app.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      try {
        if (await file.exists() && await file.length() > _maxBytes) {
          final old = File('${file.path}.1');
          if (await old.exists()) await old.delete();
          await file.rename(old.path);
        }
      } catch (_) {
        // Rotation is best-effort; fall through and keep using the file.
      }
      _file = file;

      // Flush anything buffered before the path resolved, then the banner.
      final buffered = List<String>.from(_pending);
      _pending.clear();
      for (final line in buffered) {
        _writeLine(line);
      }
      String version = 'unknown';
      try {
        version = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      _writeLine('=== HTCommander $version started on $_platformLabel ===');
    } catch (_) {
      // If even the application-support directory is unavailable there is
      // nowhere to log; drop silently rather than crash.
    }
  }

  /// Records an error (with optional stack trace) to the log file.
  void logError(String message, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer('[ERROR] $message');
    if (error != null) buffer.write(': $error');
    _write(buffer.toString());
    if (stack != null) _write(stack.toString());
  }

  /// Records an informational line to the log file.
  void logInfo(String message) => _write(message);

  /// Builds a pre-filled GitHub "New Issue" URL for a report. The body embeds
  /// the app version, platform and the most recent log (the on-disk crash log
  /// tail when available, otherwise [fallbackLog]) so the user can review and
  /// submit it under their own account — no server, no telemetry.
  ///
  /// Defaults produce a crash report; callers can override [title], [label],
  /// [promptHeader], [promptHint] and [attachNote] to file a different kind of
  /// issue (e.g. a general "Issue report" from the About box).
  Future<Uri> buildGithubIssueUri({
    String title = 'Crash report',
    String? label = 'crash',
    String promptHeader = '**What happened / what were you doing?**',
    String promptHint = '_(please describe the steps that led to the crash)_',
    String attachNote =
        'Please attach the full crash log file to this issue (drag & drop).',
    String? fallbackLog,
    int maxLogChars = 2000,
  }) async {
    String version = 'unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    String logTail = await readTail(maxChars: maxLogChars);
    if (logTail.isEmpty && fallbackLog != null) {
      logTail = fallbackLog.trimRight();
      if (logTail.length > maxLogChars) {
        logTail = logTail.substring(logTail.length - maxLogChars);
      }
    }

    final body = StringBuffer()
      ..writeln(promptHeader)
      ..writeln(promptHint)
      ..writeln()
      ..writeln('**App version:** $version')
      ..writeln('**Platform:** $_platformLabel')
      ..writeln();
    if (logTail.isNotEmpty) {
      body
        ..writeln('**Recent log:**')
        ..writeln('```')
        ..writeln(logTail)
        ..writeln('```')
        ..writeln();
    }
    final path = filePath;
    body.writeln(
      '> $attachNote'
      '${path != null ? '\n> It is located at: `$path`' : ''}',
    );

    final query = <String, String>{
      'title': title,
      'body': body.toString(),
    };
    if (label != null && label.isNotEmpty) query['labels'] = label;

    return Uri.https('github.com', '/$githubRepo/issues/new', query);
  }

  void _write(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _writeLine(line);
  }

  void _writeLine(String line) {
    final file = _file;
    if (file == null) {
      _pending.add(line);
      return;
    }
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Never let diagnostics logging throw.
    }
  }
}
