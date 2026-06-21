/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'winlink_utils.dart';

/// A file attached to a [WinLinkMail].
class WinLinkMailAttachement {
  WinLinkMailAttachement({this.name = '', Uint8List? data})
    : data = data ?? Uint8List(0);

  String name;
  Uint8List data;
}

/// Bit flags applied to a [WinLinkMail].
enum MailFlags {
  unread(1),
  private(2),
  p2p(4);

  const MailFlags(this.value);
  final int value;
}

/// Result of [WinLinkMail.decodeBlocksToEmail].
class WinLinkMailDecodeResult {
  WinLinkMailDecodeResult(this.mail, this.fail, this.dataConsumed);

  final WinLinkMail? mail;
  final bool fail;
  final int dataConsumed;
}

/// Result of [WinLinkMail.encodeMailToBlocks].
class WinLinkMailEncodeResult {
  WinLinkMailEncodeResult(
    this.blocks,
    this.uncompressedSize,
    this.compressedSize,
  );

  final List<Uint8List>? blocks;
  final int uncompressedSize;
  final int compressedSize;
}

/// A Winlink email message.
class WinLinkMail {
  WinLinkMail();

  String? mid;
  DateTime dateTime = DateTime.now();
  String? from;
  String? to;
  String? cc;
  String? subject;
  String? mbo;
  String? body;
  String? tag;
  String? location;
  List<WinLinkMailAttachement>? attachments;
  int flags = 0; // 1 = Unread
  // Mailbox name (Inbox, Outbox, Draft, Sent, Archive, Trash, or custom)
  String mailbox = 'Inbox';

  /// Decodes a sequence of B2F blocks into a [WinLinkMail].
  static WinLinkMailDecodeResult decodeBlocksToEmail(Uint8List? block) {
    if (block == null || block.isEmpty) {
      return WinLinkMailDecodeResult(null, false, 0);
    }

    // Figure out if we have a full mail and the size of the mail
    int cmdlen;
    int payloadLen = 0;
    int ptr = 0;
    bool completeMail = false;
    while (!completeMail && ((ptr + 1) < block.length)) {
      final cmd = block[ptr];
      switch (cmd) {
        case 1:
          cmdlen = block[ptr + 1];
          ptr += (2 + cmdlen);
          break;
        case 2:
          cmdlen = block[ptr + 1];
          payloadLen += cmdlen;
          ptr += (2 + cmdlen);
          break;
        case 4:
          ptr += 2;
          completeMail = true;
          break;
        default:
          return WinLinkMailDecodeResult(null, false, 0);
      }
    }
    if (!completeMail) return WinLinkMailDecodeResult(null, false, 0);

    ptr = 0;
    final payload = Uint8List(payloadLen);
    int payloadPtr = 0;
    completeMail = false;
    while (!completeMail && ((ptr + 1) < block.length)) {
      final cmd = block[ptr];
      switch (cmd) {
        case 1:
          cmdlen = block[ptr + 1];
          ptr += (2 + cmdlen);
          break;
        case 2:
          cmdlen = block[ptr + 1];
          payload.setRange(payloadPtr, payloadPtr + cmdlen, block, ptr + 2);
          payloadPtr += cmdlen;
          ptr += (2 + cmdlen);
          break;
        case 4:
          cmdlen = block[ptr + 1];
          if (WinLinkChecksum.computeChecksum(payload) != cmdlen) {
            return WinLinkMailDecodeResult(null, true, 0);
          }
          ptr += 2;
          completeMail = true;
          break;
      }
    }

    // Decompress the mail
    final expectedLength =
        payload[2] +
        (payload[3] << 8) +
        (payload[4] << 16) +
        (payload[5] << 24);
    WinlinkDecodeResult? decoded;
    try {
      decoded = WinlinkCompression.decode(
        payload,
        checkCRC: true,
        expectedSize: expectedLength,
      );
    } catch (_) {
      decoded = null;
    }
    if (decoded == null || decoded.count != expectedLength) {
      return WinLinkMailDecodeResult(null, true, 0);
    }

    // Decode the mail
    final mail = deserializeMail(decoded.data);
    if (mail == null) return WinLinkMailDecodeResult(null, true, 0);
    return WinLinkMailDecodeResult(mail, false, ptr);
  }

