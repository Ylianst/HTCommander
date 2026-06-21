/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../services/data_broker_client.dart';
import 'winlink_mail.dart';

/// A minimal SMTP server that listens on the loopback interface and queues
/// received emails into the Outbox via the data broker. Used so that standard
/// mail clients (Outlook, Thunderbird, etc.) can submit Winlink mail locally.
class SmtpServer {
  SmtpServer(this.port) : _broker = DataBrokerClient();

  final int port;
  final DataBrokerClient _broker;

  ServerSocket? _listener;
  bool _running = false;
  final List<SmtpSession> _sessions = <SmtpSession>[];

  /// Starts the SMTP server. Returns true on success.
  Future<bool> start() async {
    try {
      _listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _running = true;
      _listener!.listen(
        _onConnection,
        onError: (Object _) {
          // Ignore accept errors while running.
        },
      );
      _broker.logInfo('[SmtpServer] Started on port $port');
      return true;
    } catch (ex) {
      _broker.logError('[SmtpServer] Failed to start: $ex');
      return false;
    }
  }

  void _onConnection(Socket socket) {
    if (!_running) {
      socket.destroy();
      return;
    }
    final session = SmtpSession(this, _broker, socket);
    _sessions.add(session);
    session.run();
  }

  /// Stops the SMTP server and closes all active sessions.
  void stop() {
    _running = false;
    _listener?.close();
    _listener = null;
    final sessionArray = List<SmtpSession>.from(_sessions);
    for (final session in sessionArray) {
      session.close();
    }
    _sessions.clear();
    _broker.logInfo('[SmtpServer] Stopped');
  }

  void removeSession(SmtpSession session) {
    _sessions.remove(session);
  }

  void dispose() {
    stop();
    _broker.dispose();
  }
}

/// Handles a single SMTP client connection.
class SmtpSession {
  SmtpSession(this._server, this._broker, this._socket);

  final SmtpServer _server;
  final DataBrokerClient _broker;
  final Socket _socket;

  String? _mailFrom;
  final List<String> _rcptTo = <String>[];
  bool _inDataMode = false;
  final StringBuffer _dataBuffer = StringBuffer();
  final StringBuffer _lineBuffer = StringBuffer();
  bool _closed = false;

  void run() {
    try {
      // RFC 5321 compliant greeting
      _socket.add(utf8.encode('220 localhost ESMTP\r\n'));

      _socket.listen(
        _onData,
        onError: (Object _) => close(),
        onDone: close,
        cancelOnError: true,
      );
    } catch (_) {
      close();
    }
  }

  void _onData(Uint8List data) {
    if (_closed) return;
    final received = utf8.decode(data, allowMalformed: true);
    _lineBuffer.write(received);

    var bufferedText = _lineBuffer.toString();
    int newlinePos;
    while ((newlinePos = bufferedText.indexOf('\n')) >= 0) {
      var line = bufferedText.substring(0, newlinePos);
      // Trim trailing \r and \n
      line = line.replaceAll(RegExp(r'[\r\n]+$'), '');
      bufferedText = bufferedText.substring(newlinePos + 1);

      if (line.trim().isNotEmpty || _inDataMode) {
        if (_inDataMode) {
          _processDataLine(line);
        } else {
          _processCommand(line);
        }
        if (_closed) return;
      }
    }

    _lineBuffer.clear();
    _lineBuffer.write(bufferedText);
  }

  void _processCommand(String line) {
    final parts = line.split(RegExp(r' '));
    if (parts.isEmpty) return;

    final command = parts[0].toUpperCase();
    final spaceIndex = line.indexOf(' ');
    final args = spaceIndex >= 0 ? line.substring(spaceIndex + 1) : '';

    try {
      switch (command) {
        case 'HELO':
        case 'EHLO':
          _handleHelo(command);
          break;
        case 'MAIL':
          _handleMailFrom(args);
          break;
        case 'RCPT':
          _handleRcptTo(args);
          break;
        case 'DATA':
          _handleData();
          break;
        case 'RSET':
          _handleRset();
          break;
        case 'NOOP':
          _sendResponse('250 OK');
          break;
        case 'QUIT':
          _handleQuit();
          break;
        default:
          _sendResponse('500 Command not recognized: $command');
          break;
      }
    } catch (ex) {
      _sendResponse('451 Requested action aborted: $ex');
    }
  }

