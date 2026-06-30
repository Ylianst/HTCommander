/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'mail_store.dart';
import 'winlink_mail.dart';

/// A minimal IMAP4rev1 server that exposes the local mail store to standard
/// mail clients. As in the original C# implementation, authentication is not
/// wired up, so the server advertises its capabilities but rejects access until
/// a login mechanism is enabled.
class ImapServer {
  ImapServer(this.port) : _broker = DataBrokerClient();

  final int port;
  final DataBrokerClient _broker;

  ServerSocket? _listener;
  bool _running = false;
  final List<ImapSession> _sessions = <ImapSession>[];

  /// Starts the IMAP server. Returns true on success.
  Future<bool> start() async {
    try {
      _listener = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _listener!.listen(
        _onConnection,
        onError: (Object _) {
          // Ignore accept errors while running.
        },
      );
      _broker.logInfo('[ImapServer] Started on port $port');
      return true;
    } catch (ex) {
      _broker.logError('[ImapServer] Failed to start: $ex');
      return false;
    }
  }

  void _onConnection(Socket socket) {
    if (!_running) {
      socket.destroy();
      return;
    }
    final session = ImapSession(this, _broker, socket);
    _sessions.add(session);
    session.run();
  }

  /// Stops the IMAP server and closes all active sessions.
  void stop() {
    _running = false;
    _listener?.close();
    _listener = null;
    final sessionArray = List<ImapSession>.from(_sessions);
    for (final session in sessionArray) {
      session.close();
    }
    _sessions.clear();
    _broker.logInfo('[ImapServer] Stopped');
  }

  void removeSession(ImapSession session) {
    _sessions.remove(session);
  }

  void dispose() {
    stop();
    _broker.dispose();
  }
}

/// Handles a single IMAP client connection.
class ImapSession {
  ImapSession(this._server, this._broker, this._socket);

  final ImapServer _server;
  final DataBrokerClient _broker;
  final Socket _socket;

  // Login code is not wired up, so this is always false (matches the C#
  // implementation where the LOGIN handler is commented out).
  final bool _authenticated = false;

  int _selectedMailbox = -1;
  final Map<int, int> _messageUids = <int, int>{};
  final Map<int, Set<String>> _messageFlags = <int, Set<String>>{};
  int _uidNext = 1;

  bool _closed = false;

  // Incoming byte buffer and APPEND literal state.
  final List<int> _buf = <int>[];
  int _appendLiteralRemaining = 0;
  final List<int> _appendData = <int>[];
  String _appendFolder = '';
  String _appendTag = '';

  // IMAP folder names mapped to mailbox indices.
  static const Map<String, int> _folderToMailbox = <String, int>{
    'INBOX': 0,
    'Outbox': 1,
    'Drafts': 2,
    'Sent': 3,
    'Archive': 4,
    'Trash': 5,
  };

  static const Map<int, String> _mailboxToFolder = <int, String>{
    0: 'INBOX',
    1: 'Outbox',
    2: 'Drafts',
    3: 'Sent',
    4: 'Archive',
    5: 'Trash',
  };

