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

using System.Text;

namespace HTCommander
{
    public class AX25Address
    {
        public string address;
        public int SSID;
        public bool CRBit;
        public string CallSignWithId { get { return address + "-" + SSID; } }

        private AX25Address() { }

        public static AX25Address GetAddress(string address, int SSID, bool response = false)
        {
            if ((address == null) || (address.Length > 6)) return null;
            if ((SSID > 15) || (SSID < 0)) return null;
            AX25Address r = new AX25Address();
            r.address = address;
            r.SSID = SSID;
            r.CRBit = response;
            return r;
        }

        public static AX25Address GetAddress(string address)
        {
            if ((address == null) || (address.Length > 9)) return null;
            int s = address.IndexOf('-');
            int ssid = 0;
            if (s == -1)
            {
                // No SSID, assume 0.
                if ((address == null) || (address.Length > 6)) return null;
            }
            else
            {
                if (s < 1) return null;
                string ssidstr = address.Substring(s + 1);
                if (int.TryParse(ssidstr, out ssid) == false) return null;
                if ((ssid > 15) || (ssid < 0)) return null;
                address = address.Substring(0, s);
            }
            if (address.Length == 0) return null;
            return AX25Address.GetAddress(address, ssid, false);
        }

        public static AX25Address DecodeAX25Address(byte[] data, int index, out bool last)
        {
            last = false;
            if (index + 7 > data.Length) return null;
            StringBuilder address = new StringBuilder();
            int i;
            for (i = 0; i < 6; i++)
            {
                char c = (char)(data[index + i] >> 1);
                if (c < 0x20) return null;
                if (c != 0x20) { address.Append(c); }
                if ((data[index + i] & 0x01) != 0) return null;
            }
            bool response = ((data[index + 6] & 0x80) != 0);
            int SSID = (data[index + 6] >> 1) & 0x0F;
            last = ((data[index + 6] & 0x01) != 0);
            return AX25Address.GetAddress(address.ToString(), SSID, response);
        }

        public byte[] ToByteArray(bool last)
        {
            if ((address == null) || (address.Length > 6)) return null;
            if ((SSID > 15) || (SSID < 0)) return null;
            byte[] rdata = new byte[7];
            string addressPadded = address;
            while (addressPadded.Length < 6) { addressPadded += (char)0x20; }
            for (int i = 0; i < 6; i++) { rdata[i] = (byte)(addressPadded[i] << 1); }
            rdata[6] = (byte)(SSID << 1);
            if (CRBit) { rdata[6] |= 0x80; }
            if (last) { rdata[6] |= 0x01; }
            return rdata;
        }

        public override string ToString()
        {
            if (SSID == 0) return address;
            return address + "-" + SSID;
        }
    }
}
