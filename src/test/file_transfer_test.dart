import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/file_transfer/file_transfer_engine.dart';
import 'package:htcommander/file_transfer/pacsat.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/handlers/file_transfer_handler.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/chat_widget.dart';
import 'package:htcommander/widgets/comms_tab.dart';
import 'package:htcommander/dialogs/file_transfer_dialog.dart';
import 'package:htcommander/widgets/file_transfer_card.dart';

final epoch = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);
const linkA = FileTransferLink(
  deviceId: 100,
  radioMac: 'A',
  regionId: 0,
  channelId: 1,
  channel: 'Packet',
  encoding: 'hardwareAfsk1200',
  rxFrequency: 145050000,
  txFrequency: 145050000,
);
const linkB = FileTransferLink(
  deviceId: 101,
  radioMac: 'B',
  regionId: 0,
  channelId: 1,
  channel: 'Packet',
  encoding: 'hardwareAfsk1200',
  rxFrequency: 145050000,
  txFrequency: 145050000,
);

FileTransfer outgoing(Uint8List body, {String name = 'hi.txt'}) {
  final bytes = PacsatFile.create(
    fileId: 0x12345678,
    name: name,
    source: 'N0CALL-9',
    destination: 'K1ABC-7',
    content: body,
    time: epoch,
  );
  return FileTransfer(
    id: 'example',
    link: linkA,
    source: 'N0CALL-9',
    outgoing: true,
    file: PacsatFile.fromBytes(bytes),
    created: epoch,
    state: FileTransferState.queued,
    buffer: PacsatBuffer(bytes.length)..add(0, bytes),
  );
}

