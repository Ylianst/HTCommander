/*
HF Fax mode
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    /// <summary>
    /// HF Fax, IOC 576, 120 lines per minute
    /// </summary>
    public class HFFax : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly string name;
        private readonly int sampleRate;
        private readonly float[] cumulated;
        private int horizontalShift = 0;

        public HFFax(int sampleRate)
        {
            this.name = "HF Fax";
            lowPassFilter = new ExponentialMovingAverage();
            this.sampleRate = sampleRate;
            cumulated = new float[GetWidth()];
        }

        private static float FreqToLevel(float frequency, float offset)
        {
            return 0.5f * (frequency - offset + 1.0f);
        }

        public override string GetName() => name;
        public override int GetVISCode() => -1;
        public override int GetWidth() => 640;
        public override int GetHeight() => 1200;
        public override int GetFirstPixelSampleIndex() => 0;
        public override int GetFirstSyncPulseIndex() => -1;
        public override int GetScanLineSamples() => sampleRate / 2;
        public override void ResetState() { }

        public override int[] PostProcessScopeImage(int[] pixels, int width, int height)
        {
            // In C# we return a new pixel array that represents the post-processed image.
            // The Java version uses Android Bitmap/Canvas for rescaling.
            // Here we do the equivalent pixel manipulation.
            int realWidth = 1808;
            int realHorizontalShift = horizontalShift * realWidth / GetWidth();
            int[] result = new int[realWidth * height];

            for (int y = 0; y < height; ++y)
            {
                // Copy shifted part (from original right portion to result left)
                for (int x = 0; x < realWidth; ++x)
                {
                    // Map result x to source x
                    int srcX;
                    if (horizontalShift > 0 && x >= realWidth - realHorizontalShift)
                    {
                        // Right side of result maps to left part of source (0..horizontalShift)
                        srcX = (x - (realWidth - realHorizontalShift)) * horizontalShift / realHorizontalShift;
                    }
                    else
                    {
                        // Left side of result maps to source (horizontalShift..width)
                        int srcWidth = GetWidth() - horizontalShift;
                        int dstWidth = realWidth - realHorizontalShift;
                        srcX = horizontalShift + x * srcWidth / dstWidth;
                    }
                    srcX = Math.Min(srcX, GetWidth() - 1);
                    srcX = Math.Max(srcX, 0);
                    result[y * realWidth + x] = pixels[y * width + srcX];
                }
            }

            return result;
        }

        public override bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset)
        {
            if (syncPulseIndex < 0 || syncPulseIndex + scanLineSamples > scanLineBuffer.Length)
                return false;
            int horizontalPixels = GetWidth();
            lowPassFilter.Cutoff(horizontalPixels, 2 * scanLineSamples, 2);
            lowPassFilter.Reset();
            for (int i = 0; i < scanLineSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[i]);
            lowPassFilter.Reset();
            for (int i = scanLineSamples - 1; i >= 0; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int position = (i * scanLineSamples) / horizontalPixels;
                int color = ColorConverter.GRAY(scratchBuffer[position]);
                pixelBuffer.Pixels[i] = color;

                // Accumulate recent values, forget old
                float decay = 0.99f;
                float luminance = ((color >> 16) & 0xFF) / 255.0f; // extract R channel as luminance proxy
                cumulated[i] = cumulated[i] * decay + luminance * (1 - decay);
            }

            // Try to detect "sync": thick white margin
            int bestIndex = 0;
            float bestValue = 0;
            for (int x = 0; x < GetWidth(); ++x)
            {
                float val = cumulated[x];
                if (val > bestValue)
                {
                    bestIndex = x;
                    bestValue = val;
                }
            }

            horizontalShift = bestIndex;

            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 1;
            return true;
        }
    }
}
