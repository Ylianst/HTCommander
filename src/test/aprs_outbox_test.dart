import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_auth.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprsis/aprsis_client.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/aprs_handler.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/aprs_outbox_store.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';

void main() {
  group('APRS composition', () {
    test(
      'splits at the wire byte limit including authentication and counters',
      () {
        for (final authenticated in [false, true]) {
          final budget = authenticated ? 60 : 67;
          expect(
            splitAprsMessage(
              'a' * budget,
              'W1AW',
              authenticated: authenticated,
            ),
            ['a' * budget],
          );
          for (final length in [budget + 1, 549, 550, 1000, authenticated ? 1040 : 1180]) {
            final parts = splitAprsMessage(
              'a' * length,
              'W1AW',
              authenticated: authenticated,
            );
            expect(parts.length, inInclusiveRange(2, 20));
            expect(parts.every((p) => p.length <= budget), isTrue);
            expect(
              parts
                  .map((p) => p.replaceFirst(RegExp(r'^\(\d+/\d+\) '), ''))
                  .join(),
              'a' * length,
            );
            for (var i = 0; i < parts.length; i++) {
              expect(parts[i], startsWith('(${i + 1}/${parts.length}) '));
            }
          }
        }
      },
    );

    test('preserves SMS addressing on every part', () {
      for (final gateway in ['SMS', 'SMSGTE']) {
        final parts = splitAprsMessage(
          '@5551234567 ${'x' * 160}',
          gateway,
          authenticated: true,
        );
        expect(parts.length, greaterThan(1));
        expect(
          parts.every((p) => p.startsWith('@5551234567 (') && p.length <= 60),
          isTrue,
        );
        expect(
          parts
              .map((p) => p.replaceFirst(RegExp(r'^@\S+ \(\d+/\d+\) '), ''))
              .join(),
          'x' * 160,
        );
      }
    });

    test('rejects unsupported and oversized text without replacing it', () {
      for (final text in ['hello\u00e9', 'line\nbreak', 'tab\t', '\u007f']) {
        expect(
          () => splitAprsMessage(text, 'W1AW'),
          throwsA(
            isA<AprsComposeException>().having(
              (e) => e.reason,
              'reason',
              AprsComposeError.ascii,
            ),
          ),
        );
      }
      for (final text in ['a{b', 'a}b', 'a|b', 'a~b']) {
        expect(
          () => splitAprsMessage(text, 'W1AW'),
          throwsA(
            isA<AprsComposeException>().having(
              (e) => e.reason,
              'reason',
              AprsComposeError.reserved,
            ),
          ),
        );
      }
      expect(
        () => splitAprsMessage('x' * 1181, 'W1AW'),
        throwsA(isA<AprsComposeException>()),
      );
      expect(
        () => splitAprsMessage(' ', 'W1AW'),
        throwsA(isA<AprsComposeException>()),
      );
    });
  });

  group('durable APRS delivery', () {
    const radioId = 100;
    late DataBrokerClient bus;
    late AprsHandler handler;
    late DateTime now;
    final transmissions = <TransmitDataFrameData>[];

    setUp(() async {
      await AppDatabase.openInMemory();
      for (final id in [0, 1, radioId, aprsIsDeviceId]) {
        DataBroker.clearDevice(id);
      }
      now = DateTime(2026, 1, 1, 12);
      transmissions.clear();
      bus = DataBrokerClient();
      for (final setting in <String, Object>{
        'CallSign': 'N0CALL',
        'StationId': 7,
        'NextAprsMessageId': 1,
        'AllowTransmit': 1,
      }.entries) {
        bus.dispatch(deviceId: 0, name: setting.key, data: setting.value);
      }
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': radioId, 'MacAddress': 'original'},
        ],
      );
      bus.dispatch(deviceId: radioId, name: 'MacAddress', data: 'original');
      bus.dispatch(
        deviceId: radioId,
        name: 'Channels',
        data: [
          {'channelId': 7, 'name': 'APRS'},
        ],
      );
      bus.subscribe(
        deviceId: radioId,
        name: 'TransmitDataFrame',
        callback: (_, _, data) {
          if (data is! TransmitDataFrameData) return;
          transmissions.add(data);
          bus.dispatch(
            deviceId: radioId,
            name: 'AprsTransmitResult',
            data: {'tag': data.packet!.tag, 'accepted': true},
            store: false,
          );
        },
      );
      handler = AprsHandler(clock: () => now)..init();
      await handler.ready;
    });

    tearDown(() async {
      handler.dispose();
      await handler.ready;
      bus.dispose();
      await AppDatabase.close();
      for (final id in [0, 1, radioId, aprsIsDeviceId]) {
        DataBroker.clearDevice(id);
      }
    });

    Future<void> send([String text = 'Hello', AprsLinkPolicy policy = AprsLinkPolicy.automatic]) async {
      bus.dispatch(
        deviceId: 1,
        name: 'SendAprsMessage',
        data: AprsSendMessageData(
          destination: 'W1AW',
          message: text,
          radioDeviceId: radioId,
          policy: policy,
        ),
        store: false,
      );
      await handler.ready;
    }

    Future<void> frame(
      String line, {
      bool internet = false,
      FragmentEncodingType? encoding,
    }) async {
      final packet = Tnc2Codec.decode(line)!
        ..time = now
        ..incoming = true;
      final aprs = AprsPacket.parse(packet)!..fromAprsIs = internet;
      bus.dispatch(
        deviceId: 1,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(
          aprs,
          packet,
          encoding == null
              ? null
              : TncDataFragment(
                  finalFragment: true,
                  fragmentId: 0,
                  data: packet.toByteArray(),
                  channelId: 7,
                  regionId: 0,
                  incoming: true,
                  encoding: encoding,
                ),
        ),
        store: false,
      );
      await handler.ready;
    }

    test(
      'saves before sending, retries at increasing intervals, and accepts a late exact ACK',
      () async {
        await send();
        expect(
          (await AprsOutboxStore().load()).single.parts.single.attempts,
          1,
        );
        expect(handler.outgoingMessages.single.state, AprsDelivery.sent);
        for (var attempt = 1; attempt < 6; attempt++) {
          now = now.add(Duration(seconds: 30 * attempt - 1));
          await handler.processOutbox();
          expect(transmissions.length, attempt);
          now = now.add(const Duration(seconds: 1));
          await handler.processOutbox();
          expect(transmissions.length, attempt + 1);
        }
        now = now.add(const Duration(seconds: 180));
        await handler.processOutbox();
        expect(handler.outgoingMessages.single.state, AprsDelivery.failed);
        expect(transmissions, hasLength(6));
        await frame('W1AW-1>APRS::N0CALL-7 :ack1');
        await frame('W1AW>APRS::N0CALL-8 :ack1');
        await frame('W1AW>APRS::N0CALL-7 :ack2');
        expect(handler.outgoingMessages.single.state, AprsDelivery.failed);
        await frame('W1AW>APRS::N0CALL-7 :ack1', internet: true);
        expect(handler.outgoingMessages.single.state, AprsDelivery.delivered);
        now = now.add(const Duration(hours: 1));
        await handler.processOutbox();
        expect(transmissions, hasLength(6));
      },
    );

    test('RF-only survives restart, internet enablement, unavailable RF and manual resume', () async {
      final internet = <Object?>[];
      bus.subscribe(deviceId: 1, name: 'SendAprsIsMessage', callback: (_, _, data) => internet.add(data));
      await send('Hello', AprsLinkPolicy.rfOnly);
      final id = handler.outgoingMessages.single.id;
      handler.dispose();
      await handler.ready;
      handler = AprsHandler(clock: () => now)..init();
      await handler.ready;
      bus.dispatch(deviceId: 0, name: 'AprsIsEnabled', data: 1);
      bus.dispatch(deviceId: aprsIsDeviceId, name: 'AprsIsVerified', data: true);
      bus.dispatch(deviceId: 1, name: 'ConnectedRadios', data: []);
      bus.dispatch(deviceId: 1, name: 'RetryAprsMessage', data: id, store: false);
      await handler.ready;
      expect(handler.outgoingMessages.single.parts.single.attempts, 1);
      bus.dispatch(deviceId: 1, name: 'ConnectedRadios', data: [{'DeviceId': radioId, 'MacAddress': 'original'}]);
      await handler.processOutbox();
      expect(transmissions, hasLength(2));
      expect(internet, isEmpty);
      expect(handler.outgoingMessages.single.linkPolicy, AprsLinkPolicy.rfOnly);
      expect(handler.outgoingMessages.single.parts.single.wireId, 1);
      DataBroker.clearDevice(aprsIsDeviceId);
    });

    test('internet-only ignores a preferred radio and waits without consuming attempts', () async {
      final internet = <AprsFrameEventArgs>[];
      bus.subscribe(deviceId: 1, name: 'SendAprsIsMessage', callback: (_, _, data) {
        if (data is AprsFrameEventArgs) internet.add(data);
      });
      await send('Hello', AprsLinkPolicy.internetOnly);
      expect(handler.outgoingMessages.single.radioDeviceId, -1);
      expect(handler.outgoingMessages.single.parts.single.attempts, 0);
      bus.dispatch(deviceId: 0, name: 'AprsIsEnabled', data: 1);
      bus.dispatch(deviceId: aprsIsDeviceId, name: 'AprsIsVerified', data: true);
      await handler.processOutbox();
      expect(internet, hasLength(1));
      expect(transmissions, isEmpty);
      handler.dispose();
      await handler.ready;
      handler = AprsHandler(clock: () => now)..init();
      await handler.ready;
      bus.dispatch(deviceId: 1, name: 'RetryAprsMessage', data: handler.outgoingMessages.single.id, store: false);
      await handler.ready;
      expect(internet, hasLength(2));
      expect(transmissions, isEmpty);
      DataBroker.clearDevice(aprsIsDeviceId);
    });

    test('both links share wire IDs and one logical attempt budget', () async {
      final internet = <AprsFrameEventArgs>[];
      bus.dispatch(deviceId: 0, name: 'AprsIsEnabled', data: 1);
      bus.dispatch(deviceId: aprsIsDeviceId, name: 'AprsIsVerified', data: true);
      bus.subscribe(deviceId: 1, name: 'SendAprsIsMessage', callback: (_, _, data) {
        if (data is AprsFrameEventArgs) internet.add(data);
      });
      await send('Hello', AprsLinkPolicy.both);
      now = now.add(const Duration(seconds: 30));
      await handler.processOutbox();
      expect(transmissions, hasLength(2));
      expect(internet, hasLength(2));
      expect(handler.outgoingMessages.single.parts.single.attempts, 2);
      expect(internet.map((f) => f.aprsPacket.messageData.seqId), ['1', '1']);
      expect(transmissions.map((f) => AprsPacket.parse(f.packet!)!.messageData.seqId), ['1', '1']);
      DataBroker.clearDevice(aprsIsDeviceId);
    });

    test('legacy outbox JSON and commands preserve automatic link intent', () async {
      await send();
      for (final (radio, enabled, expected) in [
        (radioId, false, AprsLinkPolicy.rfOnly),
        (radioId, true, AprsLinkPolicy.both),
        (-1, true, AprsLinkPolicy.internetOnly),
      ]) {
        final json = handler.outgoingMessages.single.toJson()..remove('linkPolicy');
        json['radioDeviceId'] = radio;
        json['internet'] = enabled;
        expect(AprsOutgoingMessage.fromJson(json).linkPolicy, expected);
      }
      expect(AprsSendMessageData.fromJson({'destination': 'W1AW', 'message': 'Hello', 'radioDeviceId': radioId}).policy,
        AprsLinkPolicy.automatic);
      final invalidLegacy = handler.outgoingMessages.single.toJson()..remove('linkPolicy');
      invalidLegacy['radioDeviceId'] = -1;
      invalidLegacy['internet'] = false;
      expect(() => AprsOutgoingMessage.fromJson(invalidLegacy), throwsFormatException);
      expect(() => AprsSendMessageData.fromJson({'destination': 'W1AW', 'message': 'Hello',
        'radioDeviceId': radioId, 'policy': 'fallback'}), throwsArgumentError);
      bus.dispatch(deviceId: 1, name: 'SendAprsMessage', data: const AprsSendMessageData(
        destination: 'W1AW', message: 'No radio', radioDeviceId: -1, policy: AprsLinkPolicy.both), store: false);
      await handler.ready;
      expect(handler.outgoingMessages, hasLength(1));
      expect((bus.getValueDynamic(1, 'AprsSendError') as Map)['reason'], 'radio');
    });

    test('multipart IDs remain distinct across wrap and initial parts precede retries', () async {
      handler.dispose();
      bus.dispatch(deviceId: 0, name: 'NextAprsMessageId', data: 99999);
      handler = AprsHandler(clock: () => now)..init();
      await handler.ready;
      await send('a' * 140);
      final message = handler.outgoingMessages.single;
      expect(message.parts.map((p) => p.wireId), [99999, 1, 2]);
      expect(transmissions, hasLength(3));
      expect(transmissions.map((t) => AprsPacket.parse(t.packet!)!.messageData.seqId), ['99999', '1', '2']);
      now = now.add(const Duration(seconds: 30));
      await handler.processOutbox();
      expect(transmissions, hasLength(6));
    });

    test('configurable retries enforce the attempt limit and five-minute wait cap', () async {
      bus.dispatch(deviceId: 0, name: 'AprsRetryAttempts', data: 3);
      bus.dispatch(deviceId: 0, name: 'AprsRetrySeconds', data: 240);
      await send();
      now = now.add(const Duration(seconds: 240));
      await handler.processOutbox();
      expect(transmissions, hasLength(2));
      expect(handler.outgoingMessages.single.parts.single.nextAttempt, now.add(const Duration(seconds: 300)));
      now = now.add(const Duration(seconds: 300));
      await handler.processOutbox();
      expect(transmissions, hasLength(3));
      now = now.add(const Duration(seconds: 300));
      await handler.processOutbox();
      expect(transmissions, hasLength(3));
      expect(handler.outgoingMessages.single.state, AprsDelivery.failed);
    });

    test('restart pauses and resume preserves the remaining budget', () async {
      await send();
      handler.dispose();
      await handler.ready;
      handler = AprsHandler(clock: () => now)..init();
      await handler.ready;
      expect(handler.outgoingMessages.single.state, AprsDelivery.paused);
      now = now.add(const Duration(hours: 1));
      await handler.processOutbox();
      expect(transmissions, hasLength(1));
      bus.dispatch(
        deviceId: 1,
        name: 'RetryAprsMessage',
        data: handler.outgoingMessages.single.id,
        store: false,
      );
      await handler.ready;
      expect(transmissions, hasLength(2));
      expect(handler.outgoingMessages.single.parts.single.attempts, 2);
    });

    test('unavailable or different radios do not consume attempts', () async {
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': radioId, 'MacAddress': 'replacement'},
        ],
      );
      await send();
      expect(transmissions, isEmpty);
      expect(handler.outgoingMessages.single.parts.single.attempts, 0);
      bus.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': radioId, 'MacAddress': 'original'},
        ],
      );
      await handler.processOutbox();
      expect(transmissions, hasLength(1));
    });

    test(
      'stop prevents retries, active manual retry is refused, and clear cannot resurrect',
      () async {
        await send();
        final id = handler.outgoingMessages.single.id;
        bus.dispatch(
          deviceId: 1,
          name: 'RetryAprsMessage',
          data: id,
          store: false,
        );
        await handler.ready;
        expect(transmissions, hasLength(1));
        bus.dispatch(
          deviceId: 1,
          name: 'StopAprsMessage',
          data: id,
          store: false,
        );
        await handler.ready;
        now = now.add(const Duration(hours: 1));
        await handler.processOutbox();
        expect(transmissions, hasLength(1));
        expect(handler.outgoingMessages.single.state, AprsDelivery.stopped);
        bus.dispatch(
          deviceId: 1,
          name: 'ClearAprsPackets',
          data: null,
          store: false,
        );
        await handler.ready;
        expect(await AprsOutboxStore().load(), isEmpty);
        handler.dispose();
        handler = AprsHandler(clock: () => now)..init();
        await handler.ready;
        expect(handler.outgoingMessages, isEmpty);
      },
    );

    test(
      'only a used RF path proves digipeating, not an internet or loopback echo',
      () async {
        await send();
        await frame(
          'N0CALL-7>APRS,WIDE1-1*::W1AW     :Hello{1',
          internet: true,
        );
        await frame(
          'N0CALL-7>APRS,WIDE1-1*::W1AW     :Hello{1',
          encoding: FragmentEncodingType.loopback,
        );
        await frame('N0CALL-7>APRS,WIDE1-1::W1AW     :Hello{1');
        expect(handler.outgoingMessages.single.state, AprsDelivery.sent);
        await frame('N0CALL-7>APRS,WIDE1-1*::W1AW     :Hello{1');
        expect(handler.outgoingMessages.single.state, AprsDelivery.digipeated);
        await frame('W1AW>APRS::N0CALL-7 :rej1');
        expect(handler.outgoingMessages.single.state, AprsDelivery.rejected);
      },
    );

    test('stale submission results cannot change a later attempt', () async {
      await send();
      final oldTag = transmissions.single.packet!.tag;
      now = now.add(const Duration(seconds: 30));
      await handler.processOutbox();
      bus.dispatch(
        deviceId: radioId,
        name: 'AprsTransmitResult',
        data: {'tag': oldTag, 'accepted': false, 'error': 'old failure'},
        store: false,
      );
      await handler.ready;
      expect(handler.outgoingMessages.single.parts.single.error, isNull);
      expect(handler.outgoingMessages.single.state, AprsDelivery.sent);
    });

    test(
      'authenticated messages require signed replies and never downgrade after key removal',
      () async {
        const station = AprsStationInfo(
          callsign: 'W1AW',
          isAprs: true,
          authPassword: 'test-key',
        );
        bus.dispatch(deviceId: 0, name: 'Stations', data: [station]);
        await send();
        await frame('W1AW>APRS::N0CALL-7 :ack1');
        expect(handler.outgoingMessages.single.state, AprsDelivery.sent);
        bus.dispatch(deviceId: 0, name: 'Stations', data: <AprsStationInfo>[]);
        now = now.add(const Duration(seconds: 30));
        await handler.processOutbox();
        expect(transmissions, hasLength(1));
        expect(handler.outgoingMessages.single.state, AprsDelivery.paused);
        handler.dispose();
        handler = AprsHandler(clock: () => now)..init();
        await handler.ready;
        expect(handler.outgoingMessages.single.state, AprsDelivery.paused);
        bus.dispatch(deviceId: 0, name: 'Stations', data: [station]);
        final auth = AprsAuth()
          ..stations = [
            const AprsStationInfo(
              callsign: 'N0CALL-7',
              isAprs: true,
              authPassword: 'test-key',
            ),
          ];
        final content = auth
            .addAprsAckAuth('W1AW', 'N0CALL-7', 'ack1', now)
            .content;
        await frame('W1AW>APRS:$content');
        expect(handler.outgoingMessages.single.state, AprsDelivery.delivered);
      },
    );

    test('RF auto-ACK preserves authentication for a zero-SSID sender', () async {
      bus.dispatch(deviceId: 0, name: 'Stations', data: [
        const AprsStationInfo(callsign: 'W1AW', isAprs: true, authPassword: 'test-key'),
      ]);
      final peer = AprsAuth()..stations = [
        const AprsStationInfo(callsign: 'N0CALL-7', isAprs: true, authPassword: 'test-key'),
      ];
      final content = peer.addAprsAuth('W1AW', 'N0CALL-7', 'signed hello', 123, now).content;
      final packet = Tnc2Codec.decode('W1AW>APRS:$content')!;
      bus.dispatch(deviceId: radioId, name: 'UniqueDataFrame', data: TncDataFragment(
        finalFragment: true, fragmentId: 0, data: packet.toByteArray(),
        channelId: 7, regionId: 0, channelName: 'APRS', incoming: true, time: now,
      ), store: false);
      await handler.ready;
      expect(transmissions, hasLength(1));
      final ack = transmissions.single.packet!;
      expect(AprsPacket.parse(ack)!.messageData.seqId, '123');
      expect(peer.checkAprsAuth(false, 'N0CALL-7', ack.dataStr, DateTime.now()), AuthState.success);
    });

    test('storage failure or invalid composition never transmits', () async {
      await send('hello\u00e9');
      expect(transmissions, isEmpty);
      expect(handler.outgoingMessages, isEmpty);
      await AppDatabase.close();
      await send();
      expect(transmissions, isEmpty);
      expect(handler.outgoingMessages, isEmpty);
      expect(DataBroker.getValueDynamic(1, 'AprsSendError', null), isA<Map>());
    });
  });
}
