/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'data_broker.dart';

/// Cross-platform system pop-up notifications for incoming messages that are
/// addressed to our station.
///
/// A notification is only shown when the app is NOT in the foreground, i.e. it
/// is backgrounded (mobile/web) or its main window is unfocused/minimized
/// (desktop). When the app is focused the message is already visible in the UI,
/// so no notification is raised.
///
/// The service is a singleton initialized once from the main window. Message
/// handlers call [showMessage] when a message for our station arrives.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();

  /// Singleton instance.
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _available = false;
  int _nextId = 1;

  /// App lifecycle state (authoritative on mobile/web).
  bool _appResumed = true;

  /// Main window focus state (authoritative on desktop).
  bool _windowFocused = true;

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Whether the app is currently considered in the foreground.
  bool get _isForeground => _isDesktop ? _windowFocused : _appResumed;

  /// Initializes the platform plugin and registers the lifecycle observer.
  /// Safe to call once from the main window; failures degrade to a no-op.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );
      const linuxInit =
          LinuxInitializationSettings(defaultActionName: 'Open');
      const windowsInit = WindowsInitializationSettings(
        appName: 'HTCommander',
        appUserModelId: 'com.meshcentral.htcommander',
        // A fixed, app-unique GUID identifying the notification activator.
        guid: 'c73a2b9e-3f41-4d8a-9c6b-7e5f1a2d4b88',
      );
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
        linux: linuxInit,
        windows: windowsInit,
      );
      await _plugin.initialize(settings: settings);

      // Android 13+ requires a runtime permission to post notifications.
      if (!kIsWeb && Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      WidgetsBinding.instance.addObserver(this);
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  /// Updates the desktop main-window focus state. Called from the main window's
  /// window listener (focus/blur/minimize/restore).
  void setWindowFocused(bool focused) => _windowFocused = focused;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
  }

  /// Shows a pop-up notification for an incoming message, but only when the app
  /// is not in the foreground. No-op if the plugin is unavailable.
  Future<void> showMessage({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_available) return;
    if (_isForeground) return;
    // Respect the user's "Message Notifications" setting (default on).
    if ((DataBroker.getValue<int>(0, 'MessageNotifications', 1) ?? 1) != 1) {
      return;
    }

    final id = _nextId++;
    if (_nextId > 100000) _nextId = 1;

    const android = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Incoming messages addressed to your station',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwin = DarwinNotificationDetails();
    const linux = LinuxNotificationDetails();
    const windows = WindowsNotificationDetails();
    const details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
      windows: windows,
    );

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {
      // Best-effort: never let a notification failure disrupt message handling.
    }
  }
}
