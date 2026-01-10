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
// Dsp.cs - Digital Signal Processing functions for filter generation
//

using System;

namespace HamLib
{
    /// <summary>
    /// Window types for filter shaping
    /// </summary>
    public enum BpWindowType
    {
        Truncated,
        Cosine,
        Hamming,
        Blackman,
        Flattop
    }

    /// <summary>
    /// Digital Signal Processing functions for generating filters used by demodulators
    /// </summary>
    public static class Dsp
    {
        public const int MaxFilterSize = 480; // Maximum number of filter taps

        /// <summary>
        /// Filter window shape functions
        /// </summary>
        /// <param name="type">Window type (Hamming, Blackman, etc.)</param>
        /// <param name="size">Number of filter taps</param>
        /// <param name="j">Index in range of 0 to size-1</param>
        /// <returns>Multiplier for the window shape</returns>
        public static float Window(BpWindowType type, int size, int j)
        {
            float center = 0.5f * (size - 1);
            float w;

            switch (type)
            {
                case BpWindowType.Cosine:
                    w = (float)Math.Cos((j - center) / size * Math.PI);
                    break;

                case BpWindowType.Hamming:
                    w = (float)(0.53836 - 0.46164 * Math.Cos((j * 2 * Math.PI) / (size - 1)));
                    break;

                case BpWindowType.Blackman:
                    w = (float)(0.42659 - 0.49656 * Math.Cos((j * 2 * Math.PI) / (size - 1))
                               + 0.076849 * Math.Cos((j * 4 * Math.PI) / (size - 1)));
                    break;

                case BpWindowType.Flattop:
                    w = (float)(1.0 - 1.93 * Math.Cos((j * 2 * Math.PI) / (size - 1))
                               + 1.29 * Math.Cos((j * 4 * Math.PI) / (size - 1))
                               - 0.388 * Math.Cos((j * 6 * Math.PI) / (size - 1))
                               + 0.028 * Math.Cos((j * 8 * Math.PI) / (size - 1)));
                    break;

                case BpWindowType.Truncated:
                default:
                    w = 1.0f;
                    break;
            }

            return w;
        }

        /// <summary>
        /// Generate low pass filter kernel
        /// </summary>
        /// <param name="fc">Cutoff frequency as fraction of sampling frequency</param>
        /// <param name="lpFilter">Output filter array</param>
        /// <param name="filterSize">Number of filter taps</param>
        /// <param name="wtype">Window type (Hamming, etc.)</param>
        public static void GenLowpass(float fc, float[] lpFilter, int filterSize, BpWindowType wtype)
        {
            if (filterSize < 3 || filterSize > MaxFilterSize)
            {
                throw new ArgumentException($"Filter size must be between 3 and {MaxFilterSize}");
            }

            if (lpFilter.Length < filterSize)
            {
                throw new ArgumentException($"Filter array must have at least {filterSize} elements");
            }

            float center = 0.5f * (filterSize - 1);

            // Generate filter coefficients
            for (int j = 0; j < filterSize; j++)
            {
                float sinc;

                if (j - center == 0)
                {
                    sinc = 2 * fc;
                }
                else
                {
                    sinc = (float)(Math.Sin(2 * Math.PI * fc * (j - center)) / (Math.PI * (j - center)));
                }

                float shape = Window(wtype, filterSize, j);
                lpFilter[j] = sinc * shape;
            }

            // Normalize lowpass for unity gain at DC
            float G = 0;
            for (int j = 0; j < filterSize; j++)
            {
                G += lpFilter[j];
            }

            for (int j = 0; j < filterSize; j++)
            {
                lpFilter[j] = lpFilter[j] / G;
            }
        }

        /// <summary>
        /// Generate band pass filter kernel for the prefilter
        /// This is NOT for the mark/space filters
        /// </summary>
        /// <param name="f1">Lower cutoff frequency as fraction of sampling frequency</param>
        /// <param name="f2">Upper cutoff frequency as fraction of sampling frequency</param>
        /// <param name="bpFilter">Output filter array</param>
        /// <param name="filterSize">Number of filter taps</param>
        /// <param name="wtype">Window type (Hamming, etc.)</param>
        public static void GenBandpass(float f1, float f2, float[] bpFilter, int filterSize, BpWindowType wtype)
        {
            if (filterSize < 3 || filterSize > MaxFilterSize)
            {
                throw new ArgumentException($"Filter size must be between 3 and {MaxFilterSize}");
            }

            if (bpFilter.Length < filterSize)
            {
                throw new ArgumentException($"Filter array must have at least {filterSize} elements");
            }

            float center = 0.5f * (filterSize - 1);

            // Generate filter coefficients
            for (int j = 0; j < filterSize; j++)
            {
                float sinc;

                if (j - center == 0)
                {
                    sinc = 2 * (f2 - f1);
                }
                else
                {
                    sinc = (float)(Math.Sin(2 * Math.PI * f2 * (j - center)) / (Math.PI * (j - center))
                                  - Math.Sin(2 * Math.PI * f1 * (j - center)) / (Math.PI * (j - center)));
                }

                float shape = Window(wtype, filterSize, j);
                bpFilter[j] = sinc * shape;
            }

            // Normalize bandpass for unity gain in middle of passband
            // Compute gain in middle of passband
            float w = (float)(2 * Math.PI * (f1 + f2) / 2);
            float G = 0;
            for (int j = 0; j < filterSize; j++)
            {
                G += (float)(2 * bpFilter[j] * Math.Cos((j - center) * w));
            }

            for (int j = 0; j < filterSize; j++)
            {
                bpFilter[j] = bpFilter[j] / G;
            }
        }

