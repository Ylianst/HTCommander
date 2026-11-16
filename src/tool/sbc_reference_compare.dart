// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Run through compare_sbc.ps1; results and downloaded code stay in /reference.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:htcommander/sbc/radio_audio_codec.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

final class _Sbc extends Struct {
  @UnsignedLong()
  external int flags;
  @Uint8()
  external int frequency;
  @Uint8()
  external int blocks;
  @Uint8()
  external int subbands;
  @Uint8()
  external int mode;
  @Uint8()
  external int allocation;
  @Uint8()
  external int bitpool;
  @Uint8()
  external int endian;
  external Pointer<Void> priv;
  external Pointer<Void> privAllocBase;
}

typedef _InitNative = Int Function(Pointer<_Sbc>, UnsignedLong);
typedef _Init = int Function(Pointer<_Sbc>, int);
typedef _FinishNative = Void Function(Pointer<_Sbc>);
typedef _Finish = void Function(Pointer<_Sbc>);
typedef _EncodeNative =
    IntPtr Function(
      Pointer<_Sbc>,
      Pointer<Uint8>,
      Size,
      Pointer<Uint8>,
      Size,
      Pointer<IntPtr>,
    );
typedef _Encode =
    int Function(
      Pointer<_Sbc>,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<IntPtr>,
    );
typedef _DecodeNative =
    IntPtr Function(
      Pointer<_Sbc>,
      Pointer<Uint8>,
      Size,
      Pointer<Uint8>,
      Size,
      Pointer<Size>,
    );
typedef _Decode =
    int Function(
      Pointer<_Sbc>,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Size>,
    );

abstract interface class _Reference {
  String get name;
  String get reportName;
  _Codec create(SbcFrame frame);
}

abstract interface class _Codec {
  Uint8List encode(Int16List left, Int16List? right, int expectedSize);
  Int16List decode(Uint8List bytes, int expectedSamples);
  void dispose();
}

class _Library implements _Reference {
  _Library(DynamicLibrary dll)
    : init = dll.lookupFunction<_InitNative, _Init>('sbc_init'),
      initMsbc = dll.lookupFunction<_InitNative, _Init>('sbc_init_msbc'),
      finish = dll.lookupFunction<_FinishNative, _Finish>('sbc_finish'),
      encode = dll.lookupFunction<_EncodeNative, _Encode>('sbc_encode'),
      decode = dll.lookupFunction<_DecodeNative, _Decode>('sbc_decode');

  final _Init init;
  final _Init initMsbc;
  final _Finish finish;
  final _Encode encode;
  final _Decode decode;

  @override
  String get name => 'BlueZ SBC 2.2, unmodified generic C, MSVC /O2';
  @override
  String get reportName => 'bluez-comparison.json';
  @override
  _Codec create(SbcFrame frame) => _Bluez(this, frame);
}

class _Bluez implements _Codec {
  _Bluez(this.library, SbcFrame frame) {
    final status = (frame.isMsbc ? library.initMsbc : library.init)(state, 0);
    if (status != 0) {
      calloc.free(state);
      calloc.free(input);
      calloc.free(output);
      calloc.free(written);
      throw StateError('BlueZ initialization failed: $status');
    }
    state.ref
      ..frequency = frame.frequency.index
      ..blocks = frame.isMsbc ? 0 : frame.blocks ~/ 4 - 1
      ..subbands = frame.subbands == 8 ? 1 : 0
      ..mode = frame.mode.index
      ..allocation = frame.allocationMethod.index
      ..bitpool = frame.bitpool
      ..endian = 0;
  }

  final _Library library;
  final state = calloc<_Sbc>();
  final input = calloc<Uint8>(4096);
  final output = calloc<Uint8>(4096);
  final written = calloc<Size>();

