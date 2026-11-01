/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
VARA FM connected-session ARQ state machine. Sans-IO: callers feed decoded
control codes/data frames and transmit-done events, and drain [Output]s.
Time is in 48 kHz samples.
*/

import 'dart:convert';
import 'dart:typed_data';

import 'arq_host.dart';
import 'arq_link.dart';
import 'arq_time.dart';
import 'call.dart';
import 'compression.dart';
import 'fm_adapt.dart';
import 'fm_ctrl.dart';
import 'fm_frame.dart';
import 'fm_level.dart';
import 'fm_timing.dart';
import 'fm_tx.dart' show connectLeadIn;
import 'textcomp.dart';

const int rxGrace = 2400;
const int _repeatLimit = 100;
const int noLeadHeard = leadRows + 1;

class FmConfig {
  FmBandwidth bw;
  HostSettings host;
  int seed;

  FmConfig(this.bw, String mycall)
      : host = HostSettings(mycall, 10),
        seed = 1;

  FmConfig._(this.bw, this.host, this.seed);

  FmConfig copy() => FmConfig._(bw, host.copy(), seed);
}

enum FmState {
  listen,
  receiving,
  awaitGo,
  calling,
  sending,
  qrt,
  idleSent,
  idle,
  fqWait;

  String get debug => name[0].toUpperCase() + name.substring(1);
}

sealed class FmTx {
  const FmTx();

  String get debug;
}

class FmTxCtrl extends FmTx {
  final int code;
  final int lead;

  const FmTxCtrl(this.code, this.lead);

  @override
  String get debug => 'Ctrl { code: $code, lead: $lead }';

  @override
  bool operator ==(Object other) => other is FmTxCtrl && other.code == code && other.lead == lead;

  @override
  int get hashCode => Object.hash(code, lead);
}

class FmTxData extends FmTx {
  final FmRecord record;
  final List<Uint8List> frames;
  final int lead;

  const FmTxData(this.record, this.frames, this.lead);

  @override
  String get debug => 'Data { record: ${record.index}, frames: $frames, lead: $lead }';
}

class FmListen {
  final FmBandwidth bw;
  final int key;
  final (int, int)? ctrl;
  final List<int> codes;
  final List<FmRecord> records;
  final int nframes;
  final bool linked;

  const FmListen(this.bw, this.key, this.ctrl, this.codes, this.records, this.nframes, this.linked);

  String get debug => 'Listen { bw: ${fmBwDebug(bw)}, key: $key, '
      'ctrl: ${ctrl == null ? 'None' : 'Some((${ctrl!.$1}, ${ctrl!.$2}))'}, '
      'codes: [${codes.join(', ')}], records: [${records.map((r) => r.index).join(', ')}], '
      'nframes: $nframes, linked: $linked }';
}

typedef FmOutput = Output<FmTx, FmListen>;

/// Rust Debug rendering of an [FmOutput].
String fmOutputDebug(FmOutput o) => switch (o) {
      OutTx<FmTx, FmListen>(:final FmTx tx) => 'Tx(${tx.debug})',
      OutListen<FmTx, FmListen>(:final FmListen listen) => 'Listen(${listen.debug})',
      OutHost<FmTx, FmListen>(:final HostEvent event) => 'Host(${event.debug})',
    };

class CtrlIn {
  final int code;
  final int leadRow;
  final int tEnd;

  const CtrlIn(this.code, this.leadRow, this.tEnd);
}

class FrameIn {
  final bool ok;
  final Uint8List bytes;
  final double snrDb;

  const FrameIn(this.ok, this.bytes, this.snrDb);
}

class DataIn {
  final FmRecord record;
  final List<FrameIn> frames;
  final int tEnd;

  const DataIn(this.record, this.frames, this.tEnd);
}

enum _LastKind { none, ctrl, req, data }

class _TxBuf {
  final List<int> buf = <int>[];
  final List<int> inflight = <int>[];
  final List<int> states = <int>[];
  int state = 0;
  bool? textTurn;
  int lastHint = 0;

  List<int> take(List<bool> keep) {
    final List<int> taken = List<int>.of(inflight);
    inflight.clear();
    final List<int> left = <int>[];
    int pos = 0;
    for (int i = 0; i < taken.length; i++) {
      final int n = taken[i];
      if (i < keep.length && keep[i]) {
        final int end = pos + n < buf.length ? pos + n : buf.length;
        buf.removeRange(pos, end);
        if (n > 0) left.add(buf.length);
        if (i < states.length) state = states[i];
      } else {
        pos += n;
      }
    }
    states.clear();
    return left;
  }
}

