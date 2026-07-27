/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import '../aprs/aprs_packet.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../radio/ax25_packet.dart';

/// Device id used for the internet-only APRS-IS pseudo-radio, mirroring the way
/// EchoLink occupies device 200. Kept distinct from the physical radios
/// (device 1+) so APRS-IS traffic never mixes into the RF packet store.
const int aprsIsDeviceId = 201;

/// High-level connection state of the APRS-IS client.
enum AprsIsConnectionState {
  disconnected,
  connecting,
  loggingIn,
  connected,
}

/// Abstraction over the raw TCP transport so [AprsIsClient] can be unit tested
/// against a fake network. The real implementation lives in
/// `aprsis_network_io.dart` (dart:io sockets); the web build never imports it.
abstract class AprsIsNetwork {
  /// Opens a TCP connection to [host]:[port]. Completes when connected.
  Future<void> connect(String host, int port);

  /// Sends a single protocol line. The implementation appends CR/LF.
  void sendLine(String line);

  /// Decoded text received from the server. Chunks are not guaranteed to be
  /// aligned to line boundaries; [AprsIsClient] reassembles complete lines.
  Stream<String> get incoming;

  /// Completes when the connection is closed or fails.
  Future<void> get done;

  /// Closes the connection.
  Future<void> close();
}

/// Pure APRS-IS protocol client: builds the login line, frames the inbound byte
/// stream into lines, tracks the login/verified state, and surfaces received
/// packets. It performs a single session; the manager owns the reconnect loop.
class AprsIsClient {
  AprsIsClient({
    required this.callsign,
    required this.passcode,
    required this.softwareName,
    required this.softwareVersion,
    required this.filter,
    required this.network,
  });

  /// Login callsign with SSID (e.g. "K7VZT-5"), upper-case.
  final String callsign;

  /// APRS-IS passcode. "-1" means receive-only (cannot send).
  final String passcode;

  final String softwareName;
  final String softwareVersion;

  /// Server-side filter string (without the leading "filter" keyword), or empty
  /// for none.
  final String filter;

  final AprsIsNetwork network;

  /// Called for every received APRS packet line (comments are filtered out).
  void Function(String tnc2Line)? onPacketLine;

  /// Called once the server acknowledges the login, with whether the connection
  /// is verified (a valid passcode was supplied and accepted).
  void Function(bool verified)? onLogin;

  /// Called with human-readable diagnostics for the debug log.
  void Function(String message)? onDiagnostic;

  AprsIsConnectionState _state = AprsIsConnectionState.disconnected;
  AprsIsConnectionState get state => _state;

  bool _verified = false;
  bool get isVerified => _verified;

  /// True when a valid (non "-1") passcode was configured, i.e. sending is
  /// permitted once verified by the server.
  bool get canTransmit => passcode.trim() != '-1' && passcode.trim().isNotEmpty;

  StreamSubscription<String>? _sub;
  final StringBuffer _lineBuffer = StringBuffer();

  /// Builds the APRS-IS login line (without CR/LF), e.g.
  /// `user K7VZT-5 pass 12345 vers HTCommander 0.1.21 filter r/47/-122/50`.
  String buildLoginLine() {
    final buffer = StringBuffer('user $callsign pass $passcode');
    if (softwareName.isNotEmpty) {
      buffer.write(' vers $softwareName $softwareVersion');
    }
    final f = filter.trim();
    if (f.isNotEmpty) buffer.write(' filter $f');
    return buffer.toString();
  }

  /// Connects, sends the login line, and begins processing inbound lines.
  Future<void> open(String host, int port) async {
    _state = AprsIsConnectionState.connecting;
    await network.connect(host, port);
    _state = AprsIsConnectionState.loggingIn;
    _sub = network.incoming.listen(_onData, onError: (Object e) {
      onDiagnostic?.call('[APRS-IS] Stream error: $e');
    });
    network.sendLine(buildLoginLine());
    onDiagnostic?.call('[APRS-IS] Connected to $host:$port, logging in as '
        '$callsign');
  }

  /// Sends a raw TNC2 packet line to APRS-IS. No-op on a receive-only login.
  void sendPacketLine(String tnc2Line) {
    if (!canTransmit) return;
    if (_state != AprsIsConnectionState.connected) return;
    network.sendLine(tnc2Line);
  }

  /// Updates the server-side filter live via a `#filter` command. Passing an
  /// empty [filter] resets the port to its default (messages addressed to us).
  /// Allowed on receive-only logins since filters only affect inbound traffic.
  void sendFilterCommand(String filter) {
    if (_state != AprsIsConnectionState.connected) return;
    network.sendLine(filter.isEmpty ? '#filter default' : '#filter $filter');
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _lineBuffer.clear();
    _state = AprsIsConnectionState.disconnected;
    await network.close();
  }

