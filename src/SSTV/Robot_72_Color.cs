/*
Robot 72 Color
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Robot_72_Color : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly int horizontalPixels;
        private readonly int verticalPixels;
        private readonly int scanLineSamplesValue;
        private readonly int luminanceSamples;
        private readonly int chrominanceSamples;
        private readonly int beginSamples;
        private readonly int yBeginSamples;
        private readonly int vBeginSamples;
        private readonly int uBeginSamples;
        private readonly int endSamples;

        public Robot_72_Color(int sampleRate)
        {
            horizontalPixels = 320;
            verticalPixels = 240;
            double syncPulseSeconds = 0.009;
            double syncPorchSeconds = 0.003;
            double luminanceSeconds = 0.138;
            double separatorSeconds = 0.0045;
            double porchSeconds = 0.0015;
            double chrominanceSeconds = 0.069;
            double scanLineSeconds = syncPulseSeconds + syncPorchSeconds + luminanceSeconds + 2 * (separatorSeconds + porchSeconds + chrominanceSeconds);
            scanLineSamplesValue = (int)Math.Round(scanLineSeconds * sampleRate);
            luminanceSamples = (int)Math.Round(luminanceSeconds * sampleRate);
            chrominanceSamples = (int)Math.Round(chrominanceSeconds * sampleRate);
            double yBeginSeconds = syncPorchSeconds;
            yBeginSamples = (int)Math.Round(yBeginSeconds * sampleRate);
            beginSamples = yBeginSamples;
            double yEndSeconds = yBeginSeconds + luminanceSeconds;
            double vBeginSeconds = yEndSeconds + separatorSeconds + porchSeconds;
            vBeginSamples = (int)Math.Round(vBeginSeconds * sampleRate);
            double vEndSeconds = vBeginSeconds + chrominanceSeconds;
            double uBeginSeconds = vEndSeconds + separatorSeconds + porchSeconds;
            uBeginSamples = (int)Math.Round(uBeginSeconds * sampleRate);
            double uEndSeconds = uBeginSeconds + chrominanceSeconds;
            endSamples = (int)Math.Round(uEndSeconds * sampleRate);
            lowPassFilter = new ExponentialMovingAverage();
        }

        private static float FreqToLevel(float frequency, float offset)
        {
            return 0.5f * (frequency - offset + 1.0f);
        }

        public override string GetName() => "Robot 72 Color";
        public override int GetVISCode() => 12;
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
            lowPassFilter.Cutoff(horizontalPixels, 2 * luminanceSamples, 2);
            lowPassFilter.Reset();
            for (int i = beginSamples; i < endSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[syncPulseIndex + i]);
            lowPassFilter.Reset();
            for (int i = endSamples - 1; i >= beginSamples; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int yPos = yBeginSamples + (i * luminanceSamples) / horizontalPixels;
                int uPos = uBeginSamples + (i * chrominanceSamples) / horizontalPixels;
                int vPos = vBeginSamples + (i * chrominanceSamples) / horizontalPixels;
                pixelBuffer.Pixels[i] = ColorConverter.YUV2RGB(scratchBuffer[yPos], scratchBuffer[uPos], scratchBuffer[vPos]);
            }
            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 1;
            return true;
        }
    }
}
