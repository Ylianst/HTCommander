// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'native_telemetry.dart';

const _asset = 'package:htcommander/telemetry_dsp';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

@Native<
  Pointer<Void> Function(
    Pointer<Void>,
    Int32,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
    Int32,
  )
>(symbol: 'ht_telemetry_recording_sonde', assetId: _asset)
external Pointer<Void> _sonde(
  Pointer<Void> recording,
  int rate,
  int mode,
  int chipRate,
  int symbols,
  Pointer<Double> header,
  int headerCount,
);

@Native<Pointer<Void> Function(Pointer<Void>, Int32, Double)>(
  symbol: 'ht_telemetry_recording_sarsat',
  assetId: _asset,
)
external Pointer<Void> _sarsat(
  Pointer<Void> recording,
  int rate,
  double carrier,
);

@Native<Pointer<Void> Function()>(
  symbol: 'ht_telemetry_create',
  assetId: _asset,
)
external Pointer<Void> _create();

@Native<Pointer<Int16> Function(Pointer<Void>, Int32)>(
  symbol: 'ht_telemetry_resize',
  assetId: _asset,
)
external Pointer<Int16> _resize(Pointer<Void> recording, int count);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_telemetry_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<Void> recording);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'ht_telemetry_count',
  assetId: _asset,
  isLeaf: true,
)
external int _count(Pointer<Void> result);

@Native<Int32 Function(Pointer<Void>, Int32)>(
  symbol: 'ht_telemetry_length',
  assetId: _asset,
  isLeaf: true,
)
external int _length(Pointer<Void> result, int frame);

@Native<Pointer<Uint8> Function(Pointer<Void>, Int32)>(
  symbol: 'ht_telemetry_data',
  assetId: _asset,
  isLeaf: true,
)
external Pointer<Uint8> _data(Pointer<Void> result, int frame);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_telemetry_free',
  assetId: _asset,
)
external void _free(Pointer<Void> result);

List<Uint8List> _frames(Pointer<Void> result) {
  if (result == nullptr) throw StateError('Native telemetry DSP failed');
  try {
    return [
      for (int i = 0; i < _count(result); i++)
        Uint8List.fromList(_data(result, i).asTypedList(_length(result, i))),
    ];
  } finally {
    _free(result);
  }
}

void _validate(int length, int rate) {
  RangeError.checkValueInInterval(length, 0, 0x7fffffff, 'length');
  RangeError.checkValueInInterval(rate, 8000, 384000, 'sampleRate');
}

List<Uint8List> sonde(
  Int16List pcm,
  int rate,
  int mode,
  int chipRate,
  int symbols,
  List<double> header,
) {
  final recording = createRecording();
  try {
    recording.upload(pcm, rate);
    return recording.sonde(
      NativeSondeMode.values[mode],
      chipRate,
      symbols,
      header,
    );
  } finally {
    recording.dispose();
  }
}

NativeTelemetryRecording createRecording() {
  final state = _create();
  if (state == nullptr) {
    throw StateError('Unable to allocate native telemetry recording');
  }
  try {
    return _Recording(state);
  } catch (_) {
    _destroy(state);
    rethrow;
  }
}

final class _Recording implements NativeTelemetryRecording, Finalizable {
  static final _stateFinalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _destroy,
    ).cast(),
  );
  static final _bufferFinalizer = NativeFinalizer(calloc.nativeFree);
  final Pointer<Void> _state;
  final Pointer<Double> _chips = calloc<Double>(1024);
  final Object _chipsToken = Object();
  int _length = 0;
  int _rate = 0;
  int _capacity = 0;
  bool _uploaded = false;
  bool _disposed = false;

  _Recording(this._state) {
    _stateFinalizer.attach(this, _state, detach: this);
    _bufferFinalizer.attach(
      this,
      _chips.cast(),
      detach: _chipsToken,
      externalSize: 8192,
    );
  }

  void _check() {
    if (_disposed) throw StateError('Native telemetry recording is disposed');
    if (!_uploaded) throw StateError('Native telemetry recording has no input');
  }

  @override
  void upload(Int16List pcm, int sampleRate) {
    if (_disposed) throw StateError('Native telemetry recording is disposed');
    _validate(pcm.length, sampleRate);
    _uploaded = false;
    final samples = _resize(_state, pcm.length);
    if (samples == nullptr && pcm.isNotEmpty) {
      throw StateError('Unable to resize native telemetry recording');
    }
    if (pcm.isNotEmpty) samples.asTypedList(pcm.length).setAll(0, pcm);
    _length = pcm.length;
    _rate = sampleRate;
    if (_length > _capacity) {
      _capacity = _length;
      _stateFinalizer.detach(this);
      _stateFinalizer.attach(
        this,
        _state,
        detach: this,
        externalSize: _capacity * 10,
      );
    }
    _uploaded = true;
  }

  @override
  List<Uint8List> sonde(
    NativeSondeMode sondeMode,
    int chipRate,
    int symbols,
    List<double> header,
  ) {
    _check();
    final mode = sondeMode.index;
    RangeError.checkValueInInterval(mode, 0, 4, 'mode');
    RangeError.checkValueInInterval(chipRate, 1, _rate, 'chipRate');
    RangeError.checkValueInInterval(symbols, 1, 1000000, 'frameSymbols');
    final alignment = switch (mode) {
      0 => 2,
      1 => 8,
      2 => 16,
      _ => 1,
    };
    if (symbols % alignment != 0) {
      throw ArgumentError.value(
        symbols,
        'frameSymbols',
        'Must be a multiple of $alignment',
      );
    }
    if (mode != 4 &&
        (header.isEmpty ||
            header.length > 1024 ||
            header.any((v) => v != 1 && v != -1))) {
      throw ArgumentError.value(
        header,
        'header',
        'Expected 1..1024 +/-1 chips',
      );
    }
    if (header.length > 1024) {
      throw ArgumentError.value(header.length, 'header', 'Maximum 1024 chips');
    }
    if (_length == 0) return const [];
    if (header.isNotEmpty) _chips.asTypedList(header.length).setAll(0, header);
    return _frames(
      _sonde(_state, _rate, mode, chipRate, symbols, _chips, header.length),
    );
  }

  @override
  List<Uint8List> sarsat(double carrier) {
    _check();
    if (!carrier.isFinite || carrier <= 250 || carrier + 250 >= _rate / 2) {
      throw ArgumentError.value(
        carrier,
        'carrier',
        'Search must be within Nyquist',
      );
    }
    if (_length < _rate ~/ 4) return const [];
    return _frames(_sarsat(_state, _rate, carrier));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateFinalizer.detach(this);
    _destroy(_state);
    _bufferFinalizer.detach(_chipsToken);
    calloc.free(_chips);
  }
}

List<Uint8List> sarsat(Int16List pcm, int rate, double carrier) {
  final recording = createRecording();
  try {
    recording.upload(pcm, rate);
    return recording.sarsat(carrier);
  } finally {
    recording.dispose();
  }
}