  void _handleHelo(String command) {
    if (command == 'EHLO') {
      _sendResponse('250-localhost');
      _sendResponse('250-8BITMIME');
      _sendResponse('250-SIZE 10240000');
      _sendResponse('250 HELP');
    } else {
      _sendResponse('250 localhost');
    }
  }

  void _handleMailFrom(String args) {
    if (!args.toUpperCase().startsWith('FROM:')) {
      _sendResponse('501 Syntax error in MAIL FROM command');
      return;
    }

    var address = args.substring(5).trim();
    if (address.startsWith('<') && address.endsWith('>')) {
      address = address.substring(1, address.length - 1);
    }

    _mailFrom = address;
    _rcptTo.clear();
    _sendResponse('250 OK');
  }

  void _handleRcptTo(String args) {
    if (!args.toUpperCase().startsWith('TO:')) {
      _sendResponse('501 Syntax error in RCPT TO command');
      return;
    }

    var address = args.substring(3).trim();
    if (address.startsWith('<') && address.endsWith('>')) {
      address = address.substring(1, address.length - 1);
    }

    _rcptTo.add(address);
    _sendResponse('250 OK');
  }

  void _handleData() {
    if (_mailFrom == null || _mailFrom!.isEmpty || _rcptTo.isEmpty) {
      _sendResponse('503 Bad sequence of commands');
      return;
    }

    _sendResponse('354 Start mail input; end with <CRLF>.<CRLF>');
    _inDataMode = true;
    _dataBuffer.clear();
  }

  void _processDataLine(String line) {
    // Check for end of data (single dot on a line)
    if (line == '.') {
      _inDataMode = false;
      _processEmailData();
      return;
    }

    // Handle byte-stuffing (remove leading dot if present)
    if (line.startsWith('..')) {
      line = line.substring(1);
    }

    _dataBuffer.writeln(line);
  }

  void _processEmailData() {
    try {
      final emailData = _dataBuffer.toString();

      // Parse email headers and body
      String from = _mailFrom ?? '';
      String to = _rcptTo.join('; ');
      String cc = '';
      String subject = '';
      DateTime dateTime = DateTime.now();

      final lines = const LineSplitter().convert(emailData);
      bool inHeaders = true;
      final bodyBuilder = StringBuffer();

      for (final line in lines) {
        if (inHeaders) {
          if (line.trim().isEmpty) {
            inHeaders = false;
            continue;
          }

          final lower = line.toLowerCase();
          if (lower.startsWith('from:')) {
            from = line.substring(5).trim();
            // Remove angle brackets if present
            if (from.contains('<') && from.contains('>')) {
              final start = from.indexOf('<') + 1;
              final end = from.indexOf('>');
              from = from.substring(start, end);
            }
          } else if (lower.startsWith('to:')) {
            to = line.substring(3).trim();
          } else if (lower.startsWith('cc:')) {
            cc = line.substring(3).trim();
          } else if (lower.startsWith('subject:')) {
            subject = line.substring(8).trim();
          } else if (lower.startsWith('date:')) {
            final dateStr = line.substring(5).trim();
            final parsed = DateTime.tryParse(dateStr);
            if (parsed != null) dateTime = parsed;
          }
        } else {
          bodyBuilder.writeln(line);
        }
      }

      final body = bodyBuilder.toString().trimRight();

      // Create new email and queue it to the Outbox
      final mail = WinLinkMail()
        ..mid = WinLinkMail.generateMID()
        ..from = from
        ..to = to
        ..cc = cc
        ..subject = subject
        ..body = body
        ..dateTime = dateTime
        ..mailbox = 'Outbox';

      // Queue to the Outbox via the data broker (replaces MainForm.mailStore.AddMail)
      _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);

      _broker.logInfo(
        '[SmtpServer] Email queued to Outbox - From: $from, To: $to, Subject: $subject',
      );
      _sendResponse('250 OK: Message accepted for delivery');
    } catch (_) {
      _sendResponse('554 Transaction failed');
    } finally {
      _mailFrom = null;
      _rcptTo.clear();
      _dataBuffer.clear();
    }
  }

  void _handleRset() {
    _mailFrom = null;
    _rcptTo.clear();
    _dataBuffer.clear();
    _inDataMode = false;
    _sendResponse('250 OK');
  }

  void _handleQuit() {
    _sendResponse('221 Bye');
    close();
  }

  void _sendResponse(String response) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode('$response\r\n'));
    } catch (_) {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _socket.destroy();
    } catch (_) {
      // Ignore close errors.
    }
    _server.removeSession(this);
  }
}
