/*
SSTV Demodulator
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Demodulator
    {
        private readonly SimpleMovingAverage syncPulseFilter;
        private readonly ComplexConvolution baseBandLowPass;
        private readonly FrequencyModulation frequencyModulation;
        private readonly SchmittTrigger syncPulseTrigger;
        private readonly Phasor baseBandOscillator;
        private readonly Delay syncPulseValueDelay;
        private readonly double scanLineBandwidth;
        private readonly double centerFrequency;
        private readonly float syncPulseFrequencyValue;
        private readonly float syncPulseFrequencyTolerance;
        private readonly int syncPulse5msMinSamples;
        private readonly int syncPulse5msMaxSamples;
        private readonly int syncPulse9msMaxSamples;
        private readonly int syncPulse20msMaxSamples;
        private readonly int syncPulseFilterDelay;
        private int syncPulseCounter;
        private Complex baseBand;

        public enum SyncPulseWidth
        {
            FiveMilliSeconds,
            NineMilliSeconds,
            TwentyMilliSeconds
        }

        public SyncPulseWidth SyncPulseWidthValue;
        public int SyncPulseOffset;
        public float FrequencyOffset;

        public const double SyncPulseFrequency = 1200;
        public const double BlackFrequency = 1500;
        public const double WhiteFrequency = 2300;

        public Demodulator(int sampleRate)
        {
            scanLineBandwidth = WhiteFrequency - BlackFrequency;
            frequencyModulation = new FrequencyModulation(scanLineBandwidth, sampleRate);
            double syncPulse5msSeconds = 0.005;
            double syncPulse9msSeconds = 0.009;
            double syncPulse20msSeconds = 0.020;
            double syncPulse5msMinSeconds = syncPulse5msSeconds / 2;
            double syncPulse5msMaxSeconds = (syncPulse5msSeconds + syncPulse9msSeconds) / 2;
            double syncPulse9msMaxSeconds = (syncPulse9msSeconds + syncPulse20msSeconds) / 2;
            double syncPulse20msMaxSeconds = syncPulse20msSeconds + syncPulse5msSeconds;
            syncPulse5msMinSamples = (int)Math.Round(syncPulse5msMinSeconds * sampleRate);
            syncPulse5msMaxSamples = (int)Math.Round(syncPulse5msMaxSeconds * sampleRate);
            syncPulse9msMaxSamples = (int)Math.Round(syncPulse9msMaxSeconds * sampleRate);
            syncPulse20msMaxSamples = (int)Math.Round(syncPulse20msMaxSeconds * sampleRate);
            double syncPulseFilterSeconds = syncPulse5msSeconds / 2;
            int syncPulseFilterSamples = (int)Math.Round(syncPulseFilterSeconds * sampleRate) | 1;
            syncPulseFilterDelay = (syncPulseFilterSamples - 1) / 2;
            syncPulseFilter = new SimpleMovingAverage(syncPulseFilterSamples);
            syncPulseValueDelay = new Delay(syncPulseFilterSamples);
            double lowestFrequency = 1000;
            double highestFrequency = 2800;
            double cutoffFrequency = (highestFrequency - lowestFrequency) / 2;
            double baseBandLowPassSeconds = 0.002;
            int baseBandLowPassSamples = (int)Math.Round(baseBandLowPassSeconds * sampleRate) | 1;
            baseBandLowPass = new ComplexConvolution(baseBandLowPassSamples);
            Kaiser kaiser = new Kaiser();
            for (int i = 0; i < baseBandLowPass.Length; ++i)
                baseBandLowPass.Taps[i] = (float)(kaiser.Window(2.0, i, baseBandLowPass.Length) * Filter.LowPass(cutoffFrequency, sampleRate, i, baseBandLowPass.Length));
            centerFrequency = (lowestFrequency + highestFrequency) / 2;
            baseBandOscillator = new Phasor(-centerFrequency, sampleRate);
            syncPulseFrequencyValue = (float)NormalizeFrequency(SyncPulseFrequency);
            syncPulseFrequencyTolerance = (float)(50 * 2 / scanLineBandwidth);
            double syncPorchFrequency = 1500;
            double syncHighFrequency = (SyncPulseFrequency + syncPorchFrequency) / 2;
            double syncLowFrequency = (SyncPulseFrequency + syncHighFrequency) / 2;
            double syncLowValue = NormalizeFrequency(syncLowFrequency);
            double syncHighValue = NormalizeFrequency(syncHighFrequency);
            syncPulseTrigger = new SchmittTrigger((float)syncLowValue, (float)syncHighValue);
            baseBand = new Complex();
        }

        private double NormalizeFrequency(double frequency)
        {
            return (frequency - centerFrequency) * 2 / scanLineBandwidth;
        }

        public bool Process(float[] buffer, int channelSelect)
        {
            bool syncPulseDetected = false;
            int channels = channelSelect > 0 ? 2 : 1;
            for (int i = 0; i < buffer.Length / channels; ++i)
            {
                switch (channelSelect)
                {
                    case 1:
                        baseBand.Set(buffer[2 * i]);
                        break;
                    case 2:
                        baseBand.Set(buffer[2 * i + 1]);
                        break;
                    case 3:
                        baseBand.Set(buffer[2 * i] + buffer[2 * i + 1]);
                        break;
                    case 4:
                        baseBand.Set(buffer[2 * i], buffer[2 * i + 1]);
                        break;
                    default:
                        baseBand.Set(buffer[i]);
                        break;
                }
                baseBand = baseBandLowPass.Push(baseBand.Mul(baseBandOscillator.Rotate()));
                float frequencyValue = frequencyModulation.Demod(baseBand);
                float syncPulseValue = syncPulseFilter.Avg(frequencyValue);
                float syncPulseDelayedValue = syncPulseValueDelay.Push(syncPulseValue);
                buffer[i] = frequencyValue;
                if (!syncPulseTrigger.Latch(syncPulseValue))
                {
                    ++syncPulseCounter;
                }
                else if (syncPulseCounter < syncPulse5msMinSamples || syncPulseCounter > syncPulse20msMaxSamples || Math.Abs(syncPulseDelayedValue - syncPulseFrequencyValue) > syncPulseFrequencyTolerance)
                {
                    syncPulseCounter = 0;
                }
                else
                {
                    if (syncPulseCounter < syncPulse5msMaxSamples)
                        SyncPulseWidthValue = SyncPulseWidth.FiveMilliSeconds;
                    else if (syncPulseCounter < syncPulse9msMaxSamples)
                        SyncPulseWidthValue = SyncPulseWidth.NineMilliSeconds;
                    else
                        SyncPulseWidthValue = SyncPulseWidth.TwentyMilliSeconds;
                    SyncPulseOffset = i - syncPulseFilterDelay;
                    FrequencyOffset = syncPulseDelayedValue - syncPulseFrequencyValue;
                    syncPulseDetected = true;
                    syncPulseCounter = 0;
                }
            }
            return syncPulseDetected;
        }
    }
}
