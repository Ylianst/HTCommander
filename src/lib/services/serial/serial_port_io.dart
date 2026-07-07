/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Desktop (dart:io) serial port implementation.
///
/// On Windows, uses a native Win32 implementation (no external DLL required).
/// On macOS/Linux, falls back to the libserialport package.
library;

export 'serial_port_native.dart';
