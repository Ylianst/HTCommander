/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

A small, self-contained HTTP + WebSocket server for the public HTTP BBS. It
serves a single terminal page (see bbs_web_page.dart) and accepts WebSocket
connections at `/bbs?callsign=CALL`. Bound to all interfaces (`anyIPv4`).
Connected clients can also download BBS files (`GET /files/<id>?token=...`) and
upload them (`POST /upload?token=...&name=...`, bounded body size), where the
token is the client's secret [BbsWebClient.fileToken].

This server is meant to be reachable from the Internet without authentication,
so it implements the WebSocket framing itself (RFC 6455) instead of using
`dart:io`'s `WebSocket`, which has no limit on frame or message size. Frames,
messages, message rate, idle time and connection counts are all bounded.

Only transport lives here; the BBS conversation is driven by [WebBbsHandler].
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;

import '../../utils/callsign_format.dart';
import '../data_broker_client.dart';
import 'bbs_web_page.dart';

/// Callback raised when an HTTP BBS [client] connects or disconnects.
typedef BbsWebClientCallback = void Function(BbsWebClient client);

/// Callback raised when a text message is received from an HTTP BBS [client].
typedef BbsWebTextCallback = void Function(BbsWebClient client, String message);

/// A file served to a web client.
class BbsWebFile {
  const BbsWebFile(this.name, this.data);

  final String name;
  final Uint8List data;
}

/// Looks up the file [id] requested by [client]; null when not found.
typedef BbsWebDownloadCallback =
    BbsWebFile? Function(BbsWebClient client, String id);

/// Stores a file uploaded by [client]. [notified] means the result was also
/// shown to the client in its terminal.
typedef BbsWebUploadCallback =
    ({bool ok, String message, bool notified}) Function(
      BbsWebClient client,
      String name,
      Uint8List data,
    );

/// A connected HTTP BBS WebSocket client.
class BbsWebClient {
  BbsWebClient._(
    this.id,
    this.callsign,
    this.remoteAddress,
    this._socket,
    this._server,
  ) : fileToken = _newToken();

  final int id;

  /// Validated, upper-case callsign supplied by the browser.
  final String callsign;

  final String remoteAddress;

  /// Secret that authorizes this client's HTTP file downloads and uploads.
  final String fileToken;

  static final Random _random = Random.secure();

