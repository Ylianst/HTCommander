/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../radio/utils.dart';

// Useful Github stuff for WinLink
// https://github.com/la5nta/wl2k-go
// https://raw.githubusercontent.com/ham-radio-software/lzhuf/refs/heads/main/lzhuf.c

/// Winlink login security helpers (challenge generation and the secure login
/// response used during B2F authentication).
class WinlinkSecurity {
  WinlinkSecurity._();

  static final Uint8List _winlinkSecureSalt = Uint8List.fromList(const [
    77,
    197,
    101,
    206,
    190,
    249,
    93,
    200,
    51,
    243,
    93,
    237,
    71,
    94,
    239,
    138,
    68,
    108,
    70,
    185,
    225,
    137,
    217,
    16,
    51,
    122,
    193,
    48,
    194,
    195,
    198,
    175,
    172,
    169,
    70,
    84,
    61,
    62,
    104,
    186,
    114,
    52,
    61,
    168,
    66,
    129,
    192,
    208,
    187,
    249,
    232,
    193,
    41,
    113,
    41,
    45,
    240,
    16,
    29,
    228,
    208,
    228,
    61,
    20,
  ]);

  static bool test() {
    if (secureLoginResponse('23753528', 'FOOBAR') != '72768415') return false;
    if (secureLoginResponse('23753528', 'FooBar') != '95074758') return false;
    return true;
  }

  /// Computes the Winlink secure login response: the low 31 bits of
  /// `MD5(challenge + password + salt)` rendered as an 8-digit decimal string.
  static String secureLoginResponse(String challenge, String password) {
    final a1 = _asciiBytes(challenge);
    final a2 = _asciiBytes(password);
    final a3 = _winlinkSecureSalt;

    final rv = Uint8List(a1.length + a2.length + a3.length);
    rv.setRange(0, a1.length, a1);
    rv.setRange(a1.length, a1.length + a2.length, a2);
    rv.setRange(a1.length + a2.length, rv.length, a3);

    final hashBytes = md5.convert(rv).bytes;
    int pr = hashBytes[3] & 0x3f;
    for (int i = 2; i >= 0; i--) {
      pr = (pr << 8) | hashBytes[i];
    }
    final str = pr.toString().padLeft(8, '0');
    return str.substring(str.length - 8);
  }

  /// Generates an 8-digit numeric challenge string.
  static String generateChallenge() {
    final rng = Random.secure();
    var value = BigInt.zero;
    for (int i = 0; i < 8; i++) {
      value |= BigInt.from(rng.nextInt(256)) << (8 * i);
    }
    final rndStr = value.toString().padLeft(9, '0');
    return rndStr.substring(rndStr.length - 8);
  }

  static Uint8List _asciiBytes(String s) {
    final out = Uint8List(s.length);
    for (int i = 0; i < s.length; i++) {
      out[i] = s.codeUnitAt(i) & 0xFF;
    }
    return out;
  }
}

/// Result of an lzhuf decode operation.
class WinlinkDecodeResult {
  WinlinkDecodeResult(this.data, this.count);

  /// The decoded bytes (length equals the number of bytes produced).
  final Uint8List data;

  /// The number of bytes decoded. Zero indicates a CRC mismatch.
  final int count;
}

/// LZHUF compression used by the Winlink B2F protocol.
///
/// Port of the C# `WinlinkCompression` class. The codec state is encapsulated
/// in a fresh instance for each operation, so the calls are reentrant without
/// any locking.
class WinlinkCompression {
  WinlinkCompression._();

  /// Compresses [input]. When [prependCRC] is true the 2-byte CRC is written at
  /// the start of the returned buffer.
  static Uint8List encode(Uint8List input, {bool prependCRC = false}) {
    return _LzhufCodec().encode(input, prependCRC);
  }

  /// Decompresses [input]. [expectedSize] is the expected uncompressed length
  /// (used to size the work buffer). When [checkCRC] is true the leading 2-byte
  /// CRC is validated; on mismatch the returned [WinlinkDecodeResult.count] is 0.
  static WinlinkDecodeResult decode(
    Uint8List input, {
    required bool checkCRC,
    required int expectedSize,
  }) {
    return _LzhufCodec().decode(input, checkCRC, expectedSize);
  }

