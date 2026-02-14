/*
SSTV Encoder

Generates audio samples for SSTV transmission.
Supports all modes present in the decoder.

Based on the SSTV protocol specifications
used by the decoder classes.
*/

using System;
using System.Collections.Generic;

namespace HTCommander.SSTV
{
    /// <summary>
    /// Encodes pixel data into SSTV audio samples using frequency modulation.
    /// Supports Robot 36, Robot 72, Martin 1/2, Scottie 1/2/DX,
    /// Wraase SC2-180, PD 50/90/120/160/180/240/290, and HF Fax modes.
    /// </summary>
    public class Encoder
    {
        private readonly int sampleRate;
        private double phase;

        // SSTV standard frequencies
        public const double SyncPulseFrequency = 1200.0;
        public const double SyncPorchFrequency = 1500.0;
        public const double BlackFrequency = 1500.0;
        public const double WhiteFrequency = 2300.0;
        public const double LeaderToneFrequency = 1900.0;
        public const double VisBitOneFrequency = 1100.0;
        public const double VisBitZeroFrequency = 1300.0;

        public Encoder(int sampleRate)
        {
            this.sampleRate = sampleRate;
            phase = 0;
        }

        /// <summary>
        /// Reset the oscillator phase.
        /// </summary>
        public void Reset()
        {
            phase = 0;
        }

        /// <summary>
        /// Generate a tone at the given frequency for the given duration and append samples to the list.
        /// </summary>
        private void AddTone(List<float> samples, double frequency, double durationSeconds)
        {
            int count = (int)Math.Round(durationSeconds * sampleRate);
            double delta = 2.0 * Math.PI * frequency / sampleRate;
            for (int i = 0; i < count; i++)
            {
                samples.Add((float)Math.Sin(phase));
                phase += delta;
                if (phase > 2.0 * Math.PI)
                    phase -= 2.0 * Math.PI;
            }
        }

        /// <summary>
        /// Convert a pixel luminance/color level [0..1] to SSTV frequency.
        /// </summary>
        private static double LevelToFrequency(float level)
        {
            level = Math.Clamp(level, 0f, 1f);
            return BlackFrequency + level * (WhiteFrequency - BlackFrequency);
        }

        /// <summary>
        /// Add a single sample at the given frequency.
        /// </summary>
        private void AddSample(List<float> samples, double frequency)
        {
            double delta = 2.0 * Math.PI * frequency / sampleRate;
            samples.Add((float)Math.Sin(phase));
            phase += delta;
            if (phase > 2.0 * Math.PI)
                phase -= 2.0 * Math.PI;
        }

        /// <summary>
        /// Add a scan line of pixels as frequency-modulated samples.
        /// </summary>
        private void AddPixelLine(List<float> samples, float[] levels, double durationSeconds)
        {
            int count = (int)Math.Round(durationSeconds * sampleRate);
            for (int i = 0; i < count; i++)
            {
                int pixelIndex = (i * levels.Length) / count;
                pixelIndex = Math.Min(pixelIndex, levels.Length - 1);
                double freq = LevelToFrequency(levels[pixelIndex]);
                AddSample(samples, freq);
            }
        }

        /// <summary>
        /// Generate the SSTV VIS header (leader tone + break + VIS code + sync).
        /// </summary>
        private void AddVISHeader(List<float> samples, int visCode)
        {
            // Leader tone (300ms)
            AddTone(samples, LeaderToneFrequency, 0.3);
            // Break (10ms at 1200Hz)
            AddTone(samples, SyncPulseFrequency, 0.01);
            // Leader tone (300ms)
            AddTone(samples, LeaderToneFrequency, 0.3);

            // VIS start bit (30ms at 1200Hz)
            AddTone(samples, SyncPulseFrequency, 0.03);

            // Compute even parity for bit 7 over the lower 7 data bits
            int parity = 0;
            for (int i = 0; i < 7; i++)
                parity ^= (visCode >> i) & 1;
            int visCodeWithParity = (visCode & 0x7F) | (parity << 7);

            // 8 VIS bits (7 data + 1 parity, LSB first), 30ms each
            for (int i = 0; i < 8; i++)
            {
                bool bit = (visCodeWithParity & (1 << i)) != 0;
                AddTone(samples, bit ? VisBitOneFrequency : VisBitZeroFrequency, 0.03);
            }

            // VIS stop bit (30ms at 1200Hz)
            AddTone(samples, SyncPulseFrequency, 0.03);
        }

