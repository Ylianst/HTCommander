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

using System;
using System.Text;
using System.Collections.Generic;

namespace HTCommander
{
    public class AX25Packet
    {
        public int format;
        public List<AX25Address> addresses;
        public int control;
        public int pid;
        public string payload;
        public DateTime time;
        public bool confirmed;
        public int messageId;

        public AX25Packet(int format, List<AX25Address> addresses, int control, int pid, string payload, DateTime time)
        {
            this.format = format;
            this.addresses = addresses;
            this.control = control;
            this.pid = pid;
            this.payload = payload;
            this.time = time;
        }

        public static AX25Packet DecodeAX25Packet(byte[] data, DateTime time)
        {
            //string hex = BytesToHex(data);

            if (data[0] == 1)
            {
                // This is an odd packet, not sure if it's AX25 at all
                if (data.Length < 6) return null;
                int callsignLen = data[1];
                if (data.Length < (3 + callsignLen)) return null;
                int controlLen = data[2 + callsignLen];
                if (data.Length < (4 + callsignLen + controlLen)) return null;
                int messageLen = data[3 + callsignLen + controlLen];
                List<AX25Address> addresses = new List<AX25Address>();
                addresses.Add(AX25Address.GetAddress(UTF8Encoding.Default.GetString(data, 3, callsignLen - 1), 0, false));
                string payload = UTF8Encoding.Default.GetString(data, 5 + callsignLen + controlLen, messageLen - 1);
                return new AX25Packet(1, addresses, data[3 + callsignLen], 0, payload, time);
            }
            else
            {
                // This is a typical AX25 packet. Decode the headers
                int i = 0;
                bool done = false;
                List<AX25Address> addresses = new List<AX25Address>();
                do
                {
                    bool last;
                    AX25Address addr = AX25Address.DecodeAX25Address(data, i, out last);
                    if (addr == null) return null;
                    addresses.Add(addr);
                    done = last;
                    i += 7;
                } while (!done);

                // Decode control and pid data.
                int control = data[i];
                i++;
                int pid = 0;
                if (data.Length > i) { pid = data[i]; }
                i++;

                string payload = null;
                if (data.Length > i)
                {
                    payload = UTF8Encoding.UTF8.GetString(data, i, data.Length - i);
                }
                else
                {
                    payload = "";
                }
                string firstAddressRaw = ASCIIEncoding.ASCII.GetString(data, 0, 7);
                return new AX25Packet(0, addresses, control, pid, payload, time);
            }
        }

        public byte[] ToByteArray()
        {
            if ((addresses == null) || (addresses.Count == 0)) return null;
            if ((format == 1) && (addresses != null) && (addresses.Count == 1))
            {
                byte[] callsignBytes = UTF8Encoding.UTF8.GetBytes(" " + addresses[0].address);
                byte[] payloadBytes = UTF8Encoding.UTF8.GetBytes("$" + payload);
                byte[] rdata = new byte[5 + callsignBytes.Length + payloadBytes.Length];
                rdata[0] = 1;
                rdata[1] = (byte)callsignBytes.Length;
                Array.Copy(callsignBytes, 0, rdata, 2, callsignBytes.Length);
                rdata[2 + callsignBytes.Length] = 1;
                rdata[3 + callsignBytes.Length] = 0x21;
                rdata[4 + callsignBytes.Length] = (byte)payloadBytes.Length;
                Array.Copy(payloadBytes, 0, rdata, 5 + callsignBytes.Length, payloadBytes.Length);
                return rdata;
            }
            else if ((format == 0) && (addresses != null) && (addresses.Count >= 2))
            {
                byte[] payloadBytes = UTF8Encoding.UTF8.GetBytes(payload);
                int packetSize = (7 * addresses.Count) + 2 + payloadBytes.Length;
                byte[] rdata = new byte[packetSize];
                int i = 0;
                for (int j = 0; j < addresses.Count; j++)
                {
                    AX25Address a = addresses[j];
                    byte[] ab = a.ToByteArray(j == (addresses.Count - 1));
                    Array.Copy(ab, 0, rdata, i, 7);
                    i += 7;
                }
                rdata[i++] = (byte)(control >> 8);
                rdata[i++] = (byte)(control & 0xFF);
                Array.Copy(payloadBytes, 0, rdata, i, payloadBytes.Length);
                return rdata;
            }
            return null;
        }

        public override string ToString()
        {
            string r = "";
            foreach (AX25Address a in addresses) { r += "[" + a.ToString() + "]"; }
            r += ": " + payload;
            return r;
        }
    }

}
