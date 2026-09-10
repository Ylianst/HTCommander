/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/winlink/winlink_mail.dart';

/// Builds an uncompressed B2F message body (the byte layout consumed by
/// [WinLinkMail.deserializeMail]) from raw header lines and a UTF-8 body.
Uint8List _buildB2fMessage(List<String> headerLines, String body) {
  final bodyBytes = utf8.encode(body);
  final header = StringBuffer();
  for (final line in headerLines) {
    header.write('$line\r\n');
  }
  header.write('Body: ${bodyBytes.length}\r\n');
  header.write('\r\n');
  final out = BytesBuilder();
  out.add(utf8.encode(header.toString()));
  out.add(bodyBytes);
  out.add(const [0x0D, 0x0A]); // trailing CRLF after body
  out.add(const [0x00]); // end marker
  return out.toBytes();
}

void main() {
  group('WinLinkMail persistence round-trip', () {
    test('preserves a multiline body with blank lines', () {
      final mail = WinLinkMail()
        ..mid = 'ABC123DEF456'
        ..from = 'KK7VZT'
        ..to = 'W1AW'
        ..subject = 'Multiline'
        ..body = 'line one\nline two\n\nline four'
        ..mailbox = 'Inbox';

      final restored = WinLinkMail.deserialize(WinLinkMail.serialize([mail]));

      expect(restored, hasLength(1));
      expect(restored.first.body, 'line one\nline two\n\nline four');
      expect(restored.first.subject, 'Multiline');
      expect(restored.first.mid, 'ABC123DEF456');
    });

    test('preserves bodies containing backslashes and semicolons', () {
      final mail = WinLinkMail()
        ..mid = 'MID000000001'
        ..body = r'path C:\temp\file; value=1; done\'
        ..mailbox = 'Sent';

      final restored = WinLinkMail.deserialize(WinLinkMail.serialize([mail]));

      expect(restored.first.body, r'path C:\temp\file; value=1; done\');
    });

    test('round-trips multiple messages and attachments', () {
      final mailA = WinLinkMail()
        ..mid = 'MIDAAAAAAAA1'
        ..to = 'W1AW;N0CALL'
        ..subject = 'First'
        ..body = 'first body'
        ..attachments = [
          WinLinkMailAttachement(
            name: 'note.txt',
            data: Uint8List.fromList(utf8.encode('attachment payload')),
          ),
        ];
      final mailB = WinLinkMail()
        ..mid = 'MIDBBBBBBBB2'
        ..subject = 'Second'
        ..body = 'line1\nline2';

      final restored = WinLinkMail.deserialize(
        WinLinkMail.serialize([mailA, mailB]),
      );

      expect(restored, hasLength(2));
      expect(restored[0].to, 'W1AW;N0CALL');
      expect(restored[0].attachments, hasLength(1));
      expect(
        utf8.decode(restored[0].attachments!.first.data),
        'attachment payload',
      );
      expect(restored[1].body, 'line1\nline2');
    });
  });

  group('WinLinkMail legacy text recovery', () {
    test('recovers a multiline body stored in the old escaped format', () {
      // Old serialize() escaped a body newline as a backslash followed by a
      // real newline, then reload kept only the first physical line. The
      // recovery parser must rebuild the full body.
      const legacy =
          'Mail:\n'
          'MID=LEGACY000001\n'
          'Time=2025-02-22T03:30:00.000\n'
          'From=KK7VZT\n'
          'To=W1AW\n'
          'Subject=Recovered\n'
          'Body=line1\\\nline2\\\n\\\nline4\n'
          'Mailbox=Inbox\n'
          '\n';

      final restored = WinLinkMail.deserialize(legacy);

      expect(restored, hasLength(1));
      expect(restored.first.body, 'line1\nline2\n\nline4');
      expect(restored.first.subject, 'Recovered');
      expect(restored.first.mailbox, 'Inbox');
    });

    test('recovers a legacy single-line body', () {
      const legacy =
          'Mail:\n'
          'MID=LEGACY000002\n'
          'Time=2025-02-22T03:30:00.000\n'
          'Subject=Simple\n'
          'Body=just one line\n'
          '\n';

      final restored = WinLinkMail.deserialize(legacy);

      expect(restored.first.body, 'just one line');
    });
  });

  group('WinLinkMail B2F recipient parsing', () {
    test('accumulates repeated To and Cc headers', () {
      final data = _buildB2fMessage([
        'MID: DEADBEEF0001',
        'Date: 2025/02/22 03:30',
        'From: KK7VZT',
        'To: W1AW',
        'To: N0CALL',
        'Cc: K7ABC',
        'Cc: K7XYZ',
        'Subject: Broadcast',
      ], 'hello');

      final mail = WinLinkMail.deserializeMail(data);

      expect(mail, isNotNull);
      expect(mail!.to, 'W1AW;N0CALL');
      expect(mail.cc, 'K7ABC;K7XYZ');
      expect(mail.body, 'hello');
    });

    test('keeps a single recipient unchanged', () {
      final data = _buildB2fMessage([
        'MID: DEADBEEF0002',
        'Date: 2025/02/22 03:30',
        'From: KK7VZT',
        'To: W1AW',
        'Subject: Direct',
      ], 'hi');

      final mail = WinLinkMail.deserializeMail(data);

      expect(mail!.to, 'W1AW');
      expect(mail.cc, isNull);
    });
  });
}
