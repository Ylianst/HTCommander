/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// fx25.dart - FX.25 Forward Error Correction support structures and initialization
//
// Ported from C# HamLib/Fx25.cs
//

// ignore_for_file: avoid_print

import 'dart:typed_data';

/// Reed-Solomon codec control block.
class ReedSolomonCodec {
  int mm = 0; // Bits per symbol
  int nn = 0; // Symbols per block (= (1<<mm)-1)
  Uint8List alphaTo = Uint8List(0); // log lookup table
  Uint8List indexOf = Uint8List(0); // Antilog lookup table
  Uint8List genPoly = Uint8List(0); // Generator polynomial
  int nRoots = 0; // Number of generator roots = number of parity symbols
  int fcr = 0; // First consecutive root, index form
  int prim = 0; // Primitive element, index form
  int iPrim = 0; // prim-th root of 1, index form

  /// Modulo NN operation optimized for Reed-Solomon.
  int modNN(int x) {
    while (x >= nn) {
      x -= nn;
      x = (x >> mm) + (x & nn);
    }
    return x;
  }
}

/// FX.25 correlation tag definition.
class CorrelationTag {
  int value = 0; // 64 bit value, send LSB first
  int nBlockRadio = 0; // Size of transmitted block, all in bytes
  int kDataRadio = 0; // Size of transmitted data part
  int nBlockRs = 0; // Size of RS algorithm block
  int kDataRs = 0; // Size of RS algorithm data part
  int iTab = 0; // Index into Tab array

  CorrelationTag({
    required this.value,
    required this.nBlockRadio,
    required this.kDataRadio,
    required this.nBlockRs,
    required this.kDataRs,
    required this.iTab,
  });
}

/// FX.25 codec configuration.
class Fx25CodecConfig {
  int symSize; // Symbol size, bits (1-8). Always 8 for this application
  int genPoly; // Field generator polynomial coefficients
  int fcs; // First root of RS code generator polynomial, index form
  int prim; // Primitive element to generate polynomial roots
  int nRoots; // RS code generator polynomial degree (number of roots)
  ReedSolomonCodec? rs; // Pointer to RS codec control block

  Fx25CodecConfig({
    required this.symSize,
    required this.genPoly,
    required this.fcs,
    required this.prim,
    required this.nRoots,
    this.rs,
  });
}

/// FX.25 static configuration and helper functions.
class Fx25 {
  Fx25._();

  // Constants
  static const int ctagMin = 0x01;
  static const int ctagMax = 0x0B;
  static const int fx25MaxData = 239; // i.e. RS(255,239)
  static const int fx25MaxCheck = 64; // e.g. RS(255, 191)
  static const int fx25BlockSize =
      255; // Block size always 255 for 8 bit symbols
  static const int _closeEnough =
      8; // How many bits can be wrong in tag yet match?

  static final List<Fx25CodecConfig> _codecTab = <Fx25CodecConfig>[
    Fx25CodecConfig(
      symSize: 8,
      genPoly: 0x11d,
      fcs: 1,
      prim: 1,
      nRoots: 16,
    ), // RS(255,239)
    Fx25CodecConfig(
      symSize: 8,
      genPoly: 0x11d,
      fcs: 1,
      prim: 1,
      nRoots: 32,
    ), // RS(255,223)
    Fx25CodecConfig(
      symSize: 8,
      genPoly: 0x11d,
      fcs: 1,
      prim: 1,
      nRoots: 64,
    ), // RS(255,191)
  ];

