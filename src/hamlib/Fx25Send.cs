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
// Fx25Send.cs - FX.25 frame transmission with Reed-Solomon FEC
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// FX.25 frame transmission - converts HDLC frames to FX.25 encoded bit stream
    /// </summary>
    public class Fx25Send
    {
        private const int MaxRadioChannels = 16;
        
        private GenTone _genTone;
        private int[] _numberOfBitsSent;
        private int[] _nrziOutput;

        public Fx25Send()
        {
            _numberOfBitsSent = new int[MaxRadioChannels];
            _nrziOutput = new int[MaxRadioChannels];
        }

        /// <summary>
        /// Initialize the FX.25 send module with a tone generator
        /// </summary>
        public void Init(GenTone genTone)
        {
            _genTone = genTone;
            Array.Clear(_numberOfBitsSent, 0, _numberOfBitsSent.Length);
            Array.Clear(_nrziOutput, 0, _nrziOutput.Length);
        }

        /// <summary>
        /// Convert HDLC frames to a stream of bits with FX.25 encoding
        /// </summary>
        public int SendFrame(int chan, byte[] fbuf, int flen, int fxMode)
        {
            if (_genTone == null)
            {
                Console.WriteLine("FX.25 Send: GenTone not initialized!");
                return -1;
            }

            if (Fx25.GetDebugLevel() >= 3)
            {
                Console.WriteLine("------");
                Console.WriteLine($"FX.25[{chan}] send frame: FX.25 mode = {fxMode}");
                Fx25.HexDump(fbuf, flen);
            }

            _numberOfBitsSent[chan] = 0;

            // If the frame buffer is not large enough to hold the FCS, expand it
            if (fbuf.Length < (flen + 2))
            {
                byte[] fbuf2 = new byte[flen + 2];
                Array.Copy(fbuf, fbuf2, flen);
                fbuf = fbuf2;
            }

            ushort fcs = FcsCalc.Calculate(fbuf, flen);
            fbuf[flen++] = (byte)(fcs & 0xff);
            fbuf[flen++] = (byte)((fcs >> 8) & 0xff);

            byte[] data = new byte[Fx25.FX25_MAX_DATA + 1];
            const byte fence = 0xaa;
            data[Fx25.FX25_MAX_DATA] = fence;

            int dlen = StuffIt(fbuf, flen, data, Fx25.FX25_MAX_DATA);

            Debug.Assert(data[Fx25.FX25_MAX_DATA] == fence);
            if (dlen < 0)
            {
                Console.WriteLine($"FX.25[{chan}]: Frame length of {flen} + overhead is too large to encode.");
                return -1;
            }

            int ctagNum = Fx25.PickMode(fxMode, dlen);

            if (ctagNum < Fx25.CTAG_MIN || ctagNum > Fx25.CTAG_MAX)
            {
                Console.WriteLine($"FX.25[{chan}]: Could not find suitable format for requested {fxMode} and data length {dlen}.");
                return -1;
            }

            ulong ctagValue = Fx25.GetCtagValue(ctagNum);

            int kDataRadio = Fx25.GetKDataRadio(ctagNum);
            int kDataRs = Fx25.GetKDataRs(ctagNum);
            int shortenBy = Fx25.FX25_MAX_DATA - kDataRadio;
            if (shortenBy > 0)
            {
                Array.Clear(data, kDataRadio, shortenBy);
            }

            byte[] check = new byte[Fx25.FX25_MAX_CHECK + 1];
            check[Fx25.FX25_MAX_CHECK] = fence;
            ReedSolomonCodec rs = Fx25.GetRs(ctagNum);

            Debug.Assert(kDataRs + Fx25.GetNRoots(ctagNum) == Fx25.FX25_BLOCK_SIZE);

            Fx25Encode.EncodeRs(rs, data, check);
            Debug.Assert(check[Fx25.FX25_MAX_CHECK] == fence);

            if (Fx25.GetDebugLevel() >= 3)
            {
                Console.WriteLine($"FX.25[{chan}]: transmit {kDataRadio} data bytes, ctag number 0x{ctagNum:X2}");
                Fx25.HexDump(data, kDataRadio);
                Console.WriteLine($"FX.25[{chan}]: transmit {Fx25.GetNRoots(ctagNum)} check bytes:");
                Fx25.HexDump(check, Fx25.GetNRoots(ctagNum));
                Console.WriteLine("------");
            }

            for (int k = 0; k < 8; k++)
            {
                byte b = (byte)((ctagValue >> (k * 8)) & 0xff);
                SendBytes(chan, new byte[] { b }, 1);
            }

            SendBytes(chan, data, kDataRadio);
            SendBytes(chan, check, Fx25.GetNRoots(ctagNum));

            return _numberOfBitsSent[chan];
        }

        private void SendBytes(int chan, byte[] b, int count)
        {
            for (int j = 0; j < count; j++)
            {
                byte x = b[j];
                for (int k = 0; k < 8; k++)
                {
                    SendBit(chan, x & 0x01);
                    x >>= 1;
                }
            }
        }

        private void SendBit(int chan, int b)
        {
            if (b == 0)
            {
                _nrziOutput[chan] = _nrziOutput[chan] == 0 ? 1 : 0;
            }

            _genTone?.PutBit(chan, _nrziOutput[chan]);
            _numberOfBitsSent[chan]++;
        }

        private int StuffIt(byte[] inData, int ilen, byte[] outData, int osize)
        {
            const byte flag = 0x7e;
            Array.Clear(outData, 0, osize);
            outData[0] = flag;
            int olen = 8;
            int osizeBits = osize * 8;
            int ones = 0;

            for (int i = 0; i < ilen; i++)
            {
                for (byte imask = 1; imask != 0; imask <<= 1)
                {
                    int v = (inData[i] & imask) != 0 ? 1 : 0;
                    
                    if (olen >= osizeBits) return -1;
                    if (v != 0)
                        outData[olen >> 3] |= (byte)(1 << (olen & 0x7));
                    olen++;
                    
                    if (v != 0)
                    {
                        ones++;
                        if (ones == 5)
                        {
                            if (olen >= osizeBits) return -1;
                            olen++;
                            ones = 0;
                        }
                    }
                    else
                    {
                        ones = 0;
                    }
                }
            }

            for (byte imask = 1; imask != 0; imask <<= 1)
            {
                if (olen >= osizeBits) return -1;
                if ((flag & imask) != 0)
                    outData[olen >> 3] |= (byte)(1 << (olen & 0x7));
                olen++;
            }

            int ret = (olen + 7) / 8;

            byte imask2 = 1;
            while (olen < osizeBits)
            {
                if ((flag & imask2) != 0)
                    outData[olen >> 3] |= (byte)(1 << (olen & 0x7));
                olen++;
                imask2 = (byte)((imask2 << 1) | (imask2 >> 7));
            }

            return ret;
        }
    }
}
