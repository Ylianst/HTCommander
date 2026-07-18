/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Off-isolate transmit-audio encoder for the software modem.

DART frame modulation (LDPC FEC + OFDM/SC-FDMA) and, to a lesser degree, the
AFSK/PSK tone generation are CPU-heavy. Running them on the Flutter UI isolate
means a channel-access slot that fires during a window drag or tab switch blocks
the UI *and* stalls the real-time transmit pacing, which the receiver hears as
audio break-up. This class moves that work to a dedicated background isolate.

The isolate keeps a single [DartModem] alive (its LDPC/OFDM tables are built
once) and reconstructs the lightweight packet TX chain per request. Requests are
correlated by id so multiple radios can encode concurrently.
*/

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../hamlib/audio_buffer.dart';
import '../hamlib/audio_config.dart';
import '../hamlib/dart_modem.dart';
import '../hamlib/fx25.dart';
import '../hamlib/fx25_send.dart';
import '../hamlib/gen_tone.dart';
import '../hamlib/hdlc_send.dart';

/// One DART frame to modulate: raw payload plus the on-air mode and sequence
/// number chosen by the caller (the caller owns the monotonic sequence).
class DartTxFrame {
  final Uint8List payload;
  final DartMode mode;
  final int seqNum;
  const DartTxFrame(this.payload, this.mode, this.seqNum);
}

/// Which packet modulation the isolate should reconstruct for an AFSK/PSK build.
enum PacketModulation { afsk1200, psk2400 }

/// The result of an off-isolate encode: the finished little-endian 16-bit mono
/// PCM (null/empty when nothing was produced) plus any log lines the encoder
/// wants the host to surface (e.g. FX.25 fallback notices).
class ModemTxResult {
  final Uint8List? pcm;
  final List<String> logs;
  const ModemTxResult(this.pcm, this.logs);
}

/// Host-side handle to the encoder isolate. Spawns lazily on first use and is
/// reused for the lifetime of its owner. Not a global singleton so its lifecycle
/// stays tied to the owning [SoftwareModem].
class ModemTxEncoder {
  SendPort? _port;
  ReceivePort? _receivePort;
  Completer<void>? _ready;
  bool _spawning = false;
  bool _disposed = false;

  int _nextId = 0;
  final Map<int, Completer<ModemTxResult>> _pending =
      <int, Completer<ModemTxResult>>{};

  Future<void> _ensure() async {
    if (_disposed) return;
    if (_port != null) return;
    if (_spawning) {
      await _ready?.future;
      return;
    }
    _spawning = true;
    final Completer<void> ready = Completer<void>();
    _ready = ready;

    final ReceivePort receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_onMessage);

