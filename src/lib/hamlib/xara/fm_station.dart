/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/xara-modem/xara), crates/xara/src/station/fm.rs
and the shared `Modem` behaviour in station/mod.rs. Copyright (c) the XARA authors, MIT License.

FM station: joins the FM receiver, ARQ session, digipeater, unconnected
broadcasts and modulator into one block-driven 48 kHz audio processor.
*/

import 'dart:typed_data';

import 'arq_host.dart';
import 'ax25.dart' as ax25;
import 'busy.dart';
import 'dsp.dart';
import 'fm_adapt.dart' as adapt;
import 'fm_broadcast.dart' as broadcast;
import 'fm_ctrl.dart';
import 'fm_digi.dart';
import 'fm_frame.dart';
import 'fm_level.dart';
import 'fm_rx.dart';
import 'fm_rx_frontend.dart' show fs6, to48;
import 'fm_session.dart';
import 'fm_tx.dart';
import 'kiss.dart' as kc;
import 'kiss_command.dart';
import 'numeric.dart';
import 'ofdm_const.dart' as ofdm;
import 'receiver_common.dart';
import 'station.dart';
import 'xorshift.dart';

const int _silentTail = 45 * 1152;
const int _waveoutQueue = 200 * 256;
const int dataOverhang = _silentTail - _waveoutQueue;
// 0x9E3779B97F4A7C15, built from 32-bit halves because dart2js rejects
// 64-bit integer literals.
final int _seedMix = (0x9E3779B9 << 32) | 0x7F4A7C15;
const int fragmentGap = 480;

ReportBitrate _bitrate(FmBandwidth bw, FmRecord record, bool tx) =>
    ReportBitrate(record.dataLevel?.value ?? 1, roundTiesEven(bw.level(record).netBps).toInt(), tx);

List<double> _quantised(List<double> x) {
  for (int i = 0; i < x.length; i++) {
    x[i] = quantise(x[i]);
  }
  return x;
}

String _levelNote(FmRecord record, List<int> frame, bool vias) {
  final DataFrame? d = parseData(record, frame, vias);
  return d != null && record == FmRecord.start && d.trailer.level != 0 ? ' lvl ${d.trailer.level}' : '';
}

DataIn _dataIn(FmTransmission t, int tEnd) => DataIn(
      t.record,
      <FrameIn>[
        for (final FmFrameRx f in t.frames) FrameIn(f.ok && !f.missing, f.ok ? f.bytes : Uint8List(0), f.snrDb),
      ],
      tEnd,
    );

(double, double) passband(FmBandwidth bw) {
  final List<FmLayout> r = bw.layouts;
  int lo = 0, hi = 0;
  for (int i = 0; i < r.length; i++) {
    final int a = r[i].first, b = r[i].first + r[i].step * (r[i].nc - 1);
    if (i == 0 || a < lo) lo = a;
    if (i == 0 || b > hi) hi = b;
  }
  const double df = ofdm.fs / ofdm.nfft;
  return ((lo - 0.5) * df, (hi + 0.5) * df);
}

/// A session frame or control code sent or received, recorded for packet capture.
class StationFrame {
  final bool tx;

  /// FM record index, or -1 for a control code.
  final int record;

  /// Control code, or -1 for a data/connect record.
  final int code;

  /// False when the frame failed its CRC or was missing.
  final bool ok;
  final Uint8List bytes;

  /// Debug details: bandwidth, frame i/n, lead-in, RX quality, session state.
  final Map<String, Object?> meta;

  const StationFrame({
    required this.tx,
    this.record = -1,
    this.code = -1,
    this.ok = true,
    required this.bytes,
    this.meta = const <String, Object?>{},
  });
}

class FmStation {
  static const String version = 'VERSION VARA FM v4.4.0';

  /// When true, session frames are recorded for [takeFrames].
  bool logFrames = false;
  final List<StationFrame> _frameLog = <StationFrame>[];

  /// Returns and clears the session frames recorded since the last call.
  List<StationFrame> takeFrames() {
    final List<StationFrame> out = List<StationFrame>.of(_frameLog);
    _frameLog.clear();
    return out;
  }

  void _logFrame(StationFrame f) {
    if (logFrames) _frameLog.add(f);
  }

