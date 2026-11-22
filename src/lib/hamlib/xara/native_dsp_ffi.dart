// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_dsp.dart';

const _asset = 'package:htcommander/xara_dsp';
final _simd =
    const bool.fromEnvironment('HT_XARA_SCALAR') ||
        Platform.environment['HT_XARA_SCALAR'] == 'true'
    ? 0
    : 1;
final bool dartOnly = Platform.environment['HT_XARA_DART'] == 'true';

bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;
int get simdWidth => _simd == 0 ? 1 : _simdWidth();

@Native<Int32 Function()>(
  symbol: 'ht_xara_simd_width',
  assetId: _asset,
  isLeaf: true,
)
external int _simdWidth();

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Int32>,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'ht_xara_fft', assetId: _asset)
external void _fft(
  Pointer<Double> re,
  Pointer<Double> im,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  Pointer<Int32> reverse,
  int n,
  int inverse,
  int simd,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Int32>,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'ht_xara_fft_direct', assetId: _asset, isLeaf: true)
external void _fftDirect(
  Pointer<Double> re,
  Pointer<Double> im,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  Pointer<Int32> reverse,
  int n,
  int inverse,
  int simd,
  Pointer<Double> work,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
    Int32,
  )
>(symbol: 'ht_xara_fir', assetId: _asset)
external void _fir(
  Pointer<Double> x,
  Pointer<Double> hr,
  Pointer<Double> hi,
  int taps,
  int dec,
  int count,
  Pointer<Double> out,
  int simd,
);

@Native<
  Void Function(
    Pointer<Float>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Double>,
    Int32,
    Int32,
    Int32,
    Int32,
    Double,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
  )
>(symbol: 'ht_xara_correlate', assetId: _asset)
external void _correlate(
  Pointer<Float> diff,
  int capacity,
  Pointer<Int32> rows,
  Pointer<Int32> bins,
  Pointer<Double> refs,
  int markers,
  int cells,
  int first,
  int count,
  double markerMin,
  Pointer<Double> scratch,
  Pointer<Double> out,
  int simd,
);

@Native<Void Function(Pointer<Float>, Int32, Int32, Int32, Pointer<Float>)>(
  symbol: 'ht_xara_append_row',
  assetId: _asset,
)
external void _appendRow(
  Pointer<Float> diff,
  int capacity,
  int width,
  int index,
  Pointer<Float> row,
);

@Native<
  Void Function(
    Pointer<Float>,
    Int32,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Float>,
    Pointer<Float>,
    Int32,
    Int32,
  )
>(symbol: 'ht_xara_append_spectrum', assetId: _asset, isLeaf: true)
external void _appendSpectrum(
  Pointer<Float> diff,
  int capacity,
  int index,
  Pointer<Double> re,
  Pointer<Double> im,
  Pointer<Float> previous,
  Pointer<Float> row,
  int n,
  int hasPrevious,
);

final class _Resampled extends Struct {
  @Int32()
  external int index;
  @Int32()
  external int count;
  @Double()
  external double fraction;
}

@Native<
  Int32 Function(
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Int32,
    Int32,
    Int32,
    Double,
    Int32,
    Double,
    Pointer<Double>,
    Int32,
    Pointer<_Resampled>,
    Int32,
  )
>(symbol: 'ht_xara_resample', assetId: _asset)
external int _resample(
  Pointer<Double> x,
  int length,
  Pointer<Double> table,
  int half,
  int phases,
  int index,
  double fraction,
  int whole,
  double part,
  Pointer<Double> out,
  int capacity,
  Pointer<_Resampled> result,
  int simd,
);

@Native<
  Int32 Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Int32>,
    Int32,
    Int32,
    Double,
    Int32,
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Uint8>,
  )
>(symbol: 'ht_xara_turbo', assetId: _asset)
external int _turbo(
  Pointer<Double> ls,
  Pointer<Double> lp1,
  Pointer<Double> ls2,
  Pointer<Double> lp2,
  Pointer<Int32> perm,
  int k,
  int iters,
  double scale,
  int minIters,
  Pointer<Uint8> white,
  int whiteLength,
  int nbytes,
  Pointer<Uint8> bits,
);

// Each plan owns reusable storage. Attaching the finalizer to the Finalizable
// receiver keeps that storage alive throughout its FFI calls.
abstract class _Storage implements Finalizable {
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  Pointer<Uint8> _memory = nullptr;
  int _capacity = 0;

