/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Public HTTP BBS. Owns the [BbsWebServer] and starts / stops it based on the
`bbsWebServerEnabled` / `bbsWebServerPort` settings (DataBroker device 0).

Anyone who can reach the port gets a web terminal, enters a callsign (validated
by the page and again by the server) and is connected to the BBS menu shared
with radio clients ([BbsMenu]). No authentication is performed, so only the
text menu is offered: Winlink mail exchange and the CMS relay stay radio-only.
The BBS file area is offered over HTTP: each session gets a secret token that
the page uses to download files and upload them (see [BbsWebServer]). The page
also receives control messages over the WebSocket: a text message that starts
with [controlPrefix] carries JSON for the page instead of terminal text.
Conversation lines and per-callsign statistics are reported to the BBS tab like
radio clients, with the "Web" protocol.

Web sessions do not involve a radio and run independently of any radio BBS.
*/

import 'dart:convert';
import 'dart:typed_data';

import '../services/data_broker_client.dart';
import '../services/web/bbs_web_server.dart';
import 'bbs_files.dart';
import 'bbs_handler.dart';
import 'bbs_monitor.dart';

class WebBbsHandler {
  WebBbsHandler() : _broker = DataBrokerClient();

  /// Device id used for web clients in BBS traffic and statistics events.
  static const int statsDeviceId = 0;

  static const String protocol = 'Web';

  /// Starts WebSocket messages that carry JSON for the page, not text.
  static const String controlPrefix = '\u0001';

  final DataBrokerClient _broker;
  BbsWebServer? _server;
  bool _enabled = false;
  int _port = 8023;
  bool _disposed = false;

  final Map<String, StationStats> _stats = <String, StationStats>{};

  /// Lines received from a client while one of its replies is being prepared.
  final Map<BbsWebClient, List<String>> _pending = {};

  /// Per-client menu session state (running game).
  final Map<BbsWebClient, Map<String, Object?>> _sessions = {};

  /// The text menu served to web clients.
  BbsMenu menu = BbsMenu();

  /// The running server, for tests.
  BbsWebServer? get server => _server;

  void init() {
    _enabled = (_broker.getValue<int>(0, 'bbsWebServerEnabled', 0) ?? 0) == 1;
    _port = _broker.getValue<int>(0, 'bbsWebServerPort', 8023) ?? 8023;
    _broker.subscribeMultiple(
      deviceId: 0,
      names: <String>['bbsWebServerEnabled', 'bbsWebServerPort'],
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsClearAllStats',
      callback: (int deviceId, String name, Object? data) => _stats.clear(),
    );
    if (_enabled) _startServer();
  }