  /// Control codebook keys: codes 1..22 are keyed by D (downstream hash),
  /// connect replies by U (the caller's hash).
  static Map<String, Object?> _keyMeta(Codebook? cb) =>
      cb == null ? const <String, Object?>{} : <String, Object?>{'keyD': cb.keyD, 'keyU': cb.keyU};

  Map<String, Object?> _linkMeta() {
    final FmSession s = _session;
    return <String, Object?>{
      if (s.caller.isNotEmpty) 'caller': s.caller,
      if (s.answerer.isNotEmpty) 'answerer': s.answerer,
    };
  }

  String _lastListen = '';

  /// Records what the receiver now waits for (records, control codes, keys),
  /// when that changes, so a missed reply can be compared with what was sent.
  void _logListen(FmListen l, List<FmRecord> records, bool answering) {
    if (!logFrames) return;
    final (int, int)? c = l.ctrl;
    final String sig = '${l.bw.name}|${records.map((r) => r.index).join(',')}|'
        '${l.codes.join(',')}|${c?.$1}|${c?.$2}|${l.nframes}|$answering';
    if (sig == _lastListen) return;
    _lastListen = sig;
    _logFrame(StationFrame(
      tx: false,
      record: -2,
      bytes: Uint8List(0),
      meta: <String, Object?>{
        'bw': l.bw.name,
        'records': <int>[for (final FmRecord r in records) r.index],
        'codes': List<int>.of(l.codes),
        if (c != null) ...<String, Object?>{'keyD': c.$1, 'keyU': c.$2},
        'n': l.nframes,
        'linked': l.linked,
        if (!answering) 'answering': false,
        ..._linkMeta(),
        'state': _session.state.debug,
      },
    ));
  }

  /// Records a session transmission rendered as [samples] station samples.
  void _logTx(FmTx t, int samples) {
    if (!logFrames) return;
    final double burstMs = secsOf(samples) * 1000.0;
    final String state = _session.state.debug;
    switch (t) {
      case FmTxCtrl(:final int code, :final int lead):
        _logFrame(StationFrame(
          tx: true,
          code: code,
          bytes: Uint8List(0),
          meta: <String, Object?>{
            'lead': lead,
            'rows': lead + codeRows,
            'burstMs': burstMs,
            'drive': _opts.driveDb,
            ..._keyMeta(_cb),
            ..._linkMeta(),
            'state': state,
          },
        ));
      case FmTxData(:final FmRecord record, :final List<Uint8List> frames, :final int lead):
        final FmBandwidth bw = record == FmRecord.connect ? _cfg.bw : _session.bandwidth;
        for (int i = 0; i < frames.length; i++) {
          _logFrame(StationFrame(
            tx: true,
            record: record.index,
            bytes: frames[i],
            meta: <String, Object?>{
              'bw': bw.name,
              'i': i + 1,
              'n': frames.length,
              'lead': lead,
              'burstMs': burstMs,
              'vias': _session.hasVias,
              'drive': _opts.driveDb,
              'state': state,
            },
          ));
        }
    }
  }

  FmSession _session;
  FmConfig _cfg;
  final StationOptions _opts;
  bool _listenOn = true;
  FmListen? _listen;
  int _now = 0;
  final TxScheduler _tx;
  final List<Report> _reports = <Report>[];
  final List<int> _pending = <int>[];
  final Busy _busy = Busy.fm();
  final FmReceiver _rx;
  final int _rxBase = 0;
  Modulator _modm;
  Codebook? _cb;
  final Digi _digi;
  final List<Codebook?> _digiCb = <Codebook?>[null, null];
  final XorShift _rng;
  final List<(int, List<Uint8List>)> _unproto = <(int, List<Uint8List>)>[];
  final broadcast.BroadcastReassembler _reasm = broadcast.BroadcastReassembler();
  bool _kissRx = false;
  bool _ignoreDcd = false;

  FmStation(FmConfig cfg, StationOptions opts)
      : _rng = XorShift(cfg.seed * _seedMix),
        _session = FmSession(cfg.copy()),
        _cfg = cfg,
        _opts = opts,
        _tx = TxScheduler(opts.txLatency, opts.rxLag),
        _rx = FmReceiver(cfg.bw, 0, const <FmRecord>[FmRecord.connect], 1),
        _modm = Modulator(cfg.bw),
        _digi = Digi('', cfg.bw) {
    drain();
  }

  FmState get state => _session.state;

  FmSession get session => _session;

