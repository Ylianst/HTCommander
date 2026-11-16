// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_reed_solomon.dart';

const _asset = 'package:htcommander/reed_solomon';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

@Native<
  Pointer<Void> Function(
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
  )
>(symbol: 'ht_rs_create', assetId: _asset)
external Pointer<Void> _create(
  int mode,
  int roots,
  int fcr,
  int prim,
  int inversePrim,
  Pointer<Uint8> exp,
  Pointer<Uint8> log,
  Pointer<Uint8> generator,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'ht_rs_destroy', assetId: _asset)
external void _destroy(Pointer<Void> plan);

@Native<Pointer<Uint8> Function(Pointer<Void>)>(
  symbol: 'ht_rs_buffer',
  assetId: _asset,
)
external Pointer<Uint8> _buffer(Pointer<Void> plan);

@Native<Int32 Function(Pointer<Void>, Int32, Int32)>(
  symbol: 'ht_rs_process',
  assetId: _asset,
)
external int _process(Pointer<Void> plan, int encode, int erasures);

NativeReedSolomon create(
  int mode,
  int roots,
  int fcr,
  int prim,
  int inversePrim,
  List<int> exp,
  List<int> log,
  List<int> generator,
) {
  if (!supported) throw UnsupportedError('Native Reed-Solomon unavailable');
  RangeError.checkValueInInterval(mode, 0, 1, 'mode');
  RangeError.checkValueInInterval(roots, 1, 254, 'roots');
  RangeError.checkValueInInterval(fcr, 0, 254, 'fcr');
  RangeError.checkValueInInterval(prim, 1, 254, 'prim');
  RangeError.checkValueInInterval(inversePrim, 1, 254, 'inversePrim');
  if (exp.length < 256 || log.length != 256 || generator.length != roots + 1) {
    throw ArgumentError('Invalid native Reed-Solomon table lengths');
  }
  for (final table in [exp, log, generator]) {
    if (table is! Uint8List) {
      for (final symbol in table) {
        RangeError.checkValueInInterval(symbol, 0, 255, 'table symbol');
      }
    }
  }
  final tables = calloc<Uint8>(768);
  try {
    tables.asTypedList(256).setAll(0, exp.take(256));
    (tables + 256).asTypedList(256).setAll(0, log);
    (tables + 512).asTypedList(256).setAll(0, generator);
    final plan = _create(
      mode,
      roots,
      fcr,
      prim,
      inversePrim,
      tables,
      tables + 256,
      tables + 512,
    );
    if (plan == nullptr) throw StateError('Native Reed-Solomon plan failed');
    try {
      return _Plan(plan, mode, roots);
    } catch (_) {
      _destroy(plan);
      rethrow;
    }
  } finally {
    calloc.free(tables);
  }
}

final class _Plan implements NativeReedSolomon, Finalizable {
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _destroy,
    ).cast(),
  );
  final Pointer<Void> _handle;
  final int _mode;
  final int _roots;
  late final Uint8List _bytes;
  bool _disposed = false;

  _Plan(this._handle, this._mode, this._roots) {
    _bytes = _buffer(_handle).asTypedList(510);
    _finalizer.attach(
      this,
      _handle,
      detach: this,
      externalSize: _mode == 0 ? 90000 : 24000,
    );
  }

  void _check(List<int> data, int length) {
    if (_disposed) throw StateError('Native Reed-Solomon plan disposed');
    RangeError.checkValidRange(0, length, data.length);
    // Uint8List already guarantees valid field symbols.
    if (data is! Uint8List) {
      for (int i = 0; i < length; i++) {
        RangeError.checkValueInInterval(data[i], 0, 255, 'symbol');
      }
    }
  }

  @override
  void encode(List<int> data, [List<int>? parity]) {
    final length = _mode == 0 ? 255 : 255 - _roots;
    _check(data, length);
    if (_mode == 1) {
      if (parity == null) throw ArgumentError.notNull('parity');
      RangeError.checkValidRange(0, _roots, parity.length);
    }
    _bytes.setRange(0, length, data);
    final status = _process(_handle, 1, 0);
    if (status != 0) throw StateError('Native RS encode failed ($status)');
    if (_mode == 0) {
      data.setRange(0, _roots, _bytes);
    } else {
      parity!.setRange(0, _roots, _bytes, length);
    }
  }

  @override
  int decode(List<int> data, [List<int>? erasures, int count = 0]) {
    _check(data, 255);
    RangeError.checkValueInInterval(count, 0, _roots, 'count');
    if (count > 0) {
      if (erasures == null) throw ArgumentError.notNull('erasures');
      RangeError.checkValidRange(0, count, erasures.length);
      for (int i = 0; i < count; i++) {
        RangeError.checkValueInInterval(erasures[i], 0, 254, 'erasure');
      }
      _bytes.setRange(255, 255 + count, erasures);
    }
    _bytes.setRange(0, 255, data);
    final status = _process(_handle, 0, count);
    if (status < -1) throw StateError('Native RS decode failed ($status)');
    // Both reference decoders may mutate the block before returning -1.
    // Avoid writes when decoding did not change data (also permits read-only
    // clean codewords, just as the reference does).
    if (status != 0) {
      for (int i = 0; i < 255; i++) {
        if (data[i] != _bytes[i]) data[i] = _bytes[i];
      }
    }
    return status;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _destroy(_handle);
  }
}
