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

using static HTCommander.Radio;

namespace HTCommander
{
    public class RadioHtStatus
    {
        // 2 first bytes
        public bool is_power_on;
        public bool is_in_tx;
        public bool is_sq;
        public bool is_in_rx;
        public RadioChannelType double_channel;
        public bool is_scan;
        public bool is_radio;
        public int curr_ch_id_lower;
        public bool is_gps_locked;
        public bool is_hfp_connected;
        public bool is_aoc_connected;
        public int channel_id;
        public string name_str;
        public int curr_ch_id;

        // Two next byte if present
        public int rssi;
        public int curr_region;
        public int curr_channel_id_upper;

        public RadioHtStatus(byte[] msg)
        {
            // Two first bytes
            is_power_on = (msg[5] & 0x80) != 0;
            is_in_tx = (msg[5] & 0x40) != 0;
            is_sq = (msg[5] & 0x20) != 0;
            is_in_rx = (msg[5] & 0x10) != 0;
            double_channel = (RadioChannelType)((msg[5] & 0x0C) >> 2);
            is_scan = (msg[5] & 0x02) != 0;
            is_radio = (msg[5] & 0x01) != 0;
            curr_ch_id_lower = (msg[6] >> 4);
            is_gps_locked = (msg[6] & 0x08) != 0;
            is_hfp_connected = (msg[6] & 0x04) != 0;
            is_aoc_connected = (msg[6] & 0x02) != 0;

            // Next two bytes
            if (msg.Length == 9)
            {
                rssi = (msg[7] >> 4); // 0 to 16
                curr_region = ((msg[7] & 0x0F) << 2) + (msg[8] >> 6);
                curr_channel_id_upper = ((msg[8] & 0x3C) >> 2);
            }

            curr_ch_id = (curr_channel_id_upper << 4) + curr_ch_id_lower;
        }
    }
}
