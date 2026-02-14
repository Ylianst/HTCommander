/*
Mode interface
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public interface IMode
    {
        string GetName();

        int GetVISCode();

        int GetWidth();

        int GetHeight();

        int GetFirstPixelSampleIndex();

        int GetFirstSyncPulseIndex();

        int GetScanLineSamples();

        int[] PostProcessScopeImage(int[] pixels, int width, int height);

        void ResetState();

        /// <summary>
        /// Decode a scan line.
        /// </summary>
        /// <param name="frequencyOffset">Normalized correction of frequency (expected vs actual)</param>
        /// <returns>true if scanline was decoded</returns>
        bool DecodeScanLine(PixelBuffer pixelBuffer, float[] scratchBuffer, float[] scanLineBuffer, int scopeBufferWidth, int syncPulseIndex, int scanLineSamples, float frequencyOffset);
    }
}
