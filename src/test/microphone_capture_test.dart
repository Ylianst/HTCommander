import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/microphone_capture.dart';
import 'package:htcommander/services/shared_microphone.dart';
import 'package:record/record.dart';

/// Minimal in-memory stand-in for the native `record` plugin.
class _FakeRecordPlatform extends RecordPlatform {
  bool permission = true;

  /// Device ids that fail to open; `''` stands for the OS default device.
  final Set<String> failingDevices = <String>{};
  final List<String> openAttempts = <String>[];

  final Map<String, StreamController<RecordState>> _states =
      <String, StreamController<RecordState>>{};
  final Map<String, StreamController<Uint8List>> _pcm =
      <String, StreamController<Uint8List>>{};
  final Map<String, bool> _recording = <String, bool>{};

  StreamController<RecordState> _stateFor(String id) =>
      _states.putIfAbsent(id, () => StreamController<RecordState>.broadcast());

  /// Emits a PCM chunk on every active recorder.
  void emitPcm() {
    for (final c in _pcm.values) {
      if (!c.isClosed) c.add(Uint8List.fromList(<int>[1, 0, 2, 0]));
    }
  }

  /// Simulates Windows ending capture on a read error (device invalidated):
  /// a stop state event is sent but the PCM stream is left open.
  void loseDevice() {
    for (final id in _recording.keys.toList()) {
      if (_recording[id] == true) {
        _recording[id] = false;
        _stateFor(id).add(RecordState.stop);
      }
    }
  }

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permission;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    final String device = config.device?.id ?? '';
    openAttempts.add(device);
    if (failingDevices.contains(device)) {
      throw Exception('cannot open "$device"');
    }
    _pcm[recorderId] = StreamController<Uint8List>();
    _recording[recorderId] = true;
    scheduleMicrotask(() => _stateFor(recorderId).add(RecordState.record));
    return _pcm[recorderId]!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    if (_recording[recorderId] == true) {
      _recording[recorderId] = false;
      _stateFor(recorderId).add(RecordState.stop);
    }
    return null;
  }

  @override
  Future<void> cancel(String recorderId) => stop(recorderId);

  @override
  Future<bool> isRecording(String recorderId) async =>
      _recording[recorderId] ?? false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {
    _recording.remove(recorderId);
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const <InputDevice>[];

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _stateFor(recorderId).stream;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeRecordPlatform platform;

  setUp(() {
    platform = _FakeRecordPlatform();
    RecordPlatform.instance = platform;
  });

  test('reports permission denial distinctly', () async {
    platform.permission = false;
    final capture = MicrophoneCapture();
    expect(await capture.start((_) {}), isFalse);
    expect(capture.lastFailure, MicrophoneFailure.permissionDenied);
    await capture.dispose();
  });

  test('an unopenable device is reported as unavailable, not denied', () async {
    platform.failingDevices.add('');
    final capture = MicrophoneCapture();
    expect(await capture.start((_) {}), isFalse);
    expect(capture.lastFailure, MicrophoneFailure.deviceUnavailable);
    expect(
      SharedMicrophone.describeFailure(capture.lastFailure),
      isNot(contains('Grant access')),
    );
    await capture.dispose();
  });

  test('falls back to the default device only when allowed', () async {
    platform.failingDevices.add('usb-mic');

    final strict = MicrophoneCapture(deviceId: 'usb-mic');
    expect(await strict.start((_) {}), isFalse);
    expect(platform.openAttempts, <String>['usb-mic']);
    await strict.dispose();

    platform.openAttempts.clear();
    final lenient = MicrophoneCapture(
      deviceId: 'usb-mic',
      fallbackToDefault: true,
    );
    expect(await lenient.start((_) {}), isTrue);
    expect(platform.openAttempts, <String>['usb-mic', '']);
    expect(lenient.activeDeviceId, isNull);
    await lenient.dispose();
  });

  test('detects a lost device and can be restarted', () async {
    final capture = MicrophoneCapture();
    int lost = 0;
    capture.onCaptureLost = () => lost++;
    expect(await capture.start((_) {}), isTrue);
    await _settle();

    platform.loseDevice();
    await _settle();
    expect(lost, 1);
    expect(capture.isCapturing, isFalse);
    expect(capture.lastFailure, MicrophoneFailure.deviceUnavailable);

    expect(await capture.start((_) {}), isTrue);
    await _settle();
    await capture.stop();
    await _settle();
    expect(lost, 1, reason: 'a requested stop is not a lost device');
    await capture.dispose();
  });

  test('SharedMicrophone re-opens the microphone after it is lost', () async {
    final received = <int>[];
    final handle = await SharedMicrophone.instance.acquire(
      (pcm) => received.add(pcm.length),
    );
    expect(handle, isNotNull);
    await _settle();

    platform.loseDevice();
    await _settle();
    expect(SharedMicrophone.instance.isCapturing, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(SharedMicrophone.instance.isCapturing, isTrue);
    platform.emitPcm();
    await _settle();
    expect(received, isNotEmpty);

    await handle!.cancel();
    expect(SharedMicrophone.instance.isCapturing, isFalse);
  });
}
