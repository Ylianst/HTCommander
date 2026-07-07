/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Platform-aware serial port implementation for desktop.
- Windows: uses Win32 API (kernel32.dll / advapi32.dll) via dart:ffi.
- macOS/Linux: attempts to load libserialport; falls back to /dev/ listing.
*/

import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Directory, Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Public enums (matching the libserialport API surface used by the app)
// ---------------------------------------------------------------------------

enum SerialPortFlowControl { none, xonXoff, rtsCts, dtrDsr }

enum SerialPortParity { invalid, none, odd, even, mark, space }

enum SerialPortDtr { invalid, off, on, flowControl }

enum SerialPortRts { invalid, off, on, flowControl }

// ---------------------------------------------------------------------------
// SerialPortConfig
// ---------------------------------------------------------------------------

class SerialPortConfig {
  int baudRate = 9600;
  int bits = 8;
  SerialPortParity parity = SerialPortParity.none;
  int stopBits = 1;
  SerialPortDtr dtr = SerialPortDtr.off;
  SerialPortRts rts = SerialPortRts.off;
  SerialPortFlowControl _flowControl = SerialPortFlowControl.none;

  void setFlowControl(SerialPortFlowControl value) {
    _flowControl = value;
  }

  void dispose() {}
}

// ---------------------------------------------------------------------------
// SerialPort
// ---------------------------------------------------------------------------

class SerialPort {
  SerialPort(this.name);

  final String name;

  /// Platform handle: HANDLE on Windows, fd on POSIX.
  int _handle = -1;

  bool get isOpen => _handle != -1 && _handle != _kInvalidHandleValue;

  /// Enumerates available serial ports on the current platform.
  static List<String> get availablePorts {
    if (Platform.isWindows) {
      return _Win32.enumeratePorts();
    } else {
      return _Posix.enumeratePorts();
    }
  }

  /// Opens the port for both reading and writing.
  bool openReadWrite() {
    if (Platform.isWindows) {
      return _Win32.open(this);
    } else {
      return _Posix.open(this);
    }
  }

  /// Applies a [SerialPortConfig] to this port.
  set config(SerialPortConfig cfg) {
    if (!isOpen) return;
    if (Platform.isWindows) {
      _Win32.setConfig(this, cfg);
    } else {
      _Posix.setConfig(this, cfg);
    }
  }

  /// Reads the current port configuration.
  SerialPortConfig get config {
    if (!isOpen) return SerialPortConfig();
    if (Platform.isWindows) {
      return _Win32.getConfig(this);
    } else {
      return _Posix.getConfig(this);
    }
  }

  /// Reads up to [maxBytes] from the port. Returns null if no data available.
  Uint8List? read(int maxBytes) {
    if (!isOpen) return null;
    if (Platform.isWindows) {
      return _Win32.read(this, maxBytes);
    } else {
      return _Posix.read(this, maxBytes);
    }
  }

  void close() {
    if (!isOpen) return;
    if (Platform.isWindows) {
      _Win32.close(this);
    } else {
      _Posix.close(this);
    }
  }

  void dispose() {
    close();
  }
}

// ---------------------------------------------------------------------------
// SerialPortReader — produces a stream of data chunks from a serial port.
// ---------------------------------------------------------------------------

class SerialPortReader {
  SerialPortReader(this._port, {int? timeout})
      : _controller = StreamController<Uint8List>.broadcast() {
    _startPolling();
  }

  final SerialPort _port;
  final StreamController<Uint8List> _controller;
  Timer? _timer;

  Stream<Uint8List> get stream => _controller.stream;

  void _startPolling() {
    // ReadFile is non-blocking (returns immediately), so polling at 100ms
    // is responsive enough for GPS NMEA data (1–10 Hz) without wasting CPU.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_controller.isClosed || !_port.isOpen) {
        close();
        return;
      }
      final data = _port.read(4096);
      if (data != null && data.isNotEmpty && !_controller.isClosed) {
        _controller.add(data);
      }
    });
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

// ===========================================================================
// Windows implementation (Win32 API via dart:ffi)
// ===========================================================================

const int _kInvalidHandleValue = -1;

class _Win32 {
  _Win32._();

  // -------------------------------------------------------------------------
  // Constants
  // -------------------------------------------------------------------------
  static const int _genericRead = 0x80000000;
  static const int _genericWrite = 0x40000000;
  static const int _openExisting = 3;

