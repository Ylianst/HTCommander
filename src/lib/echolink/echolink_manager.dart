/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// echolink_manager.dart - Wires the internet-only EchoLink radio (device 200)
// into the running application.
//
// This is the main-isolate glue that the unit-tested [EchoLinkClient] leaves
// out: it constructs the real dart:io network, reads the EchoLink settings,
// exposes UI commands over the Data Broker, plays received audio through the
// shared PCM player and re-emits it as AudioData* events so the existing
// CommsHandler records + transcribes it, and turns outgoing TransmitVoicePCM
// into GSM voice frames.
//
// EchoLink is deliberately NOT a physical radio: it is never added to device
// 1's `ConnectedRadios` aggregate (so the data tabs never target it) and never
// participates in the radio lock mechanism. Availability is advertised on its
// own device-1 `EchoLinkAvailable` flag so the radio panel can list it in the
// radio switcher.
//

import 'dart:async';
import 'dart:typed_data';

import '../radio/pcm_player.dart';
import '../services/data_broker_client.dart';
import 'echolink_client.dart';
import 'echolink_directory.dart';
import 'echolink_network_io.dart';
import 'echolink_station.dart';
import 'pcm_resampler.dart';

/// Owns the [EchoLinkClient] and bridges it to the app's Data Broker, audio
/// player and voice pipeline. Registered as a Data Broker handler in `main()`
/// on platforms with a dart:io audio + socket stack (desktop / mobile).
class EchoLinkManager {
  EchoLinkManager();

  /// App audio sample rate (matches the radio audio engine / CommsHandler).
  static const int _appSampleRate = 32000;

  /// Received-audio run is considered finished after this much silence, so the
  /// recorder / speech-to-text engine gets discrete transmissions instead of
  /// one endless run for the whole QSO.
  static const int _rxRunEndMs = 400;

  final DataBrokerClient _broker = DataBrokerClient();

  EchoLinkClient? _client;
  bool _initialized = false;
  bool _opened = false;
  bool _reconciling = false;

  // --- Received-audio playback + re-dispatch -------------------------------
  final PcmPlayer _player = PcmPlayer();
  bool _playerReady = false;
  int _bufferedFrames = 0;
  // Never let playback fall more than ~1 s behind real time.
  static const int _maxBufferedFrames = _appSampleRate;
  final LinearResampler _rxResampler = LinearResampler.up8kTo32k();
  bool _inRxRun = false;
  Timer? _rxEndTimer;
  int _rxRunStartMs = 0;

  // --- Transmit (app -> EchoLink) ------------------------------------------
  final LinearResampler _txResampler = LinearResampler.down32kTo8k();

  /// Subscribes to settings + UI commands and opens the client if a callsign is
  /// configured. Safe to call once.
  void init() {
    if (_initialized) return;
    _initialized = true;

    // UI commands, all addressed to the EchoLink device.
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkGoOnline',
      callback: _onGoOnline,
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkGoOffline',
      callback: _onGoOffline,
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkRefreshStations',
      callback: _onRefreshStations,
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkConnect',
      callback: _onConnect,
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkDisconnect',
      callback: _onDisconnect,
    );