  static String _newToken() => [
    for (var i = 0; i < 16; i++) _random.nextInt(256),
  ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  bool _uploading = false;

  final Socket _socket;
  final BbsWebServer _server;

  Uint8List _rx = Uint8List(0);
  int _messageOpcode = -1;
  final BytesBuilder _message = BytesBuilder(copy: false);
  bool _closed = false;
  bool _accepted = false;
  Timer? _idleTimer;
  Timer? _pingTimer;
  Timer? _destroyTimer;
  int _rateWindowStartMs = 0;
  int _rateWindowCount = 0;

  /// Sends a text message to the browser.
  void sendText(String message) {
    if (_closed) return;
    _sendFrame(0x1, utf8.encode(message));
  }

  /// Sends a close frame with [code] / [reason] and drops the connection.
  void close([int code = 1000, String reason = '']) {
    if (_closed) return;
    var reasonBytes = utf8.encode(reason);
    if (reasonBytes.length > 123) reasonBytes = reasonBytes.sublist(0, 123);
    _sendFrame(0x8, <int>[(code >> 8) & 0xFF, code & 0xFF, ...reasonBytes]);
    _closed = true;
    _stopTimers();
    unawaited(_socket.close().catchError((Object _) {}));
    // Give the close frame a moment to flush before tearing down.
    _destroyTimer = Timer(const Duration(seconds: 2), _socket.destroy);
    _server._removeClient(this);
  }

  void _start() {
    _resetIdleTimer();
    _pingTimer = Timer.periodic(
      BbsWebServer.pingInterval,
      (_) => _sendFrame(0x9, const <int>[]),
    );
    _socket.listen(
      _onData,
      onError: (Object _) => _terminate(),
      onDone: _terminate,
      cancelOnError: true,
    );
  }

  void _terminate() {
    _closed = true;
    _stopTimers();
    _destroyTimer?.cancel();
    try {
      _socket.destroy();
    } catch (_) {}
    _server._removeClient(this);
  }

  void _stopTimers() {
    _idleTimer?.cancel();
    _pingTimer?.cancel();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(
      BbsWebServer.idleTimeout,
      () => close(1000, 'Idle timeout'),
    );
  }

  void _sendFrame(int opcode, List<int> payload) {
    if (_closed) return;
    final len = payload.length;
    final b = BytesBuilder(copy: false);
    b.addByte(0x80 | opcode);
    if (len < 126) {
      b.addByte(len);
    } else if (len < 65536) {
      b.add(<int>[126, (len >> 8) & 0xFF, len & 0xFF]);
    } else {
      b.add(<int>[127, 0, 0, 0, 0]);
      b.add(<int>[
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ]);
    }
    b.add(payload);
    try {
      _socket.add(b.takeBytes());
    } catch (_) {
      _terminate();
    }
  }

  void _onData(Uint8List data) {
    if (_closed) return;
    if (_rx.isEmpty) {
      _rx = data;
    } else {
      final merged = Uint8List(_rx.length + data.length);
      merged.setRange(0, _rx.length, _rx);
      merged.setRange(_rx.length, merged.length, data);
      _rx = merged;
    }

    while (!_closed && _rx.length >= 2) {
      final b0 = _rx[0];
      final b1 = _rx[1];
      final fin = (b0 & 0x80) != 0;
      final opcode = b0 & 0x0F;
      var len = b1 & 0x7F;
      var offset = 2;
      if ((b0 & 0x70) != 0 || (b1 & 0x80) == 0) {
        // Reserved bits set, or an unmasked client frame.
        close(1002, 'Protocol error');
        return;
      }
      if (len == 126) {
        if (_rx.length < 4) return;
        len = (_rx[2] << 8) | _rx[3];
        offset = 4;
      } else if (len == 127) {
        if (_rx.length < 10) return;
        for (var i = 2; i < 6; i++) {
          if (_rx[i] != 0) {
            close(1009, 'Message too big');
            return;
          }
        }
        len = (_rx[6] << 24) | (_rx[7] << 16) | (_rx[8] << 8) | _rx[9];
        offset = 10;
      }
      if (len > BbsWebServer.maxMessageBytes) {
        close(1009, 'Message too big');
        return;
      }
      if (_rx.length < offset + 4 + len) return;

      final maskOffset = offset;
      offset += 4;
      final payload = Uint8List(len);
      for (var i = 0; i < len; i++) {
        payload[i] = _rx[offset + i] ^ _rx[maskOffset + (i & 3)];
      }
      _rx = Uint8List.sublistView(_rx, offset + len);
      _onFrame(fin, opcode, payload);
    }
  }

  void _onFrame(bool fin, int opcode, Uint8List payload) {
    if (opcode >= 0x8) {
      if (!fin || payload.length > 125) {
        close(1002, 'Protocol error');
        return;
      }
      switch (opcode) {
        case 0x8:
          close();
        case 0x9:
          _sendFrame(0xA, payload);
        case 0xA:
          break;
        default:
          close(1002, 'Protocol error');
      }
      return;
    }

    if (opcode == 0x0) {
      if (_messageOpcode < 0) {
        close(1002, 'Protocol error');
        return;
      }
    } else if (opcode == 0x1 || opcode == 0x2) {
      if (_messageOpcode >= 0) {
        close(1002, 'Protocol error');
        return;
      }
      _messageOpcode = opcode;
    } else {
      close(1002, 'Protocol error');
      return;
    }

    if (_message.length + payload.length > BbsWebServer.maxMessageBytes) {
      close(1009, 'Message too big');
      return;
    }
    _message.add(payload);
    if (!fin) return;

    final messageOpcode = _messageOpcode;
    final bytes = _message.takeBytes();
    _messageOpcode = -1;
    if (messageOpcode != 0x1) return; // Binary messages are ignored.

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      close(1007, 'Invalid UTF-8');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _rateWindowStartMs >= 1000) {
      _rateWindowStartMs = now;
      _rateWindowCount = 0;
    }
    if (++_rateWindowCount > BbsWebServer.maxMessagesPerSecond) return;

    _resetIdleTimer();
    if (_accepted) _server.onTextMessage?.call(this, text);
  }
}

/// Serves the HTTP BBS terminal page and its WebSocket endpoint.
class BbsWebServer {
  BbsWebServer(this.port) : _broker = DataBrokerClient();

  /// WebSocket endpoint the terminal page connects to.
  static const String webSocketPath = '/bbs';

  static const int maxClients = 32;
  static const int maxClientsPerAddress = 4;

