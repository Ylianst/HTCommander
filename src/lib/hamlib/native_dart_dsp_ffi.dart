// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_dart_dsp.dart';

const _asset = 'package:htcommander/dart_dsp';
bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;
final referenceOnly = Platform.environment['HT_DART_REFERENCE'] == 'true';
final _simd =
    const bool.fromEnvironment('HT_DART_SCALAR') ||
        Platform.environment['HT_DART_SCALAR'] == 'true'
    ? 0
    : 1;
int get simdWidth => _simd == 0 ? 1 : _simdWidth();

@Native<Int32 Function()>(
  symbol: 'ht_dart_simd_width',
  assetId: _asset,
  isLeaf: true,
)
external int _simdWidth();

@Native<Double Function(Pointer<Double>, Int32, Int32)>(
  symbol: 'ht_dart_peak',
  assetId: _asset,
  isLeaf: true,
)
external double _peak(Pointer<Double> samples, int count, int simd);

@Native<Int32 Function(Pointer<Double>, Int32, Double, Pointer<Int16>, Int32)>(
  symbol: 'ht_dart_to_pcm',
  assetId: _asset,
  isLeaf: true,
)
external int _toPcm(
  Pointer<Double> samples,
  int count,
  double scale,
  Pointer<Int16> out,
  int simd,
);

@Native<Void Function(Pointer<Int16>, Int32, Pointer<Double>, Int32)>(
  symbol: 'ht_dart_from_pcm',
  assetId: _asset,
  isLeaf: true,
)
external void _fromPcm(
  Pointer<Int16> samples,
  int count,
  Pointer<Double> out,
  int simd,
);

double peak(Float64List samples) {
  RangeError.checkValueInInterval(samples.length, 1, 4096, 'peak samples');
  return _peak(samples.address, samples.length, _simd);
}

void toPcm(Float64List samples, double scale, Int16List out) {
  RangeError.checkValueInInterval(samples.length, 1, 4096, 'PCM samples');
  if (out.length != samples.length) {
    throw ArgumentError('Invalid PCM output length');
  }
  if (_toPcm(samples.address, samples.length, scale, out.address, _simd) != 0) {
    throw ArgumentError('Cannot convert non-finite DART samples to PCM');
  }
}

void fromPcm(Int16List samples, Float64List out) {
  RangeError.checkValueInInterval(samples.length, 1, 4096, 'PCM samples');
  if (out.length != samples.length) {
    throw ArgumentError('Invalid PCM output length');
  }
  _fromPcm(samples.address, samples.length, out.address, _simd);
}

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Int32,
  )
>(symbol: 'ht_dart_multiply_conjugate', assetId: _asset, isLeaf: true)
external void _multiplyConjugate(
  Pointer<Double> re,
  Pointer<Double> im,
  Pointer<Double> refRe,
  Pointer<Double> refIm,
  int n,
  int simd,
);

void multiplyConjugate(
  Float64List re,
  Float64List im,
  Float64List refRe,
  Float64List refIm,
) {
  RangeError.checkValueInInterval(re.length, 1, 2048, 'FFT length');
  if (im.length != re.length ||
      refRe.length != re.length ||
      refIm.length != re.length) {
    throw ArgumentError('Invalid native DART spectrum buffers');
  }
  _multiplyConjugate(
    re.address,
    im.address,
    refRe.address,
    refIm.address,
    re.length,
    _simd,
  );
}

@Native<
  Void Function(
    Pointer<Uint16>,
    Pointer<Uint16>,
    Int32,
    Int32,
    Pointer<Uint8>,
    Pointer<Uint8>,
  )
>(symbol: 'ht_dart_ldpc_encode', assetId: _asset, isLeaf: true)
external void _encode(
  Pointer<Uint16> starts,
  Pointer<Uint16> columns,
  int k,
  int n,
  Pointer<Uint8> info,
  Pointer<Uint8> out,
);

@Native<
  Int32 Function(
    Pointer<Uint16>,
    Pointer<Uint16>,
    Pointer<Uint16>,
    Pointer<Uint16>,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Uint8>,
  )
>(symbol: 'ht_dart_ldpc_decode', assetId: _asset)
external int _decode(
  Pointer<Uint16> starts,
  Pointer<Uint16> columns,
  Pointer<Uint16> varStarts,
  Pointer<Uint16> varEdges,
  int k,
  int n,
  int iterations,
  Pointer<Double> llr,
  Pointer<Double> work,
  Pointer<Uint8> out,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Double,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'ht_dart_dft', assetId: _asset, isLeaf: true)
external void _dft(
  Pointer<Double> input,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  int n,
  double norm,
  int inverse,
  Pointer<Double> out,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Double,
    Int32,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'ht_dart_correlate', assetId: _asset, isLeaf: true)
external void _correlate(
  Pointer<Double> samples,
  Pointer<Double> reference,
  int length,
  double energy,
  int start,
  int count,
  Pointer<Double> out,
);

