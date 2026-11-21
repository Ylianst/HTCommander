import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/handlers/speech_to_text_engine.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/db/comms_dao.dart';

class _SpeechEngine implements SpeechToTextEngine {
  final output = StreamController<SpeechResult>.broadcast();
  final status = StreamController<SpeechDiagnostics>.broadcast();
  final started = <int>[];
  int resets = 0;
  bool ready = false;
  Completer<bool>? initialization;
  final locales = <String>[];
  @override
  bool get isSupported => true;
  @override
  bool get isReady => ready;
  @override
  Stream<SpeechResult> get results => output.stream;
  @override
  Stream<bool> get processing => const Stream.empty();
  @override
  Stream<SpeechDiagnostics> get diagnostics => status.stream;
  @override
  Future<bool> initialize({String localeId = ''}) async {
    locales.add(localeId);
    return ready = initialization == null ? true : await initialization!.future;
  }

  @override
  Future<void> startSegment({
    required int segmentId,
    List<String> hotwords = const [],
  }) async {
    started.add(segmentId);
  }

  @override
  Future<void> processPcm16(
    Uint8List data,
    int offset,
    int length,
    int sampleRate,
  ) async {}
  @override
  Future<void> completeSegment() async {}
  @override
  Future<void> splitSegment() async {}
  @override
  Future<void> resetSegment() async {
    resets++;
  }

  @override
  Future<void> dispose() async {
    await output.close();
    await status.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SpeechEngine engine;
  late CommsHandler handler;
  late AppDatabase db;
  late DataBrokerClient client;
  final events = <({int device, Map data})>[];

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  void start(int device, String channel) => DataBroker.dispatch(
    deviceId: device,
    name: 'AudioDataStart',
    data: {'channelName': channel, 'transmit': false},
    store: false,
  );
  void end(int device) => DataBroker.dispatch(
    deviceId: device,
    name: 'AudioDataEnd',
    data: null,
    store: false,
  );
  Future<void> result(int id, String text, bool finalResult) async {
    engine.output.add(SpeechResult(text, finalResult, segmentId: id));
    await settle();
  }

  List<Map> history() =>
      (DataBroker.getValueDynamic(1, 'DecodedTextHistory') as List).cast<Map>();

  setUp(() async {
    DataBroker.reset();
    db = await AppDatabase.openInMemory();
    engine = _SpeechEngine();
    events.clear();
    client = DataBrokerClient();
    client.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TextReady',
      callback: (device, _, data) {
        if (data is Map) events.add((device: device, data: data));
      },
    );
    handler = CommsHandler(speechEngineFactory: () => engine)..init();
    await settle();
  });

