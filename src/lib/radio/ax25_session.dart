/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'ax25_address.dart';
import 'ax25_packet.dart';
import 'radio.dart' show TransmitDataFrameData;
import 'tnc_data_fragment.dart';

/// Connection state of an [AX25Session].
///
/// These four values are the public-facing states exposed to the rest of the
/// application. Internally the session runs the full six-state AX.25 v2.2 data
/// link state machine (see [_DlState]); the extra internal states collapse into
/// these four:
///   * `connecting`    <- awaiting connection (SABM) / awaiting v2.2 (SABME)
///   * `connected`     <- connected / timer recovery
///   * `disconnecting` <- awaiting release (DISC sent)
enum AX25ConnectionState {
  disconnected, // 1
  connected, // 2
  connecting, // 3
  disconnecting, // 4
}

/// Signature for the connection-state-changed callback.
typedef AX25StateChangedHandler =
    void Function(AX25Session sender, AX25ConnectionState state);

/// Signature for received-data callbacks (I-frame and UI-frame).
typedef AX25DataReceivedHandler =
    void Function(AX25Session sender, Uint8List data);

/// Signature for the error callback.
typedef AX25ErrorHandler = void Function(AX25Session sender, String error);

/// The internal six-state AX.25 v2.2 data link state machine, matching the
/// state numbering used by the AX.25 specification (and Direwolf's
/// `dlsm_state_e`).
enum _DlState {
  disconnected, // 0
  awaitingConnection, // 1 - waiting for UA in response to SABM (v2.0)
  awaitingRelease, // 2 - waiting for UA/DM in response to DISC
  connected, // 3 - information transfer
  timerRecovery, // 4 - T1 expired, resynchronizing
  awaitingV22Connection, // 5 - waiting for UA in response to SABME (v2.2)
}

/// Selective-reject capability negotiated for a link.
enum _SrejEnable { none, single, multi }

/// A block of connected-mode data waiting to be sent, or that has been sent and
/// retained for possible retransmission. This is the Dart equivalent of
/// Direwolf's `cdata_t`.
class _Cdata {
  int pid;
  Uint8List data;
  _Cdata(this.pid, this.data);
}

/// Implements the AX.25 v2.2 connected-mode data link layer.
///
/// This is a Flutter/Dart port of Direwolf's `ax25_link.c` data link state
/// machine. Unlike Direwolf, which keeps a global linked list of links, each
/// [AX25Session] instance represents exactly one link (one peer) on one radio
/// device. The public API is a drop-in replacement for the previous C#-derived
/// implementation.
///
/// The session communicates through the [DataBroker]:
///   * It subscribes to `UniqueDataFrame` events (carrying a [TncDataFragment])
///     and decodes incoming AX.25 frames via [receive].
///   * It transmits frames by dispatching `TransmitDataFrame`.
///
/// Both standard (modulo-8, AX.25 v2.0) and extended (modulo-128, AX.25 v2.2)
/// operation are supported. Set [modulo128] to `true` before calling [connect]
/// to attempt a v2.2 connection (with automatic fall-back to v2.0 if the peer
/// does not understand SABME). Subscribe to [onStateChanged], [onDataReceived],
/// [onUiDataReceived] and [onError] to observe activity. Always call [dispose]
/// when finished.
///
/// Notable feature differences from Direwolf, dictated by the surrounding
/// Flutter primitives:
///   * XID parameter negotiation is simplified. The underlying [AX25Packet]
///     layer has no XID information-field codec, so this port does not perform a
///     full parameter exchange. v2.2 links operate with sensible defaults
///     (single selective reject, k=32) and incoming XID commands are answered
///     politely. The rest of the state machine is a faithful port.
///   * There is no channel-busy signal available, so the timer pause/resume
///     machinery is present but effectively never engages.
class AX25Session {
  final DataBrokerClient _broker = DataBrokerClient();
  final int _radioDeviceId;
  bool _disposed = false;

  /// PID value used for connected-mode segmentation fragments (AX.25 v2.2).
  static const int _pidSegmentationFragment = 0x08;

  /// Default PID for application data (no layer-3 protocol).
  static const int _pidNoLayer3 = 0xF0;

  /// Largest information field we will accept, matching Direwolf's
  /// `AX25_MAX_INFO_LEN`.
  static const int _ax25MaxInfoLen = 2048;

  /// T3 inactivity-poll period, in seconds (matches Direwolf's `T3_DEFAULT`).
  static const double _t3Default = 300.0;

  /// Custom session state for storing application-specific data. Cleared when
  /// the session disconnects.
  final Map<String, Object?> sessionState = {};

  /// Raised when the connection state changes.
  AX25StateChangedHandler? onStateChanged;

  /// Raised when reassembled I-frame data is received from the remote station.
  AX25DataReceivedHandler? onDataReceived;

  /// Raised when UI-frame data is received (connectionless data).
  AX25DataReceivedHandler? onUiDataReceived;

  /// Raised when an error occurs in the session.
  AX25ErrorHandler? onError;

  /// Optional callsign override. If set, used instead of the DataBroker value.
  String? callSignOverride;

  /// Optional station ID override. If `>= 0`, used instead of the DataBroker
  /// value.
  int stationIdOverride = -1;

  // ---- tunable protocol parameters ------------------------------------------

  /// Window size (k) for basic modulo-8 (v2.0) operation.
  int maxFrames = 4;

  /// Window size (k) for extended modulo-128 (v2.2) operation.
  int maxFramesExtended = 32;

  /// Maximum size of the information field in each I-frame (N1 / paclen).
  int packetLength = 256;

  /// Number of times to retry (N2) before giving up on a connection or data.
  int retries = 10;

  /// Base acknowledgement timeout ("FRACK"), in seconds. The effective T1 value
  /// starts at `frackSeconds * (2 * digipeaters + 1)` and is then adapted
  /// dynamically from the measured round-trip time.
  int frackSeconds = 3;

  /// Number of SABME attempts before falling back to SABM (v2.0). Set to 0 to
  /// never attempt v2.2 even when [modulo128] is `true`.
  int maxV22 = 3;

  /// Baud rate. Retained for API compatibility; timing is now derived from
  /// [frackSeconds] and the measured round-trip time instead.
  int hBaud = 1200;

  /// When `true`, [connect] attempts an extended (modulo-128, v2.2) link,
  /// falling back to modulo-8 (v2.0) if the peer does not understand SABME.
  /// When `false`, only v2.0 is used.
  bool modulo128 = false;

  /// Enable trace logging for debugging.
  bool tracing = true;

  /// The list of addresses for this session: destination/peer (index 0),
  /// source/own (index 1), and optional digipeaters following.
  List<AX25Address>? addresses;

  // ---- internal state machine variables -------------------------------------

  _DlState _state = _DlState.disconnected;
  AX25ConnectionState _lastPublic = AX25ConnectionState.disconnected;

  int _modulo = 8;
  int _kMaxframe = 4;
  int _n1Paclen = 256;
  int _n2Retry = 10;
  _SrejEnable _srejEnable = _SrejEnable.none;

  int _vs = 0; // V(S) send state variable
  int _va = 0; // V(A) acknowledge state variable
  int _vr = 0; // V(R) receive state variable

