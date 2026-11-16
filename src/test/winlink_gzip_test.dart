/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/winlink/winlink_mail.dart';
import 'package:htcommander/winlink/winlink_proposal.dart';
import 'package:htcommander/winlink/winlink_utils.dart';

Uint8List _joined(List<Uint8List> blocks) {
  final b = BytesBuilder();
  for (final block in blocks) {
    b.add(block);
  }
  return b.toBytes();
}

/// Extracts the compressed payload carried by the STX blocks of a B2F frame.
Uint8List _payload(Uint8List framed) {
  final out = BytesBuilder();
  var ptr = 0;
  while (ptr < framed.length && framed[ptr] != 4) {
    final length = framed[ptr + 1];
    if (framed[ptr] == 2) out.add(framed.sublist(ptr + 2, ptr + 2 + length));
    ptr += 2 + length;
  }
  return out.toBytes();
}

/// Wraps [payload] in B2F framing with a valid outer checksum.
Uint8List _frame(List<int> payload) {
  final data = Uint8List.fromList(payload);
  final b = BytesBuilder()..add(const [1, 4, 0x54, 0, 0x30, 0]);
  for (var i = 0; i < data.length; i += 250) {
    final end = min(i + 250, data.length);
    b
      ..addByte(2)
      ..addByte(end - i)
      ..add(data.sublist(i, end));
  }
  b
    ..addByte(4)
    ..addByte(WinLinkChecksum.computeChecksum(data));
  return b.toBytes();
}

WinLinkMail _mail() => WinLinkMail()
  ..mid = 'GZIPTEST0001'
  ..dateTime = DateTime.utc(2026, 11, 14, 12, 30)
  ..from = 'N0CALL'
  ..to = 'W1AW'
  ..subject = 'GZIP test'
  ..body = 'Hello over GZIP, 73 de N0CALL — ünïcödé ✓\r\n' * 20
  ..attachments = [
    WinLinkMailAttachement(
      name: 'data.bin',
      data: Uint8List.fromList(List<int>.generate(600, (i) => i % 256)),
    ),
  ];

void main() {
  group('GZIP negotiation helpers', () {
    test('detects the G capability only in the SID capability field', () {
      expect(WinlinkGzip.sidSupportsGzip('[Pat-0.16.0-B2FHMG\$]'), isTrue);
      expect(WinlinkGzip.sidSupportsGzip('[WL2K-5.0-B2FWIHJM\$]'), isFalse);
      expect(
        WinlinkGzip.sidSupportsGzip('[RMS Express-1.7.28.0-B2FHM\$]'),
        isFalse,
      );
      expect(WinlinkGzip.sidCapabilities('CMS >'), isNull);
    });

    test('inserts G before the trailing \$ exactly once', () {
      const sid = '[RMS Express-1.7.28.0-B2FHM\$]';
      final withGzip = WinlinkGzip.addGzipFlag(sid);
      expect(withGzip, '[RMS Express-1.7.28.0-B2FHMG\$]');
      expect(WinlinkGzip.addGzipFlag(withGzip), withGzip);
    });

    test('parses FC and FD proposals and rejects other lines', () {
      final fc = WinlinkProposal.parse('FC EM ABCDEF123456 527 123 0')!;
      expect(fc.compression, WinlinkCompressionType.lzhuf);
      expect(fc.mid, 'ABCDEF123456');
      expect(fc.uncompressedSize, 527);
      expect(fc.compressedSize, 123);
      final fd = WinlinkProposal.parse('FD EM ABCDEF123456 527 99 0')!;
      expect(fd.compression, WinlinkCompressionType.gzip);
      expect(WinlinkProposal.parse('FB EM ABCDEF123456 527 99 0'), isNull);
      expect(WinlinkProposal.parse('FD EM SHORT 527 99 0'), isNull);
    });
  });

  group('GZIP message codec', () {
    test('round-trips a message and advertises the payload size', () {
      final mail = _mail();
      final encoded = WinLinkMail.encodeMailToBlocks(
        mail,
        compression: WinlinkCompressionType.gzip,
      );
      final framed = _joined(encoded.blocks!);
      final payload = _payload(framed);

      expect(payload.sublist(0, 3), [0x1F, 0x8B, 0x08]);
      expect(encoded.compressedSize, payload.length);
      expect(encoded.uncompressedSize, WinLinkMail.serializeMail(mail).length);

      final decoded = WinLinkMail.decodeBlocksToEmail(
        framed,
        compression: WinlinkCompressionType.gzip,
        expectedSize: encoded.uncompressedSize,
      );
      expect(decoded.fail, isFalse);
      expect(decoded.dataConsumed, framed.length);
      expect(decoded.mail!.body, mail.body);
      expect(decoded.mail!.attachments!.single.data, mail.attachments![0].data);
    });

    test('LZHUF proposals also advertise the payload size', () {
      final encoded = WinLinkMail.encodeMailToBlocks(_mail());
      final payload = _payload(_joined(encoded.blocks!));
      expect(encoded.compressedSize, payload.length);
    });

    test('decodes GZIP produced by a different encoder', () {
      final serialized = WinLinkMail.serializeMail(_mail());
      final decoded = WinLinkMail.decodeBlocksToEmail(
        _frame(GZipCodec(level: 6).encode(serialized)),
        compression: WinlinkCompressionType.gzip,
        expectedSize: serialized.length,
      );
      expect(decoded.fail, isFalse);
      expect(decoded.mail!.mid, 'GZIPTEST0001');
    });

    test('rejects corrupted GZIP even with a valid outer checksum', () {
      final serialized = WinLinkMail.serializeMail(_mail());
      final gz = GZipCodec().encode(serialized);
      gz[gz.length ~/ 2] ^= 0x55;
      final decoded = WinLinkMail.decodeBlocksToEmail(
        _frame(gz),
        compression: WinlinkCompressionType.gzip,
        expectedSize: serialized.length,
      );
      expect(decoded.fail, isTrue);
      expect(decoded.mail, isNull);
    });

    test('rejects GZIP whose size disagrees with the proposal', () {
      final serialized = WinLinkMail.serializeMail(_mail());
      final framed = _frame(GZipCodec().encode(serialized));
      for (final size in [serialized.length - 1, serialized.length + 1]) {
        final decoded = WinLinkMail.decodeBlocksToEmail(
          framed,
          compression: WinlinkCompressionType.gzip,
          expectedSize: size,
        );
        expect(decoded.fail, isTrue, reason: 'expectedSize $size');
      }
    });

    test('does not accept LZHUF data as GZIP', () {
      final encoded = WinLinkMail.encodeMailToBlocks(_mail());
      final decoded = WinLinkMail.decodeBlocksToEmail(
        _joined(encoded.blocks!),
        compression: WinlinkCompressionType.gzip,
        expectedSize: encoded.uncompressedSize,
      );
      expect(decoded.fail, isTrue);
    });
  });
}