  @override
  Uint8List encode(Int16List left, Int16List? right, int expectedSize) {
    final channels = right == null ? 1 : 2;
    final pcm = ByteData.sublistView(input.asTypedList(4096));
    for (int i = 0; i < left.length; i++) {
      pcm.setInt16(i * channels * 2, left[i], Endian.little);
      if (right != null) {
        pcm.setInt16((i * channels + 1) * 2, right[i], Endian.little);
      }
    }
    final size = left.length * channels * 2;
    final consumed = library.encode(
      state,
      input,
      size,
      output,
      4096,
      written.cast<IntPtr>(),
    );
    if (consumed != size || written.value != expectedSize) {
      throw StateError(
        'BlueZ encode: consumed $consumed/$size, '
        'wrote ${written.value}/$expectedSize',
      );
    }
    return Uint8List.fromList(output.asTypedList(written.value));
  }

  @override
  Int16List decode(Uint8List bytes, int expectedSamples) {
    input.asTypedList(bytes.length).setAll(0, bytes);
    final consumed = library.decode(
      state,
      input,
      bytes.length,
      output,
      4096,
      written,
    );
    if (consumed != bytes.length || written.value != expectedSamples * 2) {
      throw StateError(
        'BlueZ decode: consumed $consumed/${bytes.length}, '
        'wrote ${written.value}/${expectedSamples * 2}',
      );
    }
    final pcm = ByteData.sublistView(output.asTypedList(written.value));
    return Int16List.fromList(
      List.generate(expectedSamples, (i) => pcm.getInt16(i * 2, Endian.little)),
    );
  }

  @override
  void dispose() {
    library.finish(state);
    calloc.free(state);
    calloc.free(input);
    calloc.free(output);
    calloc.free(written);
  }
}

typedef _GoogleCreateNative = Pointer<Void> Function(Int, Int, Int);
typedef _GoogleCreate = Pointer<Void> Function(int, int, int);
typedef _GoogleDestroyNative = Void Function(Pointer<Void>);
typedef _GoogleDestroy = void Function(Pointer<Void>);
typedef _GoogleProcessNative =
    Int Function(Pointer<Void>, Int, Pointer<Uint8>, Int, Pointer<Uint8>, Int);
typedef _GoogleProcess =
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Uint8>, int);

class _GoogleLibrary implements _Reference {
  _GoogleLibrary(DynamicLibrary dll)
    : allocate = dll.lookupFunction<_GoogleCreateNative, _GoogleCreate>(
        'reference_create',
      ),
      free = dll.lookupFunction<_GoogleDestroyNative, _GoogleDestroy>(
        'reference_destroy',
      ),
      process = dll.lookupFunction<_GoogleProcessNative, _GoogleProcess>(
        'reference_process',
      );

  final _GoogleCreate allocate;
  final _GoogleDestroy free;
  final _GoogleProcess process;
  @override
  String get name =>
      'Google libsbc 6e505650145c9973d08a0bdd5e5f5e1914305e40, MSVC /O2';
  @override
  String get reportName => 'google-comparison.json';
  @override
  _Codec create(SbcFrame frame) => _Google(this, frame);
}

class _Google implements _Codec {
  _Google(this.library, SbcFrame frame) {
    final header =
        (frame.frequency.index << 6) |
        ((frame.blocks ~/ 4 - 1) << 4) |
        (frame.mode.index << 2) |
        (frame.allocationMethod.index << 1) |
        (frame.subbands == 8 ? 1 : 0);
    state = library.allocate(header, frame.bitpool, frame.isMsbc ? 1 : 0);
    if (state == nullptr) {
      calloc.free(input);
      calloc.free(output);
      throw StateError('Google reference allocation failed');
    }
  }

  final _GoogleLibrary library;
  late final Pointer<Void> state;
  final input = calloc<Uint8>(4096);
  final output = calloc<Uint8>(4096);

  int _process(bool encode, int size, int expectedSize) {
    final written = library.process(
      state,
      encode ? 1 : 0,
      input,
      size,
      output,
      4096,
    );
    if (written != expectedSize) {
      throw StateError('Google reference wrote $written/$expectedSize');
    }
    return written;
  }

