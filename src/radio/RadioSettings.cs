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

namespace HTCommander
{

    public class RadioSettings
    {
        private byte[] rawData;
        public int channel_a;
        public int channel_b;
        public bool scan;
        public bool aghfp_call_mode;
        public int double_channel;
        public int squelch_level; // 1 to 16
        public bool tail_elim;
        public bool auto_relay_en;
        public bool auto_power_on;
        public bool keep_aghfp_link;
        public int mic_gain;
        public int tx_hold_time;
        public int tx_time_limit;
        public int local_speaker; // 0 to 3
        public int bt_mic_gain; // 0 to 7
        public bool adaptive_response;
        public bool dis_tone;
        public bool power_saving_mode;
        public int auto_power_off; // 0 to 8
        public int auto_share_loc_ch; // 5 bits
        public int hm_speaker; // 2 bits
        public int positioning_system; // 4 bits
        public int time_offset; // 6 bits
        public bool use_freq_range_2;
        public bool ptt_lock;
        public bool leading_sync_bit_en;
        public bool pairing_at_power_on;
        public int screen_timeout; // 5 bits
        public int vfo_x; // 2 bits
        public bool imperial_unit;
        public int wx_mode; // 2 bits
        public int noaa_ch; // 4 bits
        public int vfol_tx_power_x; // 2 bits
        public int vfo2_tx_power_x; // 2 bits
        public bool dis_digital_mute;
        public bool signaling_ecc_en;
        public bool ch_data_lock;
        public int vfo1_mod_freq_x; // 4 bytes
        public int vfo2_mod_freq_x; // 4 bytes

        public RadioSettings(byte[] msg)
        {
            rawData = msg;

            channel_a = ((msg[5] & 0xF0) >> 4) + (msg[14] & 0xF0);
            channel_b = (msg[5] & 0x0F) + ((msg[14] & 0x0F) << 4);

            scan = (msg[6] & 0x80) != 0;
            aghfp_call_mode = (msg[6] & 0x40) != 0;
            double_channel = (msg[6] & 0x30) >> 4;
            squelch_level = (byte)(msg[6] & 0x0F);

            tail_elim = (msg[7] & 0x80) != 0;
            auto_relay_en = (msg[7] & 0x40) != 0;
            auto_power_on = (msg[7] & 0x20) != 0;
            keep_aghfp_link = (msg[7] & 0x10) != 0;
            mic_gain = (msg[7] & 0x0E) >> 1;
            tx_hold_time = ((msg[7] & 0x01) << 4) + ((msg[8] & 0xE0) >> 4);
            tx_time_limit = (msg[8] & 0x1F);

            local_speaker = msg[9] >> 6;
            bt_mic_gain = (msg[9] & 0x38) >> 3;
            adaptive_response = (msg[9] & 0x04) != 0;
            dis_tone = (msg[9] & 0x02) != 0;
            power_saving_mode = (msg[9] & 0x01) != 0;

            auto_power_off = msg[10] >> 4;
            auto_share_loc_ch = (msg[10] & 0x1F);

            hm_speaker = msg[11] >> 6;
            positioning_system = (msg[11] & 0x3C) >> 2;
            time_offset = ((msg[11] & 0x03) << 4) + ((msg[12] & 0xF0) >> 4);
            use_freq_range_2 = (msg[12] & 0x08) != 0;
            ptt_lock = (msg[12] & 0x04) != 0;
            leading_sync_bit_en = (msg[12] & 0x02) != 0;
            pairing_at_power_on = (msg[12] & 0x01) != 0;

            screen_timeout = msg[13] >> 3;
            vfo_x = (msg[13] & 0x06) >> 1;
            imperial_unit = (msg[13] & 0x01) != 0;

            wx_mode = msg[15] >> 6;
            noaa_ch = (msg[15] & 0x3C) >> 2;
            vfol_tx_power_x = (msg[15] & 0x03);

            vfo2_tx_power_x = (msg[16] >> 6);
            dis_digital_mute = (msg[16] & 0x20) != 0;
            signaling_ecc_en = (msg[16] & 0x10) != 0;
            ch_data_lock = (msg[16] & 0x08) != 0;

            vfo1_mod_freq_x = Utils.GetInt(msg, 17);
            vfo2_mod_freq_x = Utils.GetInt(msg, 21);
        }

        public byte[] ToByteArray()
        {
            byte[] buf = new byte[rawData.Length - 5];
            Array.Copy(rawData, 5, buf, 0, rawData.Length - 5);
            return buf;
        }

        public byte[] ToByteArray(int cha, int chb, int xdouble_channel, bool xscan, int xsquelch)
        {
            byte[] buf = new byte[rawData.Length - 5];
            Array.Copy(rawData, 5, buf, 0, rawData.Length - 5);
            buf[0] = (byte)(((cha & 0x0F) << 4) | (chb & 0x0F));
            buf[1] = (byte)((xscan ? 0x80 : 0) | (aghfp_call_mode ? 0x40 : 0) | ((xdouble_channel & 0x03) << 4) | (xsquelch & 0x0F));
            buf[9] = (byte)((cha & 0xF0) | ((chb & 0x0F) >> 4));
            return buf;
        }
    }

}
