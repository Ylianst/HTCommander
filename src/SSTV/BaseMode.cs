/*
Base class for all modes
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public abstract class BaseMode : IMode
    {
        public abstract string GetName();
        public abstract int GetVISCode();
        public abstract int GetWidth();
        public abstract int GetHeight();
        public abstract int GetFirstPixelSampleIndex();
        public abstract int GetFirstSyncPulseIndex();
        public abstract int GetScanLineSamples();
        public abstract void ResetState();
        public abstract bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset);

        public virtual int[] PostProcessScopeImage(int[] pixels, int width, int height)
        {
            return pixels;
        }
    }
}
