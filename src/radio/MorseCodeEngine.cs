using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace HTCommander.radio
{

    public static class MorseCodeEngine
    {
        private const int SampleRate = 32000;
        private const int Amplitude = 127; // Max for unsigned 8-bit PCM centered at 128

        // Morse code dictionary
        private static readonly Dictionary<char, string> MorseCode = new Dictionary<char, string>
        {
            ['A'] = ".-",
            ['B'] = "-...",
            ['C'] = "-.-.",
            ['D'] = "-..",
            ['E'] = ".",
            ['F'] = "..-.",
            ['G'] = "--.",
            ['H'] = "....",
            ['I'] = "..",
            ['J'] = ".---",
            ['K'] = "-.-",
            ['L'] = ".-..",
            ['M'] = "--",
            ['N'] = "-.",
            ['O'] = "---",
            ['P'] = ".--.",
            ['Q'] = "--.-",
            ['R'] = ".-.",
            ['S'] = "...",
            ['T'] = "-",
            ['U'] = "..-",
            ['V'] = "...-",
            ['W'] = ".--",
            ['X'] = "-..-",
            ['Y'] = "-.--",
            ['Z'] = "--..",
            ['0'] = "-----",
            ['1'] = ".----",
            ['2'] = "..---",
            ['3'] = "...--",
            ['4'] = "....-",
            ['5'] = ".....",
            ['6'] = "-....",
            ['7'] = "--...",
            ['8'] = "---..",
            ['9'] = "----.",
            [' '] = " " // space between words
        };

        public static byte[] GenerateMorsePcm(string text, int frequency = 500, int wpm = 8)
        {
            double unit = 1.2 / wpm; // seconds per dit (ITU standard)
            int samplesPerUnit = (int)(SampleRate * unit);

            // Tone and silence generators
            byte[] DitTone = GenerateTone(frequency, samplesPerUnit);
            byte[] DahTone = GenerateTone(frequency, samplesPerUnit * 3);
            byte[] IntraCharSpace = GenerateSilence(samplesPerUnit);        // 1 unit
            byte[] InterCharSpace = GenerateSilence(samplesPerUnit * 3);    // 3 units
            byte[] WordSpace = GenerateSilence(samplesPerUnit * 8);         // 8 units

            MemoryStream stream = new MemoryStream();

            foreach (char ch in text.ToUpperInvariant())
            {
                if (!MorseCode.TryGetValue(ch, out string code))
                    continue;

                if (code == " ")
                {
                    stream.Write(WordSpace, 0, WordSpace.Length);
                    continue;
                }

                for (int i = 0; i < code.Length; i++)
                {
                    if (code[i] == '.')
                        stream.Write(DitTone, 0, DitTone.Length);
                    else if (code[i] == '-')
                        stream.Write(DahTone, 0, DahTone.Length);

                    if (i < code.Length - 1)
                        stream.Write(IntraCharSpace, 0, IntraCharSpace.Length);
                }

                stream.Write(InterCharSpace, 0, InterCharSpace.Length);
            }

            return stream.ToArray();
        }

        private static byte[] GenerateTone(int frequency, int sampleCount)
        {
            byte[] buffer = new byte[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                double t = (double)i / SampleRate;
                double value = Math.Sin(2 * Math.PI * frequency * t);
                buffer[i] = (byte)(128 + value * Amplitude); // 8-bit unsigned PCM
            }
            return buffer;
        }

        private static byte[] GenerateSilence(int sampleCount)
        {
            return Enumerable.Repeat((byte)128, sampleCount).ToArray(); // silence centered at 128
        }
    }
}