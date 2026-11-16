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
        PlatformException,
        RootIsolateToken;

import '../sbc/radio_audio_codec.dart';
import '../sbc/sbc_enums.dart' show SbcMode;

/// One fully encoded transmission. Native code owns pacing and its end marker.
class PreparedAudioJob {
  const PreparedAudioJob({
    required this.jobId,
    required this.data,
    required this.lengths,
    required this.samples,
    required this.leadMs,
  });

  static const int maxBytes = 16 * 1024 * 1024;
  final int jobId;
  final Uint8List data;
  final Int32List lengths;
  final Int32List samples;
  final int leadMs;
}

class PreparedAudioResult {
  const PreparedAudioResult({
    required this.cancelled,
    required this.samplesSent,
  });

  final bool cancelled;
  final int samplesSent;
}

/// A preflight rejection: no audio or end marker was submitted.
class PreparedAudioUnsupportedException implements Exception {
  const PreparedAudioUnsupportedException();
}

/// The CPU-heavy audio DSP engine that runs in a dedicated background isolate,
/// off the Flutter UI isolate.
///
/// It owns SBC encoding/decoding and recording. Live voice is paced here;
/// complete modem/SSTV jobs are prepared here and paced by a native sender.
/// Platform-channel requests can originate here, but playback and unsolicited
/// platform events still belong to the root-isolate host.
class AudioEngine {
  // Named params can't be private, so `btSend` is copied into `_btSend`.
  AudioEngine(
    this._emit, {
    Future<void> Function(Uint8List data)? btSend,
    Future<PreparedAudioResult> Function(PreparedAudioJob job)? btSendPrepared,
    Future<void> Function(int jobId)? btCancelPrepared,
    int Function()? clockMs,
  })
    // ignore: prefer_initializing_formals
    : _btSend = btSend,
       // ignore: prefer_initializing_formals
       _btSendPrepared = btSendPrepared,
       // ignore: prefer_initializing_formals
       _btCancelPrepared = btCancelPrepared,
       _clockMs = clockMs ?? _monotonicMs;

  static final Stopwatch _monotonic = Stopwatch()..start();
  static int _monotonicMs() => _monotonic.elapsedMilliseconds;

  /// Monotonic millisecond clock (injectable for tests).
  final int Function() _clockMs;

  /// Report receive runs with at least this much observed audio shortfall.
  static const int _rxLossReportMs = 250;

  /// Audio format: 32 kHz, 16-bit, mono (matches the radio's SBC stream).
  static const int _sampleRate = 32000;

  /// PCM bytes consumed per encoded SBC frame: blocks * subbands * 2 (16-bit).
  static const int _pcmInputSizePerFrame = 16 * 8 * 2; // 256 bytes

  /// Receive pre-roll depth (ms of audio). At the start of each received audio
  /// run the first [_rxPrerollMs] of decoded PCM is held and then released to
  /// the speaker in a single burst, so the native player builds a small playout
  /// cushion before playback begins. Bluetooth delivers audio in bursts, so
  /// without this cushion a late burst right after the first frame can starve
  /// the player and produce an audible click/gap; the cushion absorbs that
  /// jitter. Kept short so it only adds a few tens of ms of latency to the start
  /// of received audio (imperceptible for one-way voice).
  static const int _rxPrerollMs = 60;

  /// Pre-roll depth expressed in samples (32 kHz mono).
  static const int _rxPrerollSamples = (_sampleRate * _rxPrerollMs) ~/ 1000;

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
  /// radio Bluetooth buffering and RFCOMM flow control; successful writes do
  /// not establish that the radio's audio buffer has enough capacity.
  static const int _txLeadMsVoice = 1000;
  static const int _txLeadMsBulk = 10000;

  /// Pre-computed *voice* transmissions (spoken text / WAV playback) use a
  /// shallow lead: unlike data, a brief stall only causes a small audible
  /// glitch rather than corrupting the payload, and keeping only a couple of
  /// seconds buffered at the radio means Cancel stops the transmission quickly
  /// instead of waiting for a deep buffer to drain.
  static const int _txLeadMsBulkVoice = 2000;

  /// Pre-computed, corruption-sensitive audio that must stay cancellable from
  /// the UI (SSTV images). A stall longer than the lead tears the image, so it
  /// gets a deep cushion, while staying shorter than [_txLeadMsBulk] so Cancel
  /// still stops the transmission within a few seconds.
  static const int _txLeadMsBulkData = 6000;