  bool _ensure(int bytes) {
    if (bytes <= _capacity) return false;
    RangeError.checkValueInInterval(
      bytes,
      1,
      0x7fffffff,
      'native buffer bytes',
    );
    final capacity = bytes > 2 * _capacity ? bytes : 2 * _capacity;
    final next = calloc<Uint8>(capacity);
    if (_memory != nullptr) {
      _finalizer.detach(this);
      calloc.free(_memory);
    }
    _memory = next;
    _capacity = capacity;
    _finalizer.attach(
      this,
      _memory.cast(),
      detach: this,
      externalSize: capacity,
    );
    return true;
  }
}

NativeXaraFft createFft(
  Float64List cosine,
  Float64List sine,
  Int32List reverse,
) => _Fft(cosine, sine, reverse);

final class _Fft extends _Storage implements NativeXaraFft {
  final int n;
  late final Pointer<Double> _re, _im, _cosine, _sine;
  late final Pointer<Int32> _reverse;

  _Fft(Float64List cosine, Float64List sine, Int32List reverse)
    : n = reverse.length {
    if (n < 1 ||
        (n & (n - 1)) != 0 ||
        cosine.length != n ~/ 2 ||
        sine.length != n ~/ 2) {
      throw ArgumentError('Invalid native XARA FFT tables');
    }
    for (final index in reverse) {
      RangeError.checkValueInInterval(index, 0, n - 1, 'FFT reverse index');
    }
    _ensure(4 * n * sizeOf<Double>() + n * sizeOf<Int32>());
    _re = _memory.cast();
    _im = _re + n;
    _cosine = _im + n;
    _sine = _cosine + n;
    _reverse = (_sine + n).cast();
    _cosine.asTypedList(cosine.length).setAll(0, cosine);
    _sine.asTypedList(sine.length).setAll(0, sine);
    _reverse.asTypedList(n).setAll(0, reverse);
  }

  @override
  void transform(Float64List re, Float64List im, bool inverse) {
    RangeError.checkValidRange(0, n, re.length);
    RangeError.checkValidRange(0, n, im.length);
    // Pin Dart storage only for short transforms; larger FFTs remain non-leaf.
    if (n <= 2048) {
      _fftDirect(
        re.address,
        im.address,
        _cosine,
        _sine,
        _reverse,
        n,
        inverse ? 1 : 0,
        _simd,
        _re,
      );
      return;
    }
    final r = _re.asTypedList(n), i = _im.asTypedList(n);
    r.setRange(0, n, re);
    i.setRange(0, n, im);
    _fft(_re, _im, _cosine, _sine, _reverse, n, inverse ? 1 : 0, _simd);
    re.setRange(0, n, r);
    im.setRange(0, n, i);
  }
}

NativeXaraFir createFir(Float64List hr, Float64List hi, int dec) =>
    _Fir(hr, hi, dec);

final class _Fir extends _Storage implements NativeXaraFir {
  final Float64List hr, hi;
  final int dec;

  _Fir(Float64List real, Float64List imag, this.dec)
    : hr = Float64List.fromList(real.reversed.toList()),
      hi = Float64List.fromList(imag.reversed.toList()) {
    if (real.isEmpty || real.length != imag.length || dec < 1) {
      throw ArgumentError('Invalid native XARA FIR taps or decimation');
    }
    RangeError.checkValueInInterval(dec, 1, 0x7fffffff, 'decimation');
  }

  @override
  Float64List process(Float64List samples, int count) {
    final taps = hr.length;
    RangeError.checkNotNegative(count, 'count');
    if (count == 0) return Float64List(0);
    final length = taps + (count - 1) * dec;
    if (samples.length != length) {
      throw ArgumentError('Invalid XARA FIR input length');
    }
    if (_ensure((2 * taps + length + 2 * count) * sizeOf<Double>())) {
      _memory.cast<Double>().asTypedList(2 * taps)
        ..setAll(0, hr)
        ..setAll(taps, hi);
    }
    final h = _memory.cast<Double>(), x = h + 2 * taps, out = x + length;
    x.asTypedList(length).setAll(0, samples);
    _fir(x, h, h + taps, taps, dec, count, out, _simd);
    return Float64List.fromList(out.asTypedList(2 * count));
  }
}

