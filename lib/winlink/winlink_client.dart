/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/station_info.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_session.dart';
import '../radio/radio.dart';
import '../radio/utils.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'mail_store.dart';
import 'winlink_mail.dart';
import 'winlink_utils.dart';

enum WinlinkTransportType { x25, tcp }

enum WinlinkConnectionState {
  disconnected,
  connected,
  connecting,
  disconnecting,
}

/// Holds a single debug traffic entry.
class WinlinkDebugEntry {
  WinlinkDebugEntry({
    required this.address,
    required this.outgoing,
    required this.data,
    this.isStateMessage = false,
  });

  final String address;
  final bool outgoing;
  final String data;
  final bool isStateMessage;
}

/// The Winlink B2F protocol client. Supports both TCP (telnet to a CMS server)
/// and X25 (AX.25 session over radio) transports.
class WinlinkClient {
  WinlinkClient() {
    _broker = DataBrokerClient();

    // Subscribe to broker events to start syncing
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkSync',
      callback: _onWinlinkSync,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkDisconnect',
      callback: _onWinlinkDisconnect,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkDebugClear',
      callback: _onWinlinkDebugClearHistory,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkDebugHistoryRequest',
      callback: _onWinlinkDebugHistoryRequest,
    );
  }

  late DataBrokerClient _broker;
  WinlinkTransportType _transportType = WinlinkTransportType.tcp;
  Map<String, Object?> _sessionState = <String, Object?>{};
  bool _disposed = false;

  // TCP specific fields
  Socket? _tcpSocket;
  StreamSubscription<Uint8List>? _tcpSubscription;
  bool _tcpRunning = false;
  String _remoteAddress = '';
  WinlinkConnectionState _currentState = WinlinkConnectionState.disconnected;

  // TCP retry tracking. server.winlink.org is a load-balanced pool whose
  // instances sometimes accept a connection and then drop it before sending
  // the callsign prompt. Retry a few times in that case (matches Pat/RMS).
  String _tcpServer = '';
  int _tcpPort = 0;
  bool _tcpUseTls = true;
  bool _sessionDataReceived = false;
  bool _userDisconnect = false;
  int _tcpRetryCount = 0;
  static const int _maxTcpRetries = 3;
  static const Duration _tcpRetryDelay = Duration(seconds: 2);

  // Radio lock fields for X25 transport
  int _lockedRadioId = -1;

  // AX25Session for X25 transport
  AX25Session? _ax25Session;
  bool _pendingDisconnect = false;

  // Debug traffic history buffer (last 1000 entries)
  static const int _maxDebugHistorySize = 1000;
  final List<WinlinkDebugEntry> _debugHistory = <WinlinkDebugEntry>[];

  void _onWinlinkSync(int deviceId, String name, Object? data) {
    if (_disposed) return;

    // Ignore if we are already busy (not disconnected)
    if (_currentState != WinlinkConnectionState.disconnected) return;

    // Start sync - data should contain server info or radio/station info
    // Expected for TCP: { Server: "server.winlink.org", Port: 8772, UseTls: true }
    // Expected for Radio: { RadioId: int, Station: StationInfo }
    if (data is! Map) return;

    final server = data['Server'] as String?;

    if (server != null && server.isNotEmpty) {
      // TCP/Internet sync
      final port = (data['Port'] as int?) ?? 8772;
      final useTls = (data['UseTls'] as bool?) ?? true;

      _broker.logInfo(
        '[WinlinkClient] Starting TCP sync to $server:$port (TLS: $useTls)',
      );
      _transportType = WinlinkTransportType.tcp;
      // Fresh user-initiated connection: reset retry tracking.
      _tcpRetryCount = 0;
      _userDisconnect = false;
      unawaited(connectTcp(server, port, useTls: useTls));
    } else {
      // X25/Radio sync - check for RadioId and Station
      final radioId = data['RadioId'] as int?;
      final stationObj = data['Station'];

      if (radioId != null && stationObj is StationInfo) {
        _broker.logInfo(
          '[WinlinkClient] Starting X25 sync via radio $radioId to ${stationObj.callsign}',
        );
        _startRadioSync(radioId, stationObj);
      } else {
        _broker.logInfo('[WinlinkClient] Legacy X25 connection mode');
        _transportType = WinlinkTransportType.x25;
      }
    }
  }

  /// Starts a Winlink sync using a radio with the specified station. Locks the
  /// radio and begins the X25 connection process.
  void _startRadioSync(int radioId, StationInfo station) {
    if (radioId <= 0) return;

    // Get the current region from HtStatus
    final htStatusJson = _broker.getValueDynamic(radioId, 'HtStatus');
    final regionId =
        (htStatusJson is Map ? htStatusJson['currRegion'] as int? : null) ?? 0;

    // Look up the channel ID from the channel name
    int channelId = -1;
    if (station.channel.isNotEmpty) {
      final channels = _broker.getValueDynamic(radioId, 'Channels');
      if (channels is List) {
        for (int i = 0; i < channels.length; i++) {
          final channel = channels[i];
          if (channel is Map && channel['name'] == station.channel) {
            channelId = (channel['channelId'] as int?) ?? i;
            break;
          }
        }
      }
    }

    // If no channel found, report error and don't lock the radio
    if (channelId < 0) {
      _broker.logError(
        "[WinlinkClient] Channel '${station.channel}' not found on radio $radioId",
      );
      _errorMessage("Channel '${station.channel}' not found on radio.");
      return;
    }

    _broker.logInfo(
      '[WinlinkClient] Locking radio $radioId for Winlink, channel $channelId, region $regionId',
    );

    // Store the radio for later unlock
    _lockedRadioId = radioId;

    // Lock the radio to Winlink usage
    final lockData = SetLockData(
      usage: 'Winlink',
      regionId: regionId,
      channelId: channelId,
    );
    _broker.dispatch(
      deviceId: radioId,
      name: 'SetLock',
      data: lockData,
      store: false,
    );

    // Set up X25 transport
    _transportType = WinlinkTransportType.x25;

    // Clear debug history for new session
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkDebugClear',
      data: true,
      store: false,
    );

    _stateMessage('Connecting to ${station.callsign} via radio...');

    // Initialize the AX25Session and start the connection
    _initializeAX25Session(radioId, station);
  }

  /// Initializes an AX25Session and starts connecting to the station.
  void _initializeAX25Session(int radioId, StationInfo station) {
    // Dispose any existing session
    _disposeAX25Session();

    // Get our callsign from settings
    final myCallsignWithId =
        _broker.getValue<String>(0, 'Callsign', 'N0CALL-0') ?? 'N0CALL-0';
    String myCallsign;
    int myStationId;
    final myParsed = RadioUtils.parseCallsignWithId(myCallsignWithId);
    if (myParsed == null) {
      myCallsign = myCallsignWithId;
      myStationId = 0;
    } else {
      myCallsign = myParsed.callsign;
      myStationId = myParsed.stationId;
    }

    // Parse the destination callsign
    String destCallsign;
    int destStationId;
    final destParsed = RadioUtils.parseCallsignWithId(station.callsign);
    if (destParsed == null) {
      destCallsign = station.callsign;
      destStationId = 0;
    } else {
      destCallsign = destParsed.callsign;
      destStationId = destParsed.stationId;
    }

    _broker.logInfo(
      '[WinlinkClient] Initializing AX25Session: $myCallsign-$myStationId -> $destCallsign-$destStationId',
    );

    // Create the session
    final session = AX25Session(radioId);
    session.callSignOverride = myCallsign;
    session.stationIdOverride = myStationId;

    // Subscribe to session events
    session.onStateChanged = _onAX25SessionStateChanged;
    session.onDataReceived = _onAX25SessionDataReceived;
    session.onError = _onAX25SessionError;
    _ax25Session = session;

    // Create addresses: destination, source
    final destAddress = AX25Address.getAddress(destCallsign, destStationId);
    final srcAddress = AX25Address.getAddress(myCallsign, myStationId);
    if (destAddress == null || srcAddress == null) {
      _broker.logError('[WinlinkClient] Failed to build AX25 addresses');
      _errorMessage('Invalid callsign for AX25 session.');
      return;
    }
    final addresses = <AX25Address>[destAddress, srcAddress];

    // Start the connection
    session.connect(addresses);
  }

  /// Disposes the current AX25Session and cleans up resources.
  void _disposeAX25Session() {
    final session = _ax25Session;
    if (session != null) {
      _broker.logInfo('[WinlinkClient] Disposing AX25Session');

      // Unsubscribe from events
      session.onStateChanged = null;
      session.onDataReceived = null;
      session.onError = null;

      // Disconnect if connected
      if (session.currentState == AX25ConnectionState.connected ||
          session.currentState == AX25ConnectionState.connecting) {
        session.disconnect();
      }

      // Dispose the session
      session.dispose();
      _ax25Session = null;
    }
  }

  void _onAX25SessionStateChanged(
    AX25Session sender,
    AX25ConnectionState state,
  ) {
    _broker.logInfo('[WinlinkClient] AX25Session state changed: ${state.name}');

    switch (state) {
      case AX25ConnectionState.connected:
        final addresses = sender.addresses;
        if (addresses != null && addresses.isNotEmpty) {
          _remoteAddress = addresses[0].toString();
        }
        _setConnectionState(WinlinkConnectionState.connected);
        break;
      case AX25ConnectionState.connecting:
        final addresses = sender.addresses;
        if (addresses != null && addresses.isNotEmpty) {
          _remoteAddress = addresses[0].toString();
        }
        _setConnectionState(WinlinkConnectionState.connecting);
        break;
      case AX25ConnectionState.disconnected:
        _pendingDisconnect = false;
        _setConnectionState(WinlinkConnectionState.disconnected);
        _disposeAX25Session();
        break;
      case AX25ConnectionState.disconnecting:
        _setConnectionState(WinlinkConnectionState.disconnecting);
        break;
    }
  }

  void _onAX25SessionDataReceived(AX25Session sender, Uint8List data) {
    if (data.isEmpty) return;

    _broker.logInfo(
      '[WinlinkClient] AX25Session received ${data.length} bytes',
    );

    // Copy session state from AX25Session
    _sessionState = sender.sessionState;
    final addresses = sender.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      _remoteAddress = addresses[0].toString();
    }

    // Process the received data
    _processStream(data);
  }

  void _onAX25SessionError(AX25Session sender, String error) {
    _broker.logError('[WinlinkClient] AX25Session error: $error');
    _errorMessage('Session error: $error');
  }

  /// Unlocks the radio that was locked for Winlink usage.
  void _unlockRadio() {
    if (_lockedRadioId > 0) {
      _broker.logInfo('[WinlinkClient] Unlocking radio $_lockedRadioId');
      final unlockData = SetUnlockData(usage: 'Winlink');
      _broker.dispatch(
        deviceId: _lockedRadioId,
        name: 'SetUnlock',
        data: unlockData,
        store: false,
      );
      _lockedRadioId = -1;
    }
  }

  void _onWinlinkDisconnect(int deviceId, String name, Object? data) {
    if (_disposed) return;

    _broker.logInfo(
      '[WinlinkClient] Disconnect requested, transport: ${_transportType.name}',
    );

    // User-initiated disconnect: do not auto-retry.
    _userDisconnect = true;

    if (_transportType == WinlinkTransportType.tcp) {
      disconnectTcp();
    } else if (_transportType == WinlinkTransportType.x25) {
      _disconnectX25();
    }
  }

  /// Disconnects the X25/AX25 session.
  void _disconnectX25() {
    final session = _ax25Session;
    if (session == null) return;

    // If we're already waiting for disconnect to complete, don't do anything
    if (_pendingDisconnect) return;

    _broker.logInfo('[WinlinkClient] Disconnecting X25 session');

    if (session.currentState == AX25ConnectionState.connected ||
        session.currentState == AX25ConnectionState.connecting) {
      _pendingDisconnect = true;
      session.disconnect();
    } else {
      _disposeAX25Session();
      _setConnectionState(WinlinkConnectionState.disconnected);
    }
  }

  void _onWinlinkDebugClearHistory(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _debugHistory.clear();
  }

  void _onWinlinkDebugHistoryRequest(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final historyCopy = List<WinlinkDebugEntry>.from(_debugHistory);
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkDebugHistory',
      data: historyCopy,
      store: false,
    );
  }

  void _addToDebugHistory(
    String address,
    bool outgoing,
    String data, {
    bool isStateMessage = false,
  }) {
    if (data.isEmpty) return;
    _debugHistory.add(
      WinlinkDebugEntry(
        address: address,
        outgoing: outgoing,
        data: data,
        isStateMessage: isStateMessage,
      ),
    );
    while (_debugHistory.length > _maxDebugHistorySize) {
      _debugHistory.removeAt(0);
    }
  }

  void _transportSendString(String output) {
    if (output.isEmpty) return;
    final dataStrs = output
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (final str in dataStrs) {
      if (str.isEmpty) continue;
      final trimmedStr = str.trim();
      _addToDebugHistory(_remoteAddress, true, trimmedStr);
      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkTraffic',
        data: {'Address': _remoteAddress, 'Outgoing': true, 'Data': trimmedStr},
        store: false,
      );
    }

    if (_transportType == WinlinkTransportType.tcp) {
      _sendTcpString(output);
    } else if (_transportType == WinlinkTransportType.x25) {
      _sendX25String(output);
    }
  }

  void _transportSendBytes(Uint8List data) {
    if (data.isEmpty) return;
    if (_transportType == WinlinkTransportType.tcp) {
      _sendTcpBytes(data);
    } else if (_transportType == WinlinkTransportType.x25) {
      _sendX25Bytes(data);
    }
  }

  void _sendX25String(String data) {
    final session = _ax25Session;
    if (session != null &&
        session.currentState == AX25ConnectionState.connected) {
      _broker.logInfo('[WinlinkClient] SendX25 string: ${data.length} chars');
      session.sendString(data);
    } else {
      _broker.logError(
        '[WinlinkClient] SendX25 failed: session not connected (state: ${_ax25Session?.currentState.name ?? "null"})',
      );
    }
  }

  void _sendX25Bytes(Uint8List data) {
    final session = _ax25Session;
    if (session != null &&
        session.currentState == AX25ConnectionState.connected) {
      _broker.logInfo('[WinlinkClient] SendX25 binary: ${data.length} bytes');
      session.send(data);
    } else {
      _broker.logError(
        '[WinlinkClient] SendX25 binary failed: session not connected (state: ${_ax25Session?.currentState.name ?? "null"})',
      );
    }
  }

  void _sendTcpString(String data) {
    final socket = _tcpSocket;
    if (socket != null && _tcpRunning) {
      try {
        _broker.logInfo(
          '[WinlinkClient] Sending TCP data: ${data.length} chars',
        );
        socket.add(utf8.encode(data));
      } catch (ex) {
        _broker.logError('[WinlinkClient] TCP send error: $ex');
        _errorMessage('TCP Send error: $ex');
        disconnectTcp();
      }
    }
  }

  void _sendTcpBytes(Uint8List data) {
    final socket = _tcpSocket;
    if (socket != null && _tcpRunning) {
      try {
        _broker.logInfo(
          '[WinlinkClient] Sending TCP binary data: ${data.length} bytes',
        );
        socket.add(data);
      } catch (ex) {
        _broker.logError('[WinlinkClient] TCP send error: $ex');
        _errorMessage('TCP Send error: $ex');
        disconnectTcp();
      }
    }
  }

  void _stateMessage(String? msg) {
    if (msg != null && msg.isNotEmpty) {
      _addToDebugHistory(_remoteAddress, false, msg, isStateMessage: true);
    }
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      data: msg,
      store: false,
    );
  }

  /// Reports an error condition. The message is recorded in the debug history
  /// and dispatched as a transient state message, but is also dispatched as a
  /// dedicated [WinlinkError] event so that the UI can show it persistently
  /// (with a dismiss button) instead of having it cleared when the session
  /// disconnects.
  void _errorMessage(String msg) {
    if (msg.isNotEmpty) {
      _addToDebugHistory(_remoteAddress, false, msg, isStateMessage: true);
    }
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      data: msg,
      store: false,
    );
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkError',
      data: msg,
      store: false,
    );
  }

  void _setConnectionState(WinlinkConnectionState state) {
    if (state != _currentState) {
      _broker.logInfo(
        '[WinlinkClient] Connection state: ${_currentState.name} -> ${state.name}',
      );
      _currentState = state;
      _processTransportStateChange(state);

      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkConnectionState',
        data: state.name.toUpperCase(),
        store: false,
      );

      final isBusy = state != WinlinkConnectionState.disconnected;
      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkBusy',
        data: isBusy,
        store: false,
      );

      if (state == WinlinkConnectionState.disconnected) {
        _sessionState.clear();
        _remoteAddress = '';
        _unlockRadio();
      }
    }
  }

  /// Connects to a Winlink CMS server over TCP (optionally TLS).
  Future<bool> connectTcp(
    String server,
    int port, {
    bool useTls = false,
  }) async {
    if (_transportType != WinlinkTransportType.tcp) {
      _broker.logError(
        '[WinlinkClient] ConnectTcp called with wrong transport type: ${_transportType.name}',
      );
      _errorMessage(
        'Error: Cannot use TCP connection with X25 transport type.',
      );
      return false;
    }

    if (_currentState != WinlinkConnectionState.disconnected) {
      _broker.logError(
        '[WinlinkClient] ConnectTcp called while not disconnected: ${_currentState.name}',
      );
      _errorMessage('Error: Already connected or connecting.');
      return false;
    }

    try {
      _setConnectionState(WinlinkConnectionState.connecting);
      _remoteAddress = '$server:$port';
      _tcpServer = server;
      _tcpPort = port;
      _tcpUseTls = useTls;
      _sessionDataReceived = false;

      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkDebugClear',
        data: true,
        store: false,
      );

      _broker.logInfo('[WinlinkClient] Connecting TCP to $server:$port');
      _stateMessage('Connecting to $server...');

      if (useTls) {
        _stateMessage('Establishing secure connection...');
        _tcpSocket = await SecureSocket.connect(server, port);
        _broker.logInfo('[WinlinkClient] TLS connection established');
        _stateMessage('Secure connection established.');
      } else {
        _tcpSocket = await Socket.connect(server, port);
      }

      _setConnectionState(WinlinkConnectionState.connected);

      // Start receiving data
      _tcpRunning = true;
      _tcpSubscription = _tcpSocket!.listen(
        (data) => _processStream(data),
        onError: (Object ex) {
          if (_tcpRunning) {
            _broker.logError('[WinlinkClient] TCP receive error: $ex');
          }
          _handleTcpClosed(error: '$ex');
        },
        onDone: () {
          _handleTcpClosed();
        },
        cancelOnError: true,
      );

      return true;
    } catch (ex) {
      _broker.logError('[WinlinkClient] TCP connection failed: $ex');
      _setConnectionState(WinlinkConnectionState.disconnected);
      _cleanupTcp();
      // A failure to even connect can also be a transient pool issue; retry.
      if (_maybeRetryTcp()) return false;
      _errorMessage('TCP Connection failed: $ex');
      return false;
    }
  }

  /// Handles the TCP socket closing (remote end-of-stream or receive error).
  /// If the server dropped us before the Winlink session produced any data and
  /// the user did not request a disconnect, this is usually a transient
  /// load-balancer close on server.winlink.org, so we retry a few times.
  void _handleTcpClosed({String? error}) {
    if (!_tcpRunning) return;
    _tcpRunning = false;
    _cleanupTcp();
    _setConnectionState(WinlinkConnectionState.disconnected);

    if (_maybeRetryTcp()) return;

    if (!_userDisconnect && !_sessionDataReceived) {
      // Exhausted retries without ever establishing a session.
      _errorMessage(
        'Could not establish a Winlink session: the server kept closing '
        'the connection. Please try again in a moment.',
      );
    } else if (error != null && !_userDisconnect) {
      _errorMessage('TCP Receive error: $error');
    }
  }

  /// Schedules a reconnect attempt if the connection dropped before a session
  /// was established and retries remain. Returns true if a retry was scheduled.
  bool _maybeRetryTcp() {
    if (_disposed) return false;
    if (_userDisconnect) return false;
    if (_sessionDataReceived) return false;
    if (_tcpRetryCount >= _maxTcpRetries) return false;

    _tcpRetryCount++;
    _broker.logInfo(
      '[WinlinkClient] Server closed before session started; '
      'retry $_tcpRetryCount/$_maxTcpRetries',
    );
    _stateMessage(
      'Connection dropped, retrying ($_tcpRetryCount/$_maxTcpRetries)...',
    );

    final server = _tcpServer;
    final port = _tcpPort;
    final useTls = _tcpUseTls;
    Future.delayed(_tcpRetryDelay, () {
      if (_disposed) return;
      if (_userDisconnect) return;
      if (_currentState != WinlinkConnectionState.disconnected) return;
      _transportType = WinlinkTransportType.tcp;
      unawaited(connectTcp(server, port, useTls: useTls));
    });
    return true;
  }

  /// Disconnects the TCP connection.
  void disconnectTcp() {
    if (_transportType != WinlinkTransportType.tcp) return;

    _broker.logInfo('[WinlinkClient] Disconnecting TCP');
    _setConnectionState(WinlinkConnectionState.disconnecting);
    _tcpRunning = false;
    _cleanupTcp();
    _setConnectionState(WinlinkConnectionState.disconnected);
  }

  void _cleanupTcp() {
    try {
      _tcpSubscription?.cancel();
      _tcpSubscription = null;
      _tcpSocket?.destroy();
      _tcpSocket = null;
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  String _checksumHex(int checksum) {
    return ((-checksum) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  List<String> _parseProposalResponses(String value) {
    value = value
        .toUpperCase()
        .replaceAll('+', 'Y')
        .replaceAll('R', 'N')
        .replaceAll('-', 'N')
        .replaceAll('=', 'L')
        .replaceAll('H', 'L')
        .replaceAll('!', 'A');
    final responses = <String>[];
    String r = '';
    for (int i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        if (r.isNotEmpty) r += ch;
      } else {
        if (r.isNotEmpty) {
          responses.add(r);
          r = '';
        }
        r += ch;
      }
    }
    if (r.isNotEmpty) responses.add(r);
    return responses;
  }

  void _updateEmails() {
    // All good, save the new state of the mails
    if (_sessionState.containsKey('OutMails') &&
        _sessionState.containsKey('OutMailBlocks') &&
        _sessionState.containsKey('MailProposals')) {
      final proposedMails = _sessionState['OutMails'] as List<WinLinkMail>;
      final proposalResponses = _parseProposalResponses(
        _sessionState['MailProposals'] as String,
      );

      _broker.logInfo(
        '[WinlinkClient] UpdateEmails: ${proposedMails.length} proposed, ${proposalResponses.length} responses',
      );

      if (proposalResponses.length == proposedMails.length) {
        for (int j = 0; j < proposalResponses.length; j++) {
          if (proposalResponses[j] == 'Y' || proposalResponses[j] == 'N') {
            final mid = proposedMails[j].mid;
            _broker.logInfo(
              '[WinlinkClient] Moving mail $mid to Sent (response: ${proposalResponses[j]})',
            );
            _broker.dispatch(
              deviceId: 0,
              name: 'MailMove',
              data: {'MID': mid, 'Mailbox': 'Sent'},
              store: false,
            );
          }
        }
      }
    }
  }

  // Process stream data (unified for both TCP and X25)
  void _processStream(Uint8List data) {
    if (data.isEmpty) return;

    // The server sent us something, so the session is alive. This suppresses
    // the transient-drop auto-retry (which is only for connects that never
    // produce any data).
    _sessionDataReceived = true;

    // This is embedded mail sent in compressed format
    if (_sessionState.containsKey('wlMailBinary')) {
      final blocks = _sessionState['wlMailBinary'] as BytesBuilder;
      blocks.add(data);
      _stateMessage(
        'Receiving mail, ${blocks.length}${blocks.length < 2 ? " byte" : " bytes"}',
      );
      if (_extractMail(blocks)) {
        _broker.logInfo('[WinlinkClient] Mail reception complete, sending FF');
        _sessionState.remove('wlMailBinary');
        _sessionState.remove('wlMailBlocks');
        _sessionState.remove('wlMailProp');
        _transportSendString('FF\r');

        if (_transportType == WinlinkTransportType.tcp) {
          disconnectTcp();
        } else if (_transportType == WinlinkTransportType.x25) {
          _disconnectX25();
        }
      }
      return;
    }

    final dataStr = utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (final str in dataStrs) {
      if (str.isEmpty) continue;

      _addToDebugHistory(_remoteAddress, false, str);
      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkTraffic',
        data: {'Address': _remoteAddress, 'Outgoing': false, 'Data': str},
        store: false,
      );

      // Server-side notices/errors are prefixed with "***" (e.g. a failed
      // secure login because of a bad Winlink password). Surface them so the
      // user knows what went wrong before the server disconnects.
      final trimmed = str.trimLeft();
      if (trimmed.startsWith('***')) {
        var serverMsg = trimmed
            .replaceFirst(RegExp(r'^\*+\s*'), '')
            .replaceFirst(RegExp(r'^\[\d+\]\s*'), '')
            .trim();
        _broker.logError('[WinlinkClient] Server notice: $str');
        if (serverMsg.isNotEmpty) _errorMessage(serverMsg);
        // This is a terminal error from the server. Tear the connection down
        // immediately rather than waiting for the server (or the user) to close
        // it. The error was dispatched via WinlinkError above, so the UI keeps
        // showing it (with its OK button) independently of the disconnect.
        if (_transportType == WinlinkTransportType.tcp) {
          disconnectTcp();
        } else if (_transportType == WinlinkTransportType.x25) {
          _disconnectX25();
        }
        return;
      }

      // Handle TCP callsign prompt
      if (_transportType == WinlinkTransportType.tcp &&
          str.trim().toLowerCase() == 'callsign :') {
        final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
        final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
        final useStationId =
            (_broker.getValue<int>(0, 'WinlinkUseStationId', 0) ?? 0) == 1;

        var callsignResponse = callsign;
        if (useStationId && stationId > 0) callsignResponse += '-$stationId';
        callsignResponse += '\r';
        _broker.logInfo(
          '[WinlinkClient] Responding to callsign prompt: ${callsignResponse.trim()}',
        );
        _transportSendString(callsignResponse);
        _stateMessage('Sent callsign: ${callsignResponse.trim()}');
        continue;
      }

      // Handle TCP password prompt
      if (_transportType == WinlinkTransportType.tcp &&
          str.trim().toLowerCase() == 'password :') {
        _broker.logInfo('[WinlinkClient] Responding to password prompt');
        _transportSendString('CMSTelnet\r');
        continue;
      }

      if (str.endsWith('>') && !_sessionState.containsKey('SessionStart')) {
        _broker.logInfo('[WinlinkClient] Session start prompt received');
        _sessionState['SessionStart'] = 1;

        final sb = StringBuffer();

        // Send Information
        sb.write('[RMS Express-1.7.28.0-B2FHM\$]\r');

        // Send Authentication
        if (_sessionState.containsKey('WinlinkAuth')) {
          final winlinkPassword =
              _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';
          final authResponse = WinlinkSecurity.secureLoginResponse(
            _sessionState['WinlinkAuth'] as String,
            winlinkPassword,
          );
          if (winlinkPassword.isNotEmpty) sb.write(';PR: $authResponse\r');
          _broker.logInfo('[WinlinkClient] Sending authentication response');
          _stateMessage('Authenticating...');
        }

        // Get mails from MailStore via DataBroker handler
        final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
        final mails = mailStore?.getAllMails() ?? <WinLinkMail>[];

        // Send proposals with checksum
        final proposedMails = <WinLinkMail>[];
        final proposedMailsBinary = <List<Uint8List>>[];
        int checksum = 0;
        int mailSendCount = 0;
        for (final mail in mails) {
          if (mail.mailbox != 'Outbox' ||
              mail.mid == null ||
              mail.mid!.length != 12) {
            continue;
          }

          final encoded = WinLinkMail.encodeMailToBlocks(mail);
          final blocks = encoded.blocks;
          if (blocks != null) {
            proposedMails.add(mail);
            proposedMailsBinary.add(blocks);
            final proposal =
                'FC EM ${mail.mid} ${encoded.uncompressedSize} ${encoded.compressedSize} 0\r';
            sb.write(proposal);
            for (final cu in ascii.encode(proposal)) {
              checksum += cu;
            }
            mailSendCount++;
          }
        }
        if (mailSendCount > 0) {
          sb.write('F> ${_checksumHex(checksum)}\r');
          _broker.logInfo(
            '[WinlinkClient] Proposing $mailSendCount mail(s), checksum: ${_checksumHex(checksum)}',
          );
          _transportSendString(sb.toString());
          _sessionState['OutMails'] = proposedMails;
          _sessionState['OutMailBlocks'] = proposedMailsBinary;
          _stateMessage('Proposing $mailSendCount mail(s) to send...');
        } else {
          sb.write('FF\r');
          _broker.logInfo(
            '[WinlinkClient] No outgoing mail, sending FF to check for incoming',
          );
          _transportSendString(sb.toString());
          _stateMessage('Checking for new mail...');
        }
      } else {
        String key = str;
        String value = '';
        final i = str.indexOf(' ');
        if (i > 0) {
          key = str.substring(0, i).toUpperCase();
          value = str.substring(i + 1);
        }

        final winlinkPassword =
            _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';

        if (key == ';PQ:' && winlinkPassword.isNotEmpty) {
          // Winlink Authentication Request
          _broker.logInfo('[WinlinkClient] Received authentication challenge');
          _sessionState['WinlinkAuth'] = value;
        } else if (key == 'FS') {
          // Winlink Mail Transfer Approvals ("FS YY")
          _broker.logInfo('[WinlinkClient] Received proposal response: $value');
          if (_sessionState.containsKey('OutMails') &&
              _sessionState.containsKey('OutMailBlocks')) {
            final proposedMails =
                _sessionState['OutMails'] as List<WinLinkMail>;
            final proposedMailsBinary =
                _sessionState['OutMailBlocks'] as List<List<Uint8List>>;
            _sessionState['MailProposals'] = value;

            int sentMails = 0;
            final proposalResponses = _parseProposalResponses(value);
            if (proposalResponses.length == proposedMails.length) {
              int totalSize = 0;
              for (int j = 0; j < proposalResponses.length; j++) {
                if (proposalResponses[j] == 'Y') {
                  sentMails++;
                  _broker.logInfo(
                    '[WinlinkClient] Sending mail ${proposedMails[j].mid} (${proposedMailsBinary[j].length} blocks)',
                  );
                  for (final block in proposedMailsBinary[j]) {
                    _transportSendBytes(block);
                    totalSize += block.length;
                  }
                }
              }
              if (sentMails == 1) {
                _stateMessage('Sending mail, $totalSize bytes...');
              } else if (sentMails > 1) {
                _stateMessage('Sending $sentMails mails, $totalSize bytes...');
              } else {
                // Winlink Session Close
                _broker.logInfo(
                  '[WinlinkClient] No mails accepted, closing session',
                );
                _updateEmails();
                _stateMessage('No emails to transfer.');
                _transportSendString('FF\r');
              }
            } else {
              // Winlink Session Close
              _broker.logError(
                '[WinlinkClient] Proposal response count mismatch: expected ${proposedMails.length}, got ${proposalResponses.length}',
              );
              _stateMessage('Incorrect proposal response.');
              _transportSendString('FQ\r');
            }
          } else {
            // Winlink Session Close
            _broker.logError(
              '[WinlinkClient] Unexpected FS received without pending proposals',
            );
            _stateMessage('Unexpected proposal response.');
            _transportSendString('FQ\r');
          }
        } else if (key == 'FF') {
          // Winlink Session Close
          _broker.logInfo('[WinlinkClient] Received FF, session complete');
          _updateEmails();
          _transportSendString('FQ\r');
        } else if (key == 'FC') {
          // Winlink Mail Proposal
          _broker.logInfo('[WinlinkClient] Received mail proposal: $value');
          final proposals = _sessionState.containsKey('wlMailProp')
              ? _sessionState['wlMailProp'] as List<String>
              : <String>[];
          proposals.add(value);
          _sessionState['wlMailProp'] = proposals;
        } else if (key == 'F>') {
          // Winlink Mail Proposals completed, we need to respond
          _broker.logInfo(
            '[WinlinkClient] Mail proposals complete, checksum: $value',
          );
          if (_sessionState.containsKey('wlMailProp') &&
              !_sessionState.containsKey('wlMailBinary')) {
            final proposals = _sessionState['wlMailProp'] as List<String>?;
            final proposals2 = <String>[];
            if (proposals != null && proposals.isNotEmpty) {
              // Compute the proposal checksum
              int checksum = 0;
              for (final proposal in proposals) {
                for (final cu in ascii.encode('FC $proposal\r')) {
                  checksum += cu;
                }
              }
              if (_checksumHex(checksum) == value.toUpperCase()) {
                // Build a response
                String response = '';
                int acceptedProposalCount = 0;
                for (final proposal in proposals) {
                  final proposalSplit = proposal.split(' ');
                  if (proposalSplit.length >= 5 &&
                      proposalSplit[0] == 'EM' &&
                      proposalSplit[1].length == 12) {
                    final mFullLen = int.tryParse(proposalSplit[2]);
                    final mCompLen = int.tryParse(proposalSplit[3]);
                    final mUnknown = int.tryParse(proposalSplit[4]);
                    if (mFullLen != null &&
                        mCompLen != null &&
                        mUnknown != null) {
                      // Check if we already have this email
                      if (_weHaveEmail(proposalSplit[1])) {
                        _broker.logInfo(
                          '[WinlinkClient] Rejecting mail ${proposalSplit[1]} (already have it)',
                        );
                        response += 'N';
                      } else {
                        _broker.logInfo(
                          '[WinlinkClient] Accepting mail ${proposalSplit[1]}',
                        );
                        response += 'Y';
                        proposals2.add(proposal);
                        acceptedProposalCount++;
                      }
                    } else {
                      response += 'H';
                    }
                  } else {
                    response += 'H';
                  }
                }
                _broker.logInfo(
                  '[WinlinkClient] Sending proposal response: FS $response',
                );
                _transportSendString('FS $response\r');
                if (acceptedProposalCount > 0) {
                  _sessionState['wlMailBinary'] = BytesBuilder();
                  _sessionState['wlMailProp'] = proposals2;
                }
              } else {
                // Checksum failed
                _broker.logError(
                  '[WinlinkClient] Proposal checksum failed: expected ${_checksumHex(checksum)}, got $value',
                );
                _errorMessage('Checksum Failed');
                if (_transportType == WinlinkTransportType.tcp) {
                  disconnectTcp();
                } else if (_transportType == WinlinkTransportType.x25) {
                  _disconnectX25();
                }
              }
            }
          }
        } else if (key == 'FQ') {
          // Winlink Session Close
          _broker.logInfo(
            '[WinlinkClient] Received FQ, remote closing session',
          );
          _updateEmails();
          if (_transportType == WinlinkTransportType.tcp) {
            disconnectTcp();
          } else if (_transportType == WinlinkTransportType.x25) {
            _disconnectX25();
          }
        }
      }
    }
  }

  void _processTransportStateChange(WinlinkConnectionState state) {
    switch (state) {
      case WinlinkConnectionState.connected:
        _stateMessage('Connected to $_remoteAddress');
        break;
      case WinlinkConnectionState.disconnected:
        _stateMessage('Disconnected');
        _stateMessage(null);
        break;
      case WinlinkConnectionState.connecting:
        _stateMessage('Connecting...');
        break;
      case WinlinkConnectionState.disconnecting:
        _stateMessage('Disconnecting...');
        break;
    }
  }

  bool _extractMail(BytesBuilder blocks) {
    if (!_sessionState.containsKey('wlMailProp')) return false;
    final proposals = _sessionState['wlMailProp'] as List<String>?;
    if (proposals == null) return false;
    if (proposals.isEmpty || blocks.length == 0) return true;

    // Decode the proposal
    final proposalSplit = proposals[0].split(' ');
    final mid = proposalSplit[1];

    // See what we got
    final blockBytes = blocks.toBytes();
    final result = WinLinkMail.decodeBlocksToEmail(blockBytes);
    if (result.fail) {
      _broker.logError('[WinlinkClient] Failed to decode mail $mid');
      _errorMessage('Failed to decode mail.');
      return true;
    }
    final mail = result.mail;
    if (mail == null) return false;
    final dataConsumed = result.dataConsumed;
    blocks.clear();
    if (dataConsumed > 0) {
      if (dataConsumed < blockBytes.length) {
        blocks.add(blockBytes.sublist(dataConsumed));
      }
    } else {
      blocks.add(blockBytes);
    }
    proposals.removeAt(0);

    // Set the mailbox to Inbox for received mail
    mail.mailbox = 'Inbox';

    _broker.logInfo('[WinlinkClient] Received mail ${mail.mid} for ${mail.to}');

    // Add the received mail to the persistent store using broker event
    _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);

    _stateMessage('Got mail for ${mail.to}.');

    // Return true if all proposals have been processed
    return proposals.isEmpty;
  }

  bool _weHaveEmail(String mid) {
    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    return mailStore?.mailExists(mid) ?? false;
  }

  void dispose() {
    if (!_disposed) {
      _broker.logInfo('[WinlinkClient] Disposing');

      if (_currentState != WinlinkConnectionState.disconnected) {
        if (_transportType == WinlinkTransportType.tcp) {
          disconnectTcp();
        } else if (_transportType == WinlinkTransportType.x25) {
          _disposeAX25Session();
        }
      }

      _unlockRadio();

      _broker.dispose();

      _disposed = true;
    }
  }
}
