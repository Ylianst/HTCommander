/*
PD modes
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class PaulDon : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly int horizontalPixels;
        private readonly int verticalPixels;
        private readonly int scanLineSamplesValue;
        private readonly int channelSamples;
        private readonly int beginSamples;
        private readonly int yEvenBeginSamples;
        private readonly int vAvgBeginSamples;
        private readonly int uAvgBeginSamples;
        private readonly int yOddBeginSamples;
        private readonly int endSamples;
        private readonly string name;
        private readonly int code;

        public PaulDon(string name, int code, int horizontalPixels, int verticalPixels, double channelSeconds, int sampleRate)
        {
            this.name = "PD " + name;
            this.code = code;
            this.horizontalPixels = horizontalPixels;
            this.verticalPixels = verticalPixels;
            double syncPulseSeconds = 0.02;
            double syncPorchSeconds = 0.00208;
            double scanLineSeconds = syncPulseSeconds + syncPorchSeconds + 4 * channelSeconds;
            scanLineSamplesValue = (int)Math.Round(scanLineSeconds * sampleRate);
            channelSamples = (int)Math.Round(channelSeconds * sampleRate);
            double yEvenBeginSeconds = syncPorchSeconds;
            yEvenBeginSamples = (int)Math.Round(yEvenBeginSeconds * sampleRate);
            beginSamples = yEvenBeginSamples;
            double vAvgBeginSeconds = yEvenBeginSeconds + channelSeconds;
            vAvgBeginSamples = (int)Math.Round(vAvgBeginSeconds * sampleRate);
            double uAvgBeginSeconds = vAvgBeginSeconds + channelSeconds;
            uAvgBeginSamples = (int)Math.Round(uAvgBeginSeconds * sampleRate);
            double yOddBeginSeconds = uAvgBeginSeconds + channelSeconds;
            yOddBeginSamples = (int)Math.Round(yOddBeginSeconds * sampleRate);
            double yOddEndSeconds = yOddBeginSeconds + channelSeconds;
            endSamples = (int)Math.Round(yOddEndSeconds * sampleRate);
            lowPassFilter = new ExponentialMovingAverage();
        }

        private static float FreqToLevel(float frequency, float offset)
        {
            return 0.5f * (frequency - offset + 1.0f);
        }

        public override string GetName() => name;
        public override int GetVISCode() => code;
        public override int GetWidth() => horizontalPixels;
        public override int GetHeight() => verticalPixels;
        public override int GetFirstPixelSampleIndex() => beginSamples;
        public override int GetFirstSyncPulseIndex() => 0;
        public override int GetScanLineSamples() => scanLineSamplesValue;
        public override void ResetState() { }

        public override bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset)
        {
            if (syncPulseIndex + beginSamples < 0 || syncPulseIndex + endSamples > scanLineBuffer.Length)
                return false;
            lowPassFilter.Cutoff(horizontalPixels, 2 * channelSamples, 2);
            lowPassFilter.Reset();
            for (int i = beginSamples; i < endSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[syncPulseIndex + i]);
            lowPassFilter.Reset();
            for (int i = endSamples - 1; i >= beginSamples; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int position = (i * channelSamples) / horizontalPixels;
                int yEvenPos = position + yEvenBeginSamples;
                int vAvgPos = position + vAvgBeginSamples;
                int uAvgPos = position + uAvgBeginSamples;
                int yOddPos = position + yOddBeginSamples;
                pixelBuffer.Pixels[i] =
                    ColorConverter.YUV2RGB(scratchBuffer[yEvenPos], scratchBuffer[uAvgPos], scratchBuffer[vAvgPos]);
                pixelBuffer.Pixels[i + horizontalPixels] =
                    ColorConverter.YUV2RGB(scratchBuffer[yOddPos], scratchBuffer[uAvgPos], scratchBuffer[vAvgPos]);
            }
            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 2;
            return true;
        }
    }
}
