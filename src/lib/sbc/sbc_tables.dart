/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'sbc_enums.dart';
import 'sbc_frame.dart';

/// Pre-calculated tables and constants for SBC encoding/decoding.
class SbcTables {
  SbcTables._();

  /// CRC-8 lookup table for header validation.
  /// Generator polynomial: G(X) = X^8 + X^4 + X^3 + X^2 + 1 (0x1d)
  static final Uint8List crc8Table = Uint8List.fromList(const <int>[
    0x00,
    0x1d,
    0x3a,
    0x27,
    0x74,
    0x69,
    0x4e,
    0x53,
    0xe8,
    0xf5,
    0xd2,
    0xcf,
    0x9c,
    0x81,
    0xa6,
    0xbb,
    0xcd,
    0xd0,
    0xf7,
    0xea,
    0xb9,
    0xa4,
    0x83,
    0x9e,
    0x25,
    0x38,
    0x1f,
    0x02,
    0x51,
    0x4c,
    0x6b,
    0x76,
    0x87,
    0x9a,
    0xbd,
    0xa0,
    0xf3,
    0xee,
    0xc9,
    0xd4,
    0x6f,
    0x72,
    0x55,
    0x48,
    0x1b,
    0x06,
    0x21,
    0x3c,
    0x4a,
    0x57,
    0x70,
    0x6d,
    0x3e,
    0x23,
    0x04,
    0x19,
    0xa2,
    0xbf,
    0x98,
    0x85,
    0xd6,
    0xcb,
    0xec,
    0xf1,
    0x13,
    0x0e,
    0x29,
    0x34,
    0x67,
    0x7a,
    0x5d,
    0x40,
    0xfb,
    0xe6,
    0xc1,
    0xdc,
    0x8f,
    0x92,
    0xb5,
    0xa8,
    0xde,
    0xc3,
    0xe4,
    0xf9,
    0xaa,
    0xb7,
    0x90,
    0x8d,
    0x36,
    0x2b,
    0x0c,
    0x11,
    0x42,
    0x5f,
    0x78,
    0x65,
    0x94,
    0x89,
    0xae,
    0xb3,
    0xe0,
    0xfd,
    0xda,
    0xc7,
    0x7c,
    0x61,
    0x46,
    0x5b,
    0x08,
    0x15,
    0x32,
    0x2f,
    0x59,
    0x44,
    0x63,
    0x7e,
    0x2d,
    0x30,
    0x17,
    0x0a,
    0xb1,
    0xac,
    0x8b,
    0x96,
    0xc5,
    0xd8,
    0xff,
    0xe2,
    0x26,
    0x3b,
    0x1c,
    0x01,
    0x52,
    0x4f,
    0x68,
    0x75,
    0xce,
    0xd3,
    0xf4,
    0xe9,
    0xba,
    0xa7,
    0x80,
    0x9d,
    0xeb,
    0xf6,
    0xd1,
    0xcc,
    0x9f,
    0x82,
    0xa5,
    0xb8,
    0x03,
    0x1e,
    0x39,
    0x24,
    0x77,
    0x6a,
    0x4d,
    0x50,
    0xa1,
    0xbc,
    0x9b,
    0x86,
    0xd5,
    0xc8,
    0xef,
    0xf2,
    0x49,
    0x54,
    0x73,
    0x6e,
    0x3d,
    0x20,
    0x07,
    0x1a,
    0x6c,
    0x71,
    0x56,
    0x4b,
    0x18,
    0x05,
    0x22,
    0x3f,
    0x84,
    0x99,
    0xbe,
    0xa3,
    0xf0,
    0xed,
    0xca,
    0xd7,
    0x35,
    0x28,
    0x0f,
    0x12,
    0x41,
    0x5c,
    0x7b,
    0x66,
    0xdd,
    0xc0,
    0xe7,
    0xfa,
    0xa9,
    0xb4,
    0x93,
    0x8e,
    0xf8,
    0xe5,
    0xc2,
    0xdf,
    0x8c,
    0x91,
    0xb6,
    0xab,
    0x10,
    0x0d,
    0x2a,
    0x37,
    0x64,
    0x79,
    0x5e,
    0x43,
    0xb2,
    0xaf,
    0x88,
    0x95,
    0xc6,
    0xdb,
    0xfc,
    0xe1,
    0x5a,
    0x47,
    0x60,
    0x7d,
    0x2e,
    0x33,
    0x14,
    0x09,
    0x7f,
    0x62,
    0x45,
    0x58,
    0x0b,
    0x16,
    0x31,
    0x2c,
    0x97,
    0x8a,
    0xad,
    0xb0,
    0xe3,
    0xfe,
    0xd9,
    0xc4,
  ]);

