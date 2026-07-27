/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

MorseKeyHandler turns real-time key up/down events from a USB morse key (straight
or paddle) into a 700 Hz tone rendered as PCM. Because the radio is FM voice
(there is no CW "key down"), it decouples the tone gate from the transmitter: a
start gesture keys the transmitter up, silence is sent between elements, and an
idle tail timeout drops the transmitter.

Modes:
- off  : ignores key events.
- test : renders the sidetone locally only (no transmission).
- live : renders the sidetone locally AND streams the PCM to the radio.

The handler owns its own low-latency [PcmPlayer] for the operator's sidetone so
the monitor is not delayed by the ~1 s transmit pacing lead used for the radio.
*/

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../services/data_broker_client.dart';
import '../radio/morse_keyer.dart';
import '../radio/pcm_player.dart';

class MorseKeyHandler {
  final DataBrokerClient _broker = DataBrokerClient();

  // Audio format: 32 kHz mono, matching the radio audio path and PcmPlayer.
  static const int _sampleRate = 32000;

  /// Peak amplitude of the tone (well below full scale to avoid over-deviation
  /// when FM-modulated).
  static const int _amplitude = 16000;

  /// Attack/decay ramp length to avoid clicks at tone on/off edges.
  static const int _rampSamples = 160; // ~5 ms at 32 kHz

  /// How often the real-time PCM pump runs.
  static const Duration _pumpInterval = Duration(milliseconds: 20);

  /// Maximum window between two straight-key taps to count as the start gesture.
  static const int _doubleTapWindowMs = 400;

  /// Maximum time between releasing the two paddles to count as the paddle
  /// start gesture (both released "at the same time").
  static const int _paddleReleaseWindowMs = 150;

  bool _disposed = false;
  bool _initialized = false;

  MorseKeyMode _mode = MorseKeyMode.off;
  int _radioDeviceId = -1;
  MorseKeySettings _settings = const MorseKeySettings();

  final IambicKeyer _keyer = IambicKeyer();

  // Contact state. For a straight key only [_primaryDown] is used.
  bool _primaryDown = false;
  bool _secondaryDown = false;

  // Transmission (PCM-generation) state.
  bool _transmitting = false;
  int _lastActivityMs = 0;
  int? _lastTapMs;
  // Paddle start gesture: both paddles pressed then released together.
  bool _bothPaddlesWereDown = false;
  int? _firstPaddleReleaseMs;
  // Straight-key start gesture: armed on the second quick tap's press, fired on
  // its release.
  bool _straightStartPending = false;

  // Tone/pump state.
  Timer? _pumpTimer;
  final Stopwatch _stopwatch = Stopwatch();
  int _generatedSamples = 0;
  double _phase = 0.0; // radians
  double _envelope = 0.0; // 0..1, smooths tone edges
  int _unitSamples = 2560; // recomputed from wpm
  double _unitMs = 80.0; // recomputed from wpm (paddle decode timing)

  // Paddle per-sample segment state.
  int _segRemaining = 0;
  bool _segToneOn = false;

  // Morse decoding of what is being keyed, so the sent message can be shown as a
  // chat bubble at the end of a transmission.
  MorseDecoder? _decoder;
  bool _txWasLive = false;
  // Straight-key mark/space timing.
  int? _markStartMs;
  int? _lastUpMs;
  bool _straightHadMark = false;
  // Paddle decode accumulators.
  double _paddleSpaceUnits = 0;
  bool _paddleHadElement = false;

  // Local sidetone player.
  PcmPlayer? _player;
  bool _playerReady = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _broker.subscribe(
      deviceId: 0,
      name: 'MorseKeyMode',
      callback: _onModeChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MorseKeyInput',
      callback: _onInput,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MorseKeySettings',
      callback: _onSettings,
    );

