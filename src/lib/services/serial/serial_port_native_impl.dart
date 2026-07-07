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
// POSIX implementation (macOS / Linux) — native libc / termios via dart:ffi.
//
// This talks directly to the C library (open/read/close/tcgetattr/tcsetattr/
// ioctl) so no external native library (e.g. libserialport) needs to be
// installed or bundled. Port enumeration lists matching /dev/ entries.
// ===========================================================================

class _Posix {
  _Posix._();

  // -------------------------------------------------------------------------
  // libc bindings (symbols are always present in the running process).
  // -------------------------------------------------------------------------
  static final DynamicLibrary _libc = DynamicLibrary.process();

  // int open(const char *path, int oflag, ...)
  static final _open = _libc.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('open');

  // int close(int fd)
  static final _close = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  // ssize_t read(int fd, void *buf, size_t count)
  static final _read = _libc.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)>('read');

  // int tcgetattr(int fd, struct termios *)
  static final _tcgetattr = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('tcgetattr');

  // int tcsetattr(int fd, int action, const struct termios *)
  static final _tcsetattr = _libc.lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Uint8>),
      int Function(int, int, Pointer<Uint8>)>('tcsetattr');

  // void cfmakeraw(struct termios *)
  static final _cfmakeraw = _libc.lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)>('cfmakeraw');

  // int cfsetispeed(struct termios *, speed_t) / cfsetospeed(...)
  static final _cfsetispeed = _libc.lookupFunction<
      Int32 Function(Pointer<Uint8>, IntPtr),
      int Function(Pointer<Uint8>, int)>('cfsetispeed');
  static final _cfsetospeed = _libc.lookupFunction<
      Int32 Function(Pointer<Uint8>, IntPtr),
      int Function(Pointer<Uint8>, int)>('cfsetospeed');

  // int ioctl(int fd, unsigned long request, ...)
  static final _ioctl = _libc.lookupFunction<
      Int32 Function(Int32, IntPtr, Pointer<Int32>),
      int Function(int, int, Pointer<Int32>)>('ioctl');

  // -------------------------------------------------------------------------
  // Platform-dependent constants.
  // -------------------------------------------------------------------------
  static final bool _isMac = Platform.isMacOS;

  // open() flags.
  static int get _oRdwr => 0x0002; // O_RDWR (same on macOS/Linux)
  static int get _oNoctty => _isMac ? 0x20000 : 0x0100; // O_NOCTTY
  static int get _oNonblock => _isMac ? 0x0004 : 0x0800; // O_NONBLOCK

  // termios buffer size (over-allocated to safely cover both layouts).
  static const int _termiosSize = 128;

  // Offset & width of c_cflag within struct termios.
  //  - macOS (BSD): tcflag_t = unsigned long (8 bytes); c_cflag at offset 16.
  //  - Linux (glibc): tcflag_t = unsigned int (4 bytes); c_cflag at offset 8.
  static int get _cflagOffset => _isMac ? 16 : 8;
  static bool get _cflagIs64 => _isMac;

  // Control-mode flag bits.
  static int get _csize => _isMac ? 0x0300 : 0x0030;
  static int get _cs8 => _isMac ? 0x0300 : 0x0030;
  static int get _cstopb => _isMac ? 0x0400 : 0x0040;
  static int get _cread => _isMac ? 0x0800 : 0x0080;
  static int get _parenb => _isMac ? 0x1000 : 0x0100;
  static int get _clocal => _isMac ? 0x8000 : 0x0800;
  // Hardware flow control (CCTS_OFLOW|CRTS_IFLOW on macOS, CRTSCTS on Linux).
  static int get _crtscts => _isMac ? 0x00030000 : 0x80000000;

  static const int _tcsanow = 0;

  // ioctl requests / modem bits for raising DTR & RTS.
  static int get _tiocmbis => _isMac ? 0x8004746c : 0x5416;
  static const int _tiocmDtr = 0x002;
  static const int _tiocmRts = 0x004;

  // -------------------------------------------------------------------------
  // Port enumeration — list /dev/ entries that look like serial ports.
  // -------------------------------------------------------------------------
  static List<String> enumeratePorts() => _enumerateFromDev();

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
  // Open — opens the tty non-blocking so reads return immediately.
  // -------------------------------------------------------------------------
  static bool open(SerialPort port) {
    final namePtr = port.name.toNativeUtf8();
    try {
      final fd = _open(namePtr, _oRdwr | _oNoctty | _oNonblock);
      if (fd < 0) return false;
      port._handle = fd;
      return true;
    } catch (_) {
      return false;
    } finally {
      calloc.free(namePtr);
    }
  }

  // -------------------------------------------------------------------------
  // Configuration — sets baud rate, 8 data bits, no parity, 1 stop bit and the
  // requested DTR/RTS lines. Flow control other than "none" is treated as none
  // (GPS receivers stream data and do not require handshaking).
  // -------------------------------------------------------------------------
  static void setConfig(SerialPort port, SerialPortConfig cfg) {
    final fd = port._handle;
    if (fd < 0) return;

    final tio = calloc<Uint8>(_termiosSize);
    try {
      if (_tcgetattr(fd, tio) != 0) return;

      // Raw mode: disable canonical processing, echo, signals, translations.
      _cfmakeraw(tio);

      // Adjust control flags for 8N1 + local line + receiver enabled.
      final cflagPtr = Pointer<Uint8>.fromAddress(tio.address + _cflagOffset);
      int cflag = _cflagIs64
          ? cflagPtr.cast<Uint64>().value
          : cflagPtr.cast<Uint32>().value;

      cflag &= ~_csize; // clear data-size bits
      cflag |= _cs8; // 8 data bits

      if (cfg.parity == SerialPortParity.none) {
        cflag &= ~_parenb;
      } else {
        cflag |= _parenb;
      }

      if (cfg.stopBits == 2) {
        cflag |= _cstopb;
      } else {
        cflag &= ~_cstopb;
      }

      // No hardware flow control; always enable receiver and ignore modem
      // control lines so the port opens without a carrier signal.
      cflag &= ~_crtscts;
      cflag |= _clocal | _cread;

      if (_cflagIs64) {
        cflagPtr.cast<Uint64>().value = cflag;
      } else {
        cflagPtr.cast<Uint32>().value = cflag & 0xFFFFFFFF;
      }

      // Baud rate. On macOS speed_t is the literal rate, so arbitrary values
      // (e.g. non-standard baud) work directly. On Linux cfsetispeed maps the
      // value to a Bxxxx constant; unsupported rates fall back to the closest.
      final baud = _isMac ? cfg.baudRate : _linuxBaud(cfg.baudRate);
      _cfsetispeed(tio, baud);
      _cfsetospeed(tio, baud);

      _tcsetattr(fd, _tcsanow, tio);
    } catch (_) {
      // Ignore configuration failures; the port stays usable at its defaults.
    } finally {
      calloc.free(tio);
    }

    // Raise DTR and RTS if requested (some receivers need DTR high to power).
    if (cfg.dtr == SerialPortDtr.on || cfg.rts == SerialPortRts.on) {
      final bits = calloc<Int32>();
      try {
        var v = 0;
        if (cfg.dtr == SerialPortDtr.on) v |= _tiocmDtr;
        if (cfg.rts == SerialPortRts.on) v |= _tiocmRts;
        bits.value = v;
        _ioctl(fd, _tiocmbis, bits);
      } catch (_) {
      } finally {
        calloc.free(bits);
      }
    }
  }

  /// Maps a numeric baud rate to the Linux termios Bxxxx constant.
  /// Falls back to B9600 for unrecognized rates.
  static int _linuxBaud(int baud) {
    const map = <int, int>{
      1200: 0x0009,
      1800: 0x000a,
      2400: 0x000b,
      4800: 0x000c,
      9600: 0x000d,
      19200: 0x000e,
      38400: 0x000f,
      57600: 0x1001,
      115200: 0x1002,
      230400: 0x1003,
      460800: 0x1004,
      921600: 0x1007,
    };
    return map[baud] ?? 0x000d; // default B9600
  }

  static SerialPortConfig getConfig(SerialPort port) {
    // Return a default config; full readback is not required by the app.
    return SerialPortConfig();
  }

  static Uint8List? read(SerialPort port, int maxBytes) {
    final fd = port._handle;
    if (fd < 0) return null;
    final buf = calloc<Uint8>(maxBytes);
    try {
      final n = _read(fd, buf, maxBytes);
      if (n <= 0) return null; // 0 = EOF, -1 = EAGAIN/error (no data yet)
      final data = Uint8List(n);
      for (var i = 0; i < n; i++) {
        data[i] = buf[i];
      }
      return data;
    } catch (_) {
      return null;
    } finally {
      calloc.free(buf);
    }
  }

  static void close(SerialPort port) {
    final fd = port._handle;
    if (fd >= 0) {
      try {
        _close(fd);
      } catch (_) {}
    }
    port._handle = -1;
  }
}
