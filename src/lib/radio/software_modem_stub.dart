/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web stub for the software modem. The web build has no audio channel, so the
soft-modem cannot run there. This stub replaces radio/software_modem.dart via a
conditional import (see main.dart) so that none of the hamlib DSP code is pulled
into the web build. It exposes the same public surface used by the app
(constructor + init/dispose) but performs no work.
*/

/// No-op software modem used on platforms without an audio channel (web).
class SoftwareModem {
  /// Matches the native handler API; does nothing on the web.
  void init() {}

  /// Matches the native handler API; does nothing on the web.
  void dispose() {}
}
