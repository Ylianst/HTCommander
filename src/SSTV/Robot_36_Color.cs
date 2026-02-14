/*
Robot 36 Color
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Robot_36_Color : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly int horizontalPixels;
        private readonly int verticalPixels;
        private readonly int scanLineSamplesValue;
        private readonly int luminanceSamples;
        private readonly int separatorSamples;
        private readonly int chrominanceSamples;
        private readonly int beginSamples;
        private readonly int luminanceBeginSamples;
        private readonly int separatorBeginSamples;
        private readonly int chrominanceBeginSamples;
        private readonly int endSamples;
        private bool lastEven;

        public Robot_36_Color(int sampleRate)
        {
            horizontalPixels = 320;
            verticalPixels = 240;
            double syncPulseSeconds = 0.009;
            double syncPorchSeconds = 0.003;
            double luminanceSeconds = 0.088;
            double separatorSeconds = 0.0045;
            double porchSeconds = 0.0015;
            double chrominanceSeconds = 0.044;
            double scanLineSeconds = syncPulseSeconds + syncPorchSeconds + luminanceSeconds + separatorSeconds + porchSeconds + chrominanceSeconds;
            scanLineSamplesValue = (int)Math.Round(scanLineSeconds * sampleRate);
            luminanceSamples = (int)Math.Round(luminanceSeconds * sampleRate);
            separatorSamples = (int)Math.Round(separatorSeconds * sampleRate);
            chrominanceSamples = (int)Math.Round(chrominanceSeconds * sampleRate);
            double luminanceBeginSeconds = syncPorchSeconds;
            luminanceBeginSamples = (int)Math.Round(luminanceBeginSeconds * sampleRate);
            beginSamples = luminanceBeginSamples;
            double separatorBeginSeconds = luminanceBeginSeconds + luminanceSeconds;
            separatorBeginSamples = (int)Math.Round(separatorBeginSeconds * sampleRate);
            double separatorEndSeconds = separatorBeginSeconds + separatorSeconds;
            double chrominanceBeginSeconds = separatorEndSeconds + porchSeconds;
            chrominanceBeginSamples = (int)Math.Round(chrominanceBeginSeconds * sampleRate);
            double chrominanceEndSeconds = chrominanceBeginSeconds + chrominanceSeconds;
            endSamples = (int)Math.Round(chrominanceEndSeconds * sampleRate);
            lowPassFilter = new ExponentialMovingAverage();
        }

        private static float FreqToLevel(float frequency, float offset)
        {
            return 0.5f * (frequency - offset + 1.0f);
        }

        public override string GetName() => "Robot 36 Color";
        public override int GetVISCode() => 8;
        public override int GetWidth() => horizontalPixels;
        public override int GetHeight() => verticalPixels;
        public override int GetFirstPixelSampleIndex() => beginSamples;
        public override int GetFirstSyncPulseIndex() => 0;
        public override int GetScanLineSamples() => scanLineSamplesValue;

        public override void ResetState()
        {
            lastEven = false;
        }

        public override bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset)
        {
            if (syncPulseIndex + beginSamples < 0 || syncPulseIndex + endSamples > scanLineBuffer.Length)
                return false;
            float separator = 0;
            for (int i = 0; i < separatorSamples; ++i)
                separator += scanLineBuffer[syncPulseIndex + separatorBeginSamples + i];
            separator /= separatorSamples;
            separator -= frequencyOffset;
            bool even = separator < 0;
            if (separator < -1.1f || (separator > -0.9f && separator < 0.9f) || separator > 1.1f)
                even = !lastEven;
            lastEven = even;
            lowPassFilter.Cutoff(horizontalPixels, 2 * luminanceSamples, 2);
            lowPassFilter.Reset();
            for (int i = beginSamples; i < endSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[syncPulseIndex + i]);
            lowPassFilter.Reset();
            for (int i = endSamples - 1; i >= beginSamples; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int luminancePos = luminanceBeginSamples + (i * luminanceSamples) / horizontalPixels;
                int chrominancePos = chrominanceBeginSamples + (i * chrominanceSamples) / horizontalPixels;
                if (even)
                {
                    pixelBuffer.Pixels[i] = ColorConverter.RGB(scratchBuffer[luminancePos], 0, scratchBuffer[chrominancePos]);
                }
                else
                {
                    int evenYUV = pixelBuffer.Pixels[i];
                    int oddYUV = ColorConverter.RGB(scratchBuffer[luminancePos], scratchBuffer[chrominancePos], 0);
                    pixelBuffer.Pixels[i] =
                        ColorConverter.YUV2RGB((evenYUV & 0x00ff00ff) | (oddYUV & 0x0000ff00));
                    pixelBuffer.Pixels[i + horizontalPixels] =
                        ColorConverter.YUV2RGB((oddYUV & 0x00ffff00) | (evenYUV & 0x000000ff));
                }
            }
            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 2;
            return !even;
        }
    }
}