  FmBandwidth get bandwidth => _session.bandwidth;

  int get now => _now;

  bool get ptt => _tx.ptt;

  bool get busy => _busy.isOn;

  int get buffered => _pending.length + _session.buffered;

  bool get tuning => _tx.tuning;

  StationOptions get options => _opts;

  FmConfig get config => _cfg;

  bool get digipeating => _digi.active;

  /// Enables constellation capture on received frames (diagnostics only).
  set captureSymbols(bool on) {
    _rx.captureSymbols = on;
    if (!on) _rx.captured.clear();
  }

  /// Returns and clears frames decoded since the last call while capture is on.
  List<FmFrameRx> takeCaptured() {
    final List<FmFrameRx> out = List<FmFrameRx>.of(_rx.captured);
    _rx.captured.clear();
    return out;
  }

  /// The level a captured frame was received with.
  FmLevel rxLevel(FmRecord record) => _rx.bw.level(record);

  /// True while transmit audio is queued or being played.
  bool get transmitting => _tx.hasBursts;

  /// Holds back the start of every transmission (session, digipeater and
  /// broadcast) while the host reports the radio is receiving. Reply windows
  /// are timed from when a burst actually ends, so a deferred burst stays valid.
  bool get txBlocked => _tx.blocked;
  set txBlocked(bool on) => _tx.blocked = on;

  /// Index range of transmit (non-idle) samples in the last [process] output, or -1.
  int keyedFirst = -1;
  int keyedLast = -1;

  void setDigipeater(String call) {
    _digi.call = call;
    refreshListen();
  }

  void drain() => _drainAt(_now);

  Report? pop() => _tx.pop(_reports);

  bool tune(bool on) {
    if (!on) {
      _tx.untune(_now, _reports);
      return true;
    }
    if (!idle || _tx.ptt) return false;
    _tx.tune(tuneTone(_opts.driveDb));
    return true;
  }

  void setDrive(double db) {
    _opts.driveDb = db;
    _tx.retune(() => tuneTone(db));
  }

  void setTxLatency(int t, int lag) {
    _opts.txLatency = t;
    _opts.rxLag = lag;
    _tx.setLatency(t, lag);
  }

  void update(void Function(FmConfig) f) {
    f(_cfg);
    f(_session.config);
  }

  void send(List<int> data) {
    if (_session.state == FmState.listen) {
      final int room = txRingBytes - buffered < 0 ? 0 : txRingBytes - buffered;
      if (data.length > room) _reports.add(const ReportTrace('buffer limit exceeded'));
      _pending.addAll(data.length > room ? data.sublist(0, room) : data);
      return;
    }
    _session.send(_now, data);
    drain();
  }

  void disconnect() {
    _session.disconnect(_now);
    drain();
  }

  void abort() {
    _session.abort(_now);
    drain();
  }

  void dropLink() {
    _session.dropLink();
    drain();
  }

  void setListen(bool on) {
    _listenOn = on;
    final FmListen? l = _listen;
    if (l != null) _apply(l);
  }

  void _sendUnproto() {
    final bool clear = _ignoreDcd || !_busy.isOn;
    if (_session.state != FmState.listen || _digi.active || !_tx.isEmpty || _tx.ptt || !clear) return;
    if (_unproto.isEmpty) return;
    final (_, List<Uint8List> group) = _unproto.removeAt(0);
    final FmBandwidth bw = _cfg.bw;
    if (_modm.bw != bw) _modm = Modulator(bw);
    final TxOptions opt = TxOptions(driveDb: _opts.driveDb);
    final int n = group.length;
    for (int i = 0; i < n; i++) {
      final Float64List x =
          _modm.transmission(FmRecord.broadcast, 0, <List<int>>[group[i]], idleBeaconLeadIn, opt, _rng.below);
      final int tail = i + 1 == n ? dataOverhang : fragmentGap;
      final List<Report> keyed = <Report>[
        const ReportHost(hostPending),
        _bitrate(bw, FmRecord.broadcast, true),
        ReportTrace('tx rec16 unproto ${i + 1}/$n'),
      ];
      if (i == 0) {
        _reports.addAll(keyed);
        keyed.clear();
      }
      _tx.push(_quantised(x), tail, _now, keyed, i + 1 == n ? BurstKind.lastFragment : BurstKind.fragment);
    }
  }

  bool get _linked => _listen?.linked ?? false;

