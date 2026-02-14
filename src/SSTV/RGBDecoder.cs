/*
Decoder for RGB modes
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class RGBDecoder : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly int horizontalPixels;
        private readonly int verticalPixels;
        private readonly int firstSyncPulseIndex;
        private readonly int scanLineSamples;
        private readonly int beginSamples;
        private readonly int redBeginSamples;
        private readonly int redSamples;
        private readonly int greenBeginSamples;
        private readonly int greenSamples;
        private readonly int blueBeginSamples;
        private readonly int blueSamples;
        private readonly int endSamples;
        private readonly string name;
        private readonly int code;

        public RGBDecoder(string name, int code, int horizontalPixels, int verticalPixels, double firstSyncPulseSeconds, double scanLineSeconds, double beginSeconds, double redBeginSeconds, double redEndSeconds, double greenBeginSeconds, double greenEndSeconds, double blueBeginSeconds, double blueEndSeconds, double endSeconds, int sampleRate)
        {
            this.name = name;
            this.code = code;
            this.horizontalPixels = horizontalPixels;
            this.verticalPixels = verticalPixels;
            firstSyncPulseIndex = (int)Math.Round(firstSyncPulseSeconds * sampleRate);
            scanLineSamples = (int)Math.Round(scanLineSeconds * sampleRate);
            beginSamples = (int)Math.Round(beginSeconds * sampleRate);
            redBeginSamples = (int)Math.Round(redBeginSeconds * sampleRate) - beginSamples;
            redSamples = (int)Math.Round((redEndSeconds - redBeginSeconds) * sampleRate);
            greenBeginSamples = (int)Math.Round(greenBeginSeconds * sampleRate) - beginSamples;
            greenSamples = (int)Math.Round((greenEndSeconds - greenBeginSeconds) * sampleRate);
            blueBeginSamples = (int)Math.Round(blueBeginSeconds * sampleRate) - beginSamples;
            blueSamples = (int)Math.Round((blueEndSeconds - blueBeginSeconds) * sampleRate);
            endSamples = (int)Math.Round(endSeconds * sampleRate);
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
        public override int GetFirstSyncPulseIndex() => firstSyncPulseIndex;
        public override int GetScanLineSamples() => scanLineSamples;
        public override void ResetState() { }

        public override bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset)
        {
            if (syncPulseIndex + beginSamples < 0 || syncPulseIndex + endSamples > scanLineBuffer.Length)
                return false;
            lowPassFilter.Cutoff(horizontalPixels, 2 * greenSamples, 2);
            lowPassFilter.Reset();
            for (int i = 0; i < endSamples - beginSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[syncPulseIndex + beginSamples + i]);
            lowPassFilter.Reset();
            for (int i = endSamples - beginSamples - 1; i >= 0; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int redPos = redBeginSamples + (i * redSamples) / horizontalPixels;
                int greenPos = greenBeginSamples + (i * greenSamples) / horizontalPixels;
                int bluePos = blueBeginSamples + (i * blueSamples) / horizontalPixels;
                pixelBuffer.Pixels[i] = ColorConverter.RGB(scratchBuffer[redPos], scratchBuffer[greenPos], scratchBuffer[bluePos]);
            }
            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 1;
            return true;
        }
    }
}
