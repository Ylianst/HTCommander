// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/data_broker_client.dart';
import 'mail_store.dart';

/// Shared native transport for the loopback-only, authenticated mail bridge.
abstract class MailServer {
  MailServer(
    this.port, {
    required this.store,
    required this.account,
    required this.password,
  });

  static const maxMessageBytes = 10 * 1024 * 1024;
  final int port;
  final MailStore store;
  final String account;
  final String password;
  final broker = DataBrokerClient();
  ServerSocket? _listener;
  final Map<MailSession, Future<void>> _sessions = {};
  bool get isRunning => _listener != null;
  int? get boundPort => _listener?.port;
  String get protocol;
  MailSession createSession(Socket socket);

  bool authenticate(String username, String suppliedPassword) {
    final normalized = username.toUpperCase();
    return password.isNotEmpty &&
        suppliedPassword == password &&
        (normalized == account.toUpperCase() ||
            normalized == '${account.toUpperCase()}@WINLINK.ORG');
  }

  Future<bool> start() async {
    if (isRunning) return true;
    if (account.isEmpty || password.isEmpty) {
      broker.logError('[$protocol] Callsign and bridge password are required');
      return false;
    }
    try {
      _listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _listener!.listen(
        (socket) {
          if (!isRunning || _sessions.length >= 8) {
            socket.destroy();
            return;
          }
          final session = createSession(socket);
          _sessions[session] = session.run().whenComplete(() {
            _sessions.remove(session);
          });
        },
        onError: (Object error) {
          broker.logError('[$protocol] Listener error: $error');
        },
      );
      broker.logInfo('[$protocol] Listening on 127.0.0.1:$boundPort');
      return true;
    } on SocketException catch (error) {
      broker.logError('[$protocol] Failed to start: $error');
      return false;
    }
  }

  Future<void> stop() async {
    final listener = _listener;
    _listener = null;
    final sessions = Map<MailSession, Future<void>>.of(_sessions);
    for (final session in sessions.keys) {
      session.abort();
    }
    await listener?.close();
    await Future.wait(sessions.values);
  }

  void dispose() {
    unawaited(stop());
    broker.dispose();
  }
}

abstract class MailSession {
  MailSession(this.server, this.socket);
  final MailServer server;
  final Socket socket;
  bool closed = false;
  int authFailures = 0;
  String get greeting;
  String get failureResponse;
  Future<void> handleLine(String line);
  void onClosed() {}

  void reply(String line) {
    if (!closed) socket.write('$line\r\n');
  }

  Future<void> finish() async {
    if (closed) return;
    closed = true;
    await socket.flush();
    await socket.close();
  }

  void abort() {
    closed = true;
    socket.destroy();
  }

  Future<void> run() async {
    try {
      reply(greeting);
      var buffered = '';
      await for (final bytes in socket.timeout(const Duration(minutes: 5))) {
        // Latin-1 preserves each octet, including UTF-8 split across packets.
        buffered += latin1.decode(bytes);
        while (!closed) {
          final end = buffered.indexOf('\n');
          if (end < 0) break;
          if (end > 65536) throw const FormatException('Mail line too long');
          var line = buffered.substring(0, end);
          buffered = buffered.substring(end + 1);
          if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
          await handleLine(line);
        }
        if (closed) break;
        if (buffered.length > 65536) {
          throw const FormatException('Mail line too long');
        }
      }
    } on SocketException catch (error) {
      if (!closed) {
        server.broker.logError('[${server.protocol}] Connection error: $error');
      }
    } on TimeoutException {
      server.broker.logInfo('[${server.protocol}] Idle client disconnected');
    } catch (error) {
      server.broker.logError('[${server.protocol}] Session failed: $error');
      reply(failureResponse);
      try {
        await finish();
      } on SocketException catch (error) {
        server.broker.logError('[${server.protocol}] Closing client: $error');
      }
    } finally {
      abort();
      onClosed();
    }
  }
}
