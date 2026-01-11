/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;

namespace HTCommander
{
    public class RadioBssSettings
    {
        public int MaxFwdTimes { get; set; }
        public int TimeToLive { get; set; }
        public bool PttReleaseSendLocation { get; set; }
        public bool PttReleaseSendIdInfo { get; set; }
        public bool PttReleaseSendBssUserId { get; set; }
        public bool ShouldShareLocation { get; set; }
        public bool SendPwrVoltage { get; set; }
        public int PacketFormat { get; set; }
        public bool AllowPositionCheck { get; set; }
        public int AprsSsid { get; set; }
        public int LocationShareInterval { get; set; }
        public int BssUserIdLower { get; set; }
        public string PttReleaseIdInfo { get; set; }
        public string BeaconMessage { get; set; }
        public string AprsSymbol { get; set; }
        public string AprsCallsign { get; set; }

        public RadioBssSettings(byte[] msg)
        {
            if (msg.Length < 51) // Ensure minimum length
                throw new ArgumentException("Invalid message length");

            MaxFwdTimes = (msg[5] & 0xF0) >> 4;
            TimeToLive = msg[5] & 0x0F;
            PttReleaseSendLocation = (msg[6] & 0x80) != 0;
            PttReleaseSendIdInfo = (msg[6] & 0x40) != 0;
            PttReleaseSendBssUserId = (msg[6] & 0x20) != 0;
            ShouldShareLocation = (msg[6] & 0x10) != 0;
            SendPwrVoltage = (msg[6] & 0x08) != 0;
            PacketFormat = (msg[6] & 0x04) >> 2;
            AllowPositionCheck = (msg[6] & 0x02) != 0;
            AprsSsid = (msg[7] & 0xF0) >> 4;
            LocationShareInterval = msg[8] * 10;
            BssUserIdLower = BitConverter.ToInt32(msg, 9);
            PttReleaseIdInfo = Encoding.ASCII.GetString(msg, 13, 12).TrimEnd('\0');
            BeaconMessage = Encoding.ASCII.GetString(msg, 25, 18).TrimEnd('\0');
            AprsSymbol = Encoding.ASCII.GetString(msg, 43, 2).TrimEnd('\0');
            AprsCallsign = Encoding.ASCII.GetString(msg, 45, 6).TrimEnd('\0');
        }

        public byte[] ToByteArray()
        {
            byte[] msg = new byte[46]; // Ensure the correct length

            // Byte 0: MaxFwdTimes (high nibble) | TimeToLive (low nibble)
            msg[0] = (byte)((MaxFwdTimes << 4) | (TimeToLive & 0x0F));

            // Byte 1: Various flags and PacketFormat
            msg[1] = (byte)(
                (PttReleaseSendLocation ? 0x80 : 0) |
                (PttReleaseSendIdInfo ? 0x40 : 0) |
                (PttReleaseSendBssUserId ? 0x20 : 0) |
                (ShouldShareLocation ? 0x10 : 0) |
                (SendPwrVoltage ? 0x08 : 0) |
                ((PacketFormat & 0x01) << 2) |
                (AllowPositionCheck ? 0x02 : 0)
            );

            // Byte 2: APRS SSID (high nibble)
            msg[2] = (byte)((AprsSsid & 0x0F) << 4);

            // Byte 3: Location Share Interval divided by 10
            msg[3] = (byte)(LocationShareInterval / 10);

            // Bytes 4-7: BssUserIdLower (little-endian)
            BitConverter.GetBytes(BssUserIdLower).CopyTo(msg, 4);

            // Bytes 8-19: PttReleaseIdInfo (ASCII, padded with nulls)
            Encoding.ASCII.GetBytes(PttReleaseIdInfo.PadRight(12, '\0')).CopyTo(msg, 8);

            // Bytes 20-37: BeaconMessage (ASCII, padded with nulls)
            Encoding.ASCII.GetBytes(BeaconMessage.PadRight(18, '\0')).CopyTo(msg, 20);

            // Bytes 38-39: AprsSymbol (ASCII, padded with nulls)
            Encoding.ASCII.GetBytes(AprsSymbol.PadRight(2, '\0')).CopyTo(msg, 38);

            // Bytes 40-45: AprsCallsign (ASCII, padded with nulls)
            Encoding.ASCII.GetBytes(AprsCallsign.PadRight(6, '\0')).CopyTo(msg, 40);

            return msg;
        }

    }
}
