/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/mail_store.dart';
import 'package:htcommander/winlink/winlink_client.dart';
import 'package:htcommander/winlink/winlink_mail.dart';
import 'package:htcommander/winlink/winlink_proposal.dart';

int _commandCount(String transcript, String command) =>
    RegExp('(?:^|\\r)$command\\r').allMatches(transcript).length;

String _checksumHex(String value) {
  final sum = ascii.encode(value).fold<int>(0, (total, byte) => total + byte);
  return ((-sum) & 0xff).toRadixString(16).padLeft(2, '0').toUpperCase();
}

Future<void> _waitFor(
  bool Function() predicate,
  String Function() failureMessage,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(predicate(), isTrue, reason: failureMessage());
}

/// A fake Winlink server end of a client TCP session.
class _Peer {
  _Peer._(this.server, this.socket) {
    socket.listen(raw.add);
  }

  final ServerSocket server;
  final Socket socket;
  final BytesBuilder raw = BytesBuilder();

  /// Everything received so far; latin1 keeps binary bytes one-to-one.
  String get text => latin1.decode(raw.toBytes());

  static Future<_Peer> connect(WinlinkClient client) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<Socket>();
    server.listen(accepted.complete);
    expect(
      await client.connectTcp(
        InternetAddress.loopbackIPv4.address,
        server.port,
      ),
      isTrue,
    );
    return _Peer._(server, await accepted.future);
  }

  Future<void> send(String text) => sendBytes(latin1.encode(text));

  Future<void> sendBytes(List<int> data) async {
    socket.add(data);
    await socket.flush();
  }

  Future<void> close() async {
    socket.destroy();
    await server.close();
  }
}

/// Registers an in-memory mail store holding one outbound message.
MailStore _storeWithOutboxMail(String mid) {
  final store = MailStore()
    ..addMail(
      WinLinkMail()
        ..mid = mid
        ..from = 'N0CALL'
        ..to = 'W1AW'
        ..subject = 'Outbound'
        ..body = 'Outbound body, ' * 30
        ..mailbox = 'Outbox',
    );
  DataBroker.addDataHandler('MailStore', store);
  return store;
}

/// Total size of the STX payload bytes in a B2F frame.
int _framedPayloadLength(Uint8List framed) {
  var ptr = 0;
  var length = 0;
  while (ptr < framed.length && framed[ptr] != 4) {
    if (framed[ptr] == 2) length += framed[ptr + 1];
    ptr += 2 + framed[ptr + 1];
  }
  return length;
}

