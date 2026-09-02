/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Inert stub of [HostAudioPlayer] for platforms with `dart:io` (everything except
the browser). Those platforms play audio natively, so mirroring the host's audio
into a browser audio context is unnecessary; every method is a no-op.
*/

import 'dart:typed_data';

/// No-op host audio player used off the web.
class HostAudioPlayer {
  double volume = 1.0;

  bool get isRunning => false;

  Future<void> resume() async {}

  Future<void> suspend() async {}

  void feed(Int16List pcm, int sampleRate, int channels) {}

  Future<void> dispose() async {}
}
