// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/mime.dart';

import 'winlink_mail.dart';

/// Converts Internet MIME messages to/from Winlink's plain-text mail model.
class MailMime {
  static final _addressPattern = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+$",
  );

  static bool isEmailAddress(String address) =>
      _addressPattern.hasMatch(address);

  static bool isAccountAddress(String address, String account) =>
      address.toUpperCase() == '${account.toUpperCase()}@WINLINK.ORG';

  static String _toWinlinkAddress(String address) {
    if (!isEmailAddress(address)) {
      throw const FormatException('Invalid email address');
    }
    return address.toLowerCase().endsWith('@winlink.org')
        ? address.substring(0, address.indexOf('@')).toUpperCase()
        : address;
  }

  static WinLinkMail decodeSubmission(
    Uint8List bytes, {
    required String account,
    required List<String> recipients,
  }) {
    final message = MimeMessage.parseFromData(bytes);
    final from = message.from;
    if (from == null ||
        from.length != 1 ||
        !isAccountAddress(from.single.email, account)) {
      throw const FormatException(
        'From header must match your Winlink account',
      );
    }
    final to = message.to ?? <MailAddress>[];
    final cc = message.cc ?? <MailAddress>[];
    final visibleRecipients = [
      ...to,
      ...cc,
    ].map((address) => address.email.toLowerCase()).toSet();
    final envelope = recipients.map((address) => address.toLowerCase()).toSet();
    if (envelope.length != visibleRecipients.length ||
        !envelope.containsAll(visibleRecipients) ||
        (message.bcc?.isNotEmpty ?? false)) {
      throw const FormatException(
        'Bcc is not supported; envelope recipients must match To and Cc',
      );
    }
    final subject = message.decodeSubject() ?? '';
    if (subject.contains('\r') ||
        subject.contains('\n') ||
        utf8.encode(subject).length > 252) {
      throw const FormatException('Subject exceeds the Winlink header limit');
    }
    final body = message.decodeTextPlainPart();
    if (body == null && message.decodeTextHtmlPart() != null) {
      throw const FormatException(
        'HTML-only mail is not supported; compose in plain text',
      );
    }
    final attachments = <WinLinkMailAttachement>[];
    for (final part in message.allPartsFlat) {
      final name = part.decodeFileName();
      final disposition = part.getHeaderContentDisposition()?.disposition;
      if (name == null && disposition != ContentDisposition.attachment) {
        continue;
      }
      final data = part.decodeContentBinary();
      if (data == null) {
        throw const FormatException('Cannot decode attachment');
      }
      final filename = name ?? 'attachment.bin';
      if (filename.contains('\r') || filename.contains('\n')) {
        throw const FormatException('Invalid attachment filename');
      }
      attachments.add(WinLinkMailAttachement(name: filename, data: data));
    }
    return WinLinkMail()
      ..mid = WinLinkMail.generateMID()
      ..dateTime = message.decodeDate() ?? DateTime.now()
      ..from = account.toUpperCase()
      ..to = to.map((a) => _toWinlinkAddress(a.email)).join('; ')
      ..cc = cc.map((a) => _toWinlinkAddress(a.email)).join('; ')
      ..subject = subject
      ..body = body ?? ''
      ..attachments = attachments
      ..mailbox = 'Outbox';
  }

  static List<MailAddress> _internetAddresses(String? value) {
    if (value == null || value.trim().isEmpty) return [];
    if (value.contains('\r') || value.contains('\n')) {
      throw const FormatException('Invalid stored mail address');
    }
    final normalized = value
        .replaceAll(RegExp('SMTP:', caseSensitive: false), '')
        .split(';')
        .map((segment) {
          if (segment.contains('@')) return segment;
          return segment
              .split(',')
              .map((address) {
                address = address.trim();
                if (!RegExp(r'^[A-Za-z0-9]+(?:-\d{1,2})?$').hasMatch(address)) {
                  throw const FormatException(
                    'Invalid stored Winlink callsign',
                  );
                }
                return '$address@winlink.org';
              })
              .join(', ');
        })
        .join(', ');
    final addresses = MimeMessage.parseFromText('To: $normalized\r\n\r\n').to;
    if (addresses == null || addresses.isEmpty) {
      throw const FormatException('Invalid stored mail address');
    }
    return addresses.map((a) {
      final email = a.email.contains('@') ? a.email : '${a.email}@winlink.org';
      if (!isEmailAddress(email)) {
        throw const FormatException('Invalid stored mail address');
      }
      return MailAddress(a.personalName, email);
    }).toList();
  }

  static Uint8List encode(WinLinkMail mail) {
    final builder = MessageBuilder()
      ..from = _internetAddresses(mail.from)
      ..to = _internetAddresses(mail.to)
      ..cc = _internetAddresses(mail.cc)
      ..date = mail.dateTime
      ..subject = (mail.subject ?? '').replaceAll(RegExp(r'[\r\n]'), ' ');
    builder.setHeader(
      'Message-ID',
      '<${base64Url.encode(utf8.encode(mail.mid!)).replaceAll('=', '')}@htcommander.local>',
    );
    final attachments = mail.attachments ?? <WinLinkMailAttachement>[];
    if (attachments.isEmpty) {
      builder.text = mail.body ?? '';
    } else {
      builder.setContentType(MediaType.fromText('multipart/mixed'));
      builder.addTextPlain(mail.body ?? '');
      for (final attachment in attachments) {
        builder.addBinary(
          attachment.data,
          MediaType.fromText('application/octet-stream'),
          filename: attachment.name.replaceAll(RegExp(r'[\r\n]'), ' '),
        );
      }
    }
    // Render with ASCII transfer encodings and canonical CRLF for POP octets.
    builder.setRecommendedTextEncoding();
    final text = builder.buildMimeMessage().renderMessage();
    final normalized = text.replaceAll(RegExp(r'\r?\n'), '\r\n');
    return Uint8List.fromList(
      utf8.encode(normalized.endsWith('\r\n') ? normalized : '$normalized\r\n'),
    );
  }
}
