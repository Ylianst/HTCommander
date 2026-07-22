// gsm_codec.dart - Public API for the pure-Dart GSM 06.10 (Full Rate) codec.
//
// Pure-Dart port of libgsm 1.0.22 by Jutta Degener and Carsten Bormann
// (Technische Universitaet Berlin). Produces the standard 33-byte "toast"
// frames used by EchoLink: 8 kHz, 16-bit, mono; 160 samples -> 33 bytes.
//
// See reference/libgsm for the C source of truth and its COPYRIGHT.

import 'dart:typed_data';

import 'gsm_coder.dart';
import 'gsm_frame.dart';
import 'gsm_state.dart';

/// GSM 06.10 encoder. One instance encodes a single continuous stream; create
/// a new instance (or call [reset]) for an unrelated stream.
class GsmEncoder {
  final GsmState _state = GsmState();

  // Reusable parameter scratch buffers (avoid per-frame allocation).
  final Int16List _larc = Int16List(8);
  final Int16List _nc = Int16List(4);
  final Int16List _bc = Int16List(4);
  final Int16List _mc = Int16List(4);
  final Int16List _xmaxc = Int16List(4);
  final Int16List _xmc = Int16List(52);

  /// Number of PCM samples consumed per encoded frame (160).
  int get frameSamples => gsmFrameSamples;

  /// Number of bytes produced per encoded frame (33).
  int get frameSize => gsmFrameSize;

  /// Clears the encoder's filter memory to start a new stream.
  void reset() => _state.reset();

  /// Encodes exactly [gsmFrameSamples] (160) samples into a 33-byte frame,
  /// written into `out[outOff..outOff+32]` if provided, otherwise into a new
  /// [Uint8List]. Returns the buffer written to.
  Uint8List encodeFrame(Int16List pcm, {int pcmOff = 0, Uint8List? out, int outOff = 0}) {
    if (pcm.length - pcmOff < gsmFrameSamples) {
      throw ArgumentError('encodeFrame needs $gsmFrameSamples samples');
    }
    final Int16List frameIn = pcmOff == 0 && pcm.length == gsmFrameSamples
        ? pcm
        : Int16List.sublistView(pcm, pcmOff, pcmOff + gsmFrameSamples);

    gsmCoder(_state, frameIn, _larc, _nc, _bc, _mc, _xmaxc, _xmc);

    final Uint8List dst = out ?? Uint8List(gsmFrameSize);
    packFrame(_larc, _nc, _bc, _mc, _xmaxc, _xmc, dst, outOff);
    return dst;
  }

  /// Encodes an integer number of 160-sample frames. `pcm.length` must be a
  /// multiple of 160. Returns `(pcm.length / 160) * 33` bytes.
  Uint8List encode(Int16List pcm) {
    if (pcm.length % gsmFrameSamples != 0) {
      throw ArgumentError('pcm length must be a multiple of $gsmFrameSamples');
    }
    final int frames = pcm.length ~/ gsmFrameSamples;
    final Uint8List out = Uint8List(frames * gsmFrameSize);
    for (int f = 0; f < frames; f++) {
      encodeFrame(pcm,
          pcmOff: f * gsmFrameSamples, out: out, outOff: f * gsmFrameSize);
    }
    return out;
  }
}

/// GSM 06.10 decoder. One instance decodes a single continuous stream.
class GsmDecoder {
  final GsmState _state = GsmState();

  final Int16List _larc = Int16List(8);
  final Int16List _nc = Int16List(4);
  final Int16List _bc = Int16List(4);
  final Int16List _mc = Int16List(4);
  final Int16List _xmaxc = Int16List(4);
  final Int16List _xmc = Int16List(52);

  /// Number of bytes consumed per decoded frame (33).
  int get frameSize => gsmFrameSize;

  /// Number of PCM samples produced per decoded frame (160).
  int get frameSamples => gsmFrameSamples;

  /// Clears the decoder's filter memory to start a new stream.
  void reset() => _state.reset();

  /// Decodes a single 33-byte frame at `data[dataOff..dataOff+32]` into 160
  /// samples, written into `out[outOff..outOff+159]` if provided. Returns the
  /// samples buffer, or `null` if the frame's magic nibble is invalid.
  Int16List? decodeFrame(Uint8List data, {int dataOff = 0, Int16List? out, int outOff = 0}) {
    if (data.length - dataOff < gsmFrameSize) {
      throw ArgumentError('decodeFrame needs $gsmFrameSize bytes');
    }
    if (!unpackFrame(data, dataOff, _larc, _nc, _bc, _mc, _xmaxc, _xmc)) {
      return null;
    }

    final Int16List dst = out ?? Int16List(gsmFrameSamples);
    final Int16List target = (out != null && outOff != 0)
        ? Int16List(gsmFrameSamples)
        : dst;

    gsmDecoder(_state, _larc, _nc, _bc, _mc, _xmaxc, _xmc, target);

    if (!identical(target, dst)) {
      dst.setRange(outOff, outOff + gsmFrameSamples, target);
    }
    return dst;
  }

  /// Decodes an integer number of 33-byte frames. `data.length` must be a
  /// multiple of 33. Returns `(data.length / 33) * 160` samples. Throws a
  /// [FormatException] if any frame has an invalid magic nibble.
  Int16List decode(Uint8List data) {
    if (data.length % gsmFrameSize != 0) {
      throw ArgumentError('data length must be a multiple of $gsmFrameSize');
    }
    final int frames = data.length ~/ gsmFrameSize;
    final Int16List out = Int16List(frames * gsmFrameSamples);
    for (int f = 0; f < frames; f++) {
      final Int16List? r = decodeFrame(data,
          dataOff: f * gsmFrameSize, out: out, outOff: f * gsmFrameSamples);
      if (r == null) {
        throw FormatException('Invalid GSM frame magic at frame $f');
      }
    }
    return out;
  }
}