  static bool test() {
    const xm1 =
        '8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122';
    const xm2 =
        'F05B9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E160EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006213D0FF86E9F662B3C86BB61AF60D350340';
    final m1 = RadioUtils.hexStringToByteArray(xm1)!;
    final m2 = RadioUtils.hexStringToByteArray(xm2)!;

    final d1 = decode(m1, checkCRC: true, expectedSize: 199);
    final re1 = encode(d1.data, prependCRC: true);
    final rm1 = RadioUtils.bytesToHex(re1);

    final d2 = decode(m2, checkCRC: true, expectedSize: 410);
    final re2 = encode(d2.data, prependCRC: true);
    final rm2 = RadioUtils.bytesToHex(re2);

    if (xm1.toUpperCase() != rm1.toUpperCase()) return false;
    if (xm2.toUpperCase() != rm2.toUpperCase()) return false;
    return true;
  }
}

/// Internal lzhuf codec holding all per-operation state.
class _LzhufCodec {
  static const int n = 2048;
  static const int f = 60;
  static const int threshold = 2;
  static const int nodeNil = n;
  static const int nChar = (256 - threshold) + f; // 314
  static const int t = (nChar * 2) - 1; // 627
  static const int r = t - 1; // 626
  static const int maxFreq = 0x8000;
  static const int tbSize = n + f - 2; // 2106

  final Uint8List textBuf = Uint8List(tbSize + 1);
  List<int> lSon = List<int>.filled(n + 1, 0);
  List<int> dad = List<int>.filled(n + 1, 0);
  List<int> rSon = List<int>.filled(n + 256 + 1, 0);
  List<int> freq = List<int>.filled(t + 1, 0);
  List<int> son = List<int>.filled(t, 0);
  List<int> parent = List<int>.filled(t + nChar, 0);

  Uint8List? inBuf;
  Uint8List? outBuf;
  int inPtr = 0;
  int inEnd = 0;
  int outPtr = 0;
  int crc = 0;
  bool encDec = false; // true for encode, false for decode
  int getBuf = 0;
  int getLen = 0;
  int putBuf = 0;
  int putLen = 0;
  int textSize = 0;
  int codeSize = 0;
  int matchPosition = 0;
  int matchLength = 0;

  static const List<int> _pLen = [
    0x3, 0x4, 0x4, 0x4, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, //
    0x8, 0x8, 0x8, 0x8,
  ];

  static const List<int> _pCode = [
    0x0, 0x20, 0x30, 0x40, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0x88, //
    0x90, 0x94, 0x98, 0x9C, 0xA0, 0xA4, 0xA8, 0xAC, 0xB0, 0xB4, 0xB8, 0xBC, //
    0xC0, 0xC2, 0xC4, 0xC6, 0xC8, 0xCA, 0xCC, 0xCE, 0xD0, 0xD2, 0xD4, 0xD6, //
    0xD8, 0xDA, 0xDC, 0xDE, 0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA, 0xEC, 0xEE, //
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, //
    0xFC, 0xFD, 0xFE, 0xFF,
  ];

