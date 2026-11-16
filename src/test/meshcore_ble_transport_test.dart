// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/meshcore/meshcore_ble_transport.dart';
import 'package:htcommander/meshcore/meshcore_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.htcommander/bluetooth_classic');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const remoteId = 'AA:BB:CC:DD:EE:FF';

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('Windows MeshCore availability', skip: !Platform.isWindows, () {
    test('offline retries never reach pairing or GATT connection', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, {'address': remoteId});
        if (call.method != 'bleIsAvailable') {
          fail('Offline companion must not trigger ${call.method}');
        }
        return false;
      });

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          MeshCoreBleTransport.connect(remoteId),
          throwsA(
            isA<MeshCoreException>().having(
              (e) => e.toString(),
              'message',
              contains('not advertising'),
            ),
          ),
        );
      }
      expect(calls, ['bleIsAvailable', 'bleIsAvailable']);
    });

    test('advertising companion proceeds to normal PIN pairing', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'bleIsAvailable') return true;
        expect(call.method, 'blePair');
        expect(call.arguments, {'address': remoteId, 'pin': '123456'});
        return 'authFailed';
      });

      await expectLater(
        MeshCoreBleTransport.connect(remoteId, pin: '123456'),
        throwsA(isA<MeshCorePairingException>()),
      );
      expect(calls, ['bleIsAvailable', 'blePair']);
    });

    test('scan errors surface without attempting a connection', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'bleIsAvailable');
        throw PlatformException(code: 'BLE_SCAN_FAILED', message: 'Radio off');
      });
      await expectLater(
        MeshCoreBleTransport.connect(remoteId),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'BLE_SCAN_FAILED',
          ),
        ),
      );
    });

    test('cancelled availability check cannot proceed to pairing', () async {
      var cancelled = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'bleIsAvailable');
        cancelled = true;
        return true;
      });
      await expectLater(
        MeshCoreBleTransport.connect(remoteId, isCancelled: () => cancelled),
        throwsA(
          isA<MeshCoreException>().having(
            (e) => e.toString(),
            'message',
            contains('cancelled'),
          ),
        ),
      );
    });
  });
}
