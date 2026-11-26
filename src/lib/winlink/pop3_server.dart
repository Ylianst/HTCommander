// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'mail_mime.dart';
import 'mail_server.dart';
import 'winlink_mail.dart';

class Pop3Server extends MailServer {
  Pop3Server(
    super.port, {
    required super.store,
    required super.account,
    required super.password,
  });
  Object? _maildropOwner;
  @override
  String get protocol => 'POP3';
  @override
  MailSession createSession(Socket socket) => _Pop3Session(this, socket);
}

class _Pop3Session extends MailSession {
  _Pop3Session(this._pop, Socket socket) : super(_pop, socket);
  final Pop3Server _pop;
  String? _username;
  bool _authenticated = false;
  final List<(String, Uint8List)> _messages = [];
  final Set<int> _deleted = {};

  @override
  String get greeting => '+OK HTCommander POP3 ready';
  @override
  String get failureResponse => '-ERR Local mail server error';
  @override
  void onClosed() {
    if (_pop._maildropOwner == this) _pop._maildropOwner = null;
  }

  int get _count => _messages.length - _deleted.length;
  int get _size => [
    for (var i = 0; i < _messages.length; i++)
      if (!_deleted.contains(i)) _messages[i].$2.length,
  ].fold(0, (sum, size) => sum + size);

  @override
  Future<void> handleLine(String line) async {
    final separator = line.indexOf(' ');
    final command = (separator < 0 ? line : line.substring(0, separator))
        .toUpperCase();
    // Passwords may contain spaces; preserve the argument verbatim.
    final args = separator < 0 ? '' : line.substring(separator + 1);
    if (command == 'QUIT') {
      if (_authenticated && _deleted.isNotEmpty) {
        final changed = <WinLinkMail>[];
        for (final index in _deleted) {
          final mail = server.store.getMail(_messages[index].$1);
          if (mail != null && mail.mailbox == 'Inbox') {
            mail.mailbox = 'Trash';
            server.store.updateMail(mail);
            changed.add(mail);
          }
        }
        try {
          await server.store.flush();
          server.broker.dispatch(
            deviceId: 0,
            name: 'MailsChanged',
            data: null,
            store: false,
          );
        } catch (error) {
          for (final mail in changed) {
            mail.mailbox = 'Inbox';
            server.store.updateMail(mail);
          }
          server.broker.logError('[POP3] Cannot save deletions: $error');
          reply('-ERR Cannot save deletions');
          await finish();
          return;
        }
      }
      reply('+OK Goodbye');
      await finish();
      return;
    }
    if (command == 'CAPA') {
      reply('+OK Capabilities');
      if (!_authenticated) reply('USER');
      reply('UIDL');
      reply('TOP');
      reply('RESP-CODES');
      reply('.');
      return;
    }
    if (!_authenticated) {
      if (command == 'USER') {
        _username = args;
        reply('+OK Password required');
      } else if (command == 'PASS' && _username != null) {
        if (!server.authenticate(_username!, args)) {
          reply('-ERR [AUTH] Invalid credentials');
          if (++authFailures >= 5) abort();
        } else if (_pop._maildropOwner != null) {
          reply('-ERR [IN-USE] Maildrop is locked');
        } else {
          _pop._maildropOwner = this;
          for (final mail in server.store.getAllMails()) {
            if (mail.mailbox == 'Inbox' && mail.mid != null) {
              _messages.add((mail.mid!, MailMime.encode(mail)));
            }
          }
          _authenticated = true;
          reply('+OK $_count messages');
        }
      } else {
        reply('-ERR Authentication required; use USER and PASS');
      }
      return;
    }
    switch (command) {
      case 'STAT':
        reply('+OK $_count $_size');
      case 'NOOP':
        reply('+OK');
      case 'RSET':
        _deleted.clear();
        reply('+OK $_count messages');
      case 'LIST':
      case 'UIDL':
        if (args.isEmpty) {
          reply('+OK');
          for (var i = 0; i < _messages.length; i++) {
            if (!_deleted.contains(i)) reply(_listing(i, command));
          }
          reply('.');
        } else {
          final index = _index(args);
          if (index != null) reply('+OK ${_listing(index, command)}');
        }
      case 'RETR':
      case 'TOP':
        final parts = args.split(RegExp(r'\s+'));
        final index = _index(parts.first);
        if (index == null) return;
        final topLines = command == 'TOP' && parts.length == 2
            ? int.tryParse(parts[1])
            : null;
        if (command == 'TOP' && (topLines == null || topLines < 0)) {
          reply('-ERR Invalid TOP line count');
          return;
        }
        reply('+OK ${_messages[index].$2.length} octets');
        final lines = const LineSplitter().convert(
          latin1.decode(_messages[index].$2),
        );
        var inBody = false;
        var bodyLines = 0;
        for (final text in lines) {
          if (inBody && topLines != null && bodyLines++ >= topLines) break;
          socket.add(
            latin1.encode('${text.startsWith('.') ? '.' : ''}$text\r\n'),
          );
          if (text.isEmpty) inBody = true;
        }
        reply('.');
      case 'DELE':
        final index = _index(args);
        if (index != null) {
          _deleted.add(index);
          reply('+OK Marked for deletion');
        }
      default:
        reply('-ERR Command not supported');
    }
  }

  int? _index(String arg) {
    final number = int.tryParse(arg);
    if (number == null ||
        number < 1 ||
        number > _messages.length ||
        _deleted.contains(number - 1)) {
      reply('-ERR No such message');
      return null;
    }
    return number - 1;
  }

  String _listing(int index, String command) {
    final (mid, bytes) = _messages[index];
    final value = command == 'LIST'
        ? '${bytes.length}'
        : sha256.convert(utf8.encode(mid)).toString();
    return '${index + 1} $value';
  }
}
