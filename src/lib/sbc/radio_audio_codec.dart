// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:typed_data';

import 'radio_audio_codec_stub.dart'
    if (dart.library.ffi) 'radio_audio_codec_native.dart'
    as implementation;

abstract interface class RadioAudioCodec {
  factory RadioAudioCodec() => implementation.createCodec();

  static const int maxInputBytes = 98304;
  static const int pcmBytesPerBatch = 6144;

  EncodedRadioAudio encode(Uint8List pcm, {required bool isDataFrame});

  /// Callbacks may dispose the codec to stop delivery, but must not reenter
  /// receive, encode or resetReceiver while the input buffer is being consumed.
  void receive(
    Uint8List bytes, {
    required int Function() decodeMask,
    required void Function(ReceivedRadioAudio packet) onPacket,
  });
  void resetReceiver({bool resetDecoder = true});
  void dispose();
}

class EncodedRadioAudio {
  const EncodedRadioAudio({
    required this.pcmConsumed,
    required this.data,
    required this.lengths,
    required this.samples,
  });

  final int pcmConsumed;
  final Uint8List data;
  final Int32List lengths;
  final Int32List samples;
}

class ReceivedRadioAudio {
  const ReceivedRadioAudio({
    required this.command,
    required this.payloadBytes,
    required this.pcm,
    required this.decodedFrames,
    required this.rejectedBytes,
    required this.error,
    required this.audioUs,
    required this.formats,
  });

  final int command;
  final int payloadBytes;
  final Int16List pcm;
  final int decodedFrames;
  final int rejectedBytes;
  final int error;
  final int audioUs;
  final Uint32List formats;

  String get errorDescription => switch (error) {
    0 => 'none',
    1 => 'invalid SBC sync byte',
    2 => 'invalid SBC header',
    3 => 'invalid/truncated SBC frame',
    4 => 'CRC or frame decode failure',
    5 => 'Bluetooth audio accumulator overflow',
    6 => 'truncated Bluetooth escape sequence',
    _ => 'unknown native codec error $error',
  };
}