void main() {
  test('a failed sync keeps its error but clears the busy status', () {
    final broker = DataBrokerClient();
    final client = WinlinkClient();
    try {
      broker.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: {
          'RadioId': 5,
          'Station': StationInfo(callsign: 'KG4MRA-10'),
        },
        store: false,
      );
      // Stored, so a Mail tab built afterwards still shows the error and no
      // stale "in progress" status line.
      expect(broker.getValueDynamic(1, 'WinlinkLastError'), isNotEmpty);
      expect(broker.getValueDynamic(1, 'WinlinkStateMessage'), isNull);

      broker.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: {'Server': ''},
        store: false,
      );
      expect(broker.getValueDynamic(1, 'WinlinkLastError'), isNull);
    } finally {
      client.dispose();
      broker.dispose();
      DataBroker.clearDevice(1);
    }
  });

  test('waits for more proposals or FQ after receiving mail', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final acceptedSocket = Completer<Socket>();
    server.listen(acceptedSocket.complete);

    final states = <String>[];
    final broker = DataBrokerClient();
    broker.subscribe(
      deviceId: 1,
      name: 'WinlinkConnectionState',
      callback: (_, _, data) => states.add(data! as String),
    );

    final client = WinlinkClient();
    Socket? peer;
    try {
      expect(
        await client.connectTcp(
          InternetAddress.loopbackIPv4.address,
          server.port,
        ),
        isTrue,
      );
      peer = await acceptedSocket.future;

      var transcript = '';
      peer.listen((data) => transcript += utf8.decode(data));
      peer.add(utf8.encode('CMS >\r'));
      await peer.flush();
      await _waitFor(
        () => _commandCount(transcript, 'FF') == 1,
        () => 'Initial FF not received: $transcript',
      );

      final mail = WinLinkMail()
        ..mid = 'ABCDEF123456'
        ..from = 'SENDER'
        ..to = 'RECIPIENT'
        ..subject = 'Protocol close test'
        ..body = 'Test message';
      final encoded = WinLinkMail.encodeMailToBlocks(mail);
      final proposal =
          'FC EM ${mail.mid} ${encoded.uncompressedSize} ${encoded.compressedSize} 0\r';
      peer.add(
        utf8.encode(
          '$proposal'
          'F> ${_checksumHex(proposal)}\r',
        ),
      );
      await peer.flush();
      await _waitFor(
        () => transcript.contains('FS Y\r'),
        () => 'Proposal was not accepted: $transcript',
      );

      for (final block in encoded.blocks!) {
        peer.add(block);
      }
      await peer.flush();
      await _waitFor(
        () => _commandCount(transcript, 'FF') == 2,
        () => 'Completion FF not received: $transcript',
      );

      expect(states, isNot(contains('DISCONNECTED')));

      final nextMail = WinLinkMail()
        ..mid = '654321FEDCBA'
        ..from = 'SENDER'
        ..to = 'RECIPIENT'
        ..subject = 'Second batch'
        ..body = 'Another test message';
      final nextEncoded = WinLinkMail.encodeMailToBlocks(nextMail);
      final nextProposal =
          'FC EM ${nextMail.mid} ${nextEncoded.uncompressedSize} ${nextEncoded.compressedSize} 0\r';
      peer.add(
        utf8.encode(
          '$nextProposal'
          'F> ${_checksumHex(nextProposal)}\r',
        ),
      );
      await peer.flush();
      await _waitFor(
        () => _commandCount(transcript, 'FS Y') == 2,
        () => 'Additional proposal was not accepted: $transcript',
      );
      expect(states, isNot(contains('DISCONNECTED')));

      for (final block in nextEncoded.blocks!) {
        peer.add(block);
      }
      await peer.flush();
      await _waitFor(
        () => _commandCount(transcript, 'FF') == 3,
        () => 'Second completion FF not received: $transcript',
      );

      peer.add(utf8.encode('FQ\r'));
      await peer.flush();
      await _waitFor(
        () => states.contains('DISCONNECTED'),
        () => 'FQ did not close the session; states: $states',
      );
    } finally {
      client.dispose();
      broker.dispose();
      peer?.destroy();
      await server.close();
    }
  });

  group('GZIP negotiation', () {
    const mid = 'OUTBOX000001';

    tearDown(() {
      DataBroker.dispatch(deviceId: 0, name: WinlinkGzip.settingName, data: 1);
      DataBroker.clearDevice(1);
    });

    test('keeps the standard SID and LZHUF with a non-GZIP server', () async {
      final store = _storeWithOutboxMail(mid);
      final client = WinlinkClient();
      final peer = await _Peer.connect(client);
      try {
        await peer.send('[WL2K-5.0-B2FWIHJM\$]\rCMS >\r');
        await _waitFor(
          () => peer.text.contains('F> '),
          () => 'No proposals received: ${peer.text}',
        );
        expect(peer.text, startsWith('[RMS Express-1.7.28.0-B2FHM\$]\r'));
        expect(peer.text, contains('FC EM $mid '));
        expect(peer.text, isNot(contains('FD ')));
      } finally {
        client.dispose();
        store.dispose();
        await peer.close();
      }
    });

    test('exchanges GZIP mail with a server that advertises it', () async {
      final store = _storeWithOutboxMail(mid);
      final received = <WinLinkMail>[];
      final broker = DataBrokerClient()
        ..subscribe(
          deviceId: 0,
          name: 'MailAdd',
          callback: (_, _, data) => received.add(data! as WinLinkMail),
        );
      final client = WinlinkClient();
      final peer = await _Peer.connect(client);
      try {
        await peer.send('[Pat-0.16.0-B2FHMG\$]\rCMS >\r');
        await _waitFor(
          () => peer.text.contains('F> '),
          () => 'No proposals received: ${peer.text}',
        );
        expect(peer.text, startsWith('[RMS Express-1.7.28.0-B2FHMG\$]\r'));
        final proposal = RegExp(
          'FD EM $mid (\\d+) (\\d+) 0\\r',
        ).firstMatch(peer.text)!;
        expect(peer.text, contains('F> ${_checksumHex(proposal.group(0)!)}\r'));

        // Accept it; the client must send a GZIP payload of the proposed size.
        final frameStart = peer.raw.length;
        await peer.send('FS Y\r');
        final uncompressedSize = int.parse(proposal.group(1)!);
        WinLinkMailDecodeResult? sent;
        await _waitFor(() {
          final bytes = peer.raw.toBytes().sublist(frameStart);
          sent = WinLinkMail.decodeBlocksToEmail(
            bytes,
            compression: WinlinkCompressionType.gzip,
            expectedSize: uncompressedSize,
          );
          return sent!.mail != null;
        }, () => 'Outbound GZIP mail not decodable');
        expect(sent!.mail!.mid, mid);
        expect(
          _framedPayloadLength(peer.raw.toBytes().sublist(frameStart)),
          int.parse(proposal.group(2)!),
        );

        // Now propose a GZIP message to the client.
        final inbound = WinLinkMail()
          ..mid = 'INBOUND00001'
          ..from = 'W1AW'
          ..to = 'N0CALL'
          ..subject = 'Inbound'
          ..body = 'Inbound GZIP body';
        final encoded = WinLinkMail.encodeMailToBlocks(
          inbound,
          compression: WinlinkCompressionType.gzip,
        );
        final line =
            '${WinlinkProposal.format(compression: WinlinkCompressionType.gzip, mid: inbound.mid!, uncompressedSize: encoded.uncompressedSize, compressedSize: encoded.compressedSize)}\r';
        await peer.send('${line}F> ${_checksumHex(line)}\r');
        await _waitFor(
          () => peer.text.contains('FS Y\r'),
          () => 'FD proposal not accepted: ${peer.text}',
        );
        for (final block in encoded.blocks!) {
          await peer.sendBytes(block);
        }
        await _waitFor(
          () => received.isNotEmpty && peer.text.endsWith('FF\r'),
          () => 'Inbound GZIP mail not received: ${peer.text}',
        );
        expect(received.single.mid, 'INBOUND00001');
        expect(received.single.body, 'Inbound GZIP body');
      } finally {
        client.dispose();
        broker.dispose();
        store.dispose();
        await peer.close();
      }
    });

    test('when disabled, keeps the standard SID and defers FD', () async {
      DataBroker.dispatch(deviceId: 0, name: WinlinkGzip.settingName, data: 0);
      final client = WinlinkClient();
      final peer = await _Peer.connect(client);
      try {
        await peer.send('[Pat-0.16.0-B2FHMG\$]\rCMS >\r');
        await _waitFor(
          () => peer.text.contains('FF\r'),
          () => 'Initial FF not received: ${peer.text}',
        );
        expect(peer.text, startsWith('[RMS Express-1.7.28.0-B2FHM\$]\r'));

        const line = 'FD EM INBOUND00001 100 80 0\r';
        await peer.send('${line}F> ${_checksumHex(line)}\r');
        await _waitFor(
          () => peer.text.contains('FS H\r'),
          () => 'FD proposal not deferred: ${peer.text}',
        );
      } finally {
        client.dispose();
        await peer.close();
      }
    });
  });
}
