/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/xara-modem/xara), crates/xara-arq/src/fm/digi.rs
Copyright (c) the XARA authors, MIT License.

FM digipeater: relays one ARQ link between a source side and a target side,
restamping the chain SNR and lead-in reports on every frame it forwards.
*/

import 'dart:collection';
import 'dart:typed_data';

import 'arq_host.dart';
import 'call.dart';
import 'fm_adapt.dart' show snrOffsetDb;
import 'fm_ctrl.dart';
import 'fm_frame.dart';
import 'fm_level.dart';
import 'fm_session.dart' show noLeadHeard;
import 'fm_timing.dart' show watchdog;
import 'fm_tx.dart' show connectLeadIn;

const int _pollCap = 99;

sealed class DigiTx {
  const DigiTx();

  String get debug;
}

class DigiTxCtrl extends DigiTx {
  final int code;
  final int lead;
  final Side side;

  const DigiTxCtrl(this.code, this.lead, this.side);

  @override
  String get debug => 'Ctrl { code: $code, lead: $lead, side: ${side.idx} }';

  @override
  bool operator ==(Object other) =>
      other is DigiTxCtrl && other.code == code && other.lead == lead && other.side == side;

  @override
  int get hashCode => Object.hash(code, lead, side);
}

class DigiTxData extends DigiTx {
  final FmRecord record;
  final Uint8List frame;
  final int lead;
  final Side side;

  const DigiTxData(this.record, this.frame, this.lead, this.side);

  @override
  String get debug => 'Data { record: ${record.index}, frame: $frame, lead: $lead, side: ${side.idx} }';
}

class CtrlListen {
  final int keyD;
  final int keyU;
  final List<int> codes;

  const CtrlListen(this.keyD, this.keyU, this.codes);
}

class DigiListen {
  final FmBandwidth bw;
  final int dataKey;
  final List<FmRecord> records;
  final List<CtrlListen> ctrl;

  const DigiListen(this.bw, this.dataKey, this.records, this.ctrl);
}

sealed class DigiOutput {
  const DigiOutput();
}

class DigiOutTx extends DigiOutput {
  final DigiTx tx;

  const DigiOutTx(this.tx);
}

class DigiOutListen extends DigiOutput {
  final DigiListen listen;

  const DigiOutListen(this.listen);
}

class DigiOutHost extends DigiOutput {
  final HostEvent event;

  const DigiOutHost(this.event);
}

class DigiOutDone extends DigiOutput {
  const DigiOutDone();
}

String _asciiUpper(String s) =>
    String.fromCharCodes(s.codeUnits.map((c) => c >= 0x61 && c <= 0x7A ? c - 0x20 : c));

int _snrIn(double snrDb, int chain) {
  final double s = snrDb + snrOffsetDb;
  return snrByte(chain != 0 ? (s < chain / 7.0 ? s : chain / 7.0) : s);
}

const List<int> _dataCodes = <int>[
  FmCode.qrt,
  FmCode.brk,
  FmCode.ackReq0,
  FmCode.ackReq1,
  FmCode.idle,
  FmCode.noTraffic,
  FmCode.relayFailed,
  FmCode.connectReplyNarrow,
  FmCode.connectReplyWide,
];

const List<int> _ackCodes = <int>[
  FmCode.ackStay,
  FmCode.nack,
  FmCode.qrt,
  FmCode.brk,
  FmCode.ackUp2,
  FmCode.ackDown,
  FmCode.ackUp1,
  FmCode.ackUp3,
  FmCode.ackUp6,
  FmCode.ackSecondOnly,
  FmCode.ackFirstOnly,
  FmCode.ackReq0,
  FmCode.ackReq1,
  FmCode.goAhead,
  FmCode.idle,
  FmCode.noTraffic,
  FmCode.relayFailed,
];

class Digi {
  String _call;
  FmBandwidth _ownBw;
  bool _active = false;
  String _path = '';
  List<(int, int)> _keys = <(int, int)>[(0, 0), (0, 0)];
  List<LeadIn> _lead = <LeadIn>[LeadIn(), LeadIn()];
  final List<int> _heard = <int>[noLeadHeard, noLeadHeard];
  Side _dataSide = Side.target;
  bool _linkUp = false;
  bool _linked = false;
  FmBandwidth _bw;
  List<FmRecord> _mask = <FmRecord>[];
  DataLevel _lastLevel = DataLevel.one;
  DataLevel _expected = DataLevel.one;
  int _nackRun = 0;
  int? _offer;
  int _polls = 0;
  int _interval = watchdog(1);
  int? _deadline;
  bool _quitting = false;
  final ListQueue<DigiOutput> _out = ListQueue<DigiOutput>();

