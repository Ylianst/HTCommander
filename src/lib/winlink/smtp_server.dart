// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mail_mime.dart';
import 'mail_server.dart';

class SmtpServer extends MailServer {
  SmtpServer(
    super.port, {
    required super.store,
    required super.account,
    required super.password,
  });

  @override
  String get protocol => 'SMTP';
  @override
  MailSession createSession(Socket socket) => _SmtpSession(this, socket);
}

class _SmtpSession extends MailSession {
  _SmtpSession(super.server, super.socket);
  bool _greeted = false;
  bool _authenticated = false;
  String? _authStep;
  String _authUsername = '';
  String? _sender;
  final List<String> _recipients = [];
  bool _inData = false;
  bool _tooLarge = false;
  final BytesBuilder _data = BytesBuilder(copy: false);

  @override
  String get greeting => '220 localhost HTCommander ESMTP';
  @override
  String get failureResponse => '451 Local mail server error';

  void _reset() {
    _sender = null;
    _recipients.clear();
    _data.clear();
    _inData = false;
    _tooLarge = false;
  }

  @override
  Future<void> handleLine(String line) async {
    if (_inData) {
      if (line == '.') {
        if (_tooLarge) {
          reply('552 Message exceeds ${MailServer.maxMessageBytes} bytes');
        } else {
          try {
            final mail = MailMime.decodeSubmission(
              _data.takeBytes(),
              account: server.account,
              recipients: _recipients,
            );
            await server.store.addMailDurably(mail);
            server.broker.logInfo('[SMTP] Queued mail ${mail.mid} in Outbox');
            reply('250 Queued in HTCommander Outbox; Winlink sync required');
          } on FormatException catch (error) {
            final message = error.message.replaceAll(RegExp(r'[\r\n]'), ' ');
            reply('554 $message');
          } catch (error) {
            server.broker.logError('[SMTP] Cannot persist submission: $error');
            reply('451 Cannot save message; please retry');
          }
        }
        _reset();
      } else {
        if (line.startsWith('..')) line = line.substring(1);
        if (_data.length + line.length + 2 > MailServer.maxMessageBytes) {
          _tooLarge = true;
          _data.clear();
        }
        if (!_tooLarge) _data.add(latin1.encode('$line\r\n'));
      }
      return;
    }
    if (_authStep != null) {
      _handleAuth(line);
      return;
    }
    final separator = line.indexOf(' ');
    final command = (separator < 0 ? line : line.substring(0, separator))
        .toUpperCase();
    final args = separator < 0 ? '' : line.substring(separator + 1).trim();
    switch (command) {
      case 'EHLO':
      case 'HELO':
        if (args.isEmpty) {
          reply('501 Hostname required');
          return;
        }
        _reset();
        _greeted = true;
        _authenticated = false;
        reply(command == 'EHLO' ? '250-localhost' : '250 localhost');
        if (command == 'EHLO') {
          reply('250-SIZE ${MailServer.maxMessageBytes}');
          reply('250-8BITMIME');
          reply('250 AUTH PLAIN LOGIN');
        }
      case 'AUTH':
        if (!_greeted || _sender != null || _authenticated) {
          reply('503 Bad sequence of commands');
          return;
        }
        final parts = args.split(RegExp(r'\s+'));
        final mechanism = parts.first.toUpperCase();
        if (mechanism != 'PLAIN' && mechanism != 'LOGIN') {
          reply('504 Authentication mechanism not supported');
          return;
        }
        _authStep = mechanism == 'PLAIN' ? 'plain' : 'username';
        if (parts.length > 1) {
          _handleAuth(parts[1]);
        } else {
          reply(mechanism == 'PLAIN' ? '334 ' : '334 VXNlcm5hbWU6');
        }
      case 'MAIL':
        if (!_greeted || !_authenticated) {
          reply('530 Authentication required');
          return;
        }
        _reset();
        final match = RegExp(
          r'^FROM:\s*<([^<>]*)>(?:\s+(.*))?$',
          caseSensitive: false,
        ).firstMatch(args);
        if (match == null ||
            !MailMime.isAccountAddress(match[1]!, server.account)) {
          reply('553 Sender must be ${server.account}@winlink.org');
          return;
        }
        final parameters = match[2] ?? '';
        for (final parameter in parameters.split(RegExp(r'\s+'))) {
          if (parameter.isEmpty) continue;
          if (parameter.toUpperCase().startsWith('SIZE=')) {
            final size = int.tryParse(parameter.substring(5));
            if (size == null || size < 0) {
              reply('501 Invalid SIZE');
              return;
            }
            if (size > MailServer.maxMessageBytes) {
              reply('552 Message too large');
              return;
            }
          } else if (parameter.toUpperCase() != 'BODY=8BITMIME' &&
              parameter.toUpperCase() != 'BODY=7BIT') {
            reply('555 Unsupported MAIL parameter');
            return;
          }
        }
        _sender = match[1];
        reply('250 Sender accepted');
      case 'RCPT':
        if (_sender == null) {
          reply('503 MAIL required');
          return;
        }
        final match = RegExp(
          r'^TO:\s*<([^<>]+)>$',
          caseSensitive: false,
        ).firstMatch(args);
        if (match == null || !MailMime.isEmailAddress(match[1]!)) {
          reply('501 Invalid recipient');
          return;
        }
        if (_recipients.length >= 100) {
          reply('452 Too many recipients');
          return;
        }
        _recipients.add(match[1]!);
        reply('250 Recipient accepted');
      case 'DATA':
        if (_sender == null || _recipients.isEmpty) {
          reply('503 MAIL and RCPT required');
          return;
        }
        _inData = true;
        reply('354 End with <CRLF>.<CRLF>');
      case 'RSET':
        _reset();
        reply('250 Reset');
      case 'NOOP':
        reply('250 OK');
      case 'QUIT':
        reply('221 Goodbye');
        await finish();
      default:
        reply('502 Command not implemented');
    }
  }

  void _handleAuth(String input) {
    if (input == '*') {
      _authStep = null;
      reply('501 Authentication cancelled');
      return;
    }
    try {
      final decoded = utf8.decode(base64.decode(input));
      if (_authStep == 'username') {
        _authUsername = decoded;
        _authStep = 'password';
        reply('334 UGFzc3dvcmQ6');
        return;
      }
      var username = _authUsername;
      var password = decoded;
      if (_authStep == 'plain') {
        final fields = decoded.split('\x00');
        if (fields.length != 3 ||
            (fields[0].isNotEmpty && fields[0] != fields[1])) {
          throw const FormatException('Invalid AUTH PLAIN');
        }
        username = fields[1];
        password = fields[2];
      }
      _authStep = null;
      _authenticated = server.authenticate(username, password);
      reply(_authenticated ? '235 Authenticated' : '535 Invalid credentials');
    } on FormatException {
      _authStep = null;
      reply('501 Invalid authentication data');
    }
    if (!_authenticated && ++authFailures >= 5) abort();
  }
}