        /// <summary>
        /// Extract RGB from a packed ARGB int.
        /// </summary>
        private static void UnpackRGB(int argb, out float r, out float g, out float b)
        {
            r = ((argb >> 16) & 0xFF) / 255f;
            g = ((argb >> 8) & 0xFF) / 255f;
            b = (argb & 0xFF) / 255f;
        }

        /// <summary>
        /// Convert RGB [0..1] to YUV [0..1] (BT.601).
        /// </summary>
        private static void RGBToYUV(float r, float g, float b, out float y, out float u, out float v)
        {
            y = 0.299f * r + 0.587f * g + 0.114f * b;
            u = -0.169f * r - 0.331f * g + 0.500f * b + 0.5f;
            v = 0.500f * r - 0.419f * g - 0.081f * b + 0.5f;
        }

        /// <summary>
        /// Encode a full image using Robot 36 Color mode.
        /// Image is expected as a flat ARGB int array, width x height.
        /// </summary>
        public float[] EncodeRobot36(int[] pixels, int width, int height)
        {
            int visCode = 8;
            double syncPulseSeconds = 0.009;
            double syncPorchSeconds = 0.003;
            double luminanceSeconds = 0.088;
            double separatorSeconds = 0.0045;
            double porchSeconds = 0.0015;
            double chrominanceSeconds = 0.044;
            int horizontalPixels = 320;
            int verticalPixels = 240;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line += 2)
            {
                float[] yEven = new float[horizontalPixels];
                float[] yOdd = new float[horizontalPixels];
                float[] uAvg = new float[horizontalPixels];
                float[] vAvg = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcXEven = (x * width) / horizontalPixels;
                    int srcYEven = (line * height) / verticalPixels;
                    int srcXOdd = srcXEven;
                    int srcYOdd = ((line + 1) * height) / verticalPixels;
                    srcYOdd = Math.Min(srcYOdd, height - 1);

                    UnpackRGB(pixels[srcYEven * width + srcXEven], out float rE, out float gE, out float bE);
                    RGBToYUV(rE, gE, bE, out float yE, out float uE, out float vE);
                    UnpackRGB(pixels[srcYOdd * width + srcXOdd], out float rO, out float gO, out float bO);
                    RGBToYUV(rO, gO, bO, out float yO, out float uO, out float vO);

                    yEven[x] = yE;
                    yOdd[x] = yO;
                    uAvg[x] = (uE + uO) / 2f;
                    vAvg[x] = (vE + vO) / 2f;
                }

                // Even line: sync + porch + Y + separator(even=1500Hz) + porch + V
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                AddTone(samples, SyncPorchFrequency, syncPorchSeconds);
                AddPixelLine(samples, yEven, luminanceSeconds);
                AddTone(samples, SyncPorchFrequency, separatorSeconds); // even separator ~1500Hz
                AddTone(samples, SyncPorchFrequency, porchSeconds);
                AddPixelLine(samples, vAvg, chrominanceSeconds);

