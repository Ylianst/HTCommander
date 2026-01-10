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

namespace HTCommander
{
    public class RadioDevInfo
    {
        public byte[] raw;
        public int vendor_id;
        public int product_id;
        public int hw_ver;
        public int soft_ver;
        public bool support_radio;
        public bool support_medium_power;
        public bool fixed_loc_speaker_vol;
        public bool not_support_soft_power_ctrl;
        public bool have_no_speaker;
        public bool have_hm_speaker;
        public int region_count;
        public bool support_noaa;
        public bool gmrs;
        public bool support_vfo;
        public bool support_dmr;
        public int channel_count;
        public int freq_range_count;

        public RadioDevInfo(byte[] msg)
        {
            raw = msg;
            vendor_id = msg[5];
            product_id = Utils.GetShort(msg, 6);
            hw_ver = msg[8];
            soft_ver = Utils.GetShort(msg, 9);
            support_radio = ((msg[11] & 0x80) != 0);
            support_medium_power = ((msg[11] & 0x40) != 0);
            fixed_loc_speaker_vol = ((msg[11] & 0x20) != 0);
            not_support_soft_power_ctrl = ((msg[11] & 0x10) != 0);
            have_no_speaker = ((msg[11] & 0x08) != 0);
            have_hm_speaker = ((msg[11] & 0x04) != 0);
            region_count = ((msg[11] & 0x03) << 4) + ((msg[12] & 0xF0) >> 4);
            support_noaa = ((msg[12] & 0x08) != 0);
            gmrs = ((msg[12] & 0x04) != 0);
            support_vfo = ((msg[12] & 0x02) != 0);
            support_dmr = ((msg[12] & 0x01) != 0);
            channel_count = msg[13];
            freq_range_count = (msg[14] & 0xF0) >> 4;
        }
    }
}
