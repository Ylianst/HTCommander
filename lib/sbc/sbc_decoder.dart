/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'sbc_bit_stream.dart';
import 'sbc_decoder_tables.dart';
import 'sbc_enums.dart';
import 'sbc_frame.dart';
import 'sbc_tables.dart';

/// Result of an SBC decode operation.
class SbcDecodeResult {
  /// Whether decoding succeeded.
  final bool success;

  /// Decoded PCM samples for the left channel.
  final Int16List pcmLeft;

  /// Decoded PCM samples for the right channel (null for mono).
  final Int16List? pcmRight;

  /// Decoded frame parameters.
  final SbcFrame frame;

  const SbcDecodeResult({
    required this.success,
    required this.pcmLeft,
    required this.pcmRight,
    required this.frame,
  });
}

/// SBC audio decoder - converts SBC frames to PCM samples.
class SbcDecoder {
  final List<_DecoderState> _channelStates;

  SbcDecoder()
    : _channelStates = <_DecoderState>[_DecoderState(), _DecoderState()] {
    reset();
  }

  /// Reset decoder state.
  void reset() {
    _channelStates[0].reset();
    _channelStates[1].reset();
  }

  /// Probe SBC data and extract frame parameters without full decoding.
  SbcFrame? probe(Uint8List? data) {
    if (data == null || data.length < SbcFrame.headerSize) {
      return null;
    }

    final SbcBitStream bits = SbcBitStream(
      data,
      SbcFrame.headerSize,
      isReader: true,
    );
    final SbcFrame frame = SbcFrame();

    if (_decodeHeader(bits, frame) == null) {
      return null;
    }

    return bits.hasError ? null : frame;
  }

  /// Decode an SBC frame to PCM samples.
  ///
  /// [sbcData] SBC encoded frame data.
  /// Returns an [SbcDecodeResult] with [SbcDecodeResult.success] indicating
  /// whether decoding succeeded.
  SbcDecodeResult decode(Uint8List? sbcData) {
    final SbcFrame frame = SbcFrame();

    SbcDecodeResult failure() => SbcDecodeResult(
      success: false,
      pcmLeft: Int16List(0),
      pcmRight: null,
      frame: frame,
    );

    if (sbcData == null || sbcData.length < SbcFrame.headerSize) {
      return failure();
    }

    // Decode header
    final SbcBitStream headerBits = SbcBitStream(
      sbcData,
      SbcFrame.headerSize,
      isReader: true,
    );
    final int? crc = _decodeHeader(headerBits, frame);
    if (crc == null || headerBits.hasError) {
      return failure();
    }

    final int frameSize = frame.getFrameSize();
    if (sbcData.length < frameSize) {
      return failure();
    }

    // Verify CRC
    final int computedCrc = SbcTables.computeCrc(
      frame,
      sbcData,
      sbcData.length,
    );
    if (computedCrc != crc) {
      return failure();
    }

    // Decode frame data
    final SbcBitStream dataBits = SbcBitStream(
      sbcData,
      frameSize,
      isReader: true,
    );
    dataBits.getBits(SbcFrame.headerSize * 8); // Skip header

    final List<Int16List> sbSamples = <Int16List>[
      Int16List(SbcFrame.maxSamples),
      Int16List(SbcFrame.maxSamples),
    ];
    final List<int> sbScale = List<int>.filled(2, 0);

    _decodeFrameData(dataBits, frame, sbSamples, sbScale);
    if (dataBits.hasError) {
      return failure();
    }

    final int numBlocks = frame.blocks;
    final int numSubbands = frame.subbands;

    // Synthesize PCM
    final int samplesPerChannel = numBlocks * numSubbands;
    final Int16List pcmLeft = Int16List(samplesPerChannel);

    _synthesize(
      _channelStates[0],
      numBlocks,
      numSubbands,
      sbSamples[0],
      sbScale[0],
      pcmLeft,
      1,
    );

    Int16List? pcmRight;
    if (frame.mode != SbcMode.mono) {
      pcmRight = Int16List(samplesPerChannel);
      _synthesize(
        _channelStates[1],
        numBlocks,
        numSubbands,
        sbSamples[1],
        sbScale[1],
        pcmRight,
        1,
      );
    }

    return SbcDecodeResult(
      success: true,
      pcmLeft: pcmLeft,
      pcmRight: pcmRight,
      frame: frame,
    );
  }