const List<int> _ackReq = FmCode.ackReq;

class FmSession {
  final Core<FmTx, FmListen> _core;
  late FmConfig _cfg;
  late FmBandwidth _bw;
  late FmState _state;
  late String _caller;
  late String _answerer;
  late String _mycall;
  late List<String> _vias;
  late int _keyD;
  late int _keyU;
  late bool _connected;
  late bool _registered;
  late bool _firstTurn;

  late FmRecord _level;
  late FmRecord _prevLevel;
  DataLevel? _offerRx;
  DataLevel? _offerTx;
  late int _stays;
  DataLevel? _stayLevel;
  late bool _two;
  late Adaptation _adapt;
  late int _nackRun;

  late bool _alt;
  int? _lastCode;
  late _LastKind _lastKind;
  late FmRecord _lastRecord;
  late LeadIn _lead;
  late int _heardRow;
  late int _attempts;
  late int _repeats;

  late Timing _timing;
  int? _window;

  late int _qrtLeft;

  late _TxBuf _tx;
  late ArqLink _link;
  late int _lastHeld;
  late bool _dataStored;

  FmSession(FmConfig cfg) : _core = Core<FmTx, FmListen>(cfg.seed) {
    _reset(cfg);
    _announce();
  }

  void _reset(FmConfig cfg) {
    _cfg = cfg;
    _mycall = cfg.host.primaryCall;
    _bw = cfg.bw;
    _state = FmState.listen;
    _caller = '';
    _answerer = '';
    _vias = <String>[];
    _keyD = 0;
    _keyU = 0;
    _connected = false;
    _registered = cfg.host.registered;
    _level = FmRecord.start;
    _prevLevel = FmRecord.start;
    _offerRx = null;
    _offerTx = null;
    _alt = false;
    _stays = 0;
    _stayLevel = null;
    _two = false;
    _adapt = Adaptation();
    _timing = Timing(_bw, 0);
    _lead = LeadIn();
    _heardRow = noLeadHeard;
    _tx = _TxBuf();
    _lastCode = null;
    _lastKind = _LastKind.none;
    _lastRecord = FmRecord.connect;
    _window = null;
    _attempts = 0;
    _qrtLeft = 0;
    _nackRun = 0;
    _repeats = 0;
    _firstTurn = false;
    _dataStored = false;
    _lastHeld = 0;
    _link = ArqLink();
  }

  FmState get state => _state;
  FmRecord get level => _level;
  String get peer => _caller == _mycall ? _answerer : _caller;
  int get attempts => _attempts;
  FmBandwidth get bandwidth => _bw;
  FmConfig get config => _cfg;
  int get key => _keyD;

  /// Upstream key (caller hash); connect replies are coded with it.
  int get keyU => _keyU;
  String get caller => _caller;
  String get answerer => _answerer;
  int get viaCount => _vias.length;
  bool get hasVias => _vias.isNotEmpty;
  int get buffered => _tx.buf.length + _link.files.length;

  FmOutput? pop() => _core.pop();

  int? nextDeadline() => _core.nextDeadline(_link);

  int _ackReqCode() => _alt ? FmCode.ackReq1 : FmCode.ackReq0;

  DataLevel get _top => maxLevel(_bw, _registered);

  List<int> _codes() => switch (_state) {
        FmState.listen || FmState.qrt => const <int>[],
        FmState.calling => const <int>[FmCode.qrt, FmCode.connectReplyNarrow, FmCode.connectReplyWide],
        FmState.receiving when _dataStored => const <int>[
            FmCode.qrt, FmCode.brk, FmCode.ackReq0, FmCode.ackReq1, FmCode.idle, FmCode.relayFailed,
          ],
        FmState.receiving => const <int>[
            FmCode.qrt, FmCode.brk, FmCode.ackReq0, FmCode.ackReq1, FmCode.idle, FmCode.relayFailed,
            FmCode.connectReplyNarrow, FmCode.connectReplyWide,
          ],
        FmState.awaitGo => const <int>[FmCode.qrt, FmCode.ackReq0, FmCode.ackReq1, FmCode.goAhead, FmCode.idle],
        FmState.sending => const <int>[
            FmCode.ackStay, FmCode.nack, FmCode.qrt, FmCode.brk, FmCode.ackUp2, FmCode.ackDown, FmCode.ackUp1,
            FmCode.ackUp3, FmCode.ackUp6, FmCode.ackSecondOnly, FmCode.ackFirstOnly, FmCode.idle,
          ],
        FmState.idleSent => const <int>[FmCode.qrt, FmCode.brk, FmCode.ackReq0, FmCode.ackReq1, FmCode.noTraffic],
        FmState.idle => const <int>[FmCode.qrt, FmCode.brk, FmCode.idle],
        FmState.fqWait => const <int>[FmCode.qrt, FmCode.ackReq0, FmCode.ackReq1],
      };

