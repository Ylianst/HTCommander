/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// Demod9600.cs - Demodulator for 9600 baud baseband signal
//

using System;
using System.Runtime.CompilerServices;

namespace HamLib
{
    /// <summary>
    /// Baseband demodulator-specific state (for 9600 baud)
    /// </summary>
    public class BasebandState
    {
        public float RrcWidthSym;                                    // Width of RRC filter in symbols
        public float RrcRolloff;                                     // Rolloff factor for RRC (0-1)
        public int RrcFilterTaps;                                    // Number of filter taps for RRC
        public float[] AudioIn = new float[Dsp.MaxFilterSize];       // Audio samples input
        public float[] LpFilter = new float[Dsp.MaxFilterSize];      // Low pass filter coefficients
        public float[] LpPolyphase1 = new float[Dsp.MaxFilterSize];  // Polyphase filter 1
        public float[] LpPolyphase2 = new float[Dsp.MaxFilterSize];  // Polyphase filter 2
        public float[] LpPolyphase3 = new float[Dsp.MaxFilterSize];  // Polyphase filter 3
        public float[] LpPolyphase4 = new float[Dsp.MaxFilterSize];  // Polyphase filter 4
        public float Lp1IirParam;                                    // Low pass IIR parameter 1
        public float Lp1Out;                                         // Low pass IIR output 1
        public float Lp2IirParam;                                    // Low pass IIR parameter 2
        public float Lp2Out;                                         // Low pass IIR output 2
        public float Agc1FastAttack;                                 // AGC fast attack rate
        public float Agc1SlowDecay;                                  // AGC slow decay rate
        public float Agc1Peak;                                       // AGC peak value
        public float Agc1Valley;                                     // AGC valley value
        public float Agc2FastAttack;                                 // AGC 2 fast attack
        public float Agc2SlowDecay;                                  // AGC 2 slow decay
        public float Agc2Peak;                                       // AGC 2 peak
        public float Agc2Valley;                                     // AGC 2 valley
        public float Agc3FastAttack;                                 // AGC 3 fast attack
        public float Agc3SlowDecay;                                  // AGC 3 slow decay
        public float Agc3Peak;                                       // AGC 3 peak
        public float Agc3Valley;                                     // AGC 3 valley
    }

    /// <summary>
    /// Demodulator for 9600 baud baseband signal
    /// This is used for AX.25 (with scrambling) and IL2P (without)
    /// </summary>
    public class Demod9600
    {
        // DCD thresholds
        private const int DcdThreshOn = 32;      // Hysteresis for detecting lock
        private const int DcdThreshOff = 8;      // Threshold for losing lock
        private const int DcdGoodWidth = 1024;   // Maximum width for good transition

        // PLL cycle constant
        private const double TicksPerPllCycle = 256.0 * 256.0 * 256.0 * 256.0;

        // Maximum number of subchannels
        private const int MaxSubchans = 9;

        // Slice points for multiple slicers
        private static float[] _slicePoint = new float[MaxSubchans];

        // Baseband state needs to be added to DemodulatorState
        public class Demod9600State
        {
            public BasebandState BB = new BasebandState();
            public float LpFilterLenBits;
            public int LpFilterSize;
            public BpWindowType LpWindow;
            public float LpfBaud;
            public float AgcFastAttack;
            public float AgcSlowDecay;
            public float PllLockedInertia;
            public float PllSearchingInertia;
            public int PllStepPerSample;
        }