  /// Decode the frame header into [frame]. Returns the CRC on success, or
  /// null if the header is invalid.
  int? _decodeHeader(SbcBitStream bits, SbcFrame frame) {
    final int syncword = bits.getBits(8);
    frame.isMsbc = (syncword == 0xad);

    if (frame.isMsbc) {
      bits.getBits(16); // reserved
      final SbcFrame msbcFrame = SbcFrame.createMsbc();
      frame.frequency = msbcFrame.frequency;
      frame.mode = msbcFrame.mode;
      frame.allocationMethod = msbcFrame.allocationMethod;
      frame.blocks = msbcFrame.blocks;
      frame.subbands = msbcFrame.subbands;
      frame.bitpool = msbcFrame.bitpool;
    } else if (syncword == 0x9c) {
      final int freq = bits.getBits(2);
      frame.frequency = SbcFrequency.values[freq];

      final int blocks = bits.getBits(2);
      frame.blocks = (1 + blocks) << 2;

      final int mode = bits.getBits(2);
      frame.mode = SbcMode.values[mode];

      final int bam = bits.getBits(1);
      frame.allocationMethod = SbcBitAllocationMethod.values[bam];

      final int subbands = bits.getBits(1);
      frame.subbands = (1 + subbands) << 2;

      frame.bitpool = bits.getBits(8);
    } else {
      return null;
    }

    final int crc = bits.getBits(8);

    return frame.isValid() ? crc : null;
  }

  void _decodeFrameData(
    SbcBitStream bits,
    SbcFrame frame,
    List<Int16List> sbSamples,
    List<int> sbScale,
  ) {
    final int nchannels = frame.mode != SbcMode.mono ? 2 : 1;
    final int nsubbands = frame.subbands;

    // Decode joint stereo mask
    int mjoint = 0;
    if (frame.mode == SbcMode.jointStereo) {
      final int v = bits.getBits(nsubbands);
      if (nsubbands == 4) {
        mjoint =
            ((0x00) << 3) |
            ((v & 0x02) << 1) |
            ((v & 0x04) >> 1) |
            ((v & 0x08) >> 3);
      } else {
        mjoint =
            ((0x00) << 7) |
            ((v & 0x02) << 5) |
            ((v & 0x04) << 3) |
            ((v & 0x08) << 1) |
            ((v & 0x10) >> 1) |
            ((v & 0x20) >> 3) |
            ((v & 0x40) >> 5) |
            ((v & 0x80) >> 7);
      }
    }

    // Decode scale factors
    final List<List<int>> scaleFactors = <List<int>>[
      List<int>.filled(SbcFrame.maxSubbands, 0),
      List<int>.filled(SbcFrame.maxSubbands, 0),
    ];

    for (int ch = 0; ch < nchannels; ch++) {
      for (int sb = 0; sb < nsubbands; sb++) {
        scaleFactors[ch][sb] = bits.getBits(4);
      }
    }

    // Compute bit allocation
    final List<List<int>> nbits = <List<int>>[
      List<int>.filled(SbcFrame.maxSubbands, 0),
      List<int>.filled(SbcFrame.maxSubbands, 0),
    ];

    _computeBitAllocation(frame, scaleFactors, nbits);
    if (frame.mode == SbcMode.dualChannel) {
      final List<List<int>> scaleFactors1 = <List<int>>[scaleFactors[1]];
      final List<List<int>> nbits1 = <List<int>>[nbits[1]];
      _computeBitAllocation(frame, scaleFactors1, nbits1);
    }

    // Compute scale for output samples
    for (int ch = 0; ch < nchannels; ch++) {
      int maxScf = 0;
      for (int sb = 0; sb < nsubbands; sb++) {
        final int scf = scaleFactors[ch][sb] + ((mjoint >> sb) & 1);
        if (scf > maxScf) {
          maxScf = scf;
        }
      }
      sbScale[ch] = (15 - maxScf) - (17 - 16);
    }

    if (frame.mode == SbcMode.jointStereo) {
      final int minScale = sbScale[0] < sbScale[1] ? sbScale[0] : sbScale[1];
      sbScale[0] = sbScale[1] = minScale;
    }

    // Decode samples
    for (int blk = 0; blk < frame.blocks; blk++) {
      for (int ch = 0; ch < nchannels; ch++) {
        for (int sb = 0; sb < nsubbands; sb++) {
          final int nbit = nbits[ch][sb];
          final int scf = scaleFactors[ch][sb];
          final int idx = blk * nsubbands + sb;

          if (nbit == 0) {
            sbSamples[ch][idx] = 0;
            continue;
          }

          int sample = bits.getBits(nbit);
          sample = ((sample << 1) | 1) * SbcTables.rangeScale[nbit - 1];
          sbSamples[ch][idx] =
              (sample - (1 << 28)) >> (28 - ((scf + 1) + sbScale[ch]));
        }
      }
    }

    // Uncouple joint stereo
    for (int sb = 0; sb < nsubbands; sb++) {
      if (((mjoint >> sb) & 1) == 0) {
        continue;
      }

      for (int blk = 0; blk < frame.blocks; blk++) {
        final int idx = blk * nsubbands + sb;
        final int s0 = sbSamples[0][idx];
        final int s1 = sbSamples[1][idx];
        sbSamples[0][idx] = s0 + s1;
        sbSamples[1][idx] = s0 - s1;
      }
    }

    // Skip padding
    final int paddingBits = 8 - (bits.bitPosition % 8);
    if (paddingBits < 8) {
      bits.getBits(paddingBits);
    }
  }