  List<FmRecord> _records() {
    switch (_state) {
      case FmState.listen:
        return const <FmRecord>[FmRecord.connect];
      case FmState.awaitGo when _firstTurn:
        return const <FmRecord>[FmRecord.connect];
      case FmState.receiving:
        final Set<int> v = <int>{};
        for (final FmRecord r in <FmRecord>[FmRecord.start, FmRecord.short, _level, _prevLevel, const FmRecord(1)]) {
          final DataLevel? dl = r.dataLevel;
          if (r == FmRecord.start || r == FmRecord.short || (dl != null && dl.value <= _top.value)) v.add(r.index);
        }
        return (v.toList()..sort()).map(FmRecord.new).toList();
      default:
        return const <FmRecord>[];
    }
  }

  void _announce() {
    final bool listening = _state == FmState.listen;
    _core.out.add(OutListen<FmTx, FmListen>(FmListen(
      _bw,
      listening ? 0 : _keyD,
      listening ? null : (_keyD, _keyU),
      List<int>.of(_codes()),
      _records(),
      _state == FmState.receiving ? _nframes : 1,
      _connected,
    )));
  }

  void _enter(FmState s) {
    if (s != _state) {
      _alt = false;
      _stays = 0;
      _two = false;
      if (s == FmState.sending) {
        _tx.textTurn = null;
        _tx.state = startState;
      }
      if (s == FmState.receiving) {
        _link.rx.turnCompressed = null;
        final DataLevel? o = _offerTx;
        _offerTx = null;
        final FmRecord start = o == null ? FmRecord.start : FmRecord.data(o);
        _level = start;
        _prevLevel = start;
      }
      _state = s;
    }
    _announce();
  }

  void _setState(FmState s) {
    _state = s;
    _announce();
  }

  void _listen() {
    _reset(_cfg);
    _announce();
  }

  void _close() {
    if (_connected || _state == FmState.calling) _core.host(hostDisconnected);
    _core.host(hostCancelPending);
    _listen();
  }

  void _feedWatchdog(int now) => _link.watchdog = now + watchdog(_vias.length);

  void _sendCtrl(int code) {
    final bool req = _ackReq.contains(code);
    if (!req) _lastCode = code;
    _lastKind = req ? _LastKind.req : _LastKind.ctrl;
    _core.transmitting = true;
    _link.deadline = null;
    _window = null;
    _link.idleTimer = null;
    _core.out.add(OutTx<FmTx, FmListen>(FmTxCtrl(code, _lead.len)));
  }

  void _say(int code, FmState next) {
    _sendCtrl(code);
    _enter(next);
  }

  void _resendLast() {
    _repeats++;
    if (_lastCode != null) _sendCtrl(_lastCode!);
  }

  bool get _wantsQrt => _link.wantsQrt(_tx.buf.length);

  void _qrt() {
    _qrtLeft = _vias.isEmpty && _connected ? 1 : 0;
    _sendCtrl(FmCode.qrt);
    _setState(FmState.qrt);
  }

  bool connect(int now, String? mycall, String remote, List<String> vias) {
    if (_state != FmState.listen || vias.length > 2) return false;
    _mycall = mycall ?? _cfg.host.primaryCall;
    _caller = _mycall;
    _answerer = remote;
    _vias = List<String>.of(vias);
    final String d = _vias.isEmpty ? remote : _vias.first;
    _keyD = callHash(utf8.encode(d));
    _keyU = callHash(utf8.encode(_mycall));
    _timing = Timing(_bw, _vias.length);
    _link.comp = _cfg.host.registered ? _cfg.host.compression : Compression.off;
    _lead.newSession();
    _attempts = 0;
    _setState(FmState.calling);
    _feedWatchdog(now);
    _sendConnect();
    return true;
  }

  void _sendConnect() {
    _attempts++;
    String via(int i) => i < _vias.length ? _vias[i] : '';
    final bool wide = _cfg.bw == FmBandwidth.wide;
    final Record0 r = Record0.connect(_caller, _answerer, via(0), via(1), _cfg.host.registered, wide)
        .copyWith(compression: _link.comp.bits);
    final Uint8List? bytes = r.toBytes();
    if (bytes == null) {
      _core.host(hostDisconnected);
      _listen();
      return;
    }
    _core.host(hostUnencrypted);
    _lastKind = _LastKind.data;
    _lastRecord = FmRecord.connect;
    _core.transmitting = true;
    _link.deadline = null;
    _window = null;
    _core.out.add(OutTx<FmTx, FmListen>(FmTxData(FmRecord.connect, <Uint8List>[bytes], connectLeadIn)));
  }