  @override
  Uint8List encode(Int16List left, Int16List? right, int expectedSize) {
    final channels = right == null ? 1 : 2;
    final pcm = ByteData.sublistView(input.asTypedList(4096));
    for (int i = 0; i < left.length; i++) {
      pcm.setInt16(i * channels * 2, left[i], Endian.little);
      if (right != null) {
        pcm.setInt16((i * channels + 1) * 2, right[i], Endian.little);
      }
    }
    final size = _process(true, left.length * channels * 2, expectedSize);
    return Uint8List.fromList(output.asTypedList(size));
  }

  @override
  Int16List decode(Uint8List bytes, int expectedSamples) {
    input.asTypedList(bytes.length).setAll(0, bytes);
    final size = _process(false, bytes.length, expectedSamples * 2);
    final pcm = ByteData.sublistView(output.asTypedList(size));
    return Int16List.fromList(
      List.generate(expectedSamples, (i) => pcm.getInt16(i * 2, Endian.little)),
    );
  }

  @override
  void dispose() {
    library.free(state);
    calloc.free(input);
    calloc.free(output);
  }
}

class _Difference {
  int samples = 0;
  int different = 0;
  int maximum = 0;
  double squaredError = 0;
  double referenceEnergy = 0;

  void add(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      throw StateError(
        'PCM length mismatch: ${actual.length}/${expected.length}',
      );
    }
    samples += actual.length;
    for (int i = 0; i < actual.length; i++) {
      final error = (actual[i] - expected[i]).abs();
      if (error != 0) different++;
      maximum = math.max(maximum, error);
      squaredError += error * error;
      referenceEnergy += expected[i] * expected[i];
    }
  }

  void merge(_Difference other) {
    samples += other.samples;
    different += other.different;
    maximum = math.max(maximum, other.maximum);
    squaredError += other.squaredError;
    referenceEnergy += other.referenceEnergy;
  }

  Map<String, Object?> toJson() => {
    'samples': samples,
    'differentSamples': different,
    'maxAbsoluteError': maximum,
    'rmse': samples == 0 ? null : math.sqrt(squaredError / samples),
    'differenceSnrDb': squaredError == 0 || referenceEnergy == 0
        ? null
        : 10 * math.log(referenceEnergy / squaredError) / math.ln10,
  };
}

const _patterns = [
  'silence',
  'impulse',
  '997Hz',
  'multitone',
  'low-level',
  'seeded-noise',
  'full-scale',
  'silence-tail',
];
const _framesPerPattern = 4;

Int16List _signal(SbcFrame frame, int frameIndex, int channel) {
  final count = frame.blocks * frame.subbands;
  final pattern = frameIndex ~/ _framesPerPattern;
  final start = (frameIndex % _framesPerPattern) * count;
  int seed = (0x12345678 + channel * 997 + start) & 0xffffffff;
  return Int16List.fromList(
    List.generate(count, (i) {
      final t = start + i;
      final phase = 2 * math.pi * t / frame.getFrequencyHz();
      switch (pattern) {
        case 0:
        case 7:
          return 0;
        case 1:
          return t == channel * 7 ? 32767 : 0;
        case 2:
          return (28000 * math.sin(phase * (997 + channel * 311))).round();
        case 3:
          return (9000 *
                  (math.sin(phase * 311) +
                      math.sin(phase * (1703 + channel * 97)) +
                      math.sin(phase * 7013)))
              .round();
        case 4:
          return (3 * math.sin(phase * 997)).round();
        case 5:
          seed = (1664525 * seed + 1013904223) & 0xffffffff;
          return (seed >> 16) - 32768;
        case 6:
          return (t + channel) % 2 == 0 ? -32768 : 32767;
        default:
          throw StateError('Unknown signal pattern');
      }
    }),
  );
}

Uint8List _packet(Uint8List payload) {
  final out = BytesBuilder()..add([0x7e, 3]);
  for (final b in payload) {
    if (b == 0x7d || b == 0x7e) {
      out.add([0x7d, b ^ 0x20]);
    } else {
      out.addByte(b);
    }
  }
  return (out..addByte(0x7e)).takeBytes();
}

