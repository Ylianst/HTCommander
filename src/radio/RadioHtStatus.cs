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

using System;
using static HTCommander.Radio;

namespace HTCommander
{
    public class RadioHtStatus
    {
        public byte[] raw;

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
            raw = msg;

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

        public RadioHtStatus(RadioHtStatus other)
        {
            if (other == null)
                throw new ArgumentNullException(nameof(other));

            // Two first bytes
            is_power_on = other.is_power_on;
            is_in_tx = other.is_in_tx;
            is_sq = other.is_sq;
            is_in_rx = other.is_in_rx;
            double_channel = other.double_channel;
            is_scan = other.is_scan;
            is_radio = other.is_radio;
            curr_ch_id_lower = other.curr_ch_id_lower;
            is_gps_locked = other.is_gps_locked;
            is_hfp_connected = other.is_hfp_connected;
            is_aoc_connected = other.is_aoc_connected;
            channel_id = other.channel_id;
            name_str = other.name_str; // Strings are immutable, so direct assignment is fine
            curr_ch_id = other.curr_ch_id;

            // Next two bytes
            rssi = other.rssi;
            curr_region = other.curr_region;
            curr_channel_id_upper = other.curr_channel_id_upper;
        }

        public byte[] ToByteArray()
        {
            byte[] msg = new byte[4];

            // Serialize the first two bytes
            msg[0] = 0;
            msg[0] |= (byte)(is_power_on ? 0x80 : 0x00);
            msg[0] |= (byte)(is_in_tx ? 0x40 : 0x00);
            msg[0] |= (byte)(is_sq ? 0x20 : 0x00);
            msg[0] |= (byte)(is_in_rx ? 0x10 : 0x00);
            msg[0] |= (byte)((int)double_channel << 2);
            msg[0] |= (byte)(is_scan ? 0x02 : 0x00);
            msg[0] |= (byte)(is_radio ? 0x01 : 0x00);

            msg[1] = 0;
            msg[1] |= (byte)(curr_ch_id_lower << 4);
            msg[1] |= (byte)(is_gps_locked ? 0x08 : 0x00);
            msg[1] |= (byte)(is_hfp_connected ? 0x04 : 0x00);
            msg[1] |= (byte)(is_aoc_connected ? 0x02 : 0x00);

            // Serialize the next two bytes if values are present
            msg[2] = 0;
            msg[2] |= (byte)(rssi << 4);
            msg[2] |= (byte)((curr_region >> 2) & 0x0F);

            msg[3] = 0;
            msg[3] |= (byte)((curr_region & 0x03) << 6);
            msg[3] |= (byte)((curr_channel_id_upper << 2) & 0x3C);

            return msg;
        }
    }
}
