/*
SSTV Decoder
Ported to C# from https://github.com/xdsopl/robot36
*/

#nullable enable

using System;
using System.Collections.Generic;

namespace HTCommander.SSTV
{
    public class Decoder
    {
        private readonly SimpleMovingAverage pulseFilter;
        private readonly Demodulator demodulator;
        private readonly PixelBuffer pixelBuffer;
        private readonly PixelBuffer scopeBuffer;
        private readonly PixelBuffer imageBuffer;
        private readonly float[] scanLineBuffer;
        private readonly float[] scratchBuffer;
        private readonly int[] last5msSyncPulses;
        private readonly int[] last9msSyncPulses;
        private readonly int[] last20msSyncPulses;
        private readonly int[] last5msScanLines;
        private readonly int[] last9msScanLines;
        private readonly int[] last20msScanLines;
        private readonly float[] last5msFrequencyOffsets;
        private readonly float[] last9msFrequencyOffsets;
        private readonly float[] last20msFrequencyOffsets;
        private readonly float[] visCodeBitFrequencies;
        private readonly int pulseFilterDelay;
        private readonly int scanLineMinSamples;
        private readonly int syncPulseToleranceSamples;
        private readonly int scanLineToleranceSamples;
        private readonly int leaderToneSamples;
        private readonly int leaderToneToleranceSamples;
        private readonly int transitionSamples;
        private readonly int visCodeBitSamples;
        private readonly int visCodeSamples;
        private readonly IMode rawMode;
        private readonly IMode hfFaxMode;
        private readonly List<IMode> syncPulse5msModes;
        private readonly List<IMode> syncPulse9msModes;
        private readonly List<IMode> syncPulse20msModes;

        public IMode CurrentMode;
        private bool lockMode;
        private int currentSample;
        private int leaderBreakIndex;
        private int lastSyncPulseIndex;
        private int currentScanLineSamples;
        private float lastFrequencyOffset;

        public Decoder(PixelBuffer scopeBuffer, PixelBuffer imageBuffer, string rawName, int sampleRate)
        {
            this.scopeBuffer = scopeBuffer;
            this.imageBuffer = imageBuffer;
            imageBuffer.Line = -1;
            pixelBuffer = new PixelBuffer(800, 2);
            demodulator = new Demodulator(sampleRate);
            double pulseFilterSeconds = 0.0025;
            int pulseFilterSamples = (int)Math.Round(pulseFilterSeconds * sampleRate) | 1;
            pulseFilterDelay = (pulseFilterSamples - 1) / 2;
            pulseFilter = new SimpleMovingAverage(pulseFilterSamples);
            double scanLineMaxSeconds = 7;
            int scanLineMaxSamples = (int)Math.Round(scanLineMaxSeconds * sampleRate);
            scanLineBuffer = new float[scanLineMaxSamples];
            double scratchBufferSeconds = 1.1;
            int scratchBufferSamples = (int)Math.Round(scratchBufferSeconds * sampleRate);
            scratchBuffer = new float[scratchBufferSamples];
            double leaderToneSeconds = 0.3;
            leaderToneSamples = (int)Math.Round(leaderToneSeconds * sampleRate);
            double leaderToneToleranceSeconds = leaderToneSeconds * 0.2;
            leaderToneToleranceSamples = (int)Math.Round(leaderToneToleranceSeconds * sampleRate);
            double transitionSeconds = 0.0005;
            transitionSamples = (int)Math.Round(transitionSeconds * sampleRate);
            double visCodeBitSeconds = 0.03;
            visCodeBitSamples = (int)Math.Round(visCodeBitSeconds * sampleRate);
            double visCodeSeconds = 0.3;
            visCodeSamples = (int)Math.Round(visCodeSeconds * sampleRate);
            visCodeBitFrequencies = new float[10];
            int scanLineCount = 4;
            last5msScanLines = new int[scanLineCount];
            last9msScanLines = new int[scanLineCount];
            last20msScanLines = new int[scanLineCount];
            int syncPulseCount = scanLineCount + 1;
            last5msSyncPulses = new int[syncPulseCount];
            last9msSyncPulses = new int[syncPulseCount];
            last20msSyncPulses = new int[syncPulseCount];
            last5msFrequencyOffsets = new float[syncPulseCount];
            last9msFrequencyOffsets = new float[syncPulseCount];
            last20msFrequencyOffsets = new float[syncPulseCount];
            double scanLineMinSeconds = 0.05;
            scanLineMinSamples = (int)Math.Round(scanLineMinSeconds * sampleRate);
            double syncPulseToleranceSeconds = 0.03;
            syncPulseToleranceSamples = (int)Math.Round(syncPulseToleranceSeconds * sampleRate);
            double scanLineToleranceSeconds = 0.001;
            scanLineToleranceSamples = (int)Math.Round(scanLineToleranceSeconds * sampleRate);
            rawMode = new RawDecoder(rawName, sampleRate);
            hfFaxMode = new HFFax(sampleRate);
            IMode robot36 = new Robot_36_Color(sampleRate);
            CurrentMode = robot36;
            currentScanLineSamples = robot36.GetScanLineSamples();
            syncPulse5msModes = new List<IMode>();
            syncPulse5msModes.Add(RGBModes.Wraase_SC2_180(sampleRate));
            syncPulse5msModes.Add(RGBModes.Martin("1", 44, 0.146432, sampleRate));
            syncPulse5msModes.Add(RGBModes.Martin("2", 40, 0.073216, sampleRate));
            syncPulse9msModes = new List<IMode>();
            syncPulse9msModes.Add(robot36);
            syncPulse9msModes.Add(new Robot_72_Color(sampleRate));
            syncPulse9msModes.Add(RGBModes.Scottie("1", 60, 0.138240, sampleRate));
            syncPulse9msModes.Add(RGBModes.Scottie("2", 56, 0.088064, sampleRate));
            syncPulse9msModes.Add(RGBModes.Scottie("DX", 76, 0.3456, sampleRate));
            syncPulse20msModes = new List<IMode>();
            syncPulse20msModes.Add(new PaulDon("50", 93, 320, 256, 0.09152, sampleRate));
            syncPulse20msModes.Add(new PaulDon("90", 99, 320, 256, 0.17024, sampleRate));
            syncPulse20msModes.Add(new PaulDon("120", 95, 640, 496, 0.1216, sampleRate));
            syncPulse20msModes.Add(new PaulDon("160", 98, 512, 400, 0.195584, sampleRate));
            syncPulse20msModes.Add(new PaulDon("180", 96, 640, 496, 0.18304, sampleRate));
            syncPulse20msModes.Add(new PaulDon("240", 97, 640, 496, 0.24448, sampleRate));
            syncPulse20msModes.Add(new PaulDon("290", 94, 800, 616, 0.2288, sampleRate));
        }

