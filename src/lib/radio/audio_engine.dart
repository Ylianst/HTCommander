/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart'
    show
        BackgroundIsolateBinaryMessenger,
        MethodChannel,
        RootIsolateToken;

import '../sbc/sbc_decoder.dart';
import '../sbc/sbc_encoder.dart';
import '../sbc/sbc_enums.dart';
import '../sbc/sbc_frame.dart';

/// The CPU-heavy audio DSP engine that runs in a dedicated background isolate,
/// off the Flutter UI isolate.
///
/// It owns the SBC decoder/encoder and the WAV recorder, and it runs the
/// transmit pacing loop. It performs **no platform-channel calls** — background
/// isolates cannot receive messages from the host platform (no EventChannel
/// streams, no method-call handlers), so anything touching a plugin (the PCM
/// player, Bluetooth) stays on the main-isolate host ([RadioAudio]). The engine
/// emits finished PCM via a `play` event for the host to feed to the speaker,
/// and emits framed transmit bytes via a `send` event for the host to write to
/// Bluetooth.
///
/// The engine is intentionally a near-verbatim move of the receive/transmit DSP
/// that used to live inline in `RadioAudio`, so its behaviour matches the
/// original single-isolate implementation exactly — only *where* it runs, and
/// how it talks to the outside world (messages instead of direct broker/radio
/// calls), has changed.
class AudioEngine {
  // Named params can't be private, so `btSend` is copied into `_btSend`.
  AudioEngine(this._emit, {Future<void> Function(Uint8List data)? btSend})
      // ignore: prefer_initializing_formals
      : _btSend = btSend;

  /// Audio format: 32 kHz, 16-bit, mono (matches the radio's SBC stream).
  static const int _sampleRate = 32000;

  /// Safety cap on the receive accumulator before it is reset (64 KB).
  static const int _maxAccumulatorSize = 64 * 1024;

  /// PCM bytes consumed per encoded SBC frame: blocks * subbands * 2 (16-bit).
  static const int _pcmInputSizePerFrame = 16 * 8 * 2; // 256 bytes

  /// Transmit pacing lead: how far (in ms of audio) the encoder may run ahead of
  /// real time before throttling. A deeper lead pre-delivers more audio to the
  /// radio, so a stall on the native platform thread — most notably a Windows
  /// window-resize/move modal loop, which blocks the Bluetooth writes even
  /// though they originate from this background isolate — is far less likely to
  /// starve the radio's playout buffer and corrupt the transmission.
  ///
  /// Live voice PTT keeps a short lead to stay low-latency. Bulk pre-computed
  /// transmissions (SSTV image, DART data) use a much deeper lead since their
  /// latency doesn't matter. The effective depth is still bounded by the OS /
  /// radio Bluetooth buffering and RFCOMM flow control, so a large value simply
  /// fills those as deep as they allow (it never sends faster than the link
  /// accepts). Tunable if a radio needs more or less headroom.
  static const int _txLeadMsVoice = 1000;
  static const int _txLeadMsBulk = 10000;

  /// Pre-computed *voice* transmissions (spoken text / WAV playback) use a
  /// shallow lead: unlike data, a brief stall only causes a small audible
  /// glitch rather than corrupting the payload, and keeping only a couple of
  /// seconds buffered at the radio means Cancel stops the transmission quickly
  /// instead of waiting for a deep buffer to drain.
  static const int _txLeadMsBulkVoice = 2000;

  /// A single transmit chunk at least this large (~2 s of 32 kHz/16-bit mono) is
  /// treated as a bulk, pre-computed transmission and gets the deep pacing lead.
  static const int _bulkChunkThresholdBytes = _sampleRate * 2 * 2;

  /// Frame that tells the radio to stop transmitting.
  static final Uint8List _endAudioFrame = Uint8List.fromList(<int>[
    0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e,
  ]);

  /// Sends an event message to the host isolate.
  final void Function(Map<String, Object?> msg) _emit;

  /// Writes framed transmit bytes straight to Bluetooth from this isolate.
  ///
  /// When non-null (the normal case), paced transmit frames bypass the main
  /// isolate entirely, so UI jank (window drags, tab switches) can no longer
  /// stall the real-time audio stream. When null (platform has no
  /// RootIsolateToken, e.g. web), [_sendAudio] falls back to relaying the bytes
  /// to the host via a `send` event.
  final Future<void> Function(Uint8List data)? _btSend;

  final SbcDecoder _sbcDecoder = SbcDecoder();
  final SbcEncoder _sbcEncoder = SbcEncoder();

