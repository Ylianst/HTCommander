// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'native_reed_solomon.dart';

bool get supported => false;

NativeReedSolomon create(
  int mode,
  int roots,
  int fcr,
  int prim,
  int inversePrim,
  List<int> exp,
  List<int> log,
  List<int> generator,
) => throw UnsupportedError('Native Reed-Solomon is unavailable');