        private static double ScanLineMean(int[] lines)
        {
            double mean = 0;
            foreach (int diff in lines)
                mean += diff;
            mean /= lines.Length;
            return mean;
        }

        private static double ScanLineStdDev(int[] lines, double mean)
        {
            double stdDev = 0;
            foreach (int diff in lines)
                stdDev += (diff - mean) * (diff - mean);
            stdDev = Math.Sqrt(stdDev / lines.Length);
            return stdDev;
        }

        private static double FrequencyOffsetMean(float[] offsets)
        {
            double mean = 0;
            foreach (float diff in offsets)
                mean += diff;
            mean /= offsets.Length;
            return mean;
        }

        private IMode DetectMode(List<IMode> modes, int line)
        {
            IMode bestMode = rawMode;
            int bestDist = int.MaxValue;
            foreach (IMode mode in modes)
            {
                int dist = Math.Abs(line - mode.GetScanLineSamples());
                if (dist <= scanLineToleranceSamples && dist < bestDist)
                {
                    bestDist = dist;
                    bestMode = mode;
                }
            }
            return bestMode;
        }

        private static IMode? FindMode(List<IMode> modes, int code)
        {
            foreach (IMode mode in modes)
                if (mode.GetVISCode() == code)
                    return mode;
            return null;
        }

        private static IMode? FindMode(List<IMode> modes, string name)
        {
            foreach (IMode mode in modes)
                if (mode.GetName().Equals(name))
                    return mode;
            return null;
        }

        private void CopyUnscaled()
        {
            int width = Math.Min(scopeBuffer.Width, pixelBuffer.Width);
            for (int row = 0; row < pixelBuffer.Height; ++row)
            {
                int line = scopeBuffer.Width * scopeBuffer.Line;
                Array.Copy(pixelBuffer.Pixels, row * pixelBuffer.Width, scopeBuffer.Pixels, line, width);
                Array.Fill(scopeBuffer.Pixels, 0, line + width, scopeBuffer.Width - width);
                Array.Copy(scopeBuffer.Pixels, line, scopeBuffer.Pixels, scopeBuffer.Width * (scopeBuffer.Line + scopeBuffer.Height / 2), scopeBuffer.Width);
                scopeBuffer.Line = (scopeBuffer.Line + 1) % (scopeBuffer.Height / 2);
            }
        }