  static const List<int> _dCode = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, //
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, //
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, //
    0x02, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, //
    0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04, //
    0x04, 0x04, 0x04, 0x04, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, //
    0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x07, //
    0x07, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, //
    0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x0A, 0x0A, 0x0A, 0x0A, //
    0x0A, 0x0A, 0x0A, 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, //
    0x0C, 0x0C, 0x0C, 0x0C, 0x0D, 0x0D, 0x0D, 0x0D, 0x0E, 0x0E, 0x0E, 0x0E, //
    0x0F, 0x0F, 0x0F, 0x0F, 0x10, 0x10, 0x10, 0x10, 0x11, 0x11, 0x11, 0x11, //
    0x12, 0x12, 0x12, 0x12, 0x13, 0x13, 0x13, 0x13, 0x14, 0x14, 0x14, 0x14, //
    0x15, 0x15, 0x15, 0x15, 0x16, 0x16, 0x16, 0x16, 0x17, 0x17, 0x17, 0x17, //
    0x18, 0x18, 0x19, 0x19, 0x1A, 0x1A, 0x1B, 0x1B, 0x1C, 0x1C, 0x1D, 0x1D, //
    0x1E, 0x1E, 0x1F, 0x1F, 0x20, 0x20, 0x21, 0x21, 0x22, 0x22, 0x23, 0x23, //
    0x24, 0x24, 0x25, 0x25, 0x26, 0x26, 0x27, 0x27, 0x28, 0x28, 0x29, 0x29, //
    0x2A, 0x2A, 0x2B, 0x2B, 0x2C, 0x2C, 0x2D, 0x2D, 0x2E, 0x2E, 0x2F, 0x2F, //
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, //
    0x3C, 0x3D, 0x3E, 0x3F,
  ];

  static const List<int> _dLen = [
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, //
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, //
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x4, 0x4, 0x4, //
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, //
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, //
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, //
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x5, 0x5, 0x5, 0x5, //
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, //
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, //
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, //
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, //
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, //
    0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, //
    0x8, 0x8, 0x8, 0x8,
  ];

  static const int crcMask = 0xFFFF;
  static const List<int> _crcTable = [
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50A5, 0x60C6, 0x70E7, //
    0x8108, 0x9129, 0xA14A, 0xB16B, 0xC18C, 0xD1AD, 0xE1CE, 0xF1EF, //
    0x1231, 0x0210, 0x3273, 0x2252, 0x52B5, 0x4294, 0x72F7, 0x62D6, //
    0x9339, 0x8318, 0xB37B, 0xA35A, 0xD3BD, 0xC39C, 0xF3FF, 0xE3DE, //
    0x2462, 0x3443, 0x0420, 0x1401, 0x64E6, 0x74C7, 0x44A4, 0x5485, //
    0xA56A, 0xB54B, 0x8528, 0x9509, 0xE5EE, 0xF5CF, 0xC5AC, 0xD58D, //
    0x3653, 0x2672, 0x1611, 0x0630, 0x76D7, 0x66F6, 0x5695, 0x46B4, //
    0xB75B, 0xA77A, 0x9719, 0x8738, 0xF7DF, 0xE7FE, 0xD79D, 0xC7BC, //
    0x48C4, 0x58E5, 0x6886, 0x78A7, 0x0840, 0x1861, 0x2802, 0x3823, //
    0xC9CC, 0xD9ED, 0xE98E, 0xF9AF, 0x8948, 0x9969, 0xA90A, 0xB92B, //
    0x5AF5, 0x4AD4, 0x7AB7, 0x6A96, 0x1A71, 0x0A50, 0x3A33, 0x2A12, //
    0xDBFD, 0xCBDC, 0xFBBF, 0xEB9E, 0x9B79, 0x8B58, 0xBB3B, 0xAB1A, //
    0x6CA6, 0x7C87, 0x4CE4, 0x5CC5, 0x2C22, 0x3C03, 0x0C60, 0x1C41, //
    0xEDAE, 0xFD8F, 0xCDEC, 0xDDCD, 0xAD2A, 0xBD0B, 0x8D68, 0x9D49, //
    0x7E97, 0x6EB6, 0x5ED5, 0x4EF4, 0x3E13, 0x2E32, 0x1E51, 0x0E70, //
    0xFF9F, 0xEFBE, 0xDFDD, 0xCFFC, 0xBF1B, 0xAF3A, 0x9F59, 0x8F78, //
    0x9188, 0x81A9, 0xB1CA, 0xA1EB, 0xD10C, 0xC12D, 0xF14E, 0xE16F, //
    0x1080, 0x00A1, 0x30C2, 0x20E3, 0x5004, 0x4025, 0x7046, 0x6067, //
    0x83B9, 0x9398, 0xA3FB, 0xB3DA, 0xC33D, 0xD31C, 0xE37F, 0xF35E, //
    0x02B1, 0x1290, 0x22F3, 0x32D2, 0x4235, 0x5214, 0x6277, 0x7256, //
    0xB5EA, 0xA5CB, 0x95A8, 0x8589, 0xF56E, 0xE54F, 0xD52C, 0xC50D, //
    0x34E2, 0x24C3, 0x14A0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405, //
    0xA7DB, 0xB7FA, 0x8799, 0x97B8, 0xE75F, 0xF77E, 0xC71D, 0xD73C, //
    0x26D3, 0x36F2, 0x0691, 0x16B0, 0x6657, 0x7676, 0x4615, 0x5634, //
    0xD94C, 0xC96D, 0xF90E, 0xE92F, 0x99C8, 0x89E9, 0xB98A, 0xA9AB, //
    0x5844, 0x4865, 0x7806, 0x6827, 0x18C0, 0x08E1, 0x3882, 0x28A3, //
    0xCB7D, 0xDB5C, 0xEB3F, 0xFB1E, 0x8BF9, 0x9BD8, 0xABBB, 0xBB9A, //
    0x4A75, 0x5A54, 0x6A37, 0x7A16, 0x0AF1, 0x1AD0, 0x2AB3, 0x3A92, //
    0xFD2E, 0xED0F, 0xDD6C, 0xCD4D, 0xBDAA, 0xAD8B, 0x9DE8, 0x8DC9, //
    0x7C26, 0x6C07, 0x5C64, 0x4C45, 0x3CA2, 0x2C83, 0x1CE0, 0x0CC1, //
    0xEF1F, 0xFF3E, 0xCF5D, 0xDF7C, 0xAF9B, 0xBFBA, 0x8FD9, 0x9FF8, //
    0x6E17, 0x7E36, 0x4E55, 0x5E74, 0x2E93, 0x3EB2, 0x0ED1, 0x1EF0, //
  ];

  Uint8List encode(Uint8List iBuf, bool prependCRC) {
    _init();
    encDec = true;

    inBuf = Uint8List(iBuf.length + 100);
    outBuf = Uint8List(iBuf.length * 2 + 10000);

    for (int i = 0; i < iBuf.length; i++) {
      inBuf![inEnd++] = iBuf[i];
    }

    _putc(inEnd & 0xFF);
    _putc((inEnd >> 8) & 0xFF);
    _putc((inEnd >> 16) & 0xFF);
    _putc((inEnd >> 24) & 0xFF);

    codeSize += 4;

    if (inEnd == 0) {
      inBuf = null;
      outBuf = null;
      return Uint8List(0);
    }

    textSize = 0;
    _startHuff();
    _initTree();
    int s = 0;
    int rr = n - f;
    for (int i = 0; i < rr; i++) {
      textBuf[i] = 0x20;
    }

    int len = 0;
    while ((len < f) && (inPtr < inEnd)) {
      textBuf[rr + len++] = _getc() & 0xFF;
    }
    textSize = len;
    for (int i = 1; i <= f; i++) {
      _insertNode(rr - i);
    }
    _insertNode(rr);
    do {
      if (matchLength > len) matchLength = len;
      if (matchLength <= threshold) {
        matchLength = 1;
        _encodeChar(textBuf[rr]);
      } else {
        _encodeChar((255 - threshold) + matchLength);
        _encodePosition(matchPosition);
      }
      final lastMatchLength = matchLength;
      int i = 0;
      while ((i < lastMatchLength) && (inPtr < inEnd)) {
        i++;
        _deleteNode(s);
        final c = _getc();
        textBuf[s] = c & 0xFF;
        if (s < f - 1) textBuf[s + n] = c & 0xFF;
        s = (s + 1) & (n - 1);
        rr = (rr + 1) & (n - 1);
        _insertNode(rr);
      }
      textSize += i;
      while (i < lastMatchLength) {
        i++;
        _deleteNode(s);
        s = (s + 1) & (n - 1);
        rr = (rr + 1) & (n - 1);
        len--;
        if (len > 0) _insertNode(rr);
      }
    } while (len > 0);
    _encodeEnd();
    final retCRC = _getCRC();

    Uint8List oBuf;
    int j;
    if (prependCRC) {
      oBuf = Uint8List(codeSize + 2);
      oBuf[0] = (retCRC >> 8) & 0xFF;
      oBuf[1] = retCRC & 0xFF;
      j = 2;
    } else {
      oBuf = Uint8List(codeSize);
      j = 0;
    }

    for (int i = 0; i < codeSize; i++) {
      oBuf[j++] = outBuf![i];
    }

    inBuf = null;
    outBuf = null;
    return oBuf;
  }

  WinlinkDecodeResult decode(
    Uint8List iBuf,
    bool checkCRC,
    int expectedUncompressedSize,
  ) {
    encDec = false;
    _init();

    inBuf = Uint8List(iBuf.length + 100);
    outBuf = Uint8List(expectedUncompressedSize + 10000);

    int iBufStart = 0;
    int suppliedCRC = 0;
    if (checkCRC) {
      iBufStart = 2;
      suppliedCRC = iBuf[1] & 0xFF;
      suppliedCRC |= iBuf[0] << 8;
    }

    for (int i = iBufStart; i < iBuf.length; i++) {
      inBuf![inEnd++] = iBuf[i];
    }

    textSize = _getc();
    textSize |= _getc() << 8;
    textSize |= _getc() << 16;
    textSize |= _getc() << 24;

    if (textSize == 0) {
      inBuf = null;
      outBuf = null;
      return WinlinkDecodeResult(Uint8List(0), 0);
    }

    _startHuff();

    for (int i = 0; i < (n - f); i++) {
      textBuf[i] = 0x20;
    }

    int rr = n - f;
    int count = 0;
    while (count < textSize) {
      int c = _decodeChar();
      if (c < 256) {
        _putc(c & 0xFF);
        textBuf[rr] = c & 0xFF;
        rr = (rr + 1) & (n - 1);
        count++;
      } else {
        int i = ((rr - _decodePosition()) - 1) & (n - 1);
        final jLen = (c - 255) + threshold;
        for (int k = 0; k < jLen; k++) {
          c = textBuf[(i + k) & (n - 1)];
          _putc(c & 0xFF);
          textBuf[rr] = c & 0xFF;
          rr = (rr + 1) & (n - 1);
          count++;
        }
      }
    }

    final oBuf = Uint8List(count);
    final retCRC = _getCRC() & 0xFFFF;
    for (int i = 0; i < count; i++) {
      oBuf[i] = outBuf![i];
    }

    if (checkCRC && (retCRC != suppliedCRC)) count = 0;

    inBuf = null;
    outBuf = null;
    return WinlinkDecodeResult(oBuf, count);
  }

  int _getCRC() => _swap(crc & 0xFFFF);

  void _init() {
    inPtr = 0;
    inEnd = 0;
    outPtr = 0;
    getBuf = 0;
    getLen = 0;
    putBuf = 0;
    putLen = 0;
    textSize = 0;
    codeSize = 0;
    matchPosition = 0;
    matchLength = 0;
    for (int i = 0; i < textBuf.length; i++) {
      textBuf[i] = 0;
    }
    lSon = List<int>.filled(n + 1, 0);
    dad = List<int>.filled(n + 1, 0);
    rSon = List<int>.filled(n + 256 + 1, 0);
    freq = List<int>.filled(t + 1, 0);
    parent = List<int>.filled(t + nChar, 0);
    son = List<int>.filled(t, 0);
    inBuf = null;
    outBuf = null;
    crc = 0;
  }

  void _doCRC(int c) {
    crc = ((crc << 8) ^ _crcTable[((crc >> 8) ^ c) & 0xFF]) & crcMask;
  }

  int _getc() {
    int c = 0;
    if (inPtr < inEnd) {
      c = inBuf![inPtr++] & 0xFF;
      if (!encDec) _doCRC(c);
    }
    return c;
  }

  void _putc(int c) {
    outBuf![outPtr++] = c & 0xFF;
    if (encDec) _doCRC(c & 0xFF);
  }

  void _initTree() {
    for (int i = n + 1; i <= n + 256; i++) {
      rSon[i] = nodeNil;
    }
    for (int i = 0; i < n; i++) {
      dad[i] = nodeNil;
    }
  }

  void _insertNode(int rNode) {
    int i, p, c;
    bool geq = true;

    p = n + 1 + textBuf[rNode];
    rSon[rNode] = nodeNil;
    lSon[rNode] = nodeNil;
    matchLength = 0;
    while (true) {
      if (geq) {
        if (rSon[p] == nodeNil) {
          rSon[p] = rNode;
          dad[rNode] = p;
          return;
        } else {
          p = rSon[p];
        }
      } else {
        if (lSon[p] == nodeNil) {
          lSon[p] = rNode;
          dad[rNode] = p;
          return;
        } else {
          p = lSon[p];
        }
      }
      i = 1;
      while ((i < f) && (textBuf[rNode + i] == textBuf[p + i])) {
        i++;
      }

      geq = (textBuf[rNode + i] >= textBuf[p + i]) || (i == f);

      if (i > threshold) {
        if (i > matchLength) {
          matchPosition = ((rNode - p) & (n - 1)) - 1;
          matchLength = i;
          if (matchLength >= f) break;
        }
        if (i == matchLength) {
          c = ((rNode - p) & (n - 1)) - 1;
          if (c < matchPosition) matchPosition = c;
        }
      }
    }

    dad[rNode] = dad[p];
    lSon[rNode] = lSon[p];
    rSon[rNode] = rSon[p];
    dad[lSon[p]] = rNode;
    dad[rSon[p]] = rNode;
    if (rSon[dad[p]] == p) {
      rSon[dad[p]] = rNode;
    } else {
      lSon[dad[p]] = rNode;
    }
    dad[p] = nodeNil;
  }

  void _deleteNode(int p) {
    int q;
    if (dad[p] == nodeNil) return;

    if (rSon[p] == nodeNil) {
      q = lSon[p];
    } else {
      if (lSon[p] == nodeNil) {
        q = rSon[p];
      } else {
        q = lSon[p];
        if (rSon[q] != nodeNil) {
          do {
            q = rSon[q];
          } while (rSon[q] != nodeNil);
          rSon[dad[q]] = lSon[q];
          dad[lSon[q]] = dad[q];
          lSon[q] = lSon[p];
          dad[lSon[p]] = q;
        }
        rSon[q] = rSon[p];
        dad[rSon[p]] = q;
      }
    }
    dad[q] = dad[p];
    if (rSon[dad[p]] == p) {
      rSon[dad[p]] = q;
    } else {
      lSon[dad[p]] = q;
    }
    dad[p] = nodeNil;
  }

  int _getBit() {
    while (getLen <= 8) {
      getBuf = (getBuf | (_getc() << (8 - getLen))) & 0xFFFF;
      getLen += 8;
    }
    final retVal = (getBuf >> 15) & 0x1;
    getBuf = (getBuf << 1) & 0xFFFF;
    getLen--;
    return retVal;
  }

  int _getByte() {
    while (getLen <= 8) {
      getBuf = (getBuf | (_getc() << (8 - getLen))) & 0xFFFF;
      getLen += 8;
    }
    final retVal = _hi(getBuf) & 0xFF;
    getBuf = (getBuf << 8) & 0xFFFF;
    getLen -= 8;
    return retVal;
  }

  void _putcode(int nBits, int c) {
    putBuf = (putBuf | (c >> putLen)) & 0xFFFF;
    putLen += nBits;
    if (putLen >= 8) {
      _putc(_hi(putBuf) & 0xFF);
      putLen -= 8;
      if (putLen >= 8) {
        _putc(_lo(putBuf) & 0xFF);
        codeSize += 2;
        putLen -= 8;
        putBuf = (c << (nBits - putLen)) & 0xFFFF;
      } else {
        putBuf = _swap(putBuf & 0xFF);
        codeSize += 1;
      }
    }
  }

  void _startHuff() {
    int i, j;
    for (i = 0; i < nChar; i++) {
      freq[i] = 1;
      son[i] = i + t;
      parent[i + t] = i;
    }
    i = 0;
    j = nChar;
    while (j <= r) {
      freq[j] = (freq[i] + freq[i + 1]) & 0xFFFF;
      son[j] = i;
      parent[i] = j;
      parent[i + 1] = j;
      i += 2;
      j++;
    }
    freq[t] = 0xFFFF;
    parent[r] = 0;
  }

  void _reconst() {
    int i, j = 0, k, fr, nn;
    for (i = 0; i < t; i++) {
      if (son[i] >= t) {
        freq[j] = (freq[i] + 1) >> 1;
        son[j] = son[i];
        j++;
      }
    }
    i = 0;
    j = nChar;
    while (j < t) {
      k = i + 1;
      fr = (freq[i] + freq[k]) & 0xFFFF;
      freq[j] = fr;
      k = j - 1;
      while (fr < freq[k]) {
        k--;
      }
      k++;
      for (nn = j; nn >= k + 1; nn--) {
        freq[nn] = freq[nn - 1];
        son[nn] = son[nn - 1];
      }
      freq[k] = fr;
      son[k] = i;
      i += 2;
      j++;
    }
    for (i = 0; i < t; i++) {
      k = son[i];
      parent[k] = i;
      if (k < t) parent[k + 1] = i;
    }
  }

  void _update(int c) {
    int i, j, k, nn;
    if (freq[r] == maxFreq) _reconst();
    c = parent[c + t];
    do {
      freq[c]++;
      k = freq[c];
      nn = c + 1;
      if (k > freq[nn]) {
        while (k > freq[nn + 1]) {
          nn++;
        }
        freq[c] = freq[nn];
        freq[nn] = k;

        i = son[c];
        parent[i] = nn;
        if (i < t) parent[i + 1] = nn;
        j = son[nn];
        son[nn] = i;

        parent[j] = c;
        if (j < t) parent[j + 1] = c;
        son[c] = j;

        c = nn;
      }
      c = parent[c];
    } while (c != 0);
  }

  void _encodeChar(int c) {
    int code = 0, k = parent[c + t];
    int len = 0;
    do {
      code >>= 1;
      if ((k & 1) > 0) code += 0x8000;
      len++;
      k = parent[k];
    } while (k != r);
    _putcode(len, code);
    _update(c);
  }

  void _encodePosition(int c) {
    final i = c >> 6;
    _putcode(_pLen[i], _pCode[i] << 8);
    _putcode(6, (c & 0x3F) << 10);
  }

  void _encodeEnd() {
    if (putLen > 0) {
      _putc(_hi(putBuf));
      codeSize++;
    }
  }

  int _decodeChar() {
    int c = son[r];
    while (c < t) {
      c = son[c + _getBit()];
    }
    c -= t;
    _update(c);
    return c & 0xFFFF;
  }

  int _decodePosition() {
    int i = _getByte();
    final c = (_dCode[i] << 6) & 0xFFFF;
    int j = _dLen[i];
    j -= 2;
    while (j > 0) {
      j--;
      i = ((i << 1) | _getBit()) & 0xFFFF;
    }
    return c | (i & 0x3F);
  }

  int _hi(int x) => (x >> 8) & 0xFF;

  int _lo(int x) => x & 0xFF;

  int _swap(int x) => (((x >> 8) & 0xFF) | ((x & 0xFF) << 8)) & 0xFFFF;
}

