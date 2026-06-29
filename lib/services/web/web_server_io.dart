/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.HttpsWebSocketServer`. A minimal HTTP + WebSocket
server that serves the bundled web UI (originally the C# `HTCommander/web`
folder, now packaged as Flutter assets under `assets/web/`) and bridges the
radio to connected browsers over a WebSocket at `/websocket.aspx`. Bound to all
interfaces (`anyIPv4`) to match the C# `http://+` prefix.

This class is only responsible for transport (HTTP static files + WebSocket
framing). The bridge logic that connects WebSocket clients to the radio lives in
[WebServerHandler].
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../data_broker_client.dart';

/// Callback raised when a WebSocket [client] connects or disconnects.
typedef WebSocketClientCallback = void Function(WebSocketClient client);

/// Callback raised when a text message is received from a WebSocket [client].
typedef WebSocketTextCallback =
    void Function(WebSocketClient client, String message);

/// Callback raised when a binary message is received from a WebSocket [client].
typedef WebSocketBinaryCallback =
    void Function(WebSocketClient client, Uint8List data);

/// A single connected WebSocket client.
class WebSocketClient {
  WebSocketClient(this.id, this._socket);

  /// Monotonically increasing client identifier.
  final int id;
  final WebSocket _socket;

  /// Sends a text frame to this client.
  void sendText(String message) {
    try {
      _socket.add(message);
    } catch (_) {
      // Client likely disconnected; ignore.
    }
  }

  /// Sends a binary frame to this client.
  void sendBinary(List<int> data) {
    try {
      _socket.add(data);
    } catch (_) {
      // Client likely disconnected; ignore.
    }
  }

  void _close() {
    try {
      _socket.close();
    } catch (_) {
      // Already closed.
    }
  }
}

/// Serves the bundled static web UI over HTTP and bridges the radio over a
/// WebSocket on desktop platforms.
class WebServer {
  WebServer(this.port) : _broker = DataBrokerClient();

  /// Root asset prefix where the web UI is bundled (see `pubspec.yaml`).
  static const String _assetBase = 'assets/web';

  /// The WebSocket endpoint the browser connects to (see `index.html`).
  static const String _webSocketPath = '/websocket.aspx';

  final int port;
  final DataBrokerClient _broker;

  HttpServer? _server;
  bool _running = false;
  int _nextClientId = 1;
  final Map<int, WebSocketClient> _clients = <int, WebSocketClient>{};

  /// Raised when a new WebSocket client connects.
  WebSocketClientCallback? onClientConnected;

  /// Raised when a WebSocket client disconnects.
  WebSocketClientCallback? onClientDisconnected;

  /// Raised when a text message is received from a WebSocket client.
  WebSocketTextCallback? onTextMessage;

  /// Raised when a binary message is received from a WebSocket client.
  WebSocketBinaryCallback? onBinaryMessage;

  /// Whether the server is currently listening.
  bool get isRunning => _running;

  /// The actual port the server is bound to, or `null` if not running. Differs
  /// from [port] only when [port] is `0` (ephemeral port selection).
  int? get boundPort => _server?.port;

  /// Number of currently connected WebSocket clients.
  int get clientCount => _clients.length;