        private void CopyScaled(int scale)
        {
            for (int row = 0; row < pixelBuffer.Height; ++row)
            {
                int line = scopeBuffer.Width * scopeBuffer.Line;
                for (int col = 0; col < pixelBuffer.Width; ++col)
                    for (int i = 0; i < scale; ++i)
                        scopeBuffer.Pixels[line + col * scale + i] = pixelBuffer.Pixels[pixelBuffer.Width * row + col];
                Array.Fill(scopeBuffer.Pixels, 0, line + pixelBuffer.Width * scale, scopeBuffer.Width - pixelBuffer.Width * scale);
                Array.Copy(scopeBuffer.Pixels, line, scopeBuffer.Pixels, scopeBuffer.Width * (scopeBuffer.Line + scopeBuffer.Height / 2), scopeBuffer.Width);
                scopeBuffer.Line = (scopeBuffer.Line + 1) % (scopeBuffer.Height / 2);
                for (int i = 1; i < scale; ++i)
                {
                    Array.Copy(scopeBuffer.Pixels, line, scopeBuffer.Pixels, scopeBuffer.Width * scopeBuffer.Line, scopeBuffer.Width);
                    Array.Copy(scopeBuffer.Pixels, line, scopeBuffer.Pixels, scopeBuffer.Width * (scopeBuffer.Line + scopeBuffer.Height / 2), scopeBuffer.Width);
                    scopeBuffer.Line = (scopeBuffer.Line + 1) % (scopeBuffer.Height / 2);
                }
            }
        }

        private void CopyLines(bool okay)
        {
            if (!okay)
                return;
            bool finish = false;
            if (imageBuffer.Line >= 0 && imageBuffer.Line < imageBuffer.Height && imageBuffer.Width == pixelBuffer.Width)
            {
                int width = imageBuffer.Width;
                for (int row = 0; row < pixelBuffer.Height && imageBuffer.Line < imageBuffer.Height; ++row, ++imageBuffer.Line)
                    Array.Copy(pixelBuffer.Pixels, row * width, imageBuffer.Pixels, imageBuffer.Line * width, width);
                finish = imageBuffer.Line == imageBuffer.Height;
            }
            int scale = scopeBuffer.Width / pixelBuffer.Width;
            if (scale <= 1)
                CopyUnscaled();
            else
                CopyScaled(scale);
            if (finish)
                DrawLines(unchecked((int)0xff000000), 10);
        }

        private void DrawLines(int color, int count)
        {
            for (int i = 0; i < count; ++i)
            {
                Array.Fill(scopeBuffer.Pixels, color, scopeBuffer.Line * scopeBuffer.Width, scopeBuffer.Width);
                Array.Fill(scopeBuffer.Pixels, color, (scopeBuffer.Line + scopeBuffer.Height / 2) * scopeBuffer.Width, scopeBuffer.Width);
                scopeBuffer.Line = (scopeBuffer.Line + 1) % (scopeBuffer.Height / 2);
            }
        }

        private static void AdjustSyncPulses(int[] pulses, int shift)
        {
            for (int i = 0; i < pulses.Length; ++i)
                pulses[i] -= shift;
        }

        private void ShiftSamples(int shift)
        {
            if (shift <= 0 || shift > currentSample)
                return;
            currentSample -= shift;
            leaderBreakIndex -= shift;
            lastSyncPulseIndex -= shift;
            AdjustSyncPulses(last5msSyncPulses, shift);
            AdjustSyncPulses(last9msSyncPulses, shift);
            AdjustSyncPulses(last20msSyncPulses, shift);
            Array.Copy(scanLineBuffer, shift, scanLineBuffer, 0, currentSample);
        }

