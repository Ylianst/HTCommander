// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'audio_config.dart';
import 'demod_afsk.dart';
import 'demod_psk.dart';
import 'ihdlc_receiver.dart';
import 'native_packet_modem.dart';

const _asset = 'package:htcommander/packet_modem';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

final class _RxConfig extends Struct {
  @Int32()
  external int mode;
  @Int32()
  external int slicers;
  @Int32()
  external int preTaps;
  @Int32()
  external int lpTaps;
  @Int32()
  external int delayTaps;
  @Int32()
  external int useLo;
  @Int32()
  external int v26B;
  @Int32()
  external int bOffs;
  @Int32()
  external int cOffs;
  @Int32()
  external int sOffs;
  @Uint32()
  external int pllStep;
  @Uint32()
  external int markStep;
  @Uint32()
  external int spaceStep;
  @Uint32()
  external int centerStep;
  @Double()
  external double lockedInertia;
  @Double()
  external double searchingInertia;
  @Double()
  external double fastAttack;
  @Double()
  external double slowDecay;
  @Double()
  external double normalize;
}

final class _TxConfig extends Struct {
  @Int32()
  external int mode;
  @Int32()
  external int v26B;
  @Uint32()
  external int ticksSample;
  @Uint32()
  external int ticksSymbol;
  @Uint32()
  external int markStep;
  @Uint32()
  external int spaceStep;
}

@Native<
  Pointer<Void> Function(
    Pointer<_RxConfig>,
    Pointer<Float>,
    Pointer<Float>,
    Pointer<Float>,
    Pointer<Float>,
  )
>(symbol: 'ht_packet_rx_create', assetId: _asset)
external Pointer<Void> _create(
  Pointer<_RxConfig> config,
  Pointer<Float> pre,
  Pointer<Float> lp,
  Pointer<Float> oscillator,
  Pointer<Float> gains,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_packet_rx_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<Void> state);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    IntPtr,
    IntPtr,
    Int32,
    Pointer<Uint32>,
    Int32,
  )
>(symbol: 'ht_packet_rx_process_bounded', assetId: _asset, isLeaf: true)
external int _process(
  Pointer<Void> state,
  Pointer<Uint8> pcm,
  int pcmBytes,
  int offset,
  int samples,
  Pointer<Uint32> events,
  int capacity,
);

@Native<
  Int32 Function(
    Pointer<_TxConfig>,
    Pointer<Int16>,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'ht_packet_tx', assetId: _asset)
external int _encode(
  Pointer<_TxConfig> config,
  Pointer<Int16> sine,
  Pointer<Uint8> bits,
  int count,
  Pointer<Uint8> pcm,
  int capacity,
  int leading,
  int trailing,
);

final class PacketDemodulator implements NativePacketDemodulator, Finalizable {
  // Keep pinned leaf calls short even with long FIR filters.
  static const _chunkSamples = 256;
  static final _stateFinalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(_destroy),
  );
  final IHdlcReceiver _receiver;
  late final Pointer<Void> _state;
  late final Uint32List _eventView;
  late final int _eventCapacity;
  bool _disposed = false;
  bool _processing = false;

  PacketDemodulator(DemodulatorState state, this._receiver) {
    if (!supported) {
      throw UnsupportedError('Native packet modem is unavailable');
    }
    final psk = state is PskDemodulatorState ? state : null;
    if (psk == null && state.profile != 'A' && state.profile != 'B') {
      throw ArgumentError.value(state.profile, 'profile');
    }
    _state = using((arena) {
      final config = arena<_RxConfig>();
      final c = config.ref;
      c.mode = psk == null
          ? (state.profile == 'A' ? 0 : 1)
          : (psk.modemType == ModemType.qpsk ? 2 : 3);
      c.slicers = state.numSlicers;
      c.pllStep = state.pllStepPerSample;
      c.lockedInertia = state.pllLockedInertia;
      c.searchingInertia = state.pllSearchingInertia;
      Float32List pre, lp;
      if (psk == null) {
        c.preTaps = state.usePrefilter != 0 ? state.preFilterTaps : 0;
        c.lpTaps = state.lpFilterTaps;
        c.markStep = state.afsk.mOscDelta;
        c.spaceStep = state.afsk.sOscDelta;
        c.centerStep = state.afsk.cOscDelta;
        c.fastAttack = state.agcFastAttack;
        c.slowDecay = state.agcSlowDecay;
        c.normalize = state.afsk.normalizeRpsam;
        pre = state.preFilter;
        lp = state.lpFilter;
      } else {
        c.preTaps = psk.psk.usePrefilter != 0 ? psk.psk.preFilterTaps : 0;
        c.lpTaps = psk.psk.lpFilterTaps;
        c.delayTaps = psk.psk.delayLineTaps;
        c.useLo = psk.psk.pskUseLo;
        c.v26B = psk.psk.v26Alt == V26Alternative.b ? 1 : 0;
        c.bOffs = psk.psk.bOffs;
        c.cOffs = psk.psk.cOffs;
        c.sOffs = psk.psk.sOffs;
        c.centerStep = psk.psk.loStep;
        pre = psk.psk.preFilter;
        lp = psk.psk.lpFilter;
      }
      final preBuffer = arena<Float>(math.max(1, c.preTaps));
      final lpBuffer = arena<Float>(math.max(1, c.lpTaps));
      preBuffer.asTypedList(c.preTaps).setRange(0, c.preTaps, pre);
      lpBuffer.asTypedList(c.lpTaps).setRange(0, c.lpTaps, lp);
      final oscillator = arena<Float>(256);
      final osc = oscillator.asTypedList(256);
      for (int j = 0; j < 256; j++) {
        osc[j] = psk == null
            ? math.cos(j * 2.0 * math.pi / 256.0)
            : psk.psk.sinTable256[j];
      }
      final gains = arena<Float>(AudioConfig.maxSlicers);
      final gain = gains.asTypedList(AudioConfig.maxSlicers);
      gain[0] = 0.5;
      final step = math.pow(
        10.0,
        (math.log(4.0 / 0.5) / math.ln10) / (AudioConfig.maxSlicers - 1),
      );
      for (int j = 1; j < gain.length; j++) {
        gain[j] = gain[j - 1] * step;
      }
      final crossings = 1 + _chunkSamples * c.pllStep ~/ 0x80000000;
      _eventCapacity = crossings * (psk == null ? 2 * c.slicers : 4);
      return _create(config, preBuffer, lpBuffer, oscillator, gains);
    });
    if (_state == nullptr) {
      throw StateError(
        'Native packet demodulator configuration/allocation failed',
      );
    }
    try {
      _eventView = Uint32List(_eventCapacity);
    } catch (_) {
      _destroy(_state);
      rethrow;
    }
    _stateFinalizer.attach(this, _state, detach: this);
  }

  @override
  void process(Uint8List pcm, int offset, int length) {
    if (_disposed) throw StateError('Native packet demodulator is disposed');
    if (_processing) throw StateError('Reentrant packet demodulation');
    RangeError.checkValidRange(offset, offset + length, pcm.length);
    _processing = true;
    try {
      final end = offset + length - 1;
      while (offset < end && !_disposed) {
        final count = math.min(_chunkSamples, (end + 1 - offset) ~/ 2);
        final events = _process(
          _state,
          pcm.address,
          pcm.length,
          offset,
          count,
          _eventView.address,
          _eventCapacity,
        );
        if (events < 0 || events > _eventCapacity) {
          throw StateError('Native packet demodulation failed ($events)');
        }
        for (int i = 0; i < events && !_disposed; i++) {
          final event = _eventView[i];
          final slice = (event >> 8) & 15;
          if ((event & 4096) != 0) {
            _receiver.dcdChange(0, 0, slice, (event & 1) != 0);
          } else {
            _receiver.recBit(0, 0, slice, event & 1, false, (event >> 1) & 127);
          }
        }
        offset += count * 2;
      }
    } finally {
      _processing = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateFinalizer.detach(this);
    _destroy(_state);
  }
}

