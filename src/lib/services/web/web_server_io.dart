/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

A minimal HTTP + WebSocket server that serves the Flutter web build (see
[_resolveWebAppDir]) and bridges the radio to connected browsers over a
WebSocket at `/websocket.aspx`. Bound to all interfaces (`anyIPv4`).

The served Flutter UI connects back over that WebSocket to share the host's
radio instead of using the browser's Web Bluetooth (see
radio/websocket_transport.dart).

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

/// Serves the Flutter web build over HTTP and bridges the radio over a
/// WebSocket on desktop platforms.
class WebServer {
  WebServer(this.port) : _broker = DataBrokerClient();

  /// The WebSocket endpoint the browser connects to.
  static const String _webSocketPath = '/websocket.aspx';

  final int port;
  final DataBrokerClient _broker;

  HttpServer? _server;
  bool _running = false;
  int _nextClientId = 1;
  final Map<int, WebSocketClient> _clients = <int, WebSocketClient>{};

  /// Cached, resolved Flutter web build directory. Null until first resolved;
  /// only cached once a valid build is found so a build produced after startup
  /// is still picked up.
  Directory? _webAppDir;

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
      final dir = _resolveWebAppDir();
      if (dir == null) {
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.text;
        response.write(
          '404 - Flutter web build not found. Run tools/build_web_app.ps1 or '
          'place the build under a "web_app" folder next to the app.',
        );
        await response.close();
        return;
      }

      var urlPath = request.uri.path;
      if (urlPath == '/' || urlPath.isEmpty) urlPath = '/index.html';
      final rel = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;
      final relativePath = Uri.decodeComponent(rel);

      // Security check: prevent path traversal.
      if (relativePath.contains('..') ||
          relativePath.contains('\\') ||
          relativePath.startsWith('/')) {
        response.statusCode = HttpStatus.badRequest;
        response.headers.contentType = ContentType.text;
        response.write('400 - Bad Request');
        await response.close();
        return;
      }

      // De-duplication: the app's own pubspec assets (declared under `assets/`)
      // are bundled into the Flutter web build under `assets/assets/...`, which
      // is byte-identical to what the desktop app already carries in its asset
      // bundle. Serve those straight from `rootBundle` so the staged web build
      // need not ship a second copy (see tools/build_web_app.ps1). Engine files
      // (manifests, fonts, packages) live under a single `assets/` and are left
      // to the web build, which tree-shakes them per platform.
      if (relativePath.startsWith('assets/assets/')) {
        final bundleKey = relativePath.substring('assets/'.length);
        final bundled = await _tryLoadAsset(bundleKey);
        if (bundled != null) {
          response.statusCode = HttpStatus.ok;
          response.headers.contentType = _contentTypeFor(relativePath);
          response.headers.contentLength = bundled.length;
          response.add(bundled);
          await response.close();
          return;
        }
      }

      final file = File('${dir.path}${Platform.pathSeparator}'
          '${relativePath.replaceAll('/', Platform.pathSeparator)}');
      if (!file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.text;
        response.write('404 - File Not Found');
        await response.close();
        return;
      }

      final bytes = await file.readAsBytes();
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

  /// Resolves the Flutter web build directory, or `null` if none is found.
  ///
  /// Search order: the `webAppPath` setting (device 0), a `web_app` folder next
  /// to the executable (Windows/Linux) or in the app bundle's `Resources`
  /// (macOS), and `build/web` under the working directory (dev convenience). A
  /// directory only qualifies if it contains `index.html`.
  Directory? _resolveWebAppDir() {
    final cached = _webAppDir;
    if (cached != null && File('${cached.path}${Platform.pathSeparator}'
            'index.html')
        .existsSync()) {
      return cached;
    }

    final sep = Platform.pathSeparator;
    final candidates = <String>[];
    final configured = _broker.getValue<String>(0, 'webAppPath', '') ?? '';
    if (configured.isNotEmpty) candidates.add(configured);
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir${sep}web_app');
      // macOS .app bundle: the web build is staged under Contents/Resources
      // (Contents/MacOS holds the executable) so it is sealed by code signing.
      candidates.add('$exeDir$sep..${sep}Resources${sep}web_app');
    } catch (_) {
      // resolvedExecutable may be unavailable in some test hosts.
    }
    candidates.add('build${sep}web');

    for (final path in candidates) {
      final dir = Directory(path);
      if (dir.existsSync() &&
          File('${dir.path}${Platform.pathSeparator}index.html')
              .existsSync()) {
        _webAppDir = dir;
        return dir;
      }
    }
    return null;
  }

  /// Loads a bundled asset (from the desktop app's own asset bundle),
  /// returning its bytes or `null` if it does not exist.
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