        private bool HandleHeader()
        {
            if (leaderBreakIndex < visCodeBitSamples + leaderToneToleranceSamples || currentSample < leaderBreakIndex + leaderToneSamples + leaderToneToleranceSamples + visCodeSamples + visCodeBitSamples)
                return false;
            int breakPulseIndex = leaderBreakIndex;
            leaderBreakIndex = 0;
            float preBreakFreq = 0;
            for (int i = 0; i < leaderToneToleranceSamples; ++i)
                preBreakFreq += scanLineBuffer[breakPulseIndex - visCodeBitSamples - leaderToneToleranceSamples + i];
            float leaderToneFrequency = 1900;
            float centerFrequency = 1900;
            float toleranceFrequency = 50;
            float halfBandWidth = 400;
            preBreakFreq = preBreakFreq * halfBandWidth / leaderToneToleranceSamples + centerFrequency;
            if (Math.Abs(preBreakFreq - leaderToneFrequency) > toleranceFrequency)
                return false;
            float leaderFreq = 0;
            for (int i = transitionSamples; i < leaderToneSamples - leaderToneToleranceSamples; ++i)
                leaderFreq += scanLineBuffer[breakPulseIndex + i];
            float leaderFreqOffset = leaderFreq / (leaderToneSamples - transitionSamples - leaderToneToleranceSamples);
            leaderFreq = leaderFreqOffset * halfBandWidth + centerFrequency;
            if (Math.Abs(leaderFreq - leaderToneFrequency) > toleranceFrequency)
                return false;
            float stopBitFrequency = 1200;
            float syncPulseFrequency = 1200;
            float pulseThresholdFrequency = (stopBitFrequency + leaderToneFrequency) / 2;
            float pulseThresholdValue = (pulseThresholdFrequency - centerFrequency) / halfBandWidth;
            int visBeginIndex = breakPulseIndex + leaderToneSamples - leaderToneToleranceSamples;
            int visEndIndex = breakPulseIndex + leaderToneSamples + leaderToneToleranceSamples + visCodeBitSamples;
            for (int i = 0; i < pulseFilter.Length; ++i)
                pulseFilter.Avg(scanLineBuffer[visBeginIndex++] - leaderFreqOffset);
            while (++visBeginIndex < visEndIndex)
                if (pulseFilter.Avg(scanLineBuffer[visBeginIndex] - leaderFreqOffset) < pulseThresholdValue)
                    break;
            if (visBeginIndex >= visEndIndex)
                return false;
            visBeginIndex -= pulseFilterDelay;
            visEndIndex = visBeginIndex + visCodeSamples;
            Array.Fill(visCodeBitFrequencies, 0f);
            for (int j = 0; j < 10; ++j)
                for (int i = transitionSamples; i < visCodeBitSamples - transitionSamples; ++i)
                    visCodeBitFrequencies[j] += scanLineBuffer[visBeginIndex + visCodeBitSamples * j + i] - leaderFreqOffset;
            for (int i = 0; i < 10; ++i)
                visCodeBitFrequencies[i] = visCodeBitFrequencies[i] * halfBandWidth / (visCodeBitSamples - 2 * transitionSamples) + centerFrequency;
            if (Math.Abs(visCodeBitFrequencies[0] - stopBitFrequency) > toleranceFrequency || Math.Abs(visCodeBitFrequencies[9] - stopBitFrequency) > toleranceFrequency)
                return false;
            float oneBitFrequency = 1100;
            float zeroBitFrequency = 1300;
            for (int i = 1; i < 9; ++i)
                if (Math.Abs(visCodeBitFrequencies[i] - oneBitFrequency) > toleranceFrequency && Math.Abs(visCodeBitFrequencies[i] - zeroBitFrequency) > toleranceFrequency)
                    return false;
            int visCode = 0;
            for (int i = 0; i < 8; ++i)
                visCode |= (visCodeBitFrequencies[i + 1] < stopBitFrequency ? 1 : 0) << i;
            bool check = true;
            for (int i = 0; i < 8; ++i)
                check ^= (visCode & (1 << i)) != 0;
            visCode &= 127;
            if (!check)
                return false;
            float syncPorchFrequency = 1500;
            float syncThresholdFrequency = (syncPulseFrequency + syncPorchFrequency) / 2;
            float syncThresholdValue = (syncThresholdFrequency - centerFrequency) / halfBandWidth;
            int syncPulseIndex = visEndIndex - visCodeBitSamples;
            int syncPulseMaxIndex = visEndIndex + visCodeBitSamples;
            for (int i = 0; i < pulseFilter.Length; ++i)
                pulseFilter.Avg(scanLineBuffer[syncPulseIndex++] - leaderFreqOffset);
            while (++syncPulseIndex < syncPulseMaxIndex)
                if (pulseFilter.Avg(scanLineBuffer[syncPulseIndex] - leaderFreqOffset) > syncThresholdValue)
                    break;
            if (syncPulseIndex >= syncPulseMaxIndex)
                return false;
            syncPulseIndex -= pulseFilterDelay;
            IMode? mode;
            int[] pulses;
            int[] lines;
            if ((mode = FindMode(syncPulse5msModes, visCode)) != null)
            {
                pulses = last5msSyncPulses;
                lines = last5msScanLines;
            }
            else if ((mode = FindMode(syncPulse9msModes, visCode)) != null)
            {
                pulses = last9msSyncPulses;
                lines = last9msScanLines;
            }
            else if ((mode = FindMode(syncPulse20msModes, visCode)) != null)
            {
                pulses = last20msSyncPulses;
                lines = last20msScanLines;
            }
            else
            {
                if (!lockMode)
                    DrawLines(unchecked((int)0xffff0000), 8);
                return false;
            }
            if (lockMode && mode != CurrentMode)
                return false;
            mode.ResetState();
            imageBuffer.Width = mode.GetWidth();
            imageBuffer.Height = mode.GetHeight();
            imageBuffer.Line = 0;
            CurrentMode = mode;
            lastSyncPulseIndex = syncPulseIndex + mode.GetFirstSyncPulseIndex();
            currentScanLineSamples = mode.GetScanLineSamples();
            lastFrequencyOffset = leaderFreqOffset;
            int oldestSyncPulseIndex = lastSyncPulseIndex - (pulses.Length - 1) * currentScanLineSamples;
            if (mode.GetFirstSyncPulseIndex() > 0)
                oldestSyncPulseIndex -= currentScanLineSamples;
            for (int i = 0; i < pulses.Length; ++i)
                pulses[i] = oldestSyncPulseIndex + i * currentScanLineSamples;
            Array.Fill(lines, currentScanLineSamples);
            ShiftSamples(lastSyncPulseIndex + mode.GetFirstPixelSampleIndex());
            DrawLines(unchecked((int)0xff00ff00), 8);
            DrawLines(unchecked((int)0xff000000), 10);
            return true;
        }

