/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wrapper around the host computer's default output device volume and mute.
///
/// This is the Flutter equivalent of the C# RadioAudioForm "computer master
/// volume" controls (masterVolumeTrackBar / masterMuteButton). It is backed by
/// a native CoreAudio handler and is therefore only available on macOS; on
/// every other platform all methods report "unavailable" (null / no-op) so the
/// UI can disable the corresponding controls.
class SystemAudio {
  SystemAudio._();

  static const MethodChannel _channel = MethodChannel(
    'com.htcommander/system_audio',
  );

  /// Whether the native system-audio controls are available on this platform.
  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  /// Returns the master output volume in the range 0.0-1.0, or null if it
  /// cannot be read (unsupported platform or no output device).
  static Future<double?> getMasterVolume() async {
    if (!isSupported) return null;
    try {
      final value = await _channel.invokeMethod<double>('getMasterVolume');
      if (value == null) return null;
      return value.clamp(0.0, 1.0);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Sets the master output volume. [volume] is clamped to 0.0-1.0.
  static Future<void> setMasterVolume(double volume) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setMasterVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } on PlatformException {
      // Ignore - control will simply have no effect.
    } on MissingPluginException {
      // Ignore.
    }
  }

  /// Returns whether the default output device is muted, or null if unknown.
  static Future<bool?> getMute() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<bool>('getMute');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Sets the mute state of the default output device.
  static Future<void> setMute(bool mute) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setMute', {'mute': mute});
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }
}