  void _computeBitAllocation(
    SbcFrame frame,
    List<List<int>> scaleFactors,
    List<List<int>> nbits,
  ) {
    final List<int> loudnessOffset = frame.subbands == 4
        ? SbcTables.loudnessOffset4[frame.frequency.index]
        : SbcTables.loudnessOffset8[frame.frequency.index];

    final bool stereoMode =
        frame.mode == SbcMode.stereo || frame.mode == SbcMode.jointStereo;
    final int nsubbands = frame.subbands;
    final int nchannels = stereoMode ? 2 : 1;

    final List<List<int>> bitneeds = <List<int>>[
      List<int>.filled(SbcFrame.maxSubbands, 0),
      List<int>.filled(SbcFrame.maxSubbands, 0),
    ];
    int maxBitneed = 0;

    for (int ch = 0; ch < nchannels; ch++) {
      for (int sb = 0; sb < nsubbands; sb++) {
        final int scf = scaleFactors[ch][sb];
        int bitneed;

        if (frame.allocationMethod == SbcBitAllocationMethod.loudness) {
          bitneed = scf != 0 ? scf - loudnessOffset[sb] : -5;
          bitneed >>= (bitneed > 0) ? 1 : 0;
        } else {
          bitneed = scf;
        }

        if (bitneed > maxBitneed) {
          maxBitneed = bitneed;
        }

        bitneeds[ch][sb] = bitneed;
      }
    }

    // Bit distribution
    final int bitpool = frame.bitpool;
    int bitcount = 0;
    int bitslice = maxBitneed + 1;

    for (int bc = 0; bc < bitpool;) {
      final int bs = bitslice--;
      bitcount = bc;
      if (bitcount == bitpool) {
        break;
      }

      for (int ch = 0; ch < nchannels; ch++) {
        for (int sb = 0; sb < nsubbands; sb++) {
          final int bn = bitneeds[ch][sb];
          bc += (bn >= bs && bn < bs + 15 ? 1 : 0) + (bn == bs ? 1 : 0);
        }
      }
    }

    // Assign bits
    for (int ch = 0; ch < nchannels; ch++) {
      for (int sb = 0; sb < nsubbands; sb++) {
        final int nbit = bitneeds[ch][sb] - bitslice;
        nbits[ch][sb] = nbit < 2 ? 0 : (nbit > 16 ? 16 : nbit);
      }
    }

    // Allocate remaining bits
    for (int sb = 0; sb < nsubbands && bitcount < bitpool; sb++) {
      for (int ch = 0; ch < nchannels && bitcount < bitpool; ch++) {
        final int n = (nbits[ch][sb] > 0 && nbits[ch][sb] < 16)
            ? 1
            : (bitneeds[ch][sb] == bitslice + 1 && bitpool > bitcount + 1)
            ? 2
            : 0;
        nbits[ch][sb] += n;
        bitcount += n;
      }
    }

    for (int sb = 0; sb < nsubbands && bitcount < bitpool; sb++) {
      for (int ch = 0; ch < nchannels && bitcount < bitpool; ch++) {
        final int n = nbits[ch][sb] < 16 ? 1 : 0;
        nbits[ch][sb] += n;
        bitcount += n;
      }
    }
  }