NativeXaraRows createRows(int capacity, int width) => _Rows(capacity, width);

final class _Rows extends _Storage implements NativeXaraRows {
  final int capacity, width;
  int base = 0, end = 0;

  _Rows(this.capacity, this.width) {
    RangeError.checkValueInInterval(capacity, 1, 0x7fffffff, 'capacity');
    RangeError.checkValueInInterval(width, 1, 0x7fffffff, 'width');
    _ensure((capacity + 1) * width * sizeOf<Float>());
  }

  @override
  int get storageBytes => _capacity;

  @override
  void append(int index, Float32List row) {
    RangeError.checkNotNegative(index, 'row index');
    if (row.length != width) {
      throw ArgumentError('Invalid native XARA row width');
    }
    if (index != end) base = index;
    final samples = _memory.cast<Float>();
    final input = samples + capacity * width;
    input.asTypedList(width).setAll(0, row);
    _appendRow(samples, capacity, width, index % capacity, input);
    end = index + 1;
    if (end - base > capacity) base = end - capacity;
  }

  @override
  void appendSpectrum(
    int index,
    Float64List re,
    Float64List im,
    Float32List row,
    Float32List? previous,
  ) {
    RangeError.checkNotNegative(index, 'row index');
    final n = width ~/ 2;
    if (width.isOdd ||
        n < 1 ||
        n > 128 ||
        row.length != width ||
        re.length < n ||
        im.length < n ||
        (previous != null && previous.length != width)) {
      throw ArgumentError('Invalid native XARA spectrum dimensions');
    }
    final prior = previous ?? row;
    _appendSpectrum(
      _memory.cast(),
      capacity,
      index % capacity,
      re.address,
      im.address,
      prior.address,
      row.address,
      n,
      previous == null ? 0 : 1,
    );
    if (index != end) base = index;
    end = index + 1;
    if (end - base > capacity) base = end - capacity;
  }
}

NativeXaraPattern createPattern(
  Int32List rows,
  Int32List bins,
  Float64List refs,
  int markers,
) => _Pattern(rows, bins, refs, markers);

final class _Pattern extends _Storage implements NativeXaraPattern {
  final Int32List rows, bins;
  final Float64List refs;
  final int markers;
  late final int _maxRow, _maxBin;

  _Pattern(Int32List rows, Int32List bins, Float64List refs, this.markers)
    : rows = Int32List.fromList(rows),
      bins = Int32List.fromList(bins),
      refs = Float64List.fromList(refs) {
    if (markers < 1 ||
        markers > rows.length ||
        bins.length != rows.length ||
        refs.length != 2 * rows.length) {
      throw ArgumentError('Invalid native XARA pattern');
    }
    int maxRow = 0, maxBin = 0;
    for (int c = 0; c < rows.length; c++) {
      RangeError.checkNotNegative(rows[c], 'pattern row');
      RangeError.checkNotNegative(bins[c], 'pattern bin');
      if (rows[c] > maxRow) maxRow = rows[c];
      if (bins[c] > maxBin) maxBin = bins[c];
    }
    _maxRow = maxRow;
    _maxBin = maxBin;
  }

  @override
  Float64List terms(
    NativeXaraRows source,
    int first,
    int last, [
    double markerMin = double.negativeInfinity,
  ]) {
    if (source is! _Rows ||
        first < source.base ||
        last < first ||
        last + _maxRow >= source.end ||
        _maxBin + 1 >= source.width) {
      throw ArgumentError('Native XARA pattern outside available spectra');
    }
    final count = last - first + 1, cells = rows.length;
    if (_ensure(cells * 3 * sizeOf<Double>() + 6 * count * sizeOf<Double>())) {
      final indices = _memory.cast<Int32>().asTypedList(2 * cells);
      indices
        ..setAll(0, rows)
        ..setAll(cells, bins);
      (_memory.cast<Double>() + cells).asTypedList(2 * cells).setAll(0, refs);
    }
    final r = _memory.cast<Int32>(), b = r + cells;
    final ref = _memory.cast<Double>() + cells;
    final scratch = ref + 2 * cells, out = scratch + 4 * count;
    _correlate(
      source._memory.cast(),
      source.capacity,
      r,
      b,
      ref,
      markers,
      cells,
      first % source.capacity,
      count,
      markerMin,
      scratch,
      out,
      _simd,
    );
    return Float64List.fromList(out.asTypedList(2 * count));
  }
}

