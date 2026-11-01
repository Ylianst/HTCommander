/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM control frames: three-tone codewords keyed by call hash, plus lead-in.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'call.dart';
import 'fm_level.dart';
import 'numeric.dart';
import 'rnd.dart';
import 'seq.dart' as seq;

const int ctrlSymbol = 1024;
const int codeRows = 10;
const int leadRows = 28;
const int noLeadRow = leadRows + 1;
const double toneAmp = 1.0 / 2.45;
const double _paprDb = 7.45;
const int ctrlBlock = 7;
const int codeBlock0 = 13;
const int leadBlock0 = 27;
const int tamperKey = 0x599;

/// FM control code numbers.
abstract final class FmCode {
  static const int ackStay = 1;
  static const int nack = 2;
  static const int qrt = 3;
  static const int brk = 4;
  static const int ackUp2 = 5;
  static const int ackDown = 6;
  static const int ackUp1 = 7;
  static const int ackUp3 = 8;
  static const int ackUp6 = 9;
  static const int ackSecondOnly = 10;
  static const int ackFirstOnly = 11;
  static const int ackReq0 = 12;
  static const int ackReq1 = 13;
  static const int goAhead = 14;
  static const int idle = 20;
  static const int noTraffic = 21;
  static const int relayFailed = 22;
  static const int connectReplyNarrow = 23;
  static const int connectReplyWide = 24;
  static const List<int> ackReq = <int>[ackReq0, ackReq1];
}

/// Three tone bins of one control symbol.
typedef Tones = List<int>;

/// Ten rows of tones.
typedef Codeword = List<Tones>;

List<Tones> _rows(VbRnd r, int count, int nblock, int block0) {
  return List<Tones>.generate(count, (_) {
    final List<int> bases = <int>[];
    final List<int> tones = List<int>.filled(3, 0);
    for (int i = 0; i < 3; i++) {
      int b;
      do {
        b = r.randInt(nblock - 1) * ctrlBlock + block0;
      } while (bases.contains(b));
      bases.add(b);
      tones[i] = b + r.randInt(6);
    }
    return List<int>.unmodifiable(tones);
  }, growable: false);
}

List<Codeword> codes(int key) {
  final VbRnd r = VbRnd()..seedRndWide(key + 10);
  return List<Codeword>.generate(22, (_) => _rows(r, codeRows, 7, codeBlock0), growable: false);
}

List<Codeword> connectCodes(int key) {
  final VbRnd r = VbRnd()..seedRndWide(key + 199);
  return List<Codeword>.generate(2, (_) => _rows(r, codeRows, 7, codeBlock0), growable: false);
}

final List<Tones> leadIn = () {
  final VbRnd r = VbRnd.stream(seq.fmSeed);
  for (int i = 0; i < seq.whiteningLen; i++) {
    r.nextF32();
  }
  return _rows(r, leadRows, 3, leadBlock0);
}();

enum Side {
  source,
  target;

  Side get other => this == Side.source ? Side.target : Side.source;

  int get idx => index;
}

class Codebook {
  final int keyD;
  final int keyU;
  final List<Codeword> _codes;

  Codebook(this.keyD, this.keyU) : _codes = <Codeword>[...codes(keyD), ...connectCodes(keyU)];

  factory Codebook.forLink(List<int> upstream, List<int> downstream) =>
      Codebook(callHash(downstream), callHash(upstream));

  Codeword code(int code) => _codes[code - 1];

  List<Tones> frameRows(int code, int lead) {
    if (lead > leadRows) throw ArgumentError('lead $lead');
    return <Tones>[...leadIn.sublist(leadRows - lead), ...this.code(code)];
  }

  @override
  bool operator ==(Object other) => other is Codebook && other.keyD == keyD && other.keyU == keyU;

  @override
  int get hashCode => Object.hash(keyD, keyU);
}

double ctrlGain(double driveDb) => fmGain(_paprDb, driveDb);

final Float64List _sin = Float64List.fromList(
    List<double>.generate(ctrlSymbol, (n) => math.sin(2.0 * math.pi * n / ctrlSymbol)));

Float64List ctrlSynth(List<Tones> rows, double driveDb) {
  final double g = 2.0 * toneAmp * ctrlGain(driveDb);
  final Float64List out = Float64List(rows.length * ctrlSymbol);
  int o = 0;
  for (final Tones t in rows) {
    for (int n = 0; n < ctrlSymbol; n++) {
      double s = 0.0;
      for (final int k in t) {
        s += _sin[(k * n) % ctrlSymbol];
      }
      out[o++] = (s * g).clamp(-1.0, 1.0);
    }
  }
  return out;
}

Float64List frameAudio(Codebook cb, int code, int lead, double driveDb) =>
    ctrlSynth(cb.frameRows(code, lead), driveDb);

/// Adaptive control-frame lead-in length.
class LeadIn {
  int len = leadRows;
  int _maxMissed = -1;
  int _reports = 0;

  void newSession() => _reports = 0;

  int report(int row) {
    final int missed = (len + row - noLeadRow).clamp(0, leadRows);
    if (missed > _maxMissed) _maxMissed = missed;
    _reports++;
    if (_reports > 4) return len;
    final int m = _maxMissed;
    int inc = 1;
    if (_reports == 1) {
      inc = asI64(roundTiesEven(m * 0.5));
      if (inc < 1) inc = 1;
    }
    len = (m + inc) < leadRows ? m + inc : leadRows;
    return len;
  }

  int get dataSymbols => dataLeadIn(len);
}

int dataLeadIn(int c) => (8 * c + 8) ~/ 9;
