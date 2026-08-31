/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Detects whether the running (web) build is the one served by the desktop
HTCommander app and, if so, where its WebSocket bridge lives. When hosted, the
Flutter web UI shares the host's radio over the `/websocket.aspx` bridge instead
of using the browser's Web Bluetooth (see radio/websocket_transport.dart).

The HTCommander-served build is produced with `--dart-define=HTC_HOSTED=true`
(see tools/build_web_app.ps1), which distinguishes it from a stand-alone
deployment (e.g. GitHub Pages) served from the same root path. `?bridge=1` forces
hosted mode for testing against a running host from an ordinary dev build.
*/

import 'package:flutter/foundation.dart' show kIsWeb;

/// Helpers for detecting the HTCommander-hosted web deployment.
class HostBridge {
  HostBridge._();

  /// The bridge endpoint the host serves WebSocket connections on.
  static const String _webSocketPath = '/websocket.aspx';

  /// Compile-time flag baked into the build served by the desktop app.
  static const bool _hostedBuild = bool.fromEnvironment(
    'HTC_HOSTED',
    defaultValue: false,
  );

  /// Whether this build is the Flutter web UI served by the desktop app and
  /// should connect back over the WebSocket bridge rather than Web Bluetooth.
  static bool get isHosted {
    if (!kIsWeb) return false;
    if (Uri.base.queryParameters['bridge'] == '1') return true;
    return _hostedBuild;
  }

  /// The WebSocket URL of the host bridge, derived from the page origin. Only
  /// meaningful when [isHosted] is true.
  static String get webSocketUrl {
    final base = Uri.base;
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: _webSocketPath,
    ).toString();
  }
}