  static const List<String> _dayNames = <String>[
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  void run() {
    try {
      _writeLine('* OK HTCommander IMAP Server Ready');
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
    _buf.addAll(data);
    _process();
  }

  void _process() {
    while (!_closed) {
      if (_appendLiteralRemaining > 0) {
        final take = min(_appendLiteralRemaining, _buf.length);
        if (take > 0) {
          _appendData.addAll(_buf.sublist(0, take));
          _buf.removeRange(0, take);
          _appendLiteralRemaining -= take;
        }
        if (_appendLiteralRemaining > 0) return; // Need more bytes.
        _completeAppend();
        continue;
      }

      final nl = _buf.indexOf(0x0A);
      if (nl < 0) return;
      final lineBytes = _buf.sublist(0, nl);
      _buf.removeRange(0, nl + 1);
      var line = utf8.decode(
        Uint8List.fromList(lineBytes),
        allowMalformed: true,
      );
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.trim().isEmpty) continue;
      _processCommand(line);
    }
  }

  void _processCommand(String line) {
    // Parse IMAP command: tag command [args...]
    final parts = _splitN(line, 3);
    if (parts.length < 2) return;

    final tag = parts[0];
    final command = parts[1].toUpperCase();
    final args = parts.length > 2 ? parts[2] : '';

    try {
      switch (command) {
        case 'CAPABILITY':
          _handleCapability(tag);
          break;
        case 'AUTHENTICATE':
          _handleAuthenticate(tag);
          break;
        case 'LOGIN':
          _handleLogin(tag);
          break;
        case 'LSUB':
          _handleLsub(tag);
          break;
        case 'LIST':
          _handleList(tag, args);
          break;
        case 'SELECT':
          _handleSelect(tag, args);
          break;
        case 'EXAMINE':
          _handleExamine(tag, args);
          break;
        case 'STATUS':
          _handleStatus(tag, args);
          break;
        case 'FETCH':
          _handleFetch(tag, args);
          break;
        case 'STORE':
          _handleStore(tag, args);
          break;
        case 'COPY':
          _handleCopy(tag, args);
          break;
        case 'EXPUNGE':
          _handleExpunge(tag);
          break;
        case 'SEARCH':
          _handleSearch(tag, args);
          break;
        case 'CLOSE':
          _handleClose(tag);
          break;
        case 'LOGOUT':
          _handleLogout(tag);
          break;
        case 'NOOP':
          _sendResponse(tag, 'OK NOOP completed');
          break;
        case 'UID':
          _handleUidCommand(tag, args);
          break;
        case 'APPEND':
          _handleAppend(tag, args);
          break;
        default:
          _sendResponse(tag, 'BAD Unknown command: $command');
          break;
      }
    } catch (ex) {
      try {
        _sendResponse(tag, 'BAD Command failed: $ex');
      } catch (_) {
        // Can't send response, connection is closed.
      }
    }
  }

  void _handleCapability(String tag) {
    _writeLine('* CAPABILITY IMAP4rev1 AUTH=PLAIN UIDPLUS');
    _sendResponse(tag, 'OK CAPABILITY completed');
  }

  void _handleLogin(String tag) {
    // Login is not implemented (matches the original C# behaviour).
  }

  void _handleAuthenticate(String tag) {
    // Thunderbird uses AUTHENTICATE PLAIN. Reject and let it fall back to LOGIN.
    _sendResponse(tag, 'NO AUTHENTICATE not supported, use LOGIN');
  }

  void _handleLsub(String tag) {
    if (!_authenticated) {
      _sendResponse(tag, 'NO Not authenticated');
      return;
    }
    for (final folder in _folderToMailbox.keys) {
      _writeLine('* LSUB () "/" "$folder"');
    }
    _sendResponse(tag, 'OK LSUB completed');
  }

  void _handleAppend(String tag, String args) {
    if (!_authenticated) {
      _sendResponse(tag, 'NO Not authenticated');
      return;
    }

    // Parse: APPEND "folder" (\Flags) {size}
    final parts = _splitN(args, 3);
    if (parts.length < 3) {
      _sendResponse(tag, 'BAD Invalid APPEND command');
      return;
    }

    final parsedFolder = _parseImapString(parts[0]);
    if (parsedFolder.isEmpty) {
      _sendResponse(tag, 'BAD Invalid APPEND command');
      return;
    }
    final folderName = parsedFolder[0];
    if (!_folderToMailbox.containsKey(folderName)) {
      _sendResponse(tag, 'NO Folder not found');
      return;
    }

    // Parse size {396}
    final sizeStr = parts[2].replaceAll('{', '').replaceAll('}', '').trim();
    final messageSize = int.tryParse(sizeStr);
    if (messageSize == null) {
      _sendResponse(tag, 'BAD Invalid message size');
      return;
    }

    // Tell client we're ready to receive the message.
    _writeLine('+ Ready for literal data');

    _appendFolder = folderName;
    _appendTag = tag;
    _appendData.clear();
    _appendLiteralRemaining = messageSize;
  }

  void _completeAppend() {
    final messageData = utf8.decode(
      Uint8List.fromList(_appendData),
      allowMalformed: true,
    );
    _appendData.clear();

    final mail = _parseRfc822Message(messageData);
    mail.mailbox = _appendFolder; // Use the folder name string.
    mail.mid = WinLinkMail.generateMID();

    // Add to the mail store via the data broker (replaces MainForm.mailStore.AddMail).
    _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);

    _broker.logInfo(
      '[ImapServer] Email appended to $_appendFolder - Subject: ${mail.subject}',
    );
    _sendResponse(_appendTag, 'OK APPEND completed');
  }