  /// Encodes [mail] into a list of 128-byte B2F blocks.
  static WinLinkMailEncodeResult encodeMailToBlocks(WinLinkMail mail) {
    final uncompressedMail = serializeMail(mail);
    final uncompressedSize = uncompressedMail.length;
    final payloadBuf = WinlinkCompression.encode(
      uncompressedMail,
      prependCRC: true,
    );
    final subjectBuf = utf8.encode(mail.subject ?? '');
    final blocks = <Uint8List>[];

    // Encode the binary header
    final memoryStream = BytesBuilder();
    memoryStream.addByte(0x01);
    memoryStream.addByte((subjectBuf.length + 3) & 0xFF);
    memoryStream.add(subjectBuf);
    memoryStream.addByte(0x00);
    memoryStream.addByte(0x30); // ASCII '0' in HEX.
    memoryStream.addByte(0x00);

    int payloadPtr = 0;
    while (payloadPtr < payloadBuf.length) {
      final blockSize = min(250, payloadBuf.length - payloadPtr);
      memoryStream.addByte(0x02);
      memoryStream.addByte(blockSize & 0xFF);
      memoryStream.add(payloadBuf.sublist(payloadPtr, payloadPtr + blockSize));
      payloadPtr += blockSize;
    }

    memoryStream.addByte(0x04);
    memoryStream.addByte(WinLinkChecksum.computeChecksum(payloadBuf));

    final output = memoryStream.toBytes();
    final compressedSize = output.length;

    // Break the output into 128 byte blocks
    int outputPtr = 0;
    while (outputPtr < output.length) {
      final blockSize = min(128, output.length - outputPtr);
      blocks.add(
        Uint8List.sublistView(output, outputPtr, outputPtr + blockSize),
      );
      outputPtr += blockSize;
    }

    return WinLinkMailEncodeResult(blocks, uncompressedSize, compressedSize);
  }

  static Uint8List serializeMail(WinLinkMail mail) {
    final memoryStream = BytesBuilder();
    final bodyData = utf8.encode(mail.body ?? '');
    final between = Uint8List.fromList(const [0x0D, 0x0A]);
    final end = Uint8List.fromList(const [0x00]);

    final sb = StringBuffer();
    sb.write('MID: ${mail.mid}\r\n');
    sb.write('Date: ${_formatDate(mail.dateTime)}\r\n');
    if ((mail.flags & MailFlags.private.value) != 0) {
      sb.write('Type: Private\r\n');
    }
    if (_notEmpty(mail.from)) sb.write('From: ${mail.from}\r\n');
    if (_notEmpty(mail.to)) sb.write('To: ${mail.to}\r\n');
    if (_notEmpty(mail.cc)) sb.write('Cc: ${mail.cc}\r\n');
    if (_notEmpty(mail.subject)) sb.write('Subject: ${mail.subject}\r\n');
    if (_notEmpty(mail.mbo)) sb.write('Mbo: ${mail.mbo}\r\n');
    if ((mail.flags & MailFlags.p2p.value) != 0) sb.write('X-P2P: True\r\n');
    if (_notEmpty(mail.location)) sb.write('X-Location: ${mail.location}\r\n');
    if (_notEmpty(mail.body)) sb.write('Body: ${bodyData.length}\r\n');
    if (mail.attachments != null) {
      for (final attachement in mail.attachments!) {
        sb.write('File: ${attachement.data.length} ${attachement.name}\r\n');
      }
    }
    sb.write('\r\n');

    // Assemble the binary email
    memoryStream.add(utf8.encode(sb.toString()));
    memoryStream.add(bodyData);
    memoryStream.add(between);
    if (mail.attachments != null) {
      for (final attachement in mail.attachments!) {
        memoryStream.add(attachement.data);
        memoryStream.add(between);
      }
    }
    memoryStream.add(end);
    return memoryStream.toBytes();
  }

  static int findFirstDoubleNewline(Uint8List? data) {
    // Not enough data to contain \r\n\r\n
    if (data == null || data.length < 4) return -1;
    for (int i = 0; i <= data.length - 4; i++) {
      // Found \r\n\r\n at index i
      if (data[i] == 0x0D &&
          data[i + 1] == 0x0A &&
          data[i + 2] == 0x0D &&
          data[i + 3] == 0x0A) {
        return i;
      }
    }
    return -1; // \r\n\r\n not found
  }