Int16List _nativeDecode(RadioAudioCodec codec, Uint8List bytes) {
  final packet = _packet(bytes);
  final received = <ReceivedRadioAudio>[];
  // Split inside the framed stream to exercise persistent parser state too.
  for (final part in [
    Uint8List.sublistView(packet, 0, 7),
    Uint8List.sublistView(packet, 7),
  ]) {
    codec.receive(part, decodeMask: () => 1 << 3, onPacket: received.add);
  }
  if (received.length != 1 ||
      received.single.error != 0 ||
      received.single.decodedFrames != 1 ||
      received.single.payloadBytes != bytes.length) {
    throw StateError('Native reference-frame decode failed');
  }
  return received.single.pcm;
}

Uint8List _nativeEncode(RadioAudioCodec codec, Int16List pcm, bool snr) {
  final input = Uint8List(pcm.length * 2);
  final data = ByteData.sublistView(input);
  for (int i = 0; i < pcm.length; i++) {
    data.setInt16(i * 2, pcm[i], Endian.little);
  }
  final result = codec.encode(input, isDataFrame: snr);
  final bytes = result.data;
  if (result.pcmConsumed != input.length ||
      bytes.first != 0x7e ||
      bytes[1] != 0 ||
      bytes.last != 0x7e) {
    throw StateError('Unexpected native encoded packet');
  }
  final out = BytesBuilder();
  for (int i = 2; i < bytes.length - 1; i++) {
    if (bytes[i] == 0x7d) {
      out.addByte(bytes[++i] ^ 0x20);
    } else {
      out.addByte(bytes[i]);
    }
  }
  return out.takeBytes();
}

