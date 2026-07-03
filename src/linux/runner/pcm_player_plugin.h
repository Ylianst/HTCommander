// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Native Linux PCM playback plugin.
//
// flutter_pcm_sound only supports Android / iOS / macOS, so this native plugin
// provides the equivalent streaming PCM sink on Linux for the radio audio path.
// It exposes the same channels as the Windows waveOut plugin so the Dart-side
// _NativeChannelPcmPlayer works unchanged:
//   - MethodChannel  com.htcommander/pcm_player
//   - EventChannel   com.htcommander/pcm_player_feed  (remaining buffered frames)

#ifndef RUNNER_PCM_PLAYER_PLUGIN_H_
#define RUNNER_PCM_PLAYER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers the PCM player plugin channels. Safe to call once.
void pcm_player_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // RUNNER_PCM_PLAYER_PLUGIN_H_
