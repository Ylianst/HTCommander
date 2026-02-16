/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{

    /// <summary>
    /// SBC sampling frequencies
    /// </summary>
    public enum SbcFrequency
    {
        /// <summary>16 kHz</summary>
        Freq16K = 0,
        /// <summary>32 kHz</summary>
        Freq32K = 1,
        /// <summary>44.1 kHz</summary>
        Freq44K1 = 2,
        /// <summary>48 kHz</summary>
        Freq48K = 3
    }

    /// <summary>
    /// SBC channel modes
    /// </summary>
    public enum SbcMode
    {
        /// <summary>Mono (1 channel)</summary>
        Mono = 0,
        /// <summary>Dual channel (2 independent channels)</summary>
        DualChannel = 1,
        /// <summary>Stereo (2 channels)</summary>
        Stereo = 2,
        /// <summary>Joint stereo (2 channels with joint encoding)</summary>
        JointStereo = 3
    }

    /// <summary>
    /// SBC bit allocation method
    /// </summary>
    public enum SbcBitAllocationMethod
    {
        /// <summary>Loudness allocation</summary>
        Loudness = 0,
        /// <summary>SNR allocation</summary>
        SNR = 1
    }
}