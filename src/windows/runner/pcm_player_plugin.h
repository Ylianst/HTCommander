#pragma once
// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0

#include <memory>

// Forward declaration only — no Win32 or Flutter headers needed here.
namespace flutter {
class BinaryMessenger;
}
class NativePcmOutput;

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
///       Notifications may coalesce while the platform thread is busy.
/// Setup/feed rejection is returned as a MethodChannel error. Feed success means
/// bounded enqueue; asynchronous device errors are logged/counted by the sink.
class PcmPlayerPlugin {
 public:
  explicit PcmPlayerPlugin(flutter::BinaryMessenger* messenger);
  ~PcmPlayerPlugin();

  PcmPlayerPlugin(const PcmPlayerPlugin&) = delete;
  PcmPlayerPlugin& operator=(const PcmPlayerPlugin&) = delete;

  // The same device used by Dart. Connections may retain it independently of
  // the plugin; destruction detaches platform notifications and releases audio.
  std::shared_ptr<NativePcmOutput> output() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