  // https://winlink.org/sites/default/files/downloads/winlink_data_flow_and_data_packaging.pdf
  static WinLinkMail? deserializeMail(Uint8List databuf) {
    final currentMail = WinLinkMail();

    // Pull the header out of the data
    final headerLimit = findFirstDoubleNewline(databuf);
    if (headerLimit < 0) return null;
    final header = utf8.decode(
      databuf.sublist(0, headerLimit),
      allowMalformed: true,
    );

    // Decode the header
    bool done = false;
    int bodyLength = -1;
    int ptr = headerLimit + 4;
    final lines = header.replaceAll('\r\n', '\n').split(RegExp(r'[\n\r]'));
    for (final line in lines) {
      if (done) continue;
      final i = line.indexOf(':');
      if (i > 0) {
        final key = line.substring(0, i).toLowerCase().trim();
        final value = line.substring(i + 1).trim();

        switch (key) {
          case '':
            done = true;
            break;
          case 'mid':
            currentMail.mid = value;
            break;
          case 'date':
            currentMail.dateTime = _parseDate(value);
            break;
          case 'type':
            if (value.toLowerCase() == 'private') {
              currentMail.flags |= MailFlags.private.value;
            }
            break;
          case 'to':
            currentMail.to = value;
            break;
          case 'cc':
            currentMail.cc = value;
            break;
          case 'from':
            currentMail.from = value;
            break;
          case 'subject':
            currentMail.subject = value;
            break;
          case 'mbo':
            currentMail.mbo = value;
            break;
          case 'body':
            bodyLength = int.parse(value);
            break;
          case 'file':
            final j = value.indexOf(' ');
            if (j > 0) {
              final attachement = WinLinkMailAttachement(
                name: value.substring(j + 1).trim(),
                data: Uint8List(
                  int.parse(value.substring(0, j).toLowerCase().trim()),
                ),
              );
              currentMail.attachments ??= <WinLinkMailAttachement>[];
              currentMail.attachments!.add(attachement);
            }
            break;
          case 'x-location':
            currentMail.location = value;
            break;
          case 'x-p2p':
            if (value.toLowerCase() == 'true') {
              currentMail.flags |= MailFlags.p2p.value;
            }
            break;
        }
      }
    }

    // Pull the body out of the data
    if (bodyLength > 0) {
      currentMail.body = utf8.decode(
        databuf.sublist(ptr, ptr + bodyLength),
        allowMalformed: true,
      );
      ptr += (bodyLength + 2);
    }

    // Pull the attachments out of the data
    if (currentMail.attachments != null) {
      for (final attachment in currentMail.attachments!) {
        attachment.data.setRange(0, attachment.data.length, databuf, ptr);
        ptr += (attachment.data.length + 2);
      }
    }

    return currentMail;
  }

  // Serialize a list of mails to a plain text format
  static String serialize(List<WinLinkMail> mails) {
    final sb = StringBuffer();
    for (final mail in mails) {
      sb.writeln('Mail:');
      sb.writeln('MID=${mail.mid}');
      sb.writeln('Time=${mail.dateTime.toIso8601String()}');
      if (_notEmpty(mail.from)) sb.writeln('From=${mail.from}');
      if (_notEmpty(mail.to)) sb.writeln('To=${mail.to}');
      if (_notEmpty(mail.cc)) sb.writeln('Cc=${mail.cc}');
      sb.writeln('Subject=${mail.subject}');
      if (_notEmpty(mail.mbo)) sb.writeln('Mbo=${mail.mbo}');
      sb.writeln('Body=${_escapeString(mail.body)}');
      if (_notEmpty(mail.tag)) sb.writeln('Tag=${mail.tag}');
      if (_notEmpty(mail.location)) sb.writeln('Tag=${mail.location}');
      if (mail.flags != 0) sb.writeln('Flags=${mail.flags}');
      if (_notEmpty(mail.mailbox)) sb.writeln('Mailbox=${mail.mailbox}');
      if (mail.attachments != null) {
        for (final attachement in mail.attachments!) {
          sb.writeln('File=${attachement.name}');
          sb.writeln('FileData=${base64.encode(attachement.data)}');
        }
      }
      sb.writeln(); // Separate entries with a blank line
    }
    return sb.toString();
  }

