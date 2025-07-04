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
using static HTCommander.Radio;

namespace HTCommander
{
    public class RadioChannelInfo
    {
        public byte[] raw;
        public int channel_id;
        public RadioModulationType tx_mod;
        public int tx_freq;
        public RadioModulationType rx_mod;
        public int rx_freq;
        public int tx_sub_audio;
        public int rx_sub_audio;
        public bool scan;
        public bool tx_at_max_power;
        public bool talk_around;
        public RadioBandwidthType bandwidth;
        public bool pre_de_emph_bypass;
        public bool sign;
        public bool tx_at_med_power;
        public bool tx_disable;
        public bool fixed_freq;
        public bool fixed_bandwidth;
        public bool fixed_tx_power;
        public bool mute;
        public string name_str;

        public RadioChannelInfo() { }

        public RadioChannelInfo(byte[] msg)
        {
            raw = msg;
            channel_id = msg[5];
            tx_mod = (RadioModulationType)(msg[6] >> 6);
            tx_freq = Utils.GetInt(msg, 6) & 0x3FFFFFFF;
            rx_mod = (RadioModulationType)(msg[10] >> 6);
            rx_freq = Utils.GetInt(msg, 10) & 0x3FFFFFFF;
            tx_sub_audio = Utils.GetShort(msg, 14);
            rx_sub_audio = Utils.GetShort(msg, 16);
            scan = ((msg[18] & 0x80) != 0);
            tx_at_max_power = ((msg[18] & 0x40) != 0);
            talk_around = ((msg[18] & 0x20) != 0);
            bandwidth = ((msg[18] & 0x10) != 0) ? RadioBandwidthType.WIDE : RadioBandwidthType.NARROW;
            pre_de_emph_bypass = ((msg[18] & 0x08) != 0);
            sign = ((msg[18] & 0x04) != 0);
            tx_at_med_power = ((msg[18] & 0x02) != 0);
            tx_disable = ((msg[18] & 0x01) != 0);
            fixed_freq = ((msg[19] & 0x80) != 0);
            fixed_bandwidth = ((msg[19] & 0x40) != 0);
            fixed_tx_power = ((msg[19] & 0x20) != 0);
            mute = ((msg[19] & 0x10) != 0);
            name_str = UTF8Encoding.Default.GetString(msg, 20, 10).Trim();
            int i = name_str.IndexOf("\0");
            if (i >= 0) { name_str = name_str.Substring(0, i); }
        }

        public RadioChannelInfo(RadioChannelInfo other)
        {
            if (other == null) throw new ArgumentNullException(nameof(other));
            channel_id = other.channel_id;
            tx_mod = other.tx_mod;
            tx_freq = other.tx_freq;
            rx_mod = other.rx_mod;
            rx_freq = other.rx_freq;
            tx_sub_audio = other.tx_sub_audio;
            rx_sub_audio = other.rx_sub_audio;
            scan = other.scan;
            tx_at_max_power = other.tx_at_max_power;
            talk_around = other.talk_around;
            bandwidth = other.bandwidth;
            pre_de_emph_bypass = other.pre_de_emph_bypass;
            sign = other.sign;
            tx_at_med_power = other.tx_at_med_power;
            tx_disable = other.tx_disable;
            fixed_freq = other.fixed_freq;
            fixed_bandwidth = other.fixed_bandwidth;
            fixed_tx_power = other.fixed_tx_power;
            mute = other.mute;
            name_str = other.name_str;
        }

        public byte[] ToByteArray()
        {
            byte[] r = new byte[25];
            r[0] = (byte)channel_id;
            Utils.SetInt(r, 1, (int)tx_freq);
            r[1] += (byte)(((int)tx_mod & 0x03) << 6);
            Utils.SetInt(r, 5, (int)rx_freq);
            r[5] += (byte)(((int)rx_mod & 0x03) << 6);
            Utils.SetShort(r, 9, (int)tx_sub_audio);
            Utils.SetShort(r, 11, (int)rx_sub_audio);

            if (scan) { r[13] |= 0x80; }
            if (tx_at_max_power) { r[13] |= 0x40; }
            if (talk_around) { r[13] |= 0x20; }
            if (bandwidth == RadioBandwidthType.WIDE) { r[13] |= 0x10; }
            if (pre_de_emph_bypass) { r[13] |= 0x08; }
            if (sign) { r[13] |= 0x04; }
            if (tx_at_med_power) { r[13] |= 0x02; }
            if (tx_disable) { r[13] |= 0x01; }
            if (fixed_freq) { r[14] |= 0x80; }
            if (fixed_bandwidth) { r[14] |= 0x40; }
            if (fixed_tx_power) { r[14] |= 0x20; }
            if (mute) { r[14] |= 0x10; }

            byte[] nameBuf = UTF8Encoding.Default.GetBytes(name_str);
            int nameLen = nameBuf.Length;
            if (nameLen > 10) { nameLen = 10; }
            Array.Copy(nameBuf, 0, r, 15, nameLen);

            return r;
        }

        public override bool Equals(object obj)
        {
            if (obj is RadioChannelInfo other)
            {
                return channel_id == other.channel_id &&
                       tx_mod == other.tx_mod &&
                       tx_freq == other.tx_freq &&
                       rx_mod == other.rx_mod &&
                       rx_freq == other.rx_freq &&
                       tx_sub_audio == other.tx_sub_audio &&
                       rx_sub_audio == other.rx_sub_audio &&
                       scan == other.scan &&
                       tx_at_max_power == other.tx_at_max_power &&
                       talk_around == other.talk_around &&
                       bandwidth == other.bandwidth &&
                       pre_de_emph_bypass == other.pre_de_emph_bypass &&
                       sign == other.sign &&
                       tx_at_med_power == other.tx_at_med_power &&
                       tx_disable == other.tx_disable &&
                       fixed_freq == other.fixed_freq &&
                       fixed_bandwidth == other.fixed_bandwidth &&
                       fixed_tx_power == other.fixed_tx_power &&
                       mute == other.mute &&
                       name_str == other.name_str;
            }
            return false;
        }

        public override int GetHashCode()
        {
            int hash = 17;
            hash = hash * 23 + channel_id.GetHashCode();
            hash = hash * 23 + tx_mod.GetHashCode();
            hash = hash * 23 + tx_freq.GetHashCode();
            hash = hash * 23 + rx_mod.GetHashCode();
            hash = hash * 23 + rx_freq.GetHashCode();
            hash = hash * 23 + tx_sub_audio.GetHashCode();
            hash = hash * 23 + rx_sub_audio.GetHashCode();
            hash = hash * 23 + scan.GetHashCode();
            hash = hash * 23 + tx_at_max_power.GetHashCode();
            hash = hash * 23 + talk_around.GetHashCode();
            hash = hash * 23 + bandwidth.GetHashCode();
            hash = hash * 23 + pre_de_emph_bypass.GetHashCode();
            hash = hash * 23 + sign.GetHashCode();
            hash = hash * 23 + tx_at_med_power.GetHashCode();
            hash = hash * 23 + tx_disable.GetHashCode();
            hash = hash * 23 + fixed_freq.GetHashCode();
            hash = hash * 23 + fixed_bandwidth.GetHashCode();
            hash = hash * 23 + fixed_tx_power.GetHashCode();
            hash = hash * 23 + mute.GetHashCode();
            hash = hash * 23 + (name_str?.GetHashCode() ?? 0);
            return hash;
        }
    }

}
