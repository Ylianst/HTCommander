/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// COSPAS-SARSAT 406 MHz first-generation (FGB / v1g) beacon frame decoder.
///
/// This decodes the 112-bit (short) or 144-bit (long) message that a v1g
/// beacon transmits (biphase-L PSK, 400 bps). It validates and error-corrects
/// the two BCH ("CRC") fields and parses the standard message fields.
///
/// Ported from the reference decoder `dec406_v1g.c`
/// (github.com/moricef/Decode_sarsat_406_v1g_v2g, F4EHY 2020) so the field
/// layout and BCH polynomials match bit-for-bit.
library;

/// First-generation beacon protocol classification.
enum Sarsat1gProtocol {
  unknown,
  standardLocation,
  nationalLocation,
  userProtocol,
  test,
  emergencyElt, // ELT(DT)
  rlsLocation,
  shipSecurity,
}

/// Decoded first-generation beacon message.
class Sarsat1gFrame {
  /// Frame length in bits: 112 (short) or 144 (long).
  final int length;

  /// True if BCH-1 validated (after any correction).
  final bool crc1Ok;

  /// True if BCH-2 validated (long frames only; always true for short).
  final bool crc2Ok;

  /// Number of bit errors BCH-1 corrected (0..3), or -1 if uncorrectable.
  final int corrections1;

  /// Number of bit errors BCH-2 corrected, or -1 if uncorrectable.
  final int corrections2;

  final int countryCode;
  final int protocolCode; // 4-bit code (bits 37-40)
  final Sarsat1gProtocol protocol;

  /// 15-hexadecimal beacon identifier (T.001), with default position bits.
  final String hexId;

  /// Human-readable identification (MMSI, serial, aircraft address, etc.).
  final String identification;

  /// Decoded position in decimal degrees, or null if none/unavailable.
  final double? latitude;
  final double? longitude;

  /// True if this is a self-test transmission.
  final bool isTest;

  /// The corrected frame bits (length entries, each 0/1).
  final List<int> bits;

  const Sarsat1gFrame({
    required this.length,
    required this.crc1Ok,
    required this.crc2Ok,
    required this.corrections1,
    required this.corrections2,
    required this.countryCode,
    required this.protocolCode,
    required this.protocol,
    required this.hexId,
    required this.identification,
    required this.latitude,
    required this.longitude,
    required this.isTest,
    required this.bits,
  });

  bool get hasPosition => latitude != null && longitude != null;

  /// True only when both BCH fields validated (short frames need only BCH-1).
  bool get valid => crc1Ok && crc2Ok;

  String get protocolName {
    switch (protocol) {
      case Sarsat1gProtocol.standardLocation:
        return 'Standard Location';
      case Sarsat1gProtocol.nationalLocation:
        return 'National Location';
      case Sarsat1gProtocol.userProtocol:
        return 'User / User-Location';
      case Sarsat1gProtocol.test:
        return 'Test';
      case Sarsat1gProtocol.emergencyElt:
        return 'ELT(DT) Location';
      case Sarsat1gProtocol.rlsLocation:
        return 'RLS Location';
      case Sarsat1gProtocol.shipSecurity:
        return 'Ship Security';
      case Sarsat1gProtocol.unknown:
        return 'Unknown';
    }
  }

  @override
  String toString() {
    final b = StringBuffer()
      ..writeln('406 v1g ${length == 144 ? "LONG" : "SHORT"} '
          '(BCH1=${crc1Ok ? "OK" : "FAIL"}'
          '${length == 144 ? ", BCH2=${crc2Ok ? "OK" : "FAIL"}" : ""})')
      ..writeln('Country: $countryCode')
      ..writeln('Protocol: $protocolCode ($protocolName)')
      ..writeln('Hex ID: $hexId')
      ..writeln('Identification: $identification');
    if (hasPosition) {
      b.writeln('Position: ${latitude!.toStringAsFixed(5)}, '
          '${longitude!.toStringAsFixed(5)}');
    } else {
      b.writeln('Position: not available');
    }
    if (isTest) b.writeln('Self-test: yes');
    return b.toString();
  }
}

