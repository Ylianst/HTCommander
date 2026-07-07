/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// Web stub for serial port access. Mirrors the subset of the
// `libserialport` API used by the application so that web builds
// compile. None of these are ever invoked on the web because every call site
// is guarded by `kIsWeb` / a desktop platform check.

import 'dart:typed_data';

/// Stub flow-control modes.
enum SerialPortFlowControl { none, xonXoff, rtsCts, dtrDsr }

/// Stub parity modes.
enum SerialPortParity { invalid, none, odd, even, mark, space }

/// Stub DTR pin states.
enum SerialPortDtr { invalid, off, on, flowControl }

/// Stub RTS pin states.
enum SerialPortRts { invalid, off, on, flowControl }

/// Stub serial port. Serial access is unavailable on the web.
class SerialPort {
  SerialPort(this.name);

  final String name;

  /// Always false on the web (serial access is unavailable).
  bool lastOpenPermissionDenied = false;

  /// No ports are available on the web.
  static List<String> get availablePorts => const <String>[];

  bool get isOpen => false;

  bool openReadWrite() => false;

  void close() {}

  void dispose() {}

  set config(SerialPortConfig value) {}

  SerialPortConfig get config => SerialPortConfig();
}

/// Stub serial port configuration.
class SerialPortConfig {
  int baudRate = 0;
  int bits = 0;
  SerialPortParity parity = SerialPortParity.none;
  int stopBits = 0;
  SerialPortDtr dtr = SerialPortDtr.off;
  SerialPortRts rts = SerialPortRts.off;

  void setFlowControl(SerialPortFlowControl value) {}

  void dispose() {}
}

/// Stub serial port reader producing no data.
class SerialPortReader {
  SerialPortReader(SerialPort port, {int? timeout});

  Stream<Uint8List> get stream => const Stream<Uint8List>.empty();

  void close() {}
}