    // Load any persisted settings.
    final stored = _broker.getValue<Map<dynamic, dynamic>>(
      0,
      'MorseKeySettings',
    );
    if (stored != null) {
      _settings = MorseKeySettings.fromJson(stored);
    }
    _applySettings();
    _dispatchState();
  }

  // ---------------------------------------------------------------------------
  // Broker event handlers
  // ---------------------------------------------------------------------------

  void _onSettings(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is Map) {
      _settings = MorseKeySettings.fromJson(data);
      _applySettings();
    }
  }

  void _applySettings() {
    _unitSamples = (_sampleRate * 1.2 / _settings.wpm).round().clamp(1, 1 << 20);
    _unitMs = 1.2 / _settings.wpm * 1000.0;
  }

  void _onModeChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! Map) return;
    final newMode = morseKeyModeFromString(data['mode'] as String?);
    final radioId = data['radioDeviceId'];
    if (radioId is int) _radioDeviceId = radioId;

    if (newMode == _mode) return;

    if (newMode == MorseKeyMode.off) {
      // Stop first (while the previous mode is still known) so a decoded bubble
      // and the transmit-finalize are emitted correctly.
      _stopTransmission(finalize: true);
      _mode = newMode;
      _resetKeys();
      _releasePlayer();
    } else {
      _mode = newMode;
      _ensurePlayer();
    }
    _dispatchState();
  }

  void _onInput(int deviceId, String name, Object? data) {
    if (_disposed || _mode == MorseKeyMode.off) return;
    if (data is! Map) return;
    final input = data['input'] as String?;
    final down = data['down'] == true;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final bool isPrimary = input == 'primary';
    final bool isSecondary = input == 'secondary';
    if (!isPrimary && !isSecondary) return;

    if (isPrimary) {
      if (down == _primaryDown) return; // ignore auto-repeat / duplicates
      _primaryDown = down;
    } else {
      if (down == _secondaryDown) return;
      _secondaryDown = down;
    }

    if (down) _lastActivityMs = nowMs;

    if (_settings.keyType == MorseKeyType.paddle) {
      if (_transmitting) {
        // Primary = dit lever, secondary = dah lever.
        if (isPrimary) {
          _keyer.setDit(down);
        } else {
          _keyer.setDah(down);
        }
      } else {
        // Arming: the start gesture is pressing both paddles and then releasing
        // them at nearly the same time. Do NOT feed the keyer while arming, so
        // no tone or processing happens until the transmission actually starts.
        final bool bothDown = _primaryDown && _secondaryDown;
        final bool bothUp = !_primaryDown && !_secondaryDown;
        if (bothDown) {
          _bothPaddlesWereDown = true;
          _firstPaddleReleaseMs = null;
        } else if (_bothPaddlesWereDown) {
          if (bothUp) {
            // The second paddle just came up: start only if both paddles were
            // released close together.
            final bool releasedTogether = _firstPaddleReleaseMs != null &&
                (nowMs - _firstPaddleReleaseMs!) <= _paddleReleaseWindowMs;
            _bothPaddlesWereDown = false;
            _firstPaddleReleaseMs = null;
            if (releasedTogether) _startTransmission();
          } else if (!down) {
            // One paddle released while the other is still held: the first
            // release of the squeeze.
            _firstPaddleReleaseMs = nowMs;
          }
        }
      }
    } else {
      // Straight key: only the primary contact is used. Start gesture is two
      // quick taps, and the transmission starts once the second tap is
      // released.
      if (!_transmitting) {
        if (down) {
          if (_lastTapMs != null &&
              (nowMs - _lastTapMs!) <= _doubleTapWindowMs) {
            // Second quick tap pressed: arm to start on its release.
            _lastTapMs = null;
            _straightStartPending = true;
          } else {
            _lastTapMs = nowMs;
            _straightStartPending = false;
          }
        } else if (_straightStartPending) {
          // The second tap was released: start now. The key is up, so the next
          // real press begins the first element.
          _straightStartPending = false;
          _startTransmission();
        }
      } else if (isPrimary) {
        // Feed the decoder from the key-down (mark) / key-up (space) timing.
        if (down) {
          if (_straightHadMark && _lastUpMs != null) {
            _decoder?.onSpace(nowMs - _lastUpMs!);
          }
          _markStartMs = nowMs;
        } else if (_markStartMs != null) {
          _decoder?.onMark(nowMs - _markStartMs!);
          _straightHadMark = true;
          _lastUpMs = nowMs;
        }
      }
    }

    _dispatchState();
  }

  // ---------------------------------------------------------------------------
  // Transmission lifecycle
  // ---------------------------------------------------------------------------

  void _startTransmission() {
    if (_transmitting) return;
    _transmitting = true;
    _txWasLive = _mode == MorseKeyMode.live;
    // Start from a clean keyer so no stale paddle memory leaks in.
    _keyer.reset();
    _generatedSamples = 0;
    _phase = 0.0;
    _envelope = 0.0;
    _segRemaining = 0;
    _segToneOn = false;
    // Reset the decoder and its timing state.
    _decoder = _settings.keyType == MorseKeyType.paddle
        ? MorseDecoder(fixedUnitMs: _unitMs.round())
        : MorseDecoder();
    _markStartMs = null;
    _lastUpMs = null;
    _straightHadMark = false;
    _straightStartPending = false;
    _paddleSpaceUnits = 0;
    _paddleHadElement = false;
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    _stopwatch
      ..reset()
      ..start();
    _ensurePlayer();
    _pumpTimer?.cancel();
    _pumpTimer = Timer.periodic(_pumpInterval, (_) => _pump());
    _broker.logInfo('[MorseKey] Transmission started (${morseKeyModeToString(_mode)})');
    _dispatchState();
  }

  void _stopTransmission({required bool finalize}) {
    if (!_transmitting) return;
    _transmitting = false;
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _stopwatch.stop();
    if (finalize && _txWasLive && _radioDeviceId > 0) {
      // Release the transmit hold so the radio finalizes the FM transmission.
      _broker.dispatch(
        deviceId: _radioDeviceId,
        name: 'TransmitVoicePCM',
        data: <String, Object?>{'hold': false},
        store: false,
      );
    }
    // Add a send-side chat bubble with whatever was decoded, for live
    // transmissions only (Test mode does not go on the air).
    final decoder = _decoder;
    _decoder = null;
    final decoded = decoder?.finish() ?? '';
    if (finalize && _txWasLive && _radioDeviceId > 0 && decoded.isNotEmpty) {
      _broker.dispatch(
        deviceId: _radioDeviceId,
        name: 'MorseKeyDecoded',
        data: <String, Object?>{
          'text': decoded,
          'keyType': morseKeyTypeToString(_settings.keyType),
          'wpm': decoder?.estimatedWpm,
        },
        store: false,
      );
      _broker.logInfo('[MorseKey] Decoded sent morse: "$decoded"');
    }
    _broker.logInfo('[MorseKey] Transmission stopped');
    _dispatchState();
  }

  void _resetKeys() {
    _primaryDown = false;
    _secondaryDown = false;
    _lastTapMs = null;
    _bothPaddlesWereDown = false;
    _firstPaddleReleaseMs = null;
    _straightStartPending = false;
    _keyer.reset();
  }

  // ---------------------------------------------------------------------------
  // Real-time PCM pump
  // ---------------------------------------------------------------------------

  void _pump() {
    if (_disposed || !_transmitting) return;

    // Generate exactly enough samples to stay in sync with the wall clock.
    final int elapsedMs = _stopwatch.elapsedMilliseconds;
    final int target = elapsedMs * _sampleRate ~/ 1000;
    int n = target - _generatedSamples;
    if (n <= 0) {
      _checkTail();
      return;
    }
    if (n > _sampleRate) n = _sampleRate; // cap a runaway catch-up to 1 s

    final pcm = Int16List(n);
    final bool paddle = _settings.keyType == MorseKeyType.paddle;
    final double phaseStep = 2 * math.pi * _settings.toneHz / _sampleRate;
    final double envStep = 1.0 / _rampSamples;

    for (int i = 0; i < n; i++) {
      bool toneOn;
      if (paddle) {
        if (_segRemaining <= 0) _advancePaddleSegment();
        toneOn = _segToneOn;
        _segRemaining--;
      } else {
        toneOn = _primaryDown;
      }

      // Smooth the tone envelope toward the target to avoid clicks.
      final double envTarget = toneOn ? 1.0 : 0.0;
      if (_envelope < envTarget) {
        _envelope = math.min(envTarget, _envelope + envStep);
      } else if (_envelope > envTarget) {
        _envelope = math.max(envTarget, _envelope - envStep);
      }

      final double s = math.sin(_phase) * _envelope * _amplitude;
      pcm[i] = s.toInt();
      _phase += phaseStep;
      if (_phase >= 2 * math.pi) _phase -= 2 * math.pi;
    }
    _generatedSamples += n;

    // Local low-latency sidetone (both test and live).
    if (_playerReady && _player != null) {
      // Fire and forget; the player queues internally.
      _player!.feed(pcm);
    }

    // Radio transmission (live only).
    if (_mode == MorseKeyMode.live && _radioDeviceId > 0) {
      final bytes = Uint8List.view(
        pcm.buffer,
        pcm.offsetInBytes,
        pcm.lengthInBytes,
      );
      _broker.dispatch(
        deviceId: _radioDeviceId,
        name: 'TransmitVoicePCM',
        data: <String, Object?>{
          'data': Uint8List.fromList(bytes),
          'playLocally': false,
          'hold': true,
        },
        store: false,
      );
    }

    _checkTail();
  }

  /// Advances the paddle tone/gap segment machine. A tone segment is always
  /// followed by a 1-unit inter-element gap; after a gap the next element is
  /// pulled from the keyer.
  void _advancePaddleSegment() {
    if (_segToneOn) {
      // Finished a tone -> inter-element gap.
      _segToneOn = false;
      _segRemaining = _unitSamples;
      _paddleSpaceUnits = 1; // the mandatory 1-unit inter-element gap
    } else {
      // Finished a gap (or idle) -> pull the next element.
      final el = _keyer.next();
      if (el == null) {
        _segToneOn = false;
        _segRemaining = _unitSamples; // idle silence, re-check next unit
        _paddleSpaceUnits += 1;
      } else {
        // A real element starts: feed the elapsed space, then the mark.
        if (_paddleHadElement) {
          _decoder?.onSpace((_paddleSpaceUnits * _unitMs).round());
        }
        _decoder?.onMark(
          ((el == MorseElement.dit ? 1 : 3) * _unitMs).round(),
        );
        _paddleHadElement = true;
        _paddleSpaceUnits = 0;
        _segToneOn = true;
        _segRemaining = el == MorseElement.dit ? _unitSamples : _unitSamples * 3;
      }
    }
  }

  /// Ends the transmission after the configured idle tail once all keying has
  /// stopped.
  void _checkTail() {
    if (!_transmitting) return;
    final bool paddle = _settings.keyType == MorseKeyType.paddle;
    final bool anyDown = _primaryDown || (paddle && _secondaryDown);
    if (anyDown) return;
    final bool keyerIdle = paddle ? (_keyer.idle && !_segToneOn) : true;
    if (!keyerIdle) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - _lastActivityMs) > _settings.tailMs) {
      _stopTransmission(finalize: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Local audio player
  // ---------------------------------------------------------------------------

  void _ensurePlayer() {
    if (_playerReady || _player != null) return;
    final player = PcmPlayer();
    _player = player;
    unawaited(() async {
      try {
        await player.setLogLevelError();
        await player.setup(sampleRate: _sampleRate, channelCount: 1);
        player.start();
        if (_player == player) _playerReady = true;
      } catch (e) {
        _broker.logError('[MorseKey] Failed to open sidetone player: $e');
      }
    }());
  }

  void _releasePlayer() {
    final player = _player;
    _player = null;
    _playerReady = false;
    if (player != null) {
      unawaited(player.release());
    }
  }

  // ---------------------------------------------------------------------------
  // State broadcast
  // ---------------------------------------------------------------------------

  void _dispatchState() {
    final bool keyDown =
        _primaryDown ||
        (_settings.keyType == MorseKeyType.paddle && _secondaryDown);
    _broker.dispatch(
      deviceId: 0,
      name: 'MorseKeyState',
      data: <String, Object?>{
        'mode': morseKeyModeToString(_mode),
        'transmitting': _transmitting,
        'keyDown': keyDown,
      },
      store: false,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _stopwatch.stop();
    _releasePlayer();
    _broker.dispose();
  }
}