    // Outgoing voice PCM (PTT / spoken text / Morse / DTMF) targeted at the
    // EchoLink device by the Comms tab and CommsHandler.
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'TransmitVoicePCM',
      callback: _onTransmitVoicePcm,
    );

    // Re-check when the callsign or EchoLink password is (un)configured. Both
    // must be set for EchoLink to be enabled; clearing either disables it.
    _broker.subscribe(
      deviceId: 0,
      name: 'CallSign',
      callback: (_, _, _) => unawaited(_reconcile()),
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'EchoLinkPassword',
      callback: (_, _, _) => unawaited(_reconcile()),
    );

    unawaited(_reconcile());
  }

  /// Enables or disables EchoLink to match the current settings. EchoLink is
  /// enabled only when both a callsign and a non-blank EchoLink password are
  /// configured; otherwise the client is closed and the feature is hidden (the
  /// app shows a "Disconnected" radio instead). Location is read when the client
  /// is opened; changing it later takes effect on the next open.
  Future<void> _reconcile() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      final String callsign =
          (_broker.getValue<String>(0, 'CallSign', '') ?? '')
              .trim()
              .toUpperCase();
      final String password =
          (_broker.getValue<String>(0, 'EchoLinkPassword', '') ?? '').trim();
      final bool shouldEnable = callsign.isNotEmpty && password.isNotEmpty;

      if (!shouldEnable) {
        // Missing callsign or password: tear down any live client and hide it.
        if (_client != null || _opened) {
          await _closeClient();
          _broker.logInfo('[EchoLink] Disabled (callsign/password cleared)');
        }
        _publishAvailable(false);
        return;
      }

      if (_opened) return; // Already enabled with valid settings.

      final String location =
          _broker.getValue<String>(0, 'EchoLinkLocation', '') ?? '';

      final EchoLinkClient client = EchoLinkClient(
        localCallsign: callsign,
        localPassword: password,
        localInfo: location,
        network: DartIoEchoLinkNetwork(),
      )..onAudio = _onRxAudio;

      _client = client;
      try {
        await client.open();
        _opened = true;
        _publishAvailable(true);
        _broker.logInfo('[EchoLink] Client opened for $callsign');
      } catch (e) {
        _client = null;
        _publishAvailable(false);
        _broker.logError('[EchoLink] Failed to open client: $e');
      }
    } finally {
      _reconciling = false;
    }
  }

  /// Tears down the live client (disconnecting any QSO), releases the audio
  /// device and resets the published EchoLink state so the panel clears.
  Future<void> _closeClient() async {
    final EchoLinkClient? client = _client;
    _client = null;
    _opened = false;
    _endRxRun();
    try {
      await client?.close();
    } catch (_) {}
    if (_playerReady) {
      try {
        await _player.release();
      } catch (_) {}
      _playerReady = false;
      _bufferedFrames = 0;
    }
    // Reset the device-200 state so any stale online/QSO/list indicators clear.
    // Stored (retained) to overwrite the values the client published.
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'State',
      data: 'Disconnected',
      store: true,
    );
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'ConnectedStation',
      data: null,
      store: true,
    );
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'StationList',
      data: const <Object?>[],
      store: true,
    );
  }

  /// Advertises whether EchoLink is available so the radio panel can list it in
  /// the radio switcher. Kept separate from `ConnectedRadios` on purpose. Stored
  /// (retained) so components that subscribe after startup still see it.
  void _publishAvailable(bool available) {
    _broker.dispatch(
      deviceId: 1,
      name: 'EchoLinkAvailable',
      data: available,
      store: true,
    );
  }

  // --- UI command handlers -------------------------------------------------

  void _onGoOnline(int deviceId, String name, Object? data) {
    final EchoLinkClient? client = _client;
    if (client == null) return;
    unawaited(() async {
      try {
        await client.goOnline();
        await client.refreshStations();
      } catch (e) {
        _broker.logError('[EchoLink] Go online failed: $e');
      }
    }());
  }

  void _onGoOffline(int deviceId, String name, Object? data) {
    final EchoLinkClient? client = _client;
    if (client == null) return;
    unawaited(() async {
      try {
        client.disconnect();
        await client.goOnline(status: DirectoryStatus.offline);
      } catch (e) {
        _broker.logError('[EchoLink] Go offline failed: $e');
      }
    }());
  }

  void _onRefreshStations(int deviceId, String name, Object? data) {
    final EchoLinkClient? client = _client;
    if (client == null) return;
    unawaited(() async {
      try {
        await client.refreshStations();
      } catch (e) {
        _broker.logError('[EchoLink] Refresh stations failed: $e');
      }
    }());
  }

  void _onConnect(int deviceId, String name, Object? data) {
    final EchoLinkClient? client = _client;
    if (client == null || data is! Map) return;
    final StationData station = _stationFromMap(data);
    if (station.ip.isEmpty) {
      _broker.logError('[EchoLink] Cannot connect: station has no address');
      return;
    }
    client.connectTo(station);
  }

  void _onDisconnect(int deviceId, String name, Object? data) {
    _client?.disconnect();
  }

  static StationData _stationFromMap(Map data) {
    StationStatus status = StationStatus.unknown;
    final Object? s = data['Status'] ?? data['status'];
    if (s is String) {
      status = StationStatus.values.firstWhere(
        (v) => v.name == s,
        orElse: () => StationStatus.unknown,
      );
    }
    return StationData(
      callsign: (data['Callsign'] ?? data['callsign'] ?? '') as String,
      description: (data['Description'] ?? data['description'] ?? '') as String,
      status: status,
      time: (data['Time'] ?? data['time'] ?? '') as String,
      id: (data['Id'] ?? data['id'] ?? 0) as int,
      ip: (data['Ip'] ?? data['ip'] ?? '') as String,
    );
  }

  // --- Received audio ------------------------------------------------------

  /// Called with 640 samples (80 ms) of 8 kHz decoded audio for each received
  /// voice packet. Resamples to the app rate, plays it, and re-emits it as an
  /// AudioData* run so the CommsHandler records + transcribes it.
  void _onRxAudio(Int16List pcm8k) {
    final Int16List pcm32 = _rxResampler.process(pcm8k);
    if (pcm32.isEmpty) return;

    unawaited(_playPcm(pcm32));

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_inRxRun) {
      _inRxRun = true;
      _rxRunStartMs = nowMs;
      _broker.dispatch(
        deviceId: echoLinkDeviceId,
        name: 'AudioDataStart',
        data: <String, Object?>{
          'startTime': _rxRunStartMs,
          'channelName': _rxChannelName(),
          'transmit': false,
          'muted': false,
          'usage': null,
        },
        store: false,
      );
    }

    final Uint8List bytes =
        pcm32.buffer.asUint8List(pcm32.offsetInBytes, pcm32.lengthInBytes);
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'AudioDataAvailable',
      data: <String, Object?>{
        'data': bytes,
        'offset': 0,
        'length': bytes.length,
        'channelName': _rxChannelName(),
        'transmit': false,
        'muted': false,
        'audioRunStartTime': _rxRunStartMs,
        'usage': null,
      },
      store: false,
    );

    _rxEndTimer?.cancel();
    _rxEndTimer = Timer(
      const Duration(milliseconds: _rxRunEndMs),
      _endRxRun,
    );
  }

  void _endRxRun() {
    _rxEndTimer?.cancel();
    _rxEndTimer = null;
    if (!_inRxRun) return;
    _inRxRun = false;
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'AudioDataEnd',
      data: <String, Object?>{
        'startTime': _rxRunStartMs,
        'transmit': false,
        'usage': null,
      },
      store: false,
    );
  }

  String _rxChannelName() => _client?.connectedStation?.callsign ?? 'EchoLink';

  Future<void> _playPcm(Int16List pcm) async {
    if (!_playerReady) {
      await _initPlayer();
      if (!_playerReady) return;
    }
    if (_bufferedFrames > _maxBufferedFrames) return; // fell behind; drop
    _bufferedFrames += pcm.length;
    try {
      await _player.feed(pcm);
    } catch (_) {
      // Playback is best-effort; ignore feed errors.
    }
  }

  Future<void> _initPlayer() async {
    if (_playerReady) return;
    try {
      await _player.setLogLevelError();
      await _player.setup(sampleRate: _appSampleRate, channelCount: 1);
      await _player.setFeedThreshold(_appSampleRate ~/ 8);
      _player.setFeedCallback((remaining) => _bufferedFrames = remaining);
      _player.start();
      _playerReady = true;
    } catch (e) {
      _broker.logError('[EchoLink] PCM player init failed: $e');
    }
  }

  // --- Transmit audio ------------------------------------------------------

  /// Turns outgoing 32 kHz voice PCM (PTT / spoken text / Morse / DTMF) into
  /// 8 kHz GSM voice frames on the active QSO. `{hold: false}` without data
  /// marks the end of a push-to-talk burst.
  void _onTransmitVoicePcm(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final Object? bytes = data['data'] ?? data['Data'];
    if (bytes is! Uint8List) {
      // End-of-transmission marker: reset the resampler phase for the next one.
      final bool hold = (data['hold'] ?? data['Hold']) as bool? ?? true;
      if (!hold) _txResampler.reset();
      return;
    }
    final EchoLinkClient? client = _client;
    if (client == null) return;

    final Int16List pcm32 = _int16FromBytes(bytes);
    final Int16List pcm8k = _txResampler.process(pcm32);
    if (pcm8k.isNotEmpty) client.sendAudio(pcm8k);

    final bool hold = (data['hold'] ?? data['Hold']) as bool? ?? true;
    if (!hold) _txResampler.reset();
  }

  static Int16List _int16FromBytes(Uint8List bytes) {
    if (bytes.offsetInBytes.isEven && bytes.lengthInBytes.isEven) {
      return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    }
    final int count = bytes.length ~/ 2;
    final Int16List out = Int16List(count);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  /// Releases sockets and the audio device.
  Future<void> dispose() async {
    _rxEndTimer?.cancel();
    _broker.dispose();
    try {
      await _client?.close();
    } catch (_) {}
    if (_playerReady) {
      try {
        await _player.release();
      } catch (_) {}
      _playerReady = false;
    }
  }
}