        /// <summary>
        /// Initialize the 9600 baud demodulator
        /// </summary>
        /// <param name="originalSampleRate">Number of samples per second for audio</param>
        /// <param name="upsample">Factor to upsample the incoming stream (1-4)</param>
        /// <param name="baud">Data rate in bits per second</param>
        /// <param name="D">Demodulator state structure</param>
        /// <param name="state9600">9600-specific state</param>
        public static void Init(int originalSampleRate, int upsample, 
            int baud, DemodulatorState D, Demod9600State state9600)
        {
            if (upsample < 1) upsample = 1;
            if (upsample > 4) upsample = 4;

            D.NumSlicers = 1;

            // Configure filter parameters
            state9600.LpFilterLenBits = 1.0f;

            // Calculate filter size - just round to nearest integer
            state9600.LpFilterSize = (int)((state9600.LpFilterLenBits * (float)originalSampleRate / baud) + 0.5f);

            state9600.LpWindow = BpWindowType.Cosine;
            state9600.LpfBaud = 1.00f;

            // AGC parameters
            state9600.AgcFastAttack = 0.080f;
            state9600.AgcSlowDecay = 0.00012f;

            // PLL parameters
            state9600.PllLockedInertia = 0.89f;
            state9600.PllSearchingInertia = 0.67f;

            // PLL needs to use the upsampled rate
            state9600.PllStepPerSample = (int)Math.Round(TicksPerPllCycle * baud / 
                (double)(originalSampleRate * upsample));

            // Initial filter (before scattering) is based on upsampled rate
            float fc = (float)baud * state9600.LpfBaud / (float)(originalSampleRate * upsample);

            // Generate the low pass filter
            Dsp.GenLowpass(fc, state9600.BB.LpFilter, state9600.LpFilterSize * upsample, state9600.LpWindow);

            // Create polyphase filters to reduce CPU load
            // Scatter the original filter across multiple shorter filters
            // Each input sample cycles around them to produce the upsampled rate
            int k = 0;
            for (int i = 0; i < state9600.LpFilterSize; i++)
            {
                state9600.BB.LpPolyphase1[i] = state9600.BB.LpFilter[k++];
                if (upsample >= 2)
                {
                    state9600.BB.LpPolyphase2[i] = state9600.BB.LpFilter[k++];
                    if (upsample >= 3)
                    {
                        state9600.BB.LpPolyphase3[i] = state9600.BB.LpFilter[k++];
                        if (upsample >= 4)
                        {
                            state9600.BB.LpPolyphase4[i] = state9600.BB.LpFilter[k++];
                        }
                    }
                }
            }

            // Initialize slice points for multiple slicers
            for (int j = 0; j < MaxSubchans; j++)
            {
                _slicePoint[j] = 0.02f * (j - 0.5f * (MaxSubchans - 1));
            }
        }

        /// <summary>
        /// Process a single audio sample
        /// </summary>
        /// <param name="chan">Audio channel (0 for left, 1 for right)</param>
        /// <param name="sam">One sample of audio (range -32768 to 32767)</param>
        /// <param name="upsample">Upsampling factor</param>
        /// <param name="D">Demodulator state</param>
        /// <param name="state9600">9600-specific state</param>
        /// <param name="hdlcReceiver">HDLC receiver for decoded bits</param>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static void ProcessSample(int chan, int sam, int upsample, 
            DemodulatorState D, Demod9600State state9600, IHdlcReceiver hdlcReceiver)
        {
            // Scale to nice number for convenience
            // Input range +-16k becomes +-1 here
            float fsam = sam / 16384.0f;

            // Low pass filter - push sample into buffer
            PushSample(fsam, state9600.BB.AudioIn, state9600.LpFilterSize);

            // Apply polyphase filters and process
            fsam = Convolve(state9600.BB.AudioIn, state9600.BB.LpPolyphase1, state9600.LpFilterSize);
            ProcessFilteredSample(chan, fsam, D, state9600, hdlcReceiver);

            if (upsample >= 2)
            {
                fsam = Convolve(state9600.BB.AudioIn, state9600.BB.LpPolyphase2, state9600.LpFilterSize);
                ProcessFilteredSample(chan, fsam, D, state9600, hdlcReceiver);

                if (upsample >= 3)
                {
                    fsam = Convolve(state9600.BB.AudioIn, state9600.BB.LpPolyphase3, state9600.LpFilterSize);
                    ProcessFilteredSample(chan, fsam, D, state9600, hdlcReceiver);

                    if (upsample >= 4)
                    {
                        fsam = Convolve(state9600.BB.AudioIn, state9600.BB.LpPolyphase4, state9600.LpFilterSize);
                        ProcessFilteredSample(chan, fsam, D, state9600, hdlcReceiver);
                    }
                }
            }
        }

        /// <summary>
        /// Add sample to buffer and shift the rest down
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static void PushSample(float val, float[] buff, int size)
        {
            // Shift all elements down by one
            Array.Copy(buff, 0, buff, 1, size - 1);
            buff[0] = val;
        }