  void send(int now, List<int> data) {
    _link.queue(now, _connected, data, _tx.buf);
    _idleWake(now);
  }

  void _idleWake(int now) {
    if (_state == FmState.idle && !_core.transmitting && _link.deadline == null && buffered > 0) {
      _link.deadline = _max(now, _core.txEnd + idleDataWait * tick);
    }
  }

  static int _max(int a, int b) => a > b ? a : b;

  void disconnect(int now) {
    if (buffered > 0 && _connected) {
      _link.discAfterTx = true;
    } else {
      abort(now);
    }
    _discWake(now);
  }

  void abort(int now) {
    if (_state == FmState.listen || _state == FmState.qrt) return;
    _link.discNow = true;
    _discWake(now);
  }

  void _discWake(int now) {
    if (_core.transmitting || !_wantsQrt) return;
    if (_state == FmState.idle) {
      _link.deadline = _max(now, _core.txEnd + idleDataWait * tick);
    } else if (_state == FmState.receiving) {
      _link.deadline = _max(now, _syncEnd());
    }
  }

  int _syncEnd() {
    final (double _, double hi) = receiverSyncWindow(_bw, _level, _vias.length, _two);
    return _core.txEnd + hi.truncate() * tick;
  }

  void dropLink() {
    if (_state == FmState.listen || _state == FmState.qrt) return;
    _link.discNow = true;
    if (!_core.transmitting) _close();
  }

  void onTxDone(int now) {
    _core.transmitting = false;
    _core.txEnd = now;
    final int vias = _vias.length;
    int? w;
    switch (_state) {
      case FmState.calling:
        w = callerConnectWindow(_bw, vias, false);
      case FmState.sending:
        w = _lastKind == _LastKind.data ? _timing.dataWindow(_lastRecord) : _timing.ctrlWindow();
      case FmState.idleSent:
        w = _timing.ctrlWindow();
      case FmState.fqWait:
        w = fqWaitReplies * _timing.ctrlWindow();
      case FmState.awaitGo:
        w = state2Backoff(vias, _core.rng.upto(2) + 1);
      case FmState.receiving when _wantsQrt:
        w = (_syncEnd() - now) ~/ tick;
      case FmState.idle when _wantsQrt || buffered > 0:
        w = idleDataWait;
      case FmState.qrt:
        if (_qrtLeft > 0) {
          _qrtLeft--;
          _sendCtrl(FmCode.qrt);
        } else {
          _close();
        }
      default:
        break;
    }
    _window = w;
    _link.deadline = w == null ? null : now + w * tick + rxGrace;
  }

  void poll(int now) {
    if (_core.transmitting) return;
    if (_link.watchdogFired(now)) {
      _core.host(hostTimedOut);
      _close();
      return;
    }
    if (_link.files.due(now)) {
      _link.files.flush(_tx.buf);
      _idleWake(now);
    }
    final int? ticks = _link.idleFired(now);
    if (ticks != null) {
      if (!_cfg.host.chat && ticks >= idlePollLimit) {
        _core.host(const HostLog('stopped sending due to CMS failure'));
        _qrt();
      } else {
        _say(FmCode.idle, FmState.idleSent);
      }
      return;
    }
    if (!_link.deadlineFired(now)) return;
    _window = null;
    if (_repeats >= _repeatLimit) {
      _core.host(hostTimedOut);
      _close();
      return;
    }
    switch (_state) {
      case FmState.calling:
        if (_link.discNow) {
          _close();
        } else if (_attempts < _cfg.host.retries) {
          _sendConnect();
        } else {
          _core.host(hostUnableToConnect);
          _close();
        }
      case FmState.sending:
        if (_wantsQrt) {
          _link.discTimeouts++;
          _core.host(HostLog('disconnecting ${_link.discTimeouts}/$discTimeoutLimit'));
          if (_link.discTimeouts >= discTimeoutLimit) {
            _qrt();
            return;
          }
        }
        _repeats++;
        _timing.miss();
        _sendCtrl(_ackReqCode());
      case FmState.idleSent:
      case FmState.awaitGo:
        _timing.miss();
        _resendLast();
      case FmState.fqWait:
        _core.host(hostDisconnected);
        _core.host(hostCancelPending);
        _listen();
      case FmState.receiving when _wantsQrt:
        _qrt();
      case FmState.idle when _wantsQrt || buffered > 0:
        _say(FmCode.brk, FmState.awaitGo);
      default:
        break;
    }
  }

