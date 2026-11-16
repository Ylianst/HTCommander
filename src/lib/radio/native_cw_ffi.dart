// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_cw.dart';

const _asset = 'package:htcommander/cw_dsp';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

@Native<Pointer<Void> Function(Pointer<Double>, Int32, Int32, Int32)>(
  symbol: 'ht_cw_create',
  assetId: _asset,
)
external Pointer<Void> _create(
  Pointer<Double> coefficients,
  int probes,
  int window,
  int hop,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'ht_cw_destroy', assetId: _asset)
external void _destroy(Pointer<Void> state);

@Native<Pointer<Double> Function(Pointer<Void>, Int32)>(
  symbol: 'ht_cw_prepare',
  assetId: _asset,
)
external Pointer<Double> _prepare(Pointer<Void> state, int windows);

@Native<Int32 Function(Pointer<Void>, Int32)>(
  symbol: 'ht_cw_process',
  assetId: _asset,
)
external int _process(Pointer<Void> state, int windows);

@Native<Pointer<Double> Function(Pointer<Void>)>(
  symbol: 'ht_cw_metrics',
  assetId: _asset,
  isLeaf: true,
)
external Pointer<Double> _metrics(Pointer<Void> state);

NativeCw create(Float64List coefficients, int window, int hop) {
  RangeError.checkValueInInterval(coefficients.length, 1, 4096, 'probes');
  RangeError.checkValueInInterval(window, 1, 1048576, 'window');
  RangeError.checkValueInInterval(hop, 1, window, 'hop');
  if (coefficients.any((value) => !value.isFinite)) {
    throw ArgumentError.value(coefficients, 'coefficients', 'Must be finite');
  }
  final c = calloc<Double>(coefficients.length);
  try {
    c.asTypedList(coefficients.length).setAll(0, coefficients);
    final state = _create(c, coefficients.length, window, hop);
    if (state == nullptr) throw StateError('Unable to allocate native CW DSP');
    try {
      return _Cw(state, window, hop);
    } catch (_) {
      _destroy(state);
      rethrow;
    }
  } finally {
    calloc.free(c);
  }
}

final class _Cw implements NativeCw, Finalizable {
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _destroy,
    ).cast(),
  );
  final Pointer<Void> _state;
  final int _window;
  final int _hop;
  bool _disposed = false;
  int _capacity = 0;

  _Cw(this._state, this._window, this._hop) {
    _finalizer.attach(this, _state, detach: this);
  }

  @override
  Float64List analyze(List<double> samples, int start, int windows) {
    if (_disposed) throw StateError('Native CW DSP is disposed');
    RangeError.checkValueInInterval(windows, 1, NativeCw.maxWindows, 'windows');
    final count = _window + (windows - 1) * _hop;
    RangeError.checkValidRange(start, start + count, samples.length);
    final input = _prepare(_state, windows);
    if (input == nullptr) throw StateError('Unable to resize native CW DSP');
    if (count > _capacity) {
      _capacity = count;
      _finalizer.detach(this);
      _finalizer.attach(
        this,
        _state,
        detach: this,
        externalSize: (count + windows * 3) * 8,
      );
    }
    final view = input.asTypedList(count);
    for (int i = 0; i < count; i++) {
      view[i] = samples[start + i];
    }
    final status = _process(_state, windows);
    if (status != 0) {
      throw StateError('Native CW DSP failed (status $status)');
    }
    final metrics = _metrics(_state);
    if (metrics == nullptr) {
      throw StateError('Native CW DSP returned no metrics');
    }
    return metrics.asTypedList(windows * 3);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _destroy(_state);
  }
}