  void _onEvent(FmEvent ev) {
    final int now = _now;
    final int tEnd;
    switch (ev) {
      case CtrlEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmCtrlEvent ctrl):
        tEnd = _rxBase + ctrl.tEnd48;
      case TxEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmTransmission tx):
        tEnd = _rxBase + to48(tx.tEnd);
      case FrameEv<FmCtrlEvent, FmRecord, FmFrameRx>():
        drain();
        return;
    }
    _tx.hold(tEnd + minGap);
    if (ev case TxEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmTransmission tx) when tx.record != FmRecord.broadcast) {
      final int n = tx.frames.length;
      for (int i = 0; i < n; i++) {
        final FmFrameRx f = tx.frames[i];
        final bool ok = f.ok && !f.missing;
        _logFrame(StationFrame(
          tx: false,
          record: tx.record.index,
          ok: ok,
          bytes: ok ? f.bytes : Uint8List(0),
          meta: <String, Object?>{
            'bw': _rx.bw.name,
            'i': i + 1,
            'n': n,
            if (!f.missing) ...<String, Object?>{
              'snr': f.snrDb + adapt.snrOffsetDb,
              'esn0': f.esn0Db,
              'iter': f.iterations,
              'coh': f.coherence,
            },
            if (f.missing) 'missing': true,
            'ms': (f.tEnd - f.t) * 1000.0 / fs6,
            'vias': _session.hasVias,
            'state': _digi.active ? 'Digipeating' : _session.state.debug,
          },
        ));
      }
    }
    switch (ev) {
      case CtrlEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmCtrlEvent ctrl):
        final d = ctrl.det;
        final bool digi = _digi.active;
        final check = !digi && ctrl.side == Side.source ? _session.ctrlCheck(d.code, tEnd) : null;
        _logFrame(StationFrame(
          tx: false,
          code: d.code,
          bytes: Uint8List(0),
          meta: <String, Object?>{
            'hits': d.hits,
            'row': d.leadRow,
            'side': ctrl.side.name,
            if (check != null) ...<String, Object?>{
              'verdict': check.verdict,
              'ticks': check.ticks,
              if (check.window != null) 'window': check.window,
            },
            ..._keyMeta(digi ? _digiCb[ctrl.side.idx] : _cb),
            ..._linkMeta(),
            'state': digi ? 'Digipeating' : _session.state.debug,
          },
        ));
        _reports.add(ReportTrace('rx c${d.code} hits ${d.hits} lead ${d.leadRow} end ${secsOf(tEnd).toStringAsFixed(3)} '
            '${digi ? 'Digi side ${ctrl.side.idx}' : _session.state.debug}'));
        if (digi) {
          _digi.onCtrl(now, d.code, d.leadRow, ctrl.side);
          drain();
          return;
        }
        if (ctrl.side != Side.source) return;
        _session.onCtrl(now, CtrlIn(d.code, d.leadRow, tEnd));
      case TxEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmTransmission tx) when tx.record == FmRecord.broadcast:
        final FmFrameRx? f = tx.frames.isNotEmpty && tx.frames.first.ok ? tx.frames.first : null;
        if (f == null) {
          _reasm.reset();
          return;
        }
        final String hex = f.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        _reports.add(ReportTrace('rx rec16 end ${secsOf(tEnd).toStringAsFixed(3)} $hex'));
        _reports.add(ReportHost(HostSn(f.snrDb + adapt.snrOffsetDb)));
        switch (_reasm.push(f.bytes)) {
          case broadcast.ReceivedCq(:final value) when _cfg.host.chat:
            _reports.add(ReportLine(value.hostLine));
          case broadcast.ReceivedKiss(:final KissCommand cmd, :final Uint8List data):
            _reports.add(ReportKiss(cmd, data));
          default:
        }
      case TxEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmTransmission tx)
          when _digi.active || (tx.record == FmRecord.connect && _session.state == FmState.listen):
        final String ok = tx.frames.map((f) => f.ok ? '+' : '-').join();
        FmFrameRx? first;
        for (final FmFrameRx f in tx.frames) {
          if (f.ok) {
            first = f;
            break;
          }
        }
        final bool took = tx.record == FmRecord.connect && first != null && _digi.onRecord0(now, first.bytes, first.snrDb);
        if (took || _digi.active) {
          _reports.add(ReportTrace('rx rec${tx.record.index} [$ok] end ${secsOf(tEnd).toStringAsFixed(3)} Digi'));
          if (!took) {
            _digi.onSync(now);
            for (final FmFrameRx f in tx.frames) {
              _digi.onData(now, tx.record, f.ok && !f.missing, f.bytes, f.snrDb);
            }
          }
        } else {
          _onSessionData(now, tx, tEnd);
        }
      case TxEv<FmCtrlEvent, FmRecord, FmFrameRx>(:final FmTransmission tx):
        _onSessionData(now, tx, tEnd);
      case FrameEv<FmCtrlEvent, FmRecord, FmFrameRx>():
        break;
    }
    drain();
  }

  void _onSessionData(int now, FmTransmission t, int tEnd) {
    final String ok = t.frames.map((f) => f.ok ? '+' : '-').join();
    final String lvl =
        t.frames.isNotEmpty && t.frames.last.ok ? _levelNote(t.record, t.frames.last.bytes, _session.hasVias) : '';
    _reports.add(ReportTrace(
        'rx rec${t.record.index} [$ok]$lvl end ${secsOf(tEnd).toStringAsFixed(3)} ${_session.state.debug}'));
    _session.onData(now, _dataIn(t, tEnd));
  }

  void _applyDigi(DigiListen l) {
    _reports.add(ReportTrace('digi expect [${l.records.map((r) => r.index).join(', ')}] '
        'data key ${l.dataKey.toRadixString(16).padLeft(8, '0')}'));
    _rx.setBandwidth(l.bw);
    _rx.setKey(l.dataKey);
    _rx.expect(l.records, 1);
    for (final Side s in Side.values) {
      final CtrlListen c = l.ctrl[s.idx];
      final Codebook cb = Codebook(c.keyD, c.keyU);
      _rx.setCtrl(s, cb, c.codes);
      _digiCb[s.idx] = cb;
    }
  }

  (List<double>, int) _renderDigi(DigiTx t) {
    final double d = _opts.driveDb;
    switch (t) {
      case DigiTxCtrl(:final int code, :final int lead, :final Side side):
        return (_quantised(frameAudio(_digiCb[side.idx]!, code, lead, d)), 0);
      case DigiTxData(:final FmRecord record, :final Uint8List frame, :final int lead, :final Side side):
        final FmBandwidth bw = record == FmRecord.connect ? _cfg.bw : _digi.bandwidth;
        if (_modm.bw != bw) _modm = Modulator(bw);
        final int key = _digi.key(side);
        final Float64List x =
            _modm.transmission(record, key, <List<int>>[frame], lead, TxOptions(driveDb: d), _rng.below);
        return (_quantised(x), dataOverhang);
    }
  }

  void _host(HostEvent h) {
    final Report r = switch (h) {
      _ when h == hostUnencrypted => const ReportUnencryptedLink(),
      HostRxFrame(:final FmRecord record) => _bitrate(_session.bandwidth, record, false),
      HostLog(:final String text) => ReportTrace(text),
      _ => ReportHost(h),
    };
    _reports.add(r);
  }

  void refreshListen() {
    final FmListen? l = _listen;
    if (l != null) _apply(l);
  }

  (List<double>, int, List<Report>) _render(FmTx t) {
    final double d = _opts.driveDb;
    final List<Report> keyed = <Report>[];
    switch (t) {
      case FmTxCtrl(:final int code, :final int lead):
        final Codebook cb = _cb ?? (throw StateError('codebook before the first control frame'));
        return (_quantised(frameAudio(cb, code, lead, d)), 0, keyed);
      case FmTxData(:final FmRecord record, :final List<Uint8List> frames, :final int lead):
        final FmBandwidth bw = record == FmRecord.connect ? _cfg.bw : _session.bandwidth;
        if (_modm.bw != bw) _modm = Modulator(bw);
        _reports.add(_bitrate(bw, record, true));
        for (int i = 1; i < frames.length; i++) {
          keyed.add(_bitrate(bw, record, true));
        }
        final Float64List x =
            _modm.transmission(record, _session.key, frames, lead, TxOptions(driveDb: d), _rng.below);
        return (_quantised(x), dataOverhang, keyed);
    }
  }

  void _burstDone(BurstKind kind, int start, int end) {
    final int heard = end + _tx.latency;
    _rx.mute(start - _rxBase, heard - _rxBase);
    _rx.markTxEnd(heard - _rxBase);
    final int mark = _reports.length;
    switch (kind) {
      case BurstKind.digi:
        _digi.onTxDone();
        _drainAt(end);
      case BurstKind.session:
        _session.onTxDone(heard + _opts.pttTail);
        _drainAt(end);
      case BurstKind.announce:
      case BurstKind.fragment:
      case BurstKind.lastFragment:
        break;
    }
    _tx.release(end, _reports, mark);
    if (kind == BurstKind.lastFragment) {
      _reports.add(const ReportHost(hostCancelPending));
      refreshListen();
    }
  }

  void _apply(FmListen l) {
    if (_digi.active) {
      _listen = l;
      return;
    }
    final FmListen? o = _listen;
    if (o == null || !_sameRecords(o.records, l.records) || o.nframes != l.nframes) {
      _reports.add(ReportTrace('expect [${l.records.map((r) => r.index).join(', ')}] x${l.nframes}'));
    }
    _rx.setBandwidth(l.bw);
    _rx.setKey(l.key);
    final bool answering = _listenOn || l.linked || _session.state != FmState.listen;
    final List<FmRecord> records = answering ? List<FmRecord>.of(l.records) : <FmRecord>[];
    if (_digi.call.isNotEmpty && _session.state == FmState.listen && !records.contains(FmRecord.connect)) {
      records.add(FmRecord.connect);
    }
    if (_kissRx && _session.state == FmState.listen && _tx.isEmpty) records.add(FmRecord.broadcast);
    _rx.expect(records, l.nframes);
    final (int, int)? c = l.ctrl;
    _cb = c == null ? null : Codebook(c.$1, c.$2);
    _logListen(l, records, answering);
    final Codebook? cb = _cb;
    if (cb != null && l.codes.isNotEmpty) {
      _rx.setCtrl(Side.source, cb, l.codes);
    } else {
      _rx.setCtrl(Side.source, null, const <int>[]);
    }
    _listen = l;
  }

  static bool _sameRecords(List<FmRecord> a, List<FmRecord> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _drainAt(int now) {
    if (_pending.isNotEmpty && _session.state != FmState.listen) {
      final List<int> d = List<int>.of(_pending);
      _pending.clear();
      _session.send(now, d);
    }
    final List<FmTx> txs = <FmTx>[];
    while (true) {
      final FmOutput? o = _session.pop();
      if (o == null) break;
      switch (o) {
        case OutTx<FmTx, FmListen>(:final FmTx tx):
          txs.add(tx);
        case OutListen<FmTx, FmListen>(:final FmListen listen):
          _apply(listen);
        case OutHost<FmTx, FmListen>(:final HostEvent event):
          _host(event);
      }
    }
    for (final FmTx t in txs) {
      final String what = switch (t) {
        FmTxCtrl(:final int code, :final int lead) => 'tx c$code lead $lead',
        FmTxData(:final FmRecord record, :final List<Uint8List> frames, :final int lead) =>
          'tx rec${record.index}x${frames.length}'
              '${frames.isEmpty ? '' : _levelNote(record, frames.last, _session.hasVias)} lead $lead',
      };
      _reports.add(ReportTrace('$what ${_session.state.debug}'));
      _tx.stopTune();
      final int earliest = _tx.nextStart(now);
      final (List<double> samples, int tail, List<Report> keyed) = _render(t);
      _logTx(t, samples.length);
      _tx.push(samples, tail, earliest, keyed, BurstKind.session);
    }
    while (true) {
      final DigiOutput? o = _digi.pop();
      if (o == null) break;
      switch (o) {
        case DigiOutTx(:final DigiTx tx):
          _reports.add(ReportTrace(switch (tx) {
            DigiTxCtrl(:final int code, :final int lead, :final Side side) =>
              'tx c$code lead $lead Digi side ${side.idx}',
            DigiTxData(:final FmRecord record, :final int lead, :final Side side) =>
              'tx rec${record.index}x1 lead $lead Digi side ${side.idx}',
          }));
          _tx.stopTune();
          final int earliest = _tx.nextStart(now);
          final (List<double> samples, int tail) = _renderDigi(tx);
          _tx.push(samples, tail, earliest, <Report>[], BurstKind.digi);
        case DigiOutListen(:final DigiListen listen):
          _applyDigi(listen);
        case DigiOutHost(:final HostEvent event):
          _host(event);
        case DigiOutDone():
          _digiCb[0] = null;
          _digiCb[1] = null;
          _rx.setCtrl(Side.target, null, const <int>[]);
          refreshListen();
      }
    }
  }

  static List<double> tuneTone(double driveDb) => tuneBlock(driveDb).map(quantise).toList();

  bool get idle =>
      _session.state == FmState.listen && !_digi.active && _tx.isEmpty && _unproto.isEmpty;

  StationLink link() {
    final FmSession s = _session;
    return StationLink(
      _digi.active ? 'Digipeating' : s.state.debug,
      adapt.asLevel(s.level).value,
      s.peer,
      s.bandwidth.name,
      passband(s.bandwidth),
      s.attempts,
      null,
    );
  }

  bool reconfigure(FmConfig cfg) {
    if (!idle) return false;
    _cfg = cfg;
    _digi.setBandwidth(cfg.bw);
    _session = FmSession(cfg.copy());
    drain();
    return true;
  }

  /// Processes one block of received audio and fills [output] with the
  /// transmit audio for the same sample instants.
  void process(List<double> input, List<double> output) {
    final int t0 = _now, n = input.length;
    final bool txWasEmpty = _tx.isEmpty;
    final List<double> fed = _keyBlock(t0, input, output);
    // Broadcast receive is disabled while the transmitter is busy (including the
    // PTT release delay), so re-arm it once the transmitter has fully gone idle.
    if (!txWasEmpty && _tx.isEmpty) refreshListen();
    _now = t0 + n;
    final bool forced = _tx.ptt || !_tx.isEmpty || _session.state != FmState.listen || _digi.active;
    for (final bool e in _busy.feed(input, forced)) {
      _reports.add(ReportBusy(e));
    }
    for (final FmEvent ev in _rx.feed(fed)) {
      _onEvent(ev);
    }
    final int? sd = _session.nextDeadline();
    if (sd != null && sd <= _now) _session.poll(_now);
    final int? dd = _digi.nextDeadline();
    if (dd != null && dd <= _now) _digi.poll(_now);
    drain();
    _sendUnproto();
  }

  List<double> _keyBlock(int t0, List<double> input, List<double> output) {
    final List<double> fed = List<double>.of(input);
    keyedFirst = -1;
    keyedLast = -1;
    for (int i = 0; i < output.length && i < fed.length; i++) {
      switch (_tx.next(t0 + i, _reports)) {
        case TxIdle():
          output[i] = 0.0;
          continue;
        case TxSample(:final double sample):
          output[i] = sample;
        case TxLast(:final double sample, :final BurstKind kind, :final int start, :final int end):
          _burstDone(kind, start, end);
          output[i] = sample;
      }
      if (keyedFirst < 0) keyedFirst = i;
      keyedLast = i;
      fed[i] = 0.0;
    }
    return fed;
  }

  bool connect(String mycall, String remote, List<String> vias) {
    if (_session.state == FmState.awaitGo && !_tx.ptt && _tx.isEmpty && !_linked) {
      _session = FmSession(_cfg.copy());
    }
    if (_session.state != FmState.listen || _digi.active) return false;
    final bool ok = _session.connect(_now, mycall, remote, vias);
    drain();
    return ok;
  }

  bool kiss(KissCommand cmd, List<int> data) {
    final int queued = _unproto.fold(0, (a, u) => a + u.$1);
    if (queued + data.length > kc.maxQueuedBytes) return false;
    kc.KissBuffer? b;
    try {
      b = kc.encode(cmd, data);
    } on ax25.Ax25Error {
      b = null;
    } on kc.KissTooLong {
      b = null;
    }
    final List<Uint8List>? f = b == null ? null : broadcast.frames(_cfg.bw, b.bytes);
    if (f != null) _unproto.add((data.length, f));
    return true;
  }

  bool cqFrame(String call, String? bw) {
    if (!idle) return false;
    final Uint8List? b = broadcast.cqBuffer(call, bw);
    final List<Uint8List>? f = b == null ? null : broadcast.frames(_cfg.bw, b);
    if (f == null) return false;
    _unproto.add((0, f));
    return true;
  }

  void setIgnoreDcd(bool on) => _ignoreDcd = on;

  void setKissRx(bool on) {
    _kissRx = on;
    refreshListen();
  }
}