  static final List<CorrelationTag> _tags = <CorrelationTag>[
    // Tag_00 - Reserved
    CorrelationTag(
      value: 0x566ED2717946107E,
      nBlockRadio: 0,
      kDataRadio: 0,
      nBlockRs: 0,
      kDataRs: 0,
      iTab: -1,
    ),

    // Tag_01 - RS(255, 239) 16-byte check value, 239 information bytes
    CorrelationTag(
      value: 0xB74DB7DF8A532F3E,
      nBlockRadio: 255,
      kDataRadio: 239,
      nBlockRs: 255,
      kDataRs: 239,
      iTab: 0,
    ),
    // Tag_02 - RS(144,128)
    CorrelationTag(
      value: 0x26FF60A600CC8FDE,
      nBlockRadio: 144,
      kDataRadio: 128,
      nBlockRs: 255,
      kDataRs: 239,
      iTab: 0,
    ),
    // Tag_03 - RS(80,64)
    CorrelationTag(
      value: 0xC7DC0508F3D9B09E,
      nBlockRadio: 80,
      kDataRadio: 64,
      nBlockRs: 255,
      kDataRs: 239,
      iTab: 0,
    ),
    // Tag_04 - RS(48,32)
    CorrelationTag(
      value: 0x8F056EB4369660EE,
      nBlockRadio: 48,
      kDataRadio: 32,
      nBlockRs: 255,
      kDataRs: 239,
      iTab: 0,
    ),

    // Tag_05 - RS(255, 223) 32-byte check value, 223 information bytes
    CorrelationTag(
      value: 0x6E260B1AC5835FAE,
      nBlockRadio: 255,
      kDataRadio: 223,
      nBlockRs: 255,
      kDataRs: 223,
      iTab: 1,
    ),
    // Tag_06 - RS(160,128)
    CorrelationTag(
      value: 0xFF94DC634F1CFF4E,
      nBlockRadio: 160,
      kDataRadio: 128,
      nBlockRs: 255,
      kDataRs: 223,
      iTab: 1,
    ),
    // Tag_07 - RS(96,64)
    CorrelationTag(
      value: 0x1EB7B9CDBC09C00E,
      nBlockRadio: 96,
      kDataRadio: 64,
      nBlockRs: 255,
      kDataRs: 223,
      iTab: 1,
    ),
    // Tag_08 - RS(64,32)
    CorrelationTag(
      value: 0xDBF869BD2DBB1776,
      nBlockRadio: 64,
      kDataRadio: 32,
      nBlockRs: 255,
      kDataRs: 223,
      iTab: 1,
    ),

    // Tag_09 - RS(255, 191) 64-byte check value, 191 information bytes
    CorrelationTag(
      value: 0x3ADB0C13DEAE2836,
      nBlockRadio: 255,
      kDataRadio: 191,
      nBlockRs: 255,
      kDataRs: 191,
      iTab: 2,
    ),
    // Tag_0A - RS(192, 128)
    CorrelationTag(
      value: 0xAB69DB6A543188D6,
      nBlockRadio: 192,
      kDataRadio: 128,
      nBlockRs: 255,
      kDataRs: 191,
      iTab: 2,
    ),
    // Tag_0B - RS(128, 64)
    CorrelationTag(
      value: 0x4A4ABEC4A724B796,
      nBlockRadio: 128,
      kDataRadio: 64,
      nBlockRs: 255,
      kDataRs: 191,
      iTab: 2,
    ),

    // Tag_0C through 0F - Undefined
    CorrelationTag(
      value: 0x0293D578626B67E6,
      nBlockRadio: 0,
      kDataRadio: 0,
      nBlockRs: 0,
      kDataRs: 0,
      iTab: -1,
    ),
    CorrelationTag(
      value: 0xE3B0B0D6917E58A6,
      nBlockRadio: 0,
      kDataRadio: 0,
      nBlockRs: 0,
      kDataRs: 0,
      iTab: -1,
    ),
    CorrelationTag(
      value: 0x720267AF1BE1F846,
      nBlockRadio: 0,
      kDataRadio: 0,
      nBlockRs: 0,
      kDataRs: 0,
      iTab: -1,
    ),
    CorrelationTag(
      value: 0x93210201E8F4C706,
      nBlockRadio: 0,
      kDataRadio: 0,
      nBlockRs: 0,
      kDataRs: 0,
      iTab: -1,
    ),
  ];

  static int _debugLevel = 0;