  /// A single transmit chunk at least this large (~2 s of 32 kHz/16-bit mono) is
  /// treated as a bulk, pre-computed transmission and gets the deep pacing lead.
  static const int _bulkChunkThresholdBytes = _sampleRate * 2 * 2;

  /// Frame that tells the radio to stop transmitting.
  static final Uint8List _endAudioFrame = Uint8List.fromList(<int>[
    0x7e,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x7e,
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
  final Future<PreparedAudioResult> Function(PreparedAudioJob job)?
  _btSendPrepared;
  final Future<void> Function(int jobId)? _btCancelPrepared;

  final RadioAudioCodec _codec = RadioAudioCodec();

  double _outputVolume = 1.0;
  bool _isMuted = false;

  // Audio-run state tracking (a "run" is a continuous burst of audio).
  bool _inAudioRun = false;
  bool _inAudioRunIsTransmit = false;
  int _audioRunStartMs = 0;

  // Receive pre-roll: holds the first [_rxPrerollSamples] of decoded speaker
  // PCM for the current received run, then releases them in one burst. Only the
  // speaker path is buffered; recording and modem/DART decoding still receive
  // samples immediately (see [_dispatchAudioDataAvailable]).
  final List<Int16List> _rxPrerollChunks = <Int16List>[];
  int _rxPrerollSampleCount = 0;
  bool _rxPrerollFlushed = false;

  // Receive-run continuity statistics describe delivery to this isolate, not
  // where any missing audio was lost.
  int _rxRunFirstMs = 0;
  int _rxRunLastMs = 0;
  int _rxRunSamples = 0;
  int _rxRunAudioUs = 0;
  int _rxRunPackets = 0;
  int _rxRunPayloadBytes = 0;
  int _rxRunDecodedFrames = 0;
  int _rxRunDecodeErrors = 0;
  int _rxRunRejectedBytes = 0;
  final Set<String> _rxRunFormats = <String>{};
  int _rxRunMaxGapMs = 0;
  int _rxRunMaxGapAtMs = 0;

  // Radio state pushed from the host (updated on HtStatus changes).
  String _channelName = '';
  bool _muteChannel = false;

  // Optional WAV recording of received audio.
  _WavRecorder? _recorder;

  // --- Transmit state ---
  final Queue<({Uint8List pcm, int? deadlineMs})> _pcmQueue =
      Queue<({Uint8List pcm, int? deadlineMs})>();
  bool _isTransmitting = false;
  bool _voiceTransmitCancel = false;
  bool _playInputBack = false;
  bool _voiceTransmitIsDataFrame = false;
  bool _voiceTransmitIsBulkData = false;
  bool _voiceTransmitHold = false;
  Uint8List? _reminderTransmitPcm;
  Completer<void>? _newDataSignal;
  int _nextPreparedJobId = DateTime.now().microsecondsSinceEpoch;
  int? _preparedJobId;
  bool _nativeOwnsEnd = false;
  bool _radioReceiving = false;

  // --- Local monitor playback pacing ---
  // When a transmission is monitored locally (playLocally), the SBC encoder
  // runs far ahead of real time (see [_txLeadMsBulk]) so the whole clip is
  // handed to the speaker almost instantly. The host caps playback buffering
  // (~800 ms) and drops the overflow, which cut the tail off spoken audio. To
  // fix that, monitor PCM is queued here and emitted to the host at real time,
  // decoupled from the transmit lead, so the entire clip plays out.
  final Queue<Uint8List> _monitorChunks = Queue<Uint8List>();
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
        _codec.resetReceiver();
        _resetRxPreroll();
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
        final bool isBulkData = (msg['isBulkData'] as bool?) ?? false;
        if (hold != null) _voiceTransmitHold = hold;
        if (pcm != null && pcm.isNotEmpty) {
          _queueVoice(
            pcm,
            0,
            pcm.length,
            playLocally,
            isDataFrame: isDataFrame,
            isBulkData: isBulkData,
            deadlineMs: msg['deadlineMs'] as int?,
            copyPcm: msg['pcm'] is! TransferableTypedData,
          );
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
        _radioReceiving = (msg['receiving'] as bool?) ?? _radioReceiving;
        _signalNewData();
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
    _codec.dispose();
  }

  /// Abort any in-progress transmission and end an open receive audio run.
  /// Mirrors the old `RadioAudio.stop()` audio-abort logic.
  void _stopAudio() {
    _voiceTransmitHold = false;
    _voiceTransmitCancel = true;
    _signalNewData();
    _pcmQueue.clear();
    _reminderTransmitPcm = null;
    _cancelPrepared();

    // End an in-progress receive run (a transmit run is finalized by the
    // transmit loop's `finally`).
    if (_inAudioRun && !_inAudioRunIsTransmit) {
      _inAudioRun = false;
      _dispatchAudioDataEnd();
    }
    _codec.resetReceiver(resetDecoder: false);
    _resetRxPreroll();
  }

  // ---------------------------------------------------------------------------
  // Playback: hand finished PCM to the host, which owns the audio device.
  // ---------------------------------------------------------------------------

  void _emitPlay(Int16List pcm, {bool received = false}) {
    _emitPlayBytes(
      pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
      received: received,
    );
  }

  void _emitPlayBytes(Uint8List pcm, {bool received = false}) {
    _emit(<String, Object?>{
      'evt': 'play',
      'pcm': _wrap(pcm),
      'received': received,
    });
  }

  // Routes received speaker PCM through the start-of-run pre-roll buffer. The
  // first [_rxPrerollSamples] of a run are held, then released to the speaker in
  // one burst; the remainder of the run plays directly.
  void _emitReceivePlayback(Int16List pcm) {
    if (pcm.isEmpty) return;
    if (_rxPrerollFlushed) {
      _emitPlay(pcm, received: true);
      return;
    }
    _rxPrerollChunks.add(pcm);
    _rxPrerollSampleCount += pcm.length;
    if (_rxPrerollSampleCount >= _rxPrerollSamples) {
      _flushRxPreroll();
    }
  }

  // Emits any buffered pre-roll PCM to the speaker in one burst and switches to
  // direct playback for the rest of the run.
  void _flushRxPreroll() {
    for (final Int16List chunk in _rxPrerollChunks) {
      _emitPlay(chunk, received: true);
    }
    _rxPrerollChunks.clear();
    _rxPrerollSampleCount = 0;
    _rxPrerollFlushed = true;
  }

  // Clears pre-roll state at the start of a new received audio run.
  void _resetRxPreroll() {
    _rxPrerollChunks.clear();
    _rxPrerollSampleCount = 0;
    _rxPrerollFlushed = false;
  }

  // Queues locally-monitored transmit PCM for real-time playback and starts the
  // pacing pump if it is not already running.
  // Views retain engine-owned PCM; only the chunk being emitted is copied.
  void _enqueueMonitor(Uint8List pcm) {
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
        final Uint8List chunk = _monitorChunks.removeFirst();
        _emitPlayBytes(chunk);
        emittedSamples += chunk.length ~/ 2;

        // Pace to real time, staying [_monitorLeadMs] ahead of the wall clock.
        final int targetMs = (emittedSamples * 1000) ~/ _sampleRate;
        final int waitMs =
            targetMs - stopwatch.elapsedMilliseconds - _monitorLeadMs;
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
    _codec.receive(
      data,
      decodeMask: _receiveDecodeMask,
      onPacket: _onAudioPacket,
    );
  }

  int _receiveDecodeMask() {
    int mask = 0;
    if (!(_inAudioRun && _inAudioRunIsTransmit && _isTransmitting)) {
      mask |= (1 << 0) | (1 << 3);
    }
    if (!(_inAudioRun && !_inAudioRunIsTransmit)) mask |= 1 << 9;
    return mask;
  }

  void _onAudioPacket(ReceivedRadioAudio packet) {
    if (packet.command < 0) {
      _log(
        'Bluetooth audio rejected: ${packet.errorDescription}; '
        '${packet.rejectedBytes} bytes discarded.',
      );
      return;
    }
    switch (packet.command) {
      case 0x00: // Received audio (odd)
      case 0x03: // Received audio
        if (_inAudioRun && _inAudioRunIsTransmit) {
          if (_isTransmitting) return;
          // A late TX echo can outlive its end marker; RX identifies the new run.
          _log('RX audio resumed after transmit echo without an end marker.');
          _dispatchAudioDataEnd();
          _inAudioRun = false;
        }
        final int nowMs = _clockMs();
        if (!_inAudioRun) {
          _inAudioRun = true;
          _inAudioRunIsTransmit = false;
          _resetRxPreroll();
          _rxRunFirstMs = nowMs;
          _rxRunLastMs = nowMs;
          _rxRunSamples = 0;
          _rxRunAudioUs = 0;
          _rxRunPackets = 0;
          _rxRunPayloadBytes = 0;
          _rxRunDecodedFrames = 0;
          _rxRunDecodeErrors = 0;
          _rxRunRejectedBytes = 0;
          _rxRunFormats.clear();
          _rxRunMaxGapMs = 0;
          _rxRunMaxGapAtMs = 0;
          _dispatchAudioDataStart(false);
        }
        final int gapMs = nowMs - _rxRunLastMs;
        if (gapMs > _rxRunMaxGapMs) {
          _rxRunMaxGapMs = gapMs;
          _rxRunMaxGapAtMs = _rxRunLastMs - _rxRunFirstMs;
        }
        _rxRunLastMs = nowMs;
        _rxRunPackets++;
        _rxRunPayloadBytes += packet.payloadBytes;
        _deliverDecodedPacket(packet, false);
        break;
      case 0x01: // Audio end
        if (_inAudioRun) {
          _inAudioRun = false;
          // Release any pre-roll not yet flushed so short bursts still play.
          if (!_inAudioRunIsTransmit) {
            _flushRxPreroll();
            _reportRxRunLoss();
          }
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
        _deliverDecodedPacket(packet, true);
        break;
      default:
        _log('Unknown command: ${packet.command}');
        break;
    }
  }

  void _deliverDecodedPacket(ReceivedRadioAudio packet, bool isTransmit) {
    if (!isTransmit) {
      _rxRunSamples += packet.pcm.length;
      _rxRunAudioUs += packet.audioUs;
      _rxRunDecodedFrames += packet.decodedFrames;
      const frequencies = [16000, 32000, 44100, 48000];
      for (final format in packet.formats) {
        _rxRunFormats.add(
          '${frequencies[format >> 16]}Hz/'
          '${SbcMode.values[(format >> 8) & 0xff].name}'
          '/bitpool=${format & 0xff}',
        );
      }
    }
    if (packet.error != 0) {
      _reportSbcDecodeFailure(
        packet.errorDescription,
        packet.rejectedBytes,
        isTransmit,
      );
    }
    final samples = packet.pcm;
    if (samples.isEmpty) return;
    final bool isOnMuteChannel = _muteChannel;
    if (!isOnMuteChannel) {
      if (!_isMuted && !isTransmit) _emitReceivePlayback(samples);
      _recorder?.write(samples);
    }
    final pcmBytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    _dispatchAudioDataAvailable(
      pcmBytes,
      pcmBytes.length,
      isTransmit,
      isOnMuteChannel,
    );
    final double amplitude = _calculatePcmAmplitude(samples) * _outputVolume;
    _emit(<String, Object?>{'evt': 'amplitude', 'value': amplitude});
  }

  void _reportSbcDecodeFailure(
    String reason,
    int rejectedBytes,
    bool isTransmit,
  ) {
    if (!isTransmit) {
      _rxRunDecodeErrors++;
      _rxRunRejectedBytes += rejectedBytes;
    }
    _log(
      'SBC decode rejected ${isTransmit ? 'TX echo' : 'RX'} payload: $reason; '
      '$rejectedBytes bytes discarded.',
    );
  }

  /// Compare decoded duration with packet arrival times, without attributing
  /// gaps to the radio, Bluetooth, platform delivery, or decoder.
  void _reportRxRunLoss() {
    final int wallMs = _rxRunLastMs - _rxRunFirstMs;
    final int audioMs = _rxRunAudioUs ~/ 1000;
    final int missingMs = wallMs - audioMs;
    if (missingMs < _rxLossReportMs) return;
    _log(
      'RX audio shortfall: ${missingMs}ms over ${wallMs}ms of packet arrivals '
      '(decoded ${audioMs}ms); longest gap ${_rxRunMaxGapMs}ms at '
      '${_rxRunMaxGapAtMs}ms into the run. '
      'Packets=$_rxRunPackets, payloadBytes=$_rxRunPayloadBytes, '
      'SBC frames=$_rxRunDecodedFrames, samples=$_rxRunSamples, '
      'decodeErrors=$_rxRunDecodeErrors, rejectedBytes=$_rxRunRejectedBytes, '
      'formats=${_rxRunFormats.join(',')}. '
      'Arrival timing alone does not establish radio/Bluetooth packet loss.',
    );
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
  /// played back locally as it is sent. [isBulkData] marks pre-computed,
  /// corruption-sensitive audio (SSTV) that needs a deep pacing lead.
  bool transmitVoice(
    Uint8List pcmInput,
    int offset,
    int length,
    bool play, {
    bool isDataFrame = false,
    bool isBulkData = false,
    int? deadlineMs,
  }) => _queueVoice(
    pcmInput,
    offset,
    length,
    play,
    isDataFrame: isDataFrame,
    isBulkData: isBulkData,
    deadlineMs: deadlineMs,
    copyPcm: true,
  );

  bool _queueVoice(
    Uint8List pcmInput,
    int offset,
    int length,
    bool play, {
    required bool copyPcm,
    bool isDataFrame = false,
    bool isBulkData = false,
    int? deadlineMs,
  }) {
    if (_isTransmitting && _voiceTransmitCancel) {
      _log('TransmitVoicePCM rejected while cancellation is pending.');
      return false;
    }
    _playInputBack = play;
    _voiceTransmitCancel = false;
    // The data-frame flag applies to a whole transmission run; only latch it
    // when a fresh run is about to start.
    if (!_isTransmitting) {
      _voiceTransmitIsDataFrame = isDataFrame;
      _voiceTransmitIsBulkData = isBulkData;
    }
    _pcmQueue.add((
      pcm: copyPcm
          ? Uint8List.fromList(
              Uint8List.sublistView(pcmInput, offset, offset + length),
            )
          : pcmInput,
      deadlineMs: deadlineMs,
    ));

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
    if (_nativeOwnsEnd) {
      _cancelPrepared();
    } else {
      unawaited(_sendEndAudio());
    }
  }

  void _cancelPrepared() {
    final int? jobId = _preparedJobId;
    final cancel = _btCancelPrepared;
    if (jobId != null && cancel != null) {
      unawaited(
        cancel(jobId).catchError((Object error) {
          _log('Prepared audio cancellation error: $error');
        }),
      );
    }
  }

  void _signalNewData() {
    final Completer<void>? c = _newDataSignal;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _startTransmissionIfNeeded() {
    if (_isTransmitting) return;
    _isTransmitting = true;
    _nativeOwnsEnd = false;
    _transmissionLoop();
  }

  Future<void> _transmissionLoop() async {
    _dispatchVoiceTransmitStateChanged(true);
    try {
      while (!_voiceTransmitCancel) {
        if (_pcmQueue.isNotEmpty) {
          final chunk = _pcmQueue.removeFirst();
          if (_btSendPrepared != null &&
              (_voiceTransmitIsDataFrame || _voiceTransmitIsBulkData) &&
              !_voiceTransmitHold) {
            // Preparation has not keyed the radio, so no fallback end marker
            // may race a native job or interrupt an incoming transmission.
            _nativeOwnsEnd = true;
            await _processPreparedPcm(chunk.pcm, chunk.deadlineMs);
          } else {
            _nativeOwnsEnd = false;
            await _processPcmData(chunk.pcm);
          }
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
      _pcmQueue.clear();
    } finally {
      if (_inAudioRun && _inAudioRunIsTransmit) {
        _inAudioRun = false;
        _dispatchAudioDataEnd();
      }
      _reminderTransmitPcm = null;
      if (!_nativeOwnsEnd) await _sendEndAudio();
      _dispatchVoiceTransmitStateChanged(false);
      _isTransmitting = false;
    }
  }

  Future<void> _processPreparedPcm(Uint8List incoming, int? deadlineMs) async {
    if (_btCancelPrepared == null) {
      throw StateError('Prepared audio requires native cancellation support');
    }
    if (incoming.length > 96 * 1024 * 1024) {
      throw StateError('Prepared PCM exceeds the 96 MiB limit');
    }
    final remainder = _reminderTransmitPcm;
    final Uint8List pcm;
    if (remainder == null) {
      pcm = incoming;
    } else {
      pcm = Uint8List(remainder.length + incoming.length)
        ..setRange(0, remainder.length, remainder)
        ..setRange(
          remainder.length,
          remainder.length + incoming.length,
          incoming,
        );
    }
    _reminderTransmitPcm = null;
    final payload = BytesBuilder(copy: false);
    final lengths = <int>[];
    final samples = <int>[];
    int offset = 0;
    while (pcm.length - offset >= _pcmInputSizePerFrame) {
      final int end = offset + RadioAudioCodec.maxInputBytes < pcm.length
          ? offset + RadioAudioCodec.maxInputBytes
          : pcm.length;
      final encoded = _codec.encode(
        Uint8List.sublistView(pcm, offset, end),
        isDataFrame: _voiceTransmitIsDataFrame,
      );
      if (encoded.pcmConsumed <= 0) {
        throw StateError('SBC preparation failed at PCM byte $offset');
      }
      offset += encoded.pcmConsumed;
      payload.add(encoded.data);
      lengths.addAll(encoded.lengths);
      samples.addAll(encoded.samples);
      if (payload.length > PreparedAudioJob.maxBytes ||
          lengths.length > 200000) {
        throw StateError('Prepared audio exceeds the native job limit');
      }
      if (lengths.length % 16 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      if (_voiceTransmitCancel) return;
      _checkPreparedDeadline(deadlineMs);
    }
    if (offset < pcm.length) {
      _reminderTransmitPcm = Uint8List.fromList(
        Uint8List.sublistView(pcm, offset),
      );
    }
    if (lengths.isEmpty || _voiceTransmitCancel) return;
    await Future<void>.delayed(Duration.zero);
    while ((_radioReceiving || (_inAudioRun && !_inAudioRunIsTransmit)) &&
        !_voiceTransmitCancel) {
      _checkPreparedDeadline(deadlineMs);
      _newDataSignal = Completer<void>();
      await Future.any<void>(<Future<void>>[
        _newDataSignal!.future,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
      _newDataSignal = null;
    }
    if (_voiceTransmitCancel) return;
    _checkPreparedDeadline(deadlineMs);
    _beginTransmitAudioRun();
    final job = PreparedAudioJob(
      jobId: _nextPreparedJobId++,
      data: payload.takeBytes(),
      lengths: Int32List.fromList(lengths),
      samples: Int32List.fromList(samples),
      leadMs: _voiceTransmitIsDataFrame ? _txLeadMsBulk : _txLeadMsBulkData,
    );
    _preparedJobId = job.jobId;
    try {
      final pending = _submitPrepared(job);
      if (_playInputBack && !_isMuted) {
        for (int start = 0; start < offset; start += 12800) {
          final end = start + 12800 < offset ? start + 12800 : offset;
          _enqueueMonitor(Uint8List.sublistView(pcm, start, end));
        }
      }
      final result = await pending;
      if (result.samplesSent < 0 ||
          result.samplesSent > offset ~/ 2 ||
          result.samplesSent % 128 != 0 ||
          (!result.cancelled && result.samplesSent != offset ~/ 2)) {
        throw StateError('Invalid native prepared audio sample count');
      }
      if (result.cancelled) {
        _voiceTransmitCancel = true;
        _pcmQueue.clear();
      }
      // These observers cannot delay native writes. Publish only the prefix
      // whose submission the sender confirmed, in bounded PCM chunks.
      final int sentBytes = result.samplesSent * 2;
      for (int start = 0; start < sentBytes; start += 12800) {
        final int end = start + 12800 < sentBytes ? start + 12800 : sentBytes;
        final consumed = Uint8List.sublistView(pcm, start, end);
        _recorder?.write(_int16ListFromBytes(consumed));
        _dispatchAudioDataAvailable(consumed, consumed.length, true, false);
        await Future<void>.delayed(Duration.zero);
      }
      _log(
        'Prepared TX audio: job=${job.jobId}, lead=${job.leadMs}ms, '
        'audio=${result.samplesSent * 1000 ~/ _sampleRate}ms, '
        'cancelled=${result.cancelled}, wireBytes=${job.data.length}',
      );
    } finally {
      _preparedJobId = null;
    }
  }

  Future<PreparedAudioResult> _submitPrepared(PreparedAudioJob job) async {
    try {
      return await _btSendPrepared!(job);
    } on PreparedAudioUnsupportedException {
      _log(
        'Native prepared audio is unavailable on this shared Bluetooth '
        'endpoint; using legacy paced writes without UI-stall protection.',
      );
      final clock = Stopwatch()..start();
      int sent = 0;
      int offset = 0;
      try {
        for (int i = 0; i < job.lengths.length; i++) {
          final targetMs =
              (sent + job.samples[i]) * 1000 ~/ _sampleRate - job.leadMs;
          while (!_voiceTransmitCancel &&
              clock.elapsedMilliseconds < targetMs) {
            final waitMs = targetMs - clock.elapsedMilliseconds;
            await Future<void>.delayed(
              Duration(milliseconds: waitMs < 100 ? waitMs : 100),
            );
          }
          if (_voiceTransmitCancel) break;
          await _sendAudio(
            Uint8List.sublistView(job.data, offset, offset + job.lengths[i]),
          );
          offset += job.lengths[i];
          sent += job.samples[i];
        }
      } catch (error) {
        _log('Legacy prepared audio write failed: $error');
        rethrow;
      } finally {
        await _sendAudio(_endAudioFrame);
      }
      return PreparedAudioResult(
        cancelled: _voiceTransmitCancel,
        samplesSent: sent,
      );
    }
  }

  void _checkPreparedDeadline(int? deadlineMs) {
    if (deadlineMs != null &&
        DateTime.now().millisecondsSinceEpoch >= deadlineMs) {
      throw StateError('Prepared modem transmission expired before submission');
    }
  }

  void _beginTransmitAudioRun() {
    if (_inAudioRun && !_inAudioRunIsTransmit) {
      _log('TX started before received audio end marker; closing receive run.');
      _flushRxPreroll();
      _reportRxRunLoss();
      _dispatchAudioDataEnd();
      _inAudioRun = false;
    }
    if (!_inAudioRun) {
      _inAudioRun = true;
      _inAudioRunIsTransmit = true;
      _dispatchAudioDataStart(true);
    }
  }

  Future<void> _processPcmData(Uint8List incoming) async {
    _beginTransmitAudioRun();

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
    } else if (_voiceTransmitIsBulkData) {
      txLeadMs = _txLeadMsBulkData;
    } else if (pcmLength >= _bulkChunkThresholdBytes) {
      txLeadMs = _txLeadMsBulkVoice;
    } else {
      txLeadMs = _txLeadMsVoice;
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    int totalBytesSent = 0;
    int wireBytes = 0;
    int writes = 0;
    int maxWriteMs = 0;
    int maxBehindMs = 0;

    while (pcmLength >= _pcmInputSizePerFrame && !_voiceTransmitCancel) {
      final int end = pcmLength < RadioAudioCodec.pcmBytesPerBatch
          ? pcmOffset + pcmLength
          : pcmOffset + RadioAudioCodec.pcmBytesPerBatch;
      final encoded = _codec.encode(
        Uint8List.sublistView(pcmData, pcmOffset, end),
        isDataFrame: _voiceTransmitIsDataFrame,
      );
      if (encoded.pcmConsumed <= 0 || encoded.lengths.length != 1) {
        throw StateError(
          'SBC encoding failed with $pcmLength PCM bytes remaining',
        );
      }

      final int batchPcmStart = pcmOffset;
      pcmOffset += encoded.pcmConsumed;
      pcmLength -= encoded.pcmConsumed;
      final Uint8List packets = encoded.data;
      final Stopwatch writeWatch = Stopwatch()..start();
      await _sendAudio(packets);
      if (writeWatch.elapsedMilliseconds > maxWriteMs) {
        maxWriteMs = writeWatch.elapsedMilliseconds;
      }
      wireBytes += packets.length;
      writes++;

      // Record / play back / report the PCM that was just sent.
      final Uint8List consumed = Uint8List.sublistView(
        pcmData,
        batchPcmStart,
        pcmOffset,
      );
      _recorder?.write(_int16ListFromBytes(consumed));
      if (_playInputBack && !_isMuted) {
        // Route monitor audio through the real-time pump instead of emitting it
        // in lockstep with the transmit encoder, which runs ahead of real time.
        _enqueueMonitor(consumed);
      }
      _dispatchAudioDataAvailable(consumed, consumed.length, true, false);
      totalBytesSent += consumed.length;

      // How far the radio's playout clock is ahead of what has been delivered.
      // Positive values mean the radio may have run dry (an audible gap / torn
      // image), which is what the lead is meant to prevent.
      final int behindMs =
          stopwatch.elapsedMilliseconds -
          (totalBytesSent * 1000) ~/ bytesPerSecond;
      if (behindMs > maxBehindMs) maxBehindMs = behindMs;

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

    if (_voiceTransmitIsDataFrame || _voiceTransmitIsBulkData) {
      _log(
        'TX audio: bitpool=18, lead=${txLeadMs}ms, '
        'audio=${totalBytesSent * 1000 ~/ bytesPerSecond}ms, '
        'elapsed=${stopwatch.elapsedMilliseconds}ms, '
        'writes=$writes, maxWrite=${maxWriteMs}ms, '
        'maxBehind=${maxBehindMs}ms, wireBytes=$wireBytes',
      );
    }

    // Keep any trailing partial frame for the next chunk.
    if (pcmLength > 0) {
      _reminderTransmitPcm = Uint8List.fromList(
        Uint8List.sublistView(pcmData, pcmOffset, pcmOffset + pcmLength),
      );
    }
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

  Future<void> _sendEndAudio() async {
    try {
      await _sendAudio(_endAudioFrame);
    } catch (e) {
      _log('Voice transmit stop error: $e');
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
  final RootIsolateToken? rootToken = initialMessage.length > 1
      ? initialMessage[1] as RootIsolateToken?
      : null;
  final String macAddress = initialMessage.length > 2
      ? (initialMessage[2] as String? ?? '')
      : '';

  // Enable platform-channel *sends* from this background isolate so paced
  // Bluetooth transmit writes don't have to hop through the (possibly busy)
  // main isolate. Receiving from the platform still only works on the root
  // isolate, so RX and playback remain on the host.
  Future<void> Function(Uint8List data)? btSend;
  Future<PreparedAudioResult> Function(PreparedAudioJob job)? btSendPrepared;
  Future<void> Function(int jobId)? btCancelPrepared;
  if (rootToken != null && macAddress.isNotEmpty) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    // Android serves transmit writes on a background task queue (a dedicated
    // channel) so they never queue behind work on the Android UI thread.
    final MethodChannel btChannel = MethodChannel(
      Platform.isAndroid
          ? 'com.htcommander/bluetooth_classic_audio_tx'
          : 'com.htcommander/bluetooth_classic',
    );
    btSend = (Uint8List data) async {
      final bool? sent = await btChannel.invokeMethod<bool>(
        'sendAudio',
        <String, Object?>{'address': macAddress, 'data': data},
      );
      if (sent != true) {
        throw StateError(
          'Bluetooth sendAudio rejected ${data.length} bytes for $macAddress',
        );
      }
    };
    btSendPrepared = (PreparedAudioJob job) async {
      final Map<String, Object?>? result;
      try {
        result = await btChannel.invokeMapMethod<String, Object?>(
          'sendPreparedAudio',
          <String, Object?>{
            'address': macAddress,
            'jobId': job.jobId,
            'data': job.data,
            'lengths': job.lengths,
            'samples': job.samples,
            'leadMs': job.leadMs,
          },
        );
      } on PlatformException catch (error) {
        if (Platform.isMacOS && error.code == 'UNSUPPORTED_CONNECTION') {
          throw const PreparedAudioUnsupportedException();
        }
        rethrow;
      }
      final status = result?['status'];
      final sent = result?['samplesSent'];
      if ((status != 'submitted' && status != 'cancelled') || sent is! int) {
        throw StateError('Invalid native prepared audio response: $result');
      }
      hostPort.send(<String, Object?>{
        'evt': 'log',
        'msg': 'Native TX audio: job=${job.jobId}, $result',
      });
      return PreparedAudioResult(
        cancelled: status == 'cancelled',
        samplesSent: sent,
      );
    };
    btCancelPrepared = (int jobId) async {
      final result = await btChannel.invokeMethod<bool>(
        'cancelPreparedAudio',
        <String, Object?>{'address': macAddress, 'jobId': jobId},
      );
      if (result == null) {
        throw StateError('Invalid native prepared cancellation response');
      }
      // False means completion won the race with cancellation.
    };
  }

  final ReceivePort commandPort = ReceivePort();
  final AudioEngine engine = AudioEngine(
    hostPort.send,
    btSend: btSend,
    btSendPrepared: btSendPrepared,
    btCancelPrepared: btCancelPrepared,
  );

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