/// Computes and checks the single-byte checksum at the end of B2F mail blocks.
class WinLinkChecksum {
  WinLinkChecksum._();

  static int computeChecksum(Uint8List data, [int off = 0, int? len]) {
    final end = len ?? data.length;
    int crc = 0;
    for (int i = off; i < end; i++) {
      crc += data[i];
    }
    return ((~(crc % 256) + 1) % 256) & 0xFF;
  }

  static bool checkChecksum(Uint8List data, int checksum) {
    int crc = 0;
    for (int i = 0; i < data.length; i++) {
      crc += data[i];
    }
    return ((crc + checksum) & 0xFF) == 0;
  }

  static bool test() {
    final m1 = RadioUtils.hexStringToByteArray(
      '8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122',
    )!;
    if (!checkChecksum(m1, 0x53)) return false;
    if (computeChecksum(m1) != 0x53) return false;
    return true;
  }
}

/// Full CRC16 calculator for Winlink.
class WinlinkCrc16 {
  WinlinkCrc16._();

  static int _udpCRC16(int cp, int sum) {
    return (((sum << 8) & 0xff00) ^ _crc16Tab[(sum >> 8) & 0xff] ^ cp) & 0xFFFF;
  }

  /// Note: reverse the bytes of the CRC16 when placing it in front of binary data.
  static int compute(Uint8List p) {
    int sum = 0;
    final extendedP = Uint8List(p.length + 2);
    extendedP.setRange(0, p.length, p);
    for (final c in extendedP) {
      sum = _udpCRC16(c, sum);
    }
    return sum & 0xFFFF;
  }

  static bool test() {
    final m1 = RadioUtils.hexStringToByteArray(
      'C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122',
    )!;
    return compute(m1) == 0x348A;
  }

  static const List<int> _crc16Tab = [
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7, //
    0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef, //
    0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6, //
    0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de, //
    0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485, //
    0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d, //
    0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4, //
    0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc, //
    0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823, //
    0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b, //
    0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12, //
    0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a, //
    0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41, //
    0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49, //
    0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70, //
    0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78, //
    0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f, //
    0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067, //
    0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e, //
    0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256, //
    0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d, //
    0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405, //
    0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c, //
    0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634, //
    0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab, //
    0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3, //
    0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a, //
    0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92, //
    0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9, //
    0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1, //
    0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8, //
    0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0, //
  ];
}