  int _codeTicks(int tEnd) {
    final int d = tEnd - _core.txEnd;
    return (d - d % tick) ~/ tick + detectHold;
  }

  /// How [onCtrl] treats a detected [code] ending at [tEnd]: the delay in
  /// ticks since our transmission ended, the reply window, and the verdict
  /// (`accepted`, `late`, `early`, `transmitting` or `unexpected`).
  ({int ticks, int? window, String verdict}) ctrlCheck(int code, int tEnd) {
    final int ticks = _codeTicks(tEnd);
    final String verdict = _core.transmitting
        ? 'transmitting'
        : !_codes().contains(code)
            ? 'unexpected'
            : ticks < codeGate
                ? 'early'
                : (_window != null && ticks > _window!)
                    ? 'late'
                    : 'accepted';
    return (ticks: ticks, window: _window, verdict: verdict);
  }

  void onCtrl(int now, CtrlIn c) {
    if (_core.transmitting || !_codes().contains(c.code)) return;
    final int ticks = _codeTicks(c.tEnd);
    if (ticks < codeGate || (_window != null && ticks > _window!)) return;
    if (_state != FmState.calling) _feedWatchdog(now);
    _heardRow = c.leadRow;
    if (_lastKind == _LastKind.data && !(c.code == FmCode.nack && _vias.isNotEmpty)) {
      _timing.ack(ticks, _lastRecord);
    } else if (_lastKind == _LastKind.ctrl &&
        !(_state == FmState.sending && (c.code == FmCode.brk || c.code == FmCode.goAhead))) {
      _timing.ctrl(ticks);
    }
    if (c.code == FmCode.qrt) {
      _core.host(const HostLog(qrtReceived));
      _close();
      return;
    }
    switch (_state) {
      case FmState.calling:
        _onConnectReply(now, c.code);
      case FmState.receiving:
        _ctrlReceiving(c.code);
      case FmState.awaitGo:
        _ctrlAwaitGo(c.code);
      case FmState.sending:
        _ctrlSending(c.code);
      case FmState.idleSent:
        if (c.code == FmCode.noTraffic && _wantsQrt) {
          _qrt();
        } else if (c.code == FmCode.noTraffic && buffered == 0) {
          _repeats = 0;
          _enter(FmState.idle);
          _link.idleTimer = now + idlePoll;
        } else if (c.code == FmCode.noTraffic) {
          _say(FmCode.brk, FmState.awaitGo);
        } else if (c.code == FmCode.brk) {
          _grant();
        } else {
          _resendLast();
        }
      case FmState.idle:
        if (c.code == FmCode.idle) {
          _answerPoll();
        } else if (c.code == FmCode.brk) {
          _grant();
        }
      case FmState.fqWait:
        _resendLast();
      case FmState.listen:
      case FmState.qrt:
        break;
    }
  }

  void _grant() {
    _repeats = 0;
    _say(FmCode.goAhead, FmState.receiving);
  }

  void _answerPoll() {
    _repeats = 0;
    if (_wantsQrt || buffered > 0) {
      _say(FmCode.brk, FmState.awaitGo);
    } else {
      _say(FmCode.noTraffic, FmState.idle);
    }
  }

  void _onConnectReply(int now, int code) {
    if (code != FmCode.connectReplyNarrow && code != FmCode.connectReplyWide) return;
    _bw = code == FmCode.connectReplyWide ? FmBandwidth.wide : FmBandwidth.narrow;
    if (_bw != _cfg.bw) {
      final Timing t = _timing;
      _timing = Timing(_bw, _vias.length);
      _timing.ack(t.mean[FmRecord.connect.index], FmRecord.connect);
    }
    _lead.newSession();
    _connected = true;
    _link.startFiles(_tx.buf);
    _feedWatchdog(now);
    _core.host(hostPending);
    _core.host(HostConnected(_caller, _answerer, List<String>.of(_vias), LinkBwFm(_bw)));
    if (_link.discNow) {
      _qrt();
      return;
    }
    _grant();
  }

  static String _asciiLower(String s) =>
      String.fromCharCodes(s.codeUnits.map((c) => c >= 0x41 && c <= 0x5A ? c + 0x20 : c));