  void _onData(String chunk) {
    _lineBuffer.write(chunk);
    final text = _lineBuffer.toString();
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        var line = text.substring(start, i);
        if (line.isNotEmpty && line.codeUnitAt(line.length - 1) == 0x0D) {
          line = line.substring(0, line.length - 1);
        }
        _handleLine(line);
        start = i + 1;
      }
    }
    _lineBuffer.clear();
    if (start < text.length) _lineBuffer.write(text.substring(start));
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;
    // Server comment / keep-alive / login response lines start with '#'.
    if (line.codeUnitAt(0) == 0x23) {
      _handleServerComment(line);
      return;
    }
    onPacketLine?.call(line);
  }

  void _handleServerComment(String line) {
    // Login acknowledgement looks like:
    //   # logresp K7VZT-5 verified, server T2XYZ
    final lower = line.toLowerCase();
    if (lower.contains('logresp')) {
      _verified = lower.contains(' verified');
      _state = AprsIsConnectionState.connected;
      onDiagnostic?.call('[APRS-IS] Login response: ${line.substring(1).trim()}');
      onLogin?.call(_verified);
    }
  }

  // ---------------------------------------------------------------------------
  // Gating predicates (pure, static — unit tested without a network).
  // ---------------------------------------------------------------------------

  /// Path elements that mark a packet as "do not gate to the internet".
  static const List<String> _noGateMarkers = [
    'TCPIP',
    'TCPXX',
    'NOGATE',
    'RFONLY',
    'QAX',
    'QAC',
    'QAS',
    'QAR',
    'QAO',
  ];

  /// Decides whether a packet heard on RF should be gated up to APRS-IS.
  ///
  /// Follows the community IGate rules: only genuine UI frames that did not
  /// originate on APRS-IS, that are not generic queries, and whose path carries
  /// no `TCPIP`/`TCPXX`/`NOGATE`/`RFONLY` (or q-construct) marker. Third-party
  /// packets are conservatively not gated.
  static bool shouldGateToInternet(AprsPacket aprsPacket) {
    final packet = aprsPacket.packet;
    if (packet == null) return false;
    // Never gate a packet that already came from the internet.
    if (aprsPacket.fromAprsIs) return false;
    // Must be a UI frame with at least source + destination.
    if (packet.type != FrameType.uFrameUi &&
        packet.type != FrameType.uFrame) {
      return false;
    }
    if (packet.addresses.length < 2) return false;

    final dataStr = packet.dataStr;
    if (dataStr == null || dataStr.isEmpty) return false;

    // Generic queries (data type '?') are never gated.
    if (dataStr.codeUnitAt(0) == 0x3F) return false;
    if (aprsPacket.dataType == PacketDataType.query) return false;

    // Third-party packets ('}') are not gated by this client.
    if (dataStr.codeUnitAt(0) == 0x7D) return false;

    // Reject if any address in the path carries a no-gate marker.
    for (final addr in packet.addresses) {
      final call = addr.address.toUpperCase();
      for (final marker in _noGateMarkers) {
        if (call == marker) return false;
      }
    }
    return true;
  }

  /// Builds the TNC2 line to inject a RF-heard packet onto APRS-IS, appending
  /// the `,qAR,IGATECALL` construct required for gated-from-RF packets. Returns
  /// null when the packet cannot be gated.
  static String? buildGateUpLine(AprsPacket aprsPacket, String igateCall) {
    final packet = aprsPacket.packet;
    if (packet == null) return null;
    if (packet.addresses.length < 2) return null;
    final dataStr = packet.dataStr;
    if (dataStr == null || dataStr.isEmpty) return null;

    final dest = packet.addresses[0].toString();
    final src = packet.addresses[1].toString();
    final buffer = StringBuffer('$src>$dest');
    for (var i = 2; i < packet.addresses.length; i++) {
      buffer.write(',');
      buffer.write(packet.addresses[i].toString());
    }
    buffer.write(',qAR,');
    buffer.write(igateCall);
    buffer.write(':');
    buffer.write(dataStr);
    return buffer.toString();
  }

  /// Decides whether an APRS-IS message packet should be gated down to RF.
  ///
  /// Only text messages (not acks/rejects handled elsewhere) addressed to a
  /// station in [heardCallsigns] (heard recently on RF) are gated. The sender
  /// must not itself be a locally-heard station to avoid echoing RF traffic.
  static bool shouldGateToRf(
    AprsPacket aprsPacket,
    Set<String> heardCallsigns,
  ) {
    if (aprsPacket.dataType != PacketDataType.message) return false;
    final md = aprsPacket.messageData;
    if (md.msgType == MessageType.mtAck || md.msgType == MessageType.mtRej) {
      return false;
    }
    final addressee = md.addressee.trim().toUpperCase();
    if (addressee.isEmpty) return false;
    return heardCallsigns.contains(addressee);
  }
}
