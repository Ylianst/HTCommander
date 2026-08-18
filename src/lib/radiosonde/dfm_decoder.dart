/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for Graw DFM-06/09/17 radiosondes. Ported from the reference
`dfm09mod.c` decoder in projecthorus/radiosonde_auto_rx (author zilog80).

A DFM frame is 280 bits: a 16-bit header (0x45CF) followed by a 56-bit config
block and two 104-bit data blocks. Each block is bit-interleaved and protected
by a Hamming(8,4) code. The config blocks carry the sonde serial number and PTU
(temperature) calibration; the data blocks carry GPS position/velocity and the
date. Because those fields are spread across many consecutive frames, the
decoder keeps state and emits a [DfmFrame] once a complete GPS fix is gathered.
*/

library;

import 'dart:math' as math;

/// A decoded DFM radiosonde fix (one complete set of GPS packets).
class DfmFrame {
  DfmFrame({
    required this.frameNumber,
    required this.sondeId,
    required this.dfmType,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.satellites,
    required this.dateTimeUtc,
    this.temperatureC,
  });

  /// DFM frame counter (0..255, wraps).
  final int frameNumber;

  /// Sonde identifier, e.g. "ID9:123456" (empty until the serial is resolved).
  final String sondeId;

  /// Detected DFM subtype label, e.g. "DFM09" (empty if unknown).
  final String dfmType;

  final double latitude;
  final double longitude;

  /// Altitude in metres (GPS/ellipsoid for mode<=2, MSL otherwise).
  final double altitude;

  /// Horizontal speed in m/s.
  final double horizontalSpeed;

  /// Vertical speed in m/s.
  final double verticalSpeed;

  /// Course over ground in degrees.
  final double heading;

  /// Number of GPS satellites used in the solution.
  final int satellites;

  /// UTC timestamp reported by the sonde.
  final DateTime dateTimeUtc;

  /// Air temperature in Celsius, when PTU calibration is available.
  final double? temperatureC;

  @override
  String toString() =>
      'DFM[$frameNumber] $sondeId ($dfmType) '
      'lat=$latitude lon=$longitude alt=${altitude.toStringAsFixed(1)} '
      'vH=${horizontalSpeed.toStringAsFixed(1)} vV=${verticalSpeed.toStringAsFixed(1)} '
      'dir=${heading.toStringAsFixed(1)} sats=$satellites '
      '${temperatureC != null ? 'T=${temperatureC!.toStringAsFixed(1)}C ' : ''}'
      '$dateTimeUtc';
}

/// Stateful DFM frame parser. Feed raw 280-bit frames via [decodeFrame]; a
/// [DfmFrame] is returned whenever a fresh, complete GPS fix becomes available.
class DfmDecoder {
  DfmDecoder();

  // --- Frame layout (bit offsets into the 280-bit frame) ---
  static const int _head = 0; //  16 bit
  static const int _conf = 16; //  56 bit
  static const int _dat1 = 16 + 56; // 104 bit
  static const int _dat2 = 16 + 160; // 104 bit
  static const int frameBits = 280;

  /// Decoded 16-bit header value.
  static const int header = 0x45CF;