  void onRecord0(int now, List<int> bytes, double snrDb) {
    final Record0? r = Record0.parse(bytes);
    if (r == null || r.kind != Kind.connect || r.hop != r.vias) return;
    String? me;
    for (final String c in _cfg.host.mycalls) {
      if (_asciiLower(c) == _asciiLower(r.target)) {
        me = c;
        break;
      }
    }
    if (me == null) return;
    if (_state == FmState.awaitGo && _firstTurn && r.source == _caller) {
      _feedWatchdog(now);
      _resendLast();
      return;
    }
    if (_state != FmState.listen) return;
    _mycall = me;
    _caller = r.source;
    _answerer = me;
    _vias = <String>[r.via1, r.via2].where((v) => v.isNotEmpty).toList();
    final String up = _vias.isEmpty ? r.source : _vias.last;
    _keyD = callHash(utf8.encode(me));
    _keyU = callHash(utf8.encode(up));
    _registered = r.registered;
    _link.comp = Compression.fromBits(r.compression);
    _lead.newSession();
    _feedWatchdog(now);
    _core.host(hostUnencrypted);
    _core.host(HostSn(_vias.isEmpty ? snrDb + snrOffsetDb : r.chainSnr / 7.0));
    _core.host(hostPending);
    if (_vias.isNotEmpty && !r.registered) {
      _timing = Timing(_cfg.bw, _vias.length);
      _qrt();
      return;
    }
    _bw = r.wide && _cfg.bw == FmBandwidth.wide ? FmBandwidth.wide : FmBandwidth.narrow;
    _timing = Timing(_bw, _vias.length);
    _connected = true;
    _firstTurn = true;
    _link.startFiles(_tx.buf);
    _core.host(HostConnected(_caller, _answerer, List<String>.of(_vias), LinkBwFm(_bw)));
    _core.host(HostRegistered(_registered));
    _say(_bw == FmBandwidth.wide ? FmCode.connectReplyWide : FmCode.connectReplyNarrow, FmState.awaitGo);
  }

  void _ctrlAwaitGo(int code) {
    if (code == FmCode.goAhead) {
      _repeats = 0;
      if (_wantsQrt) {
        _qrt();
        return;
      }
      if (_firstTurn) {
        _firstTurn = false;
        _startTurn();
        return;
      }
      final int q = buffered;
      if (q == 0) {
        _link.idleTicks = 0;
        _say(FmCode.idle, FmState.idleSent);
      } else if (_offerRx != null &&
          q <= payload(_bw, FmRecord.data(_offerRx!), _vias.isNotEmpty) &&
          q != _lastHeld) {
        _lastHeld = q;
        _sendCtrl(FmCode.brk);
        _announce();
      } else {
        _startTurn();
      }
    } else if (code == FmCode.idle) {
      _answerPoll();
    } else {
      _resendLast();
    }
  }

  void _startTurn() {
    _link.files.flush(_tx.buf);
    final DataLevel? start = _offerRx;
    _offerRx = null;
    _enter(FmState.sending);
    _level = start == null
        ? FmRecord.start
        : FmRecord.data(start.value < _top.value ? start : _top);
    _prevLevel = _level;
    _offerTx = _link.b2f.fs ? recommendLevel(_bw, _adapt, _registered) : null;
    _transmit();
  }

  void _transmit() {
    final FmBandwidth bw = _bw;
    final FmRecord rec = _level;
    final bool vias = _vias.isNotEmpty;
    final int flen = bw.level(rec).frameBytes;
    final int p = payload(bw, rec, vias);
    final bool text = _link.text;
    final int nf = _nframes;
    final int levelByte = rec == FmRecord.start && _offerTx != null ? _offerTx!.value : 0;
    _tx.inflight.clear();
    _tx.states.clear();
    int state = _tx.state > startState ? _tx.state : startState;
    int pos = 0;
    final List<Uint8List> frames = <Uint8List>[];
    for (int i = 0; i < nf; i++) {
      final List<int> q = _tx.buf.sublist(pos);
      final int rest = q.length;
      bool squeeze = false;
      if (text && nf == 1 && rest > p) {
        squeeze = _tx.textTurn ??= turnCompresses(q);
      }
      List<int> data;
      int take;
      if (squeeze) {
        final Encoded e = fillFrame(q, p, state);
        state = e.endState;
        data = e.bytes;
        take = e.consumed;
      } else {
        take = rest < p ? rest : p;
        data = q.sublist(0, take);
      }
      final List<int> after = q.sublist(take);
      final bool last = after.isEmpty && (nf == 1 || i == 1);
      final int hint = levelByte != 0
          ? hintMax
          : _tx.textTurn == true
              ? queueHintText(bw, rec, after, state, vias)
              : queueHint(bw, rec, after.length, vias);
      final Trailer trailer = Trailer(leadReport: _heardRow, level: levelByte, chainSnr: vias ? 0 : null);
      frames.add(buildData(rec, flen, data, squeeze, hint, last, trailer));
      _tx.inflight.add(take);
      _tx.states.add(state);
      _tx.lastHint = hint;
      pos += take;
    }
    if (rec != FmRecord.start) _offerTx = null;
    _lastKind = _LastKind.data;
    _lastRecord = rec;
    _core.transmitting = true;
    _link.deadline = null;
    _window = null;
    _core.out.add(OutTx<FmTx, FmListen>(FmTxData(rec, frames, _lead.dataSymbols)));
  }

