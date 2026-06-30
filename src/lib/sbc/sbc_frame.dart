/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'sbc_enums.dart';

/// SBC frame configuration and parameters.
class SbcFrame {
  /// Maximum number of subbands.
  static const int maxSubbands = 8;

  /// Maximum number of blocks.
  static const int maxBlocks = 16;

  /// Maximum samples per frame.
  static const int maxSamples = maxBlocks * maxSubbands;

  /// SBC frame header size in bytes.
  static const int headerSize = 4;

  /// mSBC samples per frame (fixed at 120).
  static const int msbcSamples = 120;

  /// mSBC frame size in bytes (fixed at 57).
  static const int msbcSize = 57;

  /// Whether this is an mSBC (Bluetooth HFP) frame.
  bool isMsbc = false;

  /// Sampling frequency.
  SbcFrequency frequency = SbcFrequency.freq16K;

  /// Channel mode.
  SbcMode mode = SbcMode.mono;

  /// Bit allocation method.
  SbcBitAllocationMethod allocationMethod = SbcBitAllocationMethod.loudness;

  /// Number of blocks (4, 8, 12, or 16).
  int blocks = 0;

  /// Number of subbands (4 or 8).
  int subbands = 0;

  /// Bitpool value (controls quality/bitrate).
  int bitpool = 0;

  /// Get the sampling frequency in Hz.
  int getFrequencyHz() {
    switch (frequency) {
      case SbcFrequency.freq16K:
        return 16000;
      case SbcFrequency.freq32K:
        return 32000;
      case SbcFrequency.freq44K1:
        return 44100;
      case SbcFrequency.freq48K:
        return 48000;
    }
  }

  /// Get the algorithmic codec delay in samples (encoding + decoding).
  int getDelay() => 10 * subbands;

  /// Check if the frame configuration is valid.
  bool isValid() {
    // Check number of blocks
    if (blocks < 4 || blocks > 16 || (!isMsbc && blocks % 4 != 0)) {
      return false;
    }

    // Check number of subbands
    if (subbands != 4 && subbands != 8) {
      return false;
    }

    // Validate bitpool value
    final bool twoChannels = mode != SbcMode.mono;
    final bool dualMode = mode == SbcMode.dualChannel;
    final bool jointMode = mode == SbcMode.jointStereo;
    final bool stereoMode = jointMode || mode == SbcMode.stereo;

    final int maxBits =
        ((16 * subbands * blocks) << (twoChannels ? 1 : 0)) -
        (headerSize * 8) -
        ((4 * subbands) << (twoChannels ? 1 : 0)) -
        (jointMode ? subbands : 0);

    final int maxBitpool = _min(
      maxBits ~/ (blocks << (dualMode ? 1 : 0)),
      (16 << (stereoMode ? 1 : 0)) * subbands,
    );

    return bitpool <= maxBitpool;
  }

  /// Get the frame size in bytes.
  int getFrameSize() {
    if (!isValid()) {
      return 0;
    }

    final bool twoChannels = mode != SbcMode.mono;
    final bool dualMode = mode == SbcMode.dualChannel;
    final bool jointMode = mode == SbcMode.jointStereo;

    final int nbits =
        ((4 * subbands) << (twoChannels ? 1 : 0)) +
        ((blocks * bitpool) << (dualMode ? 1 : 0)) +
        (jointMode ? subbands : 0);

    return headerSize + ((nbits + 7) >> 3);
  }

  /// Get the bitrate in bits per second.
  int getBitrate() {
    if (!isValid()) {
      return 0;
    }

    final int nsamples = blocks * subbands;
    final int nbits = 8 * getFrameSize();

    return (nbits * getFrequencyHz()) ~/ nsamples;
  }

  /// Create a standard mSBC frame configuration.
  static SbcFrame createMsbc() {
    return SbcFrame()
      ..isMsbc = true
      ..mode = SbcMode.mono
      ..frequency = SbcFrequency.freq16K
      ..allocationMethod = SbcBitAllocationMethod.loudness
      ..subbands = 8
      ..blocks = 15
      ..bitpool = 26;
  }

  static int _min(int a, int b) => a < b ? a : b;
}
