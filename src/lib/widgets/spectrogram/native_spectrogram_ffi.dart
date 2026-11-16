// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_spectrogram.dart';
import 'spectrogram_colormap.dart';

const _asset = 'package:htcommander/xara_dsp';
final referenceOnly = Platform.environment['HT_SPECTROGRAM_DART'] == 'true';

@Native<Pointer<Void> Function(Int32, Int32, Int32, Int32, Pointer<Double>)>(
  symbol: 'ht_spectrogram_create',
  assetId: _asset,
)
external Pointer<Void> _create(
  int size,
  int step,
  int first,
  int last,
  Pointer<Double> window,
);
@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<Void> context);
@Native<Int32 Function(Pointer<Void>, Pointer<Double>, Int32)>(
  symbol: 'ht_spectrogram_add',
  assetId: _asset,
)
external int _add(Pointer<Void> context, Pointer<Double> samples, int count);
@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32)>(
  symbol: 'ht_spectrogram_pcm',
  assetId: _asset,
)
external int _pcm(Pointer<Void> context, Pointer<Uint8> samples, int count);
@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_process',
  assetId: _asset,
)
external int _process(Pointer<Void> context);
@Native<Int32 Function(Pointer<Void>, Int32)>(
  symbol: 'ht_spectrogram_resize',
  assetId: _asset,
)
external int _resize(Pointer<Void> context, int count);
@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_width',
  assetId: _asset,
  isLeaf: true,
)
external int _width(Pointer<Void> context);
@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_pending',
  assetId: _asset,
  isLeaf: true,
)
external int _pending(Pointer<Void> context);
@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_next',
  assetId: _asset,
  isLeaf: true,
)
external int _next(Pointer<Void> context);
@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: 'ht_spectrogram_roll_reset',
  assetId: _asset,
  isLeaf: true,
)
external void _rollReset(Pointer<Void> context, int offset);
@Native<Void Function(Pointer<Void>)>(
  symbol: 'ht_spectrogram_clear',
  assetId: _asset,
)
external void _clear(Pointer<Void> context);
@Native<Void Function(Pointer<Void>, Pointer<Double>)>(
  symbol: 'ht_spectrogram_peak',
  assetId: _asset,
)
external void _peak(Pointer<Void> context, Pointer<Double> result);
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Double,
    Double,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'ht_spectrogram_render', assetId: _asset)
external int _render(
  Pointer<Void> context,
  Pointer<Uint8> rgba,
  Pointer<Uint8> colors,
  double intensity,
  double dbScale,
  int decibel,
  int roll,
  int count,
);

NativeSpectrogram create(
  int size,
  int step,
  int first,
  int last,
  Float64List window,
) => _Spectrogram(size, step, first, last, window);

final class _Spectrogram implements NativeSpectrogram, Finalizable {
  static final _finalizer = NativeFinalizer(Native.addressOf(_destroy));
  static final _storageFinalizer = NativeFinalizer(calloc.nativeFree);
  final Object _storageToken = Object();
  Pointer<Void> _context = nullptr;
  Pointer<Uint8> _storage = nullptr;
  int _capacity = 0;
  final int height;

  _Spectrogram(int size, int step, int first, int last, Float64List window)
    : height = last - first {
    _ensure(size * sizeOf<Double>());
    _storage.cast<Double>().asTypedList(size).setAll(0, window);
    _context = _create(size, step, first, last, _storage.cast());
    if (_context == nullptr) {
      dispose();
      throw StateError('Cannot allocate native spectrogram');
    }
    _finalizer.attach(this, _context, detach: this, externalSize: size * 44);
  }

  Pointer<Void> get _alive {
    if (_context == nullptr) throw StateError('Spectrogram disposed');
    return _context;
  }

  void _ensure(int bytes) {
    if (bytes <= _capacity) return;
    RangeError.checkValueInInterval(
      bytes,
      1,
      0x7fffffff,
      'native buffer bytes',
    );
    final next = calloc<Uint8>(bytes);
    if (_storage != nullptr) {
      _storageFinalizer.detach(_storageToken);
      calloc.free(_storage);
    }
    _storage = next;
    _capacity = bytes;
    _storageFinalizer.attach(
      this,
      next.cast(),
      detach: _storageToken,
      externalSize: bytes,
    );
  }

  void _check(int status) {
    if (status != 0) throw StateError('Native spectrogram failed ($status)');
  }

  @override
  int get width => _width(_alive);
  @override
  int get pending => _pending(_alive);
  @override
  int get nextColumn => _next(_alive);
  @override
  void addSamples(Float64List samples, int offset, int count) {
    RangeError.checkValidRange(offset, offset + count, samples.length);
    _ensure(count * sizeOf<Double>());
    _storage
        .cast<Double>()
        .asTypedList(count)
        .setRange(0, count, samples, offset);
    _check(_add(_alive, _storage.cast(), count));
  }

  @override
  void addPcm16(Uint8List samples, int offset, int count) {
    RangeError.checkValidRange(offset, offset + count * 2, samples.length);
    _ensure(count * 2);
    _storage.asTypedList(count * 2).setRange(0, count * 2, samples, offset);
    _check(_pcm(_alive, _storage, count));
  }

  @override
  void process() => _check(_process(_alive));
  @override
  void setFixedWidth(int columns) {
    RangeError.checkValueInInterval(
      columns,
      -0x80000000,
      0x7fffffff,
      'columns',
    );
    _check(_resize(_alive, columns));
  }

  @override
  void rollReset(int offset) {
    RangeError.checkValueInInterval(offset, -0x80000000, 0x7fffffff, 'offset');
    _rollReset(_alive, offset);
  }

  @override
  void clear() => _clear(_alive);
  @override
  (double, double) peak() {
    _ensure(16);
    _peak(_alive, _storage.cast());
    final values = _storage.cast<Double>().asTypedList(2);
    return (values[0], values[1]);
  }

  @override
  void render(
    Uint8List rgba,
    SpectrogramColormap colormap,
    double intensity,
    double dbScale,
    bool decibel,
    bool roll,
    int count,
  ) {
    final bytes = width * height * 4;
    RangeError.checkValidRange(0, bytes, rgba.length);
    _ensure(bytes + 768);
    final colors = _storage + bytes;
    final tables = colors.asTypedList(768);
    tables.setAll(0, colormap.r);
    tables.setAll(256, colormap.g);
    tables.setAll(512, colormap.b);
    final pixels = _storage.asTypedList(bytes);
    if (count < width) pixels.setRange(0, bytes, rgba);
    _check(
      _render(
        _alive,
        _storage,
        colors,
        intensity,
        dbScale,
        decibel ? 1 : 0,
        roll ? 1 : 0,
        count,
      ),
    );
    rgba.setRange(0, bytes, pixels);
  }

  @override
  void dispose() {
    if (_context != nullptr) {
      _finalizer.detach(this);
      _destroy(_context);
      _context = nullptr;
    }
    if (_storage != nullptr) {
      _storageFinalizer.detach(_storageToken);
      calloc.free(_storage);
      _storage = nullptr;
      _capacity = 0;
    }
  }
}
