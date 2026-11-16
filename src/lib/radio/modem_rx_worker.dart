// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:typed_data';

import '../echolink/pcm_resampler.dart';
import '../hamlib/audio_config.dart';
import '../hamlib/dart_modem.dart';
import '../hamlib/demod_afsk.dart';
import '../hamlib/demod_psk.dart';
import '../hamlib/fx25.dart';
import '../hamlib/fx25_rec.dart';
import '../hamlib/hdlc_rec2.dart';
import '../hamlib/ihdlc_receiver.dart';
import '../hamlib/multi_modem.dart';
import '../hamlib/native_packet_modem.dart';
import '../services/decoder_worker.dart';

enum ModemRxMode { afsk1200, psk2400, dart }

class ModemRxEvent {
  ModemRxEvent({
    required this.context,
    this.frame,
    this.dartResult,
    this.fx25 = false,
    this.corrections = 0,
  });

  final Object? context;
  final Uint8List? frame;
  final DartDecodeResult? dartResult;
  final bool fx25;
  final int corrections;
}

class ModemRxWorker {
  ModemRxWorker({
    required ModemRxMode mode,
    required int sampleRate,
    required void Function(ModemRxEvent) onEvent,
    required void Function(Object, StackTrace) onError,
  }) : _worker = DecoderWorker(
         name: 'modem-rx-${mode.name}',
         factory: _createModem,
         config: (mode, sampleRate),
         maxPendingBytes: sampleRate * 2 * 2,
         onEvent: (event) => onEvent(event as ModemRxEvent),
         onError: onError,
       );

  final DecoderWorker _worker;
  bool captureQuality = false;

  void process(Uint8List pcm, int offset, int length, {Object? context}) {
    if (length <= 1) return;
    _worker.add((
      DecoderPcm(pcm, offset, length, context: context),
      captureQuality,
    ), bytes: length);
  }

  Future<void> get idle => _worker.idle;
  void dispose() => _worker.dispose();
}

DecoderProcessor _createModem(Object? config, void Function(Object?) emit) {
  final (mode, rate) = config as (ModemRxMode, int);
  return _ModemDecoder(mode, rate, emit);
}

class _ModemDecoder implements DecoderProcessor, IHdlcReceiver {
  _ModemDecoder(this.mode, int rate, this.emit) {
    if (mode == ModemRxMode.dart) {
      _dart = DartModem();
      if (rate != 32000) {
        _resampler = LinearResampler(inputRate: rate, outputRate: 32000);
      }
      return;
    }
    Fx25.init(0);
    final config = AudioConfig();
    config.devices[0].defined = true;
    config.devices[0].samplesPerSec = rate;
    config.devices[0].bitsPerSample = 16;
    config.devices[0].numChannels = 1;
    config.channelMedium[0] = Medium.radio;
    config.channels[0].numSubchan = 1;
    config.channels[0].modemType = mode == ModemRxMode.afsk1200
        ? ModemType.afsk
        : ModemType.qpsk;
    config.channels[0].baud = mode == ModemRxMode.afsk1200 ? 1200 : 2400;
    _hdlc = HdlcRec2()..init(config);
    _fx25 = Fx25Rec(_Fx25Delivery(_onFx25)..init(config));
    _hdlc!.addFrameReceived((event) {
      final frame = Uint8List.fromList(
        event.frame.sublist(0, event.frameLength),
      );
      if (_fx25!.isBusy(event.channel)) {
        _pending = ModemRxEvent(context: _context, frame: frame);
        _fallback?.cancel();
        _fallback = Timer(const Duration(milliseconds: 700), () {
          final pending = _pending;
          _pending = null;
          if (pending != null) emit(pending);
        });
      } else {
        emit(
          ModemRxEvent(
            context: _context,
            frame: frame,
            corrections:
                event.correctionInfo?.correctedBitPositions.length ?? 0,
          ),
        );
      }
    });
    final DemodulatorState state;
    if (mode == ModemRxMode.afsk1200) {
      _afsk = DemodAfsk(this);
      state = DemodulatorState();
      _afsk!.init(rate, 1200, 1200, 2200, 'A', state);
    } else {
      _psk = DemodPsk(this);
      final pskState = PskDemodulatorState();
      _psk!.init(ModemType.qpsk, V26Alternative.b, rate, 2400, 'B', pskState);
      state = pskState;
    }
    if (nativePacketModemEnabled) {
      _native = NativePacketDemodulator(state, this);
    }
    _state = state;
  }

