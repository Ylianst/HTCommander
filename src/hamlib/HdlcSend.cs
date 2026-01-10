/*
Copyright 2026 Ylian Saint-Hilaire

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
// HdlcSend.cs - HDLC frame encoding and transmission
//

using System;

namespace HamLib
{
    /// <summary>
    /// HDLC frame encoder for transmitting data
    /// </summary>
    public class HdlcSend
    {
        private GenTone _genTone;
        private AudioConfig _audioConfig;
        private int[] _stuff;
        private int[] _output;
        private int[] _numberBitsSent;

        public HdlcSend(GenTone genTone, AudioConfig audioConfig)
        {
            _genTone = genTone;
            _audioConfig = audioConfig;
            _stuff = new int[AudioConfig.MaxRadioChannels];
            _output = new int[AudioConfig.MaxRadioChannels];
            _numberBitsSent = new int[AudioConfig.MaxRadioChannels];
        }

        /// <summary>
        /// Send a complete frame (wrapper for different layer 2 protocols)
        /// </summary>
        public int SendFrame(int chan, byte[] frameBuffer, int frameLen, bool badFcs)
        {
            // For now, we only support standard AX.25 HDLC
            // FX.25 and IL2P could be added later
            return SendAx25Frame(chan, frameBuffer, frameLen, badFcs);
        }

        /// <summary>
        /// Send an AX.25 HDLC frame
        /// </summary>
        private int SendAx25Frame(int chan, byte[] fbuf, int flen, bool badFcs)
        {
            _numberBitsSent[chan] = 0;

            // Start flag
            SendControlNrzi(chan, 0x7e);

            // Data bytes
            for (int j = 0; j < flen; j++)
            {
                SendDataNrzi(chan, fbuf[j]);
            }

            // FCS (Frame Check Sequence)
            ushort fcs = FcsCalc.Calculate(fbuf, flen);

            if (badFcs)
            {
                // For testing - corrupt the FCS
                SendDataNrzi(chan, (byte)((~fcs) & 0xff));
                SendDataNrzi(chan, (byte)(((~fcs) >> 8) & 0xff));
            }
            else
            {
                SendDataNrzi(chan, (byte)(fcs & 0xff));
                SendDataNrzi(chan, (byte)((fcs >> 8) & 0xff));
            }

            // End flag
            SendControlNrzi(chan, 0x7e);

            return _numberBitsSent[chan];
        }

        /// <summary>
        /// Send preamble or postamble flags
        /// </summary>
        public int SendFlags(int chan, int numFlags, bool finish, Action<int> audioFlushCallback)
        {
            _numberBitsSent[chan] = 0;

            // For AX.25, send 0x7e flags
            for (int j = 0; j < numFlags; j++)
            {
                SendControlNrzi(chan, 0x7e);
            }

            // Flush audio buffer if this is the end
            if (finish && audioFlushCallback != null)
            {
                audioFlushCallback(AudioConfig.ChannelToDevice(chan));
            }

            return _numberBitsSent[chan];
        }

        /// <summary>
        /// Send a control byte (like flags) - no bit stuffing, uses NRZI
        /// </summary>
        private void SendControlNrzi(int chan, int x)
        {
            for (int i = 0; i < 8; i++)
            {
                SendBitNrzi(chan, x & 1);
                x >>= 1;
            }
            _stuff[chan] = 0;
        }

        /// <summary>
        /// Send a data byte with bit stuffing and NRZI encoding
        /// </summary>
        private void SendDataNrzi(int chan, int x)
        {
            for (int i = 0; i < 8; i++)
            {
                SendBitNrzi(chan, x & 1);
                if ((x & 1) != 0)
                {
                    _stuff[chan]++;
                    if (_stuff[chan] == 5)
                    {
                        // Insert a 0 bit after five consecutive 1 bits
                        SendBitNrzi(chan, 0);
                        _stuff[chan] = 0;
                    }
                }
                else
                {
                    _stuff[chan] = 0;
                }
                x >>= 1;
            }
        }

        /// <summary>
        /// Send a single bit with NRZI encoding
        /// NRZI: data 1 bit -> no change, data 0 bit -> invert signal
        /// </summary>
        private void SendBitNrzi(int chan, int b)
        {
            if (b == 0)
            {
                _output[chan] = _output[chan] == 0 ? 1 : 0;
            }

            // Generate the tone
            _genTone.PutBit(chan, _output[chan]);

            _numberBitsSent[chan]++;
        }
    }
}
