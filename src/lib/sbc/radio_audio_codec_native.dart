// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'radio_audio_codec.dart';

const _asset = 'package:htcommander/radio_audio_codec';

final class _Codec extends Opaque {}

final class _TxResult extends Struct {
  @Int32()
  external int pcmConsumed;
  @Int32()
  external int dataLength;
  @Int32()
  external int batchCount;
  @Int32()
  external int reserved;
  external Pointer<Uint8> data;
  external Pointer<Int32> lengths;
  external Pointer<Int32> samples;
}

final class _RxResult extends Struct {
  @Int32()
  external int consumed;
  @Int32()
  external int command;
  @Int32()
  external int payloadBytes;
  @Int32()
  external int pcmSamples;
  @Int32()
  external int decodedFrames;
  @Int32()
  external int rejectedBytes;
  @Int32()
  external int error;
  @Int32()
  external int formatCount;
  @Int64()
  external int audioUs;
  external Pointer<Int16> pcm;
  external Pointer<Uint32> formats;
}

@Native<Uint32 Function()>(
  symbol: 'ht_audio_abi_version',
  assetId: _asset,
  isLeaf: true,
)
external int _abiVersion();

@Native<Pointer<_Codec> Function()>(symbol: 'ht_audio_create', assetId: _asset)
external Pointer<_Codec> _create();

@Native<Void Function(Pointer<_Codec>)>(
  symbol: 'ht_audio_destroy',
  assetId: _asset,
)
external void _destroy(Pointer<_Codec> codec);

@Native<Void Function(Pointer<_Codec>, Uint32)>(
  symbol: 'ht_audio_reset',
  assetId: _asset,
)
external void _reset(Pointer<_Codec> codec, int flags);

@Native<
  Int32 Function(
    Pointer<_Codec>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<_TxResult>,
  )
>(symbol: 'ht_audio_encode', assetId: _asset)
external int _encode(
  Pointer<_Codec> codec,
  Pointer<Uint8> pcm,
  int length,
  int allocation,
  Pointer<_TxResult> result,
);

@Native<
  Int32 Function(
    Pointer<_Codec>,
    Pointer<Uint8>,
    Int32,
    Uint32,
    Pointer<_RxResult>,
  )
>(symbol: 'ht_audio_receive', assetId: _asset)
external int _receive(
  Pointer<_Codec> codec,
  Pointer<Uint8> bytes,
  int length,
  int mask,
  Pointer<_RxResult> result,
);

RadioAudioCodec createCodec() => _NativeRadioAudioCodec();

final class _NativeRadioAudioCodec implements RadioAudioCodec, Finalizable {
  _NativeRadioAudioCodec() {
    if (_abiVersion() != 1) {
      throw StateError('Unsupported native audio codec ABI');
    }
    _handle = _create();
    if (_handle == nullptr) {
      throw StateError('Native audio codec allocation failed');
    }
    try {
      _arena = calloc<Uint8>(_arenaBytes);
    } catch (_) {
      _destroy(_handle);
      rethrow;
    }
    _tx = (_arena + RadioAudioCodec.maxInputBytes).cast<_TxResult>();
    _rx = (_arena + _rxOffset).cast<_RxResult>();
    _codecFinalizer.attach(this, _handle.cast(), detach: this);
    _arenaFinalizer.attach(
      this,
      _arena.cast(),
      detach: this,
      externalSize: _arenaBytes,
    );
  }

  static final _codecFinalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<_Codec>)>>(
      _destroy,
    ).cast(),
  );
  static final _arenaFinalizer = NativeFinalizer(calloc.nativeFree);
  static final int _rxOffset =
      (RadioAudioCodec.maxInputBytes + sizeOf<_TxResult>() + 7) & ~7;
  static final int _arenaBytes = _rxOffset + sizeOf<_RxResult>();

  late final Pointer<_Codec> _handle;
  late final Pointer<Uint8> _arena;
  late final Pointer<_TxResult> _tx;
  late final Pointer<_RxResult> _rx;
  bool _disposed = false;

  void _checkAlive() {
    if (_disposed) throw StateError('Native radio audio codec is disposed');
  }

  @override
  EncodedRadioAudio encode(Uint8List pcm, {required bool isDataFrame}) {
    _checkAlive();
    if (pcm.length > RadioAudioCodec.maxInputBytes) {
      throw ArgumentError.value(
        pcm.length,
        'pcm.length',
        'Native chunk too large',
      );
    }
    _arena.asTypedList(pcm.length).setAll(0, pcm);
    final status = _encode(
      _handle,
      _arena,
      pcm.length,
      isDataFrame ? 1 : 0,
      _tx,
    );
    if (status != 0) throw StateError('Native audio encode failed ($status)');
    final result = _tx.ref;
    if (result.pcmConsumed < 0 ||
        result.pcmConsumed > pcm.length ||
        result.pcmConsumed % 256 != 0 ||
        result.batchCount < 0 ||
        result.batchCount > (pcm.length + 6143) ~/ 6144 ||
        result.dataLength < 0 ||
        result.dataLength > pcm.length * 3) {
      throw StateError('Invalid native audio encode result');
    }
    return EncodedRadioAudio(
      pcmConsumed: result.pcmConsumed,
      data: Uint8List.fromList(result.data.asTypedList(result.dataLength)),
      lengths: Int32List.fromList(
        result.lengths.asTypedList(result.batchCount),
      ),
      samples: Int32List.fromList(
        result.samples.asTypedList(result.batchCount),
      ),
    );
  }

  @override
  void receive(
    Uint8List bytes, {
    required int Function() decodeMask,
    required void Function(ReceivedRadioAudio packet) onPacket,
  }) {
    _checkAlive();
    for (int base = 0; base < bytes.length;) {
      final remaining = bytes.length - base;
      final length = remaining < RadioAudioCodec.maxInputBytes
          ? remaining
          : RadioAudioCodec.maxInputBytes;
      _arena.asTypedList(length).setRange(0, length, bytes, base);
      int offset = 0;
      while (offset < length) {
        final status = _receive(
          _handle,
          _arena + offset,
          length - offset,
          decodeMask(),
          _rx,
        );
        if (status < 0) {
          throw StateError('Native audio receive failed ($status)');
        }
        final result = _rx.ref;
        if (result.consumed <= 0 ||
            result.consumed > length - offset ||
            result.pcmSamples < 0 ||
            result.pcmSamples > 2 * 1024 * 1024 ||
            result.formatCount < 0 ||
            result.formatCount > 4096) {
          throw StateError('Invalid native audio receive result');
        }
        offset += result.consumed;
        if (status == 0) continue;
        if (status != 1) {
          throw StateError('Unknown native audio receive status');
        }
        onPacket(
          ReceivedRadioAudio(
            command: result.command,
            payloadBytes: result.payloadBytes,
            pcm: Int16List.fromList(result.pcm.asTypedList(result.pcmSamples)),
            decodedFrames: result.decodedFrames,
            rejectedBytes: result.rejectedBytes,
            error: result.error,
            audioUs: result.audioUs,
            formats: Uint32List.fromList(
              result.formats.asTypedList(result.formatCount),
            ),
          ),
        );
      }
      base += length;
    }
  }

  @override
  void resetReceiver({bool resetDecoder = true}) {
    _checkAlive();
    _reset(_handle, resetDecoder ? 3 : 2);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _codecFinalizer.detach(this);
    _arenaFinalizer.detach(this);
    _destroy(_handle);
    calloc.free(_arena);
  }
}
