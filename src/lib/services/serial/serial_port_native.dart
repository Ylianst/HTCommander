/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Native desktop serial port implementation.
- Windows: uses Win32 API via dart:ffi (kernel32/advapi32) — no external DLL.
- macOS/Linux: tries libserialport; falls back to /dev/ enumeration.
*/

export 'serial_port_native_impl.dart';