  Digi(String call, FmBandwidth bw)
      : _call = _asciiUpper(call),
        _ownBw = bw,
        _bw = bw;

  String get call => _call;

  set call(String c) => _call = _asciiUpper(c);

  void setBandwidth(FmBandwidth bw) {
    _ownBw = bw;
    if (!_active) _bw = bw;
  }

  bool get active => _active;

  FmBandwidth get bandwidth => _bw;

  int get dataKey => key(_dataSide);

  int key(Side side) => _keys[side.idx].$1;

  int? nextDeadline() => _deadline;

  DigiOutput? pop() => _out.isEmpty ? null : _out.removeFirst();

  void _log(String s) => _out.add(DigiOutHost(HostLog(s)));

  void _restart(int now) => _deadline = now + _interval;

  bool onRecord0(int now, List<int> bytes, double snrDb) {
    if (_call.isEmpty || bytes.length != record0Len) return false;
    final Record0? r = Record0.parse(bytes);
    if (r == null || r.kind != Kind.connect) return false;
    bool eq(String a, String b) => a.isNotEmpty && _asciiUpper(a) == _asciiUpper(b);
    if (eq(r.via1, r.source) || eq(r.via2, r.source) || eq(r.via1, r.target) || eq(r.via2, r.target) ||
        eq(r.via1, r.via2)) {
      return false;
    }
    final int hop;
    if (eq(r.via1, _call) && r.hop == 0) {
      hop = 1;
    } else if (eq(r.via2, _call) && r.hop == 1) {
      hop = 2;
    } else {
      return false;
    }
    int h(String c) => callHash(c.codeUnits);
    if (hop == 1) {
      final String next = r.via2.isEmpty ? r.target : r.via2;
      _keys = <(int, int)>[(h(_call), h(r.source)), (h(next), h(r.via1))];
    } else {
      _keys = <(int, int)>[(h(_call), h(r.via1)), (h(r.target), h(r.via2))];
    }
    _interval = watchdog(hop == 1 && r.via2.isEmpty ? 1 : 2);
    final bool fresh = !_active;
    _active = true;
    _restart(now);
    if (fresh) {
      _lead = <LeadIn>[LeadIn(), LeadIn()];
      _heard[0] = noLeadHeard;
      _heard[1] = noLeadHeard;
      _linkUp = false;
      _linked = false;
      _quitting = false;
      _polls = 0;
      _lastLevel = DataLevel.one;
      _expected = DataLevel.one;
      _nackRun = 0;
      _offer = null;
      _bw = _ownBw;
      final List<String> vias = <String>[r.via1, r.via2].where((v) => v.isNotEmpty).toList();
      _path = '${r.source} <-> ${vias.join(' <-> ')} <-> ${r.target}';
      _out.add(const DigiOutHost(hostPending));
      _log('Starting Digipeater: $_path');
    }
    final Record0 fwd = r.copyWith(
      hop: hop,
      wide: _ownBw == FmBandwidth.wide && r.wide,
      chainSnr: _snrIn(snrDb, r.chainSnr),
    );
    final Uint8List f = fwd.restamp(bytes);
    _dataSide = Side.target;
    _setMask(<FmRecord>[]);
    _out.add(DigiOutTx(DigiTxData(FmRecord.connect, f, connectLeadIn, Side.target)));
    _announce();
    return true;
  }

  void onSync(int now) {
    if (_active) _restart(now);
  }

  void onData(int now, FmRecord record, bool ok, List<int> bytes, double snrDb) {
    if (!_active || _quitting || record == FmRecord.connect) return;
    _restart(now);
    final Side from = _dataSide, to = _dataSide.other;
    if (!ok) {
      _log('rec${record.index} from side ${from.idx} failed: relay failed');
      _sendCtrl(FmCode.relayFailed, to);
      return;
    }
    final Trailer? t = Trailer.read(record, bytes, true);
    if (t == null) return;
    final int? chain = t.chainSnr;
    if (chain == null) return;
    _lead[from.idx].report(t.leadReport);
    if (record == FmRecord.start) {
      _offer = t.level != 0 ? t.level : null;
    }
    final Trailer nt = Trailer(leadReport: _heard[to.idx], level: t.level, chainSnr: _snrIn(snrDb, chain));
    final Uint8List? f = nt.restamp(record, bytes);
    if (f == null) return;
    _maskAfterFrame(record);
    final int lead = _lead[to.idx].dataSymbols;
    _out.add(DigiOutTx(DigiTxData(record, f, lead, to)));
    _announce();
  }