        private bool ProcessSyncPulse(List<IMode> modes, float[] freqOffs, int[] syncIndexes, int[] lineLengths, int latestSyncIndex)
        {
            for (int i = 1; i < syncIndexes.Length; ++i)
                syncIndexes[i - 1] = syncIndexes[i];
            syncIndexes[syncIndexes.Length - 1] = latestSyncIndex;
            for (int i = 1; i < lineLengths.Length; ++i)
                lineLengths[i - 1] = lineLengths[i];
            lineLengths[lineLengths.Length - 1] = syncIndexes[syncIndexes.Length - 1] - syncIndexes[syncIndexes.Length - 2];
            for (int i = 1; i < freqOffs.Length; ++i)
                freqOffs[i - 1] = freqOffs[i];
            freqOffs[syncIndexes.Length - 1] = demodulator.FrequencyOffset;
            if (lineLengths[0] == 0)
                return false;
            double mean = ScanLineMean(lineLengths);
            int scanLineSamples = (int)Math.Round(mean);
            if (scanLineSamples < scanLineMinSamples || scanLineSamples > scratchBuffer.Length)
                return false;
            if (ScanLineStdDev(lineLengths, mean) > scanLineToleranceSamples)
                return false;
            bool pictureChanged = false;
            if (lockMode || (imageBuffer.Line >= 0 && imageBuffer.Line < imageBuffer.Height))
            {
                if (CurrentMode != rawMode && Math.Abs(scanLineSamples - CurrentMode.GetScanLineSamples()) > scanLineToleranceSamples)
                    return false;
            }
            else
            {
                IMode prevMode = CurrentMode;
                CurrentMode = DetectMode(modes, scanLineSamples);
                pictureChanged = CurrentMode != prevMode
                    || Math.Abs(currentScanLineSamples - scanLineSamples) > scanLineToleranceSamples
                    || Math.Abs(lastSyncPulseIndex + scanLineSamples - syncIndexes[syncIndexes.Length - 1]) > syncPulseToleranceSamples;
            }
            if (pictureChanged)
            {
                DrawLines(unchecked((int)0xff000000), 10);
                DrawLines(unchecked((int)0xff00ffff), 8);
                DrawLines(unchecked((int)0xff000000), 10);
            }
            float frequencyOffset = (float)FrequencyOffsetMean(freqOffs);
            if (syncIndexes[0] >= scanLineSamples && pictureChanged)
            {
                int endPulse = syncIndexes[0];
                int extrapolate = endPulse / scanLineSamples;
                int firstPulse = endPulse - extrapolate * scanLineSamples;
                for (int pulseIndex = firstPulse; pulseIndex < endPulse; pulseIndex += scanLineSamples)
                    CopyLines(CurrentMode.DecodeScanLine(pixelBuffer, scratchBuffer, scanLineBuffer, scopeBuffer.Width, pulseIndex, scanLineSamples, frequencyOffset));
            }
            for (int i = pictureChanged ? 0 : lineLengths.Length - 1; i < lineLengths.Length; ++i)
                CopyLines(CurrentMode.DecodeScanLine(pixelBuffer, scratchBuffer, scanLineBuffer, scopeBuffer.Width, syncIndexes[i], lineLengths[i], frequencyOffset));
            lastSyncPulseIndex = syncIndexes[syncIndexes.Length - 1];
            currentScanLineSamples = scanLineSamples;
            lastFrequencyOffset = frequencyOffset;
            ShiftSamples(lastSyncPulseIndex + CurrentMode.GetFirstPixelSampleIndex());
            return true;
        }

