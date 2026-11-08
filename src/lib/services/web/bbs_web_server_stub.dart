/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web stub for [BbsWebServer]. The web build cannot open listening sockets, so
the HTTP BBS server is unavailable. The public surface matches the `dart:io`
implementation so shared code keeps compiling.
*/

import 'dart:typed_data';

typedef BbsWebClientCallback = void Function(BbsWebClient client);

typedef BbsWebTextCallback = void Function(BbsWebClient client, String message);

class BbsWebFile {
  const BbsWebFile(this.name, this.data);

  final String name;
  final Uint8List data;
}

typedef BbsWebDownloadCallback =
    BbsWebFile? Function(BbsWebClient client, String id);

typedef BbsWebUploadCallback =
    ({bool ok, String message, bool notified}) Function(
      BbsWebClient client,
      String name,
      Uint8List data,
    );

/// Inert web stub of a connected HTTP BBS client.
class BbsWebClient {
  BbsWebClient(this.id, this.callsign, this.remoteAddress);

  final int id;
  final String callsign;
  final String remoteAddress;
  final String fileToken = '';

  void sendText(String message) {}

  void close([int code = 1000, String reason = '']) {}
}

/// Inert web stub of the HTTP BBS server.
class BbsWebServer {
  BbsWebServer(this.port);

  static const String filesPath = '/files/';
  static const String uploadPath = '/upload';

  final int port;
  int maxUploadBytes = 25 * 1024;

  BbsWebClientCallback? onClientConnected;
  BbsWebClientCallback? onClientDisconnected;
  BbsWebTextCallback? onTextMessage;
  BbsWebDownloadCallback? onFileDownload;
  BbsWebUploadCallback? onFileUpload;

  bool get isRunning => false;

  int? get boundPort => null;

  int get clientCount => 0;

  Future<bool> start() async => false;

  void stop() {}

  void dispose() {}
}