  WinLinkMail _parseRfc822Message(String messageData) {
    final mail = WinLinkMail()
      ..dateTime = DateTime.now()
      ..from = ''
      ..to = ''
      ..cc = ''
      ..subject = ''
      ..body = '';

    final lines = const LineSplitter().convert(messageData);
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
          var from = line.substring(5).trim();
          if (from.contains('<') && from.contains('>')) {
            final start = from.indexOf('<') + 1;
            final end = from.indexOf('>');
            from = from.substring(start, end);
          }
          mail.from = from;
        } else if (lower.startsWith('to:')) {
          mail.to = line.substring(3).trim();
        } else if (lower.startsWith('cc:')) {
          mail.cc = line.substring(3).trim();
        } else if (lower.startsWith('subject:')) {
          mail.subject = line.substring(8).trim();
        } else if (lower.startsWith('date:')) {
          final dateStr = line.substring(5).trim();
          final parsed = DateTime.tryParse(dateStr);
          if (parsed != null) mail.dateTime = parsed;
        }
      } else {
        bodyBuilder.writeln(line);
      }
    }

    mail.body = bodyBuilder.toString().trimRight();
    return mail;
  }

  void _handleList(String tag, String args) {
    if (!_authenticated) {
      _sendResponse(tag, 'NO Not authenticated');
      return;
    }

    final parts = _parseImapString(args);
    if (parts.length < 2) {
      for (final folder in _folderToMailbox.keys) {
        _writeLine('* LIST () "/" "$folder"');
      }
      _sendResponse(tag, 'OK LIST completed');
      return;
    }

    for (final folder in _folderToMailbox.keys) {
      _writeLine('* LIST () "/" "$folder"');
    }
    _sendResponse(tag, 'OK LIST completed');
  }

  void _handleSelect(String tag, String args) {
    if (!_authenticated) {
      _sendResponse(tag, 'NO Not authenticated');
      return;
    }

    final parsed = _parseImapString(args);
    if (parsed.isEmpty) {
      _sendResponse(tag, 'BAD Invalid SELECT command');
      return;
    }
    final folderName = parsed[0];
    final mailboxIndex = _folderToMailbox[folderName];
    if (mailboxIndex == null) {
      _sendResponse(tag, 'NO Folder not found');
      return;
    }

    _selectedMailbox = mailboxIndex;
    _initializeMailboxState();

    final mails = _getMailsInMailbox(mailboxIndex);

    // Generate a consistent UIDVALIDITY based on the mailbox itself.
    final uidValidity = mailboxIndex + 1000;

    _writeLine('* ${mails.length} EXISTS');
    _writeLine('* ${mails.length} RECENT');
    if (mails.isNotEmpty) _writeLine('* OK [UNSEEN 1]');
    _writeLine('* OK [UIDVALIDITY $uidValidity]');
    _writeLine('* OK [UIDNEXT $_uidNext]');
    _writeLine('* FLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)');
    _writeLine(
      '* OK [PERMANENTFLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)]',
    );

    _sendResponse(tag, 'OK [READ-WRITE] SELECT completed');
  }

  void _handleExamine(String tag, String args) {
    // Same as SELECT but read-only.
    _handleSelect(tag, args);
  }

  void _handleStatus(String tag, String args) {
    if (!_authenticated) {
      _sendResponse(tag, 'NO Not authenticated');
      return;
    }

    final parts = _splitN(args, 2);
    if (parts.length < 2) {
      _sendResponse(tag, 'BAD Invalid STATUS command');
      return;
    }

    final parsed = _parseImapString(parts[0]);
    if (parsed.isEmpty) {
      _sendResponse(tag, 'BAD Invalid STATUS command');
      return;
    }
    final folderName = parsed[0];
    final mailboxIndex = _folderToMailbox[folderName];
    if (mailboxIndex == null) {
      _sendResponse(tag, 'NO Folder not found');
      return;
    }

    final mails = _getMailsInMailbox(mailboxIndex);
    _writeLine('* STATUS "$folderName" (MESSAGES ${mails.length} UNSEEN 0)');
    _sendResponse(tag, 'OK STATUS completed');
  }

  void _handleFetch(String tag, String args) {
    if (!_authenticated || _selectedMailbox < 0) {
      _sendResponse(tag, 'NO No mailbox selected');
      return;
    }

    final parts = _splitN(args, 2);
    if (parts.length < 2) {
      _sendResponse(tag, 'BAD Invalid FETCH command');
      return;
    }

    final sequences = _parseSequenceSet(parts[0]);
    final items = parts[1]
        .replaceAll('(', '')
        .replaceAll(')', '')
        .toUpperCase();

    final mails = _getMailsInMailbox(_selectedMailbox);

    for (final seq in sequences) {
      if (seq < 1 || seq > mails.length) continue;

      final index = seq - 1;
      final mail = mails[index];
      final uid = _messageUids[index] ?? 0;

      final fetchItems = <String>[];

      if (items.contains('UID')) fetchItems.add('UID $uid');

      if (items.contains('FLAGS')) {
        final flags = _getFlagsString(index);
        fetchItems.add('FLAGS ($flags)');
      }

      final hasOnlyBasicItems =
          !items.contains('BODY') && !items.contains('RFC822');

      if (hasOnlyBasicItems && fetchItems.isNotEmpty) {
        _writeLine('* $seq FETCH (${fetchItems.join(' ')})');
        continue;
      }

      if (items.contains('INTERNALDATE')) {
        fetchItems.add('INTERNALDATE "${_internalDate(mail.dateTime)}"');
      }

      if (items.contains('RFC822.SIZE') || items.contains('BODYSTRUCTURE')) {
        final fullMessage = _buildRfc822Message(mail);
        fetchItems.add('RFC822.SIZE ${utf8.encode(fullMessage).length}');
      }

      if (items.contains('BODY.PEEK[HEADER]') ||
          items.contains('BODY[HEADER]')) {
        final header = _buildRfc822Header(mail);
        fetchItems.add('BODY[HEADER] {${utf8.encode(header).length}}');
        _writeLine('${fetchItems.join(' ')})');
        _writeLine(header);
        continue;
      }

      if (!hasOnlyBasicItems && items.contains('BODY.PEEK[HEADER')) {
        final header = _buildRfc822Header(mail);
        final headerSize = utf8.encode(header).length;

        if (items.contains('RFC822.SIZE')) {
          final fullMessage = _buildRfc822Message(mail);
          fetchItems.add('RFC822.SIZE ${utf8.encode(fullMessage).length}');
        }

        fetchItems.add(
          'BODY[HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID)] {$headerSize}',
        );

        _writeLine('* $seq FETCH (${fetchItems.join(' ')})');
        _write(header); // Literal data.
        _writeLine(''); // CRLF after literal.
        continue;
      }

      if (items.contains('BODY[]') || items.contains('RFC822')) {
        final fullMessage = _buildRfc822Message(mail);
        fetchItems.add('BODY[] {${utf8.encode(fullMessage).length}}');
        _writeLine('${fetchItems.join(' ')})');
        _writeLine(fullMessage);
        continue;
      }

      _writeLine('${fetchItems.join(' ')})');
    }

    _sendResponse(tag, 'OK FETCH completed');
  }

  void _handleStore(String tag, String args) {
    if (!_authenticated || _selectedMailbox < 0) {
      _sendResponse(tag, 'NO No mailbox selected');
      return;
    }

    final parts = _splitN(args, 3);
    if (parts.length < 3) {
      _sendResponse(tag, 'BAD Invalid STORE command');
      return;
    }

    final sequences = _parseSequenceSet(parts[0]);
    final operation = parts[1].toUpperCase();
    final flagsStr = parts[2].replaceAll('(', '').replaceAll(')', '');

    final isAdd = operation.contains('+');
    final isRemove = operation.contains('-');

    for (final seq in sequences) {
      final mails = _getMailsInMailbox(_selectedMailbox);
      if (seq < 1 || seq > mails.length) continue;

      final index = seq - 1;
      final flags = _messageFlags.putIfAbsent(index, () => <String>{});

      if (isAdd) {
        for (final flag in flagsStr.split(' ')) {
          flags.add(flag.trim());
        }
      } else if (isRemove) {
        for (final flag in flagsStr.split(' ')) {
          flags.remove(flag.trim());
        }
      } else {
        flags.clear();
        for (final flag in flagsStr.split(' ')) {
          flags.add(flag.trim());
        }
      }

      _writeLine('* $seq FETCH (FLAGS (${_getFlagsString(index)}))');
    }

    _sendResponse(tag, 'OK STORE completed');
  }

  void _handleCopy(String tag, String args) {
    if (!_authenticated || _selectedMailbox < 0) {
      _sendResponse(tag, 'NO No mailbox selected');
      return;
    }

    final parts = _splitN(args, 2);
    if (parts.length < 2) {
      _sendResponse(tag, 'BAD Invalid COPY command');
      return;
    }

    final sequences = _parseSequenceSet(parts[0]);
    final parsed = _parseImapString(parts[1]);
    if (parsed.isEmpty) {
      _sendResponse(tag, 'BAD Invalid COPY command');
      return;
    }
    final destFolder = parsed[0];

    if (!_folderToMailbox.containsKey(destFolder)) {
      _sendResponse(tag, 'NO Destination folder not found');
      return;
    }

    final mails = _getMailsInMailbox(_selectedMailbox);

    for (final seq in sequences) {
      if (seq < 1 || seq > mails.length) continue;

      final mail = mails[seq - 1];
      final copy = WinLinkMail()
        ..mid = WinLinkMail.generateMID()
        ..from = mail.from
        ..to = mail.to
        ..cc = mail.cc
        ..subject = mail.subject
        ..body = mail.body
        ..dateTime = mail.dateTime
        ..mailbox = destFolder
        ..attachments = mail.attachments;

      _broker.dispatch(deviceId: 0, name: 'MailAdd', data: copy, store: false);
    }

    _sendResponse(tag, 'OK COPY completed');
  }

  void _handleExpunge(String tag) {
    if (!_authenticated || _selectedMailbox < 0) {
      _sendResponse(tag, 'NO No mailbox selected');
      return;
    }

    final mails = _getMailsInMailbox(_selectedMailbox);
    final toDelete = <int>[];

    for (int i = 0; i < mails.length; i++) {
      if (_messageFlags.containsKey(i) &&
          _messageFlags[i]!.contains('\\Deleted')) {
        toDelete.add(i);
      }
    }

    // Delete in reverse order to maintain indices.
    toDelete.sort((a, b) => b.compareTo(a));
    for (final index in toDelete) {
      final mail = mails[index];
      mail.mailbox = 'Trash'; // Move to Trash.
      _writeLine('* ${index + 1} EXPUNGE');
    }

    for (final index in toDelete) {
      final mail = mails[index];
      _broker.dispatch(
        deviceId: 0,
        name: 'MailUpdate',
        data: mail,
        store: false,
      );
    }
    _initializeMailboxState();

    _sendResponse(tag, 'OK EXPUNGE completed');
  }

  void _handleSearch(String tag, String args) {
    if (!_authenticated || _selectedMailbox < 0) {
      _sendResponse(tag, 'NO No mailbox selected');
      return;
    }

    final mails = _getMailsInMailbox(_selectedMailbox);
    final results = <int>[];

    if (args.toUpperCase().contains('ALL')) {
      for (int i = 0; i < mails.length; i++) {
        results.add(i + 1);
      }
    }

    final sb = StringBuffer('* SEARCH');
    for (final seq in results) {
      sb.write(' $seq');
    }
    _writeLine(sb.toString());

    _sendResponse(tag, 'OK SEARCH completed');
  }

  void _handleUidCommand(String tag, String args) {
    final parts = _splitN(args, 2);
    if (parts.length < 2) {
      _sendResponse(tag, 'BAD Invalid UID command');
      return;
    }

    final subCommand = parts[0].toUpperCase();
    final subArgs = parts[1];

    final argParts = _splitN(subArgs, 2);
    final uidSet = argParts[0];
    var restOfArgs = argParts.length > 1 ? argParts[1] : '';

    final sequences = _parseUidSet(uidSet);
    final sequenceSet = sequences.join(',');

    if (subCommand == 'FETCH' && restOfArgs.isNotEmpty) {
      final items = restOfArgs
          .replaceAll('(', '')
          .replaceAll(')', '')
          .toUpperCase();
      if (!items.contains('UID')) {
        restOfArgs = '(UID ${restOfArgs.replaceFirst('(', '')}';
      }
    }

    final convertedArgs =
        sequenceSet + (restOfArgs.isEmpty ? '' : ' $restOfArgs');

    switch (subCommand) {
      case 'FETCH':
        _handleFetch(tag, convertedArgs);
        break;
      case 'STORE':
        _handleStore(tag, convertedArgs);
        break;
      case 'SEARCH':
        _handleSearch(tag, convertedArgs);
        break;
      case 'COPY':
        _handleCopy(tag, convertedArgs);
        break;
      default:
        _sendResponse(tag, 'BAD Unknown UID command: $subCommand');
        break;
    }
  }

  List<int> _parseUidSet(String uidSet) {
    final sequences = <int>[];

    for (final part in uidSet.split(',')) {
      if (part.contains(':')) {
        final range = part.split(':');
        final startUid = int.tryParse(range[0]);
        if (startUid == null) continue;

        final endUid = range[1] == '*'
            ? 0xFFFFFFFF
            : (int.tryParse(range[1]) ?? 0);

        for (int i = 0; i < _messageUids.length; i++) {
          final uid = _messageUids[i] ?? 0;
          if (uid >= startUid && uid <= endUid) {
            sequences.add(i + 1);
          }
        }
      } else {
        if (part == '*') {
          if (_messageUids.isNotEmpty) sequences.add(_messageUids.length);
        } else {
          final uid = int.tryParse(part);
          if (uid == null) continue;
          for (int i = 0; i < _messageUids.length; i++) {
            if (_messageUids[i] == uid) {
              sequences.add(i + 1);
              break;
            }
          }
        }
      }
    }

    final distinct = sequences.toSet().toList()..sort();
    return distinct;
  }

  void _handleClose(String tag) {
    _selectedMailbox = -1;
    _messageUids.clear();
    _messageFlags.clear();
    _sendResponse(tag, 'OK CLOSE completed');
  }

  void _handleLogout(String tag) {
    _writeLine('* BYE HTCommander IMAP Server logging out');
    _sendResponse(tag, 'OK LOGOUT completed');
    close();
  }

  void _initializeMailboxState() {
    _messageUids.clear();
    _messageFlags.clear();

    final mails = _getMailsInMailbox(_selectedMailbox);
    for (int i = 0; i < mails.length; i++) {
      // Generate a consistent UID from the email's MID hash.
      final uid = (mails[i].mid ?? '').hashCode.abs();
      _messageUids[i] = uid;
      _messageFlags[i] = <String>{};

      if (uid >= _uidNext) _uidNext = uid + 1;
    }
  }

  List<WinLinkMail> _getMailsInMailbox(int mailboxIndex) {
    // Convert mailbox index to folder name for string comparison.
    final folderName = _mailboxToFolder[mailboxIndex] ?? '';
    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    if (mailStore == null) return <WinLinkMail>[];
    return mailStore
        .getAllMails()
        .where((m) => m.mailbox == folderName)
        .toList();
  }

  String _buildRfc822Header(WinLinkMail mail) {
    final sb = StringBuffer();
    sb.writeln('From: ${mail.from ?? ''}');
    sb.writeln('To: ${mail.to ?? ''}');
    if (mail.cc != null && mail.cc!.isNotEmpty) {
      sb.writeln('Cc: ${mail.cc}');
    }
    sb.writeln('Subject: ${mail.subject ?? ''}');
    sb.writeln('Date: ${_rfc1123Date(mail.dateTime)}');
    sb.writeln('Message-ID: <${mail.mid}@htcommander>');
    sb.writeln('MIME-Version: 1.0');
    sb.writeln('Content-Type: text/plain; charset=utf-8');
    sb.writeln();
    return sb.toString();
  }

  String _buildRfc822Message(WinLinkMail mail) {
    final sb = StringBuffer();
    sb.write(_buildRfc822Header(mail));
    sb.writeln(mail.body ?? '');
    return sb.toString();
  }

  String _getFlagsString(int index) {
    final flags = _messageFlags[index];
    if (flags == null || flags.isEmpty) return '';
    return flags.join(' ');
  }

  List<int> _parseSequenceSet(String sequenceSet) {
    final result = <int>[];

    if (sequenceSet == '*') {
      final mails = _getMailsInMailbox(_selectedMailbox);
      for (int i = 1; i <= mails.length; i++) {
        result.add(i);
      }
      return result;
    }

    for (final part in sequenceSet.split(',')) {
      if (part.contains(':')) {
        final range = part.split(':');
        final start = int.parse(range[0]);
        final end = range[1] == '*'
            ? _getMailsInMailbox(_selectedMailbox).length
            : int.parse(range[1]);
        for (int i = start; i <= end; i++) {
          result.add(i);
        }
      } else {
        result.add(int.parse(part));
      }
    }

    final distinct = result.toSet().toList()..sort();
    return distinct;
  }

  List<String> _parseImapString(String input) {
    final result = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();

    for (int i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ' ' && !inQuotes) {
        if (current.isNotEmpty) {
          result.add(current.toString());
          current.clear();
        }
      } else {
        current.write(c);
      }
    }

    if (current.isNotEmpty) result.add(current.toString());
    return result;
  }

  /// Splits [input] on single spaces into at most [count] parts, keeping the
  /// remainder of the string in the final part (mirrors C# String.Split with a
  /// count limit).
  List<String> _splitN(String input, int count) {
    final result = <String>[];
    int start = 0;
    while (result.length < count - 1) {
      final idx = input.indexOf(' ', start);
      if (idx < 0) break;
      result.add(input.substring(start, idx));
      start = idx + 1;
    }
    result.add(input.substring(start));
    return result;
  }

  String _twoDigit(int value) => value.toString().padLeft(2, '0');

  /// RFC 1123 date format, e.g. "Sun, 06 Nov 1994 08:49:37 GMT".
  String _rfc1123Date(DateTime dt) {
    final u = dt.toUtc();
    return '${_dayNames[u.weekday % 7]}, ${_twoDigit(u.day)} ${_monthNames[u.month - 1]} '
        '${u.year} ${_twoDigit(u.hour)}:${_twoDigit(u.minute)}:${_twoDigit(u.second)} GMT';
  }

  /// IMAP INTERNALDATE format, e.g. "06-Nov-1994 08:49:37 +0000".
  String _internalDate(DateTime dt) {
    final u = dt.toUtc();
    return '${_twoDigit(u.day)}-${_monthNames[u.month - 1]}-${u.year} '
        '${_twoDigit(u.hour)}:${_twoDigit(u.minute)}:${_twoDigit(u.second)} +0000';
  }

  void _writeLine(String line) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode('$line\r\n'));
    } catch (_) {
      close();
    }
  }

  void _write(String text) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode(text));
    } catch (_) {
      close();
    }
  }

  void _sendResponse(String tag, String response) {
    _writeLine('$tag $response');
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
