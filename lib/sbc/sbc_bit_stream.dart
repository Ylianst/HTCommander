/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

/// Bitstream reader/writer for SBC encoding and decoding.
class SbcBitStream {
  final Uint8List _data;
  final int _maxBytes;
  final bool _isReader;

  int _bytePosition;
  int _accumulator;
  int _bitsInAccumulator;
  bool _error;

  SbcBitStream(this._data, int size, {required bool isReader})
    : _maxBytes = size,
      // Named parameters cannot be private, so the field is assigned here
      // rather than via an initializing formal.
      // ignore: prefer_initializing_formals
      _isReader = isReader,
      _bytePosition = 0,
      _accumulator = 0,
      _bitsInAccumulator = 0,
      _error = false;

  bool get hasError => _error;

  /// Current logical bit position in the stream.
  ///
  /// For a reader, [_bitsInAccumulator] holds bits already loaded but not yet
  /// consumed, so they must be subtracted. For a writer, it holds bits that
  /// have been written but not yet flushed, so they must be added. (The C#
  /// original used the reader formula in both modes, which corrupted padding
  /// when writing frames whose data did not end on a 4-bit boundary.)
  int get bitPosition => _isReader
      ? (_bytePosition * 8) - _bitsInAccumulator
      : (_bytePosition * 8) + _bitsInAccumulator;

  /// Read bits from the stream (1-32 bits).
  int getBits(int numBits) {
    if (numBits == 0) {
      return 0;
    }

    if (numBits < 0 || numBits > 32) {
      _error = true;
      return 0;
    }

    // Refill accumulator if needed
    while (_bitsInAccumulator < numBits && _bytePosition < _maxBytes) {
      _accumulator =
          ((_accumulator << 8) | _data[_bytePosition++]) & 0xFFFFFFFF;
      _bitsInAccumulator += 8;
    }

    // Check if we have enough bits
    if (_bitsInAccumulator < numBits) {
      // Not enough data - return what we have padded with zeros
      final int result = _accumulator << (numBits - _bitsInAccumulator);
      _bitsInAccumulator = 0;
      _accumulator = 0;
      _error = true;
      return result & ((1 << numBits) - 1);
    }

    // Extract the requested bits
    _bitsInAccumulator -= numBits;
    final int value =
        (_accumulator >> _bitsInAccumulator) & ((1 << numBits) - 1);
    _accumulator &= (1 << _bitsInAccumulator) - 1;

    return value;
  }

  /// Read bits and verify they match expected value.
  void getFixedBits(int numBits, int expectedValue) {
    final int value = getBits(numBits);
    if (value != expectedValue) {
      _error = true;
    }
  }

  /// Write bits to the stream (0-32 bits).
  void putBits(int value, int numBits) {
    if (numBits == 0) {
      return;
    }

    if (numBits < 0 || numBits > 32) {
      _error = true;
      return;
    }

    // Mask the value to the requested number of bits
    value &= (1 << numBits) - 1;

    // Add to accumulator
    _accumulator = (_accumulator << numBits) | value;
    _bitsInAccumulator += numBits;

    // Flush full bytes
    while (_bitsInAccumulator >= 8) {
      if (_bytePosition >= _maxBytes) {
        _error = true;
        return;
      }

      _bitsInAccumulator -= 8;
      _data[_bytePosition++] = (_accumulator >> _bitsInAccumulator) & 0xFF;
      _accumulator &= (1 << _bitsInAccumulator) - 1;
    }
  }

  /// Flush any remaining bits in the accumulator to the output.
  void flush() {
    if (_bitsInAccumulator > 0) {
      if (_bytePosition >= _maxBytes) {
        _error = true;
        return;
      }

      // Pad with zeros and write the final byte
      _data[_bytePosition++] =
          (_accumulator << (8 - _bitsInAccumulator)) & 0xFF;
      _bitsInAccumulator = 0;
      _accumulator = 0;
    }
  }
}