@Native<
  Void Function(
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Int32,
  )
>(symbol: 'ht_dart_fsk_energy', assetId: _asset, isLeaf: true)
external void _fskEnergy(
  Pointer<Double> samples,
  int count,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  int stride,
  Pointer<Double> out,
  int simd,
);

@Native<
  Double Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Double,
    Pointer<Double>,
  )
>(symbol: 'ht_dart_fsk_modulate', assetId: _asset, isLeaf: true)
external double _fskModulate(
  Pointer<Uint8> bits,
  int count,
  int sps,
  Pointer<Double> steps,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  double phase,
  Pointer<Double> out,
);

NativeDartLdpc createLdpc(
  int k,
  int n,
  Int32List starts,
  Int32List columns,
  Int32List varStarts,
  Int32List varEdges,
) => _Ldpc(k, n, starts, columns, varStarts, varEdges);

final class _Ldpc implements NativeDartLdpc, Finalizable {
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  final int k, n;
  late final Pointer<Uint8> _memory;
  late final Pointer<Uint16> _starts, _columns, _varStarts, _varEdges;
  late final Pointer<Double> _llr, _work;
  late final Pointer<Uint8> _out;
  late final Float64List _llrView;
  late final Uint8List _outView;

  _Ldpc(
    this.k,
    this.n,
    Int32List starts,
    Int32List columns,
    Int32List varStarts,
    Int32List varEdges,
  ) {
    // Only the four fixed DART codes cross this ABI.
    if (n != 648 ||
        !const [324, 432, 486, 540].contains(k) ||
        starts.length != n - k + 1 ||
        starts.first != 0 ||
        starts.last != columns.length ||
        varStarts.length != n + 1 ||
        varStarts.first != 0 ||
        varStarts.last != columns.length ||
        varEdges.length != columns.length ||
        columns.length > 0xffff) {
      throw ArgumentError('Invalid native DART LDPC graph');
    }
    for (int i = 1; i < starts.length; i++) {
      if (starts[i] < starts[i - 1]) {
        throw ArgumentError('Invalid LDPC check offsets');
      }
    }
    for (int i = 1; i < varStarts.length; i++) {
      if (varStarts[i] < varStarts[i - 1]) {
        throw ArgumentError('Invalid LDPC variable offsets');
      }
    }
    for (final col in columns) {
      RangeError.checkValidIndex(col, varStarts, 'LDPC column', n);
    }
    for (final edge in varEdges) {
      RangeError.checkValidIndex(edge, columns, 'LDPC edge');
    }
    final ints =
        starts.length + columns.length + varStarts.length + varEdges.length;
    final aligned = (ints * sizeOf<Uint16>() + 7) & ~7;
    final bytes = aligned + (columns.length + n) * sizeOf<Double>() + n;
    _memory = calloc<Uint8>(bytes);
    _starts = _memory.cast();
    _columns = _starts + starts.length;
    _varStarts = _columns + columns.length;
    _varEdges = _varStarts + varStarts.length;
    _starts.asTypedList(starts.length).setAll(0, starts);
    _columns.asTypedList(columns.length).setAll(0, columns);
    _varStarts.asTypedList(varStarts.length).setAll(0, varStarts);
    _varEdges.asTypedList(varEdges.length).setAll(0, varEdges);
    _llr = (_memory + aligned).cast();
    _work = _llr + n;
    _out = (_work + columns.length).cast();
    _llrView = _llr.asTypedList(n);
    _outView = _out.asTypedList(k);
    _finalizer.attach(this, _memory.cast(), externalSize: bytes);
  }

  @override
  Uint8List encode(Uint8List info) {
    if (info.length != k) throw ArgumentError('Expected $k LDPC info bits');
    final out = Uint8List(n);
    _encode(_starts, _columns, k, n, info.address, out.address);
    return out;
  }

  @override
  Uint8List decode(Float64List llr, Int32List? corrections, int iterations) {
    if (llr.length != n) throw ArgumentError('Expected $n LDPC LLRs');
    if (iterations <= 0) throw ArgumentError.value(iterations, 'iterations');
    if (corrections != null && corrections.isEmpty) {
      throw ArgumentError('Correction counter must not be empty');
    }
    _llrView.setAll(0, llr);
    // Iterative decoding is deliberately non-leaf: it must not block GC.
    final corrected = _decode(
      _starts,
      _columns,
      _varStarts,
      _varEdges,
      k,
      n,
      iterations,
      _llr,
      _work,
      _out,
    );
    if (corrections != null) corrections[0] += corrected;
    return Uint8List.fromList(_outView);
  }
}