/// Decoder for a single v1g frame given its raw bits.
class Sarsat1gDecoder {
  // BCH-1 generator (bits 25..106, 21 parity bits). Same coefficients as the
  // reference test_crc1(): x^21 + ... + 1.
  static const List<int> _g1 = [
    1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1 //
  ];
  // BCH-2 generator (bits 107..144, 12 parity bits).
  static const List<int> _g2 = [1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1];

  static const String _fsyncNormal = '000101111';
  static const String _fsyncSelfTest = '011010000';

  /// Reads [len] bits starting at [start] (MSB first) as an integer.
  static int _getBits(List<int> s, int start, int len) {
    int v = 0;
    for (int i = 0; i < len; i++) {
      v = (v << 1) | (s[start + i] & 1);
    }
    return v;
  }

  /// BCH-1 remainder (0 = valid). Direct port of reference test_crc1().
  static int _crc1(List<int> s) => _crcRemainder(s, _g1, 24, 85, 22);

  /// BCH-2 remainder (0 = valid). Direct port of reference test_crc2().
  static int _crc2(List<int> s) => _crcRemainder(s, _g2, 106, 132, 13);

  // Shared long-division used by both CRC fields; mirrors the reference loop.
  static int _crcRemainder(
      List<int> s, List<int> g, int startBit, int endBit, int glen) {
    final div = List<int>.filled(glen, 0);
    int i = startBit;
    for (int j = 0; j < glen; j++) {
      div[j] = s[i + j] & 1;
    }
    while (i < endBit) {
      for (int j = 0; j < glen; j++) {
        div[j] ^= g[j];
      }
      while (div[0] == 0 && i < endBit) {
        for (int j = 0; j < glen - 1; j++) {
          div[j] = div[j + 1];
        }
        div[glen - 1] = (i < endBit - 1) ? (s[i + glen] & 1) : 0;
        i++;
      }
    }
    int sum = 0;
    for (final d in div) {
      sum += d;
    }
    return sum;
  }

  /// Corrects up to 3 bit errors in [s] over the BCH-1 protected span
  /// (indices 24..105) using [crc]. Returns the number of corrections, or -1
  /// if uncorrectable. Modifies [s] in place on success.
  static int _correct(List<int> s, int Function(List<int>) crc, int lo, int hi) {
    if (crc(s) == 0) return 0;
    for (int i = lo; i <= hi; i++) {
      s[i] ^= 1;
      if (crc(s) == 0) return 1;
      s[i] ^= 1;
    }
    for (int i = lo; i <= hi; i++) {
      s[i] ^= 1;
      for (int j = i + 1; j <= hi; j++) {
        s[j] ^= 1;
        if (crc(s) == 0) return 2;
        s[j] ^= 1;
      }
      s[i] ^= 1;
    }
    for (int i = lo; i <= hi; i++) {
      s[i] ^= 1;
      for (int j = i + 1; j <= hi; j++) {
        s[j] ^= 1;
        for (int k = j + 1; k <= hi; k++) {
          s[k] ^= 1;
          if (crc(s) == 0) return 3;
          s[k] ^= 1;
        }
        s[j] ^= 1;
      }
      s[i] ^= 1;
    }
    return -1;
  }

  /// Returns true if [bits] begin with a valid 15-bit sync + frame sync.
  static bool hasSync(List<int> bits) {
    if (bits.length < 24) return false;
    for (int i = 0; i < 15; i++) {
      if (bits[i] != 1) return false;
    }
    final fs = bits.sublist(15, 24).join();
    return fs == _fsyncNormal || fs == _fsyncSelfTest;
  }