        /// <summary>
        /// FIR filter kernel - convolve data with filter
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static float Convolve(float[] data, float[] filter, int filterSize)
        {
            float sum = 0.0f;
            for (int j = 0; j < filterSize; j++)
            {
                sum += filter[j] * data[j];
            }
            return sum;
        }

        /// <summary>
        /// Automatic gain control
        /// Result should settle down to 1 unit peak to peak (i.e. -0.5 to +0.5)
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static float Agc(float input, float fastAttack, float slowDecay, 
            ref float peak, ref float valley)
        {
            if (input >= peak)
            {
                peak = input * fastAttack + peak * (1.0f - fastAttack);
            }
            else
            {
                peak = input * slowDecay + peak * (1.0f - slowDecay);
            }

            if (input <= valley)
            {
                valley = input * fastAttack + valley * (1.0f - fastAttack);
            }
            else
            {
                valley = input * slowDecay + valley * (1.0f - slowDecay);
            }

            if (peak > valley)
            {
                return (input - 0.5f * (peak + valley)) / (peak - valley);
            }
            return 0.0f;
        }

        /// <summary>
        /// Process a filtered sample
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static void ProcessFilteredSample(int chan, float fsam, 
            DemodulatorState D, Demod9600State state9600, IHdlcReceiver hdlcReceiver)
        {
            const int subchan = 0;  // Fixed subchannel for 9600 baud

            // Capture post-filtering amplitude for display
            // Similar to AGC without normalization - for audio level display
            if (fsam >= D.AlevelMarkPeak)
            {
                D.AlevelMarkPeak = fsam * D.QuickAttack + D.AlevelMarkPeak * (1.0f - D.QuickAttack);
            }
            else
            {
                D.AlevelMarkPeak = fsam * D.SluggishDecay + D.AlevelMarkPeak * (1.0f - D.SluggishDecay);
            }

            if (fsam <= D.AlevelSpacePeak)
            {
                D.AlevelSpacePeak = fsam * D.QuickAttack + D.AlevelSpacePeak * (1.0f - D.QuickAttack);
            }
            else
            {
                D.AlevelSpacePeak = fsam * D.SluggishDecay + D.AlevelSpacePeak * (1.0f - D.SluggishDecay);
            }

            // Normalize the signal with automatic gain control (AGC)
            // This removes DC bias and scales to roughly -1.0 to +1.0 range
            float demodOut = Agc(fsam, state9600.AgcFastAttack, state9600.AgcSlowDecay, 
                ref D.MPeak, ref D.MValley);

            int demodData;

            if (D.NumSlicers <= 1)
            {
                // Normal case: one demodulator to one HDLC decoder
                demodData = demodOut > 0 ? 1 : 0;
                NudgePll(chan, subchan, 0, demodOut, D, state9600, hdlcReceiver);
            }
            else
            {
                // Multiple slicers each feeding its own HDLC decoder
                for (int slice = 0; slice < D.NumSlicers; slice++)
                {
                    demodData = (demodOut - _slicePoint[slice]) > 0 ? 1 : 0;
                    NudgePll(chan, subchan, slice, demodOut - _slicePoint[slice], D, state9600, hdlcReceiver);
                }
            }
        }