  /// Range scale factors for dequantization (fixed-point 1.28 format).
  /// range_scale[i] = (1 << 28) / ((1 << (i+1)) - 1) for i in [0..15]
  static final Int32List rangeScale = Int32List.fromList(const <int>[
    0x0FFFFFFF,
    0x05555556,
    0x02492492,
    0x01111111,
    0x00842108,
    0x00410410,
    0x00204081,
    0x00101010,
    0x00080402,
    0x00040100,
    0x00020040,
    0x00010010,
    0x00008004,
    0x00004001,
    0x00002000,
    0x00001000,
  ]);

  /// Cosine values for 8-point DCT (fixed-point 0.13 format).
  /// cos(i*pi/8) for i = [0..3]
  static final Int16List cos8 = Int16List.fromList(const <int>[
    8192,
    7568,
    5793,
    3135,
  ]);

  /// Cosine values for 16-point DCT (fixed-point 0.13 format).
  /// cos(i*pi/16) for i = [0..7]
  static final Int16List cos16 = Int16List.fromList(const <int>[
    8192,
    8035,
    7568,
    6811,
    5793,
    4551,
    3135,
    1598,
  ]);

  /// Loudness offset for 4 subbands [frequency][subband].
  static final List<List<int>> loudnessOffset4 = const <List<int>>[
    <int>[-1, 0, 0, 0], // 16 kHz
    <int>[-2, 0, 0, 1], // 32 kHz
    <int>[-2, 0, 0, 1], // 44.1 kHz
    <int>[-2, 0, 0, 1], // 48 kHz
  ];

  /// Loudness offset for 8 subbands [frequency][subband].
  static final List<List<int>> loudnessOffset8 = const <List<int>>[
    <int>[-2, 0, 0, 0, 0, 0, 0, 1], // 16 kHz
    <int>[-3, 0, 0, 0, 0, 0, 1, 2], // 32 kHz
    <int>[-4, 0, 0, 0, 0, 0, 1, 2], // 44.1 kHz
    <int>[-4, 0, 0, 0, 0, 0, 1, 2], // 48 kHz
  ];

  /// Saturate value to 16-bit signed range.
  static int saturate16(int value) {
    if (value > 32767) {
      return 32767;
    }
    if (value < -32768) {
      return -32768;
    }
    return value;
  }

  /// Count leading zeros in a 32-bit unsigned integer.
  static int countLeadingZeros(int value) {
    value &= 0xFFFFFFFF;
    if (value == 0) {
      return 32;
    }

    int count = 0;
    if ((value & 0xFFFF0000) == 0) {
      count += 16;
      value = (value << 16) & 0xFFFFFFFF;
    }
    if ((value & 0xFF000000) == 0) {
      count += 8;
      value = (value << 8) & 0xFFFFFFFF;
    }
    if ((value & 0xF0000000) == 0) {
      count += 4;
      value = (value << 4) & 0xFFFFFFFF;
    }
    if ((value & 0xC0000000) == 0) {
      count += 2;
      value = (value << 2) & 0xFFFFFFFF;
    }
    if ((value & 0x80000000) == 0) {
      count += 1;
    }

    return count;
  }

  /// Compute CRC-8 of frame data.
  static int computeCrc(SbcFrame frame, Uint8List data, int size) {
    final int nch = frame.mode != SbcMode.mono ? 2 : 1;
    final int nsb = frame.subbands;
    final int nbit =
        nch * nsb * 4 + (frame.mode == SbcMode.jointStereo ? nsb : 0);

    if (size < ((SbcFrame.headerSize * 8 + nbit + 7) >> 3)) {
      return -1;
    }

    int crc = 0x0f;
    crc = crc8Table[crc ^ data[1]];
    crc = crc8Table[crc ^ data[2]];

    for (int i = 4; i < 4 + nbit ~/ 8; i++) {
      crc = crc8Table[crc ^ data[i]];
    }

    if (nbit % 8 != 0) {
      crc =
          ((crc << 4) ^ crc8Table[(crc >> 4) ^ (data[4 + nbit ~/ 8] >> 4)]) &
          0xFF;
    }

    return crc;
  }
}
