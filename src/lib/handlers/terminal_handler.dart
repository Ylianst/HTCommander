/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

The Terminal engine, independent of any UI. It connects to a Terminal station
over a radio locked to "Terminal" usage and exchanges text using the
connectionless AX.25 protocols (raw, raw compressed, APRS messages), a
connected-mode AX.25 session (with YAPP file transfer), or a XARA (VARA FM)
link. It can also wait for an incoming AX.25 connection.

It is driven entirely through the DataBroker (device 1), so the Terminal tab
(in any window), the hosted web UI and test agents all share one engine:

Commands
  TerminalConnect   {RadioId, Station: StationInfo json}
  TerminalWait      {RadioId}
  TerminalDisconnect  graceful (AX.25 DISC / XARA disconnect / unlock)
  TerminalAbort       immediate teardown
  TerminalSend      {Text}
  TerminalSendFile  {Name, Data}           (YAPP over an AX.25 session)
  TerminalCancelTransfer

Published
  TerminalState     (stored) {status, radioId, station, remote, protocol,
                    canSend, canSendFile, pendingDisconnect, transfer}
  TerminalText      {outgoing, from, to, text}
  TerminalNotice    {kind, ...args}         (the UI localizes `kind`)
  TerminalFileReceived {Name, Data}

Ported from the logic formerly inside TerminalTab (itself a port of the C#
TerminalTabUserControl).
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/radio_models.dart';
import '../models/station_info.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/ax25_session.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../radio/yapp_transfer.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../utils/station_channel_resolver.dart';

/// Overall terminal status, as published in `TerminalState`.
enum TerminalStatus { idle, connecting, connected, waiting, disconnecting }

enum _XaraState { waitingForLock, connecting, connected, disconnecting }

/// Notice kinds published in `TerminalNotice`; the UI turns them into text.
abstract final class TerminalNotices {
  static const String connecting = 'connecting'; // callsign
  static const String connected = 'connected';
  static const String connectedTo = 'connectedTo'; // callsign (connectionless)
  static const String connectedFrom = 'connectedFrom'; // callsign
  static const String disconnecting = 'disconnecting';
  static const String disconnected = 'disconnected';
  static const String waiting = 'waiting';
  static const String notConnected = 'notConnected';
  static const String busy = 'busy';
  static const String invalidCallsignDest = 'invalidCallsignDest';
  static const String invalidCallsign = 'invalidCallsign';
  static const String brotli = 'brotli';
  static const String error = 'error'; // error
  static const String regionMissing = 'regionMissing'; // station
  static const String channelMissing = 'channelMissing'; // station
  static const String xaraRequiresAudio = 'xaraRequiresAudio';
  static const String xaraNoAnswer = 'xaraNoAnswer';
  static const String xaraLockTimeout = 'xaraLockTimeout';
  static const String xaraDisconnectTimeout = 'xaraDisconnectTimeout';
  static const String transferInProgress = 'transferInProgress';
  static const String sendingFile = 'sendingFile'; // filename
  static const String fileSent = 'fileSent'; // filename
  static const String fileReceived = 'fileReceived'; // filename, size
  static const String fileTransferError = 'fileTransferError'; // message
}

