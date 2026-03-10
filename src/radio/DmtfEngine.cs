/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;

namespace HTCommander.radio
{
    public static class DmtfEngine
    {
        private const int SampleRate = 32000;
        private const int Amplitude = 63; // Half of 127 so two tones summed stay within 8-bit range

        // DTMF frequency pairs (row frequency, column frequency)
        private static readonly Dictionary<char, (int Low, int High)> DtmfFrequencies =
            new Dictionary<char, (int, int)>
        {
            ['1'] = (697, 1209),
            ['2'] = (697, 1336),
            ['3'] = (697, 1477),
            ['4'] = (770, 1209),
            ['5'] = (770, 1336),
            ['6'] = (770, 1477),
            ['7'] = (852, 1209),
            ['8'] = (852, 1336),
            ['9'] = (852, 1477),
            ['*'] = (941, 1209),
            ['0'] = (941, 1336),
            ['#'] = (941, 1477),
        };

        /// <summary>
        /// Generates 8-bit unsigned PCM audio (32000 Hz, mono) for a DTMF digit string.
        /// Valid characters: 0–9, *, #. Unknown characters are silently skipped.
        /// </summary>
        /// <param name="digits">String of DTMF characters to encode.</param>
        /// <param name="toneDurationMs">Duration of each tone in milliseconds (default 80 ms).</param>
        /// <param name="gapDurationMs">Silent gap between tones in milliseconds (default 80 ms).</param>
        /// <returns>Raw 8-bit unsigned PCM bytes at 32000 Hz mono.</returns>
        public static byte[] GenerateDmtfPcm(string digits, int toneDurationMs = 150, int gapDurationMs = 80)
        {
            int toneSamples = (int)(SampleRate * toneDurationMs / 1000.0);
            int gapSamples  = (int)(SampleRate * gapDurationMs  / 1000.0);

            byte[] gap = GenerateSilence(gapSamples);

            MemoryStream stream = new MemoryStream();
            bool firstDigit = true;

            foreach (char ch in digits)
            {
                if (!DtmfFrequencies.TryGetValue(ch, out (int Low, int High) freq))
                    continue;

                // Insert inter-digit gap before every digit except the first
                if (!firstDigit)
                    stream.Write(gap, 0, gap.Length);
                firstDigit = false;

                byte[] tone = GenerateDualTone(freq.Low, freq.High, toneSamples);
                stream.Write(tone, 0, tone.Length);
            }

            return stream.ToArray();
        }

        private static byte[] GenerateDualTone(int lowFreq, int highFreq, int sampleCount)
        {
            byte[] buffer = new byte[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                double t = (double)i / SampleRate;
                double low  = Math.Sin(2 * Math.PI * lowFreq  * t);
                double high = Math.Sin(2 * Math.PI * highFreq * t);
                // Mix two tones and scale to 8-bit unsigned PCM centered at 128
                buffer[i] = (byte)(128 + (low + high) * Amplitude);
            }
            return buffer;
        }

        private static byte[] GenerateSilence(int sampleCount)
        {
            return Enumerable.Repeat((byte)128, sampleCount).ToArray();
        }
    }
}