  /// Largest accepted WebSocket message (and frame) payload.
  static const int maxMessageBytes = 4096;
  static const int maxMessagesPerSecond = 20;
  static const Duration idleTimeout = Duration(minutes: 30);
  static const Duration pingInterval = Duration(seconds: 30);

  /// Close codes reported to the page (application range 4000-4999).
  static const int closeInvalidCallsign = 4001;
  static const int closeServerBusy = 4002;

  static const String _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  final int port;
  final DataBrokerClient _broker;

  HttpServer? _server;
  bool _running = false;
  int _nextClientId = 1;
  final Map<int, BbsWebClient> _clients = <int, BbsWebClient>{};

  BbsWebClientCallback? onClientConnected;
  BbsWebClientCallback? onClientDisconnected;
  BbsWebTextCallback? onTextMessage;
  BbsWebDownloadCallback? onFileDownload;
  BbsWebUploadCallback? onFileUpload;

  /// HTTP path prefix of file downloads (`/files/<id>?token=...`).
  static const String filesPath = '/files/';

  /// HTTP path of file uploads (`POST /upload?token=...&name=...`).
  static const String uploadPath = '/upload';

  /// Largest accepted upload body, in bytes.
  int maxUploadBytes = 25 * 1024;

  static const Duration _uploadTimeout = Duration(seconds: 60);

  bool get isRunning => _running;

  /// The bound port, or `null` if not running. Differs from [port] only when
  /// [port] is `0` (ephemeral port selection).
  int? get boundPort => _server?.port;

  int get clientCount => _clients.length;