Uint8List encodeTones(
  AudioChannelConfig channel,
  int sampleRate,
  int amplitude,
  Uint8List bits,
  int leading,
  int trailing,
) {
  if (!supported) throw UnsupportedError('Native packet modem is unavailable');
  RangeError.checkValueInInterval(sampleRate, 1, 1000000, 'sampleRate');
  RangeError.checkValueInInterval(amplitude, 0, 100, 'amplitude');
  RangeError.checkNotNegative(leading, 'leadingSamples');
  RangeError.checkNotNegative(trailing, 'trailingSamples');
  final mode = switch (channel.modemType) {
    ModemType.afsk => 0,
    ModemType.qpsk => 2,
    ModemType.psk8 => 3,
    _ => throw ArgumentError.value(channel.modemType, 'modemType'),
  };
  final bitsPerSymbol = mode == 0
      ? 1
      : mode == 2
      ? 2
      : 3;
  RangeError.checkValueInInterval(
    channel.baud,
    bitsPerSymbol,
    sampleRate,
    'baud',
  );
  return using((arena) {
    const ticks = 4294967296.0;
    final config = arena<_TxConfig>();
    final c = config.ref;
    c.mode = mode;
    c.v26B = channel.v26Alt == V26Alternative.b ? 1 : 0;
    c.ticksSample = (ticks / sampleRate + 0.5).toInt();
    c.ticksSymbol = (ticks / (channel.baud / bitsPerSymbol) + 0.5).toInt();
    c.markStep =
        ((mode == 0 ? channel.markFreq : 1800) * ticks / sampleRate + 0.5)
            .toInt();
    c.spaceStep =
        ((mode == 0 ? channel.spaceFreq : 1800) * ticks / sampleRate + 0.5)
            .toInt();
    final sine = arena<Int16>(256);
    final table = sine.asTypedList(256);
    for (int j = 0; j < 256; j++) {
      table[j] =
          (math.sin((j / 256.0) * (2 * math.pi)) * 32767 * amplitude / 100.0)
              .toInt()
              .clamp(-32768, 32767);
    }
    final input = arena<Uint8>(math.max(1, bits.length));
    input.asTypedList(bits.length).setAll(0, bits);
    final symbols = bits.length ~/ bitsPerSymbol;
    final samples =
        (symbols * c.ticksSymbol + c.ticksSample - 1) ~/ c.ticksSample +
        leading +
        trailing;
    RangeError.checkValueInInterval(samples, 0, 0x3fffffff, 'output samples');
    final output = malloc<Uint8>(math.max(1, samples * 2));
    try {
      final written = _encode(
        config,
        sine,
        input,
        bits.length,
        output,
        samples,
        leading,
        trailing,
      );
      if (written != samples) {
        throw StateError('Native packet modulation failed ($written)');
      }
      return output.asTypedList(written * 2, finalizer: malloc.nativeFree);
    } catch (_) {
      malloc.free(output);
      rethrow;
    }
  });
}
