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

import '../aprs/aprs_conversation.dart' show clearAprsConversationEvent;

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

  /// Device-0 settings that stay local on each side (host app prefs / browser
  /// localStorage) instead of syncing across the bridge, so the host and the
  /// hosted web page keep independent values. `OutputVolume` is the application
  /// output volume: each side controls (and can mute) its own playback.
  static bool isLocalOnlySetting(String name) =>
      name == 'OutputVolume' ||
      name == 'MapCustomSourceEnabled' ||
      name == 'MapCustomSourceUrl' ||
      name == 'MapCustomSourceAttribution';

  static final RegExp _secretName = RegExp(
    'password|token|passcode|apikey|secret',
    caseSensitive: false,
  );

  /// Whether a device-0 setting holds a credential (passwords, API keys and
  /// tokens such as `WinlinkPassword`, `RepeaterBookToken`, `AprsIsPasscode`).
  /// Credentials never leave the host: they are not sent to browsers or agents
  /// and browsers cannot change them.
  static bool isSecretSetting(String name) =>
      name == 'MapCustomSourceUrl' || _secretName.hasMatch(name);

  /// Host-published device-0 value listing which credential settings are set
  /// on the host (names only, never values), so the hosted web UI can show
  /// features that need them (e.g. the Mail tab needs a Winlink password).
  /// Browsers cannot change it.
  static const String hostCredentialsValue = 'HostConfiguredCredentials';

  /// Names of the credential settings that are non-empty in [settings].
  static List<String> configuredCredentials(Map<String, Object?> settings) {
    final names = <String>[
      for (final e in settings.entries)
        if (isSecretSetting(e.key) &&
            !e.key.startsWith('AgentApi') &&
            e.value != null &&
            e.value.toString().isNotEmpty)
          e.key,
    ]..sort();
    return names;
  }

  /// Whether a device-0 setting is shared between the host and the browser.
  /// Transient per-instance UI selection state (`Selected*`: current tab, radio,
  /// satellite, APRS route), local-only settings (see [isLocalOnlySetting]),
  /// credentials (see [isSecretSetting]) and the agent API controls are
  /// excluded. The agent settings must never be readable or writable by a
  /// browser, or any web client could turn on the automation channel or read
  /// its token.
  static bool isSyncedSetting(String name) =>
      !name.startsWith('Selected') &&
      !isLocalOnlySetting(name) &&
      !isSecretSetting(name) &&
      !name.startsWith('AgentApi');

  /// Device-1 clear requests the hosted web page forwards to the host, so
  /// history the user clears in the browser is also removed from the host's
  /// database and does not come back when the page is reloaded. The host only
  /// re-dispatches events in this set.
  static const Set<String> forwardedClearEvents = <String>{
    'ClearVoiceText',
    'ClearAprsPackets',
    clearAprsConversationEvent,
  };

  /// First byte of a host->browser audio frame over the bridge, distinguishing
  /// it from radio command frames (which always start with 0x00). The frame is
  /// `[magic, channels, sampleRateLo, sampleRateHi]` then little-endian 16-bit
  /// interleaved PCM.
  static const int audioFrameMagic = 0xF1;

  /// Device-0 software-modem settings a remote client (browser or agent) can
  /// change, mapped to the command the host's SoftwareModem consumes to apply
  /// them live (it persists the setting itself).
  static const Map<String, String> modemSettingCommands = <String, String>{
    'SoftwareModemMode': 'SetSoftwareModemMode',
    'SoftwareModemFec': 'SetSoftwareModemFec',
    'DartTxMode': 'SetDartTxMode',
    'XaraWide': 'SetXaraWide',
    'XaraTxLatencyMs': 'SetXaraTxLatencyMs',
    'XaraTxKeyUpMs': 'SetXaraTxKeyUpMs',
    'AprsSoftwareModemMode': 'SetAprsSoftwareModemMode',
    'AprsSoftwareModemFec': 'SetAprsSoftwareModemFec',
  };
}