  bool _layer3Initiated = false;
  bool _peerReceiverBusy = false;
  bool _rejectException = false;
  bool _ownReceiverBusy = false;
  bool _acknowledgePending = false;

  int _rc = 0; // retry count
  double _srt = 0; // smoothed round-trip time (seconds)
  double _t1v = 0; // current T1 value (seconds)
  // No channel-busy signal is available from the radio layer, so the timer
  // pause/resume machinery below is present but never actually engages.
  final bool _radioChannelBusy = false;

  // Timers use absolute expiry times (seconds), 0 meaning "not running".
  double _t1Exp = 0;
  double _t1PausedAt = 0;
  double _t1RemainingWhenLastStopped = -999; // negative => invalid
  bool _t1HadExpired = false;
  double _t3Exp = 0;
  double _tm201Exp = 0;
  double _tm201PausedAt = 0;

  // Management data link (MDL) state for XID negotiation.
  int _mdlState = 0; // 0 = ready, 1 = negotiating
  int _mdlRc = 0;

  // Transmit / receive buffers, indexed by sequence number.
  final List<_Cdata> _iFrameQueue = [];
  final List<_Cdata?> _txdataByNs = List<_Cdata?>.filled(128, null);
  final List<_Cdata?> _rxdataByNs = List<_Cdata?>.filled(128, null);

  // Segment reassembler.
  Uint8List? _raData;
  int _raLen = 0;
  int _raSize = 0;
  int _raFollowing = 0;

  Timer? _ticker;
  bool _seizePending = false;

