// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/pcm_player.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_audio.dart';
import 'package:htcommander/sbc/radio_audio_codec.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

class _ListeningRadio extends Radio {
  _ListeningRadio() : super(deviceId: 9461, macAddress: 'AA:BB:CC:DD:EE:FF');

  @override
  bool isOnMuteChannel() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows native RX mirrors PCM without feeding the speaker twice',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final controls = <Map<Object?, Object?>>[];
      var speakerFeeds = 0;
      for (final name in [
        'com.htcommander/bluetooth_classic_data',
        'com.htcommander/bluetooth_classic_audio',
        'com.htcommander/pcm_player_feed',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.htcommander/bluetooth_classic'),
        (call) async {
          switch (call.method) {
            case 'configureNativeAudioPlayback':
              controls.add(Map<Object?, Object?>.from(call.arguments as Map));
              return true;
            case 'getNativeAudioPlaybackStats':
              return <String, Object>{'droppedSamples': 0, 'decodeErrors': 0};
            case 'connectAudio':
            case 'disconnectAudio':
              return true;
            default:
              throw StateError('Unexpected Bluetooth method ${call.method}');
          }
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.htcommander/pcm_player'),
        (call) async {
          if (call.method == 'feed') speakerFeeds++;
          return true;
        },
      );
      final radio = _ListeningRadio();
      final broker = DataBrokerClient();
      broker.dispatch(
        deviceId: 1,
        name: 'SelectedRadioDeviceId',
        data: radio.deviceId,
      );
      final audio = RadioAudio(
        radio: radio,
        deviceId: radio.deviceId,
        macAddress: radio.macAddress,
      );
      addTearDown(() async {
        await audio.dispose();
        radio.dispose();
        broker.dispose();
        DataBroker.clearDevice(radio.deviceId);
        PcmPlayer.playbackTap = null;
        debugDefaultTargetPlatformOverride = null;
      });
      final mirrored = Completer<void>();
      var mirrorSamples = 0;
      var consumerBytes = 0;
      PcmPlayer.playbackTap = (pcm, rate, channels) {
        expect(rate, 32000);
        expect(channels, 1);
        mirrorSamples += pcm.length;
        if (mirrorSamples == 3072) mirrored.complete();
      };
      broker.subscribe(
        deviceId: radio.deviceId,
        name: 'AudioDataAvailable',
        callback: (_, _, data) {
          consumerBytes += (data as Map)['length'] as int;
        },
      );
      await audio.start();
      expect(audio.isAudioEnabled, isTrue);
      expect(controls.last['enabled'], isTrue);
      expect(controls.last['muted'], isFalse);

      final codec = RadioAudioCodec();
      final encoded = codec.encode(Uint8List(6144), isDataFrame: false).data;
      codec.dispose();
      ServicesBinding.instance.channelBuffers.push(
        'com.htcommander/bluetooth_classic_audio',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'event': 'data',
          'address': radio.macAddress,
          'data': encoded,
        }),
        (_) {},
      );
      await mirrored.future.timeout(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(mirrorSamples, 3072);
      expect(consumerBytes, 6144);
      expect(speakerFeeds, 0);

      broker.dispatch(deviceId: radio.deviceId, name: 'SetMute', data: true);
      await pumpEventQueue();
      expect(controls.last['muted'], isTrue);
      await audio.stop();
      expect(controls.last['enabled'], isFalse);
    },
  );
}