  final ModemRxMode mode;
  final void Function(Object?) emit;
  Object? _context;
  DartModem? _dart;
  LinearResampler? _resampler;
  HdlcRec2? _hdlc;
  Fx25Rec? _fx25;
  DemodAfsk? _afsk;
  DemodPsk? _psk;
  DemodulatorState? _state;
  NativePacketDemodulator? _native;
  Timer? _fallback;
  ModemRxEvent? _pending;
  int _prevRaw = 0;
  final _samples = _DartSampleBuffer();
  int _sinceDecode = 0;
  int _scanned = 0;

  @override
  void process(Object? command) {
    if (command == null) return;
    final (block, analysis) = command as (DecoderPcm, bool);
    _context = block.context;
    final pcm = block.materialize();
    if (_dart != null) {
      _processDart(pcm, analysis);
    } else if (_native != null) {
      _native!.process(pcm, 0, pcm.length);
    } else {
      for (int i = 0; i + 1 < pcm.length; i += 2) {
        final sample = (pcm[i] | (pcm[i + 1] << 8)).toSigned(16);
        if (_afsk != null) {
          _afsk!.processSample(0, 0, sample, _state!);
        } else {
          _psk!.processSample(0, 0, sample, _state! as PskDemodulatorState);
        }
      }
    }
  }

  void _processDart(Uint8List pcm, bool analysis) {
    var samples = Int16List(pcm.length ~/ 2);
    final bytes = ByteData.sublistView(pcm);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = bytes.getInt16(i * 2, Endian.little);
    }
    if (_resampler != null) samples = _resampler!.process(samples);
    for (final sample in samples) {
      _samples.add(sample);
    }
    _sinceDecode += samples.length;
    if (_sinceDecode < 4000) return;
    _sinceDecode = 0;
    while (_samples.length > 2000) {
      final buffer = _samples.view();
      final searchLen = buffer.length - _dart!.preambleSamples;
      final detection = _dart!.detectPreamble(buffer, searchStart: _scanned);
      if (detection.position < 0) {
        if (searchLen >= 0 && _scanned < searchLen + 1) {
          _scanned = searchLen + 1;
        }
        break;
      }
      final result = _dart!.decode(
        buffer,
        detection: detection,
        captureConstellation: analysis,
      );
      if (result == null) {
        _scanned = detection.position;
        break;
      }
      if (result.crcOk || analysis) {
        emit(
          ModemRxEvent(
            context: _context,
            frame: result.crcOk ? result.payload : null,
            dartResult: result,
            corrections: result.ldpcCorrections,
          ),
        );
      }
      final consume = result.endSample.clamp(0, _samples.length);
      if (consume <= 0) break;
      _samples.removeFront(consume);
      _scanned = (_scanned - consume).clamp(0, _samples.length);
    }
    if (_samples.length > 32000 * 8) {
      final drop = _samples.length ~/ 2;
      _samples.removeFront(drop);
      _scanned = (_scanned - drop).clamp(0, _samples.length);
    }
  }

  void _onFx25(PacketReadyEventArgs event) {
    final packet = event.packet;
    if (packet == null || packet.frameLen == 0) return;
    _fallback?.cancel();
    _pending = null;
    emit(
      ModemRxEvent(
        context: _context,
        frame: Uint8List.fromList(packet.frameData.sublist(0, packet.frameLen)),
        fx25: true,
        corrections: (event.correctionInfo?.rsSymbolsCorrected ?? 0).clamp(
          0,
          0x7fffffff,
        ),
      ),
    );
  }

  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool scrambled,
    int unused,
  ) {
    _hdlc!.recBit(chan, subchan, slice, raw, scrambled, unused);
    final bit = raw == _prevRaw ? 1 : 0;
    _prevRaw = raw;
    _fx25!.recBit(chan, subchan, slice, bit);
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool on) {
    _hdlc!.dcdChange(chan, subchan, slice, on);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _native?.dispose();
  }
}

class _Fx25Delivery extends MultiModem {
  _Fx25Delivery(void Function(PacketReadyEventArgs) onFrame) {
    addPacketReady(onFrame);
  }
}

class _DartSampleBuffer {
  Int16List _data = Int16List(0);
  int _length = 0;
  int get length => _length;

  void add(int sample) {
    if (_length == _data.length) {
      final grown = Int16List(_data.isEmpty ? 4096 : _data.length * 2);
      grown.setRange(0, _length, _data);
      _data = grown;
    }
    _data[_length++] = sample;
  }

  Int16List view() =>
      Int16List.view(_data.buffer, _data.offsetInBytes, _length);

  void removeFront(int count) {
    if (count >= _length) {
      _length = 0;
    } else if (count > 0) {
      _data.setRange(0, _length - count, _data, count);
      _length -= count;
    }
  }
}
