/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.BbsHandler` and `HTCommander.BBS` classes.

This is a two-part port:
  * [Bbs] is the per-radio BBS engine. It owns an [AX25Session], runs the
    bulletin-board conversation (M / S / D commands), and acts as a Winlink
    server, exchanging mail with connecting stations (either locally or by
    relaying to the Winlink CMS gateway). The adventure game is intentionally
    not ported.
  * [BbsHandler] is the manager (device 1). It creates/removes [Bbs] instances
    on `CreateBbs` / `RemoveBbs`, locks/unlocks the radio for "BBS" usage, and
    aggregates per-station statistics into a merged table broadcast as
    `BbsMergedStats`.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../radio/ax25_session.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../winlink/mail_store.dart';
import '../winlink/winlink_gateway_relay.dart';
import '../winlink/winlink_mail.dart';
import '../winlink/winlink_utils.dart';

// ---------------------------------------------------------------------------
// Data classes (broker payloads)
// ---------------------------------------------------------------------------

/// Statistics for a station that has connected to a single BBS instance.
class StationStats {
  String callsign = '';
  DateTime lastseen = DateTime.now();
  String protocol = '';
  int packetsIn = 0;
  int packetsOut = 0;
  int bytesIn = 0;
  int bytesOut = 0;
}

/// Per-device statistics for a station, used to build [MergedStationStats].
class DeviceStationStats {
  int packetsIn = 0;
  int packetsOut = 0;
  int bytesIn = 0;
  int bytesOut = 0;
}

/// Station statistics aggregated across all BBS instances.
class MergedStationStats {
  String callsign = '';
  DateTime lastSeen = DateTime.now();
  String protocol = '';
  int totalPacketsIn = 0;
  int totalPacketsOut = 0;
  int totalBytesIn = 0;
  int totalBytesOut = 0;
  final Map<int, DeviceStationStats> deviceStats = {};

  /// Human-readable summary matching the C# BBS tab stats column.
  String get statsString =>
      '$protocol, $totalPacketsIn in / $totalPacketsOut out, '
      '$totalBytesIn in / $totalBytesOut out';
}

/// Request payload for the `CreateBbs` command (device 1).
class CreateBbsData {
  final int radioDeviceId;
  final int channelId;
  final int regionId;

  CreateBbsData({
    required this.radioDeviceId,
    required this.channelId,
    required this.regionId,
  });
}

/// Request payload for the `RemoveBbs` command (device 1).
class RemoveBbsData {
  final int radioDeviceId;

  RemoveBbsData({required this.radioDeviceId});
}

/// Status of a single BBS instance (`BbsCreated` / `BbsList`).
class BbsStatusData {
  final int radioDeviceId;
  final int channelId;
  final int regionId;
  final bool enabled;

  BbsStatusData({
    required this.radioDeviceId,
    required this.channelId,
    required this.regionId,
    required this.enabled,
  });
}

/// Payload for the `BbsRemoved` event.
class BbsRemovedData {
  final int radioDeviceId;

  BbsRemovedData({required this.radioDeviceId});
}

/// Payload for the `BbsCreateFailed` / `BbsRemoveFailed` events.
class BbsErrorData {
  final int radioDeviceId;
  final String error;

  BbsErrorData({required this.radioDeviceId, required this.error});
}

/// Payload for the `BbsTraffic` event (a single line of BBS conversation).
class BbsTrafficData {
  final int deviceId;
  final String callsign;
  final bool outgoing;
  final String message;

  BbsTrafficData({
    required this.deviceId,
    required this.callsign,
    required this.outgoing,
    required this.message,
  });
}

/// Payload for the `BbsControlMessage` event (status / informational text).
class BbsControlMessageData {
  final int deviceId;
  final String message;

  BbsControlMessageData({required this.deviceId, required this.message});
}

/// Payload for the `BbsError` event (a session-level error).
class BbsErrorEventData {
  final int deviceId;
  final String error;

  BbsErrorEventData({required this.deviceId, required this.error});
}

/// Payload for the `BbsStatsUpdated` event from an individual BBS instance.
class BbsStatsUpdatedData {
  final int deviceId;
  final StationStats stats;

  BbsStatsUpdatedData({required this.deviceId, required this.stats});
}

/// Payload for the `BbsStatsCleared` event from an individual BBS instance.
class BbsStatsClearedData {
  final int deviceId;

  BbsStatsClearedData({required this.deviceId});
}

// ---------------------------------------------------------------------------
// Bbs: per-radio BBS engine
// ---------------------------------------------------------------------------

/// BBS (Bulletin Board System) engine for a specific radio device.
///
/// Each instance owns a single [AX25Session]. When a station connects it is
/// greeted with a banner, after which it can drive the menu (M / S / D) or
/// speak the Winlink B2F protocol to exchange mail. When possible the session
/// is relayed to the Winlink CMS gateway; otherwise mail is exchanged locally.
class Bbs {
  final int _deviceId;
  final int channelId;
  final int regionId;
  final DataBrokerClient _broker = DataBrokerClient();
  AX25Session? _session;
  WinlinkGatewayRelay? _cmsRelay;
  bool _disposed = false;

  /// Whether this BBS handler is enabled. When disabled, packets are ignored.
  bool enabled = false;

  /// Statistics for stations that have connected to this BBS.
  final Map<String, StationStats> stats = {};

  int get deviceId => _deviceId;
  AX25Session? get session => _session;

  Bbs(this._deviceId, {this.channelId = -1, this.regionId = -1}) {
    final session = AX25Session(_deviceId);
    session.onStateChanged = _onSessionStateChanged;
    session.onDataReceived = _onSessionDataReceived;
    session.onUiDataReceived = _onSessionUiDataReceived;
    session.onError = _onSessionError;
    _session = session;

    // Mirror the C# logging subscription for incoming BBS frames. The session
    // itself drives the AX.25 protocol via its own UniqueDataFrame
    // subscription; this is purely for diagnostics.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    _broker.logInfo(
      '[BBS/$_deviceId] BBS handler created for device $_deviceId',
    );
  }

  // ---- broker helpers -------------------------------------------------------

  void _dispatchTraffic(String callsign, bool outgoing, String message) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsTraffic',
      data: BbsTrafficData(
        deviceId: _deviceId,
        callsign: callsign,
        outgoing: outgoing,
        message: message,
      ),
      store: false,
    );
  }

  void _dispatchControl(String message) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsControlMessage',
      data: BbsControlMessageData(deviceId: _deviceId, message: message),
      store: false,
    );
  }

  // ---- session callbacks ----------------------------------------------------

  void _onUniqueDataFrame(int sourceDeviceId, String name, Object? data) {
    if (!enabled || _disposed) return;
    if (data is! TncDataFragment) return;
    if (data.radioDeviceId != _deviceId) return;
    final usage = data.usage;
    if (usage == null || usage.toUpperCase() != 'BBS') return;
    _broker.logInfo(
      '[BBS/$_deviceId] Received BBS frame from device $_deviceId',
    );
  }

  void _onSessionStateChanged(AX25Session sender, AX25ConnectionState state) {
    if (!enabled) return;
    _processStreamState(sender, state);
  }

  void _onSessionDataReceived(AX25Session sender, Uint8List data) {
    if (!enabled) return;
    _processStream(sender, data);
  }

  void _onSessionUiDataReceived(AX25Session sender, Uint8List data) {
    if (!enabled) return;
    _broker.logInfo('[BBS/$_deviceId] Received UI data: ${data.length} bytes');
  }

  void _onSessionError(AX25Session sender, String error) {
    _broker.logError('[BBS/$_deviceId] Session error: $error');
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsError',
      data: BbsErrorEventData(deviceId: _deviceId, error: error),
      store: false,
    );
  }

  // ---- statistics -----------------------------------------------------------

  void _updateStats(
    String callsign,
    String protocol,
    int packetIn,
    int packetOut,
    int bytesIn,
    int bytesOut,
  ) {
    if (!enabled) return;
    final s = stats[callsign] ?? StationStats();
    s.callsign = callsign;
    s.lastseen = DateTime.now();
    s.protocol = protocol;
    s.packetsIn += packetIn;
    s.packetsOut += packetOut;
    s.bytesIn += bytesIn;
    s.bytesOut += bytesOut;
    stats[callsign] = s;

    _broker.dispatch(
      deviceId: 0,
      name: 'BbsStatsUpdated',
      data: BbsStatsUpdatedData(deviceId: _deviceId, stats: s),
      store: false,
    );
  }

  /// Clears the statistics for this BBS instance.
  void clearStats() {
    stats.clear();
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsStatsCleared',
      data: BbsStatsClearedData(deviceId: _deviceId),
      store: false,
    );
  }

  String _remoteCallsign(AX25Session session) {
    final addrs = session.addresses;
    if (addrs == null || addrs.isEmpty) return '';
    return addrs[0].toString();
  }

  // ---- outbound text --------------------------------------------------------

  void _sessionSend(AX25Session session, String output) {
    if (!enabled) return;
    if (output.isEmpty) return;
    final dataStrs = output
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (int i = 0; i < dataStrs.length; i++) {
      if (dataStrs[i].trim().isEmpty && i == dataStrs.length - 1) continue;
      _dispatchTraffic(_remoteCallsign(session), true, dataStrs[i].trim());
    }
    _updateStats(_remoteCallsign(session), 'Stream', 0, 1, 0, output.length);
    session.send(Uint8List.fromList(utf8.encode(output)));
  }

  // ---- connection state -----------------------------------------------------

  void _processStreamState(AX25Session session, AX25ConnectionState state) {
    if (!enabled) return;
    switch (state) {
      case AX25ConnectionState.connected:
        _dispatchControl('Connected to ${_remoteCallsign(session)}');
        final addrs = session.addresses;
        final stationCallsign = (addrs != null && addrs.isNotEmpty)
            ? addrs[0].address
            : '';
        unawaited(_attemptCmsRelayConnect(session, stationCallsign));
        break;
      case AX25ConnectionState.disconnected:
        _dispatchControl('Disconnected');
        _cleanupCmsRelay();
        break;
      case AX25ConnectionState.connecting:
        _dispatchControl('Connecting...');
        break;
      case AX25ConnectionState.disconnecting:
        _dispatchControl('Disconnecting...');
        break;
    }
  }

  // ---- Winlink CMS relay ----------------------------------------------------

  Future<void> _attemptCmsRelayConnect(
    AX25Session session,
    String stationCallsign,
  ) async {
    try {
      _broker.logInfo(
        '[BBS/$_deviceId] Attempting CMS relay connection for $stationCallsign',
      );
      _dispatchControl('Connecting to Winlink gateway...');

      final relay = WinlinkGatewayRelay(_deviceId, _broker);
      final connected = await relay.connectAsync(
        stationCallsign,
        timeoutMs: 15000,
      );

      if (connected && relay.isConnected) {
        _broker.logInfo(
          '[BBS/$_deviceId] CMS relay connected, relay mode active',
        );
        _dispatchControl('Winlink gateway connected (relay mode)');

        _cmsRelay = relay;
        session.sessionState['wlRelayMode'] = true;

        relay.lineReceived = (line) => _onCmsRelayLineReceived(session, line);
        relay.binaryDataReceived = (data) =>
            _onCmsRelayBinaryReceived(session, data);
        relay.disconnected = () => _onCmsRelayDisconnected(session);

        final sb = StringBuffer();
        sb.write('Handy-Talky Commander BBS\r[M] for menu\r');
        if (relay.wl2kBanner != null && relay.wl2kBanner!.isNotEmpty) {
          sb.write('${relay.wl2kBanner}\r');
        } else {
          sb.write('[WL2K-5.0-B2FWIHJM\$]\r');
        }
        if (relay.pqChallenge != null && relay.pqChallenge!.isNotEmpty) {
          sb.write(';PQ: ${relay.pqChallenge}\r');
        }
        sb.write('>\r');
        _sessionSend(session, sb.toString());
      } else {
        _broker.logInfo(
          '[BBS/$_deviceId] CMS relay failed, falling back to local mode',
        );
        _dispatchControl('Winlink gateway unavailable (local mode)');
        relay.dispose();
        _sendLocalBanner(session);
      }
    } catch (ex) {
      _broker.logError('[BBS/$_deviceId] CMS relay connect error: $ex');
      _dispatchControl('Winlink gateway error (local mode)');
      _sendLocalBanner(session);
    }
  }

  void _sendLocalBanner(AX25Session session) {
    session.sessionState['wlRelayMode'] = false;
    session.sessionState['wlChallenge'] = WinlinkSecurity.generateChallenge();

    final sb = StringBuffer();
    sb.write('Handy-Talky Commander BBS\r[M] for menu\r');
    sb.write('[WL2K-5.0-B2FWIHJM\$]\r');

    final winlinkPassword =
        _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';
    if (winlinkPassword.isNotEmpty) {
      sb.write(';PQ: ${session.sessionState["wlChallenge"]}\r');
    }
    sb.write('>\r');
    _sessionSend(session, sb.toString());
  }

  void _onCmsRelayLineReceived(AX25Session session, String line) {
    if (!enabled || _disposed) return;
    if (session.currentState != AX25ConnectionState.connected) return;

    _broker.logInfo('[BBS/$_deviceId] CMS->Radio: $line');
    _dispatchControl('Gateway->Radio: ${utf8.encode(line).length} bytes');

    String key = line.toUpperCase();
    String value = '';
    final i = line.indexOf(' ');
    if (i > 0) {
      key = line.substring(0, i).toUpperCase();
      value = line.substring(i + 1);
    }

    if (key == 'FS' && value.toUpperCase().contains('Y')) {
      session.sessionState['wlRelayBinary'] = true;
      _cmsRelay?.binaryMode = true;
    }
    if (key == 'FF' || key == 'FQ') {
      session.sessionState['wlRelayBinary'] = false;
      _cmsRelay?.binaryMode = false;
    }

    _sessionSend(session, '$line\r');
  }

  void _onCmsRelayBinaryReceived(AX25Session session, Uint8List data) {
    if (!enabled || _disposed) return;
    if (session.currentState != AX25ConnectionState.connected) return;

    _broker.logInfo('[BBS/$_deviceId] CMS->Radio: ${data.length} binary bytes');
    _dispatchControl('Gateway->Radio: ${data.length} bytes (binary)');
    _updateStats(_remoteCallsign(session), 'Stream', 0, 1, 0, data.length);
    session.send(data);
  }

  void _onCmsRelayDisconnected(AX25Session session) {
    if (_disposed) return;
    _broker.logInfo('[BBS/$_deviceId] CMS relay disconnected');
    _dispatchControl('Winlink gateway disconnected');

    final isRelayMode = session.sessionState['wlRelayMode'] == true;
    if (isRelayMode && session.currentState == AX25ConnectionState.connected) {
      session.disconnect();
    }
  }

  void _cleanupCmsRelay() {
    final relay = _cmsRelay;
    if (relay != null) {
      try {
        relay.disconnect();
        relay.dispose();
      } catch (_) {}
      _cmsRelay = null;
    }
  }

  // ---- inbound data ---------------------------------------------------------

  void _processStream(AX25Session session, Uint8List data) {
    if (!enabled) return;
    if (data.isEmpty) return;
    _updateStats(_remoteCallsign(session), 'Stream', 1, 0, data.length, 0);

    final mode = session.sessionState['mode'] as String?;
    if (mode == 'mail') {
      _processMailStream(session, data);
      return;
    }
    _processBbsStream(session, data);
  }

  void _processBbsStream(AX25Session session, Uint8List data) {
    if (!enabled) return;

    final dataStr = utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    final sb = StringBuffer();
    for (int lineIndex = 0; lineIndex < dataStrs.length; lineIndex++) {
      final str = dataStrs[lineIndex];
      if (str.isEmpty) continue;
      _dispatchTraffic(_remoteCallsign(session), false, str.trim());

      // Switch to Winlink mail mode when the station sends a WL2K SID.
      if (!session.sessionState.containsKey('mode') &&
          str.length > 6 &&
          str.indexOf('-') > 0 &&
          str.startsWith('[') &&
          str.endsWith('\$]')) {
        session.sessionState['mode'] = 'mail';
        final remainingData = StringBuffer();
        remainingData.write(str);
        for (int j = lineIndex + 1; j < dataStrs.length; j++) {
          remainingData.write('\r');
          remainingData.write(dataStrs[j]);
        }
        _processMailStream(
          session,
          Uint8List.fromList(utf8.encode(remainingData.toString())),
        );
        return;
      } else if (_cmsRelay != null) {
        // First command is not a Winlink SID — they want BBS features, so
        // drop the CMS relay and continue locally.
        _broker.logInfo(
          '[BBS/$_deviceId] User sent BBS command, disconnecting Winlink gateway relay',
        );
        _dispatchControl('Disconnecting Winlink gateway (BBS mode)');
        session.sessionState['wlRelayMode'] = false;
        _cleanupCmsRelay();
      }

      String key = str.toUpperCase();
      String value = '';
      final i = str.indexOf(' ');
      if (i > 0) {
        key = str.substring(0, i).toUpperCase();
        value = str.substring(i + 1);
      }
      // value is currently unused by BBS commands but parsed for parity.
      value;

      if (key == 'M' || key == 'MENU') {
        sb.write('Welcome to our BBS\r');
        sb.write('---\r');
        sb.write('[M]ain menu\r');
        sb.write('[D]isconnect\r');
        sb.write('[S]oftware information\r');
        sb.write('---\r');
      } else if (key == 'S' || key == 'SOFTWARE') {
        sb.write(
          'This BBS is run by Handy-Talky Commander, an open source software '
          'available at https://github.com/Ylianst/HTCommander. This BBS can '
          'also handle Winlink messages in a limited way.\r',
        );
      } else if (key == 'D' || key == 'DISC' || key == 'DISCONNECT') {
        session.disconnect();
        return;
      }

      _sessionSend(session, sb.toString());
    }
  }

  // ---- Winlink mail server --------------------------------------------------

  void _processMailStream(AX25Session session, Uint8List data) {
    if (!enabled) return;

    // In relay mode, forward all data to the CMS gateway.
    final isRelayMode = session.sessionState['wlRelayMode'] == true;
    if (isRelayMode && _cmsRelay != null && _cmsRelay!.isConnected) {
      _processMailStreamRelay(session, data);
      return;
    }

    // --- Local P2P mode (fallback) ---

    // Compressed mail blocks being received from the station.
    if (session.sessionState.containsKey('wlMailBinary')) {
      final blocks = session.sessionState['wlMailBinary'] as List<int>;
      blocks.addAll(data);
      _dispatchControl(
        'Receiving mail, ${blocks.length}${blocks.length < 2 ? " byte" : " bytes"}',
      );
      if (_extractMail(session, blocks)) {
        session.sessionState.remove('wlMailBinary');
        session.sessionState.remove('wlMailBlocks');
        session.sessionState.remove('wlMailProp');
        _sendProposals(session, false);
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
      _dispatchTraffic(_remoteCallsign(session), false, str.trim());

      String key = str.toUpperCase();
      String value = '';
      final i = str.indexOf(' ');
      if (i > 0) {
        key = str.substring(0, i).toUpperCase();
        value = str.substring(i + 1);
      }

      final winlinkPassword =
          _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';

      if (key == ';PR:' && winlinkPassword.isNotEmpty) {
        // Winlink authentication response.
        final challenge = session.sessionState['wlChallenge'] as String? ?? '';
        if (WinlinkSecurity.secureLoginResponse(challenge, winlinkPassword) ==
            value) {
          session.sessionState['wlAuth'] = 'OK';
          _dispatchControl('Authentication Success');
          _broker.logInfo('[BBS/$_deviceId] Winlink Auth Success');
        } else {
          _dispatchControl('Authentication Failed');
          _broker.logInfo('[BBS/$_deviceId] Winlink Auth Failed');
        }
      } else if (key == 'FC') {
        // Winlink mail proposal.
        final proposals =
            (session.sessionState['wlMailProp'] as List<String>?) ?? <String>[];
        proposals.add(value);
        session.sessionState['wlMailProp'] = proposals;
      } else if (key == 'F>') {
        // Proposals completed — respond with accept/reject for each.
        if (session.sessionState.containsKey('wlMailProp') &&
            !session.sessionState.containsKey('wlMailBinary')) {
          final proposals = session.sessionState['wlMailProp'] as List<String>;
          final proposals2 = <String>[];
          if (proposals.isNotEmpty) {
            int checksum = 0;
            for (final proposal in proposals) {
              final proposalBin = ascii.encode('FC $proposal\r');
              for (final b in proposalBin) {
                checksum += b;
              }
            }
            checksum = (-checksum) & 0xFF;
            if (_hex2(checksum) == value) {
              final response = StringBuffer();
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
                    if (_weHaveEmail(proposalSplit[1])) {
                      response.write('N');
                    } else {
                      response.write('Y');
                      proposals2.add(proposal);
                      acceptedProposalCount++;
                    }
                  } else {
                    response.write('H');
                  }
                } else {
                  response.write('H');
                }
              }
              _sessionSend(session, 'FS $response\r');
              if (acceptedProposalCount > 0) {
                session.sessionState['wlMailBinary'] = <int>[];
                session.sessionState['wlMailProp'] = proposals2;
              }
            } else {
              _dispatchControl('Checksum Failed');
              session.disconnect();
            }
          }
        }
      } else if (key == 'FF') {
        // Station has no more mail for us — send ours back.
        _updateEmails(session);
        _sendProposals(session, true);
      } else if (key == 'FQ') {
        // Winlink session close.
        session.disconnect();
      } else if (key == 'FS') {
        // Station responded to our proposals — send the accepted mails.
        if (session.sessionState.containsKey('OutMails') &&
            session.sessionState.containsKey('OutMailBlocks')) {
          final proposedMails =
              session.sessionState['OutMails'] as List<WinLinkMail>;
          final proposedMailsBinary =
              session.sessionState['OutMailBlocks'] as List<List<Uint8List>>;
          session.sessionState['MailProposals'] = value;

          int sentMails = 0;
          final proposalResponses = _parseProposalResponses(value);
          if (proposalResponses.length == proposedMails.length) {
            int totalSize = 0;
            for (int j = 0; j < proposalResponses.length; j++) {
              if (proposalResponses[j] == 'Y') {
                sentMails++;
                for (final block in proposedMailsBinary[j]) {
                  session.send(block);
                  totalSize += block.length;
                }
              }
            }
            if (sentMails == 1) {
              _dispatchControl('Sending mail, $totalSize bytes...');
            } else if (sentMails > 1) {
              _dispatchControl('Sending $sentMails mails, $totalSize bytes...');
            } else {
              _updateEmails(session);
              _dispatchControl('No emails to transfer.');
              _sessionSend(session, 'FQ');
            }
          } else {
            _dispatchControl('Incorrect proposal response.');
            _sessionSend(session, 'FQ');
          }
        } else {
          _dispatchControl('Unexpected proposal response.');
          _sessionSend(session, 'FQ');
        }
      } else if (key == 'ECHO') {
        _sessionSend(session, '$value\r');
      }
    }
  }

  void _processMailStreamRelay(AX25Session session, Uint8List data) {
    if (!enabled) return;
    final relay = _cmsRelay;
    if (relay == null || !relay.isConnected) return;

    // Binary relay mode: forward raw bytes to CMS.
    if (session.sessionState['wlRelayBinary'] == true) {
      _broker.logInfo(
        '[BBS/$_deviceId] Radio->CMS (binary): ${data.length} bytes',
      );
      _dispatchControl('Radio->Gateway: ${data.length} bytes (binary)');
      relay.sendBinary(data);
      _updateStats(_remoteCallsign(session), 'Stream', 1, 0, data.length, 0);
      return;
    }

    // Text mode: parse lines and forward to CMS.
    _dispatchControl('Radio->Gateway: ${data.length} bytes');
    final dataStr = utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (final str in dataStrs) {
      if (str.isEmpty) continue;
      _dispatchTraffic(_remoteCallsign(session), false, str.trim());
      _broker.logInfo('[BBS/$_deviceId] Radio->CMS: $str');

      String key = str.toUpperCase();
      final i = str.indexOf(' ');
      if (i > 0) {
        key = str.substring(0, i).toUpperCase();
      }

      if (key == 'FS') {
        final value = i > 0 ? str.substring(i + 1) : '';
        if (value.toUpperCase().contains('Y')) {
          session.sessionState['wlRelayBinary'] = true;
          relay.binaryMode = true;
        }
      }
      if (key == 'FF') {
        session.sessionState['wlRelayBinary'] = false;
        relay.binaryMode = false;
      }
      if (key == 'FQ') {
        session.sessionState['wlRelayBinary'] = false;
        relay.binaryMode = false;
      }

      relay.sendLine(str);
    }
  }

  void _sendProposals(AX25Session session, bool lastExchange) {
    if (!enabled) return;

    final sb = StringBuffer();
    final proposedMails = <WinLinkMail>[];
    final proposedMailsBinary = <List<Uint8List>>[];
    int checksum = 0;
    int mailSendCount = 0;

    String connectedCallsign = '';
    final addrs = session.addresses;
    if (addrs != null && addrs.isNotEmpty) {
      connectedCallsign = addrs[0].address;
    }

    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    final mails = mailStore?.getAllMails() ?? <WinLinkMail>[];

    for (final mail in mails) {
      if (mail.mailbox != 'Outbox' ||
          mail.mid == null ||
          mail.mid!.length != 12) {
        continue;
      }
      final isForStation = WinLinkMail.isMailForStation(
        connectedCallsign,
        mail.to,
        mail.cc,
        onOthers: (_) {},
      );
      if (!isForStation) continue;

      final enc = WinLinkMail.encodeMailToBlocks(mail);
      final blocks = enc.blocks;
      if (blocks != null) {
        proposedMails.add(mail);
        proposedMailsBinary.add(blocks);
        final proposal =
            'FC EM ${mail.mid} ${enc.uncompressedSize} ${enc.compressedSize} 0\r';
        sb.write(proposal);
        final proposalBin = ascii.encode(proposal);
        for (final b in proposalBin) {
          checksum += b;
        }
        mailSendCount++;
        _broker.logInfo(
          '[BBS/$_deviceId] Proposing mail ${mail.mid} for ${mail.to} to $connectedCallsign',
        );
      }
    }

    if (mailSendCount > 0) {
      checksum = (-checksum) & 0xFF;
      sb.write('F> ${_hex2(checksum)}\r');
      session.sessionState['OutMails'] = proposedMails;
      session.sessionState['OutMailBlocks'] = proposedMailsBinary;
      _broker.logInfo(
        '[BBS/$_deviceId] Proposing $mailSendCount mail(s) to $connectedCallsign, checksum: ${_hex2(checksum)}',
      );
    } else {
      sb.write(lastExchange ? 'FQ\r' : 'FF\r');
    }
    _sessionSend(session, sb.toString());
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
      final c = value[i];
      if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
        if (r.isNotEmpty) r += c;
      } else {
        if (r.isNotEmpty) {
          responses.add(r);
          r = '';
        }
        r += c;
      }
    }
    if (r.isNotEmpty) responses.add(r);
    return responses;
  }

  bool _extractMail(AX25Session session, List<int> blocks) {
    if (!session.sessionState.containsKey('wlMailProp')) return false;
    final proposals = session.sessionState['wlMailProp'] as List<String>?;
    if (proposals == null) return false;
    if (proposals.isEmpty || blocks.isEmpty) return true;

    // Decode the proposal.
    final proposalSplit = proposals[0].split(' ');
    if (proposalSplit.length < 4) return true; // Invalid proposal format.
    final mid = proposalSplit[1];

    final result = WinLinkMail.decodeBlocksToEmail(Uint8List.fromList(blocks));
    if (result.fail) {
      _dispatchControl('Failed to decode mail.');
      _broker.logError('[BBS/$_deviceId] Failed to decode mail $mid');
      return true;
    }
    final mail = result.mail;
    if (mail == null) return false;

    final dataConsumed = result.dataConsumed;
    if (dataConsumed > 0) {
      if (dataConsumed >= blocks.length) {
        blocks.clear();
      } else {
        blocks.removeRange(0, dataConsumed);
      }
    }
    proposals.removeAt(0);

    // Decide which mailbox to file the message under.
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final isForUs = WinLinkMail.isMailForStation(
      callsign,
      mail.to,
      mail.cc,
      onOthers: (_) {},
    );
    mail.mailbox = isForUs ? 'Inbox' : 'Outbox';

    _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);
    _dispatchControl('Got mail for ${mail.to}.');
    _broker.logInfo(
      '[BBS/$_deviceId] Received mail ${mail.mid} for ${mail.to}',
    );

    return proposals.isEmpty;
  }

  bool _weHaveEmail(String mid) {
    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    return mailStore?.mailExists(mid) ?? false;
  }

  void _updateEmails(AX25Session session) {
    if (!enabled) return;

    if (session.sessionState.containsKey('OutMails') &&
        session.sessionState.containsKey('OutMailBlocks') &&
        session.sessionState.containsKey('MailProposals')) {
      final proposedMails =
          session.sessionState['OutMails'] as List<WinLinkMail>;
      final proposalResponses = _parseProposalResponses(
        session.sessionState['MailProposals'] as String,
      );

      int mailsChanges = 0;
      if (proposalResponses.length == proposedMails.length) {
        for (int j = 0; j < proposalResponses.length; j++) {
          if (proposalResponses[j] == 'Y' || proposalResponses[j] == 'N') {
            proposedMails[j].mailbox = 'Sent';
            // TODO: Persist the mailbox change via the broker when supported.
            mailsChanges++;
          }
        }
      }

      if (mailsChanges > 0) {
        _broker.dispatch(
          deviceId: 0,
          name: 'BbsMailUpdated',
          data: {'deviceId': _deviceId, 'mailChanges': mailsChanges},
          store: false,
        );
      }
    }
  }

  static String _hex2(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// Disposes this BBS instance, tearing down the session and any relay.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _broker.logInfo('[BBS/$_deviceId] BBS handler disposing');

    _cleanupCmsRelay();

    final session = _session;
    if (session != null) {
      session.onStateChanged = null;
      session.onDataReceived = null;
      session.onUiDataReceived = null;
      session.onError = null;
      session.dispose();
      _session = null;
    }

    _broker.dispose();
  }
}

// ---------------------------------------------------------------------------
// BbsHandler: manager (device 1)
// ---------------------------------------------------------------------------

/// A data handler that manages BBS instances for radios.
///
/// Listens for BBS control commands on device 1 and creates/removes [Bbs]
/// instances for specific radios, locking each radio to a dedicated channel
/// while its BBS is active. Also aggregates station statistics from all BBS
/// instances into a merged table broadcast as `BbsMergedStats`.
class BbsHandler {
  static const int _bbsDeviceId = 1;

  final DataBrokerClient _broker = DataBrokerClient();
  final Map<int, Bbs> _bbsInstances = {};
  final Map<String, MergedStationStats> _mergedStats = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;
  int get activeBbsCount => _bbsInstances.length;

  /// Initializes the handler and subscribes to broker events.
  void init() {
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'CreateBbs',
      callback: _onCreateBbs,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'RemoveBbs',
      callback: _onRemoveBbs,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'GetBbsStatus',
      callback: _onGetBbsStatus,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'BbsStatsUpdated',
      callback: _onBbsStatsUpdated,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'BbsStatsCleared',
      callback: _onBbsStatsCleared,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'BbsClearAllStats',
      callback: _onBbsClearAllStats,
    );

    _broker.logInfo('[BbsHandler] BBS Handler initialized');
  }

  // ---- create / remove ------------------------------------------------------

  void _onCreateBbs(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! CreateBbsData) return;

    final radioDeviceId = data.radioDeviceId;
    final channelId = data.channelId;
    final regionId = data.regionId;

    if (_bbsInstances.containsKey(radioDeviceId)) {
      _broker.logError(
        '[BbsHandler] BBS instance already exists for radio $radioDeviceId',
      );
      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsCreateFailed',
        data: BbsErrorData(
          radioDeviceId: radioDeviceId,
          error: 'BBS instance already exists for this radio',
        ),
        store: false,
      );
      return;
    }

    // Lock the radio for BBS usage.
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'SetLock',
      data: SetLockData(usage: 'BBS', regionId: regionId, channelId: channelId),
      store: false,
    );

    final bbsInstance = Bbs(
      radioDeviceId,
      channelId: channelId,
      regionId: regionId,
    );
    bbsInstance.enabled = true;
    _bbsInstances[radioDeviceId] = bbsInstance;

    _broker.logInfo(
      '[BbsHandler] Created BBS instance for radio $radioDeviceId on channel $channelId, region $regionId',
    );

    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsCreated',
      data: BbsStatusData(
        radioDeviceId: radioDeviceId,
        channelId: channelId,
        regionId: regionId,
        enabled: true,
      ),
      store: false,
    );

    _dispatchBbsList();
  }

  void _onRemoveBbs(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! RemoveBbsData) return;

    final radioDeviceId = data.radioDeviceId;
    final bbsInstance = _bbsInstances[radioDeviceId];
    if (bbsInstance == null) {
      _broker.logError(
        '[BbsHandler] No BBS instance exists for radio $radioDeviceId',
      );
      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsRemoveFailed',
        data: BbsErrorData(
          radioDeviceId: radioDeviceId,
          error: 'No BBS instance exists for this radio',
        ),
        store: false,
      );
      return;
    }

    bbsInstance.enabled = false;
    bbsInstance.dispose();
    _bbsInstances.remove(radioDeviceId);

    _broker.logInfo(
      '[BbsHandler] Removed BBS instance for radio $radioDeviceId',
    );

    // Unlock the radio.
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'SetUnlock',
      data: SetUnlockData(usage: 'BBS'),
      store: false,
    );

    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsRemoved',
      data: BbsRemovedData(radioDeviceId: radioDeviceId),
      store: false,
    );

    _dispatchBbsList();
  }

  void _onGetBbsStatus(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _dispatchBbsList();
  }

  // ---- statistics aggregation ----------------------------------------------

  void _onBbsStatsUpdated(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! BbsStatsUpdatedData) return;

    final stats = data.stats;
    final sourceDeviceId = data.deviceId;
    if (stats.callsign.isEmpty) return;

    final key = stats.callsign.toUpperCase();
    var mergedStats = _mergedStats[key];
    if (mergedStats != null) {
      if (stats.lastseen.isAfter(mergedStats.lastSeen)) {
        mergedStats.lastSeen = stats.lastseen;
      }
      mergedStats.protocol = stats.protocol;
      final deviceStats = mergedStats.deviceStats[sourceDeviceId] ??=
          DeviceStationStats();
      deviceStats.packetsIn = stats.packetsIn;
      deviceStats.packetsOut = stats.packetsOut;
      deviceStats.bytesIn = stats.bytesIn;
      deviceStats.bytesOut = stats.bytesOut;
      _recalculateTotals(mergedStats);
    } else {
      mergedStats = MergedStationStats()
        ..callsign = stats.callsign
        ..lastSeen = stats.lastseen
        ..protocol = stats.protocol;
      mergedStats.deviceStats[sourceDeviceId] = DeviceStationStats()
        ..packetsIn = stats.packetsIn
        ..packetsOut = stats.packetsOut
        ..bytesIn = stats.bytesIn
        ..bytesOut = stats.bytesOut;
      _recalculateTotals(mergedStats);
      _mergedStats[key] = mergedStats;
    }

    _dispatchMergedStats();
  }

  void _recalculateTotals(MergedStationStats mergedStats) {
    mergedStats.totalPacketsIn = 0;
    mergedStats.totalPacketsOut = 0;
    mergedStats.totalBytesIn = 0;
    mergedStats.totalBytesOut = 0;
    for (final deviceStats in mergedStats.deviceStats.values) {
      mergedStats.totalPacketsIn += deviceStats.packetsIn;
      mergedStats.totalPacketsOut += deviceStats.packetsOut;
      mergedStats.totalBytesIn += deviceStats.bytesIn;
      mergedStats.totalBytesOut += deviceStats.bytesOut;
    }
  }

  void _onBbsStatsCleared(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! BbsStatsClearedData) return;

    final sourceDeviceId = data.deviceId;
    final keysToRemove = <String>[];
    _mergedStats.forEach((key, value) {
      if (value.deviceStats.containsKey(sourceDeviceId)) {
        value.deviceStats.remove(sourceDeviceId);
        if (value.deviceStats.isEmpty) {
          keysToRemove.add(key);
        } else {
          _recalculateTotals(value);
        }
      }
    });
    for (final key in keysToRemove) {
      _mergedStats.remove(key);
    }

    _dispatchMergedStats();
  }

  void _onBbsClearAllStats(int deviceId, String name, Object? data) {
    if (_disposed) return;

    _mergedStats.clear();
    for (final bbs in _bbsInstances.values) {
      bbs.clearStats();
    }

    _dispatchMergedStats();
  }

  void _dispatchMergedStats() {
    final statsList = List<MergedStationStats>.from(_mergedStats.values);
    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsMergedStats',
      data: statsList,
      store: true,
    );
  }

  // ---- radio lifecycle ------------------------------------------------------

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String) return;
    if (data != 'Disconnected') return;

    final bbsInstance = _bbsInstances[deviceId];
    if (bbsInstance != null) {
      _broker.logInfo(
        '[BbsHandler] Radio $deviceId disconnected, removing BBS instance',
      );
      bbsInstance.enabled = false;
      bbsInstance.dispose();
      _bbsInstances.remove(deviceId);

      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsRemoved',
        data: BbsRemovedData(radioDeviceId: deviceId),
        store: false,
      );

      _dispatchBbsList();
    }
  }

  void _dispatchBbsList() {
    final bbsList = <BbsStatusData>[];
    _bbsInstances.forEach((radioDeviceId, bbs) {
      bbsList.add(
        BbsStatusData(
          radioDeviceId: radioDeviceId,
          channelId: bbs.channelId,
          regionId: bbs.regionId,
          enabled: bbs.enabled,
        ),
      );
    });
    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsList',
      data: bbsList,
      store: true,
    );
  }

  /// Returns the BBS instance for [radioDeviceId], or null if none is active.
  Bbs? getBbsInstance(int radioDeviceId) => _bbsInstances[radioDeviceId];

  /// Returns the list of radio device IDs that currently have a BBS instance.
  List<int> getActiveBbsRadioIds() => List<int>.from(_bbsInstances.keys);

  /// Disposes the handler, cleaning up all BBS instances and unlocking radios.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _broker.logInfo('[BbsHandler] BBS Handler disposing');

    _bbsInstances.forEach((radioDeviceId, bbs) {
      bbs.enabled = false;
      bbs.dispose();
      _broker.dispatch(
        deviceId: radioDeviceId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'BBS'),
        store: false,
      );
    });
    _bbsInstances.clear();

    _broker.dispose();
  }
}