  /// Starts listening. Returns `true` on success.
  Future<bool> start() async {
    if (_running) return true;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.idleTimeout = const Duration(seconds: 30);
      _running = true;
      _server!.listen(_handleRequest, onError: (Object _) {});
      _broker.logInfo('[BbsWebServer] Started on port $port');
      return true;
    } catch (ex) {
      _broker.logError('[BbsWebServer] Failed to start on port $port: $ex');
      _running = false;
      _server = null;
      return false;
    }
  }

  /// Stops listening and drops all clients.
  void stop() {
    if (!_running && _server == null) return;
    _running = false;
    for (final client in List<BbsWebClient>.from(_clients.values)) {
      client.close(1001, 'Server shutting down');
    }
    _clients.clear();
    _server?.close(force: true);
    _server = null;
    _broker.logInfo('[BbsWebServer] Stopped');
  }

  void dispose() {
    stop();
    _broker.dispose();
  }

  void _removeClient(BbsWebClient client) {
    if (_clients.remove(client.id) == null) return;
    if (client._accepted) onClientDisconnected?.call(client);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == webSocketPath) {
        await _handleWebSocket(request);
      } else if (path.startsWith(filesPath)) {
        await _handleDownload(request);
      } else if (path == uploadPath) {
        await _handleUpload(request);
      } else {
        await _handleHttp(request);
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// The connected client owning the request's `token`, or null.
  BbsWebClient? _clientForToken(HttpRequest request) {
    final token = request.uri.queryParameters['token'];
    if (token == null || token.length != 32) return null;
    for (final client in _clients.values) {
      if (client._accepted && !client._closed && client.fileToken == token) {
        return client;
      }
    }
    return null;
  }

  static Future<void> _plain(
    HttpResponse response,
    int status,
    String text,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..write(text);
    await response.close();
  }

  Future<void> _handleDownload(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET') {
      response.headers.set(HttpHeaders.allowHeader, 'GET');
      await _plain(response, HttpStatus.methodNotAllowed, 'Method not allowed');
      return;
    }
    final client = _clientForToken(request);
    if (client == null) {
      await _plain(response, HttpStatus.forbidden, 'Not connected to the BBS');
      return;
    }
    client._resetIdleTimer();
    final id = request.uri.path.substring(filesPath.length);
    final file = onFileDownload?.call(client, id);
    if (file == null) {
      await _plain(response, HttpStatus.notFound, 'File not found');
      return;
    }
    final ascii = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    response.headers
      ..contentType = ContentType.binary
      ..contentLength = file.data.length
      ..set(
        'Content-Disposition',
        'attachment; filename="$ascii"; '
            "filename*=UTF-8''${Uri.encodeComponent(file.name)}",
      )
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Content-Security-Policy', "default-src 'none'; sandbox");
    response.add(file.data);
    await response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    Future<void> reply(int status, String message, {bool notified = false}) {
      final body = utf8.encode(
        jsonEncode({
          'ok': status == HttpStatus.ok,
          'message': message,
          'notified': notified,
        }),
      );
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..headers.contentLength = body.length
        ..headers.set('X-Content-Type-Options', 'nosniff')
        ..add(body);
      return response.close();
    }

    if (request.method != 'POST') {
      response.headers.set(HttpHeaders.allowHeader, 'POST');
      await reply(HttpStatus.methodNotAllowed, 'Method not allowed');
      return;
    }
    final client = _clientForToken(request);
    if (client == null) {
      await reply(HttpStatus.forbidden, 'Not connected to the BBS');
      return;
    }
    final name = request.uri.queryParameters['name'] ?? '';
    final max = maxUploadBytes;
    final tooLarge = 'File too large (max $max bytes)';
    if (request.contentLength > max) {
      await reply(HttpStatus.requestEntityTooLarge, tooLarge);
      return;
    }
    if (client._uploading) {
      await reply(HttpStatus.tooManyRequests, 'An upload is already running');
      return;
    }
    client._uploading = true;
    try {
      final body = BytesBuilder(copy: false);
      await for (final chunk in request.timeout(_uploadTimeout)) {
        if (body.length + chunk.length > max) {
          await reply(HttpStatus.requestEntityTooLarge, tooLarge);
          return;
        }
        body.add(chunk);
      }
      client._resetIdleTimer();
      final handler = onFileUpload;
      if (handler == null || client._closed) {
        await reply(HttpStatus.serviceUnavailable, 'Uploads are unavailable');
        return;
      }
      final result = handler(client, name, body.takeBytes());
      await reply(
        result.ok ? HttpStatus.ok : HttpStatus.badRequest,
        result.message,
        notified: result.notified,
      );
    } on TimeoutException {
      await reply(HttpStatus.requestTimeout, 'Upload timed out');
    } finally {
      client._uploading = false;
    }
  }

  Future<void> _handleHttp(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    if (path != '/' && path != '/index.html') {
      response.statusCode = HttpStatus.notFound;
      response.headers.contentType = ContentType.text;
      response.write('404 - Not Found');
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await response.close();
      return;
    }
    final body = utf8.encode(bbsWebPageHtml);
    response.headers
      ..contentType = ContentType.html
      ..contentLength = body.length
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; "
            "style-src 'unsafe-inline'; connect-src 'self' ws: wss:; "
            "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      );
    if (request.method == 'GET') response.add(body);
    await response.close();
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final response = request.response;
    final headers = request.headers;
    final key = headers.value('sec-websocket-key');
    final upgrade = headers.value(HttpHeaders.upgradeHeader) ?? '';
    final connection = (headers[HttpHeaders.connectionHeader] ?? <String>[])
        .join(',')
        .toLowerCase();
    if (request.method != 'GET' ||
        upgrade.toLowerCase() != 'websocket' ||
        !connection.contains('upgrade') ||
        key == null ||
        key.trim().isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      response.write('400 - WebSocket upgrade required');
      await response.close();
      return;
    }
    if (headers.value('sec-websocket-version') != '13') {
      response.statusCode = HttpStatus.upgradeRequired;
      response.headers.set('Sec-WebSocket-Version', '13');
      await response.close();
      return;
    }

    final accept = base64.encode(
      sha1.convert(ascii.encode('${key.trim()}$_webSocketGuid')).bytes,
    );
    response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('Sec-WebSocket-Accept', accept)
      ..headers.contentLength = 0;
    final remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final Socket socket;
    try {
      socket = await response.detachSocket();
    } catch (_) {
      return;
    }
    if (!_running) {
      socket.destroy();
      return;
    }

    final callsign = normalizeAmateurCallsign(
      request.uri.queryParameters['callsign'],
    );
    final client = BbsWebClient._(
      _nextClientId++,
      callsign ?? '',
      remoteAddress,
      socket,
      this,
    );
    final fromAddress = _clients.values
        .where((c) => c.remoteAddress == remoteAddress)
        .length;
    _clients[client.id] = client;
    client._start();

    if (callsign == null) {
      client.close(closeInvalidCallsign, 'Invalid callsign');
      return;
    }
    if (_clients.length > maxClients || fromAddress >= maxClientsPerAddress) {
      client.close(closeServerBusy, 'Server busy, try again later');
      return;
    }
    client._accepted = true;
    _broker.logInfo(
      '[BbsWebServer] Client ${client.id} ($callsign) connected from '
      '$remoteAddress',
    );
    onClientConnected?.call(client);
  }
}