  // Deserialize a plain text format into a list of WinLinkMail objects
  static List<WinLinkMail> deserialize(String data) {
    final mails = <WinLinkMail>[];
    WinLinkMail? currentMail;

    String? fileName;
    final lines = data
        .split(RegExp(r'[\n\r]'))
        .where((l) => l.isNotEmpty)
        .toList();
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine == 'Mail:') {
        if (currentMail != null) {
          if (!_notEmpty(currentMail.mid)) currentMail.mid = generateMID();
          mails.add(currentMail);
        }
        currentMail = WinLinkMail();
      } else if (currentMail != null) {
        final i = trimmedLine.indexOf('=');
        if (i > 0) {
          final key = trimmedLine.substring(0, i).trim();
          final value = trimmedLine.substring(i + 1).trim();

          switch (key) {
            case 'MID':
              currentMail.mid = value;
              break;
            case 'Time':
              currentMail.dateTime = DateTime.parse(value);
              break;
            case 'From':
              currentMail.from = value;
              break;
            case 'To':
              currentMail.to = value;
              break;
            case 'Cc':
              currentMail.cc = value;
              break;
            case 'Subject':
              currentMail.subject = value;
              break;
            case 'Mbo':
              currentMail.mbo = value;
              break;
            case 'Body':
              currentMail.body = _unescapeString(value);
              break;
            case 'Tag':
              currentMail.tag = value;
              break;
            case 'Location':
              currentMail.location = value;
              break;
            case 'Flags':
              currentMail.flags = int.parse(value);
              break;
            case 'Mailbox':
              // Support both old integer format and new string format
              final mailboxIndex = int.tryParse(value);
              if (mailboxIndex != null) {
                // Convert old integer to string name
                const defaultMailboxes = [
                  'Inbox',
                  'Outbox',
                  'Draft',
                  'Sent',
                  'Archive',
                  'Trash',
                ];
                currentMail.mailbox =
                    (mailboxIndex >= 0 &&
                        mailboxIndex < defaultMailboxes.length)
                    ? defaultMailboxes[mailboxIndex]
                    : 'Inbox';
              } else {
                currentMail.mailbox = value;
              }
              break;
            case 'File':
              fileName = value;
              break;
            case 'FileData':
              if (_notEmpty(fileName)) {
                currentMail.attachments ??= <WinLinkMailAttachement>[];
                final attachement = WinLinkMailAttachement(
                  name: fileName!,
                  data: base64.decode(value),
                );
                currentMail.attachments!.add(attachement);
                fileName = null;
              }
              break;
          }
        }
      }
    }

    if (currentMail != null) {
      if (!_notEmpty(currentMail.mid)) currentMail.mid = generateMID();
      mails.add(currentMail);
    }

    return mails;
  }

  static const String _fieldSeparator = ';';
  static const String _recordSeparator = '\n';
  static const String _escapeCharacter = '\\';

  static String? _escapeString(String? data) {
    if (data == null || data.isEmpty) return data;

    final sb = StringBuffer();
    for (final c in data.split('')) {
      if (c == _fieldSeparator ||
          c == _recordSeparator ||
          c == _escapeCharacter) {
        sb.write(_escapeCharacter);
        sb.write(c);
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  static String? _unescapeString(String? escapedData) {
    if (escapedData == null || escapedData.isEmpty) return escapedData;

    final sb = StringBuffer();
    bool escaping = false;
    for (final c in escapedData.split('')) {
      if (escaping) {
        sb.write(c); // Append the escaped character directly
        escaping = false;
      } else if (c == _escapeCharacter) {
        escaping = true; // Next character is escaped
      } else {
        sb.write(c); // Normal character
      }
    }
    return sb.toString();
  }

  static String generateMID() {
    final rng = Random.secure();
    final result = StringBuffer();
    for (int i = 0; i < 12; i++) {
      // Map byte to alphanumeric characters (0-9, A-Z)
      final value = rng.nextInt(256) % 36; // 36 = 10 digits + 26 letters
      if (value < 10) {
        result.writeCharCode(0x30 + value); // Digits 0-9
      } else {
        result.writeCharCode(0x41 + (value - 10)); // Uppercase letters A-Z
      }
    }
    return result.toString();
  }

  static bool isMailForStation(
    String? callsign,
    String? to,
    String? cc, {
    required void Function(bool others) onOthers,
  }) {
    final r1 = _isMailForStationEx(callsign, to);
    final r2 = _isMailForStationEx(callsign, cc);
    onOthers(r1.others || r2.others);
    return r1.match || r2.match;
  }

  static ({bool match, bool others}) _isMailForStationEx(
    String? callsign,
    String? t,
  ) {
    bool others = false;
    bool response = false;
    if (callsign == null || callsign.isEmpty || t == null || t.isEmpty) {
      return (match: false, others: false);
    }
    final s = t.split(';');
    for (final s2 in s) {
      if (s2.isEmpty) continue;
      bool match = false;
      final i = s2.indexOf('@');
      if (i == -1) {
        // Callsign
        if (callsign.toUpperCase() == s2.toUpperCase()) match = true;
        if (s2.toUpperCase().startsWith('${callsign.toUpperCase()}-')) {
          match = true;
        }
      } else {
        // Email
        final key = s2.substring(0, i).toUpperCase();
        final value = s2.substring(i + 1).toUpperCase();
        if ((value == 'WINLINK.ORG' && callsign.toUpperCase() == key) ||
            (key.toUpperCase().startsWith('$callsign-'))) {
          match = true;
        }
      }
      if (match) {
        response = true;
      } else {
        others = true;
      }
    }
    return (match: response, others: others);
  }

  static bool _notEmpty(String? s) => s != null && s.isNotEmpty;

  static String _formatDate(DateTime d) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}/${p2(d.month)}/${p2(d.day)} '
        '${p2(d.hour)}:${p2(d.minute)}';
  }

  static DateTime _parseDate(String s) {
    final m = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{1,2})$',
    ).firstMatch(s.trim());
    if (m == null) return DateTime.now();
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
