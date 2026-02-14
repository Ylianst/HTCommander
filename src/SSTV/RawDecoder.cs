/*
Raw decoder
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class RawDecoder : BaseMode
    {
        private readonly ExponentialMovingAverage lowPassFilter;
        private readonly int smallPictureMaxSamples;
        private readonly int mediumPictureMaxSamples;
        private readonly string name;

        public RawDecoder(string name, int sampleRate)
        {
            this.name = name;
            smallPictureMaxSamples = (int)Math.Round(0.125 * sampleRate);
            mediumPictureMaxSamples = (int)Math.Round(0.175 * sampleRate);
            lowPassFilter = new ExponentialMovingAverage();
        }

        private static float FreqToLevel(float frequency, float offset)
        {
            return 0.5f * (frequency - offset + 1.0f);
        }

        public override string GetName() => name;
        public override int GetVISCode() => -1;
        public override int GetWidth() => -1;
        public override int GetHeight() => -1;
        public override int GetFirstPixelSampleIndex() => 0;
        public override int GetFirstSyncPulseIndex() => -1;
        public override int GetScanLineSamples() => -1;
        public override void ResetState() { }

        public override bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset)
        {
            if (syncPulseIndex < 0 || syncPulseIndex + scanLineSamples > scanLineBuffer.Length)
                return false;
            int horizontalPixels = scopeBufferWidth;
            if (scanLineSamples < smallPictureMaxSamples)
                horizontalPixels /= 2;
            if (scanLineSamples < mediumPictureMaxSamples)
                horizontalPixels /= 2;
            lowPassFilter.Cutoff(horizontalPixels, 2 * scanLineSamples, 2);
            lowPassFilter.Reset();
            for (int i = 0; i < scanLineSamples; ++i)
                scratchBuffer[i] = lowPassFilter.Avg(scanLineBuffer[syncPulseIndex + i]);
            lowPassFilter.Reset();
            for (int i = scanLineSamples - 1; i >= 0; --i)
                scratchBuffer[i] = FreqToLevel(lowPassFilter.Avg(scratchBuffer[i]), frequencyOffset);
            for (int i = 0; i < horizontalPixels; ++i)
            {
                int position = (i * scanLineSamples) / horizontalPixels;
                pixelBuffer.Pixels[i] = ColorConverter.GRAY(scratchBuffer[position]);
            }
            pixelBuffer.Width = horizontalPixels;
            pixelBuffer.Height = 1;
            return true;
        }
    }
}
