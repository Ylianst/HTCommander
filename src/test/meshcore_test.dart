import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/meshcore/meshcore_client.dart';
import 'package:htcommander/meshcore/meshcore_protocol.dart';
import 'package:htcommander/meshcore/meshcore_stream_transport.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/widgets/contact_avatar.dart';

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Uint8List _i32(int v) =>
    Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little);

Uint8List _frame(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

Uint8List _fixed(String s, int size, {int fill = 0}) {
  final out = Uint8List(size)..fillRange(0, size, fill);
  final b = utf8.encode(s);
  out.setRange(0, b.length, b);
  if (b.length < size) out[b.length] = 0;
  return out;
}

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) & 0xFF));

Uint8List _contactFrame(
  int code,
  Uint8List key,
  String name, {
  int type = MeshCoreAdvType.chat,
  int lat = 0,
  int lon = 0,
}) => _frame([
  [code],
  key,
  [type, 0, 0xFF],
  Uint8List(64),
  _fixed(name, 32),
  _u32(1700000000),
  _i32(lat),
  _i32(lon),
  _u32(1700000100),
]);

Uint8List _deviceInfoFrame({int maxChannels = 8}) => _frame([
  [MeshCoreResp.deviceInfo, 13, 50, maxChannels],
  _u32(123456),
  _fixed('7 Feb 2026', 12),
  _fixed('Heltec V3', 40),
  _fixed('v1.16.0', 20),
  [0, 0],
]);

class _FakeTransport implements MeshCoreTransport {
  final _frames = StreamController<Uint8List>.broadcast(sync: true);
  final _disconnected = StreamController<void>.broadcast(sync: true);
  final List<Uint8List> sent = [];
  void Function(Uint8List frame)? onSend;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  Future<void> sendFrame(Uint8List frame) async {
    sent.add(frame);
    onSend?.call(frame);
  }

  void receive(Uint8List frame) => _frames.add(frame);

  void drop() => _disconnected.add(null);

  @override
  Future<void> close() async {}
}

