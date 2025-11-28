/*
Copyright 2025 Ylian Saint-Hilaire

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
// DemodPsk.cs - PSK (Phase Shift Keying) Demodulator
// Port of demod_psk.c from Dire Wolf
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// PSK-specific demodulator state
    /// </summary>
    public class PskState
    {
        public V26Alternative V26Alt;                           // Which alternative when V.26
        public float[] SinTable256 = new float[256];            // Precomputed sin table for speed

        // Optional band pass pre-filter before phase detector
        public int UsePrefilter;                                // True to enable it
        public float PrefilterBaud;                             // Cutoff frequencies as fraction of baud rate
        public float PreFilterWidthSym;                         // Length in number of symbol times
        public BpWindowType PreWindow;                          // Window type
        public int PreFilterTaps;                               // Size of pre filter in audio samples
        public float[] AudioIn = new float[Dsp.MaxFilterSize];  // Audio input buffer
        public float[] PreFilter = new float[Dsp.MaxFilterSize]; // Pre-filter coefficients

        // Use local oscillator or correlate with previous sample
        public int PskUseLo;                                    // Use local oscillator rather than self correlation
        public uint LoStep;                                     // How much to advance LO phase per sample
        public uint LoPhase;                                    // Local oscillator phase accumulator

        // After mixing with LO before low pass filter
        public float[] IRaw = new float[Dsp.MaxFilterSize];     // signal * LO cos
        public float[] QRaw = new float[Dsp.MaxFilterSize];     // signal * LO sin

        // Delay line for correlation with previous symbol
        public int BOffs;                                       // Symbol length based on sample rate and baud
        public int COffs;                                       // To get cos component of previous symbol
        public int SOffs;                                       // To get sin component of previous symbol
        public float DelayLineWidthSym;                         // Delay line width in symbols
        public int DelayLineTaps;                               // In audio samples
        public float[] DelayLine = new float[Dsp.MaxFilterSize]; // Delay line buffer

        // Low pass filter
        public float LpfBaud;                                   // Cutoff frequency as fraction of baud
        public float LpFilterWidthSym;                          // Length in number of symbol times
        public int LpFilterTaps;                                // Size of low pass filter in audio samples
        public BpWindowType LpWindow;                           // Window type
        public float[] LpFilter = new float[Dsp.MaxFilterSize]; // Low pass filter coefficients
    }

    /// <summary>
    /// Extended demodulator state for PSK
    /// </summary>
    public class PskDemodulatorState : DemodulatorState
    {
        public ModemType ModemType;                             // QPSK or 8PSK
        public PskState Psk = new PskState();                   // PSK-specific state

        public PskDemodulatorState() : base()
        {
        }
    }

    /// <summary>
    /// PSK Demodulator for 2400 and 4800 bps Phase Shift Keying
    /// </summary>
    public class DemodPsk
    {
        // Phase to Gray code conversion tables
        private static readonly int[] PhaseToGrayV26 = { 0, 1, 3, 2 };
        private static readonly int[] PhaseToGrayV27 = { 1, 0, 2, 3, 7, 6, 4, 5 };

        // DCD detection constants
        private const int DcdThreshOn = 30;    // Hysteresis for DCD detect
        private const int DcdThreshOff = 6;
        private const int DcdGoodWidth = 512;

        private IHdlcReceiver _hdlcRec;

        public DemodPsk(IHdlcReceiver hdlcRec)
        {
            _hdlcRec = hdlcRec;
        }

        /// <summary>
        /// Add sample to buffer and shift the rest down
        /// </summary>
        private static void PushSample(float val, float[] buff, int size)
        {
            Array.Copy(buff, 0, buff, 1, size - 1);
            buff[0] = val;
        }

        /// <summary>
        /// FIR filter convolution kernel
        /// </summary>
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
        /// Fast atan2 approximation
        /// </summary>
        private static float MyAtan2f(float y, float x)
        {
            if (y == 0 && x == 0) return 0.0f; // Handle special case
            return (float)Math.Atan2(y, x);
        }

        /// <summary>
        /// Translate phase shift between two symbols into 2 or 3 bits
        /// </summary>
        private static int PhaseShiftToSymbol(float phaseShift, int bitsPerSymbol, int[] bitQuality)
        {
            Debug.Assert(bitsPerSymbol == 2 || bitsPerSymbol == 3);
            int N = 1 << bitsPerSymbol;
            Debug.Assert(N == 4 || N == 8);

            // Scale angle to 1 per symbol then separate into integer and fractional parts
            float a = phaseShift * N / (float)(Math.PI * 2.0);
            while (a >= N) a -= N;
            while (a < 0) a += N;
            int i = (int)a;
            if (i == N) i = N - 1; // Should be < N. Watch out for possible roundoff errors
            float f = a - i;
            Debug.Assert(i >= 0 && i < N);
            Debug.Assert(f >= -0.001f && f <= 1.001f);

            // Interpolate between the ideal angles to get a level of certainty
            int result = 0;
            for (int b = 0; b < bitsPerSymbol; b++)
            {
                float demod = bitsPerSymbol == 2 ?
                    ((PhaseToGrayV26[i] >> b) & 1) * (1.0f - f) + ((PhaseToGrayV26[(i + 1) & 3] >> b) & 1) * f :
                    ((PhaseToGrayV27[i] >> b) & 1) * (1.0f - f) + ((PhaseToGrayV27[(i + 1) & 7] >> b) & 1) * f;

                // Slice to get boolean value and quality measurement
                if (demod >= 0.5f) result |= 1 << b;
                bitQuality[b] = (int)Math.Round(100.0f * 2.0f * Math.Abs(demod - 0.5f));
            }
            return result;
        }

        /// <summary>
        /// Initialize PSK demodulator
        /// </summary>
        public void Init(ModemType modemType, V26Alternative v26Alt, int samplesPerSec, 
            int bps, char profile, PskDemodulatorState D)
        {
            int correctBaud; // baud is not same as bits/sec here!
            int carrierFreq;

            D.ModemType = modemType;
            D.Psk.V26Alt = v26Alt;
            D.NumSlicers = 1; // Haven't thought about this yet. Is it even applicable?

            if (modemType == ModemType.Qpsk)
            {
                Debug.Assert(D.Psk.V26Alt != V26Alternative.Unspecified);

                correctBaud = bps / 2;
                carrierFreq = 1800;

                switch (char.ToUpper(profile))
                {
                    case 'P': // Self correlation technique
                        D.Psk.UsePrefilter = 0; // No bandpass filter
                        D.Psk.LpfBaud = 0.60f;
                        D.Psk.LpFilterWidthSym = 1.061f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.95f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'Q': // Self correlation technique with prefilter
                        D.Psk.UsePrefilter = 1; // Add a bandpass filter
                        D.Psk.PrefilterBaud = 1.3f;
                        D.Psk.PreFilterWidthSym = 1.497f;
                        D.Psk.PreWindow = BpWindowType.Cosine;
                        D.Psk.LpfBaud = 0.60f;
                        D.Psk.LpFilterWidthSym = 1.061f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.87f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'R': // Mix with local oscillator
                    default:
                        D.Psk.PskUseLo = 1;
                        D.Psk.UsePrefilter = 0; // No bandpass filter
                        D.Psk.LpfBaud = 0.70f;
                        D.Psk.LpFilterWidthSym = 1.007f;
                        D.Psk.LpWindow = BpWindowType.Truncated;
                        D.PllLockedInertia = 0.925f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'S': // Mix with local oscillator with prefilter
                        D.Psk.PskUseLo = 1;
                        D.Psk.UsePrefilter = 1; // Add a bandpass filter
                        D.Psk.PrefilterBaud = 0.55f;
                        D.Psk.PreFilterWidthSym = 2.014f;
                        D.Psk.PreWindow = BpWindowType.Flattop;
                        D.Psk.LpfBaud = 0.60f;
                        D.Psk.LpFilterWidthSym = 1.061f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.925f;
                        D.PllSearchingInertia = 0.50f;
                        break;
                }

                D.Psk.DelayLineWidthSym = 1.25f; // Delay line > 13/12 * symbol period
                D.Psk.COffs = (int)Math.Round((11.0f / 12.0f) * samplesPerSec / (float)correctBaud);
                D.Psk.BOffs = (int)Math.Round(samplesPerSec / (float)correctBaud);
                D.Psk.SOffs = (int)Math.Round((13.0f / 12.0f) * samplesPerSec / (float)correctBaud);
            }
            else // 8PSK
            {
                correctBaud = bps / 3;
                carrierFreq = 1800;

                switch (char.ToUpper(profile))
                {
                    case 'T': // Self correlation technique
                        D.Psk.UsePrefilter = 0; // No bandpass filter
                        D.Psk.LpfBaud = 1.15f;
                        D.Psk.LpFilterWidthSym = 0.871f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.95f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'U': // Self correlation technique with prefilter
                        D.Psk.UsePrefilter = 1; // Add a bandpass filter
                        D.Psk.PrefilterBaud = 0.9f;
                        D.Psk.PreFilterWidthSym = 0.571f;
                        D.Psk.PreWindow = BpWindowType.Flattop;
                        D.Psk.LpfBaud = 1.15f;
                        D.Psk.LpFilterWidthSym = 0.871f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.87f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'V': // Mix with local oscillator
                    default:
                        D.Psk.PskUseLo = 1;
                        D.Psk.UsePrefilter = 0; // No bandpass filter
                        D.Psk.LpfBaud = 0.85f;
                        D.Psk.LpFilterWidthSym = 0.844f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.925f;
                        D.PllSearchingInertia = 0.50f;
                        break;

                    case 'W': // Mix with local oscillator with prefilter
                        D.Psk.PskUseLo = 1;
                        D.Psk.UsePrefilter = 1; // Add a bandpass filter
                        D.Psk.PrefilterBaud = 0.85f;
                        D.Psk.PreFilterWidthSym = 0.844f;
                        D.Psk.PreWindow = BpWindowType.Cosine;
                        D.Psk.LpfBaud = 0.85f;
                        D.Psk.LpFilterWidthSym = 0.844f;
                        D.Psk.LpWindow = BpWindowType.Cosine;
                        D.PllLockedInertia = 0.925f;
                        D.PllSearchingInertia = 0.50f;
                        break;
                }

                D.Psk.DelayLineWidthSym = 1.25f; // Delay line > 10/9 * symbol period
                D.Psk.COffs = (int)Math.Round((8.0f / 9.0f) * samplesPerSec / (float)correctBaud);
                D.Psk.BOffs = (int)Math.Round(samplesPerSec / (float)correctBaud);
                D.Psk.SOffs = (int)Math.Round((10.0f / 9.0f) * samplesPerSec / (float)correctBaud);
            }

            // Initialize local oscillator if used
            if (D.Psk.PskUseLo != 0)
            {
                D.Psk.LoStep = (uint)Math.Round(Math.Pow(256.0, 4) * carrierFreq / (double)samplesPerSec);

                // Pre-compute sin table for speed
                for (int j = 0; j < 256; j++)
                {
                    D.Psk.SinTable256[j] = (float)Math.Sin(2.0 * Math.PI * j / 256.0);
                }
            }

            // Calculate timing constants
            D.PllStepPerSample = (int)Math.Round((DemodulatorState.TicksPerPllCycle * correctBaud) / (double)samplesPerSec);

            // Convert symbol times to number of taps
            D.Psk.PreFilterTaps = (int)Math.Round(D.Psk.PreFilterWidthSym * samplesPerSec / (float)correctBaud);
            D.Psk.DelayLineTaps = (int)Math.Round(D.Psk.DelayLineWidthSym * samplesPerSec / (float)correctBaud);
            D.Psk.LpFilterTaps = (int)Math.Round(D.Psk.LpFilterWidthSym * samplesPerSec / (float)correctBaud);

            // Validate filter sizes
            if (D.Psk.PreFilterTaps > Dsp.MaxFilterSize)
            {
                Console.WriteLine($"Calculated pre filter size of {D.Psk.PreFilterTaps} is too large.");
                throw new InvalidOperationException("Pre filter size too large");
            }

            if (D.Psk.DelayLineTaps > Dsp.MaxFilterSize)
            {
                Console.WriteLine($"Calculated delay line size of {D.Psk.DelayLineTaps} is too large.");
                throw new InvalidOperationException("Delay line size too large");
            }

            if (D.Psk.LpFilterTaps > Dsp.MaxFilterSize)
            {
                Console.WriteLine($"Calculated low pass filter size of {D.Psk.LpFilterTaps} is too large.");
                throw new InvalidOperationException("Low pass filter size too large");
            }

            // Generate prefilter if enabled
            if (D.Psk.UsePrefilter != 0)
            {
                float f1 = carrierFreq - D.Psk.PrefilterBaud * correctBaud;
                float f2 = carrierFreq + D.Psk.PrefilterBaud * correctBaud;

                if (f1 <= 0)
                {
                    Console.WriteLine($"Prefilter of {f1} to {f2} Hz doesn't make sense.");
                    f1 = 10;
                }

                f1 = f1 / samplesPerSec;
                f2 = f2 / samplesPerSec;

                Dsp.GenBandpass(f1, f2, D.Psk.PreFilter, D.Psk.PreFilterTaps, D.Psk.PreWindow);
            }

            // Generate lowpass filter
            float fc = correctBaud * D.Psk.LpfBaud / samplesPerSec;
            Dsp.GenLowpass(fc, D.Psk.LpFilter, D.Psk.LpFilterTaps, D.Psk.LpWindow);

            // No point in having multiple numbers for signal level
            D.AlevelMarkPeak = -1;
            D.AlevelSpacePeak = -1;
        }

        /// <summary>
        /// Process one audio sample through the PSK demodulator
        /// </summary>
        public void ProcessSample(int chan, int subchan, int sam, PskDemodulatorState D)
        {
            int slice = 0; // Would it make sense to have more than one?

            Debug.Assert(chan >= 0 && chan < AudioConfig.MaxRadioChannels);
            Debug.Assert(subchan >= 0 && subchan < AudioConfig.MaxSlicers);

            // Scale to nice number for plotting during debug
            float fsam = sam / 16384.0f;

            // Optional bandpass filter before the phase detector
            if (D.Psk.UsePrefilter != 0)
            {
                PushSample(fsam, D.Psk.AudioIn, D.Psk.PreFilterTaps);
                fsam = Convolve(D.Psk.AudioIn, D.Psk.PreFilter, D.Psk.PreFilterTaps);
            }

            if (D.Psk.PskUseLo != 0)
            {
                // Mix with local oscillator to obtain phase
                float samXCos = fsam * D.Psk.SinTable256[((D.Psk.LoPhase >> 24) + 64) & 0xff];
                PushSample(samXCos, D.Psk.IRaw, D.Psk.LpFilterTaps);
                float I = Convolve(D.Psk.IRaw, D.Psk.LpFilter, D.Psk.LpFilterTaps);

                float samXSin = fsam * D.Psk.SinTable256[(D.Psk.LoPhase >> 24) & 0xff];
                PushSample(samXSin, D.Psk.QRaw, D.Psk.LpFilterTaps);
                float Q = Convolve(D.Psk.QRaw, D.Psk.LpFilter, D.Psk.LpFilterTaps);

                float a = MyAtan2f(I, Q);

                // This is just a delay line of one symbol time
                PushSample(a, D.Psk.DelayLine, D.Psk.DelayLineTaps);
                float delta = a - D.Psk.DelayLine[D.Psk.BOffs];

                int gray;
                int[] bitQuality = new int[3];
                if (D.ModemType == ModemType.Qpsk)
                {
                    if (D.Psk.V26Alt == V26Alternative.B)
                    {
                        gray = PhaseShiftToSymbol(delta + (float)(-Math.PI / 4), 2, bitQuality); // MFJ compatible
                    }
                    else
                    {
                        gray = PhaseShiftToSymbol(delta, 2, bitQuality); // Classic
                    }
                }
                else
                {
                    gray = PhaseShiftToSymbol(delta, 3, bitQuality); // 8-PSK
                }
                NudgePll(chan, subchan, slice, gray, D, bitQuality);

                D.Psk.LoPhase += D.Psk.LoStep;
            }
            else
            {
                // Correlate with previous symbol. We are looking for the phase shift.
                PushSample(fsam, D.Psk.DelayLine, D.Psk.DelayLineTaps);

                float samXCos = fsam * D.Psk.DelayLine[D.Psk.COffs];
                PushSample(samXCos, D.Psk.IRaw, D.Psk.LpFilterTaps);
                float I = Convolve(D.Psk.IRaw, D.Psk.LpFilter, D.Psk.LpFilterTaps);

                float samXSin = fsam * D.Psk.DelayLine[D.Psk.SOffs];
                PushSample(samXSin, D.Psk.QRaw, D.Psk.LpFilterTaps);
                float Q = Convolve(D.Psk.QRaw, D.Psk.LpFilter, D.Psk.LpFilterTaps);

                int gray;
                int[] bitQuality = new int[3];
                float delta = MyAtan2f(I, Q);

                if (D.ModemType == ModemType.Qpsk)
                {
                    if (D.Psk.V26Alt == V26Alternative.B)
                    {
                        gray = PhaseShiftToSymbol(delta + (float)(Math.PI / 2), 2, bitQuality); // MFJ compatible
                    }
                    else
                    {
                        gray = PhaseShiftToSymbol(delta + (float)(3 * Math.PI / 4), 2, bitQuality); // Classic
                    }
                }
                else
                {
                    gray = PhaseShiftToSymbol(delta + (float)(3 * Math.PI / 2), 3, bitQuality);
                }
                NudgePll(chan, subchan, slice, gray, D, bitQuality);
            }
        }

        /// <summary>
        /// Digital Phase Locked Loop for symbol timing recovery
        /// </summary>
        private void NudgePll(int chan, int subchan, int slice, int demodBits, 
            PskDemodulatorState D, int[] bitQuality)
        {
            var S = D.Slicer[slice];

            S.PrevDClockPll = S.DataClockPll;

            // Perform the add as unsigned to avoid signed overflow error
            S.DataClockPll = (int)((uint)S.DataClockPll + (uint)D.PllStepPerSample);

            if (S.DataClockPll < 0 && S.PrevDClockPll >= 0)
            {
                // Overflow of PLL counter - this is where we sample the data
                if (D.ModemType == ModemType.Qpsk)
                {
                    int gray = demodBits;
                    _hdlcRec.RecBit(chan, subchan, slice, (gray >> 1) & 1, false, bitQuality[1]);
                    _hdlcRec.RecBit(chan, subchan, slice, gray & 1, false, bitQuality[0]);
                }
                else
                {
                    int gray = demodBits;
                    _hdlcRec.RecBit(chan, subchan, slice, (gray >> 2) & 1, false, bitQuality[2]);
                    _hdlcRec.RecBit(chan, subchan, slice, (gray >> 1) & 1, false, bitQuality[1]);
                    _hdlcRec.RecBit(chan, subchan, slice, gray & 1, false, bitQuality[0]);
                }
                S.PllSymbolCount++;
                PllDcdEachSymbol(D, chan, subchan, slice);
            }

            // If demodulated data has changed, pull the PLL phase closer to zero
            if (demodBits != S.PrevDemodData)
            {
                PllDcdSignalTransition(D, slice, S.DataClockPll);

                int before = S.DataClockPll; // Treat as signed
                if (S.DataDetect != 0)
                {
                    S.DataClockPll = (int)Math.Floor(S.DataClockPll * D.PllLockedInertia);
                }
                else
                {
                    S.DataClockPll = (int)Math.Floor(S.DataClockPll * D.PllSearchingInertia);
                }
                S.PllNudgeTotal += (long)S.DataClockPll - (long)before;
            }

            // Remember demodulator output so we can compare next time
            S.PrevDemodData = demodBits;
        }

        /// <summary>
        /// Check if transition occurred at good or bad time
        /// </summary>
        private void PllDcdSignalTransition(PskDemodulatorState D, int slice, int dpllPhase)
        {
            if (dpllPhase > -DcdGoodWidth * 1024 * 1024 && dpllPhase < DcdGoodWidth * 1024 * 1024)
            {
                D.Slicer[slice].GoodFlag = 1;
            }
            else
            {
                D.Slicer[slice].BadFlag = 1;
            }
        }

        /// <summary>
        /// Update DCD state after each symbol
        /// </summary>
        private void PllDcdEachSymbol(PskDemodulatorState D, int chan, int subchan, int slice)
        {
            var S = D.Slicer[slice];

            S.GoodHist <<= 1;
            S.GoodHist |= (byte)S.GoodFlag;
            S.GoodFlag = 0;

            S.BadHist <<= 1;
            S.BadHist |= (byte)S.BadFlag;
            S.BadFlag = 0;

            S.Score <<= 1;
            // 2 is to detect 'flag' patterns with 2 transitions per octet
            S.Score |= (uint)((PopCount(S.GoodHist) - PopCount(S.BadHist) >= 2) ? 1 : 0);

            int score = PopCount(S.Score);
            if (score >= DcdThreshOn)
            {
                if (S.DataDetect == 0)
                {
                    S.DataDetect = 1;
                    _hdlcRec.DcdChange(chan, subchan, slice, true);
                }
            }
            else if (score <= DcdThreshOff)
            {
                if (S.DataDetect != 0)
                {
                    S.DataDetect = 0;
                    _hdlcRec.DcdChange(chan, subchan, slice, false);
                }
            }
        }

        /// <summary>
        /// Count number of set bits (population count)
        /// </summary>
        private int PopCount(uint x)
        {
            int count = 0;
            while (x != 0)
            {
                count++;
                x &= x - 1; // Clear least significant set bit
            }
            return count;
        }

        /// <summary>
        /// Count number of set bits in byte
        /// </summary>
        private int PopCount(byte x)
        {
            return PopCount((uint)x);
        }
    }
}