  // Registry
  static const int _hkeyLocalMachine = 0x80000002;
  static const int _keyRead = 0x20019;
  static const int _errorSuccess = 0;
  static const int _errorNoMoreItems = 259;

  // DCB flags bit positions
  static const int _fBinary = 0;
  static const int _fParity = 1;
  static const int _fOutxCtsFlow = 2;
  static const int _fOutxDsrFlow = 3;
  static const int _fDtrControl = 4; // 2 bits
  static const int _fDsrSensitivity = 6;
  static const int _fOutX = 8;
  static const int _fInX = 9;
  static const int _fRtsControl = 12; // 2 bits

  static const int _dtrControlDisable = 0;
  static const int _dtrControlEnable = 1;
  static const int _dtrControlHandshake = 2;
  static const int _rtsControlDisable = 0;
  static const int _rtsControlEnable = 1;
  static const int _rtsControlHandshake = 2;

  static const int _noparity = 0;
  static const int _oddparity = 1;
  static const int _evenparity = 2;
  static const int _markparity = 3;
  static const int _spaceparity = 4;

  static const int _onestopbit = 0;
  static const int _twostopbits = 2;

  static const int _purgeRxclear = 0x0008;
  static const int _purgeTxclear = 0x0004;

  // -------------------------------------------------------------------------
  // Lazy-loaded native function pointers
  // -------------------------------------------------------------------------
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _advapi32 = DynamicLibrary.open('advapi32.dll');

