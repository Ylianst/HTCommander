/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// SBC sampling frequencies.
enum SbcFrequency {
  /// 16 kHz
  freq16K,

  /// 32 kHz
  freq32K,

  /// 44.1 kHz
  freq44K1,

  /// 48 kHz
  freq48K,
}

/// SBC channel modes.
enum SbcMode {
  /// Mono (1 channel)
  mono,

  /// Dual channel (2 independent channels)
  dualChannel,

  /// Stereo (2 channels)
  stereo,

  /// Joint stereo (2 channels with joint encoding)
  jointStereo,
}

/// SBC bit allocation method.
enum SbcBitAllocationMethod {
  /// Loudness allocation
  loudness,

  /// SNR allocation
  snr,
}