  void _synthesize(
    _DecoderState state,
    int nblocks,
    int nsubbands,
    Int16List input,
    int scale,
    Int16List output,
    int pitch,
  ) {
    for (int blk = 0; blk < nblocks; blk++) {
      final int inOffset = blk * nsubbands;
      final int outOffset = blk * nsubbands * pitch;

      if (nsubbands == 4) {
        _synthesize4(state, input, inOffset, scale, output, outOffset, pitch);
      } else {
        _synthesize8(state, input, inOffset, scale, output, outOffset, pitch);
      }
    }
  }

  void _synthesize4(
    _DecoderState state,
    Int16List input,
    int inOffset,
    int scale,
    Int16List output,
    int outOffset,
    int pitch,
  ) {
    // Perform DCT and windowing for 4 subbands
    final int dctIdx = state.index != 0 ? 10 - state.index : 0;
    final int odd = dctIdx & 1;

    _dct4(input, inOffset, scale, state.v[odd], state.v[1 - odd], dctIdx);
    _applyWindow4(state.v[odd], state.index, output, outOffset, pitch);

    state.index = state.index < 9 ? state.index + 1 : 0;
  }

  void _synthesize8(
    _DecoderState state,
    Int16List input,
    int inOffset,
    int scale,
    Int16List output,
    int outOffset,
    int pitch,
  ) {
    // Perform DCT and windowing for 8 subbands
    final int dctIdx = state.index != 0 ? 10 - state.index : 0;
    final int odd = dctIdx & 1;

    _dct8(input, inOffset, scale, state.v[odd], state.v[1 - odd], dctIdx);
    _applyWindow8(state.v[odd], state.index, output, outOffset, pitch);

    state.index = state.index < 9 ? state.index + 1 : 0;
  }

  void _dct4(
    Int16List input,
    int offset,
    int scale,
    List<Int16List> out0,
    List<Int16List> out1,
    int idx,
  ) {
    final Int16List cos8 = SbcTables.cos8;

    final int s03 = (input[offset + 0] + input[offset + 3]) >> 1;
    final int d03 = (input[offset + 0] - input[offset + 3]) >> 1;
    final int s12 = (input[offset + 1] + input[offset + 2]) >> 1;
    final int d12 = (input[offset + 1] - input[offset + 2]) >> 1;

    int a0 = (s03 - s12) * cos8[2];
    int b1 = -(s03 + s12) << 13;
    int a1 = d03 * cos8[3] - d12 * cos8[1];
    int b0 = -d03 * cos8[1] - d12 * cos8[3];

    final int shr = 12 + scale;
    a0 = (a0 + (1 << (shr - 1))) >> shr;
    b0 = (b0 + (1 << (shr - 1))) >> shr;
    a1 = (a1 + (1 << (shr - 1))) >> shr;
    b1 = (b1 + (1 << (shr - 1))) >> shr;

    out0[0][idx] = SbcTables.saturate16(a0);
    out0[3][idx] = SbcTables.saturate16(-a1);
    out0[1][idx] = SbcTables.saturate16(a1);
    out0[2][idx] = SbcTables.saturate16(0);

    out1[0][idx] = SbcTables.saturate16(-a0);
    out1[3][idx] = SbcTables.saturate16(b0);
    out1[1][idx] = SbcTables.saturate16(b0);
    out1[2][idx] = SbcTables.saturate16(b1);
  }

