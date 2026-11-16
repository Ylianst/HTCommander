// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'native_gsm.dart';

const _asset = 'package:htcommander/echolink_gsm';
const _scalar = bool.fromEnvironment('HT_GSM_SCALAR');

bool get supported =>
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isAndroid;
int get simdWidth => _simdWidth();

final class _Codec extends Opaque {}

@Native<Int32 Function()>(
  symbol: 'ht_gsm_simd_width',
  assetId: _asset,
  isLeaf: true,
)
external int _simdWidth();

@Native<Int32 Function()>(
  symbol: 'ht_gsm_storage_bytes',
  assetId: _asset,
  isLeaf: true,
)
external int _storageBytes();

@Native<Pointer<_Codec> Function(Int32, Int32)>(
  symbol: 'ht_gsm_create',
  assetId: _asset,
)
external Pointer<_Codec> _create(int encoder, int simd);

@Native<Void Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<_Codec> codec);

@Native<Void Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_reset',
  assetId: _asset,
  isLeaf: true,
)
external void _reset(Pointer<_Codec> codec);

@Native<Pointer<Int16> Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_pcm',
  assetId: _asset,
  isLeaf: true,
)
external Pointer<Int16> _pcm(Pointer<_Codec> codec);

@Native<Pointer<Uint8> Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_frames',
  assetId: _asset,
  isLeaf: true,
)
external Pointer<Uint8> _frames(Pointer<_Codec> codec);

@Native<Int32 Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_encode',
  assetId: _asset,
)
external int _encode(Pointer<_Codec> codec);

@Native<Int32 Function(Pointer<_Codec>)>(
  symbol: 'ht_gsm_decode',
  assetId: _asset,
)
external int _decode(Pointer<_Codec> codec);

abstract class _Storage implements Finalizable {
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<_Codec>)>>(
      _destroy,
    ).cast(),
  );
  final Pointer<_Codec> _handle;
  late final Int16List _pcmView;
  late final Uint8List _framesView;
  bool _disposed = false;

  _Storage(bool encoder, bool simd)
    : _handle = _create(encoder ? 1 : 0, simd && !_scalar ? 1 : 0) {
    if (_handle == nullptr) {
      throw StateError('Native GSM allocation failed');
    }
    _finalizer.attach(
      this,
      _handle.cast(),
      detach: this,
      externalSize: _storageBytes(),
    );
    _pcmView = _pcm(_handle).asTypedList(640);
    _framesView = _frames(_handle).asTypedList(132);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Native GSM codec is disposed');
  }

  void reset() {
    _checkAlive();
    _reset(_handle);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _destroy(_handle);
  }
}

NativeGsmEncoder createEncoder(bool simd) => _Encoder(simd);
NativeGsmDecoder createDecoder() => _Decoder();

final class _Encoder extends _Storage implements NativeGsmEncoder {
  _Encoder(bool simd) : super(true, simd);

  @override
  void encode(Int16List pcm, int pcmOff, Uint8List out, int outOff) {
    _checkAlive();
    RangeError.checkValidRange(pcmOff, pcmOff + 640, pcm.length, 'pcmOff');
    RangeError.checkValidRange(outOff, outOff + 132, out.length, 'outOff');
    _pcmView.setRange(0, 640, pcm, pcmOff);
    final status = _encode(_handle);
    if (status != 0) throw StateError('Native GSM encode failed ($status)');
    out.setRange(outOff, outOff + 132, _framesView);
  }
}

final class _Decoder extends _Storage implements NativeGsmDecoder {
  _Decoder() : super(false, false);

  @override
  Int16List decode(Uint8List frames) {
    _checkAlive();
    if (frames.length != 132) {
      throw ArgumentError.value(frames.length, 'frames.length', 'Expected 132');
    }
    _framesView.setAll(0, frames);
    final status = _decode(_handle);
    if (status > 0 && status <= 4) {
      throw FormatException('Invalid GSM frame magic at frame ${status - 1}');
    }
    if (status != 0) throw StateError('Native GSM decode failed ($status)');
    return Int16List.fromList(_pcmView);
  }
}