  /// Starts the web server. Returns `true` on success.
  Future<bool> start() async {
    if (_running) return true;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _server!.listen(
        _handleRequest,
        onError: (Object _) {
          // Ignore individual request errors while running.
        },
      );
      _broker.logInfo('[WebServer] Started on port $port');
      return true;
    } catch (ex) {
      _broker.logError('[WebServer] Failed to start on port $port: $ex');
      _running = false;
      return false;
    }
  }

  /// Stops the web server and closes all WebSocket clients.
  void stop() {
    if (!_running && _server == null) return;
    _running = false;
    for (final client in List<WebSocketClient>.from(_clients.values)) {
      client._close();
    }
    _clients.clear();
    _server?.close(force: true);
    _server = null;
    _broker.logInfo('[WebServer] Stopped');
  }

  void dispose() {
    stop();
    _broker.dispose();
  }

  /// Sends a text message to every connected WebSocket client.
  void broadcastText(String message) {
    for (final client in _clients.values) {
      client.sendText(message);
    }
  }

  /// Sends a binary message to every connected WebSocket client.
  void broadcastBinary(List<int> data) {
    for (final client in _clients.values) {
      client.sendBinary(data);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // WebSocket upgrade requests are bridged to the radio.
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      await _handleWebSocket(request);
      return;
    }
    await _handleHttpRequest(request);
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    if (request.uri.path != _webSocketPath) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('404 - Not Found');
      await request.response.close();
      return;
    }

    WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }

    final clientId = _nextClientId++;
    final client = WebSocketClient(clientId, socket);
    _clients[clientId] = client;
    _broker.logInfo('[WebServer] WebSocket client $clientId connected');
    onClientConnected?.call(client);

    socket.listen(
      (dynamic message) {
        if (message is String) {
          onTextMessage?.call(client, message);
        } else if (message is List<int>) {
          onBinaryMessage?.call(client, Uint8List.fromList(message));
        }
      },
      onError: (Object _) {
        _removeClient(client);
      },
      onDone: () {
        _removeClient(client);
      },
      cancelOnError: true,
    );
  }

  void _removeClient(WebSocketClient client) {
    if (_clients.remove(client.id) == null) return;
    _broker.logInfo('[WebServer] WebSocket client ${client.id} disconnected');
    onClientDisconnected?.call(client);
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    try {
      var urlPath = request.uri.path;
      if (urlPath == '/' || urlPath.isEmpty) urlPath = '/index.html';

      // Decode and normalize to a relative asset path using forward slashes
      // (Flutter asset keys always use '/').
      final relativePath = Uri.decodeComponent(
        urlPath.startsWith('/') ? urlPath.substring(1) : urlPath,
      );

      // Security check: prevent path traversal.
      if (relativePath.contains('..') || relativePath.contains('\\')) {
        response.statusCode = HttpStatus.badRequest;
        response.headers.contentType = ContentType.text;
        response.write('400 - Bad Request');
        await response.close();
        return;
      }

      final assetKey = _resolveAssetKey(relativePath);
      var bytes = await _tryLoadAsset(assetKey);
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.text;
        response.write('404 - File Not Found');
        await response.close();
        return;
      }

      // Enable the page's WebSocket bridge mode (mirrors the C# server, which
      // rewrites `index.html` so the browser talks to this server instead of
      // using standalone Web Bluetooth).
      if (urlPath == '/index.html') {
        bytes = _enableWebSocketMode(bytes);
      }

      response.statusCode = HttpStatus.ok;
      response.headers.contentType = _contentTypeFor(relativePath);
      response.headers.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
    } catch (ex) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.text;
        response.write('500 - Internal Server Error\n$ex');
        await response.close();
      } catch (_) {
        // Response already (partly) sent; nothing more to do.
      }
    }
  }

  /// Rewrites the served `index.html` to put the page into WebSocket bridge
  /// mode (`var websocketMode = true;`).
  List<int> _enableWebSocketMode(List<int> bytes) {
    try {
      final html = String.fromCharCodes(bytes);
      final patched = html.replaceFirst(
        'var websocketMode = false;',
        'var websocketMode = true;',
      );
      return patched.codeUnits;
    } catch (_) {
      return bytes;
    }
  }

  /// Maps a web URL relative path to a bundled asset key. Most paths resolve
  /// under [_assetBase], but a few files are shared with the main Flutter app
  /// assets so the duplicate copy doesn't need to be bundled twice.
  static String _resolveAssetKey(String relativePath) {
    // The web UI's `images/radio.png` is byte-identical to the app's
    // `assets/images/Radio.png`. Serve the shared app asset instead of
    // bundling a duplicate under `assets/web/images/`.
    if (relativePath == 'images/radio.png') {
      return 'assets/images/Radio.png';
    }
    return '$_assetBase/$relativePath';
  }

  /// Loads a bundled asset, returning its bytes or `null` if it does not exist.
  Future<List<int>?> _tryLoadAsset(String assetKey) async {
    try {
      final data = await rootBundle.load(assetKey);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  /// Returns the MIME content type for [path] based on its file extension,
  /// mirroring the C# `GetMimeType` switch (with a few common additions).
  static ContentType _contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'html':
      case 'htm':
        return ContentType.html;
      case 'css':
        return ContentType('text', 'css', charset: 'utf-8');
      case 'js':
      case 'mjs':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case 'json':
        return ContentType('application', 'json', charset: 'utf-8');
      case 'webmanifest':
        return ContentType('application', 'manifest+json', charset: 'utf-8');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'gif':
        return ContentType('image', 'gif');
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'ico':
        return ContentType('image', 'x-icon');
      case 'txt':
        return ContentType.text;
      default:
        return ContentType('application', 'octet-stream');
    }
  }
}