  void onCtrl(int now, int code, int leadRow, Side side) {
    if (!_active || _quitting || !_codes(side).contains(code)) return;
    _restart(now);
    _heard[side.idx] = leadRow;
    final Side to = side.other;
    if (code == FmCode.qrt) _log(qrtReceived);
    if (FmCode.ackReq.contains(code)) {
      _polls++;
      if (_polls > _pollCap) {
        _end(true);
        return;
      }
    } else {
      _polls = 0;
    }
    if (side == Side.source && code == FmCode.goAhead) _linkUp = true;
    _maskAfterCode(code);
    if (side == Side.target && (code == FmCode.connectReplyNarrow || code == FmCode.connectReplyWide)) {
      if (!_linked) _log('Digipeating: $_path');
      _linked = true;
      _bw = code == FmCode.connectReplyWide ? FmBandwidth.wide : FmBandwidth.narrow;
    }
    _sendCtrl(code, to);
    if (code == FmCode.brk) _dataSide = side;
    if (code == FmCode.qrt) _quitting = true;
    _announce();
  }

  void onTxDone() {
    if (_quitting) _end(false);
  }

  void poll(int now) {
    final int? d = _deadline;
    if (d != null && d <= now) {
      if (_linkUp) _log('Connection timed out');
      _end(true);
    }
  }

  void abort() {
    if (_active) _end(false);
  }

  void _end(bool timeout) {
    if (_linked) _log('Digipeater is disconnected${timeout ? ' (Timeout)' : ''}');
    _active = false;
    _deadline = null;
    _quitting = false;
    _bw = _ownBw;
    _keys = <(int, int)>[(0, 0), (0, 0)];
    _out.add(const DigiOutHost(hostCancelPending));
    _out.add(const DigiOutDone());
  }

  void _sendCtrl(int code, Side side) {
    _out.add(DigiOutTx(DigiTxCtrl(code, _lead[side.idx].len, side)));
  }

  List<int> _codes(Side side) {
    if (side != _dataSide) return _ackCodes;
    if (_dataSide == Side.target) return _dataCodes;
    return _dataCodes.sublist(0, 7);
  }

  DataLevel get _top => _bw.topLevel;

  List<FmRecord> _at(int l) {
    final DataLevel d = DataLevel.clamped(l, _top);
    return d == DataLevel.one ? <FmRecord>[FmRecord.data(d), FmRecord.short] : <FmRecord>[FmRecord.data(d)];
  }

  void _maskAfterFrame(FmRecord record) {
    final DataLevel? dl = record.dataLevel;
    final DataLevel l = dl != null && dl.value <= _top.value ? dl : DataLevel.one;
    _lastLevel = l;
    _nackRun = 0;
    if (record != FmRecord.start) _offer = null;
    _setMask(_at(l.value));
  }

  void _maskAfterCode(int code) {
    final int l = _lastLevel.value;
    final List<FmRecord> m;
    switch (code) {
      case FmCode.ackStay:
        _expected = _lastLevel;
        m = _at(l);
      case FmCode.ackUp1:
        m = _at(l + 1);
      case FmCode.ackUp2:
        m = _at(l + 2);
      case FmCode.ackUp3:
        m = _at(l + 3);
      case FmCode.ackUp6:
        m = _at(l + 6);
      case FmCode.ackDown:
        m = _at(_lastLevel.down().value);
      case FmCode.goAhead:
        _expected = DataLevel.one;
        final int? o = _offer;
        m = o == null ? <FmRecord>[FmRecord.start] : _at(o);
      case FmCode.nack:
        final int e = _expected.value;
        if (e >= 2) {
          final int sub = e - (2 + _nackRun);
          final int lo = sub < 1 ? 1 : sub;
          m = <FmRecord>[for (int k = lo; k < e; k++) ..._at(k)];
        } else {
          m = _at(1);
        }
        _nackRun++;
      default:
        m = <FmRecord>[];
    }
    _setMask(m);
  }

  void _setMask(List<FmRecord> m0) {
    final List<FmRecord> m = <FmRecord>[...m0];
    if (!_linkUp) m.add(FmRecord.connect);
    final List<int> idx = m.map((r) => r.index).toSet().toList()..sort();
    _mask = <FmRecord>[for (final int i in idx) FmRecord(i)];
  }

  void _announce() {
    final List<CtrlListen> ctrl = <CtrlListen>[
      for (final Side s in Side.values) CtrlListen(_keys[s.idx].$1, _keys[s.idx].$2, List<int>.of(_codes(s))),
    ];
    _out.add(DigiOutListen(DigiListen(_bw, dataKey, List<FmRecord>.of(_mask), ctrl)));
  }
}
