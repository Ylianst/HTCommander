#pragma once
// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0

#include <memory>

// Forward declaration only — no Win32, SAPI or Flutter headers needed here.
namespace flutter {
class BinaryMessenger;
}

/// Native Windows text-to-speech plugin backed by SAPI 5 (`ISpVoice`).
///
/// flutter_tts has no working Windows synthesis path (its `synthesizeToFile` /
/// `awaitSynthCompletion` methods are unimplemented on Windows), so this native
/// plugin provides the same in-memory synthesis the Apple runners expose. It
/// serves the identical MethodChannel contract consumed by
/// lib/services/tts_service_io.dart:
///   MethodChannel  com.htcommander/tts
///     getVoices() -> [{name, locale, identifier, gender}]
///     synthesize({text, voiceIdentifier, locale, rate, pitch})
///         -> { samples: Float32List (mono, -1..1), sampleRate: int } | null
///     preview({text, voiceIdentifier, locale, rate, pitch}) -> null
///     stopPreview() -> null
///
/// SAPI renders raw 16-bit PCM directly into an in-memory stream at a fixed
/// sample rate; the samples are converted to mono float and returned to Dart,
/// which resamples them to the 32 kHz radio audio format. Nothing is written to
/// disk.
class TtsPlugin {
 public:
  explicit TtsPlugin(flutter::BinaryMessenger* messenger);
  ~TtsPlugin();

  TtsPlugin(const TtsPlugin&) = delete;
  TtsPlugin& operator=(const TtsPlugin&) = delete;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
