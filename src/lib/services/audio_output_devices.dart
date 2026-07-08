/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// A selectable audio output (speaker) device.
class AudioOutputDevice {
  const AudioOutputDevice({required this.id, required this.label});

  /// Stable identifier passed to the native player to select the device (the
  /// PulseAudio/PipeWire sink name on Linux, the waveOut device index as a
  /// string on Windows, or the CoreAudio device UID on macOS). Empty string
  /// means "OS default".
  final String id;

  /// Human-readable name shown in the UI.
  final String label;
}

/// Enumerates the audio output devices available for playback.
///
/// Implemented on Linux (via `pactl list sinks`), Windows and macOS (via the
/// native PCM player plugin's `listDevices` method). Other platforms return an
/// empty list and callers should fall back to the OS default output device.
class AudioOutputDevices {
  static const MethodChannel _channel =
      MethodChannel('com.htcommander/pcm_player');

  /// Whether specific output-device selection is supported on this platform.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  }

  /// Returns the list of output devices, or an empty list when enumeration is
  /// unsupported or fails. The returned ids match the `deviceId` accepted by
  /// the native PCM player; use an empty id for the OS default device.
  static Future<List<AudioOutputDevice>> list() async {
    if (!isSupported) return const <AudioOutputDevice>[];
    if (Platform.isLinux) return _listLinux();
    return _listNative();
  }

  /// Windows / macOS: queries the native PCM player plugin for output devices.
  static Future<List<AudioOutputDevice>> _listNative() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listDevices');
      if (result == null) return const <AudioOutputDevice>[];
      return result.map((entry) {
        final map = entry as Map<Object?, Object?>;
        final id = map['id'] as String? ?? '';
        final label = map['label'] as String? ?? id;
        return AudioOutputDevice(id: id, label: label);
      }).toList();
    } catch (_) {
      return const <AudioOutputDevice>[];
    }
  }

  /// Linux: shells out to `pactl list sinks` and parses the output.
  static Future<List<AudioOutputDevice>> _listLinux() async {
    try {
      // Force LC_ALL=C so the labels we parse are stable across locales.
      final result = await Process.run(
        'pactl',
        const ['list', 'sinks'],
        environment: const {'LC_ALL': 'C'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) return const <AudioOutputDevice>[];
      return _parseSinks((result.stdout as String).split('\n'));
    } catch (_) {
      return const <AudioOutputDevice>[];
    }
  }

  /// Parses the output of `pactl list sinks` into a list of output devices.
  ///
  /// Each sink block looks like:
  /// ```
  /// Sink #1
  ///   Name: alsa_output.pci-0000_00_1f.3.analog-stereo
  ///   Description: Built-in Audio Analog Stereo
  /// ```
  /// The `Name` is used as the device id (what PulseAudio expects) and the
  /// `Description` as the friendly label.
  static List<AudioOutputDevice> _parseSinks(List<String> lines) {
    final devices = <AudioOutputDevice>[];
    String? name;
    String? description;

    void commit() {
      final n = name;
      if (n != null && n.isNotEmpty) {
        final d = description;
        devices.add(
          AudioOutputDevice(
            id: n,
            label: (d != null && d.isNotEmpty) ? d : n,
          ),
        );
      }
    }

    for (final line in lines) {
      if (line.startsWith('Sink #')) {
        commit();
        name = null;
        description = null;
      } else {
        final trimmed = line.trim();
        if (trimmed.startsWith('Name:')) {
          name = trimmed.substring('Name:'.length).trim();
        } else if (trimmed.startsWith('Description:')) {
          description = trimmed.substring('Description:'.length).trim();
        }
      }
    }
    commit();

    return devices;
  }
}
