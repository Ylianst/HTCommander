@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/web/web_server.dart';

/// Performs a raw HTTP/1.1 GET against the local server. A raw [Socket] is used
/// because [TestWidgetsFlutterBinding] stubs out [HttpClient] (it forces every
/// request to 400), while leaving real server sockets working.
Future<({int status, String contentType, String body})> _get(
  int port,
  String rawPath,
) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write(
    'GET $rawPath HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
  );
  await socket.flush();

  final bytes = <int>[];
  await for (final chunk in socket) {
    bytes.addAll(chunk);
  }
  socket.destroy();

  final text = latin1.decode(bytes);
  final headerEnd = text.indexOf('\r\n\r\n');
  final headerPart = headerEnd >= 0 ? text.substring(0, headerEnd) : text;
  final body = headerEnd >= 0 ? text.substring(headerEnd + 4) : '';

  final lines = headerPart.split('\r\n');
  final statusLine = lines.isNotEmpty ? lines.first : '';
  final statusMatch = RegExp(r'HTTP/1\.\d (\d{3})').firstMatch(statusLine);
  final status = statusMatch != null ? int.parse(statusMatch.group(1)!) : 0;

  var contentType = '';
  for (final line in lines.skip(1)) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    if (line.substring(0, idx).trim().toLowerCase() == 'content-type') {
      contentType = line.substring(idx + 1).trim().split(';').first.trim();
    }
  }
  return (status: status, contentType: contentType, body: body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serves bundled index.html and 404s missing files', () async {
    final server = WebServer(0); // ephemeral port
    expect(await server.start(), isTrue);
    addTearDown(server.dispose);

    final port = server.boundPort;
    expect(port, isNotNull);

    // Root path resolves to index.html and returns the bundled content.
    final root = await _get(port!, '/');
    expect(root.status, 200);
    expect(root.contentType, 'text/html');
    expect(root.body.toLowerCase(), contains('<html'));

    // index.html is served in WebSocket bridge mode (the server rewrites the
    // default standalone-Bluetooth flag), matching the C# implementation.
    expect(root.body, contains('var websocketMode = true;'));
    expect(root.body, isNot(contains('var websocketMode = false;')));

    // A static JS asset is served with the JavaScript MIME type.
    final js = await _get(port, '/radio.js');
    expect(js.status, 200);
    expect(js.contentType, 'application/javascript');

    // Unknown files return 404.
    final missing = await _get(port, '/does-not-exist.txt');
    expect(missing.status, 404);
  });

  test('rejects path traversal attempts', () async {
    final server = WebServer(0);
    expect(await server.start(), isTrue);
    addTearDown(server.dispose);

    final res = await _get(server.boundPort!, '/..%2f..%2fpubspec.yaml');
    expect(res.status, 400);
  });
}