void dft(
  Float64List input,
  Float64List cosine,
  Float64List sine,
  double norm,
  bool inverse,
  Float64List out,
) {
  final n = input.length ~/ 2;
  RangeError.checkValueInInterval(n, 1, 128, 'DFT size');
  if (input.length != 2 * n ||
      out.length != 2 * n ||
      cosine.length != n * n ||
      sine.length != n * n ||
      identical(input.buffer, out.buffer)) {
    throw ArgumentError('Invalid native DART DFT buffers');
  }
  _dft(
    input.address,
    cosine.address,
    sine.address,
    n,
    norm,
    inverse ? 1 : 0,
    out.address,
  );
}

void correlate(
  Float64List samples,
  Float64List reference,
  double energy,
  int start,
  int count,
  Float64List out,
) {
  RangeError.checkValueInInterval(
    reference.length,
    1,
    2048,
    'reference length',
  );
  RangeError.checkValueInInterval(count, 1, 64, 'correlation count');
  RangeError.checkValidRange(
    start,
    start + count + reference.length - 1,
    samples.length,
  );
  RangeError.checkValidRange(0, count, out.length);
  _correlate(
    samples.address,
    reference.address,
    reference.length,
    energy,
    start,
    count,
    out.address,
  );
}

@Native<
  Void Function(
    Pointer<Double>,
    Int32,
    Double,
    Pointer<Double>,
    Int32,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'ht_dart_corr_normalize', assetId: _asset, isLeaf: true)
external void _normalizeCorrelation(
  Pointer<Double> samples,
  int length,
  double energy,
  Pointer<Double> correlation,
  int n,
  int count,
  Pointer<Double> out,
);

void normalizeCorrelation(
  Float64List samples,
  int length,
  double energy,
  Float64List correlation,
  int count,
  Float64List out,
) {
  RangeError.checkValueInInterval(correlation.length, 1, 2048, 'FFT length');
  RangeError.checkValueInInterval(
    length,
    1,
    correlation.length,
    'reference length',
  );
  RangeError.checkValueInInterval(
    count,
    1,
    correlation.length - length + 1,
    'count',
  );
  RangeError.checkValidRange(0, count + length - 1, samples.length);
  RangeError.checkValidRange(0, count, out.length);
  _normalizeCorrelation(
    samples.address,
    length,
    energy,
    correlation.address,
    correlation.length,
    count,
    out.address,
  );
}

void fskEnergy(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
) {
  RangeError.checkValueInInterval(stride, 1, 2048, 'FSK symbol length');
  if (samples.length > stride ||
      cosine.length != 4 * stride ||
      sine.length != 4 * stride ||
      out.length != 4) {
    throw ArgumentError('Invalid native DART FSK buffers');
  }
  _fskEnergy(
    samples.address,
    samples.length,
    cosine.address,
    sine.address,
    stride,
    out.address,
    _simd,
  );
}

@Native<
  Void Function(
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Int32,
    Int32,
  )
>(symbol: 'ht_dart_fsk_soft', assetId: _asset, isLeaf: true)
external void _fskSoft(
  Pointer<Double> samples,
  int count,
  Pointer<Double> cosine,
  Pointer<Double> sine,
  int stride,
  Pointer<Double> out,
  int symbols,
  Pointer<Double> quality,
  int measureSnr,
  int simd,
);

void fskSoft(
  Float64List samples,
  Float64List cosine,
  Float64List sine,
  int stride,
  Float64List out,
  Float64List quality,
  bool measureSnr,
) {
  RangeError.checkValueInInterval(stride, 1, 2048, 'FSK symbol length');
  final symbols = out.length ~/ 2;
  if (out.length != 2 * symbols ||
      symbols == 0 ||
      symbols * stride > 4096 ||
      samples.length > symbols * stride ||
      cosine.length != 4 * stride ||
      sine.length != 4 * stride ||
      quality.length != 2) {
    throw ArgumentError('Invalid native DART FSK soft buffers');
  }
  _fskSoft(
    samples.address,
    samples.length,
    cosine.address,
    sine.address,
    stride,
    out.address,
    symbols,
    quality.address,
    measureSnr ? 1 : 0,
    _simd,
  );
}

double fskModulate(
  Uint8List bits,
  int sps,
  Float64List steps,
  Float64List cosine,
  Float64List sine,
  double phase,
  Float64List out,
) {
  RangeError.checkValueInInterval(sps, 1, 2048, 'FSK symbol length');
  RangeError.checkValueInInterval(out.length, 1, 4096, 'FSK TX count');
  if (out.length != ((bits.length + 1) ~/ 2) * sps ||
      steps.length != 4 ||
      cosine.length != 4 * sps ||
      sine.length != 4 * sps) {
    throw ArgumentError('Invalid native DART FSK TX buffers');
  }
  for (final bit in bits) {
    if (bit > 1) throw ArgumentError.value(bit, 'FSK bit');
  }
  return _fskModulate(
    bits.address,
    bits.length,
    sps,
    steps.address,
    cosine.address,
    sine.address,
    phase,
    out.address,
  );
}