    await Isolate.spawn(
      _modemTxEncoderIsolateEntry,
      receivePort.sendPort,
      debugName: 'modem-tx-encoder',
    );
    await ready.future;
    _spawning = false;
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _port = message;
      if (!(_ready?.isCompleted ?? true)) _ready?.complete();
      return;
    }
    if (message is Map) {
      final int id = (message['id'] as int?) ?? -1;
      final Completer<ModemTxResult>? completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      final Object? pcm = message['pcm'];
      Uint8List? bytes;
      if (pcm is TransferableTypedData) {
        bytes = pcm.materialize().asUint8List();
      } else if (pcm is Uint8List) {
        bytes = pcm;
      }
      final List<String> logs =
          (message['logs'] as List?)?.cast<String>() ?? const <String>[];
      completer.complete(ModemTxResult(bytes, logs));
    }
  }

  Future<ModemTxResult> _request(Map<String, Object?> req) async {
    await _ensure();
    final SendPort? port = _port;
    if (_disposed || port == null) {
      return const ModemTxResult(null, <String>[]);
    }
    final int id = _nextId++;
    final Completer<ModemTxResult> completer = Completer<ModemTxResult>();
    _pending[id] = completer;
    req['id'] = id;
    port.send(req);
    return completer.future;
  }

  /// Modulate [frames] as a single DART transmission (lead-in/tail silence
  /// included). Sequence numbers must already be assigned by the caller.
  Future<ModemTxResult> encodeDart(List<DartTxFrame> frames) {
    return _request(<String, Object?>{
      'kind': 'dart',
      'frames': frames
          .map((DartTxFrame f) => <String, Object?>{
                'payload': f.payload,
                'mode': f.mode.index,
                'seqNum': f.seqNum,
              })
          .toList(growable: false),
    });
  }

  /// Modulate [frames] as a single bundled AFSK/PSK transmission using one
  /// TXDELAY preamble and one TXTAIL postamble, with optional FX.25 FEC.
  Future<ModemTxResult> encodePacket({
    required PacketModulation modulation,
    required bool fecEnabled,
    required int txdelay,
    required int txtail,
    required int sampleRate,
    required List<Uint8List> frames,
  }) {
    return _request(<String, Object?>{
      'kind': 'packet',
      'modulation': modulation.index,
      'fecEnabled': fecEnabled,
      'txdelay': txdelay,
      'txtail': txtail,
      'sampleRate': sampleRate,
      'frames': frames,
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _port?.send(<String, Object?>{'kind': 'shutdown'});
    _port = null;
    _receivePort?.close();
    _receivePort = null;
    for (final Completer<ModemTxResult> c in _pending.values) {
      if (!c.isCompleted) c.complete(const ModemTxResult(null, <String>[]));
    }
    _pending.clear();
  }
}

// ---------------------------------------------------------------------------
// Isolate side
// ---------------------------------------------------------------------------

/// Entry point for the encoder isolate. Holds one [DartModem] for the isolate's
/// lifetime so its precomputed tables are built only once.
Future<void> _modemTxEncoderIsolateEntry(SendPort hostPort) async {
  final ReceivePort commandPort = ReceivePort();
  hostPort.send(commandPort.sendPort);

  // Reed-Solomon codec tables are static (per-isolate) state, so this isolate
  // must initialize FX.25 itself before it can modulate any AX.25/FX.25 frame -
  // otherwise Fx25.getRs() asserts on a null codec.
  Fx25.init(0);

  DartModem? dartModem;

  await for (final Object? message in commandPort) {
    if (message is! Map) continue;
    final String kind = (message['kind'] as String?) ?? '';
    if (kind == 'shutdown') break;

    final int id = (message['id'] as int?) ?? -1;
    final List<String> logs = <String>[];
    Uint8List? pcm;
    try {
      if (kind == 'dart') {
        dartModem ??= DartModem();
        pcm = _buildDartPcm(dartModem, message['frames'] as List);
      } else if (kind == 'packet') {
        pcm = _buildPacketPcm(message, logs);
      }
    } catch (e) {
      logs.add('Modem TX encode error: $e');
      pcm = null;
    }

    hostPort.send(<String, Object?>{
      'id': id,
      'pcm': pcm == null
          ? null
          : TransferableTypedData.fromList(<Uint8List>[pcm]),
      'logs': logs,
    });
  }

  commandPort.close();
  Isolate.exit();
}

/// Build a DART transmission: each frame encoded as a full DART frame (own
/// preamble/header/payload/FEC), concatenated with PTT lead-in/tail silence.
Uint8List? _buildDartPcm(DartModem modem, List rawFrames) {
  const int sampleRate = 32000;
  final List<int> samples = <int>[];

  // Half a second of leading silence so PTT is fully keyed before data tones.
  samples.addAll(List<int>.filled(sampleRate ~/ 2, 0));

  for (final Object? entry in rawFrames) {
    final Map frame = entry as Map;
    final Uint8List payload = frame['payload'] as Uint8List;
    final DartMode mode = DartMode.values[(frame['mode'] as int?) ?? 0];
    final int seqNum = (frame['seqNum'] as int?) ?? 0;
    final Int16List framePcm = modem.encode(
      payload: payload,
      mode: mode,
      seqNum: seqNum & 0xFF,
    );
    samples.addAll(framePcm);
  }

  // Tenth of a second of trailing silence before PTT release.
  samples.addAll(List<int>.filled(sampleRate ~/ 10, 0));

  return _packSamples(samples);
}

/// Build a bundled AFSK/PSK transmission: one TXDELAY preamble, each frame
/// back-to-back (HDLC flags delimit them, optional FX.25 FEC), one TXTAIL
/// postamble, bracketed by PTT lead-in/tail silence.
Uint8List? _buildPacketPcm(Map message, List<String> logs) {
  final PacketModulation modulation =
      PacketModulation.values[(message['modulation'] as int?) ?? 0];
  final bool fecEnabled = (message['fecEnabled'] as bool?) ?? true;
  final int txdelay = (message['txdelay'] as int?) ?? 30;
  final int txtail = (message['txtail'] as int?) ?? 10;
  final int sampleRate = (message['sampleRate'] as int?) ?? 32000;
  final List frames = message['frames'] as List;

  // Audio configuration for the requested modulation (mirrors _buildInstance).
  final AudioConfig audioConfig = AudioConfig();
  audioConfig.devices[0].defined = true;
  audioConfig.devices[0].samplesPerSec = sampleRate;
  audioConfig.devices[0].bitsPerSample = 16;
  audioConfig.devices[0].numChannels = 1;
  audioConfig.channelMedium[0] = Medium.radio;
  audioConfig.channels[0].numSubchan = 1;
  switch (modulation) {
    case PacketModulation.afsk1200:
      audioConfig.channels[0].modemType = ModemType.afsk;
      audioConfig.channels[0].markFreq = 1200;
      audioConfig.channels[0].spaceFreq = 2200;
      audioConfig.channels[0].baud = 1200;
      break;
    case PacketModulation.psk2400:
      audioConfig.channels[0].modemType = ModemType.qpsk;
      audioConfig.channels[0].baud = 2400;
      audioConfig.channels[0].v26Alt = V26Alternative.b;
      break;
  }
  audioConfig.channels[0].txdelay = txdelay;
  audioConfig.channels[0].txtail = txtail;

  final AudioBuffer buffer = AudioBuffer(AudioConfig.maxAudioDevices);
  final GenTone genTone = GenTone(buffer);
  genTone.init(audioConfig, 50);
  final HdlcSend hdlcSend = HdlcSend(genTone, audioConfig);
  final Fx25Send fx25Send = Fx25Send()..init(genTone);

  const int chan = 0;
  buffer.clearAll();

  // Half a second of leading silence so PTT is fully keyed before data tones.
  for (int i = 0; i < sampleRate ~/ 2; i++) {
    buffer.put(0, 0);
  }

  // Single preamble for the whole transmission.
  hdlcSend.sendFlags(chan, txdelay, false, null);

  // AX.25 minimum data: two 7-byte addresses + control (FCS added separately).
  const int ax25MinDataLen = 14 + 1;
  const int fx25SmallestFec = 16; // 16 check bytes = smallest FX.25 FEC
  for (final Object? entry in frames) {
    final Uint8List frameData = entry as Uint8List;
    int sent = -1;
    if (fecEnabled && frameData.length >= ax25MinDataLen) {
      sent = fx25Send.sendFrame(chan, frameData, frameData.length,
          fx25SmallestFec);
      if (sent < 0) {
        logs.add('TX FX.25: sendFrame rejected the frame (too small/large for '
            'any FX.25 block) - falling back to plain AX.25.');
      } else {
        logs.add('TX FX.25: encoded ${frameData.length}-byte frame into '
            '$sent bits.');
      }
    }
    if (sent < 0) {
      logs.add('TX AX.25 (no FEC): sending ${frameData.length}-byte frame.');
      hdlcSend.sendFrame(chan, frameData, frameData.length, false);
    }
  }

  // Single postamble.
  hdlcSend.sendFlags(chan, txtail, true, (device) {});

  // 1/10th of a second of trailing silence so the final tones are fully sent
  // before PTT is released.
  for (int i = 0; i < sampleRate ~/ 10; i++) {
    buffer.put(0, 0);
  }

  final Int16List samples = buffer.getAndClear(0);
  if (samples.isEmpty) return null;
  return _packSamples(samples);
}

/// Pack 16-bit samples into little-endian PCM bytes, clamping to range.
Uint8List _packSamples(List<int> samples) {
  final Uint8List pcmData = Uint8List(samples.length * 2);
  final ByteData bd = ByteData.view(pcmData.buffer);
  for (int i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i].clamp(-32768, 32767), Endian.little);
  }
  return pcmData;
}