  static final _createFileW = _kernel32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32,
          Uint32, IntPtr),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
          int)>('CreateFileW');

  static final _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static final _getCommState = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('GetCommState');

  static final _setCommState = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('SetCommState');

  static final _setCommTimeouts = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('SetCommTimeouts');

  static final _readFile = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>,
          Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('ReadFile');

  static final _purgeComm = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Uint32),
      int Function(int, int)>('PurgeComm');

  static final _regOpenKeyExW = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(int, Pointer<Utf16>, int, int,
          Pointer<IntPtr>)>('RegOpenKeyExW');

  static final _regEnumValueW = _advapi32.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>,
          Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>),
      int Function(int, int, Pointer<Utf16>, Pointer<Uint32>,
          Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>)>(
      'RegEnumValueW');

  static final _regCloseKey = _advapi32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

  // -------------------------------------------------------------------------
  // DCB struct layout (28 bytes on x86/x64)
  // Offsets:  0: DCBlength(4), 4: BaudRate(4), 8: flags(4),
  //          12: wReserved(2), 14: XonLim(2), 16: XoffLim(2),
  //          18: ByteSize(1), 19: Parity(1), 20: StopBits(1),
  //          21: XonChar(1), 22: XoffChar(1), 23: ErrorChar(1),
  //          24: EofChar(1), 25: EvtChar(1), 26: wReserved1(2)
  // -------------------------------------------------------------------------
  static const int _dcbSize = 28;

  // COMMTIMEOUTS: 5 x DWORD = 20 bytes
  static const int _commTimeoutsSize = 20;

  // -------------------------------------------------------------------------
  // Port enumeration via registry
  // -------------------------------------------------------------------------
  static List<String> enumeratePorts() {
    final ports = <String>[];
    final subKey = r'HARDWARE\DEVICEMAP\SERIALCOMM'.toNativeUtf16();
    final phkResult = calloc<IntPtr>();

    try {
      final status =
          _regOpenKeyExW(_hkeyLocalMachine, subKey, 0, _keyRead, phkResult);
      if (status != _errorSuccess) return ports;

      final hKey = phkResult.value;
      final valueName = calloc<Uint16>(256).cast<Utf16>();
      final valueNameSize = calloc<Uint32>();
      final dataBuffer = calloc<Uint8>(512);
      final dataSize = calloc<Uint32>();

      try {
        for (var i = 0;; i++) {
          valueNameSize.value = 256;
          dataSize.value = 512;

          final result = _regEnumValueW(
            hKey, i, valueName, valueNameSize,
            nullptr, nullptr, dataBuffer, dataSize,
          );

          if (result == _errorNoMoreItems) break;
          if (result != _errorSuccess) continue;

          final portName = dataBuffer.cast<Utf16>().toDartString();
          if (portName.isNotEmpty) ports.add(portName);
        }
      } finally {
        _regCloseKey(hKey);
        calloc.free(valueName);
        calloc.free(valueNameSize);
        calloc.free(dataBuffer);
        calloc.free(dataSize);
      }
    } finally {
      calloc.free(subKey);
      calloc.free(phkResult);
    }

    ports.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return numA.compareTo(numB);
    });
    return ports;
  }

  // -------------------------------------------------------------------------
  // Open
  // -------------------------------------------------------------------------
  static bool open(SerialPort port) {
    final path =
        port.name.startsWith(r'\\') ? port.name : r'\\.\' + port.name;
    final lpFileName = path.toNativeUtf16();

    try {
      port._handle = _createFileW(
        lpFileName,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
    } finally {
      calloc.free(lpFileName);
    }

    if (port._handle == _kInvalidHandleValue) return false;

    // Set COMMTIMEOUTS for non-blocking reads: return immediately with
    // whatever bytes are already in the receive buffer.
    final timeouts = calloc<Uint8>(_commTimeoutsSize);
    // ReadIntervalTimeout = MAXDWORD → return immediately
    timeouts.cast<Uint32>()[0] = 0xFFFFFFFF;
    // ReadTotalTimeoutMultiplier = 0
    timeouts.cast<Uint32>()[1] = 0;
    // ReadTotalTimeoutConstant = 0
    timeouts.cast<Uint32>()[2] = 0;
    // WriteTotalTimeoutMultiplier = 0
    timeouts.cast<Uint32>()[3] = 0;
    // WriteTotalTimeoutConstant = 1000
    timeouts.cast<Uint32>()[4] = 1000;
    _setCommTimeouts(port._handle, timeouts);
    calloc.free(timeouts);

    _purgeComm(port._handle, _purgeRxclear | _purgeTxclear);
    return true;
  }

  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------
  static void setConfig(SerialPort port, SerialPortConfig cfg) {
    final dcb = calloc<Uint8>(_dcbSize);
    dcb.cast<Uint32>()[0] = _dcbSize; // DCBlength

    _getCommState(port._handle, dcb);

    // BaudRate
    dcb.cast<Uint32>()[1] = cfg.baudRate;

    // ByteSize (offset 18)
    dcb[18] = cfg.bits;

    // Parity (offset 19)
    switch (cfg.parity) {
      case SerialPortParity.none:
        dcb[19] = _noparity;
      case SerialPortParity.odd:
        dcb[19] = _oddparity;
      case SerialPortParity.even:
        dcb[19] = _evenparity;
      case SerialPortParity.mark:
        dcb[19] = _markparity;
      case SerialPortParity.space:
        dcb[19] = _spaceparity;
      default:
        dcb[19] = _noparity;
    }

    // StopBits (offset 20)
    dcb[20] = cfg.stopBits == 2 ? _twostopbits : _onestopbit;

    // Flags (offset 8, 4 bytes)
    var flags = 0;
    flags |= (1 << _fBinary);
    if (cfg.parity != SerialPortParity.none) flags |= (1 << _fParity);

    switch (cfg.dtr) {
      case SerialPortDtr.on:
        flags |= (_dtrControlEnable << _fDtrControl);
      case SerialPortDtr.flowControl:
        flags |= (_dtrControlHandshake << _fDtrControl);
      default:
        flags |= (_dtrControlDisable << _fDtrControl);
    }

    switch (cfg.rts) {
      case SerialPortRts.on:
        flags |= (_rtsControlEnable << _fRtsControl);
      case SerialPortRts.flowControl:
        flags |= (_rtsControlHandshake << _fRtsControl);
      default:
        flags |= (_rtsControlDisable << _fRtsControl);
    }

    switch (cfg._flowControl) {
      case SerialPortFlowControl.rtsCts:
        flags |= (1 << _fOutxCtsFlow);
        flags |= (_rtsControlHandshake << _fRtsControl);
      case SerialPortFlowControl.dtrDsr:
        flags |= (1 << _fOutxDsrFlow);
        flags |= (1 << _fDsrSensitivity);
        flags |= (_dtrControlHandshake << _fDtrControl);
      case SerialPortFlowControl.xonXoff:
        flags |= (1 << _fOutX);
        flags |= (1 << _fInX);
      case SerialPortFlowControl.none:
        break;
    }

    dcb.cast<Uint32>()[2] = flags;

    _setCommState(port._handle, dcb);
    calloc.free(dcb);
  }

  static SerialPortConfig getConfig(SerialPort port) {
    final cfg = SerialPortConfig();
    final dcb = calloc<Uint8>(_dcbSize);
    dcb.cast<Uint32>()[0] = _dcbSize;
    _getCommState(port._handle, dcb);

    cfg.baudRate = dcb.cast<Uint32>()[1];
    cfg.bits = dcb[18];

    switch (dcb[19]) {
      case _oddparity:
        cfg.parity = SerialPortParity.odd;
      case _evenparity:
        cfg.parity = SerialPortParity.even;
      case _markparity:
        cfg.parity = SerialPortParity.mark;
      case _spaceparity:
        cfg.parity = SerialPortParity.space;
      default:
        cfg.parity = SerialPortParity.none;
    }

    cfg.stopBits = dcb[20] == _twostopbits ? 2 : 1;
    calloc.free(dcb);
    return cfg;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------
  static Uint8List? read(SerialPort port, int maxBytes) {
    final buffer = calloc<Uint8>(maxBytes);
    final bytesRead = calloc<Uint32>();

    try {
      final result =
          _readFile(port._handle, buffer, maxBytes, bytesRead, nullptr);
      if (result == 0 || bytesRead.value == 0) return null;

      final data = Uint8List(bytesRead.value);
      for (var i = 0; i < bytesRead.value; i++) {
        data[i] = buffer[i];
      }
      return data;
    } finally {
      calloc.free(buffer);
      calloc.free(bytesRead);
    }
  }

  // -------------------------------------------------------------------------
  // Close
  // -------------------------------------------------------------------------
  static void close(SerialPort port) {
    _closeHandle(port._handle);
    port._handle = _kInvalidHandleValue;
  }
}

// ===========================================================================
// POSIX implementation (macOS / Linux) — uses libserialport if available,
// otherwise falls back to /dev/ directory listing for enumeration only.
// ===========================================================================

class _Posix {
  _Posix._();

  /// Cached reference to libserialport, or null if unavailable.
  static DynamicLibrary? _lib;
  static bool _libChecked = false;

  static DynamicLibrary? get _serialLib {
    if (!_libChecked) {
      _libChecked = true;
      try {
        _lib = DynamicLibrary.open(Platform.isMacOS
            ? 'libserialport.dylib'
            : 'libserialport.so');
      } catch (_) {
        _lib = null;
      }
    }
    return _lib;
  }

  // -------------------------------------------------------------------------
  // Port enumeration
  // -------------------------------------------------------------------------
  static List<String> enumeratePorts() {
    // Try libserialport first.
    final lib = _serialLib;
    if (lib != null) {
      try {
        return _enumerateWithLibSerialPort(lib);
      } catch (_) {
        // Fall through to /dev/ enumeration.
      }
    }
    return _enumerateFromDev();
  }

  /// Enumerates ports using libserialport's sp_list_ports / sp_get_port_name.
  static List<String> _enumerateWithLibSerialPort(DynamicLibrary lib) {
    // int sp_list_ports(struct sp_port ***list_ptr)
    final spListPorts = lib.lookupFunction<
        Int32 Function(Pointer<Pointer<Pointer<Void>>>),
        int Function(Pointer<Pointer<Pointer<Void>>>)>('sp_list_ports');
    // char *sp_get_port_name(const struct sp_port *port)
    final spGetPortName = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('sp_get_port_name');
    // void sp_free_port_list(struct sp_port **list)
    final spFreePortList = lib.lookupFunction<
        Void Function(Pointer<Pointer<Void>>),
        void Function(Pointer<Pointer<Void>>)>('sp_free_port_list');

    final listPtr = calloc<Pointer<Pointer<Void>>>();
    try {
      final ret = spListPorts(listPtr);
      if (ret != 0) return []; // SP_OK == 0

      final list = listPtr.value;
      final ports = <String>[];
      for (var i = 0; list[i] != nullptr; i++) {
        final namePtr = spGetPortName(list[i]);
        if (namePtr != nullptr) {
          ports.add(namePtr.toDartString());
        }
      }
      spFreePortList(list);
      return ports;
    } finally {
      calloc.free(listPtr);
    }
  }

  /// Fallback: list /dev/ entries that look like serial ports.
  static List<String> _enumerateFromDev() {
    final ports = <String>[];
    try {
      final dev = Directory('/dev');
      if (!dev.existsSync()) return ports;
      for (final entity in dev.listSync()) {
        final name = entity.path.split('/').last;
        if (Platform.isMacOS) {
          if (name.startsWith('cu.')) ports.add(entity.path);
        } else {
          // Linux
          if (name.startsWith('ttyUSB') ||
              name.startsWith('ttyACM') ||
              name.startsWith('ttyS')) {
            ports.add(entity.path);
          }
        }
      }
    } catch (_) {}
    ports.sort();
    return ports;
  }

  // -------------------------------------------------------------------------
  // Open / Config / Read / Close — delegates to libserialport if available.
  // If not, serial communication is unavailable (only enumeration works).
  // -------------------------------------------------------------------------

  static bool open(SerialPort port) {
    final lib = _serialLib;
    if (lib == null) return false;
    try {
      return _openWithLib(lib, port);
    } catch (_) {
      return false;
    }
  }

  static bool _openWithLib(DynamicLibrary lib, SerialPort port) {
    final spGetPortByName = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>),
        int Function(
            Pointer<Utf8>, Pointer<Pointer<Void>>)>('sp_get_port_by_name');
    final spOpen = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('sp_open');

    final namePtr = port.name.toNativeUtf8();
    final portPtr = calloc<Pointer<Void>>();
    try {
      if (spGetPortByName(namePtr, portPtr) != 0) return false;
      // SP_MODE_READ_WRITE = 3
      if (spOpen(portPtr.value, 3) != 0) return false;
      // Store the sp_port pointer as an integer handle.
      port._handle = portPtr.value.address;
      return true;
    } finally {
      calloc.free(namePtr);
      calloc.free(portPtr);
    }
  }

  static void setConfig(SerialPort port, SerialPortConfig cfg) {
    final lib = _serialLib;
    if (lib == null) return;
    try {
      final spSetBaudrate = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('sp_set_baudrate');
      final spSetBits = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('sp_set_bits');
      final spSetParity = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('sp_set_parity');
      final spSetStopbits = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('sp_set_stopbits');
      final spSetFlowcontrol = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('sp_set_flowcontrol');

      final spPort = Pointer<Void>.fromAddress(port._handle);
      spSetBaudrate(spPort, cfg.baudRate);
      spSetBits(spPort, cfg.bits);

      int parityVal = 0; // SP_PARITY_NONE
      switch (cfg.parity) {
        case SerialPortParity.odd:
          parityVal = 1;
        case SerialPortParity.even:
          parityVal = 2;
        case SerialPortParity.mark:
          parityVal = 3;
        case SerialPortParity.space:
          parityVal = 4;
        default:
          parityVal = 0;
      }
      spSetParity(spPort, parityVal);
      spSetStopbits(spPort, cfg.stopBits);

      int fcVal = 0; // SP_FLOWCONTROL_NONE
      switch (cfg._flowControl) {
        case SerialPortFlowControl.xonXoff:
          fcVal = 1;
        case SerialPortFlowControl.rtsCts:
          fcVal = 2;
        case SerialPortFlowControl.dtrDsr:
          fcVal = 3;
        default:
          fcVal = 0;
      }
      spSetFlowcontrol(spPort, fcVal);
    } catch (_) {}
  }

  static SerialPortConfig getConfig(SerialPort port) {
    // Return a default config; full readback is not critical.
    return SerialPortConfig();
  }

  static Uint8List? read(SerialPort port, int maxBytes) {
    final lib = _serialLib;
    if (lib == null) return null;
    try {
      // int sp_nonblocking_read(struct sp_port *port, void *buf, size_t count)
      final spRead = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr),
          int Function(
              Pointer<Void>, Pointer<Uint8>, int)>('sp_nonblocking_read');

      final buf = calloc<Uint8>(maxBytes);
      try {
        final spPort = Pointer<Void>.fromAddress(port._handle);
        final n = spRead(spPort, buf, maxBytes);
        if (n <= 0) return null;
        final data = Uint8List(n);
        for (var i = 0; i < n; i++) {
          data[i] = buf[i];
        }
        return data;
      } finally {
        calloc.free(buf);
      }
    } catch (_) {
      return null;
    }
  }

  static void close(SerialPort port) {
    final lib = _serialLib;
    if (lib == null) return;
    try {
      final spClose = lib.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('sp_close');
      final spFreePort = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('sp_free_port');

      final spPort = Pointer<Void>.fromAddress(port._handle);
      spClose(spPort);
      spFreePort(spPort);
    } catch (_) {}
    port._handle = -1;
  }
}