        /// <summary>
        /// Update the PLL state for each audio sample
        /// A PLL is used to sample near the centers of the data bits
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static void NudgePll(int chan, int subchan, int slice, float demodOutF,
            DemodulatorState D, Demod9600State state9600, IHdlcReceiver hdlcReceiver)
        {
            SlicerState S = D.Slicer[slice];

            S.PrevDClockPll = S.DataClockPll;

            // Perform the add as unsigned to avoid signed overflow
            unchecked
            {
                S.DataClockPll = (int)((uint)S.DataClockPll + (uint)state9600.PllStepPerSample);
            }

            // Check for overflow (was large positive, now large negative)
            if (S.PrevDClockPll > 1000000000 && S.DataClockPll < -1000000000)
            {
                // Sample the data bit
                int rawBit = demodOutF > 0 ? 1 : 0;
                
                // Descramble the bit for 9600 baud (G3RUH scrambling)
                int descrambledBit = Descramble(rawBit, ref S.Lfsr);
                
                if (hdlcReceiver != null)
                {
                    // Pass the descrambled bit to HDLC receiver
                    hdlcReceiver.RecBit(chan, subchan, slice, descrambledBit, 
                        false, 0);
                }

                S.PllSymbolCount++;

                // Update DCD state
                PllDcdEachSymbol2(D, chan, subchan, slice);
            }

            // Check for zero crossing
            if ((S.PrevDemodOutF < 0 && demodOutF > 0) || 
                (S.PrevDemodOutF > 0 && demodOutF < 0))
            {
                // Signal transition detected
                PllDcdSignalTransition2(D, slice, S.DataClockPll);

                // Calculate target phase using linear interpolation
                float target = state9600.PllStepPerSample * demodOutF / (demodOutF - S.PrevDemodOutF);

                int before = S.DataClockPll;

                // Nudge PLL toward the target
                if (S.DataDetect != 0)
                {
                    // Locked on - use locked inertia
                    S.DataClockPll = (int)(S.DataClockPll * state9600.PllLockedInertia + 
                        target * (1.0f - state9600.PllLockedInertia));
                }
                else
                {
                    // Searching - use searching inertia
                    S.DataClockPll = (int)(S.DataClockPll * state9600.PllSearchingInertia + 
                        target * (1.0f - state9600.PllSearchingInertia));
                }

                S.PllNudgeTotal += (long)S.DataClockPll - (long)before;
            }

            // Remember demodulator output for next comparison
            S.PrevDemodOutF = demodOutF;
        }

        /// <summary>
        /// Update DCD state when a signal transition is detected
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static void PllDcdSignalTransition2(DemodulatorState D, int slice, int dpllPhase)
        {
            SlicerState S = D.Slicer[slice];

            // Check if transition occurred at expected time (good) or not (bad)
            if (dpllPhase > -DcdGoodWidth * 1024 * 1024 && dpllPhase < DcdGoodWidth * 1024 * 1024)
            {
                S.GoodFlag = 1;
            }
            else
            {
                S.BadFlag = 1;
            }
        }

        /// <summary>
        /// Update DCD state for each symbol
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static void PllDcdEachSymbol2(DemodulatorState D, int chan, int subchan, int slice)
        {
            SlicerState S = D.Slicer[slice];

            // Shift history and add current flags
            S.GoodHist <<= 1;
            S.GoodHist |= (byte)S.GoodFlag;
            S.GoodFlag = 0;

            S.BadHist <<= 1;
            S.BadHist |= (byte)S.BadFlag;
            S.BadFlag = 0;

            S.Score <<= 1;

            // Compare good vs bad transitions (need at least 2 for flag pattern)
            int goodCount = PopCount(S.GoodHist);
            int badCount = PopCount(S.BadHist);
            S.Score |= (uint)((goodCount - badCount >= 2) ? 1 : 0);

            // Check overall score
            int scoreCount = PopCount(S.Score);

            if (scoreCount >= DcdThreshOn)
            {
                if (S.DataDetect == 0)
                {
                    S.DataDetect = 1;
                    // Would call dcd_change here in full implementation
                }
            }
            else if (scoreCount <= DcdThreshOff)
            {
                if (S.DataDetect != 0)
                {
                    S.DataDetect = 0;
                    // Would call dcd_change here in full implementation
                }
            }
        }

        /// <summary>
        /// Count number of set bits (population count)
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static int PopCount(byte value)
        {
            int count = 0;
            while (value != 0)
            {
                count++;
                value &= (byte)(value - 1);
            }
            return count;
        }

        /// <summary>
        /// Count number of set bits in 32-bit value
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static int PopCount(uint value)
        {
            int count = 0;
            while (value != 0)
            {
                count++;
                value &= value - 1;
            }
            return count;
        }

        /// <summary>
        /// Descramble a bit for G3RUH/K9NG scrambling
        /// The data stream must be unscrambled at the receiving end
        /// </summary>
        /// <param name="input">Input bit (0 or 1)</param>
        /// <param name="state">Scrambler/descrambler state (shift register)</param>
        /// <returns>Descrambled output bit (0 or 1)</returns>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static int Descramble(int input, ref int state)
        {
            int output = (input ^ (state >> 16) ^ (state >> 11)) & 1;
            state = (state << 1) | (input & 1);
            return output;
        }
    }
}