  /// Initialize FX.25 subsystem.
  ///
  /// [debugLevel]: 0=errors only, 1=default, 2=verbose, 3=dump data.
  static void init(int debugLevel) {
    _debugLevel = debugLevel;

    // Initialize Reed-Solomon codecs
    for (int i = 0; i < _codecTab.length; i++) {
      _codecTab[i].rs = _initRs(
        _codecTab[i].symSize,
        _codecTab[i].genPoly,
        _codecTab[i].fcs,
        _codecTab[i].prim,
        _codecTab[i].nRoots,
      );

      if (_codecTab[i].rs == null) {
        print('FX.25 internal error: InitRs failed!');
        throw StateError('FX.25 InitRs failed');
      }
    }

    // Verify integrity of tables and assumptions
    for (int j = 0; j < 16; j++) {
      for (int k = 0; k < 16; k++) {
        final int popcount = _popCount(_tags[j].value ^ _tags[k].value);
        if (j == k) {
          assert(popcount == 0);
        } else {
          assert(popcount == 32);
        }
      }
    }

    // Verify tag configurations
    for (int j = ctagMin; j <= ctagMax; j++) {
      assert(
        _tags[j].nBlockRadio - _tags[j].kDataRadio ==
            _codecTab[_tags[j].iTab].nRoots,
      );
      assert(
        _tags[j].nBlockRs - _tags[j].kDataRs == _codecTab[_tags[j].iTab].nRoots,
      );
      assert(_tags[j].nBlockRs == fx25BlockSize);
    }
  }

  /// Get the Reed-Solomon codec for a specific correlation tag.
  static ReedSolomonCodec getRs(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    assert(_tags[ctagNum].iTab >= 0 && _tags[ctagNum].iTab < _codecTab.length);
    assert(_codecTab[_tags[ctagNum].iTab].rs != null);
    return _codecTab[_tags[ctagNum].iTab].rs!;
  }

  /// Get correlation tag value.
  static int getCtagValue(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    return _tags[ctagNum].value;
  }

  /// Get data size transmitted over radio.
  static int getKDataRadio(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    return _tags[ctagNum].kDataRadio;
  }

  /// Get data size for RS algorithm.
  static int getKDataRs(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    return _tags[ctagNum].kDataRs;
  }

  /// Get number of check bytes (roots).
  static int getNRoots(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    return _codecTab[_tags[ctagNum].iTab].nRoots;
  }

  /// Get current debug level.
  static int getDebugLevel() => _debugLevel;

  /// Pick suitable transmission format based on user preference and size of
  /// data part required.
  ///
  /// [fxMode]: 0 = none, 1 = pick automatically, 16/32/64 = use this many
  /// check bytes, 100 + n = use tag n (0x01-0x0B).
  /// [dlen]: required size for transmitted "data" part, in bytes.
  /// Returns a correlation tag number in [ctagMin]..[ctagMax], or -1 on failure.
  static int pickMode(int fxMode, int dlen) {
    if (fxMode <= 0) return -1;

    // Specify a specific tag by adding 100 to the number.
    if (fxMode - 100 >= ctagMin && fxMode - 100 <= ctagMax) {
      if (dlen <= getKDataRadio(fxMode - 100)) {
        return fxMode - 100;
      } else {
        return -1; // Assuming caller prints failure message
      }
    }
    // Specify number of check bytes.
    else if (fxMode == 16 || fxMode == 32 || fxMode == 64) {
      for (int k = ctagMax; k >= ctagMin; k--) {
        if (fxMode == getNRoots(k) && dlen <= getKDataRadio(k)) {
          return k;
        }
      }
      return -1;
    }

    // For any other number, try to come up with something reasonable.
    const List<int> prefer = [0x04, 0x03, 0x06, 0x09, 0x05, 0x01];
    for (int k = 0; k < prefer.length; k++) {
      final int m = prefer[k];
      if (dlen <= getKDataRadio(m)) {
        return m;
      }
    }
    return -1;
  }