  /// Decodes a frame from its raw [bits] (length 112 or 144). Applies BCH
  /// error correction. Returns null if [bits] has the wrong length.
  static Sarsat1gFrame? decode(List<int> bits) {
    if (bits.length != 112 && bits.length != 144) return null;
    final s = List<int>.from(bits);
    // Pad short frames to 144 so shared index math is uniform.
    final work = s.length == 144 ? s : (List<int>.from(s)..addAll(List<int>.filled(32, 0)));
    final len = s.length;

    final c1 = _correct(work, _crc1, 24, 105);
    final crc1Ok = c1 >= 0;
    int c2 = 0;
    bool crc2Ok = true;
    if (len == 144) {
      // BCH-2 does not apply to orbitography user frames.
      final userCode = _getBits(work, 36, 3);
      final isOrbitography = work[25] == 1 && userCode == 0;
      if (!isOrbitography) {
        c2 = _correct(work, _crc2, 106, 131);
        crc2Ok = c2 >= 0;
      }
    }

    final country = _getBits(work, 26, 10);
    final protocolCode = _getBits(work, 36, 4);
    final isTest = work.sublist(15, 24).join() == _fsyncSelfTest;
    final protocol = _classify(work, len, protocolCode);
    final ident = _identify(work, protocol, protocolCode);
    final pos = _position(work, len, protocol);
    final hexId = _hex15(work, protocol);

    return Sarsat1gFrame(
      length: len,
      crc1Ok: crc1Ok,
      crc2Ok: crc2Ok,
      corrections1: c1,
      corrections2: c2,
      countryCode: country,
      protocolCode: protocolCode,
      protocol: protocol,
      hexId: hexId,
      identification: ident,
      latitude: pos?[0],
      longitude: pos?[1],
      isTest: isTest,
      bits: work.sublist(0, len),
    );
  }

  static Sarsat1gProtocol _classify(List<int> s, int len, int code) {
    final protocolFlag = s[25];
    if (len == 112) {
      if (protocolFlag != 1) return Sarsat1gProtocol.unknown;
      switch (code & 0x7) {
        case 7:
          return Sarsat1gProtocol.test;
        default:
          return Sarsat1gProtocol.userProtocol;
      }
    }
    if (protocolFlag == 0) {
      switch (code) {
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
          return Sarsat1gProtocol.standardLocation;
        case 8:
        case 10:
        case 11:
          return Sarsat1gProtocol.nationalLocation;
        case 9:
          return Sarsat1gProtocol.emergencyElt;
        case 12:
          return Sarsat1gProtocol.shipSecurity;
        case 13:
          return Sarsat1gProtocol.rlsLocation;
        case 14:
        case 15:
          return Sarsat1gProtocol.test;
        default:
          return Sarsat1gProtocol.unknown;
      }
    }
    return Sarsat1gProtocol.userProtocol;
  }

  static String _identify(List<int> s, Sarsat1gProtocol proto, int code) {
    if (proto == Sarsat1gProtocol.standardLocation ||
        proto == Sarsat1gProtocol.shipSecurity) {
      final idData = _getBits(s, 40, 24); // bits 41-64
      switch (code) {
        case 2: // MMSI + beacon number
        case 12:
          final mmsi = (idData >> 4) & 0xFFFFF;
          return 'MMSI last6: $mmsi';
        case 3: // 24-bit aircraft address
          return 'Aircraft ${((idData) & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
        case 4:
        case 6:
        case 7:
          final tac = (idData >> 14) & 0x3FF;
          final serial = idData & 0x3FFF;
          return 'TAC: $tac, Serial: $serial';
        case 5:
          final op = (idData >> 9) & 0x7FFF;
          final serial = idData & 0x1FF;
          return 'Operator: ${op.toRadixString(16).toUpperCase()}, Serial: $serial';
        default:
          return 'ID: ${idData.toRadixString(16).toUpperCase()}';
      }
    }
    return '';
  }

