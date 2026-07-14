/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../dialogs/active_station_selector_dialog.dart';
import '../l10n/app_localizations.dart';
import '../models/radio_models.dart';
import '../models/station_info.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/ax25_session.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Represents a piece of text with a specific color in the terminal.
class TerminalTextSpan {
  final String text;
  final Color color;
  final bool bold;

  const TerminalTextSpan(
    this.text, {
    this.color = Colors.white70,
    this.bold = false,
  });
}

/// Terminal tab - a packet-radio terminal ported from the C#
/// `TerminalTabUserControl`.
///
/// Connects to a configured Terminal station over a connected radio by locking
/// the radio to "Terminal" usage on the DataBroker, then exchanges text using
/// either the connectionless AX.25 protocols (Raw AX.25, Raw AX.25 compressed,
/// and APRS messaging) or the connected-mode AX.25 session protocol
/// ([AX25Session], for `X25Session`). All radio interaction flows through the
/// DataBroker:
///   * subscribes to `ConnectedRadios`, `LockState` and `UniqueDataFrame`
///   * dispatches `SetLock` / `SetUnlock` / `TransmitDataFrame`
///
/// "Wait for Connection" and YAPP file transfer are not ported yet and are
/// surfaced as disabled affordances.
class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

/// A line of terminal output, tracking the originating/target callsigns so that
/// consecutive fragments from the same source are merged (port of the C#
/// `TerminalText` helper used by `AppendTerminalString`).
class _TerminalLine {
  String? from; // null for outgoing/system lines
  final String? to;
  final bool outgoing;
  final bool system;

  /// Whether this visual line should be prefixed with the sender's callsign
  /// (when the "Show Callsign" option is enabled). Computed at append time,
  /// mirroring the C# `AppendTerminalString` logic.
  bool showCallsignPrefix;
  String text;

  _TerminalLine({
    this.from,
    this.to,
    this.outgoing = false,
    this.system = false,
    this.showCallsignPrefix = false,
    this.text = '',
  });
}