  /// Find matching correlation tag for the given 64-bit value.
  ///
  /// Returns a tag index ([ctagMin]..[ctagMax]) or -1 if no match.
  static int tagFindMatch(int t) {
    for (int c = ctagMin; c <= ctagMax; c++) {
      if (_popCount(t ^ _tags[c].value) <= _closeEnough) {
        return c;
      }
    }
    return -1;
  }

  /// Count number of '1' bits in a 64-bit integer.
  static int _popCount(int x) {
    int count = 0;
    while (x != 0) {
      count++;
      x &= x - 1; // Clear the least significant bit set
    }
    return count;
  }

  /// Initialize a Reed-Solomon codec.
  static ReedSolomonCodec? _initRs(
    int symsize,
    int gfpoly,
    int fcr,
    int prim,
    int nroots,
  ) {
    if (symsize > 8) return null;
    if (fcr >= (1 << symsize)) return null;
    if (prim == 0 || prim >= (1 << symsize)) return null;
    if (nroots >= (1 << symsize)) return null;

    final ReedSolomonCodec rs = ReedSolomonCodec()
      ..mm = symsize
      ..nn = (1 << symsize) - 1;

    rs.alphaTo = Uint8List(rs.nn + 1);
    rs.indexOf = Uint8List(rs.nn + 1);

    // Generate Galois field lookup tables
    final int a0 = rs.nn;
    rs.indexOf[0] = a0; // log(zero) = -inf
    rs.alphaTo[a0] = 0; // alpha**-inf = 0

    int sr = 1;
    for (int i = 0; i < rs.nn; i++) {
      rs.indexOf[sr] = i;
      rs.alphaTo[i] = sr;
      sr <<= 1;
      if ((sr & (1 << symsize)) != 0) {
        sr ^= gfpoly;
      }
      sr &= rs.nn;
    }

    if (sr != 1) {
      // Field generator polynomial is not primitive
      return null;
    }

    // Form RS code generator polynomial from its roots
    rs.genPoly = Uint8List(nroots + 1);
    rs.fcr = fcr;
    rs.prim = prim;
    rs.nRoots = nroots;

    // Find prim-th root of 1, used in decoding
    int iprim;
    for (iprim = 1; (iprim % prim) != 0; iprim += rs.nn) {}
    rs.iPrim = iprim ~/ prim;

    rs.genPoly[0] = 1;
    for (int i = 0, root = fcr * prim; i < nroots; i++, root += prim) {
      rs.genPoly[i + 1] = 1;

      // Multiply rs.genPoly[] by @**(root + x)
      for (int j = i; j > 0; j--) {
        if (rs.genPoly[j] != 0) {
          rs.genPoly[j] =
              rs.genPoly[j - 1] ^
              rs.alphaTo[rs.modNN(rs.indexOf[rs.genPoly[j]] + root)];
        } else {
          rs.genPoly[j] = rs.genPoly[j - 1];
        }
      }
      rs.genPoly[0] = rs.alphaTo[rs.modNN(rs.indexOf[rs.genPoly[0]] + root)];
    }

    // Convert rs.genPoly[] to index form for quicker encoding
    for (int i = 0; i <= nroots; i++) {
      rs.genPoly[i] = rs.indexOf[rs.genPoly[i]];
    }

    return rs;
  }

  /// Hex dump utility for debugging.
  static void hexDump(Uint8List data, int len) {
    int offset = 0;
    while (len > 0) {
      final int n = len < 16 ? len : 16;
      final StringBuffer sb = StringBuffer();
      sb.write('  ${offset.toRadixString(16).padLeft(3, '0')}: ');

      for (int i = 0; i < n; i++) {
        sb.write(' ${data[offset + i].toRadixString(16).padLeft(2, '0')}');
      }

      for (int i = n; i < 16; i++) {
        sb.write('   ');
      }

      sb.write('  ');
      for (int i = 0; i < n; i++) {
        final int c = data[offset + i];
        sb.write(c >= 32 && c < 127 ? String.fromCharCode(c) : '.');
      }
      print(sb.toString());

      offset += 16;
      len -= 16;
    }
  }
}