  // COSPAS 15 Hex ID: bits 26-85 with default position values per T.001.
  static String _hex15(List<int> s, Sarsat1gProtocol proto) {
    int idHi = 0, idLo = 0;
    for (int i = 25; i <= 84; i++) {
      // 60-bit value split as 28-bit hi + 32-bit lo.
      final bit = s[i] & 1;
      idHi = (idHi << 1) | (idLo >> 31);
      idLo = ((idLo << 1) | bit) & 0xFFFFFFFF;
    }
    idHi &= 0x0FFFFFFF; // 28 bits
    switch (proto) {
      case Sarsat1gProtocol.standardLocation:
      case Sarsat1gProtocol.shipSecurity:
        idLo = (idLo & 0xFFE00000) | 0x000FFBFF;
        break;
      case Sarsat1gProtocol.nationalLocation:
        idLo = (idLo & 0xF8000000) | 0x03F81FE0;
        break;
      case Sarsat1gProtocol.rlsLocation:
      case Sarsat1gProtocol.emergencyElt:
        idLo = (idLo & 0xFFF80000) | 0x0003FDFF;
        break;
      default:
        break;
    }
    final hi = idHi.toRadixString(16).toUpperCase().padLeft(7, '0');
    final lo = idLo.toRadixString(16).toUpperCase().padLeft(8, '0');
    return hi + lo;
  }

  // Returns [lat, lon] in degrees, or null. Standard Location + User-Location.
  static List<double>? _position(List<int> s, int len, Sarsat1gProtocol proto) {
    if (proto == Sarsat1gProtocol.standardLocation ||
        proto == Sarsat1gProtocol.shipSecurity) {
      final nsSouth = s[64] == 1; // bit 65
      final latQ = _getBits(s, 65, 9); // bits 66-74, 1/4 deg
      double lat = latQ * 0.25;
      if (nsSouth) lat = -lat;
      final ewWest = s[74] == 1; // bit 75
      final lonQ = _getBits(s, 75, 10); // bits 76-85, 1/4 deg
      double lon = lonQ * 0.25;
      if (ewWest) lon = -lon;
      if (len == 144) {
        // PDF-2 fine offsets (Δlat/Δlon), present when fixed bits == 1101.
        if (_getBits(s, 106, 4) == 0xD) {
          final latSign = s[112] == 1 ? 1 : -1;
          final latMin = _getBits(s, 113, 5);
          final latSec = _getBits(s, 118, 4) * 4;
          final lonSign = s[122] == 1 ? 1 : -1;
          final lonMin = _getBits(s, 123, 5);
          final lonSec = _getBits(s, 128, 4) * 4;
          lat += latSign * (latMin / 60.0 + latSec / 3600.0);
          lon += lonSign * (lonMin / 60.0 + lonSec / 3600.0);
        }
      }
      if (!_validCoord(lat, lon)) return null;
      return [lat, lon];
    }
    if (proto == Sarsat1gProtocol.userProtocol && len == 144) {
      final userCode = _getBits(s, 36, 3);
      if (userCode == 0) return null; // orbitography: no position
      final latSign = s[107] == 0 ? 1 : -1; // bit 108
      final latDeg = _getBits(s, 108, 7); // bits 109-115
      final latMin4 = _getBits(s, 115, 4); // bits 116-119
      final lonSign = s[119] == 0 ? 1 : -1; // bit 120
      final lonDeg = _getBits(s, 120, 8); // bits 121-128
      final lonMin4 = _getBits(s, 128, 4); // bits 129-132
      final lat = latSign * (latDeg + (latMin4 * 4.0) / 60.0);
      final lon = lonSign * (lonDeg + (lonMin4 * 4.0) / 60.0);
      if (!_validCoord(lat, lon)) return null;
      return [lat, lon];
    }
    return null;
  }

  static bool _validCoord(double lat, double lon) =>
      lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;

  /// Renders frame [bits] (each 0/1) as an uppercase hex string.
  static String bitsToHex(List<int> bits) {
    final sb = StringBuffer();
    for (int i = 0; i < bits.length; i += 4) {
      int nib = 0;
      for (int j = 0; j < 4; j++) {
        nib <<= 1;
        if (i + j < bits.length) nib |= bits[i + j] & 1;
      }
      sb.write(nib.toRadixString(16).toUpperCase());
    }
    return sb.toString();
  }
}