  final List<int> _accumulator = <int>[];

  double _outputVolume = 1.0;
  bool _isMuted = false;

  // Audio-run state tracking (a "run" is a continuous burst of audio).
  bool _inAudioRun = false;
  bool _inAudioRunIsTransmit = false;
  int _audioRunStartMs = 0;

  // Radio state pushed from the host (updated on HtStatus changes).
  String _channelName = '';
  bool _muteChannel = false;

  // Optional WAV recording of received audio.
  _WavRecorder? _recorder;

  // Encoder frame configuration (matches the radio's 32 kHz / mono SBC format).
  late final SbcFrame _encoderFrame = SbcFrame()
    ..frequency = SbcFrequency.freq32K
    ..blocks = 16
    ..mode = SbcMode.mono
    ..allocationMethod = SbcBitAllocationMethod.loudness
    ..subbands = 8
    // Experimental: raised from the radio's default 18 to test whether the
    // firmware accepts a higher-quality SBC stream. Confirmed working at 40
    // over the air; 124 (the codec max) was rejected.
    ..bitpool = 40;

  // --- Transmit state ---
  final Queue<Uint8List> _pcmQueue = Queue<Uint8List>();
  bool _isTransmitting = false;
  bool _voiceTransmitCancel = false;
  bool _playInputBack = false;
  bool _voiceTransmitIsDataFrame = false;
  bool _voiceTransmitHold = false;
  Uint8List? _reminderTransmitPcm;
  Completer<void>? _newDataSignal;

  // --- Local monitor playback pacing ---
  // When a transmission is monitored locally (playLocally), the SBC encoder
  // runs far ahead of real time (see [_txLeadMsBulk]) so the whole clip is
  // handed to the speaker almost instantly. The host caps playback buffering
  // (~800 ms) and drops the overflow, which cut the tail off spoken audio. To
  // fix that, monitor PCM is queued here and emitted to the host at real time,
  // decoupled from the transmit lead, so the entire clip plays out.
  final Queue<Int16List> _monitorChunks = Queue<Int16List>();
  bool _monitorPumping = false;
  Completer<void>? _monitorNewData;

  // Keep the speaker this far ahead of the wall clock so it never underruns,
  // while staying well under the host's playback drop cap.
  static const int _monitorLeadMs = 200;

  // ---------------------------------------------------------------------------
  // Command dispatch (messages from the host isolate)
  // ---------------------------------------------------------------------------

  Future<void> handleCommand(Map<Object?, Object?> msg) async {
    final String cmd = (msg['cmd'] as String?) ?? '';
    switch (cmd) {
      case 'init':
        _outputVolume = (msg['volume'] as num?)?.toDouble() ?? 1.0;
        _isMuted = (msg['muted'] as bool?) ?? false;
        _emit(<String, Object?>{'evt': 'ready'});
        break;
      case 'reset':
        _sbcDecoder.reset();
        _accumulator.clear();
        break;
      case 'stopAudio':
        _stopAudio();
        break;
      case 'rx':
        final Uint8List? bytes = _unwrap(msg['bytes']);
        if (bytes != null) _onAudioData(bytes);
        break;
      case 'setVolume':
        _outputVolume = (msg['value'] as num?)?.toDouble() ?? _outputVolume;
        break;
      case 'setMute':
        _isMuted = (msg['value'] as bool?) ?? _isMuted;
        break;
      case 'startRecording':
        final String? filename = msg['filename'] as String?;
        if (filename != null && filename.isNotEmpty) {
          _recorder?.close();
          _recorder = _WavRecorder(filename, _sampleRate);
        }
        break;
      case 'stopRecording':
        _recorder?.close();
        _recorder = null;
        break;
      case 'tx':
        final Uint8List? pcm = _unwrap(msg['pcm']);
        final bool playLocally = (msg['playLocally'] as bool?) ?? false;
        final bool? hold = msg['hold'] as bool?;
        final bool isDataFrame = (msg['isDataFrame'] as bool?) ?? false;
        if (hold != null) _voiceTransmitHold = hold;
        if (pcm != null && pcm.isNotEmpty) {
          transmitVoice(pcm, 0, pcm.length, playLocally,
              isDataFrame: isDataFrame);
        }
        break;
      case 'txHold':
        final bool hold = (msg['hold'] as bool?) ?? false;
        _voiceTransmitHold = hold;
        // Releasing the hold wakes the transmit loop so it can drain and end
        // the audio run.
        if (!hold) _signalNewData();
        break;
      case 'cancelTx':
        cancelVoiceTransmit();
        break;
      case 'radioState':
        _channelName = (msg['channelName'] as String?) ?? _channelName;
        _muteChannel = (msg['muteChannel'] as bool?) ?? _muteChannel;
        break;
      case 'shutdown':
        _shutdown();
        break;
    }
  }