  bool get _compressedTurn =>
      _state == FmState.sending ? _tx.textTurn == true : _link.rx.turnCompressed == true;

  void _countFrame(FmRecord record) {
    final DataLevel l = asLevel(record);
    if (_compressedTurn) {
      _stays = 0;
    } else if (_stayLevel == null || l.value > _stayLevel!.value) {
      _stays = 1;
    } else {
      _stays++;
    }
    _stayLevel = l;
  }

  int get _nframes => _two ? 2 : 1;

  void _updateTwo() => _two = _vias.isEmpty && _stays > 1 && !_compressedTurn;

  void _accept(List<bool> keep) {
    final FmRecord rec = _level;
    final int n = _tx.inflight.length;
    for (int i = 0; i < n; i++) {
      if (i < keep.length && keep[i]) {
        _countFrame(rec);
      } else {
        _stays = 0;
      }
    }
    for (final int left in _tx.take(keep)) {
      _core.host(HostBuffer(left + _link.files.length));
    }
  }

  void _ctrlSending(int code) {
    _alt = !_alt;
    _repeats = 0;
    final FmRecord was = _level;
    switch (code) {
      case FmCode.ackStay:
      case FmCode.ackUp2:
      case FmCode.ackDown:
      case FmCode.ackUp1:
      case FmCode.ackUp3:
      case FmCode.ackUp6:
        _accept(const <bool>[true, true]);
      case FmCode.ackSecondOnly:
        _accept(const <bool>[false, true]);
      case FmCode.ackFirstOnly:
        _accept(const <bool>[true, false]);
      case FmCode.nack:
        _accept(const <bool>[]);
      case FmCode.brk:
      case FmCode.idle:
        _accept(const <bool>[true, true]);
        _link.turnQuit(_tx.buf);
        if (_wantsQrt) {
          _qrt();
        } else if (code == FmCode.brk) {
          _grant();
        } else {
          _answerPoll();
        }
        return;
      default:
        return;
    }
    if (code == FmCode.nack && asLevel(was) == DataLevel.one) {
      _nackRun++;
    } else {
      _nackRun = 0;
    }
    final int h = _tx.lastHint;
    if (code == FmCode.ackUp2 ||
        code == FmCode.ackUp1 ||
        code == FmCode.ackUp3 ||
        code == FmCode.ackUp6 ||
        code == FmCode.ackFirstOnly ||
        (code == FmCode.ackDown && h == 0) ||
        (code == FmCode.ackStay && h == 2)) {
      _stays = 0;
    }
    _prevLevel = was;
    final FmRecord next = senderLevelAfter(was, code);
    final DataLevel top = _bw.topLevel;
    if (next == FmRecord.short || next == FmRecord.start) {
      _level = next;
    } else if (next.dataLevel != null) {
      _level = FmRecord.data(next.dataLevel!.value < top.value ? next.dataLevel! : top);
    } else {
      _level = FmRecord.data(top);
    }
    _updateTwo();
    if (_nackRun >= 4) {
      _core.host(const HostLog('disconnecting due to poor conditions'));
      _qrt();
    } else if (_wantsQrt) {
      _qrt();
    } else {
      _transmit();
    }
  }

  void _ctrlReceiving(int code) {
    final bool reqOrRelay = code == FmCode.ackReq0 || code == FmCode.ackReq1 || code == FmCode.relayFailed;
    if (reqOrRelay && (code == _ackReqCode() || code == FmCode.relayFailed)) {
      _alt = !_alt;
      final int n = code == FmCode.relayFailed ? 1 : _nframes;
      for (int i = 0; i < n; i++) {
        _adapt.frameLost();
      }
      _stays = 0;
      _two = false;
      _prevLevel = _level;
      _level = FmRecord.data(stepDown(_level));
      _sendCtrl(FmCode.nack);
      _announce();
    } else if (code == FmCode.ackReq0 || code == FmCode.ackReq1) {
      _resendLast();
    } else if (code == FmCode.brk || code == FmCode.connectReplyNarrow || code == FmCode.connectReplyWide) {
      _sendCtrl(FmCode.goAhead);
    } else if (code == FmCode.idle) {
      _answerPoll();
    }
  }

