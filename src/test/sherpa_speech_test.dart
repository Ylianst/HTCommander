import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/radio_speech.dart';
import 'package:htcommander/handlers/sherpa_speech_to_text_engine.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final model = Platform.environment['STT_MODEL_FIXTURE'];
  final vad = Platform.environment['STT_VAD_FIXTURE'];
  final nativeDirectory = Platform.environment['STT_NATIVE_LIBRARY_DIRECTORY'];

  test(
    'native VAD suppresses silence and Zipformer emits segment-tagged speech',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'htcommander-stt-test-',
      );
      final target = Directory(
        '${root.path}/models/streaming-zipformer-en-20M',
      );
      await target.create(recursive: true);
      final files = {
        'encoder.int8.onnx': 'encoder-epoch-99-avg-1.int8.onnx',
        'decoder.onnx': 'decoder-epoch-99-avg-1.onnx',
        'joiner.int8.onnx': 'joiner-epoch-99-avg-1.int8.onnx',
        'tokens.txt': 'tokens.txt',
      };
      for (final entry in files.entries) {
        await File('$model/${entry.value}').copy('${target.path}/${entry.key}');
      }
      await File(vad!).copy('${root.path}/models/silero_vad.onnx');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
      DataBroker.reset();
      DataBroker.dispatch(
        deviceId: 0,
        name: 'VoiceModel',
        data: 'streaming-zipformer-en',
      );
      final engine = SherpaSpeechToTextEngine();
      final errors = <String>[];
      final subscription = engine.diagnostics.listen((d) {
        if (d.error != null) errors.add(d.error!);
      });
      try {
        if (Platform.isWindows) {
          // Windows searches System32 before PATH. Preload the matching runtime
          // without modifying Flutter's installation or any shared DLLs.
          DynamicLibrary.open('$nativeDirectory\\onnxruntime.dll');
        }
        expect(
          await engine.initialize(localeId: 'en'),
          isTrue,
          reason: errors.join('\n'),
        );
        await engine.startSegment(
          segmentId: 100,
          hotwords: RadioSpeechVocabulary.hotwords('K6ABC'),
        );
        final silence = engine.results.firstWhere(
          (r) => r.isFinal && r.segmentId == 100,
        );
        await engine.processPcm16(
          Uint8List(32000 * 2 * 2),
          0,
          32000 * 2 * 2,
          32000,
        );
        await engine.completeSegment();
        expect(
          (await silence.timeout(const Duration(seconds: 30))).text,
          isEmpty,
        );

        sherpa.initBindings();
        final wave = sherpa.readWave('$model/test_wavs/0.wav');
        expect(wave.sampleRate, 16000);
        final sampleCount = wave.samples.length ~/ 512 * 512;
        final pcm = ByteData(sampleCount * 4);
        for (var i = 0; i < sampleCount; i++) {
          final sample = (wave.samples[i] * 32768).round().clamp(-32768, 32767);
          pcm.setInt16(i * 4, sample, Endian.little);
          pcm.setInt16(i * 4 + 2, sample, Endian.little);
        }
        await engine.startSegment(
          segmentId: 101,
          hotwords: RadioSpeechVocabulary.hotwords('K6ABC'),
        );
        final speech = engine.results.firstWhere(
          (r) => r.isFinal && r.segmentId == 101,
        );
        await engine.processPcm16(
          pcm.buffer.asUint8List(),
          0,
          pcm.lengthInBytes,
          32000,
        );
        await engine.completeSegment();
        final recognized = (await speech.timeout(
          const Duration(seconds: 30),
        )).text.trim();
        expect(recognized, isNotEmpty);
        await engine.startSegment(
          segmentId: 102,
          hotwords: RadioSpeechVocabulary.hotwords('K6ABC'),
        );
        final longSpeech = engine.results.firstWhere(
          (r) => r.isFinal && r.segmentId == 102,
        );
        for (var i = 0; i < 6; i++) {
          final drained = engine.diagnostics.firstWhere(
            (d) => d.queuedAudioMs == 0,
          );
          await engine.processPcm16(
            pcm.buffer.asUint8List(),
            0,
            pcm.lengthInBytes,
            32000,
          );
          await drained.timeout(const Duration(seconds: 30));
        }
        await engine.completeSegment();
        final longResult = await longSpeech.timeout(
          const Duration(seconds: 30),
        );
        expect(longResult.text.length, greaterThan(recognized.length * 3));
        await engine.startSegment(
          segmentId: 103,
          hotwords: RadioSpeechVocabulary.hotwords('K6ABC'),
        );
        final splitSpeech = engine.results.firstWhere(
          (r) => r.isFinal && r.segmentId == 103,
        );
        final drained = engine.diagnostics.firstWhere(
          (d) => d.queuedAudioMs == 0,
        );
        await engine.processPcm16(
          pcm.buffer.asUint8List(),
          0,
          pcm.lengthInBytes,
          32000,
        );
        await drained.timeout(const Duration(seconds: 30));
        await engine.splitSegment();
        await engine.completeSegment();
        expect(
          (await splitSpeech.timeout(const Duration(seconds: 30))).text.trim(),
          recognized,
        );
        expect(errors, isEmpty);
      } finally {
        await engine.dispose();
        await subscription.cancel();
        messenger.setMockMethodCallHandler(channel, null);
        DataBroker.reset();
        await root.delete(recursive: true);
      }
    },
    skip:
        model == null ||
            vad == null ||
            (Platform.isWindows && nativeDirectory == null)
        ? 'Set STT_MODEL_FIXTURE and STT_VAD_FIXTURE to local public model fixtures.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