        public bool Process(float[] recordBuffer, int channelSelect)
        {
            bool newLinesPresent = false;
            bool syncPulseDetected = demodulator.Process(recordBuffer, channelSelect);
            int syncPulseIndex = currentSample + demodulator.SyncPulseOffset;
            int channels = channelSelect > 0 ? 2 : 1;
            for (int j = 0; j < recordBuffer.Length / channels; ++j)
            {
                scanLineBuffer[currentSample++] = recordBuffer[j];
                if (currentSample >= scanLineBuffer.Length)
                {
                    ShiftSamples(currentScanLineSamples);
                    syncPulseIndex -= currentScanLineSamples;
                }
            }
            if (syncPulseDetected)
            {
                switch (demodulator.SyncPulseWidthValue)
                {
                    case Demodulator.SyncPulseWidth.FiveMilliSeconds:
                        newLinesPresent = ProcessSyncPulse(syncPulse5msModes, last5msFrequencyOffsets, last5msSyncPulses, last5msScanLines, syncPulseIndex);
                        break;
                    case Demodulator.SyncPulseWidth.NineMilliSeconds:
                        leaderBreakIndex = syncPulseIndex;
                        newLinesPresent = ProcessSyncPulse(syncPulse9msModes, last9msFrequencyOffsets, last9msSyncPulses, last9msScanLines, syncPulseIndex);
                        break;
                    case Demodulator.SyncPulseWidth.TwentyMilliSeconds:
                        leaderBreakIndex = syncPulseIndex;
                        newLinesPresent = ProcessSyncPulse(syncPulse20msModes, last20msFrequencyOffsets, last20msSyncPulses, last20msScanLines, syncPulseIndex);
                        break;
                    default:
                        break;
                }
            }
            else if (HandleHeader())
            {
                newLinesPresent = true;
            }
            else if (currentSample > lastSyncPulseIndex + (currentScanLineSamples * 5) / 4)
            {
                CopyLines(CurrentMode.DecodeScanLine(pixelBuffer, scratchBuffer, scanLineBuffer, scopeBuffer.Width, lastSyncPulseIndex, currentScanLineSamples, lastFrequencyOffset));
                lastSyncPulseIndex += currentScanLineSamples;
                newLinesPresent = true;
            }

            return newLinesPresent;
        }

        public void SetMode(string name)
        {
            if (rawMode.GetName().Equals(name))
            {
                lockMode = true;
                imageBuffer.Line = -1;
                CurrentMode = rawMode;
                return;
            }
            IMode? mode = FindMode(syncPulse5msModes, name);
            if (mode == null)
                mode = FindMode(syncPulse9msModes, name);
            if (mode == null)
                mode = FindMode(syncPulse20msModes, name);
            if (mode == null && hfFaxMode.GetName().Equals(name))
                mode = hfFaxMode;
            if (mode == CurrentMode)
            {
                lockMode = true;
                return;
            }
            if (mode != null)
            {
                lockMode = true;
                imageBuffer.Width = mode.GetWidth();
                imageBuffer.Height = mode.GetHeight();
                // Reallocate if buffer is too small
                int required = imageBuffer.Width * imageBuffer.Height;
                if (imageBuffer.Pixels.Length < required)
                    imageBuffer.Pixels = new int[required];
                CurrentMode = mode;
                currentScanLineSamples = mode.GetScanLineSamples();
                // For modes without VIS header (like HF Fax), start decoding immediately
                if (mode.GetVISCode() < 0)
                    imageBuffer.Line = 0;
                else
                    imageBuffer.Line = -1;
                return;
            }
            lockMode = false;
        }
    }
}
