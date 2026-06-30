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
/// The integer values match the C# `AX25Session.ConnectionState` enum.
enum AX25ConnectionState {
  disconnected, // 1
  connected, // 2
  connecting, // 3
  disconnecting, // 4
}

/// Identifies the protocol timers used by the session.
enum _TimerName { connect, disconnect, t1, t2, t3 }

/// Signature for the connection-state-changed callback.
typedef AX25StateChangedHandler =
    void Function(AX25Session sender, AX25ConnectionState state);

/// Signature for received-data callbacks (I-frame and UI-frame).
typedef AX25DataReceivedHandler =
    void Function(AX25Session sender, Uint8List data);

/// Signature for the error callback.
typedef AX25ErrorHandler = void Function(AX25Session sender, String error);

/// Implements the AX.25 data link layer protocol for connected-mode
/// communication. This is a direct port of the C# `AX25Session` class.
///
/// The session uses the [DataBroker] to send and receive packets through a
/// specified radio device:
///   * It subscribes to `UniqueDataFrame` events (which carry a
///     [TncDataFragment]) and decodes incoming AX.25 frames.
///   * It transmits frames by dispatching `TransmitDataFrame`.
///
/// Both standard (modulo-8) and extended (modulo-128) sequence numbering are
/// supported. Call [connect] to initiate a connection, [send] to transmit data
/// once connected, and [disconnect] to tear the link down. Subscribe to
/// [onStateChanged], [onDataReceived], [onUiDataReceived] and [onError] to
/// observe session activity. Always call [dispose] when finished.
class AX25Session {
  final DataBrokerClient _broker = DataBrokerClient();
  final int _radioDeviceId;
  bool _disposed = false;

  /// Custom session state for storing application-specific data. Cleared when
  /// the session disconnects.
  final Map<String, Object?> sessionState = {};

  /// Raised when the connection state changes.
  AX25StateChangedHandler? onStateChanged;

  /// Raised when I-frame data is received from the remote station.
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

  // ---- tunable protocol parameters (defaults match the C# version) ----------

  /// Maximum number of outstanding I-frames (window size).
  int maxFrames = 4;

  /// Maximum size of the data payload in each I-frame.
  int packetLength = 256;

  /// Number of retries before giving up on a connection.
  int retries = 3;

  /// Baud rate used for timeout calculations.
  int hBaud = 1200;

  /// Use modulo-128 mode (extended sequence numbers, up to 127 outstanding
  /// frames).
  bool modulo128 = false;

  /// Enable trace logging for debugging.
  bool tracing = true;

  /// The list of addresses for this session: destination (index 0), source
  /// (index 1), and optional digipeaters.
  List<AX25Address>? addresses;

  final _SessionState _state = _SessionState();
  final _SessionTimers _timers = _SessionTimers();

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

  /// The current connection state of the session.
  AX25ConnectionState get currentState => _state.connection;

  /// The number of packets awaiting transmission or acknowledgment.
  int get sendBufferLength => _state.sendBuffer.length;

  /// The number of out-of-order packets buffered for reordering.
  int get receiveBufferLength => _state.receiveBuffer.length;

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

  void _setConnectionState(AX25ConnectionState state) {
    if (state != _state.connection) {
      _state.connection = state;
      _onStateChangedEvent(state);
      if (state == AX25ConnectionState.disconnected) {
        _state.sendBuffer.clear();
        _state.receiveBuffer.clear();
        addresses = null;
        sessionState.clear();
      }
    }
  }

