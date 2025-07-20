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
        public DateTime time;  // The date and time this message was sent or received
        public bool confirmed; // Indicates this APRS message was confirmed with an ACK
        public int messageId;  // This is the APRS MessageID
        public int channel_id;
        public string channel_name;
        public int frame_size;
        public bool incoming;
        public bool sent;
        public AuthState authState = AuthState.Unknown;

        public enum AuthState
        {
            Unknown = 0,
            Failed = 1,
            Success = 2,
            None = 3
        }

        // Content of the packet
        public List<AX25Address> addresses;
        public bool pollFinal;
        public bool command;   // Command or Response depending on the packet usage
        public FrameType type; // Type of frame this is
        public byte nr;        // 0 to 7, or if modulo128 is true, 0 to 127. Gives the sequence number of the next expected frame.
        public byte ns;        // 0 to 7, or if modulo128 is true, 0 to 127. Goes up by one each frame sent.
        public byte pid;       // Only used for I_FRAME and U_FRAME_UI
        public bool modulo128; // True if we need 2 control bytes for more inflight packets
        public string dataStr; // Only used for I_FRAME and U_FRAME_UI
        public byte[] data;    // Only used for I_FRAME and U_FRAME_UI

        // Tag and deadline are used to limit when a message can be sent
        public string tag;
        public DateTime deadline = DateTime.MaxValue;
        public bool isSame(AX25Packet p)
        {
            if (p.dataStr != dataStr) return false;
            for (int i = 0; i < 2; i++) { if (!p.addresses[i].isSame(addresses[i])) return false; } // Only compare 2 first addresses
            if (p.pollFinal != pollFinal) return false;
            if (p.command != command) return false;
            if (p.nr != nr) return false;
            if (p.ns != ns) return false;
            if (p.pid != pid) return false;
            if (p.modulo128 != modulo128) return false;
            return true;
        }

        public AX25Packet(List<AX25Address> addresses, byte nr, byte ns, bool pollFinal, bool command, FrameType type, byte[] data = null)
        {
            this.addresses = addresses;
            this.nr = nr;
            this.ns = ns;
            this.pollFinal = pollFinal;
            this.command = command;
            this.type = type;             // Default value of information frame
            this.time = DateTime.Now;
            this.data = data;
            pid = 240;                    // Default value of no layer 3 protocol implemented
        }

        public AX25Packet(List<AX25Address> addresses, string dataStr, DateTime time)
        {
            this.addresses = addresses;
            this.dataStr = dataStr;
            this.time = time;
            type = FrameType.U_FRAME_UI;  // Default value of information frame
            pid = 240;                    // Default value of no layer 3 protocol implemented
        }

        public AX25Packet(List<AX25Address> addresses, byte[] data, DateTime time)
        {
            this.addresses = addresses;
            this.data = data;
            this.time = time;
            type = FrameType.U_FRAME_UI;  // Default value of information frame
            pid = 240;                    // Default value of no layer 3 protocol implemented
        }

        public static AX25Packet DecodeAX25Packet(TncDataFragment frame)
        {
            byte[] data = frame.data;
            if ((data == null) || (data.Length < 6)) return null;

            // This is an odd packet, not a AX.25 packet
            if (data[0] == 1)
            {
                int callsignLen = data[1];
                if (data.Length < (3 + callsignLen)) return null;
                int controlLen = data[2 + callsignLen];
                if (data.Length < (4 + callsignLen + controlLen)) return null;
                int messageLen = data[3 + callsignLen + controlLen];
                List<AX25Address> xaddresses = new List<AX25Address>();
                xaddresses.Add(AX25Address.GetAddress(UTF8Encoding.Default.GetString(data, 3, callsignLen - 1), 0));
                string xxdata = UTF8Encoding.Default.GetString(data, 5 + callsignLen + controlLen, messageLen - 1);
                byte[] xxdata2 = new byte[messageLen - 1];
                Array.Copy(data, 5 + callsignLen + controlLen, xxdata2, 0, messageLen - 1);
                AX25Packet xpacket = new AX25Packet(xaddresses, xxdata, frame.time);
                xpacket.data = xxdata2;
                xpacket.channel_id = frame.channel_id;
                xpacket.channel_name = frame.channel_name;
                xpacket.incoming = frame.incoming;
                xpacket.frame_size = data.Length;
                return xpacket;
            }

            // Decode the headers
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
            if (addresses.Count < 1) return null;
            bool command = addresses[0].CRBit1;
            bool modulo128 = (addresses[0].CRBit2 == false);

            // Decode control and pid data.
            int control = data[i++];
            bool pollFinal = false;
            FrameType type;
            byte pid = 0;
            byte nr = 0;
            byte ns = 0;

            if ((control & (int)FrameType.U_FRAME) == (int)FrameType.U_FRAME)
            {
                pollFinal = (((control & (int)Defs.PF) >> 4) != 0);
                type = (FrameType)(control & (int)FrameType.U_FRAME_MASK);
                if (type == FrameType.U_FRAME_UI) { pid = data[i++]; }
                else if (type == FrameType.U_FRAME_XID /*&& frame.length > 0*/)
                {
                    // Parse XID parameter fields and break out to properties
                }
                else if (type == FrameType.U_FRAME_TEST /*&& frame.length > 0*/)
                {

                }
            }
            else if ((control & (int)FrameType.U_FRAME) == (int)FrameType.S_FRAME)
            {
                type = (FrameType)(control & (int)FrameType.S_FRAME_MASK);
                if (modulo128)
                {
                    control |= (data[i++] << 8);
                    nr = (byte)((control & (int)Defs.NR_MODULO128) >> 8);
                    pollFinal = ((control & (int)Defs.PF) >> 7) != 0;
                }
                else
                {
                    nr = (byte)((control & (int)Defs.NR) >> 5);
                    pollFinal = ((control & (int)Defs.PF) >> 4) != 0;
                }
            }
            else if ((control & 1) == (int)FrameType.I_FRAME)
            {
                type = FrameType.I_FRAME;
                if (modulo128)
                {
                    control |= (data[i++] << 8);
                    nr = (byte)((control & (int)Defs.NR_MODULO128) >> 8);
                    ns = (byte)((control & (int)Defs.NS_MODULO128) >> 1);
                    pollFinal = ((control & (int)Defs.PF) >> 7) != 0;
                }
                else
                {
                    nr = (byte)((control & (int)Defs.NR) >> 5);
                    ns = (byte)((control & (int)Defs.NS) >> 1);
                    pollFinal = ((control & (int)Defs.PF) >> 4) != 0;
                }
                pid = data[i++];
            }
            else
            {
                // Invalid packet
                return null;
            }

            string xdataStr = null;
            byte[] xdata = null;
            if (data.Length > i) {
                xdataStr = UTF8Encoding.UTF8.GetString(data, i, data.Length - i);
                xdata = new byte[data.Length - i];
                Array.Copy(data, i, xdata, 0, data.Length - i);
            }
            AX25Packet packet = new AX25Packet(addresses, xdataStr, frame.time);
            packet.data = xdata;
            packet.command = command;
            packet.modulo128 = modulo128;
            packet.pollFinal = pollFinal;
            packet.type = type;
            packet.pid = pid;
            packet.nr = nr;
            packet.ns = ns;
            packet.channel_id = frame.channel_id;
            packet.channel_name = frame.channel_name;
            packet.incoming = frame.incoming;
            packet.frame_size = data.Length;
            return packet;
        }

        private int GetControl()
        {
            int control = (int)type;
            if ((type == FrameType.I_FRAME) || ((type & FrameType.U_FRAME) == FrameType.S_FRAME)) { control |= (nr << ((modulo128) ? 9 : 5)); }
            if (type == FrameType.I_FRAME) { control |= (ns << 1); }
            if (pollFinal) { control |= (1 << ((modulo128) ? 8 : 4)); }
            return control;
        }

        public byte[] ToByteArray()
        {
            if ((addresses == null) || (addresses.Count < 1)) return null;
            byte[] dataBytes = null;
            int dataBytesLen = 0;
            if (data != null)
            {
                dataBytes = data;
                dataBytesLen = data.Length;
            }
            else if ((dataStr != null) && (dataStr.Length > 0))
            {
                dataBytes = UTF8Encoding.UTF8.GetBytes(dataStr);
                dataBytesLen = dataBytes.Length;
            }

            // Compute the packet size & control bits
            int packetSize = (7 * addresses.Count) + (modulo128 ? 2 : 1) + dataBytesLen; // Addresses, control and data
            if ((type == FrameType.I_FRAME) || (type == FrameType.U_FRAME_UI)) { packetSize++; } // PID is present
            byte[] rdata = new byte[packetSize];
            int control = GetControl();

            // Put the addresses
            int i = 0;
            for (int j = 0; j < addresses.Count; j++)
            {
                AX25Address a = addresses[j];
                a.CRBit1 = false;
                a.CRBit2 = a.CRBit3 = true;
                //if (j == 0) { a.CRBit1 = ((control & 1) != 0); }
                //if (j == 1) { a.CRBit1 = (((control ^ 1) & 1) != 0); a.CRBit2 = (modulo128 ? false : true); }
                if (j == 0) { a.CRBit1 = command; }
                if (j == 1) { a.CRBit1 = !command; a.CRBit2 = (modulo128 ? false : true); }
                byte[] ab = a.ToByteArray(j == (addresses.Count - 1));
                Array.Copy(ab, 0, rdata, i, 7);
                i += 7;
            }

            // Put the control
            rdata[i++] = (byte)(control & 0xFF);
            if (modulo128) { rdata[i++] = (byte)(control >> 8); }

            // Put the pid if needed
            if ((type == FrameType.I_FRAME) || (type == FrameType.U_FRAME_UI)) { rdata[i++] = pid; }

            // Put the data
            if (dataBytesLen > 0) { Array.Copy(dataBytes, 0, rdata, i, dataBytes.Length); }

            return rdata;
        }

        public override string ToString()
        {
            string r = "";
            foreach (AX25Address a in addresses) { r += "[" + a.ToString() + "]"; }
            r += ": " + data;
            return r;
        }

        // AX.25 & KISS protocol-related constants
        public enum FrameType : byte
        {
            //     Information frame
            I_FRAME = 0,
            I_FRAME_MASK = 1,
            //     Supervisory frame and subtypes
            S_FRAME = 1,
            S_FRAME_RR = 1,                                                    // Receive Ready
            S_FRAME_RNR = 1 | (1 << 2),                                        // Receive Not Ready
            S_FRAME_REJ = 1 | (1 << 3),                                        // Reject
            S_FRAME_SREJ = 1 | (1 << 2) | (1 << 3),                            // Selective Reject
            S_FRAME_MASK = 1 | (1 << 2) | (1 << 3),
            //     Unnumbered frame and subtypes
            U_FRAME = 3,
            U_FRAME_SABM = 3 | (1 << 2) | (1 << 3) | (1 << 5),                 // Set Asynchronous Balanced Mode
            U_FRAME_SABME = 3 | (1 << 3) | (1 << 5) | (1 << 6),                // SABM for modulo 128 operation
            U_FRAME_DISC = 3 | (1 << 6),                                       // Disconnect
            U_FRAME_DM = 3 | (1 << 2) | (1 << 3),                              // Disconnected Mode
            U_FRAME_UA = 3 | (1 << 5) | (1 << 6),                              // Acknowledge
            U_FRAME_FRMR = 3 | (1 << 2) | (1 << 7),                            // Frame Reject
            U_FRAME_UI = 3,                                                    // Information
            U_FRAME_XID = 3 | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 7),       // Exchange Identification
            U_FRAME_TEST = 3 | (1 << 5) | (1 << 6) | (1 << 7),                 // Test
            U_FRAME_MASK = 3 | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 6) | (1 << 7),
            A_CRH = 0x80                                                       // C/R Bit Hardened (Control/Repeated bit in Repeater Path SSID) -  Value 128 (0x80) is a common assumption for this bit.
    }

    public enum Defs : int
        {
            FLAG            = (1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6),       // Unused, but included for non-KISS implementations.

            // Address field - SSID subfield bitmasks
            A_CRH           = (1<<7),                                          // Command/Response or Has-Been-Repeated bit of an SSID octet
            A_RR            = (1<<5)|(1<<6),                                   // The "R" (reserved) bits of an SSID octet
            A_SSID          = (1<<1)|(1<<2)|(1<<3)|(1<<4),                     // The SSID portion of an SSID octet

            // Control field bitmasks
            PF              = (1<<4),                                          // Poll/Final
            NS              = (1<<1)|(1<<2)|(1<<3),                            // N(S) - send sequence number
            NR              = (1<<5)|(1<<6)|(1<<7),                            // N(R) - receive sequence number
            PF_MODULO128    = (1<<8),                                          // Poll/Final in modulo 128 mode I & S frames
            NS_MODULO128    = (127<<1),                                        // N(S) in modulo 128 I frames
            NR_MODULO128    = (127<<9),                                        // N(R) in modulo 128 I & S frames

            // Protocol ID field bitmasks (most are unlikely to be used, but are here for the sake of completeness.)
            PID_X25         = 1,                                               // ISO 8208/CCITT X.25 PLP
            PID_CTCPIP      = (1<<1)|(1<<2),                                   // Compressed TCP/IP packet. Van Jacobson (RFC 1144)
            PID_UCTCPIP     = (1<<0)|(1<<1)|(1<<2),                            // Uncompressed TCP/IP packet. Van Jacobson (RFC 1144)
            PID_SEGF        = (1<<4),                                          // Segmentation fragment
            PID_TEXNET      = (1<<0)|(1<<1)|(1<<6)|(1<<7),                     // TEXNET datagram protocol
            PID_LQP         = (1<<2)|(1<<6)|(1<<7),                            // Link Quality Protocol
            PID_ATALK       = (1<<1)|(1<<3)|(1<<6)|(1<<7),                     // Appletalk
            PID_ATALKARP    = (1<<0)|(1<<1)|(1<<3)|(1<<6)|(1<<7),              // Appletalk ARP
            PID_ARPAIP      = (1<<2)|(1<<3)|(1<<6)|(1<<7),                     // ARPA Internet Protocol
            PID_ARPAAR      = (1<<0)|(1<<2)|(1<<3)|(1<<6)|(1<<7),              // ARPA Address Resolution
            PID_FLEXNET     = (1<<1)|(1<<2)|(1<<3)|(1<<6)|(1<<7),              // FlexNet
            PID_NETROM      = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<6)|(1<<7),       // Net/ROM
            PID_NONE        = (1<<4)|(1<<5)|(1<<6)|(1<<7),                     // No layer 3 protocol implemented
            PID_ESC         = 255                                              // Escape character. Next octet contains more Level 3 protocol information.
        }

    }

}