#pragma once
// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0

#include <memory>

// Forward declaration only — no Win32 or Flutter headers needed here.
namespace flutter {
class BinaryMessenger;
}

/// Native Windows PCM playback plugin (16-bit signed PCM) using the Win32
/// waveOut (winmm) API.
///
/// flutter_pcm_sound has no Windows implementation, so this provides an
/// equivalent low-latency streaming sink for the radio audio path. The Dart
/// wrapper lib/radio/pcm_player.dart talks to it over:
///   - MethodChannel  com.htcommander/pcm_player
///       setup{sampleRate,channels} | feed{buffer} | setFeedThreshold{threshold}
///       | start | release | setLogLevel
///   - EventChannel   com.htcommander/pcm_player_feed
///       emits the remaining buffered frame count after each buffer finishes.
class PcmPlayerPlugin {
 public:
  explicit PcmPlayerPlugin(flutter::BinaryMessenger* messenger);
  ~PcmPlayerPlugin();

  PcmPlayerPlugin(const PcmPlayerPlugin&) = delete;
  PcmPlayerPlugin& operator=(const PcmPlayerPlugin&) = delete;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
