/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_stream_transport.dart - MeshCore companion links over USB serial
// (desktop) and TCP / Wi-Fi (desktop and mobile). Both use the '<' / '>'
// length-prefixed framing from meshcore_protocol.dart.
//
// The companion firmware is built per interface: a USB link needs the USB
// companion firmware, a Wi-Fi link the Wi-Fi firmware (default TCP port 5000).
//

import 'dart:async';
import 'dart:io' show InternetAddress, Platform, Socket, SocketOption;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/serial/serial_port.dart';
import 'meshcore_client.dart';
import 'meshcore_protocol.dart';

/// Default TCP port of the Wi-Fi companion firmware.
const int meshCoreDefaultTcpPort = 5000;

/// Baud rate of the USB companion firmware.
const int meshCoreSerialBaud = 115200;

/// USB serial is available on desktop builds only.
bool get meshCoreSerialSupported =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// TCP needs dart:io sockets, which the web build does not have.
bool get meshCoreTcpSupported => !kIsWeb;

/// Serial ports that could host a MeshCore companion.
List<String> meshCoreSerialPorts() =>
    meshCoreSerialSupported ? SerialPort.availablePorts : const [];

class MeshCoreSerialTransport implements MeshCoreTransport {
  MeshCoreSerialTransport._(this._name, this._port);

  final String _name;
  final SerialPort _port;
  final _decoder = MeshCoreStreamDecoder();
  final _frames = StreamController<Uint8List>.broadcast();
  final _disconnected = StreamController<void>.broadcast();
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readSub;
  Timer? _presenceTimer;
  bool _closed = false;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  static Future<MeshCoreSerialTransport> open(String portName) async {
    if (!meshCoreSerialSupported) {
      throw const MeshCoreException('USB serial is not supported here.');
    }
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final denied = port.lastOpenPermissionDenied;
      port.dispose();
      throw MeshCoreException(
        denied
            ? 'Permission denied opening $portName.'
            : 'Unable to open $portName. It may be in use by another program.',
      );
    }
    final config = SerialPortConfig()
      ..baudRate = meshCoreSerialBaud
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none)
      // Matches the official clients; on ESP32 boards with auto-reset
      // circuitry both lines high keeps the chip running.
      ..dtr = SerialPortDtr.on
      ..rts = SerialPortRts.on;
    port.config = config;
    config.dispose();
    final transport = MeshCoreSerialTransport._(portName, port);
    transport._start();
    return transport;
  }

  void _start() {
    final reader = SerialPortReader(
      _port,
      pollInterval: const Duration(milliseconds: 15),
    );
    _reader = reader;
    _readSub = reader.stream.listen((data) {
      for (final f in _decoder.add(data)) {
        if (!_frames.isClosed) _frames.add(f);
      }
    });
    // A USB unplug does not error the non-blocking reads, so watch for the
    // port disappearing from the system.
    _presenceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!SerialPort.availablePorts.contains(_name)) _lost();
    });
  }

  void _lost() {
    if (_closed) return;
    _closed = true;
    _disconnected.add(null);
  }

  @override
  Future<void> sendFrame(Uint8List frame) async {
    if (_closed) throw const MeshCoreException('Not connected');
    final data = encodeStreamFrame(frame);
    if (_port.write(data) != data.length) {
      _lost();
      throw const MeshCoreException('Write to the serial port failed');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _presenceTimer?.cancel();
    await _readSub?.cancel();
    _reader?.close();
    // Some USB-serial drivers block on close after recent I/O.
    final port = _port;
    unawaited(
      Future(() {
        try {
          if (port.isOpen) port.close();
        } catch (_) {}
        try {
          port.dispose();
        } catch (_) {}
      }),
    );
    await _frames.close();
    await _disconnected.close();
  }
}

class MeshCoreTcpTransport implements MeshCoreTransport {
  MeshCoreTcpTransport._(this._socket);

  final Socket _socket;
  final _decoder = MeshCoreStreamDecoder();
  final _frames = StreamController<Uint8List>.broadcast();
  final _disconnected = StreamController<void>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  bool _closed = false;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  static Future<MeshCoreTcpTransport> connect(String host, int port) async {
    if (!meshCoreTcpSupported) {
      throw const MeshCoreException('TCP is not supported here.');
    }
    final Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      throw MeshCoreException('Unable to connect to $host:$port ($e)');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final transport = MeshCoreTcpTransport._(socket);
    transport._start();
    return transport;
  }

  void _start() {
    _sub = _socket.listen(
      (data) {
        for (final f in _decoder.add(data)) {
          if (!_frames.isClosed) _frames.add(f);
        }
      },
      onError: (_) => _lost(),
      onDone: _lost,
      cancelOnError: true,
    );
  }

  void _lost() {
    if (_closed) return;
    _closed = true;
    _disconnected.add(null);
  }

  @override
  Future<void> sendFrame(Uint8List frame) async {
    if (_closed) throw const MeshCoreException('Not connected');
    _socket.add(encodeStreamFrame(frame));
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _sub?.cancel();
    try {
      _socket.destroy();
    } catch (_) {}
    await _frames.close();
    await _disconnected.close();
  }
}

/// Parses "host:port" (or "[v6]:port"); the port defaults to 5000.
({String host, int port})? parseMeshCoreTcpTarget(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  var port = meshCoreDefaultTcpPort;
  if (t.startsWith('[')) {
    final end = t.indexOf(']');
    if (end < 0) return null;
    final rest = t.substring(end + 1);
    if (rest.startsWith(':')) {
      final p = int.tryParse(rest.substring(1));
      if (p == null) return null;
      port = p;
    }
    t = t.substring(1, end);
  } else if (t.indexOf(':') == t.lastIndexOf(':') && t.contains(':')) {
    final p = int.tryParse(t.substring(t.indexOf(':') + 1));
    if (p == null) return null;
    port = p;
    t = t.substring(0, t.indexOf(':'));
  }
  if (t.isEmpty || port < 1 || port > 65535) return null;
  if (InternetAddress.tryParse(t) == null &&
      !RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.\-]*[A-Za-z0-9])?$').hasMatch(t)) {
    return null;
  }
  return (host: t, port: port);
}