/// The terminal engine (see the file header for its broker interface).
class TerminalHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _disposed = false;

  final List<int> _connectedRadios = [];
  final Map<int, RadioLockState> _lockStates = {};
  StationInfo? _station;
  int _radioId = -1;

  AX25Session? _session;
  YappTransfer? _yapp;
  YappProgress? _transfer;
  _XaraState? _xaraState;
  Timer? _xaraTimer;
  Timer? _xaraLockPollTimer;

  bool _waiting = false;
  String? _remote;
  bool _pendingDisconnect = false;

  void init() {
    _loadConnectedRadios();
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadios,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockState,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockChannelResolveFailed',
      callback: _onLockChannelResolveFailed,
    );
    _broker.subscribeMultiple(
      deviceId: DataBroker.allDevices,
      names: const ['XaraEvent', 'XaraDataReceived', 'AudioState'],
      callback: _onXaraDataOrEvent,
    );
    _broker.subscribeMultiple(
      deviceId: 1,
      names: const [
        'TerminalConnect',
        'TerminalWait',
        'TerminalDisconnect',
        'TerminalAbort',
        'TerminalSend',
        'TerminalSendFile',
        'TerminalCancelTransfer',
      ],
      callback: _onCommand,
    );
    _publish();
  }

  void dispose() {
    if (_disposed) return;
    if (_xaraState != null) _finishXara(abort: true, notify: false);
    _yapp?.dispose();
    _yapp = null;
    _session?.dispose();
    _session = null;
    _disposed = true;
    _broker.dispose();
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The radio locked to Terminal usage, or -1.
  int get activeRadioId {
    for (final radioId in _connectedRadios) {
      final lock = _lockStates[radioId];
      if (lock != null && lock.isLocked && lock.usage == 'Terminal') {
        return radioId;
      }
    }
    return -1;
  }

  TerminalStatus get status {
    final x = _xaraState;
    if (x != null) {
      return switch (x) {
        _XaraState.connected => TerminalStatus.connected,
        _XaraState.disconnecting => TerminalStatus.disconnecting,
        _ => TerminalStatus.connecting,
      };
    }
    final s = _session;
    if (s != null) {
      if (_waiting) return TerminalStatus.waiting;
      switch (s.currentState) {
        case AX25ConnectionState.connected:
          return TerminalStatus.connected;
        case AX25ConnectionState.connecting:
          return TerminalStatus.connecting;
        case AX25ConnectionState.disconnecting:
          return TerminalStatus.disconnecting;
        case AX25ConnectionState.disconnected:
          break;
      }
    }
    if (activeRadioId > 0) {
      // A connected-mode session waits for its handshake; connectionless
      // protocols are usable as soon as the radio is locked.
      final p = _station?.terminalProtocol;
      return s != null && p == TerminalProtocol.x25Session
          ? TerminalStatus.connecting
          : TerminalStatus.connected;
    }
    // Lock requested but not yet confirmed by the radio.
    if (_station != null && _radioId > 0 && !_lockedOnce) {
      return TerminalStatus.connecting;
    }
    return TerminalStatus.idle;
  }

  bool get _canSend {
    if (_transfer != null) return false;
    if (_xaraState != null) return _xaraState == _XaraState.connected;
    return activeRadioId > 0;
  }

  bool get _canSendFile =>
      _session?.currentState == AX25ConnectionState.connected &&
      !(_yapp?.isBusy ?? true);

  void _publish() {
    if (_disposed) return;
    final t = _transfer;
    final station = _station;
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalState',
      data: <String, Object?>{
        'status': status.name,
        'radioId': _radioId > 0 ? _radioId : activeRadioId,
        'station': station?.toJson(),
        'remote': station?.callsign ?? _remote,
        'protocol':
            station?.terminalProtocol.name ??
            (_session != null ? TerminalProtocol.x25Session.name : null),
        'canSend': _canSend,
        'canSendFile': _canSendFile,
        'pendingDisconnect': _pendingDisconnect,
        'transfer': t == null
            ? null
            : <String, Object?>{
                'filename': t.filename,
                'fileSize': t.fileSize,
                'bytesTransferred': t.bytesTransferred,
                'direction': t.direction.name,
              },
      },
    );
  }

  void _notice(String kind, [Map<String, Object?> args = const {}]) {
    if (_disposed) return;
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalNotice',
      data: <String, Object?>{'kind': kind, ...args},
      store: false,
    );
  }

  void _text({
    required bool outgoing,
    required String? from,
    required String? to,
    required String text,
  }) {
    if (_disposed || text.isEmpty) return;
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalText',
      data: <String, Object?>{
        'outgoing': outgoing,
        'from': from,
        'to': to,
        'text': text,
      },
      store: false,
    );
  }

  String get _myCallsign =>
      _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';

  String get _myAddress {
    final id = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    return id > 0 ? '$_myCallsign-$id' : _myCallsign;
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  void _onCommand(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final args = data is Map ? data : const <Object?, Object?>{};
    switch (name) {
      case 'TerminalConnect':
        final radioId = (args['RadioId'] as num?)?.toInt() ?? -1;
        final station = args['Station'];
        if (station is StationInfo) {
          connect(radioId, station);
        } else if (station is Map) {
          connect(
            radioId,
            StationInfo.fromJson(station.cast<String, dynamic>()),
          );
        }
      case 'TerminalWait':
        waitForConnection((args['RadioId'] as num?)?.toInt() ?? -1);
      case 'TerminalDisconnect':
        disconnect();
      case 'TerminalAbort':
        abort();
      case 'TerminalSend':
        final text = args['Text'];
        if (text is String) send(text);
      case 'TerminalSendFile':
        final fileName = args['Name'];
        final bytes = args['Data'];
        if (fileName is String && bytes is List) {
          sendFile(
            fileName,
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes.cast<int>()),
          );
        }
      case 'TerminalCancelTransfer':
        _yapp?.cancel();
    }
  }

  /// Locks [radioId] to Terminal usage and connects to [station].
  void connect(int radioId, StationInfo station) {
    if (radioId <= 0) return;
    if (status != TerminalStatus.idle) {
      _notice(TerminalNotices.busy);
      return;
    }

    // Validate the station's region/channel up front so a missing region or
    // channel lets the UI offer to fix the contact instead of failing quietly.
    final res = resolveStationChannel(_broker, radioId, station);
    if (res.status == StationChannelStatus.regionMissing) {
      _notice(TerminalNotices.regionMissing, {'station': station.toJson()});
      return;
    }
    if (res.status == StationChannelStatus.channelMissing) {
      _notice(TerminalNotices.channelMissing, {'station': station.toJson()});
      return;
    }

    if (station.terminalProtocol.isXara) {
      if (kIsWeb ||
          Platform.isIOS ||
          !(_broker.getValue<bool>(radioId, 'AudioState', false) ?? false)) {
        _xaraError(TerminalNotices.xaraRequiresAudio);
        return;
      }
      final path = AX25Address.parsePath(station.ax25Path);
      if (AX25Address.parse(station.callsign) == null ||
          path == null ||
          path.length > 2) {
        _xaraError(TerminalNotices.invalidCallsignDest);
        return;
      }
      _yapp?.dispose();
      _yapp = null;
      _transfer = null;
      _session?.dispose();
      _session = null;
    }

    _station = station;
    _radioId = radioId;
    _lockedOnce = false;
    _xaraState = station.terminalProtocol.isXara
        ? _XaraState.waitingForLock
        : null;

    // Lock the radio to Terminal usage, carrying the contact's modem so the
    // radio uses it for the duration of the lock without touching the global
    // software modem setting. 'Hardware' maps to the radio's built-in TNC.
    _broker.dispatch(
      deviceId: radioId,
      name: 'SetLock',
      data: SetLockData(
        usage: 'Terminal',
        regionId: res.regionId,
        channelId: res.channelId,
        channelName: res.channelName,
        modem: station.terminalProtocol.isXara ? 'XARA' : station.modem,
        xaraWide: station.terminalProtocol.isXara
            ? station.terminalProtocol == TerminalProtocol.xaraWide
            : null,
      ),
      store: false,
    );

    _broker.logInfo(
      '[Terminal] Connecting to station ${station.callsign} on radio '
      '$radioId (Channel: ${res.channelId >= 0 ? res.channelId : res.channelName}, '
      'Region: ${res.regionId})',
    );

    if (station.terminalProtocol.isXara) {
      _startXara(radioId, station);
    } else if (station.terminalProtocol == TerminalProtocol.x25Session) {
      _startSession(radioId, station);
    } else {
      _notice(TerminalNotices.connectedTo, {'callsign': station.callsign});
    }
    _publish();
  }

  /// Gracefully ends the current connection.
  void disconnect() {
    if (_xaraState != null) {
      _disconnectXara();
      return;
    }
    final radioId = activeRadioId;
    if (radioId <= 0) {
      // Nothing locked yet (e.g. a lock still pending): drop local state.
      if (_session != null || _station != null || _waiting) abort();
      return;
    }
    // Ignore repeat requests while a graceful disconnect is already underway;
    // calling disconnect() again mid-handshake would abort it and release the
    // radio lock before the remote confirms (mirrors the C# guard).
    if (_pendingDisconnect) {
      _broker.logInfo('[Terminal] Disconnect already in progress');
      return;
    }

    // For a connected-mode session, perform a graceful AX.25 disconnect; the
    // radio is unlocked only when the session reaches the DISCONNECTED state
    // (i.e. once the remote acknowledges the DISC with a UA).
    final session = _session;
    if (session != null &&
        session.currentState != AX25ConnectionState.disconnected) {
      _pendingDisconnect = true;
      // Only initiate a DISC while still connected/connecting. If the session
      // is already disconnecting, wait for the in-flight handshake to complete.
      if (session.currentState == AX25ConnectionState.connected ||
          session.currentState == AX25ConnectionState.connecting) {
        _broker.logInfo('[Terminal] Initiating graceful AX.25 disconnect');
        session.disconnect();
      }
      _publish();
      return;
    }

    // Otherwise (connectionless protocols) just unlock the radio. The modem
    // override is released together with the lock.
    _unlockAndReset(radioId);
  }

  /// Ends the current connection immediately: aborts XARA, drops the AX.25
  /// session and releases the radio.
  void abort() {
    if (_xaraState != null) {
      _finishXara(abort: true);
      return;
    }
    final radioId = _radioId > 0 ? _radioId : activeRadioId;
    if (radioId > 0 || _session != null || _waiting || _station != null) {
      _unlockAndReset(radioId);
    }
  }

  void _unlockAndReset(int radioId) {
    if (radioId > 0) {
      _broker.dispatch(
        deviceId: radioId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'Terminal'),
        store: false,
      );
      _broker.logInfo('[Terminal] Disconnecting from radio $radioId');
    }
    _yapp?.dispose();
    _yapp = null;
    _transfer = null;
    _session?.dispose();
    _session = null;
    _station = null;
    _radioId = -1;
    _waiting = false;
    _remote = null;
    _pendingDisconnect = false;
    _notice(TerminalNotices.disconnected);
    _publish();
  }

  /// Sends a line of text over the current connection.
  void send(String text) {
    if (text.isEmpty) return;
    final radioId = activeRadioId;
    if (radioId <= 0 && _xaraState == null) {
      _notice(TerminalNotices.notConnected);
      return;
    }
    // A YAPP file transfer owns the session; block text sends while it runs.
    if (_yapp?.isBusy ?? false) {
      _notice(TerminalNotices.transferInProgress);
      return;
    }
    final station = _station;

    // "Wait for Connection" has no configured station: send through the live
    // connected-mode session directly.
    if (station == null) {
      final session = _session;
      if (session == null ||
          session.currentState != AX25ConnectionState.connected) {
        _notice(TerminalNotices.notConnected);
        return;
      }
      session.sendString('$text\r');
      _text(
        outgoing: true,
        from: _myAddress,
        to: _remote ?? 'UNKNOWN',
        text: '$text\n',
      );
      return;
    }

    switch (station.terminalProtocol) {
      case TerminalProtocol.aprs:
        if (!_sendAprsPacket(radioId, station, text)) return;
      case TerminalProtocol.rawX25Compress:
        if (!_sendRawX25Packet(radioId, station, text, compress: true)) return;
      case TerminalProtocol.rawX25:
        if (!_sendRawX25Packet(radioId, station, text, compress: false)) {
          return;
        }
      case TerminalProtocol.x25Session:
        final session = _session;
        if (session == null ||
            session.currentState != AX25ConnectionState.connected) {
          _notice(TerminalNotices.notConnected);
          return;
        }
        // Send a line terminated with a carriage return (BBS convention).
        session.sendString('$text\r');
      case TerminalProtocol.xaraNarrow:
      case TerminalProtocol.xaraWide:
        if (_xaraState != _XaraState.connected) {
          _notice(TerminalNotices.notConnected);
          return;
        }
        _broker.dispatch(
          deviceId: _radioId,
          name: 'XaraSend',
          data: Uint8List.fromList(utf8.encode('$text\r')),
          store: false,
        );
    }

    _text(
      outgoing: true,
      from: _myAddress,
      to: station.callsign,
      text: '$text\n',
    );
  }

  /// Sends a file over the AX.25 session using YAPP.
  void sendFile(String fileName, Uint8List bytes) {
    final yapp = _yapp;
    final session = _session;
    if (yapp == null ||
        session == null ||
        session.currentState != AX25ConnectionState.connected) {
      _notice(TerminalNotices.notConnected);
      return;
    }
    if (yapp.isBusy) {
      _notice(TerminalNotices.transferInProgress);
      return;
    }
    _notice(TerminalNotices.sendingFile, {'filename': fileName});
    yapp.sendFile(fileName, bytes);
    _publish();
  }

  // ---------------------------------------------------------------------------
  // Radio tracking
  // ---------------------------------------------------------------------------

  void _loadConnectedRadios() {
    _connectedRadios.clear();
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final deviceId = item['DeviceId'] ?? item['deviceId'];
        if (deviceId is int && deviceId > 0) {
          _connectedRadios.add(deviceId);
          final lock = _broker.getJsonValue<RadioLockState>(
            deviceId,
            'LockState',
            (json) => RadioLockState.fromJson(json),
          );
          if (lock != null) _lockStates[deviceId] = lock;
        }
      }
    }
  }

  void _onConnectedRadios(int deviceId, String name, Object? data) {
    _loadConnectedRadios();
    if (_xaraState != null && !_connectedRadios.contains(_radioId)) {
      _finishXara(abort: true);
    }
    _lockStates.removeWhere((id, _) => !_connectedRadios.contains(id));
    if (_radioId > 0 && !_connectedRadios.contains(_radioId)) {
      _radioId = -1;
      _station = null;
    }
    _publish();
  }

  void _onLockState(int deviceId, String name, Object? data) {
    if (deviceId == _radioId && _xaraState != null) {
      final lock = data is Map<String, dynamic>
          ? RadioLockState.fromJson(data)
          : null;
      if (lock == null || !lock.isLocked || lock.usage != 'Terminal') {
        _finishXara(abort: true);
      }
    }
    if (data is Map<String, dynamic>) {
      _lockStates[deviceId] = RadioLockState.fromJson(data);
      final lock = _lockStates[deviceId]!;
      // Our Terminal lock was released elsewhere (e.g. the radio changed
      // channel): drop a connectionless connection with it.
      if (deviceId == _radioId &&
          _session == null &&
          _xaraState == null &&
          (!lock.isLocked || lock.usage != 'Terminal') &&
          _station != null &&
          _lockedOnce) {
        _station = null;
        _radioId = -1;
      }
      if (deviceId == _radioId && lock.isLocked && lock.usage == 'Terminal') {
        _lockedOnce = true;
      }
    } else if (data == null) {
      _lockStates.remove(deviceId);
      if (_radioId == deviceId) {
        _radioId = -1;
        _station = null;
      }
    }
    _publish();
  }

  /// Whether the current connection's radio has reported the Terminal lock.
  bool _lockedOnce = false;

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    // Only process frames while we have a radio locked to Terminal usage.
    final radioId = activeRadioId;
    if (radioId <= 0 || deviceId != radioId) return;

    // Connected-mode sessions (the X25Session protocol and "Wait for
    // Connection") are handled entirely by the AX25Session, which has its own
    // UniqueDataFrame subscription; connectionless protocols are decoded here.
    if (_session != null || _xaraState != null) return;

    if (data is! TncDataFragment) return;
    if (!data.incoming) return;
    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    _processIncomingPacket(packet);
  }

  /// A radio reported that the connected station's channel could not be found in
  /// the region it switched to. Aborts the connection and lets the UI offer to
  /// fix the contact.
  void _onLockChannelResolveFailed(int deviceId, String name, Object? data) {
    if (data is! Map || data['usage'] != 'Terminal') return;
    if (deviceId != _radioId) return;
    final station = _station;

    if (_xaraState != null) _finishXara(abort: true, notify: false);
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetUnlock',
      data: SetUnlockData(usage: 'Terminal'),
      store: false,
    );
    _session?.dispose();
    _session = null;
    _station = null;
    _radioId = -1;
    _publish();
    if (station != null) {
      _notice(TerminalNotices.channelMissing, {'station': station.toJson()});
    }
  }

  // ---------------------------------------------------------------------------
  // XARA
  // ---------------------------------------------------------------------------

  void _xaraError(String kind, {String? details}) {
    _broker.logError(
      '[Terminal] XARA: $kind${details == null ? '' : ' ($details)'}',
    );
    _notice(TerminalNotices.error, {'error': kind, 'details': ?details});
  }

  ({bool ready, String details}) _xaraLockReadiness(
    int radioId,
    StationInfo station,
  ) {
    final lock = _lockStates[radioId];
    final resolution = resolveStationChannel(_broker, radioId, station);
    final ht = _broker.getValueDynamic(radioId, 'HtStatus');
    final settings = _broker.getValueDynamic(radioId, 'Settings');
    final region = ht is Map ? ht['currRegion'] : null;
    // HtStatus.currChId is the channel of the last reception, not the
    // selected one; the selected channel is settings channel A.
    final channel = settings is Map ? settings['channelA'] : null;
    final reason = lock?.isLocked != true
        ? 'lockNotHeld'
        : lock?.usage != 'Terminal'
        ? 'lockOwnedByOtherUsage'
        : resolution.status != StationChannelStatus.ok
        ? 'channelResolutionPending'
        : ht is! Map || settings is! Map
        ? 'statusUnavailable'
        : region != resolution.regionId
        ? 'regionMismatch'
        : resolution.channelId >= 0 && channel != resolution.channelId
        ? 'channelMismatch'
        : 'ready';
    return (
      ready: reason == 'ready',
      details:
          'radio=$radioId reason=$reason '
          'lockOwner=${lock?.usage} locked=${lock?.isLocked} '
          'expectedRegion=${resolution.regionId} '
          'expectedChannel=${resolution.channelId} '
          'reportedRegion=$region selectedChannel=$channel '
          'lastRxChannel=${ht is Map ? ht['currChId'] : null} '
          'resolution=${resolution.status.name} '
          'contactRegion=${jsonEncode(station.channelRegion)} '
          'contactChannel=${jsonEncode(station.channel)} '
          'scan=${settings is Map ? settings['scan'] : null} '
          'dualWatch=${settings is Map ? settings['doubleChannel'] : null}',
    );
  }

  void _startXara(int radioId, StationInfo station) {
    if (_xaraState != _XaraState.waitingForLock) return;
    _notice(TerminalNotices.connecting, {'callsign': station.callsign});
    var lastDetails = _xaraLockReadiness(radioId, station).details;
    _broker.logInfo('[Terminal] XARA lock wait (15s): $lastDetails');
    _xaraTimer = Timer(const Duration(seconds: 15), () {
      _xaraError(
        TerminalNotices.xaraLockTimeout,
        details: _xaraLockReadiness(radioId, station).details,
      );
      _finishXara(abort: true);
    });
    _xaraLockPollTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      final readiness = _xaraLockReadiness(radioId, station);
      if (readiness.details != lastDetails) {
        lastDetails = readiness.details;
        _broker.logInfo('[Terminal] XARA lock wait changed: $lastDetails');
      }
      if (readiness.ready) {
        _broker.logInfo(
          '[Terminal] XARA lock confirmed; starting connection: $lastDetails',
        );
        timer.cancel();
        _xaraTimer?.cancel();
        _xaraState = _XaraState.connecting;
        _xaraTimer = Timer(const Duration(seconds: 120), () {
          _xaraError(TerminalNotices.xaraNoAnswer);
          _finishXara(abort: true);
        });
        _broker.dispatch(
          deviceId: radioId,
          name: 'XaraConnect',
          data: {
            'Remote': station.callsign.trim().toUpperCase(),
            'Vias': station.ax25Path
                .split(',')
                .map((s) => s.trim().toUpperCase())
                .where((s) => s.isNotEmpty)
                .toList(),
          },
          store: false,
        );
        _publish();
      }
    });
  }

  void _onXaraDataOrEvent(int deviceId, String name, Object? data) {
    if (_xaraState == null || deviceId != _radioId) return;
    if (name == 'AudioState') {
      if (data != true) {
        _xaraError(TerminalNotices.xaraRequiresAudio);
        _finishXara(abort: true);
      }
      return;
    }
    if (name == 'XaraDataReceived') {
      if (_xaraState == _XaraState.connected && data is Uint8List) {
        _receivedText(data);
      }
      return;
    }
    if (data is! Map) return;
    switch (data['evt']) {
      case 'connected':
        if (_xaraState != _XaraState.connecting) return;
        _xaraTimer?.cancel();
        _xaraState = _XaraState.connected;
        _notice(TerminalNotices.connected);
        _publish();
      case 'disconnected':
        _finishXara();
      case 'timedOut':
      case 'unableToConnect':
        _xaraError(TerminalNotices.xaraNoAnswer);
        _finishXara();
    }
  }

  void _disconnectXara() {
    if (_pendingDisconnect) return;
    if (_xaraState != _XaraState.connected) {
      _finishXara(abort: true);
      return;
    }
    _pendingDisconnect = true;
    _xaraState = _XaraState.disconnecting;
    _notice(TerminalNotices.disconnecting);
    _xaraTimer?.cancel();
    _xaraTimer = Timer(const Duration(seconds: 30), () {
      _xaraError(TerminalNotices.xaraDisconnectTimeout);
      _finishXara(abort: true);
    });
    _broker.dispatch(
      deviceId: _radioId,
      name: 'XaraDisconnect',
      data: null,
      store: false,
    );
    _publish();
  }

  void _finishXara({bool abort = false, bool notify = true}) {
    _xaraTimer?.cancel();
    _xaraTimer = null;
    _xaraLockPollTimer?.cancel();
    _xaraLockPollTimer = null;
    final radioId = _radioId;
    _xaraState = null;
    _radioId = -1;
    _station = null;
    _pendingDisconnect = false;
    if (abort && radioId > 0) {
      _broker.dispatch(
        deviceId: radioId,
        name: 'XaraAbort',
        data: null,
        store: false,
      );
    }
    final lock = _broker.getJsonValue<RadioLockState>(
      radioId,
      'LockState',
      RadioLockState.fromJson,
    );
    if (lock?.isLocked == true && lock?.usage == 'Terminal') {
      _broker.dispatch(
        deviceId: radioId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'Terminal'),
        store: false,
      );
    }
    if (notify) _notice(TerminalNotices.disconnected);
    _publish();
  }

  // ---------------------------------------------------------------------------
  // AX.25 session
  // ---------------------------------------------------------------------------

  /// Creates an [AX25Session] and initiates a connected-mode handshake to
  /// [station] (used for [TerminalProtocol.x25Session]).
  void _startSession(int radioId, StationInfo station) {
    _session?.dispose();

    final myStationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final dest = AX25Address.parse(
      station.ax25Destination.isNotEmpty
          ? station.ax25Destination
          : station.callsign,
    );
    final src = AX25Address.getAddress(_myCallsign, myStationId);
    if (dest == null || src == null) {
      _notice(TerminalNotices.invalidCallsignDest);
      return;
    }

    // Optional digipeater path (e.g. "RELAY-1,WIDE1-1"). Invalid entries were
    // rejected at contact-edit time, so a null here just means no path.
    final digipeaters = AX25Address.parsePath(station.ax25Path) ?? const [];

    final session = AX25Session(radioId);
    session.callSignOverride = _myCallsign;
    session.stationIdOverride = myStationId;
    // Outgoing client: fall silent once the link is torn down so we don't keep
    // answering the peer's retransmitted DISC after the radio is unlocked.
    session.acceptIncoming = false;
    session.onStateChanged = _onSessionStateChanged;
    session.onDataReceived = _onSessionDataReceived;
    session.onError = _onSessionError;
    _session = session;
    _attachYapp(session);

    _notice(TerminalNotices.connecting, {'callsign': station.callsign});
    session.connect([dest, src, ...digipeaters]);
  }

  /// Locks [radioId] to Terminal usage on its current channel and listens for
  /// an incoming AX.25 connection (mirrors the C# `WaitForConnectionOnRadio`).
  void waitForConnection(int radioId) {
    if (radioId <= 0) return;
    if (status != TerminalStatus.idle) {
      _notice(TerminalNotices.busy);
      return;
    }
    _session?.dispose();

    _broker.dispatch(
      deviceId: radioId,
      name: 'SetLock',
      data: SetLockData(usage: 'Terminal', regionId: -1, channelId: -1),
      store: false,
    );

    final session = AX25Session(radioId);
    session.callSignOverride = _myCallsign;
    session.stationIdOverride = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    session.onStateChanged = _onSessionStateChanged;
    session.onDataReceived = _onSessionDataReceived;
    session.onError = _onSessionError;
    _session = session;
    _attachYapp(session);

    _station = null;
    _radioId = radioId;
    _lockedOnce = false;
    _waiting = true;
    _remote = null;
    _pendingDisconnect = false;

    _broker.logInfo(
      '[Terminal] Waiting for incoming connection on radio $radioId',
    );
    _notice(TerminalNotices.waiting);
    _publish();
  }

  void _onSessionStateChanged(AX25Session sender, AX25ConnectionState state) {
    if (!identical(sender, _session)) return;
    switch (state) {
      case AX25ConnectionState.connected:
        if (_waiting) {
          // Incoming connection accepted: capture the remote callsign.
          final addrs = sender.addresses;
          final remote = (addrs != null && addrs.isNotEmpty)
              ? addrs[0].callSignWithId
              : 'UNKNOWN';
          _waiting = false;
          _remote = remote;
          _broker.logInfo(
            '[Terminal] Incoming connection established from $remote',
          );
          _notice(TerminalNotices.connectedFrom, {'callsign': remote});
        } else {
          _notice(TerminalNotices.connected);
        }
        _pendingDisconnect = false;
      case AX25ConnectionState.disconnected:
        _notice(TerminalNotices.disconnected);
        // Abort any in-progress file transfer.
        _yapp?.reset();
        _transfer = null;
        // If the radio is still locked to Terminal, release it.
        final radioId = activeRadioId;
        if (radioId > 0) {
          _broker.dispatch(
            deviceId: radioId,
            name: 'SetUnlock',
            data: SetUnlockData(usage: 'Terminal'),
            store: false,
          );
        }
        _station = null;
        _radioId = -1;
        _waiting = false;
        _remote = null;
        _pendingDisconnect = false;
      case AX25ConnectionState.disconnecting:
        // DISC sent; awaiting the remote's UA before the radio is released.
        _notice(TerminalNotices.disconnecting);
      case AX25ConnectionState.connecting:
        break;
    }
    _publish();
  }

  void _onSessionDataReceived(AX25Session sender, Uint8List data) {
    // Give the YAPP engine first chance at the data; if it consumes the bytes
    // as protocol traffic, don't show them as terminal text.
    if (_yapp?.processIncomingData(data) == true) return;
    _receivedText(data);
  }

  void _receivedText(Uint8List data) {
    _text(
      outgoing: false,
      from: _station?.callsign ?? _remote ?? 'UNKNOWN',
      to: _myCallsign,
      text: utf8.decode(data, allowMalformed: true),
    );
  }

  void _onSessionError(AX25Session sender, String error) {
    _notice(TerminalNotices.error, {'error': error});
  }

  /// Attaches a [YappTransfer] engine to [session], armed to auto-receive.
  void _attachYapp(AX25Session session) {
    _yapp?.dispose();
    final yapp = YappTransfer(session);
    yapp.onProgress = (progress) {
      _transfer = progress;
      _publish();
    };
    yapp.onReceiveComplete = (filename, data) {
      _transfer = null;
      _notice(TerminalNotices.fileReceived, {
        'filename': filename,
        'size': data.length,
      });
      _broker.dispatch(
        deviceId: 1,
        name: 'TerminalFileReceived',
        data: <String, Object?>{'Name': filename, 'Data': data},
        store: false,
      );
      _publish();
    };
    yapp.onSendComplete = (filename) {
      _transfer = null;
      _notice(TerminalNotices.fileSent, {'filename': filename});
      _publish();
    };
    yapp.onError = (message) {
      _transfer = null;
      _notice(TerminalNotices.fileTransferError, {'message': message});
      _publish();
    };
    yapp.enableAutoReceive();
    _yapp = yapp;
  }

  // ---------------------------------------------------------------------------
  // Connectionless protocols
  // ---------------------------------------------------------------------------

  AX25Address? _sourceAddress() => AX25Address.getAddress(
    _myCallsign,
    _broker.getValue<int>(0, 'StationId', 0) ?? 0,
  );

  void _transmit(int radioId, AX25Packet packet) {
    packet.incoming = false;
    packet.sent = false;
    _broker.dispatch(
      deviceId: radioId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(packet: packet, channelId: -1, regionId: -1),
      store: false,
    );
  }

  bool _sendRawX25Packet(
    int radioId,
    StationInfo station,
    String text, {
    required bool compress,
  }) {
    final src = _sourceAddress();
    // For raw protocols, the AX25Destination overrides the callsign when set.
    final dest = AX25Address.parse(
      station.ax25Destination.isNotEmpty
          ? station.ax25Destination
          : station.callsign,
    );
    if (src == null || dest == null) {
      _notice(TerminalNotices.invalidCallsignDest);
      return false;
    }

    final raw = Uint8List.fromList(utf8.encode(text));
    int pid = 241; // none
    Uint8List payload = raw;
    if (compress) {
      // Pick the smaller of uncompressed (241) or Deflate (243). Brotli (242)
      // from the C# implementation is unavailable in the Dart SDK.
      try {
        final deflated = Uint8List.fromList(zlib.encode(raw));
        if (deflated.length < payload.length) {
          payload = deflated;
          pid = 243;
        }
      } catch (_) {
        // Fall back to uncompressed on any compression error.
      }
    }

    final packet = AX25Packet(
      addresses: [dest, src],
      data: payload,
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    packet.pid = pid;
    _transmit(radioId, packet);
    return true;
  }

  bool _sendAprsPacket(int radioId, StationInfo station, String text) {
    final src = _sourceAddress();
    final dest = AX25Address.parse('APRS');
    if (src == null || dest == null) {
      _notice(TerminalNotices.invalidCallsign);
      return false;
    }
    // APRS message format: :CALLSIGN  :message  (9-char padded callsign)
    var paddedAddr = station.callsignNoZero;
    if (paddedAddr.length > 9) paddedAddr = paddedAddr.substring(0, 9);
    while (paddedAddr.length < 9) {
      paddedAddr += ' ';
    }
    final packet = AX25Packet(
      addresses: [dest, src],
      dataStr: ':$paddedAddr:$text',
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    packet.pid = 240;
    _transmit(radioId, packet);
    return true;
  }

  void _processIncomingPacket(AX25Packet packet) {
    final station = _station;
    if (station == null) return;
    if (packet.addresses.length < 2) return;
    final fromCallsign = packet.addresses[1].callSignWithId;

    switch (station.terminalProtocol) {
      case TerminalProtocol.aprs:
        _processAprsPacket(packet, fromCallsign);
      case TerminalProtocol.rawX25:
      case TerminalProtocol.rawX25Compress:
        _processRawX25Packet(packet, fromCallsign);
      case TerminalProtocol.x25Session:
      case TerminalProtocol.xaraNarrow:
      case TerminalProtocol.xaraWide:
        // Connected-mode data arrives through the session / XARA callbacks.
        break;
    }
  }

  void _processRawX25Packet(AX25Packet packet, String fromCallsign) {
    String? text;
    final pid = packet.pid;
    if (packet.data != null && packet.data!.isNotEmpty) {
      if (pid == 243) {
        try {
          text = utf8.decode(zlib.decode(packet.data!), allowMalformed: true);
        } catch (_) {
          text = utf8.decode(packet.data!, allowMalformed: true);
        }
      } else if (pid == 242) {
        // Brotli compressed - unsupported in this build.
        _notice(TerminalNotices.brotli);
        return;
      } else {
        text = utf8.decode(packet.data!, allowMalformed: true);
      }
    } else if (packet.dataStr != null && packet.dataStr!.isNotEmpty) {
      text = packet.dataStr;
    }
    if (text != null && text.isNotEmpty) {
      _text(outgoing: false, from: fromCallsign, to: _myCallsign, text: text);
    }
  }

  void _processAprsPacket(AX25Packet packet, String fromCallsign) {
    var aprsData = packet.dataStr;
    if ((aprsData == null || aprsData.isEmpty) &&
        packet.data != null &&
        packet.data!.isNotEmpty) {
      aprsData = utf8.decode(packet.data!, allowMalformed: true);
    }
    if (aprsData == null || aprsData.length < 11) return;
    if (aprsData[0] != ':') return;
    if (aprsData[10] != ':') return;

    var messageContent = aprsData.substring(11);
    final msgIdIndex = messageContent.lastIndexOf('{');
    if (msgIdIndex >= 0) {
      messageContent = messageContent.substring(0, msgIdIndex);
    }
    final authIndex = messageContent.lastIndexOf('}');
    if (authIndex >= 0) {
      messageContent = messageContent.substring(0, authIndex);
    }
    if (messageContent.isNotEmpty) {
      _text(
        outgoing: false,
        from: fromCallsign,
        to: _myCallsign,
        text: messageContent,
      );
    }
  }
}