class _TerminalTabState extends State<TerminalTab>
    with AutomaticKeepAliveClientMixin {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // Connection state.
  final List<int> _connectedRadios = [];
  final Map<int, RadioLockState> _lockStates = {};
  StationInfo? _connectedStation;
  int _connectedRadioId = -1;

  // Connected-mode AX.25 session, used only for the X25Session protocol.
  AX25Session? _session;

  // Settings (persisted on broker device 0).
  bool _showCallsign = false;
  bool _wordWrap = false;

  // Terminal content.
  final List<_TerminalLine> _lines = [];

  // Per-line callsign tracking, mirroring the C# `AppendTerminalString` state:
  // the last sender whose callsign was shown, and whether the cursor is at the
  // start of a fresh line.
  String? _lastFrom;
  bool _atLineStart = true;

  @override
  bool get wantKeepAlive => true;

  bool get _isConnected => _activeTerminalRadioId > 0;

  @override
  void initState() {
    super.initState();

    _showCallsign =
        _broker.getValue<bool>(0, 'TerminalShowCallsign', false) ?? false;
    _wordWrap = _broker.getValue<bool>(0, 'TerminalWordWrap', false) ?? false;

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
  }

  @override
  void dispose() {
    _session?.dispose();
    _session = null;
    _broker.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DataBroker subscriptions
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
    if (!mounted) return;
    setState(() {
      _loadConnectedRadios();
      // Drop lock states for radios that are no longer connected.
      _lockStates.removeWhere((id, _) => !_connectedRadios.contains(id));
      if (_connectedRadioId > 0 &&
          !_connectedRadios.contains(_connectedRadioId)) {
        _connectedRadioId = -1;
        _connectedStation = null;
      }
    });
  }

  void _onLockState(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      if (data is Map<String, dynamic>) {
        _lockStates[deviceId] = RadioLockState.fromJson(data);
      } else if (data == null) {
        _lockStates.remove(deviceId);
        if (_connectedRadioId == deviceId) {
          _connectedRadioId = -1;
          _connectedStation = null;
        }
      }
    });
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (!mounted) return;
    // Only process frames while we have a radio locked to Terminal usage.
    final radioId = _activeTerminalRadioId;
    if (radioId <= 0 || deviceId != radioId) return;

    // The X25Session protocol is handled entirely by the AX25Session, which has
    // its own UniqueDataFrame subscription; the tab must not also decode those
    // frames. Connectionless protocols are decoded here.
    if (_connectedStation?.terminalProtocol == TerminalProtocol.x25Session) {
      return;
    }

    // UniqueDataFrame carries a TncDataFragment; decode it into an AX.25 packet.
    if (data is! TncDataFragment) return;
    if (!data.incoming) return;
    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    _processIncomingPacket(packet);
  }

  // ---------------------------------------------------------------------------
  // Radio selection helpers (port of GetActiveTerminalRadioId / GetAvailable*)
  // ---------------------------------------------------------------------------

  int get _activeTerminalRadioId {
    for (final radioId in _connectedRadios) {
      final lock = _lockStates[radioId];
      if (lock != null && lock.isLocked && lock.usage == 'Terminal') {
        return radioId;
      }
    }
    return -1;
  }

  List<int> get _availableRadios {
    final result = <int>[];
    for (final radioId in _connectedRadios) {
      final lock = _lockStates[radioId];
      if (lock == null || !lock.isLocked) result.add(radioId);
    }
    return result;
  }

  String _friendlyName(int radioId) {
    return _broker.getValue<String>(
          radioId,
          'FriendlyName',
          'Radio $radioId',
        ) ??
        'Radio $radioId';
  }

  // ---------------------------------------------------------------------------
  // Connect / disconnect (port of terminalConnectButton_Click)
  // ---------------------------------------------------------------------------

  Future<void> _onConnectPressed() async {
    final activeRadioId = _activeTerminalRadioId;
    if (activeRadioId > 0) {
      // For a connected-mode session, perform a graceful AX.25 disconnect; the
      // radio is unlocked when the session reaches the DISCONNECTED state.
      final session = _session;
      if (session != null &&
          session.currentState != AX25ConnectionState.disconnected) {
        _broker.logInfo('[TerminalTab] Disconnecting AX.25 session');
        session.disconnect();
        return;
      }

      // Otherwise (connectionless protocols) just unlock the radio.
      _broker.dispatch(
        deviceId: activeRadioId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'Terminal'),
        store: false,
      );
      // Restore the user's regular software modem mode.
      _broker.dispatch(
        deviceId: 0,
        name: 'ClearSessionModem',
        data: null,
        store: false,
      );
      _broker.logInfo('[TerminalTab] Disconnecting from radio $activeRadioId');
      _session?.dispose();
      _session = null;
      setState(() {
        _connectedStation = null;
        _connectedRadioId = -1;
      });
      _appendSystem('*** ${AppLocalizations.of(context).stateDisconnected} ***');
      return;
    }

    final available = _availableRadios;
    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).terminalNoRadio)),
      );
      return;
    }

    int radioId;
    if (available.length > 1) {
      final picked = await _pickRadio(available);
      if (picked == null) return;
      radioId = picked;
    } else {
      radioId = available.first;
    }

    if (!mounted) return;
    final station = await showActiveStationSelector(
      context,
      stationType: StationType.terminal,
    );
    if (station == null) return;

    _connectToStation(radioId, station);
  }

  Future<int?> _pickRadio(List<int> radios) async {
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).stateSelectRadio),
        children: [
          for (final radioId in radios)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(radioId),
              child: Text(_friendlyName(radioId)),
            ),
        ],
      ),
    );
  }

  /// Locks the radio to Terminal usage and connects to [station] (port of
  /// `ActiveLockToStation`).
  void _connectToStation(int radioId, StationInfo station) {
    if (radioId <= 0) return;

    // Resolve the channel id from the station's channel name.
    int channelId = -1;
    if (station.channel.isNotEmpty) {
      final channels = _broker.getJsonListValue<RadioChannelInfo>(
        radioId,
        'Channels',
        (json) => RadioChannelInfo.fromJson(json),
      );
      if (channels != null) {
        for (var i = 0; i < channels.length; i++) {
          if (channels[i].name == station.channel) {
            channelId = i;
            break;
          }
        }
      }
    }

    _broker.dispatch(
      deviceId: radioId,
      name: 'SetLock',
      data: SetLockData(usage: 'Terminal', regionId: -1, channelId: channelId),
      store: false,
    );

    // Override the software modem with the contact's configured modem for the
    // duration of the session. Restored on disconnect. 'Hardware' maps to the
    // radio's built-in TNC (software modem off).
    _broker.dispatch(
      deviceId: 0,
      name: 'SetSessionModem',
      data: station.modem,
      store: false,
    );

    setState(() {
      _connectedStation = station;
      _connectedRadioId = radioId;
    });

    _broker.logInfo(
      '[TerminalTab] Connecting to station ${station.callsign} on radio '
      '$radioId (Channel: $channelId)',
    );

    // For the connected-mode protocol, start an AX.25 session handshake.
    if (station.terminalProtocol == TerminalProtocol.x25Session) {
      _startSession(radioId, station);
    } else {
      _appendSystem('*** Connected to ${station.callsign} ***');
    }
    _inputFocus.requestFocus();
  }

  /// Creates an [AX25Session] and initiates a connected-mode handshake to
  /// [station] (used for [TerminalProtocol.x25Session]).
  void _startSession(int radioId, StationInfo station) {
    _session?.dispose();

    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';
    final myStationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;

    final dest = AX25Address.parse(
      station.ax25Destination.isNotEmpty
          ? station.ax25Destination
          : station.callsign,
    );
    final src = AX25Address.getAddress(myCallsign, myStationId);
    if (dest == null || src == null) {
      _appendSystem('*** ${AppLocalizations.of(context).terminalInvalidCallsignDest} ***');
      return;
    }

    final session = AX25Session(radioId);
    session.callSignOverride = myCallsign;
    session.stationIdOverride = myStationId;
    session.onStateChanged = _onSessionStateChanged;
    session.onDataReceived = _onSessionDataReceived;
    session.onError = _onSessionError;
    _session = session;

    _appendSystem('*** ${AppLocalizations.of(context).terminalConnectingTo(station.callsign)} ***');
    session.connect([dest, src]);
  }

  void _onSessionStateChanged(AX25Session sender, AX25ConnectionState state) {
    if (!mounted) return;
    switch (state) {
      case AX25ConnectionState.connected:
        _appendSystem('*** ${AppLocalizations.of(context).stateConnected} ***');
        break;
      case AX25ConnectionState.disconnected:
        _appendSystem('*** ${AppLocalizations.of(context).stateDisconnected} ***');
        // If the radio is still locked to Terminal, release it so the UI
        // returns to the disconnected state.
        final radioId = _activeTerminalRadioId;
        if (radioId > 0) {
          _broker.dispatch(
            deviceId: radioId,
            name: 'SetUnlock',
            data: SetUnlockData(usage: 'Terminal'),
            store: false,
          );
          // Restore the user's regular software modem mode.
          _broker.dispatch(
            deviceId: 0,
            name: 'ClearSessionModem',
            data: null,
            store: false,
          );
        }
        setState(() {
          _connectedStation = null;
          _connectedRadioId = -1;
        });
        break;
      case AX25ConnectionState.connecting:
      case AX25ConnectionState.disconnecting:
        break;
    }
  }

  void _onSessionDataReceived(AX25Session sender, Uint8List data) {
    if (!mounted) return;
    final station = _connectedStation;
    final fromCallsign = station?.callsign ?? 'UNKNOWN';
    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';
    _appendString(
      outgoing: false,
      from: fromCallsign,
      to: myCallsign,
      text: utf8.decode(data, allowMalformed: true),
    );
  }

  void _onSessionError(AX25Session sender, String error) {
    if (!mounted) return;
    _appendSystem('*** ${AppLocalizations.of(context).terminalError(error)} ***');
  }

  // ---------------------------------------------------------------------------
  // Sending (port of SendRawX25Packet / SendRawX25CompressPacket / SendAprsPacket)
  // ---------------------------------------------------------------------------

  void _onSend() {
    final text = _inputController.text;
    if (text.isEmpty) return;
    final radioId = _activeTerminalRadioId;
    final station = _connectedStation;
    if (radioId <= 0 || station == null) return;

    switch (station.terminalProtocol) {
      case TerminalProtocol.aprs:
        _sendAprsPacket(radioId, station, text);
        break;
      case TerminalProtocol.rawX25Compress:
        _sendRawX25Packet(radioId, station, text, compress: true);
        break;
      case TerminalProtocol.rawX25:
        _sendRawX25Packet(radioId, station, text, compress: false);
        break;
      case TerminalProtocol.x25Session:
        final session = _session;
        if (session == null ||
            session.currentState != AX25ConnectionState.connected) {
          _appendSystem('*** ${AppLocalizations.of(context).terminalNotConnected} ***');
          return;
        }
        // Send a line terminated with a carriage return (BBS convention).
        session.sendString('$text\r');
        break;
    }

    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';
    final myStationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final myAddress =
        myStationId > 0 ? '$myCallsign-$myStationId' : myCallsign;
    _appendString(
      outgoing: true,
      from: myAddress,
      to: station.callsign,
      text: '$text\n',
    );
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  /// Builds the source AX.25 address from our configured callsign + station id.
  AX25Address? _buildSourceAddress() {
    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';
    final myStationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    return AX25Address.getAddress(myCallsign, myStationId);
  }

  AX25Address? _buildDestAddress(StationInfo station) {
    // For raw protocols, the AX25Destination overrides the callsign when set.
    final target = station.ax25Destination.isNotEmpty
        ? station.ax25Destination
        : station.callsign;
    return AX25Address.parse(target);
  }

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

  void _sendRawX25Packet(
    int radioId,
    StationInfo station,
    String text, {
    required bool compress,
  }) {
    final src = _buildSourceAddress();
    final dest = _buildDestAddress(station);
    if (src == null || dest == null) {
      _appendSystem('*** ${AppLocalizations.of(context).terminalInvalidCallsignDest} ***');
      return;
    }

    final raw = Uint8List.fromList(utf8.encode(text));
    int pid = 241; // none
    Uint8List payload = raw;

    if (compress) {
      // Pick the smallest of uncompressed (241) or Deflate (243). Brotli (242)
      // from the C# implementation is unavailable in the Dart SDK, so it is
      // skipped; receivers still decode 241/243 interoperably.
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
  }

  void _sendAprsPacket(int radioId, StationInfo station, String text) {
    final src = _buildSourceAddress();
    final dest = AX25Address.parse('APRS');
    if (src == null || dest == null) {
      _appendSystem('*** ${AppLocalizations.of(context).terminalInvalidCallsign} ***');
      return;
    }

    // APRS message format: :CALLSIGN  :message  (9-char padded callsign)
    var paddedAddr = station.callsignNoZero;
    if (paddedAddr.length > 9) paddedAddr = paddedAddr.substring(0, 9);
    while (paddedAddr.length < 9) {
      paddedAddr += ' ';
    }
    final aprsContent = ':$paddedAddr:$text';

    final packet = AX25Packet(
      addresses: [dest, src],
      dataStr: aprsContent,
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    packet.pid = 240;
    _transmit(radioId, packet);
  }

  // ---------------------------------------------------------------------------
  // Receiving (port of ProcessRawX25Packet / ProcessRawX25CompressPacket /
  // ProcessAprsPacket)
  // ---------------------------------------------------------------------------

  void _processIncomingPacket(AX25Packet packet) {
    final station = _connectedStation;
    if (station == null) return;
    if (packet.addresses.length < 2) return;

    final fromCallsign = packet.addresses[1].callSignWithId;
    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'N0CALL') ?? 'N0CALL';

    switch (station.terminalProtocol) {
      case TerminalProtocol.aprs:
        _processAprsPacket(packet, fromCallsign, myCallsign);
        break;
      case TerminalProtocol.rawX25:
      case TerminalProtocol.rawX25Compress:
        _processRawX25Packet(packet, fromCallsign, myCallsign);
        break;
      case TerminalProtocol.x25Session:
        // Connected-mode frames are delivered via AX25Session callbacks
        // (`_onSessionDataReceived`), so nothing is processed here.
        break;
    }
  }

  void _processRawX25Packet(
    AX25Packet packet,
    String fromCallsign,
    String myCallsign,
  ) {
    String? text;
    final pid = packet.pid;

    if (packet.data != null && packet.data!.isNotEmpty) {
      if (pid == 243) {
        // Deflate compressed.
        try {
          text = utf8.decode(zlib.decode(packet.data!), allowMalformed: true);
        } catch (_) {
          text = utf8.decode(packet.data!, allowMalformed: true);
        }
      } else if (pid == 242) {
        // Brotli compressed - unsupported in this build; show raw bytes count.
        _appendSystem(
          '*** ${AppLocalizations.of(context).terminalBrotli} ***',
        );
        return;
      } else {
        text = utf8.decode(packet.data!, allowMalformed: true);
      }
    } else if (packet.dataStr != null && packet.dataStr!.isNotEmpty) {
      text = packet.dataStr;
    }

    if (text != null && text.isNotEmpty) {
      _appendString(
        outgoing: false,
        from: fromCallsign,
        to: myCallsign,
        text: text,
      );
    }
  }

  void _processAprsPacket(
    AX25Packet packet,
    String fromCallsign,
    String myCallsign,
  ) {
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
      _appendString(
        outgoing: false,
        from: fromCallsign,
        to: myCallsign,
        text: messageContent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Terminal text model (port of AppendTerminalString)
  // ---------------------------------------------------------------------------

  void _appendSystem(String text) {
    setState(() {
      _lines.add(_TerminalLine(system: true, text: text));
      // A system line is always on its own line and breaks the callsign run.
      _atLineStart = true;
      _lastFrom = null;
    });
    _scrollToBottom();
  }

  /// Appends received/sent [text] to the terminal, split into visual lines and
  /// prefixed with the sender's callsign per line when "Show Callsign" is on.
  ///
  /// This is a direct port of the C# `AppendTerminalString`: it tracks
  /// [_lastFrom] and [_atLineStart] across calls so the callsign is shown only
  /// when the sender changes or a new line begins, and consecutive fragments
  /// from the same sender on the same unfinished line are merged.
  void _appendString({
    required bool outgoing,
    required String? from,
    required String? to,
    required String text,
  }) {
    if (text.isEmpty) return;

    // Normalize line endings, then strip C0 control characters (0x00-0x1F) and
    // DEL (0x7F) - keeping only Tab (0x09) and newline (0x0A) - so non-printable
    // codes can't hide or clip surrounding characters in the renderer. Done via
    // code units so no literal control bytes appear in this source file.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = String.fromCharCodes(
      text.codeUnits.where((c) {
        if (c == 0x0A) return true; // keep newline (line separator)
        if (c == 0x09) return true; // keep tab
        if (c < 0x20) return false; // drop other C0 controls
        if (c == 0x7F) return false; // drop DEL
        return true;
      }),
    );

    final lines = text.split('\n');

    setState(() {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final isLastLine = (i == lines.length - 1);

        // Skip a trailing empty fragment (the text ended with a newline).
        if (line.isEmpty && isLastLine) continue;

        // Decide whether to show the callsign for this line, mirroring the C#
        // rule: only when the sender changed or we're at the start of a line.
        var showPrefix = false;
        if (_showCallsign && from != null && from.isNotEmpty) {
          if (_lastFrom != from || _atLineStart) {
            showPrefix = true;
            _lastFrom = from;
          }
        }

        // Append the line text. When we're mid-line (not at line start) and not
        // forcing a new callsign prefix, merge onto the current visual line;
        // otherwise start a new line.
        final canMerge =
            !_atLineStart &&
            !showPrefix &&
            _lines.isNotEmpty &&
            !_lines.last.system &&
            _lines.last.outgoing == outgoing &&
            _lines.last.from == from;
        if (canMerge) {
          _lines.last.text += line;
        } else {
          _lines.add(
            _TerminalLine(
              from: from,
              to: to,
              outgoing: outgoing,
              showCallsignPrefix: showPrefix,
              text: line,
            ),
          );
        }

        if (!isLastLine) {
          // The line is terminated; the next text starts a fresh line.
          _atLineStart = true;
        } else {
          // For the last fragment we're at line start only if it was empty.
          _atLineStart = line.isEmpty;
        }
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Recomputes [showCallsignPrefix] for every existing line, mirroring the
  /// append-time logic. Called when "Show Callsign" is toggled so that all
  /// existing lines immediately reflect the new setting.
  void _recomputeCallsignPrefixes() {
    for (final line in _lines) {
      if (line.system) {
        line.showCallsignPrefix = false;
        continue;
      }
      line.showCallsignPrefix =
          _showCallsign && line.from != null && line.from!.isNotEmpty;
    }
  }

  /// Builds the colored spans for a single line, honoring "Show Callsign".
  List<TerminalTextSpan> _spansForLine(_TerminalLine line) {
    if (line.system) {
      return [
        TerminalTextSpan(
          line.text,
          color: Colors.yellow,
          bold: true,
        ),
      ];
    }

    final spans = <TerminalTextSpan>[];
    if (_showCallsign && line.showCallsignPrefix && line.from != null) {
      spans.add(
        TerminalTextSpan(
          '${line.from}: ',
          color: line.outgoing ? Colors.lightBlueAccent : Colors.greenAccent,
          bold: true,
        ),
      );
    }
    spans.add(
      TerminalTextSpan(
        line.text,
        color: line.outgoing ? Colors.lightBlueAccent : Colors.white70,
      ),
    );
    return spans;
  }

  // ---------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'showCallsign',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showCallsign
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).terminalShowCallsign),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'wordWrap',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _wordWrap
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).terminalWordWrap),
            ],
          ),
        ),
        // "Wait for Connection" requires the AX.25 session layer (not ported).
        PopupMenuItem<String>(
          value: 'waitForConnection',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: false,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).terminalWaitForConnection),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).tabClear),
            ],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text(AppLocalizations.of(context).tabDetach),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'showCallsign':
          setState(() {
            _showCallsign = !_showCallsign;
            _recomputeCallsignPrefixes();
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'TerminalShowCallsign',
            data: _showCallsign,
            store: true,
          );
          break;
        case 'wordWrap':
          setState(() => _wordWrap = !_wordWrap);
          _broker.dispatch(
            deviceId: 0,
            name: 'TerminalWordWrap',
            data: _wordWrap,
            store: true,
          );
          break;
        case 'clear':
          setState(() {
            _lines.clear();
            _lastFrom = null;
            _atLineStart = true;
          });
          break;
        case 'detach':
          windowService.createWindow('terminal');
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Container(color: Colors.black, child: _buildTerminalText()),
        ),
        _buildInputPanel(),
      ],
    );
  }

  Widget _buildHeader() {
    final connected = _isConnected;
    final title = connected && _connectedStation != null
        ? AppLocalizations.of(context).terminalHeaderWith(
            _connectedStation!.callsign,
          )
        : AppLocalizations.of(context).tabTerminal;
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 220;
          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (showButton) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _connectedRadios.isEmpty && !connected
                        ? null
                        : _onConnectPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(
                      connected
                          ? AppLocalizations.of(context).commonDisconnect
                          : AppLocalizations.of(context).commonConnect,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Builder(
                builder: (context) => InkWell(
                  onTap: () => _showMenu(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/MenuIcon.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.menu, size: 24);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTerminalText() {
    final spans = <TerminalTextSpan>[];
    for (var i = 0; i < _lines.length; i++) {
      // Separate each terminal line with a newline, mirroring the C#
      // AppendTerminalString which prepends Environment.NewLine before every
      // line except the first. Without this, all lines render concatenated on
      // a single visual line.
      if (i > 0) spans.add(const TerminalTextSpan('\n'));
      spans.addAll(_spansForLine(_lines[i]));
    }

    final richText = SelectableText.rich(
      TextSpan(
        children: spans
            .map(
              (span) => TextSpan(
                text: span.text,
                style: TextStyle(
                  color: span.color,
                  fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            )
            .toList(),
      ),
      style: const TextStyle(
        fontFamily: 'Courier New',
        fontFamilyFallback: ['monospace', 'Courier'],
        fontSize: 14,
        height: 1.3,
      ),
    );

    // When word wrap is on, let the text fill the available width and wrap.
    if (_wordWrap) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        child: SizedBox(width: double.infinity, child: richText),
      );
    }

    // When word wrap is off, allow horizontal scrolling of long lines while
    // still stretching the content to at least the full viewport width so the
    // terminal occupies the entire tab width.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Subtract the horizontal padding so the min-width matches the
        // available content area exactly.
        final minWidth = constraints.maxWidth - 16;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minWidth > 0 ? minWidth : 0,
              ),
              child: IntrinsicWidth(child: richText),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputPanel() {
    final enabled = _isConnected;
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: enabled ? Colors.white : const Color(0xFFE0E0E0),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                enabled: enabled,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: enabled ? _onSend : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(AppLocalizations.of(context).terminalSend),
            ),
          ),
        ],
      ),
    );
  }
}
