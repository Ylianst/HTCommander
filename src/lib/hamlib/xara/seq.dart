/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Whitening and phasor index sequences.
*/

import 'dart:typed_data';

import 'rnd.dart';

const double hfSeed = 292.0;
const double fmSeed = 43.0;
const int whiteningLen = 150000;
const int pskCarriers = 13;
const int pskSymbols = 471;
const int ofdmBins = 128;
const int ofdmSymbols = 469;
const int dataDatLen = 65000;

Uint8List whitening(double seed) {
  final VbRnd r = VbRnd.stream(seed);
  final Uint8List out = Uint8List(whiteningLen);
  for (int i = 0; i < whiteningLen; i++) {
    out[i] = r.randInt(1);
  }
  return out;
}

List<Uint8List> pskPhasorIndex() {
  final VbRnd r = VbRnd.stream(hfSeed);
  final List<Uint8List> d = List.generate(pskCarriers, (_) => Uint8List(pskSymbols));
  for (final (int lo, int hi) in const [(0, 411), (411, pskSymbols)]) {
    for (final Uint8List row in d) {
      for (int k = lo; k < hi; k++) {
        row[k] = r.randInt(128);
      }
    }
  }
  return d;
}

Uint8List dataDat() {
  final VbRnd r = VbRnd.stream(hfSeed);
  final Uint8List out = Uint8List(dataDatLen);
  for (int i = 0; i < dataDatLen; i++) {
    out[i] = r.randInt(128);
  }
  return out;
}

List<Uint8List> ofdmPhasorIndex() {
  final Uint8List d = dataDat();
  int it = 0;
  final List<Uint8List> out = List.generate(ofdmBins, (_) => Uint8List(ofdmSymbols));
  for (final (int lo, int hi) in const [(0, 409), (409, ofdmSymbols)]) {
    for (final Uint8List row in out) {
      for (int m = lo; m < hi; m++) {
        row[m] = d[it++];
      }
    }
  }
  return out;
}