NativeXaraResampler createResampler(Float64List table, int half, int phases) =>
    _Resampler(table, half, phases);

final class _Resampler extends _Storage implements NativeXaraResampler {
  final Float64List table;
  final int half, phases;

  _Resampler(Float64List table, this.half, this.phases)
    : table = Float64List.fromList(table) {
    if (half < 1 || phases < 1 || table.length != (phases + 1) * 2 * half) {
      throw ArgumentError('Invalid native XARA resampler kernel');
    }
    RangeError.checkValueInInterval(
      table.length,
      1,
      0x7fffffff,
      'kernel length',
    );
  }

  @override
  (List<double>, int, double) process(
    List<double> samples,
    int index,
    double fraction,
    int whole,
    double part,
  ) {
    RangeError.checkValueInInterval(index, half - 1, 0x7fffffff, 'index');
    RangeError.checkValueInInterval(samples.length, 0, 0x7fffffff, 'length');
    if (!fraction.isFinite ||
        fraction < 0 ||
        fraction >= 1 ||
        whole < 0 ||
        whole > 0x7fffffff ||
        !part.isFinite ||
        part < 0 ||
        part >= 1 ||
        (whole == 0 && part == 0)) {
      throw ArgumentError('Invalid native XARA resampler phase or step');
    }
    final available = samples.length - half - index;
    if (available <= 0) return (<double>[], index, fraction);
    final capacity = (available / (whole + part)).ceil() + 1;
    if (_ensure(
      (table.length + samples.length + capacity) * sizeOf<Double>() +
          sizeOf<_Resampled>(),
    )) {
      _memory.cast<Double>().asTypedList(table.length).setAll(0, table);
    }
    final h = _memory.cast<Double>(), x = h + table.length;
    final out = x + samples.length,
        result = (out + capacity).cast<_Resampled>();
    x.asTypedList(samples.length).setAll(0, samples);
    final status = _resample(
      x,
      samples.length,
      h,
      half,
      phases,
      index,
      fraction,
      whole,
      part,
      out,
      capacity,
      result,
      _simd,
    );
    if (status != 0) throw StateError('Native XARA resample failed ($status)');
    final count = result.ref.count;
    if (count < 0 || count > capacity) {
      throw StateError('Invalid native XARA resample result');
    }
    return (
      Float64List.fromList(out.asTypedList(count)),
      result.ref.index,
      result.ref.fraction,
    );
  }
}

(Uint8List, int) decodeTurbo(
  Float64List ls,
  Float64List lp1,
  Float64List ls2,
  Float64List lp2,
  List<int> perm,
  int iters,
  double scale,
  int minIters,
  List<int> white,
  int nbytes,
) {
  final k = perm.length, tlen = k + 3;
  if (k < 1 ||
      k > 0x7ffff000 ||
      ls.length != tlen ||
      lp1.length != tlen ||
      ls2.length != tlen ||
      lp2.length != tlen ||
      iters < 0 ||
      iters >= 0x7fffffff ||
      minIters < 0 ||
      !scale.isFinite ||
      nbytes < 0 ||
      nbytes > k ~/ 8) {
    throw ArgumentError('Invalid native XARA turbo decoder input');
  }
  // Validate before narrowing Dart ints to the native permutation's int32.
  for (final p in perm) {
    RangeError.checkValueInInterval(p, 0, k - 1, 'permutation');
  }
  return using((arena) {
    final input = arena<Double>(4 * tlen);
    input.asTypedList(4 * tlen)
      ..setAll(0, ls)
      ..setAll(tlen, lp1)
      ..setAll(2 * tlen, ls2)
      ..setAll(3 * tlen, lp2);
    final permutation = arena<Int32>(k);
    permutation.asTypedList(k).setAll(0, perm);
    final whitening = arena<Uint8>(white.length);
    whitening.asTypedList(white.length).setAll(0, white);
    final bits = arena<Uint8>(k);
    final ran = _turbo(
      input,
      input + tlen,
      input + 2 * tlen,
      input + 3 * tlen,
      permutation,
      k,
      iters,
      scale,
      minIters,
      whitening,
      white.length,
      nbytes,
      bits,
    );
    if (ran < 0) throw StateError('Native XARA turbo decode failed ($ran)');
    return (Uint8List.fromList(bits.asTypedList(k)), ran);
  });
}