  void _onSettingChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (name == 'bbsWebServerEnabled') {
      final enabled = (data is int ? data : 0) == 1;
      if (enabled == _enabled) return;
      _enabled = enabled;
      if (_enabled) {
        _startServer();
      } else {
        _stopServer();
      }
    } else if (name == 'bbsWebServerPort') {
      final port = data is int ? data : _port;
      if (port == _port) return;
      _port = port;
      if (_enabled) {
        _stopServer();
        _startServer();
      }
    }
  }

  void _startServer() {
    if (_server != null) return;
    final server = BbsWebServer(_port);
    server.onClientConnected = _onClientConnected;
    server.onClientDisconnected = _onClientDisconnected;
    server.onTextMessage = _onTextMessage;
    server.onFileDownload = _onFileDownload;
    server.onFileUpload = _onFileUpload;
    server.maxUploadBytes = BbsFileStore.maxUploadBytes;
    _server = server;
    server.start();
  }

  void _stopServer() {
    final server = _server;
    if (server == null) return;
    _server = null;
    server.dispose();
  }

  void _onClientConnected(BbsWebClient client) {
    BbsMonitor.instance.sessionStarted(
      statsDeviceId,
      client.callsign,
      protocol,
    );
    _dispatchControl(
      'Web connected to ${client.callsign} (${client.remoteAddress})',
      client.callsign,
    );
    final files = menu.files;
    _server?.maxUploadBytes = BbsFileStore.maxUploadBytes;
    _sendControl(client, {
      't': 'session',
      'token': client.fileToken,
      'files': files.isAvailable,
      'upload': files.isAvailable && files.uploadsEnabled,
      'maxUpload': BbsFileStore.maxUploadBytes,
    });
    final welcome = menu.welcome(client.callsign, protocol);
    _send(client, '${BbsMenu.banner}$welcome${BbsMenu.prompt}');
  }

  void _onClientDisconnected(BbsWebClient client) {
    _pending.remove(client);
    _sessions.remove(client);
    _dispatchControl(
      'Web disconnected from ${client.callsign}',
      client.callsign,
    );
    BbsMonitor.instance.sessionEnded(statsDeviceId, client.callsign);
  }

  void _onTextMessage(BbsWebClient client, String message) {
    if (_disposed) return;
    _updateStats(client.callsign, 1, 0, message.length, 0);
    final lines = message
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    // While a reply is still being prepared (e.g. a callsign lookup), queue
    // new lines so that replies keep their order.
    final queued = _pending[client];
    if (queued != null) {
      queued.addAll(lines);
      return;
    }
    _processLines(client, lines);
  }

  void _processLines(BbsWebClient client, List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      // Drop control characters so they cannot garble the traffic log.
      final line = lines[i].replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (line.isEmpty) continue;
      _dispatchTraffic(client.callsign, false, line);

      final reply = menu.handleLine(
        client.callsign,
        line,
        transfer: BbsFileTransfer.web,
        session: _sessions.putIfAbsent(client, () => <String, Object?>{}),
      );
      if (reply is BbsMenuReply) {
        if (!_applyReply(client, reply)) return;
        continue;
      }
      _pending[client] = lines.sublist(i + 1);
      reply
          .catchError(
            (Object _) =>
                const BbsMenuReply('Command failed.\r${BbsMenu.prompt}'),
          )
          .then((r) {
            final rest = _pending.remove(client);
            if (_disposed || rest == null) return;
            if (_applyReply(client, r)) _processLines(client, rest);
          });
      return;
    }
  }

  /// Sends [reply] to [client]; false once the client is disconnected.
  bool _applyReply(BbsWebClient client, BbsMenuReply reply) {
    if (reply.disconnect) {
      _pending.remove(client);
      client.close(1000, 'Disconnected');
      return false;
    }
    _send(client, reply.text);
    final file = reply.download;
    if (file != null) {
      _sendControl(client, {
        't': 'download',
        'url': '${BbsWebServer.filesPath}${file.id}?token=${client.fileToken}',
        'name': file.name,
      });
    }
    return true;
  }

  void _sendControl(BbsWebClient client, Map<String, Object?> message) {
    client.sendText('$controlPrefix${jsonEncode(message)}');
  }

  BbsWebFile? _onFileDownload(BbsWebClient client, String id) {
    if (_disposed) return null;
    final files = menu.files;
    final file = int.tryParse(id) == null ? null : files.find(id);
    final data = file == null ? null : files.read(file);
    if (file == null || data == null) return null;
    _dispatchControl(
      'Web download of ${file.name} (${data.length} bytes)',
      client.callsign,
    );
    _updateStats(client.callsign, 0, 1, 0, data.length);
    return BbsWebFile(file.name, data);
  }

  ({bool ok, String message, bool notified}) _onFileUpload(
    BbsWebClient client,
    String name,
    Uint8List data,
  ) {
    if (_disposed) {
      return (ok: false, message: 'The BBS is shutting down', notified: false);
    }
    _updateStats(client.callsign, 1, 0, data.length, 0);
    final result = menu.files.upload(client.callsign, name, data);
    final file = result.file;
    final message = file == null
        ? 'Upload of ${BbsFileStore.sanitizeName(name)} failed: ${result.error}.'
        : 'Received ${file.name} (${data.length} bytes), '
              'saved as file #${file.id}.';
    _dispatchControl('Web upload: $message', client.callsign);
    _send(client, '$message\r${BbsMenu.prompt}');
    return (ok: file != null, message: message, notified: true);
  }

  void _send(BbsWebClient client, String text) {
    for (final line in text.split('\r')) {
      if (line.trim().isNotEmpty) {
        _dispatchTraffic(client.callsign, true, line.trim());
      }
    }
    _updateStats(client.callsign, 0, 1, 0, text.length);
    client.sendText(text);
  }

  void _updateStats(
    String callsign,
    int packetsIn,
    int packetsOut,
    int bytesIn,
    int bytesOut,
  ) {
    final s = _stats.putIfAbsent(callsign, StationStats.new);
    s.callsign = callsign;
    s.lastseen = DateTime.now();
    s.protocol = protocol;
    s.packetsIn += packetsIn;
    s.packetsOut += packetsOut;
    s.bytesIn += bytesIn;
    s.bytesOut += bytesOut;
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsStatsUpdated',
      data: BbsStatsUpdatedData(deviceId: statsDeviceId, stats: s),
      store: false,
    );
  }

  void _dispatchTraffic(String callsign, bool outgoing, String message) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsTraffic',
      data: BbsTrafficData(
        deviceId: statsDeviceId,
        callsign: callsign,
        outgoing: outgoing,
        message: message,
      ),
      store: false,
    );
  }

  void _dispatchControl(String message, String callsign) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsControlMessage',
      data: BbsControlMessageData(
        deviceId: statsDeviceId,
        callsign: callsign,
        message: message,
      ),
      store: false,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopServer();
    _broker.dispose();
  }
}
