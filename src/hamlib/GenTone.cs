/*
Copyright 2025 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// GenTone.cs - AFSK tone generation for encoding
//

using System;

namespace HamLib
{
    /// <summary>
    /// Generates AFSK tones for audio encoding
    /// </summary>
    public class GenTone
    {
        private const double TicksPerCycle = 256.0 * 256.0 * 256.0 * 256.0;
        private const uint PhaseShift180 = 128u << 24;
        private const uint PhaseShift90 = 64u << 24;
        private const uint PhaseShift45 = 32u << 24;

        private AudioConfig _audioConfig;
        private AudioBuffer _audioBuffer;
        private short[] _sineTable;
        private int _amp16bit;

        // Per-channel state
        private int[] _ticksPerSample;
        private int[] _ticksPerBit;
        private int[] _f1ChangePerSample;
        private int[] _f2ChangePerSample;
        private float[] _samplesPerSymbol;
        private uint[] _tonePhase;
        private int[] _bitLenAcc;
        private int[] _lfsr;
        private int[] _bitCount;
        private int[] _saveBit;
        private int[] _prevDat;

        public GenTone(AudioBuffer audioBuffer)
        {
            _audioBuffer = audioBuffer;
            _sineTable = new short[256];
            _ticksPerSample = new int[AudioConfig.MaxRadioChannels];
            _ticksPerBit = new int[AudioConfig.MaxRadioChannels];
            _f1ChangePerSample = new int[AudioConfig.MaxRadioChannels];
            _f2ChangePerSample = new int[AudioConfig.MaxRadioChannels];
            _samplesPerSymbol = new float[AudioConfig.MaxRadioChannels];
            _tonePhase = new uint[AudioConfig.MaxRadioChannels];
            _bitLenAcc = new int[AudioConfig.MaxRadioChannels];
            _lfsr = new int[AudioConfig.MaxRadioChannels];
            _bitCount = new int[AudioConfig.MaxRadioChannels];
            _saveBit = new int[AudioConfig.MaxRadioChannels];
            _prevDat = new int[AudioConfig.MaxRadioChannels];
        }

        /// <summary>
        /// Initialize tone generator
        /// </summary>
        public void Init(AudioConfig audioConfig, int amp)
        {
            _audioConfig = audioConfig;
            _amp16bit = (int)((32767 * amp) / 100);

            for (int chan = 0; chan < AudioConfig.MaxRadioChannels; chan++)
            {
                if (_audioConfig.ChannelMedium[chan] == Medium.Radio)
                {
                    int a = AudioConfig.ChannelToDevice(chan);

                    _tonePhase[chan] = 0;
                    _bitLenAcc[chan] = 0;
                    _lfsr[chan] = 0;
                    _bitCount[chan] = 0;
                    _saveBit[chan] = 0;
                    _prevDat[chan] = 0;

                    _ticksPerSample[chan] = (int)((TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);

                    var chanConfig = _audioConfig.Channels[chan];

                    switch (chanConfig.ModemType)
                    {
                        case ModemType.Qpsk:
                            chanConfig.MarkFreq = 1800;
                            chanConfig.SpaceFreq = chanConfig.MarkFreq;
                            _ticksPerBit[chan] = (int)((TicksPerCycle / ((double)chanConfig.Baud * 0.5)) + 0.5);
                            _f1ChangePerSample[chan] = (int)(((double)chanConfig.MarkFreq * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            _f2ChangePerSample[chan] = _f1ChangePerSample[chan];
                            _samplesPerSymbol[chan] = 2.0f * (float)_audioConfig.Devices[a].SamplesPerSec / (float)chanConfig.Baud;
                            _tonePhase[chan] = PhaseShift45;
                            break;

                        case ModemType.Psk8:
                            chanConfig.MarkFreq = 1800;
                            chanConfig.SpaceFreq = chanConfig.MarkFreq;
                            _ticksPerBit[chan] = (int)((TicksPerCycle / ((double)chanConfig.Baud / 3.0)) + 0.5);
                            _f1ChangePerSample[chan] = (int)(((double)chanConfig.MarkFreq * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            _f2ChangePerSample[chan] = _f1ChangePerSample[chan];
                            _samplesPerSymbol[chan] = 3.0f * (float)_audioConfig.Devices[a].SamplesPerSec / (float)chanConfig.Baud;
                            break;

                        case ModemType.Baseband:
                        case ModemType.Scramble:
                        case ModemType.Ais:
                            _ticksPerBit[chan] = (int)((TicksPerCycle / (double)chanConfig.Baud) + 0.5);
                            _f1ChangePerSample[chan] = (int)(((double)chanConfig.Baud * 0.5 * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            _samplesPerSymbol[chan] = (float)_audioConfig.Devices[a].SamplesPerSec / (float)chanConfig.Baud;
                            break;

                        case ModemType.Eas:
                            _ticksPerBit[chan] = (int)((TicksPerCycle / 520.833333333333) + 0.5);
                            _samplesPerSymbol[chan] = (int)((_audioConfig.Devices[a].SamplesPerSec / 520.83333) + 0.5);
                            _f1ChangePerSample[chan] = (int)((2083.33333333333 * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            _f2ChangePerSample[chan] = (int)((1562.5000000 * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            break;

                        default: // AFSK
                            _ticksPerBit[chan] = (int)((TicksPerCycle / (double)chanConfig.Baud) + 0.5);
                            _samplesPerSymbol[chan] = (float)_audioConfig.Devices[a].SamplesPerSec / (float)chanConfig.Baud;
                            _f1ChangePerSample[chan] = (int)(((double)chanConfig.MarkFreq * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            _f2ChangePerSample[chan] = (int)(((double)chanConfig.SpaceFreq * TicksPerCycle / (double)_audioConfig.Devices[a].SamplesPerSec) + 0.5);
                            break;
                    }
                }
            }

            // Generate sine table
            for (int j = 0; j < 256; j++)
            {
                double a = ((double)j / 256.0) * (2 * Math.PI);
                int s = (int)(Math.Sin(a) * 32767 * amp / 100.0);

                if (s < -32768)
                {
                    s = -32768;
                }
                else if (s > 32767)
                {
                    s = 32767;
                }
                _sineTable[j] = (short)s;
            }
        }

        /// <summary>
        /// Generate tone for one data bit
        /// </summary>
        public void PutBit(int chan, int dat)
        {
            int a = AudioConfig.ChannelToDevice(chan);

            if (_audioConfig.ChannelMedium[chan] != Medium.Radio)
            {
                Console.WriteLine($"Invalid channel {chan} for tone generation.");
                return;
            }

            if (dat < 0)
            {
                // Hack to test receive PLL recovery
                _bitLenAcc[chan] -= _ticksPerBit[chan];
                dat = 0;
            }

            var chanConfig = _audioConfig.Channels[chan];

            // Handle multi-bit symbols for QPSK and 8PSK
            if (chanConfig.ModemType == ModemType.Qpsk)
            {
                dat &= 1;
                if ((_bitCount[chan] & 1) == 0)
                {
                    _saveBit[chan] = dat;
                    _bitCount[chan]++;
                    return;
                }

                int dibit = (_saveBit[chan] << 1) | dat;
                int[] gray2phase = { 0, 1, 3, 2 };
                int symbol = gray2phase[dibit];
                _tonePhase[chan] += (uint)(symbol * PhaseShift90);
                if (chanConfig.V26Alt == V26Alternative.B)
                {
                    _tonePhase[chan] += PhaseShift45;
                }
                _bitCount[chan]++;
            }
            else if (chanConfig.ModemType == ModemType.Psk8)
            {
                dat &= 1;
                if (_bitCount[chan] < 2)
                {
                    _saveBit[chan] = (_saveBit[chan] << 1) | dat;
                    _bitCount[chan]++;
                    return;
                }

                int tribit = (_saveBit[chan] << 1) | dat;
                int[] gray2phase = { 1, 0, 2, 3, 6, 7, 5, 4 };
                int symbol = gray2phase[tribit];
                _tonePhase[chan] += (uint)(symbol * PhaseShift45);
                _saveBit[chan] = 0;
                _bitCount[chan] = 0;
            }

            // Scrambler for certain modes
            if (chanConfig.ModemType == ModemType.Scramble &&
                chanConfig.Layer2Xmit != Layer2Type.Il2p)
            {
                int x = (dat ^ (_lfsr[chan] >> 16) ^ (_lfsr[chan] >> 11)) & 1;
                _lfsr[chan] = (_lfsr[chan] << 1) | (x & 1);
                dat = x;
            }

            // Generate audio samples for this bit
            do
            {
                int sam;

                switch (chanConfig.ModemType)
                {
                    case ModemType.Afsk:
                        _tonePhase[chan] += (uint)(dat != 0 ? _f1ChangePerSample[chan] : _f2ChangePerSample[chan]);
                        sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
                        PutSample(chan, a, sam);
                        break;

                    case ModemType.Eas:
                        _tonePhase[chan] += (uint)(dat != 0 ? _f1ChangePerSample[chan] : _f2ChangePerSample[chan]);
                        sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
                        PutSample(chan, a, sam);
                        break;

                    case ModemType.Qpsk:
                    case ModemType.Psk8:
                        _tonePhase[chan] += (uint)_f1ChangePerSample[chan];
                        sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
                        PutSample(chan, a, sam);
                        break;

                    case ModemType.Baseband:
                    case ModemType.Scramble:
                    case ModemType.Ais:
                        if (dat != _prevDat[chan])
                        {
                            _tonePhase[chan] += (uint)_f1ChangePerSample[chan];
                        }
                        else
                        {
                            if ((_tonePhase[chan] & 0x80000000) != 0)
                                _tonePhase[chan] = 0xc0000000; // 270 degrees
                            else
                                _tonePhase[chan] = 0x40000000; // 90 degrees
                        }
                        sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
                        PutSample(chan, a, sam);
                        break;

                    default:
                        Console.WriteLine($"INTERNAL ERROR: Modem type {chanConfig.ModemType} not implemented");
                        return;
                }

                _bitLenAcc[chan] += _ticksPerSample[chan];
            }
            while (_bitLenAcc[chan] < _ticksPerBit[chan]);

            _bitLenAcc[chan] -= _ticksPerBit[chan];
            _prevDat[chan] = dat;
        }

        /// <summary>
        /// Generate quiet period (silence)
        /// </summary>
        public void PutQuietMs(int chan, int timeMs)
        {
            int a = AudioConfig.ChannelToDevice(chan);
            int sam = 0;
            int nsamples = (int)((timeMs * (float)_audioConfig.Devices[a].SamplesPerSec / 1000.0) + 0.5);

            for (int j = 0; j < nsamples; j++)
            {
                PutSample(chan, a, sam);
            }

            // Avoid abrupt change when it starts up again
            _tonePhase[chan] = 0;
        }

        /// <summary>
        /// Put a single audio sample
        /// </summary>
        private void PutSample(int chan, int device, int sample)
        {
            // Clamp to 16-bit range
            if (sample < -32768) sample = -32768;
            if (sample > 32767) sample = 32767;

            _audioBuffer.Put(device, (short)sample);
        }
    }
}