Int16List _interleave(SbcDecodeResult result) {
  if (!result.success) throw StateError('Dart rejected reference SBC frame');
  final right = result.pcmRight;
  if (right == null) return result.pcmLeft;
  return Int16List.fromList(
    List.generate(
      result.pcmLeft.length * 2,
      (i) => i.isEven ? result.pcmLeft[i ~/ 2] : right[i ~/ 2],
    ),
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<int> _scaleFactors(Uint8List bytes, SbcFrame frame) {
  final channels = frame.mode == SbcMode.mono ? 1 : 2;
  final start = 32 + (frame.mode == SbcMode.jointStereo ? frame.subbands : 0);
  return List.generate(channels * frame.subbands, (i) {
    final bit = start + i * 4;
    return (bytes[bit ~/ 8] >> (4 - bit % 8)) & 15;
  });
}

class _Totals {
  int cases = 0;
  int encodedFrames = 0;
  int exactEncodedFrames = 0;
  int nativeEncodedFrames = 0;
  int nativeEncodeMismatches = 0;
  final decodeBluez = _Difference();
  final decodeDart = _Difference();
  final encoderPcm = _Difference();
  final nativePcm = _Difference();

  Map<String, Object?> toJson() => {
    'cases': cases,
    'encodedFramesCompared': encodedFrames,
    'exactEncodedFrames': exactEncodedFrames,
    'nativeEncodedFramesCompared': nativeEncodedFrames,
    'nativeEncodeMismatches': nativeEncodeMismatches,
    'dartVsReferenceDecodeOfReferenceFrames': decodeBluez.toJson(),
    'dartVsReferenceDecodeOfDartFrames': decodeDart.toJson(),
    'referenceDecodeOfDartVsReferenceEncodedFrames': encoderPcm.toJson(),
    'nativeVsDartDecode': nativePcm.toJson(),
  };
}

Map<String, Object?> _compare(
  _Reference library,
  _Reference vectorReference,
  SbcFrame frame,
  _Totals totals,
  _Totals? radio,
) {
  final dartEncoder = SbcEncoder();
  final dartDecodeBluez = SbcDecoder();
  final dartDecodeDart = SbcDecoder();
  final nativeBluez = RadioAudioCodec();
  final nativeDart = RadioAudioCodec();
  final decodeBluez = _Difference();
  final decodeDart = _Difference();
  final encoderPcm = _Difference();
  final nativePcm = _Difference();
  int frames = 0, exact = 0, nativeFrames = 0, nativeMismatches = 0;
  final channels = frame.mode == SbcMode.mono ? 1 : 2;
  // The existing Dart dual-channel encoder is unsupported; decode real BlueZ
  // dual-channel frames instead of a self-generated synthetic fixture.
  final canEncode = frame.mode != SbcMode.dualChannel;
  Map<String, Object?>? firstByteDifference;
  final patterns = List.generate(_patterns.length, (_) => _Totals());
  try {
    for (int pass = 0; pass < 2; pass++) {
      dartEncoder.reset();
      dartDecodeBluez.reset();
      dartDecodeDart.reset();
      nativeBluez.resetReceiver();
      nativeDart.resetReceiver();
      // Both ports have an unsafe/unsupported dual-channel encode path.
      // Use BlueZ-generated frames to test all three dual-channel decoders.
      final bluezEncoder = (canEncode ? library : vectorReference).create(
        frame,
      );
      final bluezDecodeBluez = library.create(frame);
      final bluezDecodeDart = library.create(frame);
      final nativeEncoder = RadioAudioCodec();
      try {
        for (int n = 0; n < _patterns.length * _framesPerPattern; n++) {
          final pattern = patterns[n ~/ _framesPerPattern];
          final left = _signal(frame, n, 0);
          final right = channels == 1 ? null : _signal(frame, n, 1);
          final reference = bluezEncoder.encode(
            left,
            right,
            frame.getFrameSize(),
          );
          final referencePcm = bluezDecodeBluez.decode(
            reference,
            left.length * channels,
          );
          final decodedReference = dartDecodeBluez.decode(reference);
          final referenceInterleaved = _interleave(decodedReference);
          decodeBluez.add(referenceInterleaved, referencePcm);
          pattern.decodeBluez.add(referenceInterleaved, referencePcm);
          nativePcm.add(
            _nativeDecode(nativeBluez, reference),
            decodedReference.pcmLeft,
          );
          if (!canEncode) continue;
          final encoded = dartEncoder.encode(left, right, frame);
          if (encoded == null) throw StateError('Dart encode failed');
          frames++;
          pattern.encodedFrames++;
          if (_same(encoded, reference)) {
            exact++;
            pattern.exactEncodedFrames++;
          } else if (firstByteDifference == null) {
            final index = List.generate(
              encoded.length,
              (i) => i,
            ).firstWhere((i) => encoded[i] != reference[i]);
            firstByteDifference = {
              'frame': n,
              'byte': index,
              'dart': encoded[index],
              'reference': reference[index],
              'dartScaleFactors': _scaleFactors(encoded, frame),
              'referenceScaleFactors': _scaleFactors(reference, frame),
            };
          }
          final referenceDecodedDart = bluezDecodeDart.decode(
            encoded,
            left.length * channels,
          );
          final decodedDart = dartDecodeDart.decode(encoded);
          decodeDart.add(_interleave(decodedDart), referenceDecodedDart);
          encoderPcm.add(referenceDecodedDart, referencePcm);
          pattern.decodeDart.add(
            _interleave(decodedDart),
            referenceDecodedDart,
          );
          pattern.encoderPcm.add(referenceDecodedDart, referencePcm);
          nativePcm.add(
            _nativeDecode(nativeDart, encoded),
            decodedDart.pcmLeft,
          );
          if (radio != null && frame.bitpool == 18) {
            nativeFrames++;
            if (!_same(
              _nativeEncode(
                nativeEncoder,
                left,
                frame.allocationMethod == SbcBitAllocationMethod.snr,
              ),
              encoded,
            )) {
              nativeMismatches++;
            }
          }
        }
      } finally {
        bluezEncoder.dispose();
        bluezDecodeBluez.dispose();
        bluezDecodeDart.dispose();
        nativeEncoder.dispose();
      }
    }
  } finally {
    nativeBluez.dispose();
    nativeDart.dispose();
  }
  for (final total in [totals, ?radio]) {
    total.cases++;
    total.encodedFrames += frames;
    total.exactEncodedFrames += exact;
    total.nativeEncodedFrames += nativeFrames;
    total.nativeEncodeMismatches += nativeMismatches;
    total.decodeBluez.merge(decodeBluez);
    total.decodeDart.merge(decodeDart);
    total.encoderPcm.merge(encoderPcm);
    total.nativePcm.merge(nativePcm);
  }
  return {
    'frequency': frame.getFrequencyHz(),
    'mode': frame.mode.name,
    'blocks': frame.blocks,
    'subbands': frame.subbands,
    'allocation': frame.allocationMethod.name,
    'bitpool': frame.bitpool,
    'msbc': frame.isMsbc,
    'encodedFramesCompared': frames,
    'exactEncodedFrames': exact,
    'firstEncodedByteDifference': firstByteDifference,
    'dartVsReferenceDecodeOfReferenceFrames': decodeBluez.toJson(),
    'dartVsReferenceDecodeOfDartFrames': decodeDart.toJson(),
    'referenceDecodeOfDartVsReferenceEncodedFrames': encoderPcm.toJson(),
    'nativeVsDartDecode': nativePcm.toJson(),
    if (radio != null || frame.isMsbc)
      'patterns': [
        for (int i = 0; i < patterns.length; i++)
          {'signal': _patterns[i], ...patterns[i].toJson()},
      ],
  };
}

void _runReference(
  _Reference library,
  _Reference vectorReference,
  String reportDirectory, {
  required bool requireExact,
}) {
  final totals = _Totals();
  final radio = _Totals();
  final cases = <Map<String, Object?>>[];
  for (final frequency in SbcFrequency.values) {
    for (final mode in SbcMode.values) {
      for (final blocks in [4, 8, 12, 16]) {
        for (final bands in [4, 8]) {
          for (final allocation in SbcBitAllocationMethod.values) {
            for (final bitpool in [2, 18, 40, 53, 64, 124]) {
              final frame = SbcFrame()
                ..frequency = frequency
                ..mode = mode
                ..blocks = blocks
                ..subbands = bands
                ..allocationMethod = allocation
                ..bitpool = bitpool;
              if (!frame.isValid()) continue;
              final isRadio =
                  frequency == SbcFrequency.freq32K &&
                  mode == SbcMode.mono &&
                  blocks == 16 &&
                  bands == 8;
              cases.add(
                _compare(
                  library,
                  vectorReference,
                  frame,
                  totals,
                  isRadio ? radio : null,
                ),
              );
            }
          }
        }
      }
    }
    print('Compared ${frequency.name}: ${totals.cases} configurations');
  }
  cases.add(
    _compare(library, vectorReference, SbcFrame.createMsbc(), totals, null),
  );
  final report = {
    'reference': library.name,
    'requiredBitExact': requireExact,
    'nativeParity':
        totals.nativeEncodeMismatches == 0 && totals.nativePcm.different == 0,
    'externalBitExact':
        totals.encodedFrames == totals.exactEncodedFrames &&
        totals.decodeBluez.different == 0 &&
        totals.decodeDart.different == 0,
    'patterns': _patterns,
    'framesPerPattern': _framesPerPattern,
    'passesWithReset': 2,
    'notes': [
      'No conformance tolerance is assumed: all numerical differences are reported.',
      'Dual-channel frames always come from BlueZ; Dart and Google dual-channel encoding are not tested.',
      'Native RX outputs the left channel; both Dart channels are compared to the reference.',
      'Native TX is fixed at 32kHz/mono/16 blocks/8 subbands/bitpool 18.',
      'The second pass resets and reuses Dart and native RX states.',
    ],
    'all': totals.toJson(),
    'radio32kMono16x8': radio.toJson(),
    'cases': cases,
  };
  final path = '$reportDirectory${Platform.pathSeparator}${library.reportName}';
  File(
    path,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print('All configurations: ${jsonEncode(totals.toJson())}');
  print('Radio configurations: ${jsonEncode(radio.toJson())}');
  print('Detailed report: $path');
  if (report['externalBitExact'] == false) {
    print(
      'External reference differences found; this is NOT a conformance pass.',
    );
  }
  if (totals.nativeEncodeMismatches != 0 || totals.nativePcm.different != 0) {
    stderr.writeln('FAIL: optimized native codec differs from Dart.');
    exitCode = 1;
  } else if (requireExact &&
      report['externalBitExact'] == false &&
      exitCode == 0) {
    exitCode = 2;
  }
}

void _writeGoldens(_Reference library) {
  final configurations = <SbcFrame>[
    for (final allocation in SbcBitAllocationMethod.values)
      SbcFrame()
        ..frequency = SbcFrequency.freq32K
        ..mode = SbcMode.mono
        ..blocks = 16
        ..subbands = 8
        ..allocationMethod = allocation
        ..bitpool = 18,
    for (final mode in [SbcMode.mono, SbcMode.stereo, SbcMode.jointStereo])
      SbcFrame()
        ..frequency = SbcFrequency.freq16K
        ..mode = mode
        ..blocks = 16
        ..subbands = 4
        ..allocationMethod = SbcBitAllocationMethod.snr
        ..bitpool = 2,
    SbcFrame()
      ..frequency = SbcFrequency.freq48K
      ..mode = SbcMode.jointStereo
      ..blocks = 16
      ..subbands = 8
      ..allocationMethod = SbcBitAllocationMethod.loudness
      ..bitpool = 53,
    SbcFrame.createMsbc(),
  ];
  final vectors = <Map<String, Object?>>[];
  for (final frame in configurations) {
    final left = frame.mode == SbcMode.mono && frame.subbands == 4
        ? Int16List.fromList(List.filled(frame.blocks * frame.subbands, -32768))
        : _signal(frame, 24, 0);
    final right = frame.mode == SbcMode.mono ? null : _signal(frame, 24, 1);
    final encoder = library.create(frame);
    final decoder = library.create(frame);
    final encoded = <Uint8List>[];
    final decoded = <Int16List>[];
    try {
      for (int n = 0; n < 4; n++) {
        final bytes = encoder.encode(left, right, frame.getFrameSize());
        encoded.add(bytes);
        decoded.add(
          decoder.decode(bytes, left.length * (right == null ? 1 : 2)),
        );
      }
    } finally {
      encoder.dispose();
      decoder.dispose();
    }
    vectors.add({
      'frequency': frame.frequency.index,
      'mode': frame.mode.index,
      'blocks': frame.blocks,
      'subbands': frame.subbands,
      'allocation': frame.allocationMethod.index,
      'bitpool': frame.bitpool,
      'msbc': frame.isMsbc,
      'pcmLeft': left,
      'pcmRight': right,
      'encoded': encoded,
      'decoded': decoded,
    });
  }
  final directory = Directory('test${Platform.pathSeparator}sbc_vectors')
    ..createSync(recursive: true);
  final path = '${directory.path}${Platform.pathSeparator}google.json';
  File(path).writeAsStringSync(
    jsonEncode({
      'reference': library.name,
      'source':
          'https://github.com/google/libsbc/tree/'
          '6e505650145c9973d08a0bdd5e5f5e1914305e40',
      'license': 'Apache-2.0',
      'vectors': vectors,
    }),
  );
  print('Wrote independent Google reference vectors: $path');
}

void main(List<String> args) {
  if (args.length != 3 && !(args.length == 4 && args[3] == '--write-goldens')) {
    stderr.writeln(
      'Usage: dart run tool\\sbc_reference_compare.dart '
      '<BlueZ DLL> <Google DLL> <report directory> [--write-goldens]',
    );
    exitCode = 64;
    return;
  }
  final bluez = _Library(DynamicLibrary.open(File(args[0]).absolute.path));
  final google = _GoogleLibrary(
    DynamicLibrary.open(File(args[1]).absolute.path),
  );
  _runReference(bluez, bluez, args[2], requireExact: false);
  _runReference(google, bluez, args[2], requireExact: true);
  if (args.length == 4) _writeGoldens(google);
}
