/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Numeric helpers that reproduce Rust f32/u32/u64 semantics in Dart.
*/

import 'dart:typed_data';

final Float32List _f32 = Float32List(1);
final ByteData _bd = ByteData(8);

/// Rounds [x] to the nearest IEEE single-precision value (Rust `as f32`).
double toF32(double x) {
  _f32[0] = x;
  return _f32[0];
}

/// Rust `f32::to_bits`.
int f32Bits(double x) {
  _bd.setFloat32(0, x);
  return _bd.getUint32(0);
}

/// Rust `f64::to_bits`, as the raw 64-bit pattern.
int f64Bits(double x) {
  _bd.setFloat64(0, x);
  return _bd.getInt64(0);
}

/// Rust `f as u32`: truncates toward zero, saturates, NaN becomes 0.
int asU32(double x) {
  if (x.isNaN || x <= 0) return 0;
  if (x >= 4294967295.0) return 0xFFFFFFFF;
  return x.truncate();
}

/// i64::MAX (0x7FFFFFFFFFFFFFFF) on native; computed because dart2js rejects
/// 64-bit integer literals.
final int maxI64 = -1 >>> 1;

/// Rust `f as i64`: truncates toward zero, saturates, NaN becomes 0.
int asI64(double x) {
  if (x.isNaN) return 0;
  if (x >= 9223372036854775807.0) return maxI64;
  if (x <= -9223372036854775808.0) return -0x8000000000000000;
  return x.truncate();
}

/// Rust `f64::round_ties_even`.
double roundTiesEven(double x) {
  if (x.isNaN || x.isInfinite) return x;
  final double r = x.roundToDouble();
  if ((r - x).abs() == 0.5) return 2.0 * (x / 2.0).roundToDouble();
  return r;
}

/// Unsigned 64-bit comparison of two raw bit patterns.
int compareU64(int a, int b) {
  final int x = a ^ 0x8000000000000000;
  final int y = b ^ 0x8000000000000000;
  return x < y ? -1 : (x > y ? 1 : 0);
}

/// Number of significant bits of an unsigned 64-bit pattern.
int bitWidthU64(int v) => v < 0 ? 64 : v.bitLength;