  void _dct8(
    Int16List input,
    int offset,
    int scale,
    List<Int16List> out0,
    List<Int16List> out1,
    int idx,
  ) {
    final Int16List cos16 = SbcTables.cos16;

    final int s07 = (input[offset + 0] + input[offset + 7]) >> 1;
    final int d07 = (input[offset + 0] - input[offset + 7]) >> 1;
    final int s16 = (input[offset + 1] + input[offset + 6]) >> 1;
    final int d16 = (input[offset + 1] - input[offset + 6]) >> 1;
    final int s25 = (input[offset + 2] + input[offset + 5]) >> 1;
    final int d25 = (input[offset + 2] - input[offset + 5]) >> 1;
    final int s34 = (input[offset + 3] + input[offset + 4]) >> 1;
    final int d34 = (input[offset + 3] - input[offset + 4]) >> 1;

    int a0 = ((s07 + s34) - (s25 + s16)) * cos16[4];
    int b3 = (-(s07 + s34) - (s25 + s16)) << 13;
    int a2 = (s07 - s34) * cos16[6] + (s25 - s16) * cos16[2];
    int b1 = (s34 - s07) * cos16[2] + (s25 - s16) * cos16[6];
    int a1 = d07 * cos16[5] - d16 * cos16[1] + d25 * cos16[7] + d34 * cos16[3];
    int b2 = -d07 * cos16[1] - d16 * cos16[3] - d25 * cos16[5] - d34 * cos16[7];
    int a3 = d07 * cos16[7] - d16 * cos16[5] + d25 * cos16[3] - d34 * cos16[1];
    int b0 = -d07 * cos16[3] + d16 * cos16[7] + d25 * cos16[1] + d34 * cos16[5];

    final int shr = 12 + scale;
    a0 = (a0 + (1 << (shr - 1))) >> shr;
    b0 = (b0 + (1 << (shr - 1))) >> shr;
    a1 = (a1 + (1 << (shr - 1))) >> shr;
    b1 = (b1 + (1 << (shr - 1))) >> shr;
    a2 = (a2 + (1 << (shr - 1))) >> shr;
    b2 = (b2 + (1 << (shr - 1))) >> shr;
    a3 = (a3 + (1 << (shr - 1))) >> shr;
    b3 = (b3 + (1 << (shr - 1))) >> shr;

    out0[0][idx] = SbcTables.saturate16(a0);
    out0[7][idx] = SbcTables.saturate16(-a1);
    out0[1][idx] = SbcTables.saturate16(a1);
    out0[6][idx] = SbcTables.saturate16(-a2);
    out0[2][idx] = SbcTables.saturate16(a2);
    out0[5][idx] = SbcTables.saturate16(-a3);
    out0[3][idx] = SbcTables.saturate16(a3);
    out0[4][idx] = SbcTables.saturate16(0);

    out1[0][idx] = SbcTables.saturate16(-a0);
    out1[7][idx] = SbcTables.saturate16(b0);
    out1[1][idx] = SbcTables.saturate16(b0);
    out1[6][idx] = SbcTables.saturate16(b1);
    out1[2][idx] = SbcTables.saturate16(b1);
    out1[5][idx] = SbcTables.saturate16(b2);
    out1[3][idx] = SbcTables.saturate16(b2);
    out1[4][idx] = SbcTables.saturate16(b3);
  }

  void _applyWindow4(
    List<Int16List> input,
    int index,
    Int16List output,
    int offset,
    int pitch,
  ) {
    final List<Int16List> window = SbcDecoderTables.window4;

    for (int i = 0; i < 4; i++) {
      int s = 0;
      for (int j = 0; j < 10; j++) {
        s += input[i][j] * window[i][index + j];
      }

      output[offset + i * pitch] = SbcTables.saturate16((s + (1 << 12)) >> 13);
    }
  }

  void _applyWindow8(
    List<Int16List> input,
    int index,
    Int16List output,
    int offset,
    int pitch,
  ) {
    final List<Int16List> window = SbcDecoderTables.window8;

    for (int i = 0; i < 8; i++) {
      int s = 0;
      for (int j = 0; j < 10; j++) {
        s += input[i][j] * window[i][index + j];
      }

      output[offset + i * pitch] = SbcTables.saturate16((s + (1 << 12)) >> 13);
    }
  }
}

class _DecoderState {
  int index = 0;
  late final List<List<Int16List>> v; // [2][MaxSubbands][10]

  _DecoderState() {
    v = <List<Int16List>>[
      List<Int16List>.generate(SbcFrame.maxSubbands, (_) => Int16List(10)),
      List<Int16List>.generate(SbcFrame.maxSubbands, (_) => Int16List(10)),
    ];
    reset();
  }

  void reset() {
    index = 0;
    for (int odd = 0; odd < 2; odd++) {
      for (int sb = 0; sb < SbcFrame.maxSubbands; sb++) {
        v[odd][sb].fillRange(0, 10, 0);
      }
    }
  }
}