                // Odd line: sync + porch + Y + separator(odd=2300Hz) + porch + U
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                AddTone(samples, SyncPorchFrequency, syncPorchSeconds);
                AddPixelLine(samples, yOdd, luminanceSeconds);
                AddTone(samples, WhiteFrequency, separatorSeconds); // odd separator ~2300Hz
                AddTone(samples, SyncPorchFrequency, porchSeconds);
                AddPixelLine(samples, uAvg, chrominanceSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a full image using Robot 72 Color mode.
        /// </summary>
        public float[] EncodeRobot72(int[] pixels, int width, int height)
        {
            int visCode = 12;
            double syncPulseSeconds = 0.009;
            double syncPorchSeconds = 0.003;
            double luminanceSeconds = 0.138;
            double separatorSeconds = 0.0045;
            double porchSeconds = 0.0015;
            double chrominanceSeconds = 0.069;
            int horizontalPixels = 320;
            int verticalPixels = 240;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line++)
            {
                float[] yLine = new float[horizontalPixels];
                float[] uLine = new float[horizontalPixels];
                float[] vLine = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcX = (x * width) / horizontalPixels;
                    int srcY = (line * height) / verticalPixels;
                    UnpackRGB(pixels[srcY * width + srcX], out float r, out float g, out float b);
                    RGBToYUV(r, g, b, out yLine[x], out uLine[x], out vLine[x]);
                }

                // Sync pulse
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                // Sync porch
                AddTone(samples, SyncPorchFrequency, syncPorchSeconds);
                // Y channel
                AddPixelLine(samples, yLine, luminanceSeconds);
                // Separator + porch + V channel
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                AddTone(samples, SyncPorchFrequency, porchSeconds);
                AddPixelLine(samples, vLine, chrominanceSeconds);
                // Separator + porch + U channel
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                AddTone(samples, SyncPorchFrequency, porchSeconds);
                AddPixelLine(samples, uLine, chrominanceSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a full image using a Martin mode (Martin 1 or Martin 2).
        /// </summary>
        public float[] EncodeMartin(int[] pixels, int width, int height, string variant)
        {
            int visCode;
            double channelSeconds;
            if (variant == "1")
            {
                visCode = 44;
                channelSeconds = 0.146432;
            }
            else // "2"
            {
                visCode = 40;
                channelSeconds = 0.073216;
            }

            double syncPulseSeconds = 0.004862;
            double separatorSeconds = 0.000572;
            int horizontalPixels = 320;
            int verticalPixels = 256;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line++)
            {
                float[] red = new float[horizontalPixels];
                float[] green = new float[horizontalPixels];
                float[] blue = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcX = (x * width) / horizontalPixels;
                    int srcY = (line * height) / verticalPixels;
                    UnpackRGB(pixels[srcY * width + srcX], out red[x], out green[x], out blue[x]);
                }

                // Sync pulse
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                // Separator
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                // Green
                AddPixelLine(samples, green, channelSeconds);
                // Separator
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                // Blue
                AddPixelLine(samples, blue, channelSeconds);
                // Separator
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                // Red
                AddPixelLine(samples, red, channelSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a full image using a Scottie mode (Scottie 1, 2, or DX).
        /// </summary>
        public float[] EncodeScottie(int[] pixels, int width, int height, string variant)
        {
            int visCode;
            double channelSeconds;
            if (variant == "1")
            {
                visCode = 60;
                channelSeconds = 0.138240;
            }
            else if (variant == "2")
            {
                visCode = 56;
                channelSeconds = 0.088064;
            }
            else // "DX"
            {
                visCode = 76;
                channelSeconds = 0.3456;
            }

            double syncPulseSeconds = 0.009;
            double separatorSeconds = 0.0015;
            int horizontalPixels = 320;
            int verticalPixels = 256;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line++)
            {
                float[] red = new float[horizontalPixels];
                float[] green = new float[horizontalPixels];
                float[] blue = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcX = (x * width) / horizontalPixels;
                    int srcY = (line * height) / verticalPixels;
                    UnpackRGB(pixels[srcY * width + srcX], out red[x], out green[x], out blue[x]);
                }

                // Scottie order: separator + green + separator + blue + sync + separator + red
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                AddPixelLine(samples, green, channelSeconds);
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                AddPixelLine(samples, blue, channelSeconds);
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                AddTone(samples, SyncPorchFrequency, separatorSeconds);
                AddPixelLine(samples, red, channelSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a full image using Wraase SC2-180 mode.
        /// </summary>
        public float[] EncodeWraaseSC2_180(int[] pixels, int width, int height)
        {
            int visCode = 55;
            double syncPulseSeconds = 0.0055225;
            double syncPorchSeconds = 0.0005;
            double channelSeconds = 0.235;
            int horizontalPixels = 320;
            int verticalPixels = 256;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line++)
            {
                float[] red = new float[horizontalPixels];
                float[] green = new float[horizontalPixels];
                float[] blue = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcX = (x * width) / horizontalPixels;
                    int srcY = (line * height) / verticalPixels;
                    UnpackRGB(pixels[srcY * width + srcX], out red[x], out green[x], out blue[x]);
                }

                // Sync pulse + porch
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                AddTone(samples, SyncPorchFrequency, syncPorchSeconds);
                // Red
                AddPixelLine(samples, red, channelSeconds);
                // Green
                AddPixelLine(samples, green, channelSeconds);
                // Blue
                AddPixelLine(samples, blue, channelSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a full image using a PD (PaulDon) mode.
        /// Valid variants: "50", "90", "120", "160", "180", "240", "290"
        /// </summary>
        public float[] EncodePaulDon(int[] pixels, int width, int height, string variant)
        {
            int visCode;
            int horizontalPixels;
            int verticalPixels;
            double channelSeconds;

            switch (variant)
            {
                case "50":
                    visCode = 93; horizontalPixels = 320; verticalPixels = 256; channelSeconds = 0.09152;
                    break;
                case "90":
                    visCode = 99; horizontalPixels = 320; verticalPixels = 256; channelSeconds = 0.17024;
                    break;
                case "120":
                    visCode = 95; horizontalPixels = 640; verticalPixels = 496; channelSeconds = 0.1216;
                    break;
                case "160":
                    visCode = 98; horizontalPixels = 512; verticalPixels = 400; channelSeconds = 0.195584;
                    break;
                case "180":
                    visCode = 96; horizontalPixels = 640; verticalPixels = 496; channelSeconds = 0.18304;
                    break;
                case "240":
                    visCode = 97; horizontalPixels = 640; verticalPixels = 496; channelSeconds = 0.24448;
                    break;
                case "290":
                    visCode = 94; horizontalPixels = 800; verticalPixels = 616; channelSeconds = 0.2288;
                    break;
                default:
                    throw new ArgumentException("Unknown PD variant: " + variant);
            }

            double syncPulseSeconds = 0.02;
            double syncPorchSeconds = 0.00208;

            var samples = new List<float>();
            AddVISHeader(samples, visCode);

            for (int line = 0; line < verticalPixels; line += 2)
            {
                float[] yEven = new float[horizontalPixels];
                float[] yOdd = new float[horizontalPixels];
                float[] uAvg = new float[horizontalPixels];
                float[] vAvg = new float[horizontalPixels];

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcXEven = (x * width) / horizontalPixels;
                    int srcYEven = (line * height) / verticalPixels;
                    int srcXOdd = srcXEven;
                    int srcYOdd = ((line + 1) * height) / verticalPixels;
                    srcYOdd = Math.Min(srcYOdd, height - 1);

                    UnpackRGB(pixels[srcYEven * width + srcXEven], out float rE, out float gE, out float bE);
                    RGBToYUV(rE, gE, bE, out float yE, out float uE, out float vE);
                    UnpackRGB(pixels[srcYOdd * width + srcXOdd], out float rO, out float gO, out float bO);
                    RGBToYUV(rO, gO, bO, out float yO, out float uO, out float vO);

                    yEven[x] = yE;
                    yOdd[x] = yO;
                    uAvg[x] = (uE + uO) / 2f;
                    vAvg[x] = (vE + vO) / 2f;
                }

                // Sync pulse
                AddTone(samples, SyncPulseFrequency, syncPulseSeconds);
                // Sync porch
                AddTone(samples, SyncPorchFrequency, syncPorchSeconds);
                // Y even
                AddPixelLine(samples, yEven, channelSeconds);
                // V average
                AddPixelLine(samples, vAvg, channelSeconds);
                // U average
                AddPixelLine(samples, uAvg, channelSeconds);
                // Y odd
                AddPixelLine(samples, yOdd, channelSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Encode a grayscale image using HF Fax mode (IOC 576, 120 LPM).
        /// Pixels should be ARGB packed ints.
        /// </summary>
        public float[] EncodeHFFax(int[] pixels, int width, int height)
        {
            int horizontalPixels = 640;
            int totalLines = 1200;
            double scanLineSeconds = 0.5; // 120 LPM = 0.5s per line

            var samples = new List<float>();

            // HF Fax has no VIS header; just encode scan lines
            for (int line = 0; line < totalLines; line++)
            {
                float[] gray = new float[horizontalPixels];
                int srcY = (line * height) / totalLines;
                srcY = Math.Min(srcY, height - 1);

                for (int x = 0; x < horizontalPixels; x++)
                {
                    int srcX = (x * width) / horizontalPixels;
                    srcX = Math.Min(srcX, width - 1);
                    int argb = pixels[srcY * width + srcX];
                    float r = ((argb >> 16) & 0xFF) / 255f;
                    float g = ((argb >> 8) & 0xFF) / 255f;
                    float b = (argb & 0xFF) / 255f;
                    gray[x] = 0.299f * r + 0.587f * g + 0.114f * b;
                }

                AddPixelLine(samples, gray, scanLineSeconds);
            }

            return samples.ToArray();
        }

        /// <summary>
        /// Convenience method to encode any supported mode by name.
        /// </summary>
        public float[] Encode(int[] pixels, int width, int height, string modeName)
        {
            switch (modeName)
            {
                case "Robot 36 Color":
                    return EncodeRobot36(pixels, width, height);
                case "Robot 72 Color":
                    return EncodeRobot72(pixels, width, height);
                case "Martin 1":
                    return EncodeMartin(pixels, width, height, "1");
                case "Martin 2":
                    return EncodeMartin(pixels, width, height, "2");
                case "Scottie 1":
                    return EncodeScottie(pixels, width, height, "1");
                case "Scottie 2":
                    return EncodeScottie(pixels, width, height, "2");
                case "Scottie DX":
                    return EncodeScottie(pixels, width, height, "DX");
                case "Wraase SC2\u2013180":
                    return EncodeWraaseSC2_180(pixels, width, height);
                case "PD 50":
                    return EncodePaulDon(pixels, width, height, "50");
                case "PD 90":
                    return EncodePaulDon(pixels, width, height, "90");
                case "PD 120":
                    return EncodePaulDon(pixels, width, height, "120");
                case "PD 160":
                    return EncodePaulDon(pixels, width, height, "160");
                case "PD 180":
                    return EncodePaulDon(pixels, width, height, "180");
                case "PD 240":
                    return EncodePaulDon(pixels, width, height, "240");
                case "PD 290":
                    return EncodePaulDon(pixels, width, height, "290");
                case "HF Fax":
                    return EncodeHFFax(pixels, width, height);
                default:
                    throw new ArgumentException("Unknown mode: " + modeName);
            }
        }

        /// <summary>
        /// Get the list of all supported mode names.
        /// </summary>
        public static string[] GetSupportedModes()
        {
            return new[]
            {
                "Robot 36 Color",
                "Robot 72 Color",
                "Martin 1",
                "Martin 2",
                "Scottie 1",
                "Scottie 2",
                "Scottie DX",
                "Wraase SC2\u2013180",
                "PD 50",
                "PD 90",
                "PD 120",
                "PD 160",
                "PD 180",
                "PD 240",
                "PD 290",
                "HF Fax"
            };
        }
    }
}
