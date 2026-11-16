// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'native_satellite.dart';

const _asset = 'package:htcommander/satellite_sgp4';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

final class _Engine extends Opaque {}

@Native<Int32 Function()>(symbol: 'ht_satellite_abi', assetId: _asset)
external int _abi();
@Native<Int32 Function()>(
  symbol: 'ht_satellite_coefficient_count',
  assetId: _asset,
)
external int _coefficientCount();
@Native<Pointer<_Engine> Function()>(
  symbol: 'ht_satellite_create',
  assetId: _asset,
)
external Pointer<_Engine> _create();
@Native<Void Function(Pointer<_Engine>)>(
  symbol: 'ht_satellite_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<_Engine> handle);
@Native<Pointer<Double> Function(Pointer<_Engine>)>(
  symbol: 'ht_satellite_coefficients',
  assetId: _asset,
)
external Pointer<Double> _coefficients(Pointer<_Engine> handle);
@Native<Pointer<Double> Function(Pointer<_Engine>)>(
  symbol: 'ht_satellite_times',
  assetId: _asset,
)
external Pointer<Double> _times(Pointer<_Engine> handle);
@Native<Pointer<Double> Function(Pointer<_Engine>)>(
  symbol: 'ht_satellite_rows',
  assetId: _asset,
)
external Pointer<Double> _rows(Pointer<_Engine> handle);
@Native<Void Function(Pointer<_Engine>)>(
  symbol: 'ht_satellite_init',
  assetId: _asset,
)
external void _init(Pointer<_Engine> handle);
@Native<Int32 Function(Pointer<_Engine>, Int32)>(
  symbol: 'ht_satellite_batch',
  assetId: _asset,
)
external int _batch(Pointer<_Engine> handle, int count);

@Native<Void Function(Pointer<_Engine>, Double, Double, Double)>(
  symbol: 'ht_satellite_observer',
  assetId: _asset,
)
external void _observer(
  Pointer<_Engine> handle,
  double latitude,
  double longitude,
  double altitude,
);
@Native<Int32 Function(Pointer<_Engine>, Int64, Int64, Int64, Int64, Int32)>(
  symbol: 'ht_satellite_look_grid',
  assetId: _asset,
)
external int _lookGrid(
  Pointer<_Engine> handle,
  int epochUs,
  int startUs,
  int stepUs,
  int toUs,
  int count,
);

NativeSatellite create(Float64List coefficients) {
  if (_abi() != 2 || _coefficientCount() != coefficients.length) {
    throw StateError('Incompatible satellite native ABI');
  }
  return _NativeSatellite(coefficients);
}

final class _NativeSatellite implements NativeSatellite, Finalizable {
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<_Engine>)>>(
      _destroy,
    ).cast(),
  );
  final Pointer<_Engine> _handle;
  late final Float64List _input;
  late final Float64List _output;
  bool _disposed = false;

  _NativeSatellite(Float64List coefficients) : _handle = _create() {
    if (_handle == nullptr) throw StateError('Satellite allocation failed');
    try {
      _coefficients(
        _handle,
      ).asTypedList(coefficients.length).setAll(0, coefficients);
      _init(_handle);
      _input = _times(_handle).asTypedList(256);
      _output = _rows(_handle).asTypedList(256 * 7);
      _finalizer.attach(this, _handle.cast(), detach: this);
    } catch (_) {
      _destroy(_handle);
      rethrow;
    }
  }

  @override
  Float64List propagate(Float64List minutes) {
    if (_disposed) throw StateError('Satellite engine disposed');
    final result = Float64List(minutes.length * 7);
    for (var offset = 0; offset < minutes.length; offset += 256) {
      final count = math.min(256, minutes.length - offset);
      _input.setRange(0, count, minutes, offset);
      if (_batch(_handle, count) != 0) {
        throw StateError('Invalid native satellite batch');
      }
      result.setRange(offset * 7, (offset + count) * 7, _output);
    }
    return result;
  }

  @override
  Float64List lookGrid({
    required int epochUs,
    required int fromUs,
    required int toUs,
    required int stepUs,
    required double latitudeDeg,
    required double longitudeDeg,
    required double altitudeMeters,
  }) {
    if (_disposed) throw StateError('Satellite engine disposed');
    if (fromUs >= toUs || stepUs <= 0) {
      throw ArgumentError('Invalid native look-angle grid');
    }
    final span = toUs - fromUs;
    final samples = (span + stepUs - 1) ~/ stepUs + 1;
    final result = Float64List(samples * 5);
    _observer(_handle, latitudeDeg, longitudeDeg, altitudeMeters);
    for (var offset = 0; offset < samples; offset += 256) {
      final count = math.min(256, samples - offset);
      if (_lookGrid(
            _handle,
            epochUs,
            fromUs + offset * stepUs,
            stepUs,
            toUs,
            count,
          ) !=
          0) {
        throw StateError('Invalid native satellite look-angle batch');
      }
      result.setRange(offset * 5, (offset + count) * 5, _output);
    }
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _destroy(_handle);
  }
}
