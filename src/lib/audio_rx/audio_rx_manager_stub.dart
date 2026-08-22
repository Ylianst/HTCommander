/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// audio_rx_manager_stub.dart - No-op Audio Receive Device manager for the web
// build. Audio Receive Devices rely on native audio capture and the dart:io
// software modem, neither of which exist in the browser, so `main.dart`
// conditionally imports this stub on web.
//

/// Web stub: does nothing. Mirrors the real [AudioRxManager] surface used by
/// `main()`.
class AudioRxManager {
  AudioRxManager([Object? softwareModem]);

  void init() {}

  Future<void> dispose() async {}
}