  // ---- incoming frames ------------------------------------------------------

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;
    // Only process frames from our radio device.
    if (data.radioDeviceId != _radioDeviceId) return;
    // Skip our own outgoing packets - only process incoming frames.
    if (!data.incoming) return;

    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    receive(packet);
  }

  /// Transmits an AX.25 packet via the DataBroker to the associated radio.
  void _emitPacket(AX25Packet packet) {
    _trace('EmitPacket');
    // The Flutter `RadioLockState` does not carry channel/region, so transmit
    // with -1 (meaning "use the radio's current channel/region"), consistent
    // with the rest of the app's transmit paths.
    _broker.dispatch(
      deviceId: _radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(packet: packet, channelId: -1, regionId: -1),
      store: false,
    );
  }

  // ---- timeouts -------------------------------------------------------------

  int get _modulus => modulo128 ? 128 : 8;

  // Milliseconds required to transmit the largest possible packet.
  int _getMaxPacketTime() {
    return ((600 + (packetLength * 8)) / hBaud * 1000).floor();
  }

  // Gives the TNC time to finish transmitting queued packets before a response
  // is expected from the remote side.
  int _getTimeout() {
    int multiplier = 0;
    for (final packet in _state.sendBuffer) {
      if (packet.sent) multiplier++;
    }
    final addrCount = addresses?.length ?? 2;
    final int addrFactor = math.max(1, addrCount - 2);
    final int sentFactor = math.max(1, multiplier);
    return (_getMaxPacketTime() * addrFactor * 4) +
        (_getMaxPacketTime() * sentFactor);
  }

  double _getTimerTimeout(_TimerName timerName) {
    switch (timerName) {
      case _TimerName.connect:
        return _getTimeout().toDouble();
      case _TimerName.disconnect:
        return _getTimeout().toDouble();
      case _TimerName.t1:
        return _getTimeout().toDouble();
      case _TimerName.t2:
        return (_getMaxPacketTime() * 2).toDouble();
      case _TimerName.t3:
        return (_getTimeout() * 7).toDouble();
    }
  }

  void _setTimer(_TimerName timerName) {
    _clearTimer(timerName);
    if (addresses == null) return;

    final ms = _getTimerTimeout(timerName).round();
    _trace('SetTimer $timerName to ${ms}ms');
    final duration = Duration(milliseconds: ms < 1 ? 1 : ms);
    final timer = Timer(duration, () => _onTimerElapsed(timerName));
    _timers.set(timerName, timer);
  }

  void _clearTimer(_TimerName timerName) {
    _trace('ClearTimer $timerName');
    _timers.cancel(timerName);
    switch (timerName) {
      case _TimerName.connect:
        _timers.connectAttempts = 0;
        break;
      case _TimerName.disconnect:
        _timers.disconnectAttempts = 0;
        break;
      case _TimerName.t1:
        _timers.t1Attempts = 0;
        break;
      case _TimerName.t3:
        _timers.t3Attempts = 0;
        break;
      case _TimerName.t2:
        break;
    }
  }

  bool _isTimerEnabled(_TimerName timerName) => _timers.isActive(timerName);

  void _onTimerElapsed(_TimerName timerName) {
    if (_disposed) return;
    // The timer has fired; mark it inactive (these behave as one-shots that are
    // explicitly re-armed, matching the C# restart-on-each-cycle usage).
    _timers.markFired(timerName);
    switch (timerName) {
      case _TimerName.connect:
        _connectTimerCallback();
        break;
      case _TimerName.disconnect:
        _disconnectTimerCallback();
        break;
      case _TimerName.t1:
        _t1TimerCallback();
        break;
      case _TimerName.t2:
        _t2TimerCallback();
        break;
      case _TimerName.t3:
        _t3TimerCallback();
        break;
    }
  }

  // ---- acknowledgment / send bookkeeping ------------------------------------

  void _receiveAcknowledgement(AX25Packet packet) {
    _trace('ReceiveAcknowledgement');
    for (int p = 0; p < _state.sendBuffer.length; p++) {
      if (_state.sendBuffer[p].sent &&
          (_state.sendBuffer[p].ns != packet.nr) &&
          (_distanceBetween(packet.nr, _state.sendBuffer[p].ns, _modulus) <=
              maxFrames)) {
        _state.sendBuffer.removeAt(p);
        p--;
      }
    }
    _state.remoteReceiveSequence = packet.nr;
  }

  void _sendRR(bool pollFinal) {
    _trace('SendRR');
    _emitPacket(
      AX25Packet(
        addresses: addresses!,
        nr: _state.receiveSequence,
        ns: _state.sendSequence,
        pollFinal: pollFinal,
        command: true,
        type: FrameType.sFrameRr,
      ),
    );
  }

  // Difference between 'leader' and 'follower' modulo 'modulus'.
  int _distanceBetween(int l, int f, int m) {
    return (l < f) ? (l + (m - f)) : (l - f);
  }

  bool _shouldPiggybackAck() {
    return _state.sendBuffer.isNotEmpty &&
        _state.sendBuffer.any((p) => !p.sent);
  }

  // Send queued packets. If a REJ sequence number is set, outstanding packets
  // are resent along with any new packets (up to maxFrames). Otherwise only new
  // packets are sent.
  void _drain({bool resent = true}) {
    _trace(
      'Drain, Packets in Queue: ${_state.sendBuffer.length}, '
      'Resend: $resent',
    );
    if (_state.remoteBusy) {
      _clearTimer(_TimerName.t1);
      return;
    }

    int sequenceNum = _state.sendSequence;
    if (_state.gotREJSequenceNum > 0) {
      sequenceNum = _state.gotREJSequenceNum;
    }

    bool startTimer = false;
    for (
      int packetIndex = 0;
      packetIndex < _state.sendBuffer.length;
      packetIndex++
    ) {
      final dst = _distanceBetween(
        sequenceNum,
        _state.remoteReceiveSequence,
        _modulus,
      );
      if (_state.sendBuffer[packetIndex].sent || (dst < maxFrames)) {
        _state.sendBuffer[packetIndex].nr = _state.receiveSequence;
        if (!_state.sendBuffer[packetIndex].sent) {
          _state.sendBuffer[packetIndex].ns = _state.sendSequence;
          _state.sendBuffer[packetIndex].sent = true;
          _state.sendSequence = (_state.sendSequence + 1) % _modulus;
          sequenceNum = (sequenceNum + 1) % _modulus;
        } else if (!resent) {
          continue;
        }
        startTimer = true;
        _emitPacket(_state.sendBuffer[packetIndex]);
      }
    }

    if ((_state.gotREJSequenceNum < 0) && !startTimer) {
      _sendRR(false);
    }

    _state.gotREJSequenceNum = -1;
    if (startTimer) {
      _setTimer(_TimerName.t1);
    } else {
      _clearTimer(_TimerName.t1);
    }
  }

  void _renumber() {
    _trace('Renumber');
    for (int p = 0; p < _state.sendBuffer.length; p++) {
      _state.sendBuffer[p].ns = p % _modulus;
      _state.sendBuffer[p].nr = 0;
      _state.sendBuffer[p].sent = false;
    }
  }

  // ---- timer callbacks ------------------------------------------------------

  void _connectTimerCallback() {
    _trace('Timer - Connect');
    if (_timers.connectAttempts >= (retries - 1)) {
      _clearTimer(_TimerName.connect);
      _setConnectionState(AX25ConnectionState.disconnected);
      return;
    }
    _connectEx();
  }

  void _disconnectTimerCallback() {
    _trace('Timer - Disconnect');
    if (_timers.disconnectAttempts >= (retries - 1)) {
      _clearTimer(_TimerName.disconnect);
      _emitPacket(
        AX25Packet(
          addresses: addresses!,
          nr: _state.receiveSequence,
          ns: _state.sendSequence,
          pollFinal: false,
          command: false,
          type: FrameType.uFrameDm,
        ),
      );
      _setConnectionState(AX25ConnectionState.disconnected);
      return;
    }
    disconnect();
  }

  void _t1TimerCallback() {
    _trace('** Timer - T1 expired');
    if (_timers.t1Attempts >= retries) {
      _clearTimer(_TimerName.t1);
      disconnect();
      return;
    }
    _timers.t1Attempts++;
    _sendRR(true);
  }

  void _t2TimerCallback() {
    _trace('** Timer - T2 expired');
    _clearTimer(_TimerName.t2);
    _drain(resent: true);
  }

  void _t3TimerCallback() {
    _trace('** Timer - T3 expired');
    if (_isTimerEnabled(_TimerName.t1)) return; // Don't interfere with T1.
    if (_timers.t3Attempts >= retries) {
      _clearTimer(_TimerName.t3);
      disconnect();
      return;
    }
    _timers.t3Attempts++;
    // (No RR poll sent here, matching the C# implementation.)
  }

  // ---- public API -----------------------------------------------------------

  /// Initiates a connection to a remote station.
  ///
  /// [addrs] must contain at least the destination (index 0) and source
  /// (index 1) addresses, with optional digipeaters following. Returns `true`
  /// if the connection attempt was started, or `false` if already connected or
  /// the addresses are invalid.
  bool connect(List<AX25Address> addrs) {
    _trace('Connect');
    if (currentState != AX25ConnectionState.disconnected) return false;
    if (addrs.length < 2) return false;
    addresses = addrs;
    _state.sendBuffer.clear();
    _clearTimer(_TimerName.connect);
    _clearTimer(_TimerName.t1);
    _clearTimer(_TimerName.t2);
    _clearTimer(_TimerName.t3);
    return _connectEx();
  }

  bool _connectEx() {
    _trace('ConnectEx');
    _setConnectionState(AX25ConnectionState.connecting);
    _state.receiveSequence = 0;
    _state.sendSequence = 0;
    _state.remoteReceiveSequence = 0;
    _state.remoteBusy = false;
    _state.gotREJSequenceNum = -1;
    _clearTimer(_TimerName.disconnect);
    _clearTimer(_TimerName.t3);
    _emitPacket(
      AX25Packet(
        addresses: addresses!,
        nr: _state.receiveSequence,
        ns: _state.sendSequence,
        pollFinal: true,
        command: true,
        type: modulo128 ? FrameType.uFrameSabme : FrameType.uFrameSabm,
      ),
    );
    _renumber();
    _timers.connectAttempts++;
    if (_timers.connectAttempts >= retries) {
      _clearTimer(_TimerName.connect);
      _setConnectionState(AX25ConnectionState.disconnected);
      return true;
    }
    if (!_isTimerEnabled(_TimerName.connect)) _setTimer(_TimerName.connect);
    return true;
  }

  /// Initiates a disconnection from the remote station.
  void disconnect() {
    if (_state.connection == AX25ConnectionState.disconnected) return;
    _trace('Disconnect');
    _clearTimer(_TimerName.connect);
    _clearTimer(_TimerName.t1);
    _clearTimer(_TimerName.t2);
    _clearTimer(_TimerName.t3);
    if (_state.connection != AX25ConnectionState.connected) {
      _onErrorEvent('ax25.Session.disconnect: Not connected.');
      _setConnectionState(AX25ConnectionState.disconnected);
      _clearTimer(_TimerName.disconnect);
      return;
    }
    if (_timers.disconnectAttempts >= retries) {
      _clearTimer(_TimerName.disconnect);
      _emitPacket(
        AX25Packet(
          addresses: addresses!,
          nr: _state.receiveSequence,
          ns: _state.sendSequence,
          pollFinal: false,
          command: false,
          type: FrameType.uFrameDm,
        ),
      );
      _setConnectionState(AX25ConnectionState.disconnected);
      return;
    }
    _timers.disconnectAttempts++;
    _setConnectionState(AX25ConnectionState.disconnecting);
    _emitPacket(
      AX25Packet(
        addresses: addresses!,
        nr: _state.receiveSequence,
        ns: _state.sendSequence,
        pollFinal: true,
        command: true,
        type: FrameType.uFrameDisc,
      ),
    );
    // Arm the disconnect timer WITHOUT going through _setTimer/_clearTimer,
    // because those reset `disconnectAttempts` to 0. Re-arming via _setTimer
    // would zero the counter on every retry, so the retry cap (`>= retries`)
    // could never be reached and DISC frames would be sent forever while the
    // remote keeps replying. Arming directly lets the counter accumulate so the
    // disconnect sequence sends a few DISCs and then times out.
    if (!_isTimerEnabled(_TimerName.disconnect)) {
      _armTimer(_TimerName.disconnect);
    }
  }

  /// Arms [timerName] without resetting its retry counter (unlike [_setTimer],
  /// which first calls [_clearTimer]). Used by the disconnect retry sequence so
  /// the attempt counter accumulates across re-arms and the retry cap is
  /// actually reached.
  void _armTimer(_TimerName timerName) {
    if (addresses == null) return;
    final ms = _getTimerTimeout(timerName).round();
    _trace('ArmTimer $timerName to ${ms}ms');
    final duration = Duration(milliseconds: ms < 1 ? 1 : ms);
    final timer = Timer(duration, () => _onTimerElapsed(timerName));
    _timers.set(timerName, timer);
  }

  /// Sends [info] over the connection as a UTF-8 encoded string.
  void sendString(String info) {
    send(Uint8List.fromList(utf8.encode(info)));
  }

  /// Sends [info] over the connection, splitting it into I-frames based on
  /// [packetLength]. If the T2 timer is not running the packets are sent
  /// immediately; otherwise they are queued until the timer expires.
  void send(Uint8List info) {
    _trace('Send');
    if (info.isEmpty) return;
    if (addresses == null) return;
    for (int i = 0; i < info.length; i += packetLength) {
      final length = math.min(packetLength, info.length - i);
      final packetInfo = Uint8List.sublistView(info, i, i + length);
      _state.sendBuffer.add(
        AX25Packet(
          addresses: addresses!,
          nr: 0,
          ns: 0,
          pollFinal: false,
          command: true,
          type: FrameType.iFrame,
          data: Uint8List.fromList(packetInfo),
        ),
      );
    }
    if (!_isTimerEnabled(_TimerName.t2)) _drain(resent: false);
  }

  /// Processes a received AX.25 [packet]. Called internally when
  /// `UniqueDataFrame` events arrive, but may also be called directly. Returns
  /// `true` if the packet was processed, `false` if invalid.
  bool receive(AX25Packet packet) {
    if (packet.addresses.length < 2) return false;
    _trace('Receive ${packet.type}');

    AX25Packet? response = AX25Packet(
      addresses: addresses ?? packet.addresses,
      nr: _state.receiveSequence,
      ns: _state.sendSequence,
      pollFinal: false,
      command: !packet.command, // Command is flipped for response.
      type: 0,
    );

    var newState = currentState;

    // Ignore packets from a station other than the one this session is bound to.
    final addrs = addresses;
    if (addrs != null &&
        packet.addresses[1].callSignWithId != addrs[0].callSignWithId) {
      _trace(
        'Got packet from wrong station: ${packet.addresses[1].callSignWithId}, '
        'expected: ${addrs[0].callSignWithId}',
      );
      return false;
    }

    // If we are not connected and this is not a connection request, respond
    // with DM (or UA for a DISC).
    if (addrs == null &&
        packet.type != FrameType.uFrameSabm &&
        packet.type != FrameType.uFrameSabme) {
      final respAddrs = <AX25Address>[];
      final a0 = AX25Address.parse(packet.addresses[1].toString());
      final a1 = AX25Address.getAddress(sessionCallsign, sessionStationId);
      if (a0 == null || a1 == null) return false;
      respAddrs.add(a0);
      respAddrs.add(a1);
      response.addresses = respAddrs;
      response.command = false;
      response.pollFinal = true;
      response.type = packet.type == FrameType.uFrameDisc
          ? FrameType.uFrameUa
          : FrameType.uFrameDm;
      _emitPacket(response);
      return false;
    }

    switch (packet.type) {
      case FrameType.uFrameSabm:
      case FrameType.uFrameSabme:
        if (currentState != AX25ConnectionState.disconnected) return false;
        final a0 = AX25Address.parse(packet.addresses[1].toString());
        final a1 = AX25Address.getAddress(sessionCallsign, sessionStationId);
        if (a0 == null || a1 == null) return false;
        addresses = [a0, a1];
        response.addresses = addresses!;
        _state.receiveSequence = 0;
        _state.sendSequence = 0;
        _state.remoteReceiveSequence = 0;
        _state.gotREJSequenceNum = -1;
        _state.remoteBusy = false;
        _state.sendBuffer.clear();
        _state.receiveBuffer.clear();
        _clearTimer(_TimerName.connect);
        _clearTimer(_TimerName.disconnect);
        _clearTimer(_TimerName.t1);
        _clearTimer(_TimerName.t2);
        _clearTimer(_TimerName.t3);
        modulo128 = (packet.type == FrameType.uFrameSabme);
        _renumber();
        response.type = FrameType.uFrameUa;
        if (packet.command && packet.pollFinal) response.pollFinal = true;
        newState = AX25ConnectionState.connected;
        break;

      case FrameType.uFrameDisc:
        if (_state.connection == AX25ConnectionState.connected) {
          _state.receiveSequence = 0;
          _state.sendSequence = 0;
          _state.remoteReceiveSequence = 0;
          _state.gotREJSequenceNum = -1;
          _state.remoteBusy = false;
          _state.receiveBuffer.clear();
          _clearTimer(_TimerName.connect);
          _clearTimer(_TimerName.disconnect);
          _clearTimer(_TimerName.t1);
          _clearTimer(_TimerName.t2);
          _clearTimer(_TimerName.t3);
          response.type = FrameType.uFrameUa;
          response.pollFinal = true;
          _emitPacket(response);
          _setConnectionState(AX25ConnectionState.disconnected);
        } else {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
          _emitPacket(response);
        }
        return true;

      case FrameType.uFrameUa:
        if (_state.connection == AX25ConnectionState.connecting) {
          _clearTimer(_TimerName.connect);
          _clearTimer(_TimerName.t2);
          _setTimer(_TimerName.t3);
          response = null;
          newState = AX25ConnectionState.connected;
        } else if (_state.connection == AX25ConnectionState.disconnecting) {
          _clearTimer(_TimerName.disconnect);
          _clearTimer(_TimerName.t2);
          _clearTimer(_TimerName.t3);
          response = null;
          newState = AX25ConnectionState.disconnected;
        } else if (_state.connection == AX25ConnectionState.connected) {
          response = null;
        } else {
          response.type = FrameType.uFrameDm;
          response.pollFinal = false;
        }
        break;

      case FrameType.uFrameDm:
        if (_state.connection == AX25ConnectionState.connected) {
          _connectEx();
          response = null;
        } else if (_state.connection == AX25ConnectionState.connecting ||
            _state.connection == AX25ConnectionState.disconnecting) {
          _state.receiveSequence = 0;
          _state.sendSequence = 0;
          _state.remoteReceiveSequence = 0;
          _state.gotREJSequenceNum = -1;
          _state.remoteBusy = false;
          _state.sendBuffer.clear();
          _state.receiveBuffer.clear();
          _clearTimer(_TimerName.connect);
          _clearTimer(_TimerName.disconnect);
          _clearTimer(_TimerName.t1);
          _clearTimer(_TimerName.t2);
          _clearTimer(_TimerName.t3);
          final wasConnecting =
              _state.connection == AX25ConnectionState.connecting;
          response = null;
          if (wasConnecting) {
            modulo128 = false;
            _connectEx();
          } else {
            newState = AX25ConnectionState.disconnected;
          }
        } else {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      case FrameType.uFrameUi:
        if (packet.data != null && packet.data!.isNotEmpty) {
          _onUiDataReceivedEvent(packet.data!);
        }
        if (packet.pollFinal) {
          response.pollFinal = false;
          response.type = (_state.connection == AX25ConnectionState.connected)
              ? FrameType.sFrameRr
              : FrameType.uFrameDm;
        } else {
          response = null;
        }
        break;

      case FrameType.uFrameXid:
        response.type = FrameType.uFrameDm;
        break;

      case FrameType.uFrameTest:
        response.type = FrameType.uFrameTest;
        if (packet.data != null && packet.data!.isNotEmpty) {
          response.data = packet.data;
        }
        break;

      case FrameType.uFrameFrmr:
        if (_state.connection == AX25ConnectionState.connecting && modulo128) {
          modulo128 = false;
          _connectEx();
          response = null;
        } else if (_state.connection == AX25ConnectionState.connected) {
          _connectEx();
          response = null;
        } else {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      case FrameType.sFrameRr:
        if (_state.connection == AX25ConnectionState.connected) {
          _state.remoteBusy = false;
          if (packet.command && packet.pollFinal) {
            response.type = FrameType.sFrameRr;
            response.pollFinal = true;
          } else {
            response = null;
          }
          _receiveAcknowledgement(packet);
          if (_shouldPiggybackAck() && (response == null)) {
            _trace('Piggybacking ack on outgoing data after RR');
            if (!_isTimerEnabled(_TimerName.t2)) _drain(resent: false);
          } else {
            _setTimer(_TimerName.t2);
          }
        } else if (packet.command) {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      case FrameType.sFrameRnr:
        if (_state.connection == AX25ConnectionState.connected) {
          _state.remoteBusy = true;
          _receiveAcknowledgement(packet);
          if (packet.command && packet.pollFinal) {
            response.type = FrameType.sFrameRr;
            response.pollFinal = true;
          } else {
            response = null;
          }
          _clearTimer(_TimerName.t2);
          _setTimer(_TimerName.t1);
        } else if (packet.command) {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      case FrameType.sFrameRej:
        if (_state.connection == AX25ConnectionState.connected) {
          _state.remoteBusy = false;
          if (packet.command && packet.pollFinal) {
            response.type = FrameType.sFrameRr;
            response.pollFinal = true;
          } else {
            response = null;
          }
          _receiveAcknowledgement(packet);
          _state.gotREJSequenceNum = packet.nr;
          if (_shouldPiggybackAck() && (response == null)) {
            _trace('Piggybacking ack on outgoing data after REJ');
            if (!_isTimerEnabled(_TimerName.t2)) _drain(resent: false);
          } else {
            _setTimer(_TimerName.t2);
          }
        } else {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      case FrameType.iFrame:
        if (_state.connection == AX25ConnectionState.connected) {
          if (packet.pollFinal) response.pollFinal = true;

          if (packet.ns == _state.receiveSequence) {
            // In-sequence packet - process immediately.
            _state.sentREJ = false;
            _state.receiveSequence = (_state.receiveSequence + 1) % _modulus;
            if (packet.data != null && packet.data!.isNotEmpty) {
              _onDataReceivedEvent(packet.data!);
            }
            _processBufferedPackets();
            // `response` is still the non-null acknowledgement frame here.
            if (_shouldPiggybackAck() && !response.pollFinal) {
              _trace('Piggybacking ack on outgoing data instead of sending RR');
              response = null;
              if (!_isTimerEnabled(_TimerName.t2)) _drain(resent: false);
            } else {
              response = null;
              _setTimer(_TimerName.t2);
            }
          } else if (_isWithinReceiveWindow(packet.ns) &&
              !_state.receiveBuffer.containsKey(packet.ns)) {
            // Out-of-order packet within window - buffer it.
            _trace(
              'Buffering out-of-order packet NS=${packet.ns}, '
              'expected=${_state.receiveSequence}',
            );
            _state.receiveBuffer[packet.ns] = packet;
            if (!_state.sentREJ) {
              response.type = FrameType.sFrameRej;
              _state.sentREJ = true;
            } else {
              response = null;
            }
          } else if (_state.sentREJ) {
            response = null;
          } else {
            response.type = FrameType.sFrameRej;
            _state.sentREJ = true;
          }

          _receiveAcknowledgement(packet);

          if ((response == null) && !_shouldPiggybackAck()) {
            _setTimer(_TimerName.t2);
          }
        } else if (packet.command) {
          response.type = FrameType.uFrameDm;
          response.pollFinal = true;
        }
        break;

      default:
        response = null;
        break;
    }

    if (response != null) {
      if (response.addresses.isEmpty ||
          identical(response.addresses, packet.addresses)) {
        final respAddrs = <AX25Address>[];
        final a0 = AX25Address.parse(packet.addresses[1].toString());
        final a1 = AX25Address.getAddress(sessionCallsign, sessionStationId);
        if (a0 != null && a1 != null) {
          respAddrs.add(a0);
          respAddrs.add(a1);
          response.addresses = respAddrs;
          _emitPacket(response);
        }
      } else {
        _emitPacket(response);
      }
    }

    if (newState != currentState) {
      if (currentState == AX25ConnectionState.disconnecting &&
          newState == AX25ConnectionState.connected) {
        return true;
      }
      _setConnectionState(newState);
    }

    return true;
  }

  // Process buffered packets that can now be delivered in sequence.
  void _processBufferedPackets() {
    while (_state.receiveBuffer.containsKey(_state.receiveSequence)) {
      final bufferedPacket = _state.receiveBuffer.remove(
        _state.receiveSequence,
      );
      _trace('Processing buffered packet NS=${bufferedPacket!.ns}');
      if (bufferedPacket.data != null && bufferedPacket.data!.isNotEmpty) {
        _onDataReceivedEvent(bufferedPacket.data!);
      }
      _state.receiveSequence = (_state.receiveSequence + 1) % _modulus;
    }
  }

  // Whether a packet sequence number is within the receive window.
  bool _isWithinReceiveWindow(int ns) {
    final distance = _distanceBetween(ns, _state.receiveSequence, _modulus);
    return distance < maxFrames;
  }

  /// Disposes the session, stopping all timers and unsubscribing from the
  /// DataBroker.
  void dispose() {
    if (_disposed) return;
    _broker.logInfo(
      '[AX25Session] Session disposing for radio device $_radioDeviceId',
    );
    _clearTimer(_TimerName.connect);
    _clearTimer(_TimerName.disconnect);
    _clearTimer(_TimerName.t1);
    _clearTimer(_TimerName.t2);
    _clearTimer(_TimerName.t3);
    _state.sendBuffer.clear();
    _state.receiveBuffer.clear();
    addresses = null;
    sessionState.clear();
    _disposed = true;
    _broker.dispose();
  }
}

/// Internal protocol state for an [AX25Session] (port of the C# nested
/// `State` class).
class _SessionState {
  AX25ConnectionState connection = AX25ConnectionState.disconnected;
  int receiveSequence = 0; // V(R)
  int sendSequence = 0; // V(S)
  int remoteReceiveSequence = 0; // N(R)
  bool remoteBusy = false;
  bool sentREJ = false;
  bool sentSREJ = false;
  int gotREJSequenceNum = -1;
  int gotSREJSequenceNum = -1;
  final List<AX25Packet> sendBuffer = [];
  final Map<int, AX25Packet> receiveBuffer = {};
}

/// Internal timers for an [AX25Session] (port of the C# nested `Timers`
/// class). Dart [Timer]s are one-shot and are re-armed each cycle, matching the
/// way the C# timers are explicitly restarted.
class _SessionTimers {
  Timer? connect;
  Timer? disconnect;
  Timer? t1;
  Timer? t2;
  Timer? t3;

  int connectAttempts = 0;
  int disconnectAttempts = 0;
  int t1Attempts = 0;
  int t3Attempts = 0;

  void set(_TimerName name, Timer timer) {
    switch (name) {
      case _TimerName.connect:
        connect?.cancel();
        connect = timer;
        break;
      case _TimerName.disconnect:
        disconnect?.cancel();
        disconnect = timer;
        break;
      case _TimerName.t1:
        t1?.cancel();
        t1 = timer;
        break;
      case _TimerName.t2:
        t2?.cancel();
        t2 = timer;
        break;
      case _TimerName.t3:
        t3?.cancel();
        t3 = timer;
        break;
    }
  }

  void cancel(_TimerName name) {
    switch (name) {
      case _TimerName.connect:
        connect?.cancel();
        connect = null;
        break;
      case _TimerName.disconnect:
        disconnect?.cancel();
        disconnect = null;
        break;
      case _TimerName.t1:
        t1?.cancel();
        t1 = null;
        break;
      case _TimerName.t2:
        t2?.cancel();
        t2 = null;
        break;
      case _TimerName.t3:
        t3?.cancel();
        t3 = null;
        break;
    }
  }

  /// Clears the stored reference after a one-shot timer has fired (the callback
  /// has already executed; this just keeps [isActive] accurate).
  void markFired(_TimerName name) {
    switch (name) {
      case _TimerName.connect:
        connect = null;
        break;
      case _TimerName.disconnect:
        disconnect = null;
        break;
      case _TimerName.t1:
        t1 = null;
        break;
      case _TimerName.t2:
        t2 = null;
        break;
      case _TimerName.t3:
        t3 = null;
        break;
    }
  }

  bool isActive(_TimerName name) {
    switch (name) {
      case _TimerName.connect:
        return connect?.isActive ?? false;
      case _TimerName.disconnect:
        return disconnect?.isActive ?? false;
      case _TimerName.t1:
        return t1?.isActive ?? false;
      case _TimerName.t2:
        return t2?.isActive ?? false;
      case _TimerName.t3:
        return t3?.isActive ?? false;
    }
  }
}
