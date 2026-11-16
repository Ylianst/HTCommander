// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_scanline.dart';

bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;

@Native<
  Int32 Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Double,
    Double,
  )
>(symbol: 'ht_sstv_scanline', assetId: 'package:htcommander/sstv_dsp')
external int _process(
  Pointer<Double> input,
  Pointer<Double> scratch,
  Pointer<Int32> pixels,
  Pointer<Int32> config,
  double alpha,
  double offset,
);

NativeSstvScanLine create() => _ScanLine();

final class _ScanLine implements NativeSstvScanLine, Finalizable {
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  Pointer<Double> _storage = nullptr;
  int _capacity = 0;
  bool _disposed = false;

  @override
  void process(
    Float64List input,
    int start,
    Float64List scratch,
    int scratchStart,
    Int32List pixels,
    List<int> config,
    double alpha,
    double frequencyOffset,
  ) {
    if (_disposed) throw StateError('SSTV scanline is disposed');
    if (config.length != 11) {
      throw ArgumentError.value(config.length, 'config.length', 'Must be 11');
    }
    for (int i = 0; i < config.length; ++i) {
      RangeError.checkValueInInterval(
        config[i],
        -0x80000000,
        0x7fffffff,
        'config[$i]',
      );
    }
    final count = config[2];
    final width = config[1];
    final kind = config[0];
    RangeError.checkValueInInterval(kind, 0, 5, 'kind');
    RangeError.checkValueInInterval(width, 1, 0x7fffffff, 'width');
    RangeError.checkValueInInterval(count, 1, 0x7fffffff, 'count');
    final pixelCount = width * (kind >= 2 && kind <= 4 ? 2 : 1);
    RangeError.checkValueInInterval(pixelCount, 1, 0x7fffffff, 'pixelCount');
    RangeError.checkValidRange(start, start + count, input.length);
    RangeError.checkValidRange(
      scratchStart,
      scratchStart + count,
      scratch.length,
    );
    RangeError.checkValidRange(0, pixelCount, pixels.length);
    final bytes = count * 16 + pixelCount * 4 + 11 * 4;
    if (bytes > _capacity) {
      final next = calloc<Double>((bytes + 7) ~/ 8);
      if (_storage != nullptr) {
        _finalizer.detach(this);
        calloc.free(_storage);
      }
      _storage = next;
      _capacity = bytes;
      _finalizer.attach(
        this,
        _storage.cast(),
        detach: this,
        externalSize: bytes,
      );
    }
    final filtered = _storage + count;
    final output = (filtered + count).cast<Int32>();
    final parameters = output + pixelCount;
    _storage.asTypedList(count).setRange(0, count, input, start);
    // Only Robot36 reads existing pixels or preserves an unwritten second row.
    // Other kernels overwrite every output pixel, so avoid copying them in.
    if (kind == 3 || kind == 4) {
      output.asTypedList(pixelCount).setRange(0, pixelCount, pixels);
    }
    parameters.asTypedList(11).setAll(0, config);
    final status = _process(
      _storage,
      filtered,
      output,
      parameters,
      alpha,
      frequencyOffset,
    );
    if (status != 0) throw StateError('Native SSTV scanline failed ($status)');
    scratch.setRange(
      scratchStart,
      scratchStart + count,
      filtered.asTypedList(count),
    );
    pixels.setRange(0, pixelCount, output.asTypedList(pixelCount));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_storage != nullptr) {
      _finalizer.detach(this);
      calloc.free(_storage);
      _storage = nullptr;
    }
  }
}