  void onData(int now, DataIn d) {
    if (_core.transmitting || d.frames.isEmpty || d.tEnd < _core.txEnd) return;
    if (d.record == FmRecord.connect) {
      for (final FrameIn f in d.frames) {
        if (f.ok) {
          onRecord0(now, f.bytes, f.snrDb);
          break;
        }
      }
      return;
    }
    if (_state != FmState.receiving || !_records().contains(d.record)) return;
    _feedWatchdog(now);
    if (_wantsQrt) {
      _qrt();
      return;
    }
    _receive(d);
  }

  void _receive(DataIn d) {
    final FmRecord rec = d.record;
    final bool vias = _vias.isNotEmpty;
    final bool two = d.frames.length == 2;
    final List<DataFrame?> parsed = _parseFrames(d);
    if (parsed.isNotEmpty && parsed.first != null) {
      _link.rx.turnCompressed ??= parsed.first!.control.compressed;
    }
    final List<bool> ok = parsed.map((p) => p != null).toList();
    _dataStored = true;
    _alt = !_alt;
    _repeats = 0;
    final int lastok = ok.lastIndexOf(true);
    final double? held = _rxStats(d, parsed, lastok);
    final int skip = payload(_bw, rec, vias);
    for (int i = 0; i < parsed.length; i++) {
      final DataFrame? p = parsed[i];
      if (p != null) _core.deliver(_link, p.data, i == 1 && !ok[0] ? skip : 0);
    }
    if (lastok < 0 || held == null) {
      _stepBack(rec, FmCode.nack);
      return;
    }
    final DataFrame lastf = parsed[lastok]!;
    if ((two && ok[0] && !ok[1]) || (!two && _two && ok[0])) {
      if (!two) {
        _adapt.frameLost();
        _stays = 0;
      }
      _stepBack(rec, FmCode.ackFirstOnly);
      return;
    }
    if (lastf.control.last && ok.every((o) => o)) {
      final bool fq = !two &&
          !lastf.control.full &&
          lastf.data.length == 3 &&
          lastf.data[0] == 0x46 &&
          lastf.data[1] == 0x51 &&
          lastf.data[2] == 0x0D;
      _endTurn(rec, lastf.trailer.level, fq);
      return;
    }
    final Decision dec = decide(_bw, _adapt, Heard(rec, lastf.control.hint, ok[0]), held, _registered);
    if (dec.stayReset) _stays = 0;
    _prevLevel = rec;
    _level = dec.level;
    _updateTwo();
    _sendCtrl(dec.code);
    _announce();
  }

  List<DataFrame?> _parseFrames(DataIn d) {
    final bool vias = _vias.isNotEmpty;
    return <DataFrame?>[
      for (int i = 0; i < d.frames.length; i++)
        () {
          final FrameIn f = d.frames[i];
          if (!f.ok) return null;
          final DataFrame? p = parseData(d.record, f.bytes, vias);
          if (p == null) return null;
          final Uint8List? data = _link.inflate(i == 1, p.control.compressed, p.data);
          return data == null ? null : DataFrame(data, p.control, p.trailer);
        }(),
    ];
  }

  double? _rxStats(DataIn d, List<DataFrame?> parsed, int lastok) {
    final FmRecord rec = d.record;
    final int n = _bw.topLevel.value;
    double? held;
    for (int i = 0; i < parsed.length; i++) {
      final DataFrame? p = parsed[i];
      if (p != null) {
        _lead.report(p.trailer.leadReport);
        final double snr = d.frames[i].snrDb + snrOffsetDb;
        held = _adapt.frameOk(snr, asLevel(rec), n);
        _countFrame(rec);
        if (i == lastok) _core.host(HostSn(snr));
        _core.host(HostRxFrame(rec));
      } else {
        _adapt.frameLost();
        _stays = 0;
      }
    }
    return held;
  }

  void _stepBack(FmRecord rec, int code) {
    _prevLevel = rec;
    _level = FmRecord.data(stepDown(rec));
    _two = false;
    _sendCtrl(code);
    _announce();
  }

  void _endTurn(FmRecord rec, int offer, bool fq) {
    if (rec == FmRecord.start) {
      _offerRx = DataLevel.of(offer < _top.value ? offer : _top.value);
    }
    if (_wantsQrt) {
      _qrt();
      return;
    }
    final int code = _cfg.host.chat && buffered == 0 ? FmCode.idle : FmCode.brk;
    _level = rec;
    if (code == FmCode.idle) _link.idleTicks = 0;
    _say(code, code == FmCode.brk ? (fq ? FmState.fqWait : FmState.awaitGo) : FmState.idleSent);
  }
}