/// Structured, JSON-serializable summary of a decoded beacon. Stored in the
/// Comms record so the UI can show a full field breakdown and the raw frame,
/// and so it survives persistence and cross-isolate/broker transport.
class Sarsat1gDetails {
  final int lengthBits; // 112 or 144
  final bool crc1Ok;
  final bool crc2Ok;
  final int countryCode;
  final String? countryName;
  final int protocolCode;
  final String protocolName;
  final String hexId;
  final String identification;
  final double? latitude;
  final double? longitude;
  final bool isTest;

  /// The full decoded frame (all bits, including sync) as hex.
  final String rawHex;

  /// Number of beacons with this ID coalesced into one bubble (>= 1).
  final int count;

  /// Time the most recent beacon in the bubble was received.
  final DateTime? lastReceivedTime;

  const Sarsat1gDetails({
    required this.lengthBits,
    required this.crc1Ok,
    required this.crc2Ok,
    required this.countryCode,
    required this.countryName,
    required this.protocolCode,
    required this.protocolName,
    required this.hexId,
    required this.identification,
    required this.latitude,
    required this.longitude,
    required this.isTest,
    required this.rawHex,
    this.count = 1,
    this.lastReceivedTime,
  });

  /// Builds a record from a decoded [frame]; [countryName] is looked up by the
  /// caller (the decoder itself has no country table). [count] /
  /// [lastReceivedTime] carry beacon-coalescing metadata; [latitude] /
  /// [longitude] override the frame's position (to retain a prior fix).
  factory Sarsat1gDetails.fromFrame(
    Sarsat1gFrame frame, {
    String? countryName,
    int count = 1,
    DateTime? lastReceivedTime,
    double? latitude,
    double? longitude,
  }) {
    return Sarsat1gDetails(
      lengthBits: frame.length,
      crc1Ok: frame.crc1Ok,
      crc2Ok: frame.crc2Ok,
      countryCode: frame.countryCode,
      countryName: countryName,
      protocolCode: frame.protocolCode,
      protocolName: frame.protocolName,
      hexId: frame.hexId,
      identification: frame.identification,
      latitude: latitude ?? frame.latitude,
      longitude: longitude ?? frame.longitude,
      isTest: frame.isTest,
      rawHex: Sarsat1gDecoder.bitsToHex(frame.bits),
      count: count,
      lastReceivedTime: lastReceivedTime,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'lengthBits': lengthBits,
    'crc1Ok': crc1Ok,
    'crc2Ok': crc2Ok,
    'countryCode': countryCode,
    'countryName': countryName,
    'protocolCode': protocolCode,
    'protocolName': protocolName,
    'hexId': hexId,
    'identification': identification,
    'latitude': latitude,
    'longitude': longitude,
    'isTest': isTest,
    'rawHex': rawHex,
    'count': count,
    'lastReceivedTime': lastReceivedTime?.millisecondsSinceEpoch,
  };

  factory Sarsat1gDetails.fromJson(Map<dynamic, dynamic> json) {
    double? toD(Object? v) => v is num ? v.toDouble() : null;
    final lastMs = json['lastReceivedTime'];
    return Sarsat1gDetails(
      lengthBits: json['lengthBits'] as int? ?? 0,
      crc1Ok: json['crc1Ok'] as bool? ?? false,
      crc2Ok: json['crc2Ok'] as bool? ?? false,
      countryCode: json['countryCode'] as int? ?? 0,
      countryName: json['countryName'] as String?,
      protocolCode: json['protocolCode'] as int? ?? 0,
      protocolName: json['protocolName'] as String? ?? '',
      hexId: json['hexId'] as String? ?? '',
      identification: json['identification'] as String? ?? '',
      latitude: toD(json['latitude']),
      longitude: toD(json['longitude']),
      isTest: json['isTest'] as bool? ?? false,
      rawHex: json['rawHex'] as String? ?? '',
      count: json['count'] as int? ?? 1,
      lastReceivedTime: lastMs is int
          ? DateTime.fromMillisecondsSinceEpoch(lastMs)
          : null,
    );
  }
}