void main() {
  group('MeshCore stream framing', () {
    Uint8List fromRadio(List<int> payload) => Uint8List.fromList([
      0x3E,
      payload.length & 0xFF,
      payload.length >> 8,
      ...payload,
    ]);

    test('encodes app-to-radio frames', () {
      expect(encodeStreamFrame([1, 2, 3]), [0x3C, 3, 0, 1, 2, 3]);
      final big = encodeStreamFrame(List.filled(300, 7));
      expect(big.sublist(0, 3), [0x3C, 300 & 0xFF, 1]);
    });

    test('reassembles frames split across chunks', () {
      final d = MeshCoreStreamDecoder();
      final bytes = [...fromRadio([5, 6, 7]), ...fromRadio([9])];
      final out = <Uint8List>[];
      for (final b in bytes) {
        out.addAll(d.add([b]));
      }
      expect(out, [
        [5, 6, 7],
        [9],
      ]);
    });

    test('skips noise and implausible lengths', () {
      final d = MeshCoreStreamDecoder();
      final noise = 'boot> ok\r\n'.codeUnits;
      final frames = d.add([
        ...noise,
        0x3E, 0xFF, 0xFF, // bogus 65535-byte header
        ...fromRadio([1, 2]),
      ]);
      expect(frames, [
        [1, 2],
      ]);
    });

    test('parses TCP targets', () {
      expect(parseMeshCoreTcpTarget('192.168.1.20'), (
        host: '192.168.1.20',
        port: meshCoreDefaultTcpPort,
      ));
      expect(parseMeshCoreTcpTarget('meshcore.local:5001'), (
        host: 'meshcore.local',
        port: 5001,
      ));
      expect(parseMeshCoreTcpTarget('[fe80::1]:4000'), (
        host: 'fe80::1',
        port: 4000,
      ));
      expect(parseMeshCoreTcpTarget('host:0'), isNull);
      expect(parseMeshCoreTcpTarget('bad host'), isNull);
      expect(parseMeshCoreTcpTarget(''), isNull);
    });

    test('TCP transport talks to a companion end to end', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Uint8List>[];
      server.listen((socket) {
        final decoder = <int>[];
        socket.listen((data) {
          decoder.addAll(data);
          // App-to-radio frames: '<' + len16 + payload.
          while (decoder.length >= 3 && decoder[0] == 0x3C) {
            final len = decoder[1] | (decoder[2] << 8);
            if (decoder.length < 3 + len) break;
            final payload = Uint8List.fromList(decoder.sublist(3, 3 + len));
            decoder.removeRange(0, 3 + len);
            received.add(payload);
            if (payload[0] == MeshCoreCmd.deviceQuery) {
              final reply = _deviceInfoFrame();
              // Split the reply to exercise reassembly.
              final framed = fromRadio(reply);
              socket.add(framed.sublist(0, 10));
              socket.add(framed.sublist(10));
            }
          }
        });
      });
      final transport = await MeshCoreTcpTransport.connect(
        '127.0.0.1',
        server.port,
      );
      final client = MeshCoreClient(transport);
      final info = await client.queryDevice();
      expect(info.model, 'Heltec V3');
      expect(received.single, MeshCoreCommands.deviceQuery());
      await client.close();
      await server.close();
    });
  });

  group('MeshCore contacts', () {
    final key = bytesToHex(_key(0x40));

    test('a MeshCore user survives JSON and text export round-trips', () {
      final station = StationInfo(
        callsign: key,
        name: 'Alice',
        description: 'Base camp',
        stationType: StationType.meshCore,
        avatarIcon: 'star',
      );
      final fromJson = StationInfo.fromJson(station.toJson());
      expect(fromJson.stationType, StationType.meshCore);
      expect(fromJson.callsign, key);
      expect(fromJson.avatarIcon, 'star');
      final fromText = StationInfo.deserializeList(
        StationInfo.serializeList([station]),
      ).single;
      expect(fromText.stationType, StationType.meshCore);
      expect(fromText.callsign, key);
      expect(fromText.name, 'Alice');
    });

    test('existing station type indexes are unchanged', () {
      expect(StationType.email.index, 8);
      expect(StationType.meshCore.index, 9);
    });

    test('peer and fingerprint helpers', () {
      expect(meshCorePeerForKey(key.toUpperCase()), key.substring(0, 12));
      expect(
        meshCoreFingerprint(key),
        '${key.substring(0, 8)}…${key.substring(56)}',
      );
    });

    test('initials from display names', () {
      expect(nameInitials('Alice Smith'), 'AS');
      expect(nameInitials('bob'), 'BO');
      expect(nameInitials('  '), '?');
      expect(nameInitials('Ünal Öz'), 'ÜÖ');
    });
  });

  group('MeshCore command builders', () {
    test('appStart reserves seven bytes before the app name', () {
      final f = MeshCoreCommands.appStart('HTC');
      expect(f, [1, 0, 0, 0, 0, 0, 0, 0, 0x48, 0x54, 0x43]);
    });

    test('sendText uses the six-byte key prefix and attempt', () {
      final key = _key(1);
      final f = MeshCoreCommands.sendText(
        key,
        'Hi',
        timestamp: 0x01020304,
        attempt: 2,
      );
      expect(f.sublist(0, 7), [2, 0, 2, 4, 3, 2, 1]);
      expect(f.sublist(7, 13), key.sublist(0, 6));
      expect(utf8.decode(f.sublist(13)), 'Hi');
    });

    test('sendText never exceeds the 160-byte text limit', () {
      final f = MeshCoreCommands.sendText(
        _key(1),
        'é' * 200,
        timestamp: 0,
      );
      expect(f.length - 13, lessThanOrEqualTo(160));
      expect(() => utf8.decode(f.sublist(13)), returnsNormally);
    });

    test('setChannel is 50 bytes with a padded name', () {
      final secret = hashtagChannelSecret('#test');
      final f = MeshCoreCommands.setChannel(3, '#test', secret);
      expect(f.length, 50);
      expect(f[0], MeshCoreCmd.setChannel);
      expect(f[1], 3);
      expect(utf8.decode(f.sublist(2, 7)), '#test');
      expect(f[7], 0);
      expect(f.sublist(34), secret);
    });

    test('addUpdateContact encodes negative coordinates', () {
      final c = MeshCoreContact(
        publicKey: _key(9),
        type: MeshCoreAdvType.chat,
        name: 'Alice',
        latitude: -33.5,
        longitude: 151.25,
      );
      final f = MeshCoreCommands.addUpdateContact(c);
      final parsed = MeshCoreContact.parse(f)!;
      expect(parsed.latitude, -33.5);
      expect(parsed.longitude, 151.25);
      expect(parsed.name, 'Alice');
      expect(parsed.outPathLen, MeshCoreConst.pathUnknown);
    });
  });

  group('MeshCore parsers', () {
    test('hashtag secret matches the published #test example', () {
      expect(
        bytesToHex(hashtagChannelSecret('#test')),
        '9cd8fcf22a47333b591d96a2b848b73f',
      );
      expect(hashtagChannelSecret('test'), hashtagChannelSecret('#test'));
    });

    test('self info', () {
      final key = _key(5);
      final f = _frame([
        [MeshCoreResp.selfInfo, 1, 22, 22],
        key,
        _i32(45500000),
        _i32(-73600000),
        [0, 0, 0, 1],
        _u32(910525),
        _u32(62500),
        [7, 5],
        utf8.encode('My Node'),
      ]);
      final info = MeshCoreSelfInfo.parse(f)!;
      expect(info.publicKey, key);
      expect(info.latitude, closeTo(45.5, 1e-9));
      expect(info.longitude, closeTo(-73.6, 1e-9));
      expect(info.manualAddContacts, isTrue);
      expect(info.radioFreqMhz, closeTo(910.525, 1e-9));
      expect(info.radioBandwidthKhz, closeTo(62.5, 1e-9));
      expect(info.spreadingFactor, 7);
      expect(info.name, 'My Node');
    });

    test('device info', () {
      final info = MeshCoreDeviceInfo.parse(_deviceInfoFrame(maxChannels: 40))!;
      expect(info.firmwareVersionCode, 13);
      expect(info.maxContacts, 100);
      expect(info.maxChannels, 40);
      expect(info.model, 'Heltec V3');
      expect(info.version, 'v1.16.0');
    });

    test('channel info ignores stale bytes after the name terminator', () {
      final secret = publicChannelSecret();
      final f = _frame([
        [MeshCoreResp.channelInfo, 0],
        _fixed('Public', 32, fill: 0x41),
        secret,
      ]);
      final ch = MeshCoreChannel.parse(f)!;
      expect(ch.name, 'Public');
      expect(ch.kind, MeshCoreChannelKind.public);
      expect(ch.isEmpty, isFalse);
    });

    test('channel kinds', () {
      MeshCoreChannel ch(String name, Uint8List secret) =>
          MeshCoreChannel(index: 1, name: name, secret: secret);
      expect(
        ch('#hike', hashtagChannelSecret('#hike')).kind,
        MeshCoreChannelKind.hashtag,
      );
      expect(
        ch('#hike', randomChannelSecret()).kind,
        MeshCoreChannelKind.private,
      );
      expect(ch('', Uint8List(16)).isEmpty, isTrue);
    });

    test('contact frame with location', () {
      final key = _key(7);
      final c = MeshCoreContact.parse(
        _contactFrame(
          MeshCoreResp.contact,
          key,
          'Bob',
          lat: 40712800,
          lon: -74006000,
        ),
      )!;
      expect(c.publicKeyHex, bytesToHex(key));
      expect(c.prefixHex, bytesToHex(key.sublist(0, 6)));
      expect(c.name, 'Bob');
      expect(c.latitude, closeTo(40.7128, 1e-9));
      expect(c.longitude, closeTo(-74.006, 1e-9));
      expect(c.lastModified, 1700000100);
    });

    test('contact without location', () {
      final c = MeshCoreContact.parse(
        _contactFrame(MeshCoreResp.contact, _key(1), 'X'),
      )!;
      expect(c.latitude, isNull);
      expect(c.longitude, isNull);
    });

    test('V3 direct message with negative SNR', () {
      final f = _frame([
        [MeshCoreResp.contactMsgRecvV3, 0xF6, 0, 0],
        [1, 2, 3, 4, 5, 6],
        [0x02, MeshCoreTxtType.plain],
        _u32(1700000000),
        utf8.encode('hello'),
      ]);
      final m = MeshCoreIncomingMessage.parse(f)!;
      expect(m.isChannel, isFalse);
      expect(m.senderPrefixHex, '010203040506');
      expect(m.snr, -2.5);
      expect(hopsFromPathLen(m.pathLen), 2);
      expect(m.senderTimestamp, 1700000000);
      expect(m.text, 'hello');
    });

    test('signed direct message skips the signature', () {
      final f = _frame([
        [MeshCoreResp.contactMsgRecv],
        [1, 2, 3, 4, 5, 6],
        [0xFF, MeshCoreTxtType.signedPlain],
        _u32(1),
        [9, 9, 9, 9],
        utf8.encode('signed'),
      ]);
      final m = MeshCoreIncomingMessage.parse(f)!;
      expect(m.text, 'signed');
      expect(hopsFromPathLen(m.pathLen), isNull);
      expect(m.snr, isNull);
    });

    test('V3 channel message', () {
      final f = _frame([
        [MeshCoreResp.channelMsgRecvV3, 20, 0, 0],
        [3, 0, MeshCoreTxtType.plain],
        _u32(1700000000),
        utf8.encode('Alice: hi all'),
      ]);
      final m = MeshCoreIncomingMessage.parse(f)!;
      expect(m.isChannel, isTrue);
      expect(m.channelIndex, 3);
      expect(m.snr, 5.0);
      final split = splitChannelText(m.text);
      expect(split.sender, 'Alice');
      expect(split.text, 'hi all');
    });

    test('send replies and confirmations', () {
      final sent = MeshCoreSentInfo.parse(
        _frame([
          [MeshCoreResp.sent, 1],
          _u32(0xDEADBEEF),
          _u32(9000),
        ]),
      )!;
      expect(sent.flood, isTrue);
      expect(sent.ackTag, 0xDEADBEEF);
      expect(sent.timeoutMs, 9000);
      final ack = MeshCoreSendConfirmed.parse(
        _frame([
          [MeshCorePush.sendConfirmed],
          _u32(0xDEADBEEF),
          _u32(1234),
        ]),
      )!;
      expect(ack.ackTag, 0xDEADBEEF);
      expect(ack.roundTripMs, 1234);
    });

    test('key and text helpers', () {
      final hex = bytesToHex(_key(3));
      expect(normalizePublicKeyHex(hex.toUpperCase()), hex);
      expect(normalizePublicKeyHex('${hex.substring(0, 8)} ${hex.substring(8)}'),
          hex);
      expect(normalizePublicKeyHex(hex.substring(2)), isNull);
      expect(normalizePublicKeyHex('00' * 32), isNull);
      expect(normalizeChannelSecretHex('zz' * 16), isNull);
      expect(utf8Truncate('aé', 2), utf8.encode('a'));
      expect(maxChannelTextBytes('Node'), 154);
      expect(splitChannelText('no sender here').sender, isNull);
    });
  });

  group('MeshCoreClient', () {
    late _FakeTransport transport;
    late MeshCoreClient client;

    setUp(() {
      transport = _FakeTransport();
      client = MeshCoreClient(
        transport,
        commandTimeout: const Duration(milliseconds: 200),
      );
    });

    tearDown(() => client.close());

    test('sends one command at a time', () async {
      transport.onSend = (f) {
        if (f[0] == MeshCoreCmd.deviceQuery) {
          scheduleMicrotask(() => transport.receive(_deviceInfoFrame()));
        } else if (f[0] == MeshCoreCmd.getBattAndStorage) {
          scheduleMicrotask(
            () => transport.receive(
              _frame([
                [MeshCoreResp.battAndStorage],
                [0x10, 0x0F],
                _u32(10),
                _u32(100),
              ]),
            ),
          );
        }
      };
      final a = client.queryDevice();
      final b = client.getBattery();
      expect(transport.sent.length, 1);
      await a;
      final batt = await b;
      expect(transport.sent.length, 2);
      expect(batt!.millivolts, 0x0F10);
      expect(batt.totalKb, 100);
    });

    test('collects contacts until end of contacts', () async {
      transport.onSend = (f) {
        if (f[0] != MeshCoreCmd.getContacts) return;
        scheduleMicrotask(() {
          transport.receive(
            _frame([
              [MeshCoreResp.contactsStart],
              _u32(2),
            ]),
          );
          transport.receive(
            _contactFrame(MeshCoreResp.contact, _key(1), 'A'),
          );
          // A push in the middle of the sequence must not disturb it.
          transport.receive(_contactFrame(MeshCorePush.newAdvert, _key(3), 'N'));
          transport.receive(
            _contactFrame(MeshCoreResp.contact, _key(2), 'B'),
          );
          transport.receive(
            _frame([
              [MeshCoreResp.endOfContacts],
              _u32(0),
            ]),
          );
        });
      };
      final events = <MeshCoreEvent>[];
      client.events.listen(events.add);
      final contacts = await client.getContacts();
      expect(contacts.map((c) => c.name), ['A', 'B']);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<MeshCoreContactEvent>().single.isNew, isTrue);
    });

    test('maps error frames to exceptions', () async {
      transport.onSend = (f) => scheduleMicrotask(
        () => transport.receive(
          Uint8List.fromList([MeshCoreResp.err, MeshCoreErr.tableFull]),
        ),
      );
      await expectLater(
        client.setChannel(1, 'x', Uint8List(16)),
        throwsA(
          isA<MeshCoreException>().having(
            (e) => e.errorCode,
            'errorCode',
            MeshCoreErr.tableFull,
          ),
        ),
      );
    });

    test('times out and continues with the next command', () async {
      transport.onSend = (f) {
        if (f[0] == MeshCoreCmd.getBattAndStorage) {
          scheduleMicrotask(
            () => transport.receive(
              Uint8List.fromList([MeshCoreResp.battAndStorage, 1, 0]),
            ),
          );
        }
      };
      final first = client.sendAdvert();
      final second = client.getBattery();
      await expectLater(first, throwsA(isA<MeshCoreException>()));
      expect((await second)!.millivolts, 1);
    });

    test('drains queued messages after a message-waiting push', () async {
      var remaining = 2;
      transport.onSend = (f) {
        if (f[0] != MeshCoreCmd.syncNextMessage) return;
        scheduleMicrotask(() {
          if (remaining-- > 0) {
            transport.receive(
              _frame([
                [MeshCoreResp.channelMsgRecvV3, 0, 0, 0],
                [0, 0xFF, 0],
                _u32(1),
                utf8.encode('Bob: msg $remaining'),
              ]),
            );
          } else {
            transport.receive(
              Uint8List.fromList([MeshCoreResp.noMoreMessages]),
            );
          }
        });
      };
      final messages = <MeshCoreIncomingMessage>[];
      client.events.listen((e) {
        if (e is MeshCoreMessageEvent) messages.add(e.message);
      });
      transport.receive(Uint8List.fromList([MeshCorePush.msgWaiting]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messages.map((m) => m.text), ['Bob: msg 1', 'Bob: msg 0']);
    });

    test('channel sync stops at the first missing slot', () async {
      transport.onSend = (f) {
        if (f[0] == MeshCoreCmd.deviceQuery) {
          scheduleMicrotask(() => transport.receive(_deviceInfoFrame()));
        } else if (f[0] == MeshCoreCmd.getChannel) {
          final idx = f[1];
          scheduleMicrotask(() {
            if (idx < 2) {
              transport.receive(
                _frame([
                  [MeshCoreResp.channelInfo, idx],
                  _fixed(idx == 0 ? 'Public' : '', 32),
                  idx == 0 ? publicChannelSecret() : Uint8List(16),
                ]),
              );
            } else {
              transport.receive(
                Uint8List.fromList([MeshCoreResp.err, MeshCoreErr.notFound]),
              );
            }
          });
        }
      };
      await client.queryDevice();
      final channels = await client.getChannels();
      expect(channels.length, 2);
      expect(channels[1].isEmpty, isTrue);
    });

    test('a dropped link fails pending commands', () async {
      final pending = client.getBattery();
      final events = <MeshCoreEvent>[];
      client.events.listen(events.add);
      transport.drop();
      await expectLater(pending, throwsA(isA<MeshCoreException>()));
      await Future<void>.delayed(Duration.zero);
      expect(events.single, isA<MeshCoreDisconnectedEvent>());
    });

    test('only advances the device clock forwards', () async {
      final now = DateTime.utc(2026, 1, 1);
      final c = MeshCoreClient(transport, clock: () => now);
      transport.onSend = (f) {
        if (f[0] == MeshCoreCmd.getDeviceTime) {
          scheduleMicrotask(
            () => transport.receive(
              _frame([
                [MeshCoreResp.currTime],
                _u32(1000),
              ]),
            ),
          );
        } else if (f[0] == MeshCoreCmd.setDeviceTime) {
          scheduleMicrotask(
            () => transport.receive(Uint8List.fromList([MeshCoreResp.ok])),
          );
        }
      };
      await c.syncTime();
      expect(
        transport.sent.last,
        MeshCoreCommands.setDeviceTime(now.millisecondsSinceEpoch ~/ 1000),
      );
    });
  });
}
