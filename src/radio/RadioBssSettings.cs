using System;
using System.Text;

namespace HTCommander
{
    public class RadioBssSettings
    {
        public int MaxFwdTimes { get; private set; }
        public int TimeToLive { get; private set; }
        public bool PttReleaseSendLocation { get; private set; }
        public bool PttReleaseSendIdInfo { get; private set; }
        public bool PttReleaseSendBssUserId { get; private set; }
        public bool ShouldShareLocation { get; private set; }
        public bool SendPwrVoltage { get; private set; }
        public int PacketFormat { get; private set; }
        public bool AllowPositionCheck { get; private set; }
        public int AprsSsid { get; private set; }
        public int LocationShareInterval { get; private set; }
        public int BssUserIdLower { get; private set; }
        public string PttReleaseIdInfo { get; private set; }
        public string BeaconMessage { get; private set; }
        public string AprsSymbol { get; private set; }
        public string AprsCallsign { get; private set; }

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
            byte[] msg = new byte[51]; // Ensure the correct length

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


/*

class BSSSettings(Bitfield):
    max_fwd_times: int = bf_int(4)
    time_to_live: int = bf_int(4)
    ptt_release_send_location: bool
    ptt_release_send_id_info: bool
    ptt_release_send_bss_user_id: bool  # (Applies when BSS is turned on)
    should_share_location: bool
    send_pwr_voltage: bool
    packet_format: PacketFormat = bf_int_enum(PacketFormat, 1)
    allow_position_check: bool
    _pad: t.Literal[0] = bf_lit_int(1, default=0)
    aprs_ssid: int = bf_int(4)
    _pad2: t.Literal[0] = bf_lit_int(4, default=0)
    location_share_interval: int = bf_map(bf_int(8), IntScale(10))
    bss_user_id_lower: int = bf_int(32)
    ptt_release_id_info: str = bf_str(12)
    beacon_message: str = bf_str(18)
    aprs_symbol: str = bf_str(2)
    aprs_callsign: str = bf_str(6)

*/