  void _shutdown() {
    _stopAudio();
    _recorder?.close();
    _recorder = null;
  }

  /// Abort any in-progress transmission and end an open receive audio run.
  /// Mirrors the old `RadioAudio.stop()` audio-abort logic.
  void _stopAudio() {
    _voiceTransmitHold = false;
    _voiceTransmitCancel = true;
    _signalNewData();
    _pcmQueue.clear();
    _reminderTransmitPcm = null;

    // End an in-progress receive run (a transmit run is finalized by the
    // transmit loop's `finally`).
    if (_inAudioRun && !_inAudioRunIsTransmit) {
      _inAudioRun = false;
      _dispatchAudioDataEnd();
    }
    _accumulator.clear();
  }

  // ---------------------------------------------------------------------------
  // Playback: hand finished PCM to the host, which owns the audio device.
  // ---------------------------------------------------------------------------

  void _emitPlay(Int16List pcm) {
    _emit(<String, Object?>{
      'evt': 'play',
      'pcm': _wrap(pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes)),
    });
  }

  // Queues locally-monitored transmit PCM for real-time playback and starts the
  // pacing pump if it is not already running.
  void _enqueueMonitor(Int16List pcm) {
    if (pcm.isEmpty) return;
    _monitorChunks.add(pcm);
    final Completer<void>? c = _monitorNewData;
    if (c != null && !c.isCompleted) c.complete();
    if (!_monitorPumping) {
      _monitorPumping = true;
      _monitorPumpLoop();
    }
  }

  // Emits queued monitor PCM to the host at real time (32 kHz mono), keeping a
  // small [_monitorLeadMs] lead so playback never underruns. Continues draining
  // any audio the encoder produced ahead of time until the queue empties and
  // the transmission has finished (or is cancelled).
  Future<void> _monitorPumpLoop() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    int emittedSamples = 0;
    try {
      while (true) {
        if (_voiceTransmitCancel) {
          _monitorChunks.clear();
          break;
        }
        if (_monitorChunks.isEmpty) {
          // Nothing queued: stop once the transmission is over, otherwise wait
          // briefly for the encoder to produce more.
          if (!_isTransmitting) break;
          _monitorNewData = Completer<void>();
          await Future.any(<Future<void>>[
            _monitorNewData!.future,
            Future<void>.delayed(const Duration(milliseconds: 20)),
          ]);
          _monitorNewData = null;
          continue;
        }
        final Int16List chunk = _monitorChunks.removeFirst();
        _emitPlay(chunk);
        emittedSamples += chunk.length;

        // Pace to real time, staying [_monitorLeadMs] ahead of the wall clock.
        final int targetMs = (emittedSamples * 1000) ~/ _sampleRate;
        final int waitMs = targetMs - stopwatch.elapsedMilliseconds - _monitorLeadMs;
        if (waitMs > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: waitMs < 100 ? waitMs : 100),
          );
        }
      }
    } finally {
      _monitorPumping = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Receive loop
  // ---------------------------------------------------------------------------

  void _onAudioData(Uint8List data) {
    _accumulator.addAll(data);

    if (_accumulator.length > _maxAccumulatorSize) {
      _log('Accumulator overflow (${_accumulator.length} bytes), resetting.');
      _accumulator.clear();
      return;
    }

    Uint8List? frame;
    while ((frame = _extractData()) != null) {
      final Uint8List uframe = _unescapeBytes(frame!);
      if (uframe.isEmpty) break;

      switch (uframe[0]) {
        case 0x00: // Received audio (odd)
        case 0x03: // Received audio
          if (_inAudioRun && _inAudioRunIsTransmit) return;
          if (!_inAudioRun) {
            _inAudioRun = true;
            _inAudioRunIsTransmit = false;
            _dispatchAudioDataStart(false);
          }
          _decodeSbcFrame(uframe, 1, uframe.length - 1, false);
          break;
        case 0x01: // Audio end
          if (_inAudioRun) {
            _inAudioRun = false;
            _dispatchAudioDataEnd();
          }
          break;
        case 0x02: // Audio ACK
          break;
        case 0x09: // Transmit audio (echo) - decoded for metering, not played
          if (_inAudioRun && !_inAudioRunIsTransmit) return;
          if (!_inAudioRun) {
            _inAudioRun = true;
            _inAudioRunIsTransmit = true;
            _dispatchAudioDataStart(true);
          }
          _decodeSbcFrame(uframe, 1, uframe.length - 1, true);
          break;
        default:
          _log('Unknown command: ${uframe[0]}');
          break;
      }
    }
  }

  /// Extract the next `0x7e`-delimited frame from [_accumulator], consuming the
  /// bytes up to and including the closing marker. Returns null if no complete
  /// frame is available yet.
  Uint8List? _extractData() {
    while (true) {
      final int len = _accumulator.length;
      if (len < 2) return null;

      // Skip past leading consecutive 0x7e bytes, keeping the last as start.
      int scanFrom = 0;
      if (len >= 2 && _accumulator[0] == 0x7e && _accumulator[1] == 0x7e) {
        scanFrom = 1;
      }

      int start = -1;
      int end = -1;
      for (int i = scanFrom; i < len; i++) {
        if (_accumulator[i] == 0x7e) {
          if (start == -1) {
            start = i;
          } else {
            end = i;
            break;
          }
        }
      }

      if (start != -1 && end != -1 && end > start + 1) {
        final Uint8List extracted = Uint8List.fromList(
          _accumulator.sublist(start + 1, end),
        );
        _accumulator.removeRange(0, end + 1);
        return extracted;
      } else if (start != -1 && end != -1 && end == start + 1) {
        // Two consecutive 0x7e: discard everything up to the first, keep the
        // second as a potential start marker for the next frame.
        _accumulator.removeRange(0, end);
        continue;
      } else if (start > 0) {
        // Discard garbage bytes before the first 0x7e marker.
        _accumulator.removeRange(0, start);
        continue;
      } else if (start == -1) {
        // No marker at all - discard everything as garbage.
        _accumulator.clear();
        return null;
      } else {
        // Only a start marker found, no end yet - wait for more data.
        return null;
      }
    }
  }

  /// Unescape `0x7d`-escaped bytes (next byte XOR 0x20) into a new buffer.
  Uint8List _unescapeBytes(Uint8List buffer) {
    if (buffer.isEmpty) return buffer;
    final Uint8List out = Uint8List(buffer.length);
    int dst = 0;
    int src = 0;
    final int end = buffer.length;
    while (src < end) {
      if (buffer[src] == 0x7d) {
        src++;
        if (src < end) {
          out[dst++] = buffer[src] ^ 0x20;
        } else {
          break;
        }
      } else {
        out[dst++] = buffer[src];
      }
      src++;
    }
    return Uint8List.sublistView(out, 0, dst);
  }

  /// Decode one or more concatenated SBC frames starting at [start] for
  /// [length] bytes, play/record/emit the resulting PCM.
  void _decodeSbcFrame(
    Uint8List sbcFrame,
    int start,
    int length,
    bool isTransmit,
  ) {
    if (sbcFrame.isEmpty) return;

    try {
      int offset = start;
      int remaining = length;
      final List<int> samples = <int>[];

      while (remaining > 0) {
        // SBC frames start with 0x9C, mSBC with 0xAD.
        final int syncByte = sbcFrame[offset];
        if (syncByte != 0x9C && syncByte != 0xAD) break;

        if (remaining < SbcFrame.headerSize) break;
        final Uint8List header = Uint8List.sublistView(
          sbcFrame,
          offset,
          offset + SbcFrame.headerSize,
        );
        final SbcFrame? probed = _sbcDecoder.probe(header);
        if (probed == null) break;
        final int frameSize = probed.getFrameSize();
        if (frameSize <= 0 || frameSize > remaining) break;

        final Uint8List sbcData = Uint8List.sublistView(
          sbcFrame,
          offset,
          offset + frameSize,
        );
        final result = _sbcDecoder.decode(sbcData);
        if (!result.success) break;
        if (result.frame.getFrameSize() != frameSize) break;

        samples.addAll(result.pcmLeft);

        offset += frameSize;
        remaining -= frameSize;
      }

      if (samples.isEmpty) return;

      // Audio on a muted channel is neither played on the speaker nor recorded,
      // but it is still reported to the host so subscribers can tell which
      // channel/VFO the frames came from.
      final bool isOnMuteChannel = _muteChannel;

      if (!isOnMuteChannel) {
        if (!_isMuted && !isTransmit) {
          // Scale by output volume for playback (software volume control).
          final Int16List playbackPcm = Int16List(samples.length);
          for (int i = 0; i < samples.length; i++) {
            int v = (samples[i] * _outputVolume).round();
            if (v > 32767) {
              v = 32767;
            } else if (v < -32768) {
              v = -32768;
            }
            playbackPcm[i] = v;
          }
          _emitPlay(playbackPcm);
        }
        _recorder?.write(Int16List.fromList(samples));
      }

      // Emit raw (unscaled) PCM bytes to the host.
      final Uint8List pcmBytes = Int16List.fromList(
        samples,
      ).buffer.asUint8List();
      _dispatchAudioDataAvailable(
        pcmBytes,
        pcmBytes.length,
        isTransmit,
        isOnMuteChannel,
      );

      // Output amplitude (after conceptual volume) for metering.
      final double amplitude = _calculatePcmAmplitude(samples) * _outputVolume;
      _emit(<String, Object?>{'evt': 'amplitude', 'value': amplitude});
    } catch (e) {
      _log('SBC decode error: $e');
    }
  }

  static double _calculatePcmAmplitude(List<int> samples) {
    if (samples.isEmpty) return 0.0;
    int max = 0;
    for (final s in samples) {
      final int a = s < 0 ? -s : s;
      if (a > max) max = a;
    }
    final double amp = max / 32768.0;
    return amp > 1.0 ? 1.0 : amp;
  }

  // ---------------------------------------------------------------------------
  // Transmit (SBC encode) path
  // ---------------------------------------------------------------------------

  /// Queue [length] bytes of 32 kHz / 16-bit / mono PCM (starting at [offset])
  /// for transmission to the radio. When [play] is true the audio is also
  /// played back locally as it is sent.
  bool transmitVoice(
    Uint8List pcmInput,
    int offset,
    int length,
    bool play, {
    bool isDataFrame = false,
  }) {
    _playInputBack = play;
    _voiceTransmitCancel = false;
    // The data-frame flag applies to a whole transmission run; only latch it
    // when a fresh run is about to start.
    if (!_isTransmitting) _voiceTransmitIsDataFrame = isDataFrame;
    _pcmQueue.add(
      Uint8List.fromList(
        Uint8List.sublistView(pcmInput, offset, offset + length),
      ),
    );

    if (_isTransmitting) _signalNewData();
    _startTransmissionIfNeeded();
    return true;
  }

  /// Abort an in-progress transmission and tell the radio to stop transmitting.
  void cancelVoiceTransmit() {
    _voiceTransmitHold = false;
    _voiceTransmitCancel = true;
    _signalNewData();
    _pcmQueue.clear();
    _reminderTransmitPcm = null;
    _sendAudio(_endAudioFrame);
  }

  void _signalNewData() {
    final Completer<void>? c = _newDataSignal;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _startTransmissionIfNeeded() {
    if (_isTransmitting) return;
    _isTransmitting = true;
    _transmissionLoop();
  }

  Future<void> _transmissionLoop() async {
    _dispatchVoiceTransmitStateChanged(true);
    try {
      while (!_voiceTransmitCancel) {
        if (_pcmQueue.isNotEmpty) {
          await _processPcmData(_pcmQueue.removeFirst());
        } else {
          // Wait briefly for more data. While a PTT stream is held open keep
          // the audio run alive across gaps; otherwise end once the queue is
          // empty so the audio run is finalized.
          _newDataSignal = Completer<void>();
          await Future.any(<Future<void>>[
            _newDataSignal!.future,
            Future<void>.delayed(const Duration(milliseconds: 100)),
          ]);
          _newDataSignal = null;
          if (_pcmQueue.isEmpty && !_voiceTransmitHold) break;
        }
      }
    } catch (e) {
      _log('Voice transmit error: $e');
    } finally {
      if (_inAudioRun && _inAudioRunIsTransmit) {
        _inAudioRun = false;
        _dispatchAudioDataEnd();
      }
      _reminderTransmitPcm = null;
      await _sendAudio(_endAudioFrame);
      _dispatchVoiceTransmitStateChanged(false);
      _isTransmitting = false;
    }
  }

  Future<void> _processPcmData(Uint8List incoming) async {
    if (!_inAudioRun) {
      _inAudioRun = true;
      _inAudioRunIsTransmit = true;
      _dispatchAudioDataStart(true);
    }

    // Prepend any leftover bytes from the previous chunk.
    Uint8List pcmData = incoming;
    final Uint8List? reminder = _reminderTransmitPcm;
    if (reminder != null) {
      final Uint8List merged = Uint8List(reminder.length + incoming.length);
      merged.setRange(0, reminder.length, reminder);
      merged.setRange(reminder.length, merged.length, incoming);
      pcmData = merged;
      _reminderTransmitPcm = null;
    }

    int pcmOffset = 0;
    int pcmLength = pcmData.length;

    // Real-time pacing: 32 kHz, 16-bit, mono = 64000 bytes/sec.
    const int bytesPerSecond = _sampleRate * 2;
    // Pick how far ahead of real time this transmission may run:
    //  - Data frames (SSTV / DART) are corruption-sensitive, so they keep the
    //    deep lead that rides out platform-thread stalls (e.g. a window resize
    //    that blocks Bluetooth writes).
    //  - Large pre-computed voice clips (spoken text / WAV) only glitch on a
    //    stall, so they use a shallow lead so Cancel stops them quickly.
    //  - Live PTT voice arrives as small streamed chunks and stays low-latency.
    final int txLeadMs;
    if (_voiceTransmitIsDataFrame) {
      txLeadMs = _txLeadMsBulk;
    } else if (pcmLength >= _bulkChunkThresholdBytes) {
      txLeadMs = _txLeadMsBulkVoice;
    } else {
      txLeadMs = _txLeadMsVoice;
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    int totalBytesSent = 0;

    while (pcmLength >= _pcmInputSizePerFrame && !_voiceTransmitCancel) {
      final (Uint8List? encoded, int bytesConsumed) = _encodeSbcFrames(
        pcmData,
        pcmOffset,
        pcmLength,
      );
      if (encoded == null || bytesConsumed <= 0) break;

      await _sendAudio(_escapeBytes(0, encoded));

      // Record / play back / report the PCM that was just consumed.
      final Uint8List consumed = Uint8List.sublistView(
        pcmData,
        pcmOffset,
        pcmOffset + bytesConsumed,
      );
      _recorder?.write(_int16ListFromBytes(consumed));
      if (_playInputBack && !_isMuted) {
        // Route monitor audio through the real-time pump instead of emitting it
        // in lockstep with the transmit encoder, which runs ahead of real time.
        _enqueueMonitor(Int16List.fromList(_int16ListFromBytes(consumed)));
      }
      _dispatchAudioDataAvailable(
        Uint8List.fromList(consumed),
        bytesConsumed,
        true,
        false,
      );

      pcmOffset += bytesConsumed;
      pcmLength -= bytesConsumed;
      totalBytesSent += bytesConsumed;

      // Allow the transmit buffer to run up to txLeadMs ahead of real time,
      // then throttle so we never outpace the radio's playout.
      final int expectedElapsedMs =
          (totalBytesSent * 1000) ~/ bytesPerSecond - txLeadMs;
      final int waitMs = expectedElapsedMs - stopwatch.elapsedMilliseconds;
      if (waitMs > 0 && !_voiceTransmitCancel) {
        await Future<void>.delayed(
          Duration(milliseconds: waitMs < 100 ? waitMs : 100),
        );
      }
    }

    // Keep any trailing partial frame for the next chunk.
    if (pcmLength > 0) {
      _reminderTransmitPcm = Uint8List.fromList(
        Uint8List.sublistView(pcmData, pcmOffset, pcmOffset + pcmLength),
      );
    }
  }

  /// Encode as many consecutive SBC frames as fit (up to <300 bytes) from
  /// [pcmData] starting at [pcmOffset]. Returns the concatenated SBC blob and
  /// the number of PCM bytes consumed.
  (Uint8List?, int) _encodeSbcFrames(
    Uint8List pcmData,
    int pcmOffset,
    int pcmLength,
  ) {
    if (pcmLength < _pcmInputSizePerFrame) return (null, 0);

    // Data frames (the software modem) carry an OFDM/FSK waveform, not speech —
    // so use SBC's SNR bit-allocation instead of the psychoacoustic "loudness"
    // curve. Voice keeps loudness. The allocation method is signaled in each
    // SBC frame header, so the radio's decoder adapts automatically.
    _encoderFrame.allocationMethod = _voiceTransmitIsDataFrame
        ? SbcBitAllocationMethod.snr
        : SbcBitAllocationMethod.loudness;

    final int samplesPerChannel = _encoderFrame.blocks * _encoderFrame.subbands;
    final int bytesPerFrame = samplesPerChannel * 2;
    int totalToConsume = pcmLength;
    int totalGenerated = 0;
    int totalBytesConsumed = 0;
    final BytesBuilder builder = BytesBuilder(copy: false);

    while (totalToConsume >= _pcmInputSizePerFrame && totalGenerated < 300) {
      final Int16List pcmSamples = _int16ListFromBytes(
        Uint8List.sublistView(
          pcmData,
          pcmOffset + totalBytesConsumed,
          pcmOffset + totalBytesConsumed + bytesPerFrame,
        ),
      );
      final Uint8List? sbcFrameData = _sbcEncoder.encode(
        pcmSamples,
        null,
        _encoderFrame,
      );
      if (sbcFrameData == null || sbcFrameData.isEmpty) break;

      builder.add(sbcFrameData);
      totalToConsume -= bytesPerFrame;
      totalGenerated += sbcFrameData.length;
      totalBytesConsumed += bytesPerFrame;
    }

    if (totalGenerated > 0) return (builder.toBytes(), totalBytesConsumed);
    return (null, 0);
  }

  /// Frame [b] with start/end `0x7e` markers and a leading command byte,
  /// escaping any `0x7d`/`0x7e` bytes in the payload.
  Uint8List _escapeBytes(int cmd, Uint8List b) {
    final BytesBuilder out = BytesBuilder(copy: false);
    out.addByte(0x7e);
    out.addByte(cmd);
    for (final int byte in b) {
      if (byte == 0x7d || byte == 0x7e) {
        out.addByte(0x7d);
        out.addByte(byte ^ 0x20);
      } else {
        out.addByte(byte);
      }
    }
    out.addByte(0x7e);
    return out.toBytes();
  }

  /// Convert little-endian 16-bit PCM bytes to an [Int16List].
  Int16List _int16ListFromBytes(Uint8List bytes) {
    final int count = bytes.length ~/ 2;
    final Int16List out = Int16List(count);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  Future<void> _sendAudio(Uint8List data) async {
    final Future<void> Function(Uint8List data)? btSend = _btSend;
    if (btSend != null) {
      await btSend(data);
    } else {
      _emit(<String, Object?>{'evt': 'send', 'bytes': _wrap(data)});
    }
  }

  // ---------------------------------------------------------------------------
  // Event emission to the host isolate
  // ---------------------------------------------------------------------------

  void _log(String msg) => _emit(<String, Object?>{'evt': 'log', 'msg': msg});

  void _dispatchVoiceTransmitStateChanged(bool transmitting) {
    _emit(<String, Object?>{
      'evt': 'txState',
      'transmitting': transmitting,
      'isDataFrame': _voiceTransmitIsDataFrame,
    });
  }

  void _dispatchAudioDataStart(bool transmit) {
    _audioRunStartMs = DateTime.now().millisecondsSinceEpoch;
    _emit(<String, Object?>{
      'evt': 'audioStart',
      'transmit': transmit,
      'startMs': _audioRunStartMs,
      'channelName': _channelName,
      'muted': _muteChannel,
    });
  }

  void _dispatchAudioDataAvailable(
    Uint8List data,
    int length,
    bool transmit,
    bool muted,
  ) {
    _emit(<String, Object?>{
      'evt': 'audioData',
      'pcm': _wrap(data),
      'length': length,
      'transmit': transmit,
      'muted': muted,
      'channelName': _channelName,
      'startMs': _audioRunStartMs,
    });
  }

  void _dispatchAudioDataEnd() {
    _emit(<String, Object?>{
      'evt': 'audioEnd',
      'transmit': _inAudioRunIsTransmit,
      'startMs': _audioRunStartMs,
    });
  }

  // ---------------------------------------------------------------------------
  // TransferableTypedData helpers (zero-copy byte transfer between isolates)
  // ---------------------------------------------------------------------------

  static TransferableTypedData _wrap(Uint8List bytes) =>
      TransferableTypedData.fromList(<Uint8List>[bytes]);

  static Uint8List? _unwrap(Object? value) {
    if (value is TransferableTypedData) {
      return value.materialize().asUint8List();
    }
    if (value is Uint8List) return value;
    return null;
  }
}

/// Entry point for the audio-engine isolate.
///
/// Protocol: the host sends `[SendPort, RootIsolateToken?, macAddress]` via
/// [initialMessage] so the isolate can send its own command [SendPort] back and
/// (given a token) write transmit audio to Bluetooth directly; thereafter the
/// two exchange `Map` messages.
///
/// Platform channels: a background isolate can **send** to the platform
/// (`invokeMethod`) once [BackgroundIsolateBinaryMessenger] is initialized, but
/// it can never **receive** (no EventChannel / method-call handlers). So the
/// engine writes paced transmit audio to Bluetooth itself — keeping the
/// real-time TX path off the busy main isolate — while received bytes and PCM
/// playback stay on the host. If no token is available (e.g. web) the engine
/// falls back to relaying transmit bytes to the host via a `send` event.
///
/// Host -> engine commands (`cmd`): `init`, `reset`, `stopAudio`, `rx`,
/// `setVolume`, `setMute`, `startRecording`, `stopRecording`, `tx`, `txHold`,
/// `cancelTx`, `radioState`, `shutdown`.
///
/// Engine -> host events (`evt`): `port`, `ready`, `log`, `send`, `play`,
/// `audioStart`, `audioEnd`, `audioData`, `amplitude`, `txState`.
Future<void> audioEngineIsolateEntry(List<Object?> initialMessage) async {
  final SendPort hostPort = initialMessage[0] as SendPort;
  final RootIsolateToken? rootToken =
      initialMessage.length > 1 ? initialMessage[1] as RootIsolateToken? : null;
  final String macAddress =
      initialMessage.length > 2 ? (initialMessage[2] as String? ?? '') : '';

  // Enable platform-channel *sends* from this background isolate so paced
  // Bluetooth transmit writes don't have to hop through the (possibly busy)
  // main isolate. Receiving from the platform still only works on the root
  // isolate, so RX and playback remain on the host.
  Future<void> Function(Uint8List data)? btSend;
  if (rootToken != null && macAddress.isNotEmpty) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    const MethodChannel btChannel =
        MethodChannel('com.htcommander/bluetooth_classic');
    btSend = (Uint8List data) async {
      try {
        await btChannel.invokeMethod<bool>('sendAudio', <String, Object?>{
          'address': macAddress,
          'data': data,
        });
      } catch (e) {
        hostPort.send(<String, Object?>{
          'evt': 'log',
          'msg': 'AudioEngine Bluetooth sendAudio error: $e',
        });
      }
    };
  }

  final ReceivePort commandPort = ReceivePort();
  final AudioEngine engine = AudioEngine(hostPort.send, btSend: btSend);

  // Hand our command port back to the host.
  hostPort.send(<String, Object?>{'evt': 'port', 'port': commandPort.sendPort});

  await for (final Object? message in commandPort) {
    if (message is Map) {
      final String cmd = (message['cmd'] as String?) ?? '';
      try {
        await engine.handleCommand(message);
      } catch (e) {
        hostPort.send(<String, Object?>{
          'evt': 'log',
          'msg': 'AudioEngine command "$cmd" error: $e',
        });
      }
      if (cmd == 'shutdown') break;
    }
  }

  commandPort.close();
  Isolate.exit();
}

/// Minimal incremental WAV (PCM 16-bit) file writer.
class _WavRecorder {
  final RandomAccessFile? _raf;
  final int _sampleRate;
  int _dataBytes = 0;

  _WavRecorder(String filename, this._sampleRate) : _raf = _openFile(filename) {
    if (_raf != null) {
      _raf.writeFromSync(_header(0, _sampleRate));
    }
  }

  static RandomAccessFile? _openFile(String filename) {
    try {
      final file = File(filename);
      return file.openSync(mode: FileMode.write);
    } catch (e) {
      debugPrint('AudioEngine: Failed to open recording file: $e');
      return null;
    }
  }

  void write(Int16List samples) {
    final raf = _raf;
    if (raf == null) return;
    try {
      final bytes = samples.buffer.asUint8List(
        samples.offsetInBytes,
        samples.lengthInBytes,
      );
      raf.writeFromSync(bytes);
      _dataBytes += bytes.length;
    } catch (e) {
      debugPrint('AudioEngine: Recording write error: $e');
    }
  }

  void close() {
    final raf = _raf;
    if (raf == null) return;
    try {
      // Patch the RIFF/data sizes in the header.
      raf.setPositionSync(0);
      raf.writeFromSync(_header(_dataBytes, _sampleRate));
      raf.closeSync();
    } catch (e) {
      debugPrint('AudioEngine: Recording close error: $e');
    }
  }

  // 44-byte canonical WAV header for 16-bit mono PCM.
  static Uint8List _header(int dataBytes, int sampleRate) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const int blockAlign = channels * bitsPerSample ~/ 8;
    final int riffSize = 36 + dataBytes;

    final bytes = Uint8List(44);
    final bd = ByteData.sublistView(bytes);
    bytes.setAll(0, 'RIFF'.codeUnits);
    bd.setUint32(4, riffSize, Endian.little);
    bytes.setAll(8, 'WAVE'.codeUnits);
    bytes.setAll(12, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // fmt chunk size
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    bytes.setAll(36, 'data'.codeUnits);
    bd.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }
}
