/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{

    public class TncDataFragment
    {
        public bool final_fragment;
        public int fragment_id;
        public byte[] data;
        public int region_id;
        public int channel_id;
        public string channel_name;
        public bool incoming;
        public DateTime time;
        public FragmentEncodingType encoding = FragmentEncodingType.Unknown;
        public FragmentFrameType frame_type = FragmentFrameType.Unknown;
        public int corrections = -1;

        public enum FragmentEncodingType
        {
            Unknown,
            Loopback,
            HardwareAfsk1200,
            SoftwareAfsk1200,
            SoftwareG3RUH9600,
            SoftwarePsk2400,
            SoftwarePsk4800,
        }
        
        public enum FragmentFrameType
        {
            Unknown,
            AX25,
            FX25
        }

        public TncDataFragment(bool is_final_fragment, int fragment_id, byte[] data, int channel_id, int region_id)
        {
            this.final_fragment = is_final_fragment;
            this.fragment_id = fragment_id;
            this.data = data;
            this.channel_id = channel_id;
            this.region_id = region_id;
            channel_name = (channel_id == -1) ? "" : (channel_id + 1).ToString().Replace(",","");
        }

        public override string ToString()
        {
            //return "TncFrag2," + channel_id + "," + region_id + "," + channel_name + "," + Utils.BytesToHex(data);
            return "TncFrag3," + channel_id + "," + region_id + "," + channel_name + "," + Utils.BytesToHex(data) + "," + (int)encoding + "," + (int)frame_type + "," + (int)corrections;
        }

        public TncDataFragment(byte[] msg)
        {
            final_fragment = (msg[5] & 0x80) != 0;
            bool with_channel_id = (msg[5] & 0x40) != 0;
            fragment_id = msg[5] & 0x3F;
            int dataLen = msg.Length - 6 - (with_channel_id ? 1 : 0);
            data = new byte[dataLen];
            Array.Copy(msg, 6, data, 0, dataLen);
            if (with_channel_id) { channel_id = msg[msg.Length - 1]; } else { channel_id = -1; }
        }

        public TncDataFragment Append(TncDataFragment frame)
        {
            if ((frame.fragment_id == fragment_id + 1) && (final_fragment == false))
            {
                // Merge the data
                byte[] mergedData = new byte[data.Length + frame.data.Length];
                Array.Copy(data, 0, mergedData, 0, data.Length);
                Array.Copy(frame.data, 0, mergedData, data.Length, frame.data.Length);
                frame.data = mergedData;
                return frame;
            }
            else
            {
                // Discard the old data and just keep the new frame
                return frame;
            }
        }

        public byte[] toByteArray()
        {
            int len = 1 + data.Length + ((channel_id != -1) ? 1 : 0);
            byte[] rdata = new byte[len];
            if (final_fragment) { rdata[0] |= 0x80; }
            if (channel_id != -1) { rdata[0] |= 0x40; }
            rdata[0] |= (byte)(fragment_id & 0x3F);
            Array.Copy(data, 0, rdata, 1, data.Length);
            if (channel_id != -1) { rdata[len - 1] = (byte)channel_id; }
            return rdata;
        }

        public string ToHex()
        {
            return Utils.BytesToHex(data);
        }
    }
}
