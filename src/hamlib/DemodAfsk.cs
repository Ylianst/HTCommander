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
// DemodAfsk.cs - AFSK (Audio Frequency Shift Keying) Demodulator
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Slicer state for PLL and data detection
    /// </summary>
    public class SlicerState
    {
        public int DataClockPll;              // PLL for data clock recovery (32-bit signed)
        public int PrevDClockPll;             // Previous value before incrementing
        public int PllSymbolCount;            // Number of symbols during nudge accumulation
        public long PllNudgeTotal;            // Sum of DPLL nudge amounts
        public int PrevDemodData;             // Previous data bit detected
        public float PrevDemodOutF;           // Previous demodulator output (float)
        public int Lfsr;                      // Descrambler shift register (for 9600 baud)

        // For detecting phase lock to incoming signal
        public int GoodFlag;                  // Set if transition near expected time
        public int BadFlag;                   // Set if transition not where expected
        public byte GoodHist;                 // History of good transitions for past octet
        public byte BadHist;                  // History of bad transitions for past octet
        public uint Score;                    // History of good vs bad for past 32 symbols
        public int DataDetect;                // True when locked on to signal
    }

    /// <summary>
    /// AFSK-specific demodulator state
    /// </summary>
    public class AfskState
    {
        // Local oscillators for Mark, Space, and Center frequencies
        public uint MOscPhase;                // Phase for Mark local oscillator
        public uint MOscDelta;                // How much to change per audio sample
        public uint SOscPhase;                // Phase for Space local oscillator
        public uint SOscDelta;                // How much to change per audio sample
        public uint COscPhase;                // Phase for Center frequency local oscillator
        public uint COscDelta;                // How much to change per audio sample

        // Mixer outputs for Mark (profile A)
        public float[] MIRaw = new float[Dsp.MaxFilterSize];
        public float[] MQRaw = new float[Dsp.MaxFilterSize];

        // Mixer outputs for Space (profile A)
        public float[] SIRaw = new float[Dsp.MaxFilterSize];
        public float[] SQRaw = new float[Dsp.MaxFilterSize];

        // Mixer outputs for Center (profile B)
        public float[] CIRaw = new float[Dsp.MaxFilterSize];
        public float[] CQRaw = new float[Dsp.MaxFilterSize];

        // Root Raised Cosine filter settings
        public int UseRrc;                    // Use RRC rather than generic low pass
        public float RrcWidthSym;             // Width of RRC filter in symbols
        public float RrcRolloff;              // Rolloff factor (0 to 1)

        // For FM demodulator (profile B)
        public float PrevPhase;               // Previous phase for rate calculation
        public float NormalizeRpsam;          // Normalize to -1 to +1 for expected tones
    }

    /// <summary>
    /// Demodulator state structure
    /// </summary>
    public class DemodulatorState
    {
        public const long TicksPerPllCycle = 256L * 256L * 256L * 256L; // 2^32

        // Configuration (set during initialization)
        public char Profile;                  // 'A', 'B', etc.
        public int PllStepPerSample;          // PLL advance per audio sample

        // Prefilter (bandpass before demodulation)
        public int UsePrefilter;              // True to enable
        public float PrefilterBaud;           // Cutoff as fraction of baud beyond tones
        public float PreFilterLenSym;         // Length in symbol times
        public BpWindowType PreWindow;        // Window type
        public int PreFilterTaps;             // Number of filter taps
        public float[] PreFilter = new float[Dsp.MaxFilterSize];
        public float[] RawCb = new float[Dsp.MaxFilterSize]; // Audio input circular buffer

        // Low pass filter
        public float LpfBaud;                 // Cutoff as fraction of baud rate
        public float LpFilterWidthSym;        // Length in symbol times
        public BpWindowType LpWindow;         // Window type
        public int LpFilterTaps;              // Number of filter taps
        public float[] LpFilter = new float[Dsp.MaxFilterSize];

        // AGC (Automatic Gain Control)
        public float AgcFastAttack;
        public float AgcSlowDecay;
        public float QuickAttack;             // For signal level reporting
        public float SluggishDecay;

        // PLL inertia
        public float PllLockedInertia;        // When locked on signal
        public float PllSearchingInertia;     // When searching for signal

        // Peak/valley tracking for AGC
        public float MPeak, SPeak;
        public float MValley, SValley;

        // Audio level measurements
        public float AlevelRecPeak;
        public float AlevelRecValley;
        public float AlevelMarkPeak;
        public float AlevelSpacePeak;

        // Slicers (multiple detection thresholds)
        public int NumSlicers;                // Number of slicers in use
        public SlicerState[] Slicer = new SlicerState[AudioConfig.MaxSlicers];

        // AFSK-specific state
        public AfskState Afsk = new AfskState();

        public DemodulatorState()
        {
            for (int i = 0; i < AudioConfig.MaxSlicers; i++)
            {
                Slicer[i] = new SlicerState();
            }
        }
    }

    /// <summary>
    /// AFSK Demodulator
    /// </summary>
    public class DemodAfsk
    {
        private const float MinG = 0.5f;
        private const float MaxG = 4.0f;
        private const int DcdThreshOn = 30;   // Hysteresis for DCD detect
        private const int DcdThreshOff = 6;
        private const int DcdGoodWidth = 512;

        private static float[] _fcos256Table = new float[256];
        private static float[] _spaceGain = new float[AudioConfig.MaxSlicers];
        private static bool _tablesInitialized = false;

        private IHdlcReceiver _hdlcRec;

        public DemodAfsk(IHdlcReceiver hdlcRec)
        {
            _hdlcRec = hdlcRec;
        }

        /// <summary>
        /// Initialize lookup tables (called once)
        /// </summary>
        private static void InitTables()
        {
            if (_tablesInitialized)
                return;

            // Cosine table indexed by unsigned byte
            for (int j = 0; j < 256; j++)
            {
                _fcos256Table[j] = (float)Math.Cos(j * 2.0 * Math.PI / 256.0);
            }

            // Space gain table for multiple slicers
            _spaceGain[0] = MinG;
            float step = (float)Math.Pow(10.0, Math.Log10(MaxG / MinG) / (AudioConfig.MaxSlicers - 1));
            for (int j = 1; j < AudioConfig.MaxSlicers; j++)
            {
                _spaceGain[j] = _spaceGain[j - 1] * step;
            }

            _tablesInitialized = true;
        }

        /// <summary>
        /// Fast cosine approximation using lookup table
        /// </summary>
        private static float Fcos256(uint x)
        {
            return _fcos256Table[(x >> 24) & 0xff];
        }

        /// <summary>
        /// Fast sine approximation using lookup table
        /// </summary>
        private static float Fsin256(uint x)
        {
            return _fcos256Table[((x >> 24) - 64) & 0xff];
        }

        /// <summary>
        /// Quick approximation to sqrt(x*x + y*y)
        /// </summary>
        private static float FastHypot(float x, float y)
        {
            return (float)Math.Sqrt(x * x + y * y);
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
        private static float Convolve(float[] data, float[] filter, int filterTaps)
        {
            float sum = 0.0f;
            for (int j = 0; j < filterTaps; j++)
            {
                sum += filter[j] * data[j];
            }
            return sum;
        }

        /// <summary>
        /// Automatic Gain Control
        /// Result settles to 1 unit peak to peak (i.e. -0.5 to +0.5)
        /// </summary>
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

            // Clip to envelope
            float x = input;
            if (x > peak) x = peak;
            if (x < valley) x = valley;

            if (peak > valley)
            {
                return (x - 0.5f * (peak + valley)) / (peak - valley);
            }
            return 0.0f;
        }

        /// <summary>
        /// Initialize AFSK demodulator
        /// </summary>
        public void Init(int samplesPerSec, int baud, int markFreq, int spaceFreq, 
            char profile, DemodulatorState D)
        {
            InitTables();

            D.Profile = profile;
            D.NumSlicers = 1;

            switch (D.Profile)
            {
                case 'A':
                case 'E': // For compatibility during transition
                    D.Profile = 'A';
                    InitProfileA(samplesPerSec, baud, markFreq, spaceFreq, D);
                    break;

                case 'B':
                case 'D': // Backward compatibility
                    D.Profile = 'B';
                    InitProfileB(samplesPerSec, baud, markFreq, spaceFreq, D);
                    break;

                default:
                    throw new ArgumentException($"Invalid AFSK demodulator profile = {profile}");
            }

            // Calculate PLL timing constants
            if (baud == 521) // EAS special case
            {
                D.PllStepPerSample = (int)Math.Round(
                    (DemodulatorState.TicksPerPllCycle * 520.83) / samplesPerSec);
            }
            else
            {
                D.PllStepPerSample = (int)Math.Round(
                    (DemodulatorState.TicksPerPllCycle * (double)baud) / samplesPerSec);
            }

            // Generate prefilter if enabled
            if (D.UsePrefilter != 0)
            {
                D.PreFilterTaps = (int)(D.PreFilterLenSym * samplesPerSec / baud) | 1; // odd

                if (D.PreFilterTaps > Dsp.MaxFilterSize)
                {
                    Console.WriteLine($"Warning: Calculated pre filter size of {D.PreFilterTaps} is too large.");
                    D.PreFilterTaps = (Dsp.MaxFilterSize - 1) | 1;
                }

                float f1 = Math.Min(markFreq, spaceFreq) - D.PrefilterBaud * baud;
                float f2 = Math.Max(markFreq, spaceFreq) + D.PrefilterBaud * baud;
                f1 = f1 / samplesPerSec;
                f2 = f2 / samplesPerSec;

                Dsp.GenBandpass(f1, f2, D.PreFilter, D.PreFilterTaps, D.PreWindow);
            }

            // Generate lowpass filter
            if (D.Afsk.UseRrc != 0)
            {
                Debug.Assert(D.Afsk.RrcWidthSym >= 1 && D.Afsk.RrcWidthSym <= 16);
                Debug.Assert(D.Afsk.RrcRolloff >= 0.0f && D.Afsk.RrcRolloff <= 1.0f);

                D.LpFilterTaps = (int)(D.Afsk.RrcWidthSym * samplesPerSec / baud) | 1; // odd

                if (D.LpFilterTaps > Dsp.MaxFilterSize)
                {
                    Console.WriteLine($"Calculated RRC low pass filter size of {D.LpFilterTaps} is too large.");
                    D.LpFilterTaps = (Dsp.MaxFilterSize - 1) | 1;
                }

                Debug.Assert(D.LpFilterTaps > 8 && D.LpFilterTaps <= Dsp.MaxFilterSize);
                Dsp.GenRrcLowpass(D.LpFilter, D.LpFilterTaps, D.Afsk.RrcRolloff, 
                    (float)samplesPerSec / baud);
            }
            else
            {
                D.LpFilterTaps = (int)Math.Round(D.LpFilterWidthSym * samplesPerSec / baud);

                if (D.LpFilterTaps > Dsp.MaxFilterSize)
                {
                    Console.WriteLine($"Calculated FIR low pass filter size of {D.LpFilterTaps} is too large.");
                    D.LpFilterTaps = (Dsp.MaxFilterSize - 1) | 1;
                }

                Debug.Assert(D.LpFilterTaps > 8 && D.LpFilterTaps <= Dsp.MaxFilterSize);

                float fc = baud * D.LpfBaud / samplesPerSec;
                Dsp.GenLowpass(fc, D.LpFilter, D.LpFilterTaps, D.LpWindow);
            }
        }

        /// <summary>
        /// Initialize Profile A demodulator (dual tone comparison)
        /// </summary>
        private void InitProfileA(int samplesPerSec, int baud, int markFreq, int spaceFreq, 
            DemodulatorState D)
        {
            D.UsePrefilter = 1;

            if (baud > 600)
            {
                D.PrefilterBaud = 0.155f;
                D.PreFilterLenSym = 383 * 1200f / 44100f; // about 8 symbols
                D.PreWindow = BpWindowType.Truncated;
            }
            else
            {
                D.PrefilterBaud = 0.87f;
                D.PreFilterLenSym = 1.857f;
                D.PreWindow = BpWindowType.Cosine;
            }

            // Local oscillators for Mark and Space tones
            D.Afsk.MOscPhase = 0;
            D.Afsk.MOscDelta = (uint)Math.Round(Math.Pow(2.0, 32) * markFreq / samplesPerSec);

            D.Afsk.SOscPhase = 0;
            D.Afsk.SOscDelta = (uint)Math.Round(Math.Pow(2.0, 32) * spaceFreq / samplesPerSec);

            D.Afsk.UseRrc = 1;

            if (D.Afsk.UseRrc != 0)
            {
                D.Afsk.RrcWidthSym = 2.80f;
                D.Afsk.RrcRolloff = 0.20f;
            }
            else
            {
                D.LpfBaud = 0.14f;
                D.LpFilterWidthSym = 1.388f;
                D.LpWindow = BpWindowType.Truncated;
            }

            D.AgcFastAttack = 0.70f;
            D.AgcSlowDecay = 0.000090f;

            D.PllLockedInertia = 0.74f;
            D.PllSearchingInertia = 0.50f;

            D.QuickAttack = D.AgcFastAttack;
            D.SluggishDecay = D.AgcSlowDecay;
        }

        /// <summary>
        /// Initialize Profile B demodulator (FM discriminator)
        /// </summary>
        private void InitProfileB(int samplesPerSec, int baud, int markFreq, int spaceFreq, 
            DemodulatorState D)
        {
            D.UsePrefilter = 1;

            if (baud > 600)
            {
                D.PrefilterBaud = 0.19f;
                D.PreFilterLenSym = 8.163f;
                D.PreWindow = BpWindowType.Truncated;
            }
            else
            {
                D.PrefilterBaud = 0.87f;
                D.PreFilterLenSym = 1.857f;
                D.PreWindow = BpWindowType.Cosine;
            }

            // Local oscillator for Center frequency
            D.Afsk.COscPhase = 0;
            D.Afsk.COscDelta = (uint)Math.Round(
                Math.Pow(2.0, 32) * 0.5 * (markFreq + spaceFreq) / samplesPerSec);

            D.Afsk.UseRrc = 1;

            if (D.Afsk.UseRrc != 0)
            {
                D.Afsk.RrcWidthSym = 2.00f;
                D.Afsk.RrcRolloff = 0.40f;
            }
            else
            {
                D.LpfBaud = 0.5f;
                D.LpFilterWidthSym = 1.714286f;
                D.LpWindow = BpWindowType.Truncated;
            }

            // For scaling phase shift into normalized -1 to +1 range
            D.Afsk.NormalizeRpsam = (float)(1.0 / (0.5 * Math.Abs(markFreq - spaceFreq) * 
                2 * Math.PI / samplesPerSec));

            D.AgcFastAttack = 0.70f;
            D.AgcSlowDecay = 0.000090f;

            D.PllLockedInertia = 0.74f;
            D.PllSearchingInertia = 0.50f;

            D.QuickAttack = D.AgcFastAttack;
            D.SluggishDecay = D.AgcSlowDecay;

            // Disable received signal display for profile B
            D.AlevelMarkPeak = -1;
            D.AlevelSpacePeak = -1;
        }

        /// <summary>
        /// Process one audio sample through the AFSK demodulator
        /// </summary>
        public void ProcessSample(int chan, int subchan, int sam, DemodulatorState D)
        {
            Debug.Assert(chan >= 0 && chan < AudioConfig.MaxRadioChannels);
            Debug.Assert(subchan >= 0 && subchan < AudioConfig.MaxSlicers);

            // Scale to normalized float
            float fsam = sam / 16384.0f;

            switch (D.Profile)
            {
                case 'A':
                case 'E':
                    ProcessSampleProfileA(chan, subchan, fsam, D);
                    break;

                case 'B':
                case 'D':
                    ProcessSampleProfileB(chan, subchan, fsam, D);
                    break;
            }
        }

        /// <summary>
        /// Process sample using Profile A (dual tone amplitude comparison)
        /// </summary>
        private void ProcessSampleProfileA(int chan, int subchan, float fsam, DemodulatorState D)
        {
            // Apply prefilter if enabled
            if (D.UsePrefilter != 0)
            {
                PushSample(fsam, D.RawCb, D.PreFilterTaps);
                fsam = Convolve(D.RawCb, D.PreFilter, D.PreFilterTaps);
            }

            // Mix with Mark local oscillator
            PushSample(fsam * Fcos256(D.Afsk.MOscPhase), D.Afsk.MIRaw, D.LpFilterTaps);
            PushSample(fsam * Fsin256(D.Afsk.MOscPhase), D.Afsk.MQRaw, D.LpFilterTaps);
            D.Afsk.MOscPhase += D.Afsk.MOscDelta;

            // Mix with Space local oscillator
            PushSample(fsam * Fcos256(D.Afsk.SOscPhase), D.Afsk.SIRaw, D.LpFilterTaps);
            PushSample(fsam * Fsin256(D.Afsk.SOscPhase), D.Afsk.SQRaw, D.LpFilterTaps);
            D.Afsk.SOscPhase += D.Afsk.SOscDelta;

            // Apply lowpass filters and calculate amplitudes
            float mI = Convolve(D.Afsk.MIRaw, D.LpFilter, D.LpFilterTaps);
            float mQ = Convolve(D.Afsk.MQRaw, D.LpFilter, D.LpFilterTaps);
            float mAmp = FastHypot(mI, mQ);

            float sI = Convolve(D.Afsk.SIRaw, D.LpFilter, D.LpFilterTaps);
            float sQ = Convolve(D.Afsk.SQRaw, D.LpFilter, D.LpFilterTaps);
            float sAmp = FastHypot(sI, sQ);

            // Capture mark and space peak amplitudes for display
            if (mAmp >= D.AlevelMarkPeak)
            {
                D.AlevelMarkPeak = mAmp * D.QuickAttack + D.AlevelMarkPeak * (1.0f - D.QuickAttack);
            }
            else
            {
                D.AlevelMarkPeak = mAmp * D.SluggishDecay + D.AlevelMarkPeak * (1.0f - D.SluggishDecay);
            }

            if (sAmp >= D.AlevelSpacePeak)
            {
                D.AlevelSpacePeak = sAmp * D.QuickAttack + D.AlevelSpacePeak * (1.0f - D.QuickAttack);
            }
            else
            {
                D.AlevelSpacePeak = sAmp * D.SluggishDecay + D.AlevelSpacePeak * (1.0f - D.SluggishDecay);
            }

            if (D.NumSlicers <= 1)
            {
                // Single slicer with AGC
                float mNorm = Agc(mAmp, D.AgcFastAttack, D.AgcSlowDecay, ref D.MPeak, ref D.MValley);
                float sNorm = Agc(sAmp, D.AgcFastAttack, D.AgcSlowDecay, ref D.SPeak, ref D.SValley);

                float demodOut = mNorm - sNorm;
                                
                NudgePll(chan, subchan, 0, demodOut, D, 1.0f);
            }
            else
            {
                // Multiple slicers
                Agc(mAmp, D.AgcFastAttack, D.AgcSlowDecay, ref D.MPeak, ref D.MValley);
                Agc(sAmp, D.AgcFastAttack, D.AgcSlowDecay, ref D.SPeak, ref D.SValley);

                for (int slice = 0; slice < D.NumSlicers; slice++)
                {
                    float demodOut = mAmp - sAmp * _spaceGain[slice];
                    float amp = 0.5f * (D.MPeak - D.MValley + (D.SPeak - D.SValley) * _spaceGain[slice]);
                    if (amp < 0.0000001f) amp = 1; // avoid divide by zero

                    NudgePll(chan, subchan, slice, demodOut, D, amp);
                }
            }
        }

        /// <summary>
        /// Process sample using Profile B (FM discriminator)
        /// </summary>
        private void ProcessSampleProfileB(int chan, int subchan, float fsam, DemodulatorState D)
        {
            // Apply prefilter if enabled
            if (D.UsePrefilter != 0)
            {
                PushSample(fsam, D.RawCb, D.PreFilterTaps);
                fsam = Convolve(D.RawCb, D.PreFilter, D.PreFilterTaps);
            }

            // Mix with Center frequency local oscillator
            PushSample(fsam * Fcos256(D.Afsk.COscPhase), D.Afsk.CIRaw, D.LpFilterTaps);
            PushSample(fsam * Fsin256(D.Afsk.COscPhase), D.Afsk.CQRaw, D.LpFilterTaps);
            D.Afsk.COscPhase += D.Afsk.COscDelta;

            float cI = Convolve(D.Afsk.CIRaw, D.LpFilter, D.LpFilterTaps);
            float cQ = Convolve(D.Afsk.CQRaw, D.LpFilter, D.LpFilterTaps);

            float phase = (float)Math.Atan2(cQ, cI);
            float rate = phase - D.Afsk.PrevPhase;
            if (rate > Math.PI) rate -= 2 * (float)Math.PI;
            else if (rate < -Math.PI) rate += 2 * (float)Math.PI;
            D.Afsk.PrevPhase = phase;

            // Scale rate into -1 to +1 for expected tones
            float normRate = rate * D.Afsk.NormalizeRpsam;

            if (D.NumSlicers <= 1)
            {
                float demodOut = normRate;
                NudgePll(chan, subchan, 0, demodOut, D, 1.0f);
            }
            else
            {
                // Multiple slicers with frequency offsets
                for (int slice = 0; slice < D.NumSlicers; slice++)
                {
                    float offset = -0.5f + slice * (1.0f / (D.NumSlicers - 1));
                    float demodOut = normRate + offset;
                    NudgePll(chan, subchan, slice, demodOut, D, 1.0f);
                }
            }
        }

        private int _bitCounter = 0; // Track number of bits detected

        /// <summary>
        /// Digital Phase Locked Loop for symbol timing recovery
        /// </summary>
        private void NudgePll(int chan, int subchan, int slice, float demodOut, 
            DemodulatorState D, float amplitude)
        {
            var S = D.Slicer[slice];

            S.PrevDClockPll = S.DataClockPll;

            // Perform add as unsigned to avoid signed overflow
            S.DataClockPll = (int)((uint)S.DataClockPll + (uint)D.PllStepPerSample);

            // Check for overflow (zero crossing) - this is where we sample
            if (S.DataClockPll < 0 && S.PrevDClockPll > 0)
            {
                // Sample the data
                int quality = (int)(Math.Abs(demodOut) * 100.0f / amplitude);
                if (quality > 100) quality = 100;

                int bitValue = demodOut > 0 ? 1 : 0;
                
                // DEBUG: Log every bit detected
                _bitCounter++;
                //Console.WriteLine($"[PLL] Bit #{_bitCounter}: value={bitValue}, demodOut={demodOut:F6}, quality={quality}, DCD={S.DataDetect}");

                // Pass bit to HDLC decoder
                _hdlcRec.RecBit(chan, subchan, slice, bitValue, false, quality);

                // DCD detection
                PllDcdEachSymbol(D, chan, subchan, slice);
            }

            // Transitions nudge the DPLL phase toward the incoming signal
            int demodData = demodOut > 0 ? 1 : 0;
            if (demodData != S.PrevDemodData)
            {
                PllDcdSignalTransition(D, slice, S.DataClockPll);

                // Adjust PLL phase
                if (S.DataDetect != 0)
                {
                    S.DataClockPll = (int)(S.DataClockPll * D.PllLockedInertia);
                }
                else
                {
                    S.DataClockPll = (int)(S.DataClockPll * D.PllSearchingInertia);
                }
            }

            // Remember demodulator output for next time
            S.PrevDemodData = demodData;
        }

        /// <summary>
        /// Check if transition occurred at good or bad time
        /// </summary>
        private void PllDcdSignalTransition(DemodulatorState D, int slice, int dpllPhase)
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
        private void PllDcdEachSymbol(DemodulatorState D, int chan, int subchan, int slice)
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
                    //Console.WriteLine($"[DCD] *** DATA CARRIER DETECTED *** (chan={chan}, subchan={subchan}, score={score})");
                    _hdlcRec.DcdChange(chan, subchan, slice, true);
                }
            }
            else if (score <= DcdThreshOff)
            {
                if (S.DataDetect != 0)
                {
                    S.DataDetect = 0;
                    //Console.WriteLine($"[DCD] *** DATA CARRIER LOST *** (chan={chan}, subchan={subchan}, score={score})");
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