        /// <summary>
        /// Generate mark and space filters
        /// </summary>
        /// <param name="fc">Tone frequency (mark or space)</param>
        /// <param name="sps">Samples per second</param>
        /// <param name="sinTable">Output sine table</param>
        /// <param name="cosTable">Output cosine table</param>
        /// <param name="filterSize">Number of filter taps</param>
        /// <param name="wtype">Window type</param>
        public static void GenMs(int fc, int sps, float[] sinTable, float[] cosTable, int filterSize, BpWindowType wtype)
        {
            if (filterSize < 3 || filterSize > MaxFilterSize)
            {
                throw new ArgumentException($"Filter size must be between 3 and {MaxFilterSize}");
            }

            if (sinTable.Length < filterSize || cosTable.Length < filterSize)
            {
                throw new ArgumentException($"Filter arrays must have at least {filterSize} elements");
            }

            float Gs = 0, Gc = 0;

            for (int j = 0; j < filterSize; j++)
            {
                float center = 0.5f * (filterSize - 1);
                float am = ((float)(j - center) / (float)sps) * ((float)fc) * (2.0f * (float)Math.PI);

                float shape = Window(wtype, filterSize, j);

                sinTable[j] = (float)Math.Sin(am) * shape;
                cosTable[j] = (float)Math.Cos(am) * shape;

                Gs += sinTable[j] * (float)Math.Sin(am);
                Gc += cosTable[j] * (float)Math.Cos(am);
            }

            // Normalize for unity gain
            for (int j = 0; j < filterSize; j++)
            {
                sinTable[j] = sinTable[j] / Gs;
                cosTable[j] = cosTable[j] / Gc;
            }
        }

        /// <summary>
        /// Root Raised Cosine function
        /// Why do they call it that? It's mostly the sinc function with cos windowing to taper off edges faster.
        /// </summary>
        /// <param name="t">Time in units of symbol duration (centers of two adjacent symbols differ by 1)</param>
        /// <param name="a">Roll off factor, between 0 and 1</param>
        /// <returns>Basically the sinc (sin(x)/x) function with edges decreasing faster.
        /// Should be 1 for t = 0 and 0 at all other integer values of t.</returns>
        public static float Rrc(float t, float a)
        {
            float sinc, window, result;

            // Calculate sinc function
            if (t > -0.001f && t < 0.001f)
            {
                sinc = 1;
            }
            else
            {
                sinc = (float)(Math.Sin(Math.PI * t) / (Math.PI * t));
            }

            // Calculate window function
            if (Math.Abs(a * t) > 0.499f && Math.Abs(a * t) < 0.501f)
            {
                window = (float)(Math.PI / 4);
            }
            else
            {
                window = (float)(Math.Cos(Math.PI * a * t) / (1 - Math.Pow(2 * a * t, 2)));
                // This made nicer looking waveforms for generating signal.
                // window = (float)Math.Cos(Math.PI * a * t);
                // Do we want to let it go negative?
                // I think this would happen when a > 0.5 / (filter width in symbol times)
                if (window < 0)
                {
                    // Note: Original C code has comments about this
                    // window = 0;
                }
            }

            result = sinc * window;

            return result;
        }

        /// <summary>
        /// Generate Root Raised Cosine low pass filter
        /// The Root Raised Cosine (RRC) low pass filter is supposed to minimize Intersymbol Interference (ISI)
        /// </summary>
        /// <param name="pfilter">Output filter array</param>
        /// <param name="filterTaps">Number of filter taps</param>
        /// <param name="rolloff">Rolloff factor (between 0 and 1)</param>
        /// <param name="samplesPerSymbol">Samples per symbol</param>
        public static void GenRrcLowpass(float[] pfilter, int filterTaps, float rolloff, float samplesPerSymbol)
        {
            if (filterTaps < 3 || filterTaps > MaxFilterSize)
            {
                throw new ArgumentException($"Filter taps must be between 3 and {MaxFilterSize}");
            }

            if (pfilter.Length < filterTaps)
            {
                throw new ArgumentException($"Filter array must have at least {filterTaps} elements");
            }

            // Generate filter coefficients
            for (int k = 0; k < filterTaps; k++)
            {
                float t = (k - ((filterTaps - 1.0f) / 2.0f)) / samplesPerSymbol;
                pfilter[k] = Rrc(t, rolloff);
            }

            // Scale it for unity gain
            float sum = 0;
            for (int k = 0; k < filterTaps; k++)
            {
                sum += pfilter[k];
            }

            for (int k = 0; k < filterTaps; k++)
            {
                pfilter[k] = pfilter[k] / sum;
            }
        }
    }
}