void offer(
  FileTransferEngine engine,
  FileTransfer t,
  DateTime now, {
  String local = 'K1ABC-7',
}) {
  for (var at = 0; at < t.file.header.length; at += 237) {
    final end = min(at + 237, t.file.header.length);
    engine.receivePiece(
      linkB,
      'N0CALL-9',
      local,
      PacsatPiece(
        directory: true,
        last: end == t.file.header.length,
        fileId: t.file.fileId,
        offset: at,
        bytes: Uint8List.sublistView(t.file.header, at, end),
      ),
      now,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('matches the independently calculated PFH and CRC fixtures', () {
    final t = outgoing(Uint8List.fromList([0x48, 0x69, 0x0a]));
    expect(t.file.header.length, 189);
    expect(t.file.size, 192);
    expect(t.file.header, containsAllInOrder([0x0a, 0x00, 0x02, 0xd4, 0x24]));
    final piece = PacsatPiece.decode(
      Uint8List.fromList([
        0x22,
        0x78,
        0x56,
        0x34,
        0x12,
        0,
        0xbd,
        0,
        0,
        0x48,
        0x69,
        0x0a,
        0x2f,
        0x81,
      ]),
      directory: false,
    );
    expect(piece.offset, 189);
    expect(piece.last, true);
    expect(pacsatCrc(ascii.encode('123456789')), 0x31c3);
    expect(t.file.verify(t.buffer!.bytes), [0x48, 0x69, 0x0a]);
    expect(PacsatRequest(2, t.file.fileId).encode(), [
      0x12,
      0x78,
      0x56,
      0x34,
      0x12,
      0xf5,
      0,
    ]);
  });

  test('binary pieces reject CRC errors and requests have no inner CRC', () {
    final t = outgoing(Uint8List.fromList([1, 2, 3]));
    final bytes = PacsatPiece(
      directory: false,
      last: true,
      fileId: t.file.fileId,
      offset: t.file.header.length,
      bytes: Uint8List.fromList([1, 2, 3]),
    ).encode();
    bytes[9] ^= 1;
    expect(
      () => PacsatPiece.decode(bytes, directory: false),
      throwsFormatException,
    );
    expect(
      () => PacsatRequest.decode(
        Uint8List.fromList([0x12, 1, 0, 0, 0, 0xf5, 0, 0]),
      ),
      throwsFormatException,
    );
    expect(
      () => PacsatRequest.decode(
        Uint8List.fromList([0x12, 1, 0, 0, 0, 0xf5, 0, 0, 0, 0, 0, 0]),
      ),
      throwsFormatException,
    );
  });

  test('gzip and UTF-8 names round-trip, body damage fails verification', () {
    final t = outgoing(
      Uint8List.fromList(List.filled(50000, 65)),
      name: '\u00e9.txt',
    );
    expect(t.file.compressed, true);
    expect(t.file.name, '\u00e9.txt');
    expect(t.file.verify(t.buffer!.bytes).length, 50000);
    final damaged = Uint8List.fromList(t.buffer!.bytes)
      ..[t.file.header.length] ^= 1;
    expect(() => t.file.verify(damaged), throwsFormatException);
    expect(
      () => outgoing(Uint8List.fromList([1, 2, 3]), name: 'x' * 256),
      throwsFormatException,
    );
  });

  test(
    'range coverage ignores duplicates, detects conflicts and splits large holes',
    () {
      final buffer = PacsatBuffer(100000);
      expect(buffer.requestHoles().map((h) => h.length), [65535, 34465]);
      buffer.add(99998, [3, 4]);
      buffer.add(99998, [3, 4]);
      expect(buffer.received, 2);
      expect(() => buffer.add(99999, [9]), throwsFormatException);
      expect(() => buffer.add(100000, [1]), throwsFormatException);
      expect(buffer.complete, false);
    },
  );

  test('offers respect SSIDs, require acceptance and expire', () {
    final sent = <Uint8List>[];
    final engine = FileTransferEngine(
      send: (t, pid, to, bytes) {
        sent.add(bytes);
        return true;
      },
      available: (_) => true,
      cancelPackets: (_) {},
      changed: () {},
      receivedFile: (_, _) {},
      random: Random(1),
    );
    final t = outgoing(Uint8List.fromList([1, 2, 3]));
    offer(engine, t, epoch, local: 'K1ABC');
    expect(engine.transfers, isEmpty);
    offer(engine, t, epoch);
    expect(engine.transfers.single.buffer, isNull);
    engine.tick(epoch.add(const Duration(seconds: 5)));
    expect(sent, isEmpty);
    engine.act(engine.transfers.single.id, 'accept', epoch);
    engine.tick(epoch.add(const Duration(seconds: 6)));
    expect(PacsatRequest.decode(sent.single).command, 0);
    final holes = engine.transfers.single.buffer!.requestHoles();
    expect(holes.single.offset, t.file.header.length);
    expect(holes.single.length, 3);
  });

  test(
    'persists partial bytes, resumes via holes, and never transmits on restart alone',
    () {
      final sent = <PacsatRequest>[];
      var canceled = 0;
      final engine = FileTransferEngine(
        send: (t, pid, to, bytes) {
          sent.add(PacsatRequest.decode(bytes));
          return true;
        },
        available: (_) => true,
        cancelPackets: (_) {
          canceled++;
        },
        changed: () {},
        receivedFile: (_, _) {},
        random: Random(1),
      );
      final t = outgoing(Uint8List.fromList([1, 2, 3, 4]));
      offer(engine, t, epoch);
      final rx = engine.transfers.single;
      engine.act(rx.id, 'accept', epoch);
      rx.buffer!.add(t.file.header.length, [1, 2]);
      final restored = FileTransfer.restore(
        jsonDecode(jsonEncode(rx.toJson(storage: true)))
            as Map<String, dynamic>,
      );
      engine.transfers
        ..clear()
        ..add(restored);
      expect(restored.state, FileTransferState.paused);
      engine.tick(epoch.add(const Duration(seconds: 30)));
      expect(sent, isEmpty);
      engine.act(restored.id, 'resume', epoch.add(const Duration(seconds: 30)));
      engine.tick(epoch.add(const Duration(seconds: 36)));
      expect(sent.single.command, 2);
      expect(sent.single.holes.single.length, 2);
      engine.act(restored.id, 'cancel', epoch.add(const Duration(seconds: 37)));
      engine.tick(epoch.add(const Duration(seconds: 43)));
      expect(sent.last.command, 1);
      expect(canceled, 1);
      expect(restored.buffer, isNull);
    },
  );

  test(
    'sender queues only offers, rejection/cancel prevent subsequent body packets',
    () {
      final frames = <(int, Uint8List)>[];
      var canceled = 0;
      final engine = FileTransferEngine(
        send: (t, pid, to, bytes) {
          frames.add((pid, bytes));
          return true;
        },
        available: (_) => true,
        cancelPackets: (_) {
          canceled++;
        },
        changed: () {},
        receivedFile: (_, _) {},
        random: Random(1),
      );
      final t = outgoing(Uint8List.fromList([1, 2, 3]));
      engine.addOutgoing(t);
      engine.tick(epoch);
      engine.tick(epoch.add(const Duration(seconds: 20)));
      expect(frames.every((f) => f.$1 == 0xbd), true);
      engine.receiveRequest(
        linkA,
        'K1ABC-7',
        PacsatRequest(1, t.file.fileId),
        epoch.add(const Duration(seconds: 21)),
      );
      engine.tick(epoch.add(const Duration(minutes: 3)));
      expect(t.state, FileTransferState.rejected);
      expect(frames.every((f) => f.$1 == 0xbd), true);
      expect(canceled, 1);
    },
  );

  test(
    'two stations complete a binary transfer with dropped and reordered pieces',
    () {
      final random = Random(6);
      final content = Uint8List.fromList(
        List.generate(12000, (_) => random.nextInt(256)),
      );
      final t = outgoing(content, name: 'sample.bin');
      final queue = <(bool, int, String, Uint8List)>[];
      Uint8List? received;
      var dataCount = 0;
      var holeRequests = 0;
      var now = epoch;
      late FileTransferEngine rx;
      final tx = FileTransferEngine(
        send: (t, pid, to, bytes) {
          if (pid == 0xbb && ++dataCount == 2) return true;
          queue.add((true, pid, to, bytes));
          return true;
        },
        available: (_) => true,
        cancelPackets: (_) {},
        changed: () {},
        receivedFile: (_, _) {},
        random: Random(1),
      );
      rx = FileTransferEngine(
        send: (t, pid, to, bytes) {
          if (PacsatRequest.decode(bytes).holes.isNotEmpty) holeRequests++;
          queue.add((false, pid, to, bytes));
          return true;
        },
        available: (_) => true,
        cancelPackets: (_) {},
        changed: () {},
        receivedFile: (transfer, bytes) {
          received = bytes;
          rx.completeReceive(transfer, 'verified.bin', now);
        },
        random: Random(2),
      );
      tx.addOutgoing(t);
      for (
        var step = 0;
        step < 10000 && t.state != FileTransferState.completed;
        step++
      ) {
        now = epoch.add(Duration(milliseconds: step * 250));
        tx.tick(now);
        rx.tick(now);
        while (queue.isNotEmpty) {
          final packet = queue.removeLast();
          if (packet.$1) {
            rx.receivePiece(
              linkB,
              'N0CALL-9',
              'K1ABC-7',
              PacsatPiece.decode(packet.$4, directory: packet.$2 == 0xbd),
              now,
            );
          } else {
            tx.receiveRequest(
              linkA,
              'K1ABC-7',
              PacsatRequest.decode(packet.$4),
              now,
            );
          }
        }
        for (final transfer in rx.transfers) {
          if (transfer.state == FileTransferState.offering) {
            rx.act(transfer.id, 'accept', now);
          }
        }
      }
      expect(holeRequests, greaterThan(0));
      expect(t.state, FileTransferState.completed);
      expect(received, content);
      expect(rx.transfers.single.state, FileTransferState.completed);
    },
  );

  testWidgets(
    'file offer is a chat block with accept/reject, then progress/cancel',
    (tester) async {
      final t = outgoing(Uint8List.fromList([1, 2, 3]));
      final rx = FileTransfer(
        id: 'rx',
        link: linkB,
        source: t.source,
        outgoing: false,
        file: t.file,
        created: epoch,
        state: FileTransferState.offering,
      );
      final actions = <String>[];
      Widget app() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatWidget(
            messages: [
              ChatMessage(
                id: 'rx',
                route: 'Packet FILE',
                senderCallsign: rx.source,
                message: '',
                time: epoch,
                isSender: false,
                bubbleContent: FileTransferCard(
                  transfer: rx,
                  onAction: actions.add,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('hi.txt'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.tap(find.text('Reject'));
      expect(actions, ['accept', 'reject']);
      rx.state = FileTransferState.receiving;
      rx.transferred = 100;
      await tester.pumpWidget(app());
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      await tester.tap(find.text('Cancel'));
      expect(actions.last, 'cancel');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Comms restores transfer cards, opens the menu dialog and updates one block',
    (tester) async {
      DataBroker.reset();
      final bus = DataBrokerClient();
      addTearDown(() {
        bus.dispose();
        DataBroker.reset();
      });
      final t = outgoing(Uint8List.fromList([1, 2, 3]));
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': 100, 'MacAddress': 'A'},
        ],
      );
      bus.dispatch(deviceId: 1, name: 'SelectedRadioDeviceId', data: 100);
      bus.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
      bus.dispatch(deviceId: 1, name: 'FileTransfers', data: [t.toJson()]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CommsTab()),
          // Ahem makes the existing PTT settings label exceed the menu width.
          theme: ThemeData(
            popupMenuTheme: const PopupMenuThemeData(
              labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('hi.txt'), findsOneWidget);
      final chat = tester.widget<ChatWidget>(find.byType(ChatWidget));
      final id = chat.messages.single.id;
      await tester.tap(
        find.image(const AssetImage('assets/images/MenuIcon.png')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Transfer File...'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTransferDialog), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
      expect(
        find.text('Destination callsign (including SSID)'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      t.state = FileTransferState.sending;
      t.transferred = 100;
      bus.dispatch(deviceId: 1, name: 'FileTransfers', data: [t.toJson()]);
      await tester.pump();
      final updated = tester.widget<ChatWidget>(find.byType(ChatWidget));
      expect(updated.messages.single.id, id);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('native broker adapter', () {
    late Directory directory;
    late FileTransferHandler handler;
    late DataBrokerClient bus;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    setUp(() async {
      DataBroker.reset();
      directory = await Directory.systemTemp.createTemp('htc-file-transfer-');
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory.path,
      );
      bus = DataBrokerClient();
      bus.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
      bus.dispatch(deviceId: 0, name: 'StationId', data: 9);
      bus.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': 100, 'MacAddress': 'A'},
        ],
      );
      bus.dispatch(
        deviceId: 100,
        name: 'Settings',
        data: {'channelA': 1, 'channelB': 2, 'doubleChannel': 0},
      );
      bus.dispatch(
        deviceId: 100,
        name: 'HtStatus',
        data: {
          'currRegion': 0,
          'doubleChannel': 0,
          'isInTx': false,
          'isInRx': false,
          'rssi': 0,
        },
      );
      bus.dispatch(
        deviceId: 100,
        name: 'Channels',
        data: [
          {
            'channelId': 1,
            'name': 'Packet',
            'rxFreq': 145050000,
            'txFreq': 145050000,
            'txDisable': false,
          },
        ],
      );
      handler = FileTransferHandler();
      await handler.init();
    });
    tearDown(() async {
      handler.dispose();
      await handler.flush();
      bus.dispose();
      messenger.setMockMethodCallHandler(pathChannel, null);
      await directory.delete(recursive: true);
      DataBroker.reset();
    });

    void receive(AX25Packet packet, {bool historical = false}) {
      final frame = TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: packet.toByteArray(),
        channelId: 1,
        regionId: 0,
        incoming: true,
        encoding: FragmentEncodingType.hardwareAfsk1200,
        frameType: FragmentFrameType.ax25,
        historical: historical,
      );
      bus.dispatch(deviceId: 100, name: 'DataFrame', data: frame, store: false);
    }

    test(
      'outgoing card is durable before queue confirmation; radio receives binary PID',
      () async {
        Map? result;
        final packets = <AX25Packet>[];
        bus.subscribe(
          deviceId: 1,
          name: 'FileTransferCommandResult',
          callback: (_, _, data) {
            result = data as Map;
          },
        );
        bus.subscribe(
          deviceId: 100,
          name: 'TransmitDataFrame',
          callback: (_, _, data) {
            final packet = (data as TransmitDataFrameData).packet!;
            packets.add(packet);
            bus.dispatch(
              deviceId: 100,
              name: 'FileTransmitResult',
              data: {'tag': packet.tag, 'accepted': true},
              store: false,
            );
          },
        );
        bus.dispatch(
          deviceId: 1,
          name: 'FileTransferSend',
          data: {
            'requestId': 'test',
            'deviceId': 100,
            'name': 'hi.txt',
            'destination': 'K1ABC-7',
            'data': base64Encode([1, 2, 3]),
          },
          store: false,
        );
        for (var i = 0; i < 100 && result == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(result?['accepted'], true);
        final archive = File(
          '${directory.path}${Platform.pathSeparator}file-transfers${Platform.pathSeparator}transfers.json',
        );
        final stored = jsonDecode(await archive.readAsString()) as List;
        expect(stored.single['data'], isNotNull);
        expect(
          (DataBroker.getValueDynamic(1, 'FileTransfers') as List)
              .single['outgoing'],
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(packets, isNotEmpty);
        expect(packets.first.pid, 0xbd);
        expect(packets.first.addresses.first.callSignWithId, 'QST-1');
        expect(
          PacsatPiece.decode(packets.first.data!, directory: true).offset,
          0,
        );
      },
    );

    test(
      'live offer appears without Comms UI, historical offer does not; accepted file is saved',
      () async {
        final whole = PacsatFile.create(
          fileId: 52,
          name: 'received.txt',
          source: 'K1ABC-7',
          destination: 'N0CALL-9',
          content: Uint8List.fromList([7, 8, 9]),
          time: epoch,
        );
        final file = PacsatFile.fromBytes(whole);
        AX25Packet packet(PacsatPiece piece) => AX25Packet.uiBytes([
          AX25Address.parse('QST-1')!,
          AX25Address.parse('K1ABC-7')!,
        ], piece.encode())..pid = piece.directory ? 0xbd : 0xbb;
        final offered = packet(
          PacsatPiece(
            directory: true,
            last: true,
            fileId: 52,
            offset: 0,
            bytes: file.header,
          ),
        );
        receive(offered, historical: true);
        expect(DataBroker.getValueDynamic(1, 'FileTransfers'), isEmpty);
        receive(offered);
        final row =
            (DataBroker.getValueDynamic(1, 'FileTransfers') as List).single
                as Map;
        expect(row['state'], 'offering');
        bus.dispatch(
          deviceId: 1,
          name: 'FileTransferAction',
          data: {'id': row['id'], 'action': 'accept'},
          store: false,
        );
        receive(
          packet(
            PacsatPiece(
              directory: false,
              last: true,
              fileId: 52,
              offset: file.header.length,
              bytes: Uint8List.fromList([7, 8, 9]),
            ),
          ),
        );
        Map? complete;
        for (var i = 0; i < 100; i++) {
          complete =
              (DataBroker.getValueDynamic(1, 'FileTransfers') as List).single
                  as Map;
          if (complete['state'] == 'completed') break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(complete?['state'], 'completed');
        expect(await File(complete!['savedPath'] as String).readAsBytes(), [
          7,
          8,
          9,
        ]);
        expect(await handler.flush(), true);
        final archive = File(
          '${directory.path}${Platform.pathSeparator}file-transfers${Platform.pathSeparator}transfers.json',
        );
        expect(
          (jsonDecode(await archive.readAsString()) as List).single['state'],
          'completed',
        );
      },
    );
  });
}