  tearDown(() async {
    await handler.flush();
    handler.dispose();
    await settle();
    client.dispose();
    await AppDatabase.close();
    DataBroker.reset();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'configuration changes during initialization apply the latest settings',
    () async {
      DataBroker.dispatch(deviceId: 0, name: 'VoiceLanguage', data: 'auto');
      await settle();
      expect(engine.output.isClosed, isFalse);
      engine = _SpeechEngine()..initialization = Completer<bool>();
      DataBroker.dispatch(deviceId: 0, name: 'VoiceLanguage', data: 'en');
      await settle();
      expect(engine.locales, ['en']);
      final initializing = engine;
      engine = _SpeechEngine();
      DataBroker.dispatch(deviceId: 0, name: 'VoiceLanguage', data: 'ja');
      initializing.initialization!.complete(true);
      await settle();
      expect(engine.locales, ['ja']);
      expect(initializing.output.isClosed, isTrue);
    },
  );

  test(
    'late finals correct their own history entry without clearing newer speech',
    () async {
      start(2, 'Local');
      final first = engine.started.last;
      await result(first, 'Calling kilo six alpha', false);
      end(2);
      start(3, 'Satellite');
      final second = engine.started.last;
      await result(second, 'New transmission', false);
      await result(first, 'Calling kilo six alpha bravo charlie', true);
      expect(history(), hasLength(1));
      expect(history().single['text'], 'Calling K6ABC');
      expect(history().single['channel'], 'Local');
      expect(
        (DataBroker.getValueDynamic(1, 'CurrentDecodedTextEntry')
            as Map)['text'],
        'New transmission',
      );
      expect(events.last.device, 2);
      expect(events.last.data['updateKey'], events.first.data['updateKey']);
      end(3);
      await result(second, 'New transmission complete', true);
      await result(first, 'Duplicate callback', true);
      await handler.flush();
      final stored = await db.comms.recent(10);
      expect(stored, hasLength(2));
      expect(stored.first.originalText, 'Calling kilo six alpha bravo charlie');
      expect(stored.first.text, 'Calling K6ABC');
      expect(stored.last.channel, 'Satellite');
    },
  );

  test('provisional text is not inserted before a delayed final', () async {
    start(2, 'Local');
    final id = engine.started.last;
    await result(id, 'Partial', false);
    end(2);
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    expect(await db.comms.count(), 0);
    await result(id, 'Final corrected words', true);
    await handler.flush();
    expect((await db.comms.recent(10)).single.text, 'Final corrected words');
  });

  test('out-of-order batch finals retain transmission chronology', () async {
    start(2, 'First');
    final first = engine.started.last;
    end(2);
    await settle();
    start(3, 'Second');
    final second = engine.started.last;
    end(3);
    await result(second, 'Second transmission', true);
    await result(first, 'First transmission', true);
    expect(history().map((e) => e['text']), [
      'First transmission',
      'Second transmission',
    ]);
  });

  test(
    'original-text migration preserves previously stored messages',
    () async {
      await db.comms.insert(DecodedTextEntry(text: 'Existing message'));
      await db.db.execute('ALTER TABLE comms_events DROP COLUMN original_text');
      await CommsDao.addOriginalTextColumn(db.db);
      await db.comms.insert(
        DecodedTextEntry(
          text: 'K6ABC',
          originalText: 'kilo six alpha bravo charlie',
        ),
      );
      final rows = await db.comms.recent(10);
      expect(rows.first.text, 'Existing message');
      expect(rows.last.originalText, 'kilo six alpha bravo charlie');
    },
  );

  test(
    'Unicode results and empty finals release the segment without duplicates',
    () async {
      start(2, 'Local');
      final id = engine.started.last;
      await result(id, '你好，收到。', false);
      end(2);
      await result(id, '', true);
      await handler.flush();
      expect((await db.comms.recent(10)).single.text, '你好，收到。');
    },
  );

  test(
    'overload preserves available speech, rejects stale results and reports recovery',
    () async {
      start(2, 'Local');
      final id = engine.started.last;
      await result(id, 'Available words', false);
      engine.status.add(
        SpeechDiagnostics(
          segmentId: id,
          queuedAudioMs: 10000,
          overloaded: true,
          error: 'Overloaded',
        ),
      );
      await settle();
      expect(engine.resets, 1);
      await result(id, 'Stale words', true);
      expect(history().single['text'], 'Available words');
      engine.status.add(SpeechDiagnostics(segmentId: id, queuedAudioMs: 5000));
      await settle();
      await handler.flush();
      expect((await db.comms.recent(10)).single.text, 'Available words');
    },
  );

  test('clearing history discards delayed recognition callbacks', () async {
    start(2, 'Local');
    final id = engine.started.last;
    await result(id, 'Partial', false);
    DataBroker.dispatch(
      deviceId: 1,
      name: 'ClearVoiceText',
      data: null,
      store: false,
    );
    await result(id, 'Late final', true);
    expect(history(), isEmpty);
    expect(await db.comms.count(), 0);
  });

  test(
    'iOS exposes no local speech engine and does not initialize one',
    () async {
      await handler.flush();
      handler.dispose();
      await settle();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isRadioSpeechSupported, isFalse);
      final unsupported = createSpeechToTextEngine();
      expect(unsupported.isSupported, isFalse);
      await unsupported.dispose();
      engine = _SpeechEngine();
      handler = CommsHandler(speechEngineFactory: () => engine)..init();
      await settle();
      expect(engine.ready, isFalse);
      start(2, 'Local');
      expect(engine.started, isEmpty);
      await engine.dispose();
    },
  );
}
