/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Conditional-import facade for serial port access.
///
/// On platforms with `dart:io` (desktop) this re-exports the real
/// `libserialport` API. On the web (no `dart:io`) it resolves to a
/// stub that provides the same symbols so the application compiles, while
/// serial access remains unavailable (all call sites are guarded by `kIsWeb`).
library;

export 'serial_port_stub.dart' if (dart.library.io) 'serial_port_io.dart';