  /// Creates a new AX.25 session that communicates through the radio identified
  /// by [radioDeviceId].
  AX25Session(int radioDeviceId) : _radioDeviceId = radioDeviceId {
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );
    _broker.logInfo(
      '[AX25Session] Session created for radio device $radioDeviceId',
    );
  }

  // ---- public accessors -----------------------------------------------------

  /// The callsign used for this session.
  String get sessionCallsign {
    if (callSignOverride != null) return callSignOverride!;
    return _broker.getValue<String>(0, 'CallSign', 'NOCALL') ?? 'NOCALL';
  }

  /// The station ID used for this session.
  int get sessionStationId {
    if (stationIdOverride >= 0) return stationIdOverride;
    return _broker.getValue<int>(0, 'StationId', 0) ?? 0;
  }

  /// The radio device ID associated with this session.
  int get radioDeviceId => _radioDeviceId;

  /// The current (public) connection state of the session.
  AX25ConnectionState get currentState => _publicState;

  /// The number of blocks awaiting transmission or acknowledgment.
  int get sendBufferLength {
    var n = _iFrameQueue.length;
    for (final t in _txdataByNs) {
      if (t != null) n++;
    }
    return n;
  }

  /// The number of out-of-order blocks buffered for reordering.
  int get receiveBufferLength {
    var n = 0;
    for (final r in _rxdataByNs) {
      if (r != null) n++;
    }
    return n;
  }

  AX25ConnectionState get _publicState {
    switch (_state) {
      case _DlState.disconnected:
        return AX25ConnectionState.disconnected;
      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        return AX25ConnectionState.connecting;
      case _DlState.awaitingRelease:
        return AX25ConnectionState.disconnecting;
      case _DlState.connected:
      case _DlState.timerRecovery:
        return AX25ConnectionState.connected;
    }
  }

  // ---- event helpers --------------------------------------------------------

  void _onErrorEvent(String error) {
    _trace('ERROR: $error');
    onError?.call(this, error);
  }

  void _onStateChangedEvent(AX25ConnectionState state) =>
      onStateChanged?.call(this, state);

  void _onUiDataReceivedEvent(Uint8List data) =>
      onUiDataReceived?.call(this, data);

  void _onDataReceivedEvent(Uint8List data) => onDataReceived?.call(this, data);

  void _trace(String msg) {
    if (tracing && !_disposed) {
      _broker.logInfo('[AX25Session/$_radioDeviceId] $msg');
    }
  }

  // ---- broker plumbing ------------------------------------------------------

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;
    if (data.radioDeviceId != _radioDeviceId) return;
    if (!data.incoming) return;

    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    receive(packet);
  }

  /// Transmits an AX.25 packet via the DataBroker to the associated radio. This
  /// is the Dart equivalent of Direwolf's `lm_data_request`.
  void _emitPacket(AX25Packet packet) {
    // Only I and S frames carry sequence numbers whose control field width
    // depends on the modulo. U-frames always use a single control byte and are
    // modulo-independent, so they must never be flagged as extended (doing so
    // would make the encoder emit an invalid second control byte and misplace
    // the poll/final bit).
    final t = packet.type;
    final isIorS = t == FrameType.iFrame || (t & 0x3) == FrameType.sFrame;
    packet.modulo128 = isIorS && _modulo == 128;
    _broker.dispatch(
      deviceId: _radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(packet: packet, channelId: -1, regionId: -1),
      store: false,
    );
  }

  // ---- frame builders -------------------------------------------------------

  AX25Packet _uFrame(int type, {required bool command, required bool pf, Uint8List? info}) {
    final p = AX25Packet(
      addresses: addresses!,
      nr: 0,
      ns: 0,
      pollFinal: pf,
      command: command,
      type: type,
      data: info,
    );
    if (type == FrameType.uFrameUi) p.pid = _pidNoLayer3;
    return p;
  }

  AX25Packet _sFrame(int type, {required bool command, required int nr, required bool pf, Uint8List? info}) {
    return AX25Packet(
      addresses: addresses!,
      nr: nr,
      ns: 0,
      pollFinal: pf,
      command: command,
      type: type,
      data: info,
    );
  }

  AX25Packet _iFramePacket({required int nr, required int ns, required bool p, required int pid, required Uint8List data}) {
    final pkt = AX25Packet(
      addresses: addresses!,
      nr: nr,
      ns: ns,
      pollFinal: p,
      command: true,
      type: FrameType.iFrame,
      data: data,
    );
    pkt.pid = pid;
    return pkt;
  }

  // ---- modulo arithmetic ----------------------------------------------------

  int _mod(int n) {
    final m = _modulo;
    var r = n % m;
    if (r < 0) r += m;
    return r;
  }

  bool _withinWindow() => _vs != _mod(_va + _kMaxframe);

  // ---- version selection ----------------------------------------------------

  void _setVersion20() {
    _srejEnable = _SrejEnable.none;
    _modulo = 8;
    _n1Paclen = packetLength;
    _kMaxframe = maxFrames;
    _n2Retry = retries;
  }

  void _setVersion22() {
    _srejEnable = _SrejEnable.single; // may be upgraded to multi via XID.
    _modulo = 128;
    _n1Paclen = packetLength;
    _kMaxframe = maxFramesExtended;
    _n2Retry = retries;
  }

  // ---- timing ---------------------------------------------------------------

  double _now() => DateTime.now().microsecondsSinceEpoch / 1000000.0;

  int get _numAddr => addresses?.length ?? 2;

  void _initT1vSrt() {
    _t1v = frackSeconds * (2 * (_numAddr - 2) + 1).toDouble();
    _srt = _t1v / 2.0;
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      _dlTimerExpiry();
    });
  }

  void _maybeStopTicker() {
    if (_state == _DlState.disconnected &&
        _t1Exp == 0 &&
        _t3Exp == 0 &&
        _tm201Exp == 0) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _dlTimerExpiry() {
    if (_disposed) return;
    final now = _now();
    if (_t1Exp != 0 && _t1PausedAt == 0 && _t1Exp <= now) {
      _t1Exp = 0;
      _t1PausedAt = 0;
      _t1HadExpired = true;
      _t1Expiry();
    }
    if (_t3Exp != 0 && _t3Exp <= now) {
      _t3Exp = 0;
      _t3Expiry();
    }
    if (_tm201Exp != 0 && _tm201PausedAt == 0 && _tm201Exp <= now) {
      _tm201Exp = 0;
      _tm201PausedAt = 0;
      _tm201Expiry();
    }
    _maybeStopTicker();
  }

  void _startT1() {
    final now = _now();
    _t1Exp = now + _t1v;
    _t1PausedAt = _radioChannelBusy ? now : 0;
    _t1HadExpired = false;
    _ensureTicker();
  }

  void _stopT1() {
    _resumeT1();
    if (_t1Exp != 0) {
      _t1RemainingWhenLastStopped = _t1Exp - _now();
      if (_t1RemainingWhenLastStopped < 0) _t1RemainingWhenLastStopped = 0;
    }
    _t1Exp = 0;
    _t1HadExpired = false;
  }

  bool get _isT1Running => _t1Exp != 0;

  void _resumeT1() {
    if (_t1Exp == 0 || _t1PausedAt == 0) return;
    final pausedFor = _now() - _t1PausedAt;
    _t1Exp += pausedFor;
    _t1PausedAt = 0;
  }

  void _startT3() {
    _t3Exp = _now() + _t3Default;
    _ensureTicker();
  }

  void _stopT3() {
    _t3Exp = 0;
  }

  void _stopTm201() {
    _tm201Exp = 0;
  }

  /// Dynamically adjust the T1 timeout, mirroring Direwolf's `select_t1_value`.
  void _selectT1Value() {
    if (_rc == 0) {
      if (_t1RemainingWhenLastStopped >= 0) {
        _srt = 7.0 / 8.0 * _srt +
            1.0 / 8.0 * (_t1v - _t1RemainingWhenLastStopped);
      }
      if (_srt < 1) {
        _srt = 1;
        if (_numAddr > 2) {
          _srt += 2 * (_numAddr - 2);
        }
      }
      _t1v = _srt * 2;
    } else {
      if (_t1HadExpired) {
        // Linear back-off (not exponential) so retries give up in ~1 minute.
        _t1v = _rc * 0.25 + _srt * 2;
      }
    }

    // Guardrail: keep t1v from flying off into absurd values.
    final initial = frackSeconds * (2 * (_numAddr - 2) + 1).toDouble();
    if (_t1v < 0.25 || _t1v > 2 * initial) {
      _initT1vSrt();
    }
  }

  // ---- sequence-number bookkeeping ------------------------------------------

  void _setVa(int n) {
    _va = n;
    var x = _mod(n - 1);
    while (_txdataByNs[x] != null) {
      _txdataByNs[x] = null;
      x = _mod(x - 1);
    }
  }

  bool _isGoodNr(int nr) {
    int adj(int x) => _mod(x - _va);
    final aVa = adj(_va);
    final aNr = adj(nr);
    final aVs = adj(_vs);
    return aVa <= aNr && aNr <= aVs;
  }

  bool _isNsInWindow(int ns) {
    const generousK = 63;
    int adj(int x) => _mod(x - _vr);
    final aVr = adj(_vr);
    final aNs = adj(ns);
    final aVrpk = adj(_vr + generousK);
    return aVr < aNs && aNs < aVrpk;
  }

  // ---- state transition -----------------------------------------------------

  void _enterNewState(_DlState newState) {
    _state = newState;
    final pub = _publicState;
    if (pub != _lastPublic) {
      _lastPublic = pub;
      _onStateChangedEvent(pub);
      if (pub == AX25ConnectionState.disconnected) {
        addresses = null;
        sessionState.clear();
      }
    }
    if (newState != _DlState.disconnected) _ensureTicker();
  }

  // ---- exception conditions / recovery --------------------------------------

  void _clearExceptionConditions() {
    _peerReceiverBusy = false;
    _rejectException = false;
    _ownReceiverBusy = false;
    _acknowledgePending = false;
    for (var n = 0; n < 128; n++) {
      _rxdataByNs[n] = null;
    }
  }

  void _establishDataLink() {
    _clearExceptionConditions();
    _rc = 1;
    _emitPacket(_uFrame(
      _modulo == 128 ? FrameType.uFrameSabme : FrameType.uFrameSabm,
      command: true,
      pf: true,
    ));
    _stopT3();
    _startT1();
  }

  void _nrErrorRecovery() {
    _onErrorEvent('AX.25 Protocol Error J: N(R) sequence error.');
    _establishDataLink();
    _layer3Initiated = false;
  }

  void _transmitEnquiry() {
    _emitPacket(_sFrame(
      _ownReceiverBusy ? FrameType.sFrameRnr : FrameType.sFrameRr,
      command: true,
      nr: _vr,
      pf: true,
    ));
    _acknowledgePending = false;
    _startT1();
  }

  /// Send RR/RNR/SREJ response(s) to a command with the poll bit set (or on LM
  /// seize with an ack pending). Mirrors Direwolf's `enquiry_response`.
  void _enquiryResponse(int frameType, bool f) {
    if (f &&
        (frameType == FrameType.sFrameRr ||
            frameType == FrameType.sFrameRnr ||
            frameType == FrameType.iFrame)) {
      if (_ownReceiverBusy) {
        _emitPacket(_sFrame(FrameType.sFrameRnr,
            command: false, nr: _vr, pf: f));
        _acknowledgePending = false;
      } else if (_srejEnable != _SrejEnable.none) {
        // Look for out-of-sequence frames still missing and ask for them.
        var last = _mod(_vr - 1);
        while (last != _vr && _rxdataByNs[last] == null) {
          last = _mod(last - 1);
        }
        if (last != _vr) {
          final resend = <int>[];
          var j = _vr;
          while (j != last) {
            if (_rxdataByNs[j] == null) resend.add(j);
            j = _mod(j + 1);
          }
          _sendSrejFrames(resend, true);
        } else {
          _emitPacket(_sFrame(FrameType.sFrameRr,
              command: false, nr: _vr, pf: f));
          _acknowledgePending = false;
        }
      } else {
        _emitPacket(_sFrame(FrameType.sFrameRr,
            command: false, nr: _vr, pf: f));
        _acknowledgePending = false;
      }
    } else {
      _emitPacket(_sFrame(
        _ownReceiverBusy ? FrameType.sFrameRnr : FrameType.sFrameRr,
        command: false,
        nr: _vr,
        pf: f,
      ));
      _acknowledgePending = false;
    }
  }

  void _checkNeedForResponse(int frameType, bool cmd, bool pf) {
    if (cmd && pf) {
      _enquiryResponse(frameType, true);
    } else if (!cmd && pf) {
      _onErrorEvent('AX.25 Protocol Error A: F=1 received but P=1 not outstanding.');
    }
  }

  void _checkIFrameAckd(int nr) {
    if (_peerReceiverBusy) {
      _setVa(nr);
      _startT3();
      if (!_isT1Running) _startT1();
    } else if (nr == _vs) {
      _setVa(nr);
      _stopT1();
      _startT3();
      _selectT1Value();
    } else if (nr != _va) {
      _setVa(nr);
      _startT1();
    }
  }

  void _invokeRetransmission(int nrInput) {
    if (_txdataByNs[nrInput] == null) {
      _trace('invokeRetransmission: N(S)=$nrInput not available');
      return;
    }
    var localVs = nrInput;
    do {
      final txdata = _txdataByNs[localVs];
      if (txdata != null) {
        _emitPacket(_iFramePacket(
          nr: _vr,
          ns: localVs,
          p: false,
          pid: txdata.pid,
          data: txdata.data,
        ));
      }
      localVs = _mod(localVs + 1);
    } while (localVs != _vs);
  }

  // ---- selective reject -----------------------------------------------------

  void _sendSrejFrames(List<int> resend, bool allowF1) {
    if (resend.isEmpty) return;

    if (_srejEnable == _SrejEnable.multi && resend.length > 1) {
      final info = <int>[];
      for (var i = 1; i < resend.length; i++) {
        info.add(_modulo == 8 ? (resend[i] << 5) : (resend[i] << 1));
      }
      final nr = resend[0];
      final f = allowF1 && (nr == _vr);
      if (f) _acknowledgePending = false;
      _emitPacket(_sFrame(FrameType.sFrameSrej,
          command: false, nr: nr, pf: f, info: Uint8List.fromList(info)));
      return;
    }

    for (final nr in resend) {
      final f = allowF1 && (nr == _vr);
      if (f) _acknowledgePending = false;
      _emitPacket(_sFrame(FrameType.sFrameSrej,
          command: false, nr: nr, pf: f));
    }
  }

  int _resendForSrej(int nr, Uint8List? info) {
    var numResent = 0;
    var iFrameNs = nr;
    var txdata = _txdataByNs[iFrameNs];
    if (txdata != null) {
      _emitPacket(_iFramePacket(
        nr: _vr,
        ns: iFrameNs,
        p: false,
        pid: txdata.pid,
        data: txdata.data,
      ));
      numResent++;
    }
    if (info != null) {
      for (var j = 0; j < info.length; j++) {
        iFrameNs = _modulo == 8 ? ((info[j] >> 5) & 0x07) : ((info[j] >> 1) & 0x7f);
        txdata = _txdataByNs[iFrameNs];
        if (txdata != null) {
          _emitPacket(_iFramePacket(
            nr: _vr,
            ns: iFrameNs,
            p: false,
            pid: txdata.pid,
            data: txdata.data,
          ));
          numResent++;
        }
      }
    }
    return numResent;
  }

  // ---- transmit queue -------------------------------------------------------

  /// Start transmission when possible. In this port the transmitter is driven by
  /// the data broker, so we simply schedule the "seize confirm" work on a
  /// microtask (guarded so only one is pending at a time).
  void _lmSeizeRequest() {
    if (_seizePending) return;
    _seizePending = true;
    scheduleMicrotask(() {
      _seizePending = false;
      if (!_disposed) _lmSeizeConfirm();
    });
  }

  void _lmSeizeConfirm() {
    switch (_state) {
      case _DlState.connected:
      case _DlState.timerRecovery:
        _iFramePopOffQueue();
        if (_acknowledgePending) {
          _acknowledgePending = false;
          _enquiryResponse(FrameType.iFrame, false);
        }
        break;
      default:
        break;
    }
  }

  void _iFramePopOffQueue() {
    if (_iFrameQueue.isEmpty) return;

    switch (_state) {
      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        if (_layer3Initiated) {
          _iFrameQueue.removeAt(0);
        }
        break;
      case _DlState.connected:
      case _DlState.timerRecovery:
        while (!_peerReceiverBusy && _iFrameQueue.isNotEmpty && _withinWindow()) {
          final txdata = _iFrameQueue.removeAt(0);
          final ns = _vs;
          _emitPacket(_iFramePacket(
            nr: _vr,
            ns: ns,
            p: false,
            pid: txdata.pid,
            data: txdata.data,
          ));
          _txdataByNs[ns] = txdata;
          _vs = _mod(_vs + 1);
          _acknowledgePending = false;
          _stopT3();
          _startT1();
        }
        break;
      default:
        break;
    }
  }

  void _discardIQueue() {
    _iFrameQueue.clear();
  }

  /// Append a block to the I-frame queue (respecting current state) and kick the
  /// transmitter. Mirrors Direwolf's `data_request_good_size`.
  void _dataRequestGoodSize(_Cdata txdata) {
    switch (_state) {
      case _DlState.disconnected:
      case _DlState.awaitingRelease:
        return; // discard
      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        if (_layer3Initiated) return; // discard
        _iFrameQueue.add(txdata);
        break;
      case _DlState.connected:
      case _DlState.timerRecovery:
        _iFrameQueue.add(txdata);
        break;
    }

    if ((_state == _DlState.connected || _state == _DlState.timerRecovery) &&
        !_peerReceiverBusy &&
        _withinWindow()) {
      _acknowledgePending = true;
      _lmSeizeRequest();
    }
  }

  // ---- data delivery / reassembly -------------------------------------------

  void _dlDataIndication(int pid, Uint8List data) {
    if (_raData == null) {
      // Ready state.
      if (pid != _pidSegmentationFragment) {
        _onDataReceivedEvent(data);
        return;
      } else if (data.isNotEmpty && (data[0] & 0x80) != 0) {
        // First segment.
        _raFollowing = data[0] & 0x7f;
        final total = (_raFollowing + 1) * (data.length - 1) - 1;
        _raSize = total < 0 ? 0 : total;
        _raData = Uint8List(_raSize);
        _raLen = data.length - 2;
        if (_raLen > 0) {
          _raData!.setRange(0, _raLen, data.sublist(2));
        }
      } else {
        _onErrorEvent('AX.25 Reassembler Protocol Error Z: Not first segment in ready state.');
      }
    } else {
      // Reassembling state.
      if (pid != _pidSegmentationFragment) {
        _onDataReceivedEvent(data);
        _onErrorEvent('AX.25 Reassembler Protocol Error Z: Not segment in reassembling state.');
        _raData = null;
        return;
      } else if (data.isNotEmpty && (data[0] & 0x80) != 0) {
        _onErrorEvent('AX.25 Reassembler Protocol Error Z: First segment in reassembling state.');
        _raData = null;
        return;
      } else if (data.isEmpty || (data[0] & 0x7f) != _raFollowing - 1) {
        _onErrorEvent('AX.25 Reassembler Protocol Error Z: Segments out of sequence.');
        _raData = null;
        return;
      } else {
        _raFollowing = data[0] & 0x7f;
        if (_raLen + data.length - 1 <= _raSize) {
          _raData!.setRange(_raLen, _raLen + data.length - 1, data.sublist(1));
          _raLen += data.length - 1;
        } else {
          _onErrorEvent('AX.25 Reassembler Protocol Error Z: Segments exceed buffer space.');
          _raData = null;
          return;
        }
        if (_raFollowing == 0) {
          _onDataReceivedEvent(Uint8List.sublistView(_raData!, 0, _raLen));
          _raData = null;
        }
      }
    }
  }

  // ---- public API: connect / disconnect / send ------------------------------

  /// Initiates a connection to a remote station.
  ///
  /// [addrs] must contain at least the destination/peer (index 0) and
  /// source/own (index 1) addresses, with optional digipeaters following.
  /// Returns `true` if a connection attempt was started, or `false` if already
  /// connected/connecting or the addresses are invalid.
  bool connect(List<AX25Address> addrs) {
    _trace('Connect');
    if (currentState != AX25ConnectionState.disconnected) return false;
    if (addrs.length < 2) return false;

    addresses = addrs;
    _resetLinkVariables();
    _initT1vSrt();

    if (modulo128 && maxV22 > 0) {
      _setVersion22();
      _establishDataLink();
      _layer3Initiated = true;
      _enterNewState(_DlState.awaitingV22Connection);
    } else {
      _setVersion20();
      _establishDataLink();
      _layer3Initiated = true;
      _enterNewState(_DlState.awaitingConnection);
    }
    return true;
  }

  /// Initiates a disconnection from the remote station.
  void disconnect() {
    _trace('Disconnect');
    switch (_state) {
      case _DlState.disconnected:
        return;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        _discardIQueue();
        _rc = 0;
        _emitPacket(_uFrame(FrameType.uFrameDisc, command: true, pf: true));
        _stopT1();
        _stopT3();
        _enterNewState(_DlState.disconnected);
        _dlConnectionTerminated();
        break;

      case _DlState.awaitingRelease:
        _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: false));
        _stopT1();
        _enterNewState(_DlState.disconnected);
        _dlConnectionTerminated();
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _discardIQueue();
        _rc = 0;
        _emitPacket(_uFrame(FrameType.uFrameDisc, command: true, pf: true));
        _stopT3();
        _startT1();
        _enterNewState(_DlState.awaitingRelease);
        break;
    }
  }

  /// Sends [info] over the connection as a UTF-8 encoded string.
  void sendString(String info) {
    send(Uint8List.fromList(utf8.encode(info)));
  }

  /// Sends [info] over the connection. Data larger than [packetLength] is split
  /// into multiple I-frames (v2.0) or v2.2 segmentation fragments (v2.2), then
  /// queued for transmission.
  void send(Uint8List info) {
    _trace('Send (${info.length} bytes)');
    if (info.isEmpty) return;
    if (addresses == null) return;
    _dlDataRequest(_pidNoLayer3, info);
  }

  void _dlDataRequest(int pid, Uint8List data) {
    if (data.length <= _n1Paclen) {
      _dataRequestGoodSize(_Cdata(pid, Uint8List.fromList(data)));
      return;
    }

    if (_modulo == 8) {
      // v2.0: just split into multiple I-frames not exceeding N1.
      var offset = 0;
      while (offset < data.length) {
        final thisLen = math.min(_n1Paclen, data.length - offset);
        _dataRequestGoodSize(
          _Cdata(pid, Uint8List.fromList(data.sublist(offset, offset + thisLen))),
        );
        offset += thisLen;
      }
      return;
    }

    // v2.2 segmentation using PID 0x08.
    var nsegToFollow = ((data.length + 1) + (_n1Paclen - 1) - 1) ~/ (_n1Paclen - 1);
    if (nsegToFollow < 2 || nsegToFollow > 128) {
      _dataRequestGoodSize(_Cdata(pid, Uint8List.fromList(data)));
      return;
    }

    var offset = 0;
    var remaining = data.length;

    // First segment: header (0x80 | segments-to-follow), original PID, data.
    nsegToFollow--;
    var seglen = math.min(_n1Paclen - 2, remaining);
    final first = BytesBuilder();
    first.addByte(0x80 | nsegToFollow);
    first.addByte(pid);
    first.add(data.sublist(offset, offset + seglen));
    _dataRequestGoodSize(_Cdata(_pidSegmentationFragment, first.toBytes()));
    offset += seglen;
    remaining -= seglen;

    // Subsequent segments: header (segments-to-follow), data.
    do {
      nsegToFollow--;
      seglen = math.min(_n1Paclen - 1, remaining);
      final seg = BytesBuilder();
      seg.addByte(nsegToFollow);
      seg.add(data.sublist(offset, offset + seglen));
      _dataRequestGoodSize(_Cdata(_pidSegmentationFragment, seg.toBytes()));
      offset += seglen;
      remaining -= seglen;
    } while (nsegToFollow > 0);
  }

  void _resetLinkVariables() {
    _vs = 0;
    _va = 0;
    _vr = 0;
    _rc = 0;
    _layer3Initiated = false;
    _peerReceiverBusy = false;
    _rejectException = false;
    _ownReceiverBusy = false;
    _acknowledgePending = false;
    _mdlState = 0;
    _mdlRc = 0;
    _iFrameQueue.clear();
    for (var n = 0; n < 128; n++) {
      _txdataByNs[n] = null;
      _rxdataByNs[n] = null;
    }
    _raData = null;
  }

  void _dlConnectionTerminated() {
    _discardIQueue();
    for (var n = 0; n < 128; n++) {
      _txdataByNs[n] = null;
      _rxdataByNs[n] = null;
    }
    _raData = null;
    _stopT1();
    _stopT3();
    _stopTm201();
    _maybeStopTicker();
  }

  // ---- timer expiry handlers ------------------------------------------------

  void _t1Expiry() {
    _trace('T1 expired (state=$_state, rc=$_rc)');
    switch (_state) {
      case _DlState.disconnected:
        break;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        if (_state == _DlState.awaitingV22Connection && _rc == maxV22) {
          _setVersion20();
          _enterNewState(_DlState.awaitingConnection);
        }
        if (_rc == _n2Retry) {
          _discardIQueue();
          _onErrorEvent('Failed to connect after $_n2Retry tries.');
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        } else {
          _rc++;
          _emitPacket(_uFrame(
            _state == _DlState.awaitingV22Connection
                ? FrameType.uFrameSabme
                : FrameType.uFrameSabm,
            command: true,
            pf: true,
          ));
          _selectT1Value();
          _startT1();
        }
        break;

      case _DlState.awaitingRelease:
        if (_rc == _n2Retry) {
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        } else {
          _rc++;
          _emitPacket(_uFrame(FrameType.uFrameDisc, command: true, pf: true));
          _selectT1Value();
          _startT1();
        }
        break;

      case _DlState.connected:
        _rc = 1;
        _transmitEnquiry();
        _enterNewState(_DlState.timerRecovery);
        break;

      case _DlState.timerRecovery:
        if (_rc == _n2Retry) {
          if (_va != _vs) {
            _onErrorEvent('AX.25 Protocol Error I: $_n2Retry timeouts: unacknowledged sent data.');
          } else if (_peerReceiverBusy) {
            _onErrorEvent('AX.25 Protocol Error U: $_n2Retry timeouts: extended peer busy condition.');
          } else {
            _onErrorEvent('AX.25 Protocol Error T: $_n2Retry timeouts: no response to enquiry.');
          }
          _discardIQueue();
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: false));
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        } else {
          _rc++;
          _transmitEnquiry();
        }
        break;
    }
  }

  void _t3Expiry() {
    _trace('T3 expired (state=$_state)');
    if (_state == _DlState.connected) {
      _rc = 1;
      _transmitEnquiry();
      _enterNewState(_DlState.timerRecovery);
    }
  }

  void _tm201Expiry() {
    if (_mdlState != 1) return;
    _mdlRc++;
    if (_mdlRc > _n2Retry) {
      _onErrorEvent('AX.25 Protocol Error MDL-C: Management retry limit exceeded.');
      _mdlState = 0;
    }
    // XID negotiation is simplified in this port; nothing further to send.
  }

  // ---- frame reception ------------------------------------------------------

  /// Processes a received AX.25 [packet]. Called internally when
  /// `UniqueDataFrame` events arrive, but may also be called directly. Returns
  /// `true` if the packet belonged to this session, `false` otherwise.
  bool receive(AX25Packet packet) {
    if (_disposed) return false;
    if (packet.addresses.length < 2) return false;
    _trace('Receive ${packet.frameTypeName}');

    final cmd = packet.command;
    final pf = packet.pollFinal;
    final nr = packet.nr;
    final ns = packet.ns;
    final type = packet.type;

    final addrs = addresses;

    // Ignore packets from a station other than the one this session is bound to.
    if (addrs != null &&
        packet.addresses[1].callSignWithId != addrs[0].callSignWithId) {
      _trace('Ignoring packet from ${packet.addresses[1].callSignWithId}');
      return false;
    }

    // No active link yet.
    if (addrs == null) {
      if (type == FrameType.uFrameSabm || type == FrameType.uFrameSabme) {
        // Accept an incoming connection: bind to the calling station.
        final peer = AX25Address.parse(packet.addresses[1].toString());
        final us = AX25Address.getAddress(sessionCallsign, sessionStationId);
        if (peer == null || us == null) return false;
        addresses = [peer, us];
        _resetLinkVariables();
        _initT1vSrt();
      } else {
        // Respond with DM (or UA to a DISC) using swapped addresses.
        final peer = AX25Address.parse(packet.addresses[1].toString());
        final us = AX25Address.getAddress(sessionCallsign, sessionStationId);
        if (peer == null || us == null) return false;
        addresses = [peer, us];
        _emitPacket(_uFrame(
          type == FrameType.uFrameDisc ? FrameType.uFrameUa : FrameType.uFrameDm,
          command: false,
          pf: true,
        ));
        addresses = null;
        return false;
      }
    }

    switch (type) {
      case FrameType.iFrame:
        _iFrame(cmd, pf, nr, ns, packet.pid, packet.data ?? Uint8List(0));
        break;
      case FrameType.sFrameRr:
        _rrRnrFrame(true, cmd, pf, nr);
        break;
      case FrameType.sFrameRnr:
        _rrRnrFrame(false, cmd, pf, nr);
        break;
      case FrameType.sFrameRej:
        _rejFrame(cmd, pf, nr);
        break;
      case FrameType.sFrameSrej:
        _srejFrame(cmd, pf, nr, packet.data);
        break;
      case FrameType.uFrameSabme:
        _sabmEFrame(true, pf);
        break;
      case FrameType.uFrameSabm:
        _sabmEFrame(false, pf);
        break;
      case FrameType.uFrameDisc:
        _discFrame(pf);
        break;
      case FrameType.uFrameDm:
        _dmFrame(pf);
        break;
      case FrameType.uFrameUa:
        _uaFrame(pf);
        break;
      case FrameType.uFrameFrmr:
        _frmrFrame();
        break;
      case FrameType.uFrameUi:
        _uiFrame(cmd, pf, packet.data);
        break;
      case FrameType.uFrameXid:
        _xidFrame(cmd, pf);
        break;
      case FrameType.uFrameTest:
        _testFrame(cmd, pf, packet.data);
        break;
      default:
        break;
    }

    // A received frame may have acked our data or cleared peer-busy. Kick the
    // transmitter if we now have data to send.
    if (_iFrameQueue.isNotEmpty &&
        (_state == _DlState.connected || _state == _DlState.timerRecovery) &&
        !_peerReceiverBusy &&
        _withinWindow()) {
      _lmSeizeRequest();
    }

    return true;
  }

  int get _recoveryState => _modulo == 128 ? 5 : 1;

  void _enterRecoveryAwaiting() {
    _enterNewState(_recoveryState == 5
        ? _DlState.awaitingV22Connection
        : _DlState.awaitingConnection);
  }

  // ---- I-frame --------------------------------------------------------------

  void _iFrame(bool cmd, bool p, int nr, int ns, int pid, Uint8List info) {
    switch (_state) {
      case _DlState.disconnected:
        if (cmd) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: p));
        }
        break;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        break;

      case _DlState.awaitingRelease:
        if (cmd && p) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: true));
        }
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        if (info.length <= _ax25MaxInfoLen) {
          if (_isGoodNr(nr)) {
            _checkIFrameAckd(nr);

            if (_state == _DlState.timerRecovery && _va == _vs) {
              _stopT1();
              _selectT1Value();
              _startT3();
              _rc = 0;
              _enterNewState(_DlState.connected);
            }

            if (_ownReceiverBusy) {
              if (p) {
                _emitPacket(_sFrame(FrameType.sFrameRnr,
                    command: false, nr: _vr, pf: true));
                _acknowledgePending = false;
              }
            } else {
              _iFrameContinued(p, ns, pid, info);
            }
          } else {
            _nrErrorRecovery();
            _enterRecoveryAwaiting();
          }
        } else {
          _onErrorEvent('AX.25 Protocol Error O: Information part length $info.length out of range.');
          _establishDataLink();
          _layer3Initiated = false;
          _enterRecoveryAwaiting();
        }
        break;
    }
  }

  void _iFrameContinued(bool p, int ns, int pid, Uint8List info) {
    if (ns == _vr) {
      _vr = _mod(_vr + 1);
      _rejectException = false;
      _dlDataIndication(pid, info);

      _rxdataByNs[ns] = null;

      while (_rxdataByNs[_vr] != null) {
        final buffered = _rxdataByNs[_vr]!;
        _dlDataIndication(buffered.pid, buffered.data);
        _rxdataByNs[_vr] = null;
        _vr = _mod(_vr + 1);
      }

      if (p) {
        _emitPacket(_sFrame(FrameType.sFrameRr,
            command: false, nr: _vr, pf: true));
        _acknowledgePending = false;
      } else if (!_acknowledgePending) {
        _acknowledgePending = true;
        _lmSeizeRequest();
      }
    } else if (_rejectException) {
      if (p) {
        _emitPacket(_sFrame(FrameType.sFrameRr,
            command: false, nr: _vr, pf: true));
        _acknowledgePending = false;
      }
    } else if (_srejEnable == _SrejEnable.none) {
      _rejectException = true;
      _emitPacket(_sFrame(FrameType.sFrameRej,
          command: false, nr: _vr, pf: p));
      _acknowledgePending = false;
    } else {
      // Selective reject enabled (v2.2 modulo 128).
      if (_isNsInWindow(ns)) {
        _rxdataByNs[ns] = _Cdata(pid, Uint8List.fromList(info));

        if (p) {
          _enquiryResponse(FrameType.iFrame, true);
        } else if (_ownReceiverBusy) {
          _emitPacket(_sFrame(FrameType.sFrameRnr,
              command: false, nr: _vr, pf: false));
        } else if (_rxdataByNs[_mod(ns - 1)] == null) {
          // Ask for the gap (this transmission only, not cumulative).
          const allowF1 = true;
          final last = _mod(ns - 1);
          var firstMissing = last;
          while (firstMissing != _vr && _rxdataByNs[_mod(firstMissing - 1)] == null) {
            firstMissing = _mod(firstMissing - 1);
          }
          final resend = <int>[];
          var x = firstMissing;
          final stop = _mod(last + 1);
          do {
            resend.add(_mod(x));
            x = _mod(x + 1);
          } while (x != stop);
          _sendSrejFrames(resend, allowF1);
        }
      } else {
        // Out of range; discard, respond if polled.
        if (p) {
          _enquiryResponse(FrameType.iFrame, true);
        }
      }
    }
  }

  // ---- RR / RNR -------------------------------------------------------------

  void _rrRnrFrame(bool ready, bool cmd, bool pf, int nr) {
    switch (_state) {
      case _DlState.disconnected:
        if (cmd) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: pf));
        }
        break;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        break;

      case _DlState.awaitingRelease:
        if (cmd && pf) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: true));
        }
        break;

      case _DlState.connected:
        _peerReceiverBusy = !ready;
        if (cmd && pf) {
          _checkNeedForResponse(
              ready ? FrameType.sFrameRr : FrameType.sFrameRnr, cmd, pf);
        }
        if (_isGoodNr(nr)) {
          _checkIFrameAckd(nr);
        } else {
          _nrErrorRecovery();
          _enterRecoveryAwaiting();
        }
        break;

      case _DlState.timerRecovery:
        _peerReceiverBusy = !ready;
        if (!cmd && pf) {
          // Response with F=1.
          _stopT1();
          _selectT1Value();
          if (_isGoodNr(nr)) {
            _setVa(nr);
            if (_vs == _va) {
              _startT3();
              _rc = 0;
              _enterNewState(_DlState.connected);
            } else {
              _invokeRetransmission(nr);
              _stopT3();
              _startT1();
              _acknowledgePending = false;
            }
          } else {
            _nrErrorRecovery();
            _enterRecoveryAwaiting();
          }
        } else {
          if (cmd && pf) {
            _enquiryResponse(
                ready ? FrameType.sFrameRr : FrameType.sFrameRnr, true);
          }
          if (_isGoodNr(nr)) {
            _setVa(nr);
            if (!cmd && !pf) {
              if (_vs == _va) {
                _stopT1();
                _selectT1Value();
                _startT3();
                _rc = 0;
                _enterNewState(_DlState.connected);
              }
            }
          } else {
            _nrErrorRecovery();
            _enterRecoveryAwaiting();
          }
        }
        break;
    }
  }

  // ---- REJ ------------------------------------------------------------------

  void _rejFrame(bool cmd, bool pf, int nr) {
    switch (_state) {
      case _DlState.disconnected:
        if (cmd) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: pf));
        }
        break;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        break;

      case _DlState.awaitingRelease:
        if (cmd && pf) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: true));
        }
        break;

      case _DlState.connected:
        _peerReceiverBusy = false;
        _checkNeedForResponse(FrameType.sFrameRej, cmd, pf);
        if (_isGoodNr(nr)) {
          _setVa(nr);
          _stopT1();
          _stopT3();
          _selectT1Value();
          _invokeRetransmission(nr);
          _startT1();
          _acknowledgePending = false;
        } else {
          _nrErrorRecovery();
          _enterRecoveryAwaiting();
        }
        break;

      case _DlState.timerRecovery:
        _peerReceiverBusy = false;
        if (!cmd && pf) {
          _stopT1();
          _selectT1Value();
          if (_isGoodNr(nr)) {
            _setVa(nr);
            if (_vs == _va) {
              _startT3();
              _rc = 0;
              _enterNewState(_DlState.connected);
            } else {
              _invokeRetransmission(nr);
              _stopT3();
              _startT1();
              _acknowledgePending = false;
            }
          } else {
            _nrErrorRecovery();
            _enterRecoveryAwaiting();
          }
        } else {
          if (cmd && pf) {
            _enquiryResponse(FrameType.sFrameRej, true);
          }
          if (_isGoodNr(nr)) {
            _setVa(nr);
            if (_vs != _va) {
              _invokeRetransmission(nr);
              _stopT3();
              _startT1();
              _acknowledgePending = false;
            }
          } else {
            _nrErrorRecovery();
            _enterRecoveryAwaiting();
          }
        }
        break;
    }
  }

  // ---- SREJ -----------------------------------------------------------------

  void _srejFrame(bool cmd, bool f, int nr, Uint8List? info) {
    switch (_state) {
      case _DlState.disconnected:
      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
      case _DlState.awaitingRelease:
        break;

      case _DlState.connected:
        _peerReceiverBusy = false;
        if (_isGoodNr(nr)) {
          if (f) _setVa(nr);
          _stopT1();
          _startT3();
          _selectT1Value();
          final numResent = _resendForSrej(nr, info);
          if (numResent > 0) {
            _stopT3();
            _startT1();
            _acknowledgePending = false;
          }
        } else {
          _nrErrorRecovery();
          _enterRecoveryAwaiting();
        }
        break;

      case _DlState.timerRecovery:
        _peerReceiverBusy = false;
        _stopT1();
        _selectT1Value();
        if (_isGoodNr(nr)) {
          if (f) _setVa(nr);
          if (_vs == _va) {
            _startT3();
            _rc = 0;
            _enterNewState(_DlState.connected);
          } else {
            final numResent = _resendForSrej(nr, info);
            if (numResent > 0) {
              _stopT3();
              _startT1();
              _acknowledgePending = false;
            }
          }
        } else {
          _nrErrorRecovery();
          _enterRecoveryAwaiting();
        }
        break;
    }
  }

  // ---- SABM / SABME ---------------------------------------------------------

  void _sabmEFrame(bool extended, bool p) {
    switch (_state) {
      case _DlState.disconnected:
        if (extended) {
          _setVersion22();
        } else {
          _setVersion20();
        }
        _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        _clearExceptionConditions();
        _vs = 0;
        _va = 0;
        _vr = 0;
        _initT1vSrt();
        _startT3();
        _rc = 0;
        _enterNewState(_DlState.connected);
        break;

      case _DlState.awaitingConnection:
        if (extended) {
          _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: p));
          _enterNewState(_DlState.awaitingV22Connection);
        } else {
          _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        }
        break;

      case _DlState.awaitingV22Connection:
        _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        if (!extended) {
          _enterNewState(_DlState.awaitingConnection);
        }
        break;

      case _DlState.awaitingRelease:
        _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: p));
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        if (_state == _DlState.timerRecovery) {
          if (extended) {
            _setVersion22();
          } else {
            _setVersion20();
          }
        }
        _clearExceptionConditions();
        _onErrorEvent('AX.25 Protocol Error F: Data Link reset; SABM(E) received while connected.');
        if (_vs != _va) {
          _discardIQueue();
        }
        _stopT1();
        _startT3();
        _vs = 0;
        _va = 0;
        _vr = 0;
        _rc = 0;
        _enterNewState(_DlState.connected);
        break;
    }
  }

  // ---- DISC -----------------------------------------------------------------

  void _discFrame(bool p) {
    switch (_state) {
      case _DlState.disconnected:
      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: p));
        break;

      case _DlState.awaitingRelease:
        _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _discardIQueue();
        _emitPacket(_uFrame(FrameType.uFrameUa, command: false, pf: p));
        _stopT1();
        _stopT3();
        _enterNewState(_DlState.disconnected);
        _dlConnectionTerminated();
        break;
    }
  }

  // ---- DM -------------------------------------------------------------------

  void _dmFrame(bool f) {
    switch (_state) {
      case _DlState.disconnected:
        break;

      case _DlState.awaitingConnection:
        if (f) {
          _discardIQueue();
          _stopT1();
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        }
        break;

      case _DlState.awaitingRelease:
        if (f) {
          _stopT1();
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        }
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _onErrorEvent('AX.25 Protocol Error E: DM received while connected.');
        _discardIQueue();
        _stopT1();
        _stopT3();
        _enterNewState(_DlState.disconnected);
        _dlConnectionTerminated();
        break;

      case _DlState.awaitingV22Connection:
        // Peer doesn't understand v2.2 (some TNCs answer SABME with DM). Fall
        // back to v2.0 instead of failing.
        if (f) {
          _trace('Peer does not understand AX.25 v2.2, trying v2.0');
          _initT1vSrt();
          _setVersion20();
          _establishDataLink();
          _layer3Initiated = true;
          _enterNewState(_DlState.awaitingConnection);
        }
        break;
    }
  }

  // ---- UA -------------------------------------------------------------------

  void _uaFrame(bool f) {
    switch (_state) {
      case _DlState.disconnected:
        _onErrorEvent('AX.25 Protocol Error C: Unexpected UA in disconnected state.');
        break;

      case _DlState.awaitingConnection:
      case _DlState.awaitingV22Connection:
        if (f) {
          if (_layer3Initiated) {
            // Connection confirmed.
          } else if (_vs != _va) {
            _initT1vSrt();
            _startT3();
          }
          _stopT1();
          _startT3();
          _vs = 0;
          _va = 0;
          _vr = 0;
          _selectT1Value();
          if (_state == _DlState.awaitingV22Connection) {
            _mdlNegotiateRequest();
          }
          _rc = 0;
          _enterNewState(_DlState.connected);
        } else {
          _onErrorEvent('AX.25 Protocol Error D: UA received without F=1.');
        }
        break;

      case _DlState.awaitingRelease:
        if (f) {
          _stopT1();
          _enterNewState(_DlState.disconnected);
          _dlConnectionTerminated();
        } else {
          _onErrorEvent('AX.25 Protocol Error D: UA received without F=1.');
        }
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _onErrorEvent('AX.25 Protocol Error C: Unexpected UA while connected.');
        _establishDataLink();
        _layer3Initiated = false;
        _enterRecoveryAwaiting();
        break;
    }
  }

  // ---- FRMR -----------------------------------------------------------------

  void _frmrFrame() {
    switch (_state) {
      case _DlState.disconnected:
      case _DlState.awaitingConnection:
      case _DlState.awaitingRelease:
        break;

      case _DlState.connected:
      case _DlState.timerRecovery:
        _onErrorEvent('AX.25 Protocol Error K: FRMR not expected while connected.');
        _setVersion20();
        _establishDataLink();
        _layer3Initiated = false;
        _enterNewState(_DlState.awaitingConnection);
        break;

      case _DlState.awaitingV22Connection:
        _trace('Peer does not understand AX.25 v2.2 (FRMR), trying v2.0');
        _initT1vSrt();
        _setVersion20();
        _establishDataLink();
        _layer3Initiated = true;
        _enterNewState(_DlState.awaitingConnection);
        break;
    }

    if (_mdlState == 1) {
      _setVersion20();
      _mdlState = 0;
    }
  }

  // ---- UI -------------------------------------------------------------------

  void _uiFrame(bool cmd, bool pf, Uint8List? info) {
    // Deliver connectionless data to the application, preserving the behavior
    // relied upon by the rest of the app.
    if (info != null && info.isNotEmpty) {
      _onUiDataReceivedEvent(info);
    }

    if (cmd && pf) {
      switch (_state) {
        case _DlState.disconnected:
        case _DlState.awaitingConnection:
        case _DlState.awaitingRelease:
        case _DlState.awaitingV22Connection:
          if (addresses != null) {
            _emitPacket(_uFrame(FrameType.uFrameDm, command: false, pf: pf));
          }
          break;
        case _DlState.connected:
        case _DlState.timerRecovery:
          _enquiryResponse(FrameType.uFrameUi, pf);
          break;
      }
    }
  }

  // ---- XID (simplified) -----------------------------------------------------

  void _xidFrame(bool cmd, bool pf) {
    // The AX25Packet layer has no XID information-field codec, so this port does
    // not perform a full ISO 8885 parameter exchange. We answer an incoming XID
    // command politely (accepting current/default parameters) and treat an XID
    // response as completing negotiation. See the class doc comment.
    switch (_mdlState) {
      case 0: // ready
        if (cmd) {
          if (pf) {
            _emitPacket(_uFrame(FrameType.uFrameXid, command: false, pf: true));
          } else {
            _onErrorEvent('AX.25 Protocol Error MDL-A: XID command without P=1.');
          }
        } else {
          _onErrorEvent('AX.25 Protocol Error MDL-B: Unexpected XID response.');
        }
        break;
      case 1: // negotiating
        if (!cmd) {
          if (pf) {
            _mdlState = 0;
            _stopTm201();
          } else {
            _onErrorEvent('AX.25 Protocol Error MDL-D: XID response without F=1.');
          }
        }
        break;
    }
  }

  void _mdlNegotiateRequest() {
    // Simplified: v2.2 links operate with the defaults chosen by
    // [_setVersion22] (single selective reject, k = maxFramesExtended). We do
    // not send an XID command because the frame layer cannot build the
    // parameter information field. This is the one intentional deviation from
    // the Direwolf port.
  }

  // ---- TEST -----------------------------------------------------------------

  void _testFrame(bool cmd, bool pf, Uint8List? info) {
    if (cmd) {
      _emitPacket(_uFrame(FrameType.uFrameTest, command: false, pf: pf, info: info));
    }
  }

  // ---- disposal -------------------------------------------------------------

  /// Disposes the session, stopping all timers and unsubscribing from the
  /// DataBroker.
  void dispose() {
    if (_disposed) return;
    _broker.logInfo(
      '[AX25Session] Session disposing for radio device $_radioDeviceId',
    );
    _ticker?.cancel();
    _ticker = null;
    _t1Exp = 0;
    _t3Exp = 0;
    _tm201Exp = 0;
    _iFrameQueue.clear();
    for (var n = 0; n < 128; n++) {
      _txdataByNs[n] = null;
      _rxdataByNs[n] = null;
    }
    _raData = null;
    addresses = null;
    sessionState.clear();
    _disposed = true;
    _broker.dispose();
  }
}
