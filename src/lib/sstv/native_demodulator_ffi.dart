// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_demodulator.dart';

const _asset = 'package:htcommander/sstv_dsp';

bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;
int get simdWidth => supported ? _simdWidth() : 1;

final class _Sync extends Struct {
  @Int32()
  external int detected;
  @Int32()
  external int width;
  @Int32()
  external int offset;
  @Double()
  external double frequencyOffset;
}

@Native<Int32 Function()>(
  symbol: 'ht_sstv_simd_width',
  assetId: _asset,
  isLeaf: true,
)
external int _simdWidth();

@Native<
  Pointer<Void> Function(
    Int32,
    Pointer<Double>,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'ht_sstv_create', assetId: _asset)
external Pointer<Void> _create(
  int rate,
  Pointer<Double> taps,
  int tapCount,
  int syncCount,
  int min5,
  int max5,
  int max9,
  int max20,
  int simd,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_sstv_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<Void> state);

@Native<
  Void Function(Pointer<Void>, Pointer<Double>, Int32, Int32, Pointer<_Sync>)
>(symbol: 'ht_sstv_process', assetId: _asset)
external void _process(
  Pointer<Void> state,
  Pointer<Double> samples,
  int length,
  int channel,
  Pointer<_Sync> result,
);

@Native<
  Void Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Int32,
    Pointer<Double>,
    Pointer<_Sync>,
  )
>(symbol: 'ht_sstv_process_pcm16', assetId: _asset)
external void _processPcm16(
  Pointer<Void> state,
  Pointer<Uint8> pcm,
  int length,
  Pointer<Double> output,
  Pointer<_Sync> result,
);

NativeSstvDemodulator create(
  int sampleRate,
  Float64List taps,
  int syncCount,
  int min5,
  int max5,
  int max9,
  int max20,
  bool useSimd,
) {
  RangeError.checkValueInInterval(sampleRate, 1, 0x7fffffff, 'sampleRate');
  RangeError.checkValueInInterval(taps.length, 1, 0x7fffffff ~/ 4, 'tapCount');
  RangeError.checkValueInInterval(syncCount, 1, 0x7fffffff ~/ 2, 'syncCount');
  if (min5 < 0 ||
      max5 < min5 ||
      max9 < max5 ||
      max20 < max9 ||
      max20 >= 0x7fffffff ||
      taps.any((value) => !value.isFinite)) {
    throw ArgumentError('Invalid native SSTV filter or sync thresholds');
  }
  final coefficients = calloc<Double>(taps.length);
  try {
    coefficients.asTypedList(taps.length).setAll(0, taps);
    final state = _create(
      sampleRate,
      coefficients,
      taps.length,
      syncCount,
      min5,
      max5,
      max9,
      max20,
      useSimd ? 1 : 0,
    );
    if (state == nullptr) {
      throw StateError('Unable to allocate native SSTV demodulator');
    }
    return _Demodulator(state);
  } finally {
    calloc.free(coefficients);
  }
}

final class _Demodulator implements NativeSstvDemodulator, Finalizable {
  static final _stateFinalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _destroy,
    ).cast(),
  );
  static final _bufferFinalizer = NativeFinalizer(calloc.nativeFree);
  final Pointer<Void> _state;
  final Pointer<_Sync> _sync = calloc<_Sync>();
  final Object _syncToken = Object();
  final Object _samplesToken = Object();
  final Object _pcmToken = Object();
  Pointer<Double> _samples = nullptr;
  Pointer<Uint8> _pcm = nullptr;
  int _pcmCapacity = 0;
  int _capacity = 0;
  bool _disposed = false;

  _Demodulator(this._state) {
    _stateFinalizer.attach(this, _state, detach: this);
    _bufferFinalizer.attach(this, _sync.cast(), detach: _syncToken);
  }

  @override
  int syncWidth = 0;
  @override
  int syncOffset = 0;
  @override
  double frequencyOffset = 0;

  @override
  bool process(Float64List samples, int channelSelect) {
    if (_disposed) throw StateError('SSTV demodulator is disposed');
    RangeError.checkValueInInterval(channelSelect, 0, 4, 'channelSelect');
    if (samples.isEmpty) return false;
    RangeError.checkValueInInterval(samples.length, 1, 0x7fffffff, 'length');
    _reserveSamples(samples.length);
    final buffer = _samples.asTypedList(samples.length);
    buffer.setAll(0, samples);
    _process(_state, _samples, samples.length, channelSelect, _sync);
    final count = samples.length ~/ (channelSelect > 0 ? 2 : 1);
    samples.setRange(0, count, buffer);
    return _readSync();
  }

  void _reserveSamples(int length) {
    if (length > _capacity) {
      final next = calloc<Double>(length);
      if (_samples != nullptr) {
        _bufferFinalizer.detach(_samplesToken);
        calloc.free(_samples);
      }
      _samples = next;
      _capacity = length;
      _bufferFinalizer.attach(
        this,
        _samples.cast(),
        detach: _samplesToken,
        externalSize: _capacity * 8,
      );
    }
  }

  @override
  (Float64List, bool) processPcm16(Uint8List pcm, int offset, int length) {
    if (_disposed) throw StateError('SSTV demodulator is disposed');
    RangeError.checkValidRange(offset, offset + length, pcm.length);
    RangeError.checkValueInInterval(length, 0, 0x7fffffff, 'length');
    final count = length ~/ 2;
    if (count == 0) return (Float64List(0), false);
    final bytes = count * 2;
    _reserveSamples(count);
    if (bytes > _pcmCapacity) {
      final next = calloc<Uint8>(bytes);
      if (_pcm != nullptr) {
        _bufferFinalizer.detach(_pcmToken);
        calloc.free(_pcm);
      }
      _pcm = next;
      _pcmCapacity = bytes;
      _bufferFinalizer.attach(
        this,
        _pcm.cast(),
        detach: _pcmToken,
        externalSize: bytes,
      );
    }
    _pcm
        .asTypedList(bytes)
        .setAll(0, Uint8List.sublistView(pcm, offset, offset + bytes));
    _processPcm16(_state, _pcm, bytes, _samples, _sync);
    return (_samples.asTypedList(count), _readSync());
  }

  bool _readSync() {
    final result = _sync.ref;
    if (result.detected < 0) {
      throw StateError('Native SSTV demodulator rejected its arguments');
    }
    syncWidth = result.width;
    syncOffset = result.offset;
    frequencyOffset = result.frequencyOffset;
    return result.detected != 0;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateFinalizer.detach(this);
    _destroy(_state);
    _bufferFinalizer.detach(_syncToken);
    calloc.free(_sync);
    if (_samples != nullptr) {
      _bufferFinalizer.detach(_samplesToken);
      calloc.free(_samples);
    }
    if (_pcm != nullptr) {
      _bufferFinalizer.detach(_pcmToken);
      calloc.free(_pcm);
    }
  }
}