  // Hamming(8,4) generator (systematic: first 4 rows identity).
  static const List<List<int>> _g = [
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1],
    [0, 1, 1, 1],
    [1, 0, 1, 1],
    [1, 1, 0, 1],
    [1, 1, 1, 0],
  ];

  // Parity-check matrix.
  static const List<List<int>> _h = [
    [0, 1, 1, 1, 1, 0, 0, 0],
    [1, 0, 1, 1, 0, 1, 0, 0],
    [1, 1, 0, 1, 0, 0, 1, 0],
    [1, 1, 1, 0, 0, 0, 0, 1],
  ];

  // 1-bit-error syndromes (columns of H).
  static const List<int> _he = [0x7, 0xB, 0xD, 0xE, 0x8, 0x4, 0x2, 0x1];

  // --- Accumulated sonde state (spans many frames) ---
  int _frnr = 0;
  int _sondeTyp = 0; // 0x100 bit => serial resolved; low nibble = channel/type
  int _sn6 = 0;
  int _sn = 0;
  String _sondeId = '';
  String _dfmType = '';
  int _posmode = 2;

  // Config channel accumulation for the serial number.
  int _maxCh = 0;
  int _nulCh = 0;
  int _snCh = 0;
  int _chXbit = 0;
  int _snX = 0;
  final List<int> _chX = [0, 0];

  // PTU / temperature calibration.
  final List<double> _meas24 = List<double>.filled(9, 0);
  final List<int> _cfgchk24 = List<int>.filled(9, 0);
  int _cfgchk = 0;
  int _ptuOut = 0;
  String _sensorTyp = 'T';
  double _rf = 220e3;

  // GPS/date fields plus their per-field frame timestamps for freshness.
  int _frameCounter = 0;
  final List<double> _pckTs = List<double>.filled(9, -1e9);
  double _sek = 0;
  double _lat = 0, _lon = 0, _alt = 0;
  double _dir = 0, _horiV = 0, _vertV = 0;
  int _jahr = 0, _monat = 0, _tag = 0, _std = 0, _min = 0;
  int _nSV = 0, _nPRN = 0;

  static const List<int> _idFr = [0, 1, 2, 3, 4, 8];

  /// Precomputed Hamming codewords (lazy).
  static List<List<int>>? _codewords;

  static List<List<int>> _buildCodewords() {
    final cw = List<List<int>>.generate(16, (_) => List<int>.filled(8, 0));
    for (int nib = 0; nib < 16; nib++) {
      final msg = [
        (nib >> 3) & 1,
        (nib >> 2) & 1,
        (nib >> 1) & 1,
        nib & 1,
      ];
      for (int i = 0; i < 8; i++) {
        int c = 0;
        for (int j = 0; j < 4; j++) {
          c ^= _g[i][j] & msg[j];
        }
        cw[nib][i] = c;
      }
    }
    return cw;
  }

  /// Decodes one 280-bit frame (hard bits, MSB-first per field as read off the
  /// wire). Returns a [DfmFrame] when it completes a GPS fix, else null.
  DfmFrame? decodeFrame(List<int> frame) {
    if (frame.length < frameBits) return null;
    _codewords ??= _buildCodewords();
    _frameCounter++;

    // Verify the header to reject noise.
    int hdr = 0;
    for (int i = 0; i < 16; i++) {
      hdr = (hdr << 1) | (frame[_head + i] & 1);
    }
    if (hdr != header) return null;

    final confBlk = _decodeBlock(frame, _conf, 7);
    final dat1Blk = _decodeBlock(frame, _dat1, 13);
    final dat2Blk = _decodeBlock(frame, _dat2, 13);

    _confOut(confBlk);
    DfmFrame? out;
    final f1 = _datOut(dat1Blk);
    if (f1 != null) out = f1;
    final f2 = _datOut(dat2Blk);
    if (f2 != null) out = f2;
    return out;
  }

  // Deinterleave + Hamming decode a block of L codewords -> L*4 data bits.
  List<int> _decodeBlock(List<int> frame, int offset, int l) {
    const int b = 8, s = 4;
    // Deinterleave: block[8*i+j] = str[L*j+i]
    final block = List<int>.filled(b * l, 0);
    for (int j = 0; j < b; j++) {
      for (int i = 0; i < l; i++) {
        block[b * i + j] = frame[offset + l * j + i] & 1;
      }
    }
    final sym = List<int>.filled(s * l, 0);
    for (int i = 0; i < l; i++) {
      _correct(block, b * i);
      for (int j = 0; j < s; j++) {
        sym[s * i + j] = block[b * i + j];
      }
    }
    return sym;
  }

  // Single-bit Hamming correction on codeword at [off..off+8).
  void _correct(List<int> code, int off) {
    final syndrom = List<int>.filled(4, 0);
    for (int i = 0; i < 4; i++) {
      int v = 0;
      for (int j = 0; j < 8; j++) {
        v ^= _h[i][j] & code[off + j];
      }
      syndrom[i] = v;
    }
    int synval = 0;
    for (int j = 0; j < 4; j++) {
      synval |= syndrom[j] << (3 - j);
    }
    if (synval != 0) {
      for (int j = 0; j < 8; j++) {
        if (synval == _he[j]) {
          code[off + j] ^= 1;
          break;
        }
      }
    }
  }

  static int _bits2val(List<int> bits, int start, int len) {
    int v = 0;
    for (int j = 0; j < len; j++) {
      v = (v << 1) | (bits[start + j] & 1);
    }
    return v;
  }

  static int _toShort(int v) => v >= 0x8000 ? v - 0x10000 : v;

  // DFM-09 (STM32) float24 unpack.
  static double _fl24(int d) {
    final p = (d >> 20) & 0xF;
    final val = d & 0xFFFFF;
    return val / (1 << p);
  }

  void _confOut(List<int> conf) {
    final confId = _bits2val(conf, 0, 4);

    if (confId > 4 && _bits2val(conf, 8, 4 * 5) == 0) {
      _nulCh = _bits2val(conf, 0, 8);
    }

    if (confId > 5 && confId > _maxCh) {
      if (_bits2val(conf, 4, 4) == 0xC) {
        _maxCh = confId;
      }
    }

    if (confId > 5 && (confId == (_nulCh >> 4) + 1 || confId == _maxCh)) {
      final sn2Ch = _bits2val(conf, 0, 8);
      final snCh = (sn2Ch >> 4) & 0xF;

      if ((_nulCh & 0x58) == 0x58) {
        // DFM-06 style serial.
        final sn6 = _bits2val(conf, 4, 4 * 6);
        if (sn6 == _sn6 && sn6 != 0) {
          _sondeTyp = 0x100 | snCh;
          _ptuOut = 6;
          _sondeId = 'ID${(snCh & 0xF).toRadixString(16)}:'
              '${_sn6.toRadixString(16).toUpperCase()}';
        } else {
          _sondeTyp = 0;
          _resetCfgchk();
        }
        _sn6 = sn6;
      } else if ((sn2Ch & 0xF) == 0xC || (sn2Ch & 0xF) == 0x0) {
        final val = _bits2val(conf, 8, 4 * 5);
        final hl = val & 0xF;
        if (hl < 2) {
          if (_snCh != snCh) {
            _chXbit = 0;
            _chX[0] = 0;
            _chX[1] = 0;
            _resetCfgchk();
          }
          _snCh = snCh;
          _chX[hl] = (val >> 4) & 0xFFFF;
          _chXbit |= 1 << hl;
          if (_chXbit == 3) {
            final sn = (_chX[0] << 16) | _chX[1];
            if (sn == _snX || _snX == 0) {
              _sondeTyp = 0x100 | snCh;
              _sn = sn;
              _ptuOut = 0;
              if (snCh == 0xA) _ptuOut = snCh; // DFM-09 (T+)
              if (snCh == 0xB) _ptuOut = snCh; // DFM-17
              if (snCh == 0xC) _ptuOut = snCh; // DFM-09P / DFM-17TU
              if (snCh == 0xD) _ptuOut = snCh; // DFM-17P
              if (_sn6 == 0 || (_sondeTyp & 0xF) >= 0xA) {
                _sondeId = 'ID${(_sondeTyp & 0xF).toRadixString(16)}:$_sn';
              }
            } else {
              _sondeTyp = 0;
              _resetCfgchk();
            }
            _snX = sn;
            _chXbit = 0;
          }
        }
      }
    }

    if (confId >= 0 && confId <= 8) {
      _cfgchk24[confId] = 1;
      final val = _bits2val(conf, 4, 4 * 6);
      _meas24[confId] = _fl24(val);
      _cfgchk = 0;
      if (_ptuOut >= 0x5) {
        _cfgchk = _cfgchk24[0] *
            _cfgchk24[1] *
            _cfgchk24[2] *
            _cfgchk24[3] *
            _cfgchk24[4] *
            _cfgchk24[5];
      }
      if (_ptuOut >= 0x7) _cfgchk *= _cfgchk24[6] * _cfgchk24[7];
      if (_ptuOut >= 0x8) _cfgchk *= _cfgchk24[8];
    }

    _sensorTyp = 'T';
    _rf = 220e3;

    _updateType();
  }

  void _resetCfgchk() {
    for (int j = 0; j < 9; j++) {
      _cfgchk24[j] = 0;
    }
    _cfgchk = 0;
    _ptuOut = 0;
  }

  void _updateType() {
    switch (_sondeTyp & 0xF) {
      case 0x6:
        _dfmType = 'DFM06';
        break;
      case 0x7:
      case 0x8:
        _dfmType = _sn6 != 0 ? 'DFM06P' : 'PS15';
        break;
      case 0xA:
        _dfmType = 'DFM09';
        break;
      case 0xB:
        _dfmType = 'DFM17';
        break;
      case 0xC:
        _dfmType = _sensorTyp == 'P' ? 'DFM09P' : 'DFM17';
        break;
      case 0xD:
        _dfmType = 'DFM17P';
        break;
      default:
        _dfmType = '';
        break;
    }
  }

  // NTC thermistor temperature approximation (get_Temp in the reference).
  double? _getTemp() {
    if (_cfgchk == 0 || _ptuOut == 0) return null;
    double f = _meas24[0], f1 = _meas24[3], f2 = _meas24[4];
    if (_sensorTyp == 'P') {
      f = _meas24[1];
      f1 = _meas24[5];
      f2 = _meas24[6];
    }
    const b0 = 3260.0;
    const t0 = 25 + 273.15;
    const r0 = 5.0e3;
    final g = f2 / _rf;
    double r = (f - f1) / g;
    if (f * f1 * f2 == 0) r = 0;
    if (r <= 0) return null;
    final t = 1 / (1 / t0 + 1 / b0 * math.log(r / r0));
    final c = t - 273.15;
    if (c < -270.0) return null;
    return c;
  }

  DfmFrame? _datOut(List<int> dat) {
    final frId = _bits2val(dat, 48, 4);
    if (frId < 0 || frId > 8) return null;

    _pckTs[frId] = _frameCounter.toDouble();

    if (frId == 0) {
      final mode = _bits2val(dat, 16, 8);
      _posmode = (mode > 1 && mode < 5) ? mode : -1;
      _frnr = _bits2val(dat, 24, 8);
    }

    if (_posmode <= 2) {
      if (frId == 1) {
        final prn = _bits2val(dat, 0, 32);
        _nPRN = 0;
        for (int j = 0; j < 32; j++) {
          if ((prn >> j) & 1 != 0) _nPRN++;
        }
        _sek = _bits2val(dat, 32, 16) / 1000.0;
      }
      if (frId == 2) {
        _lat = _bits2val(dat, 0, 32) / 1e7;
        _horiV = _toShort(_bits2val(dat, 32, 16)) / 1e2;
      }
      if (frId == 3) {
        _lon = _bits2val(dat, 0, 32) / 1e7;
        _dir = (_bits2val(dat, 32, 16) & 0xFFFF) / 1e2;
      }
      if (frId == 4) {
        _alt = _bits2val(dat, 0, 32) / 1e2;
        _vertV = _toShort(_bits2val(dat, 32, 16)) / 1e2;
      }
    } else if (_posmode == 3 || _posmode == 4) {
      if (frId == 0) {
        _sek = _bits2val(dat, 0, 16) / 1000.0;
        _horiV = _toShort(_bits2val(dat, 32, 16)) / 1e2;
      }
      if (frId == 1) {
        _lat = _bits2val(dat, 0, 32) / 1e7;
        _dir = (_bits2val(dat, 32, 16) & 0xFFFF) / 1e2;
      }
      if (frId == 2) {
        _lon = _bits2val(dat, 0, 32) / 1e7;
        _vertV = _toShort(_bits2val(dat, 32, 16)) / 1e2;
      }
      if (frId == 3) {
        _alt = _bits2val(dat, 0, 32) / 1e2;
      }
    }

    if (frId == 8) {
      _jahr = _bits2val(dat, 0, 12);
      _monat = _bits2val(dat, 12, 4);
      _tag = _bits2val(dat, 16, 5);
      _std = _bits2val(dat, 21, 5);
      _min = _bits2val(dat, 26, 6);
      _nSV = _bits2val(dat, 32, 8);
      return _tryEmit();
    }
    return null;
  }

  // Emit a fix when packets 0,1,2,3,4,8 are all fresh (within 6 frames of pck8),
  // mirroring the reference `contgps` trigger in print_gpx().
  DfmFrame? _tryEmit() {
    final t8 = _pckTs[8];
    for (final i in _idFr) {
      if (t8 - _pckTs[i] >= 6.0) return null;
    }
    if (_lat == 0 && _lon == 0) return null;
    if (_jahr < 2000 || _monat < 1 || _monat > 12 || _tag < 1 || _tag > 31) {
      return null;
    }

    int sats = _nSV;
    if (sats == 0) sats = _nPRN;

    final secWhole = _sek.floor();
    final micros = ((_sek - secWhole) * 1e6).round();
    final DateTime dt;
    try {
      dt = DateTime.utc(
        _jahr,
        _monat,
        _tag,
        _std,
        _min,
        secWhole.clamp(0, 59),
        0,
        (micros ~/ 1000).clamp(0, 999),
      );
    } catch (_) {
      return null;
    }

    return DfmFrame(
      frameNumber: _frnr,
      sondeId: _sondeId,
      dfmType: _dfmType,
      latitude: _lat,
      longitude: _lon,
      altitude: _alt,
      horizontalSpeed: _horiV,
      verticalSpeed: _vertV,
      heading: _dir,
      satellites: sats,
      dateTimeUtc: dt,
      temperatureC: _getTemp(),
    );
  }
}
