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

//
// Ax25Pad.cs - AX.25 packet assembler and disassembler
//

using System;
using System.Text;

namespace HamLib
{
    #region Constants and Enums

    public static class Ax25Constants
    {
        public const int MaxRepeaters = 8;
        public const int MinAddrs = 2;  // Destination & Source
        public const int MaxAddrs = 10; // Destination, Source, 8 digipeaters

        public const int Destination = 0;
        public const int Source = 1;
        public const int Repeater1 = 2;
        public const int Repeater2 = 3;
        public const int Repeater3 = 4;
        public const int Repeater4 = 5;
        public const int Repeater5 = 6;
        public const int Repeater6 = 7;
        public const int Repeater7 = 8;
        public const int Repeater8 = 9;

        public const int MaxAddrLen = 12;
        public const int MinInfoLen = 0;
        public const int MaxInfoLen = 2048;

        public const int MinPacketLen = 2 * 7 + 1;
        public const int MaxPacketLen = MaxAddrs * 7 + 2 + 3 + MaxInfoLen;

        public const byte UiFrame = 0x03;
        public const byte PidNoLayer3 = 0xF0;
        public const byte PidNetrom = 0xCF;
        public const byte PidSegmentationFragment = 0x08;
        public const byte PidEscapeCharacter = 0xFF;

        // SSID bit masks
        public const byte SsidHMask = 0x80;
        public const int SsidHShift = 7;
        public const byte SsidRrMask = 0x60;
        public const int SsidRrShift = 5;
        public const byte SsidSsidMask = 0x1E;
        public const int SsidSsidShift = 1;
        public const byte SsidLastMask = 0x01;

        public const int AlevelToTextSize = 40;
    }

    public enum Ax25FrameType
    {
        I = 0,                  // Information
        S_RR,                   // Receive Ready
        S_RNR,                  // Receive Not Ready
        S_REJ,                  // Reject Frame
        S_SREJ,                 // Selective Reject
        U_SABME,                // Set Async Balanced Mode, Extended
        U_SABM,                 // Set Async Balanced Mode
        U_DISC,                 // Disconnect
        U_DM,                   // Disconnect Mode
        U_UA,                   // Unnumbered Acknowledge
        U_FRMR,                 // Frame Reject
        U_UI,                   // Unnumbered Information
        U_XID,                  // Exchange Identification
        U_TEST,                 // Test
        U,                      // Other Unnumbered
        NotAX25                 // Could not get control byte
    }

    public enum CmdRes
    {
        Cr00 = 2,
        Cmd = 1,
        Res = 0,
        Cr11 = 3
    }

    public enum Ax25Modulo
    {
        Unknown = 0,
        Modulo8 = 8,
        Modulo128 = 128
    }

    #endregion

    #region Audio Level Structure

    public struct ALevel
    {
        public int Rec;
        public int Mark;
        public int Space;

        public ALevel(int rec = -1, int mark = -1, int space = -1)
        {
            Rec = rec;
            Mark = mark;
            Space = space;
        }
    }

    #endregion

    #region Packet Class

    /// <summary>
    /// Represents an AX.25 packet
    /// </summary>
    public class Packet
    {
        private const int Magic = 0x41583235; // "AX25"

        public int Seq { get; private set; }
        public double ReleaseTime { get; set; }
        public Packet NextP { get; set; }
        public int NumAddr { get; internal set; }
        public int FrameLen { get; internal set; }
        public Ax25Modulo Modulo { get; set; }
        public byte[] FrameData { get; private set; }

        private static int _lastSeqNum = 0;
        private static int _newCount = 0;
        private static int _deleteCount = 0;

        public Packet()
        {
            _lastSeqNum++;
            _newCount++;
            Seq = _lastSeqNum;

            FrameData = new byte[Ax25Constants.MaxPacketLen + 1];
            NumAddr = -1;
            FrameLen = 0;
            Modulo = Ax25Modulo.Unknown;

            // Check for memory leak
            if (_newCount > _deleteCount + 256)
            {
                Console.WriteLine($"Report to WB2OSZ - Memory leak for packet objects. new={_newCount}, delete={_deleteCount}");
            }
        }

        ~Packet()
        {
            _deleteCount++;
        }

        /// <summary>
        /// Create a new packet from text monitor format
        /// </summary>
        public static Packet FromText(string monitor, bool strict)
        {
            if (string.IsNullOrEmpty(monitor))
                return null;

            var packet = new Packet();

            // Initialize with two addresses and control/pid for APRS
            for (int i = 0; i < 6; i++)
            {
                packet.FrameData[Ax25Constants.Destination * 7 + i] = (byte)(' ' << 1);
                packet.FrameData[Ax25Constants.Source * 7 + i] = (byte)(' ' << 1);
            }
            packet.FrameData[Ax25Constants.Destination * 7 + 6] = 
                (byte)(Ax25Constants.SsidHMask | Ax25Constants.SsidRrMask);
            packet.FrameData[Ax25Constants.Source * 7 + 6] = 
                (byte)(Ax25Constants.SsidRrMask | Ax25Constants.SsidLastMask);

            packet.FrameData[14] = Ax25Constants.UiFrame;
            packet.FrameData[15] = Ax25Constants.PidNoLayer3;

            packet.FrameLen = 7 + 7 + 1 + 1;
            packet.NumAddr = -1;
            packet.GetNumAddr(); // Sets NumAddr properly

            // Separate the addresses from the rest
            int colonPos = monitor.IndexOf(':');
            if (colonPos < 0)
                return null;

            string addrPart = monitor.Substring(0, colonPos);
            string infoPart = monitor.Substring(colonPos + 1);

            // Parse source address
            int gtPos = addrPart.IndexOf('>');
            if (gtPos < 0)
            {
                Console.WriteLine("Failed to create packet from text. No source address");
                return null;
            }

            string srcAddr = addrPart.Substring(0, gtPos);
            if (!ParseAddr(Ax25Constants.Source, srcAddr, strict, out string srcCallsign, out int srcSsid, out bool srcHeard))
            {
                Console.WriteLine("Failed to create packet from text. Bad source address");
                return null;
            }

            packet.SetAddr(Ax25Constants.Source, srcCallsign);
            packet.SetH(Ax25Constants.Source);
            packet.SetSsid(Ax25Constants.Source, srcSsid);

            // Parse destination and digipeaters
            string[] parts = addrPart.Substring(gtPos + 1).Split(',');
            if (parts.Length < 1)
            {
                Console.WriteLine("Failed to create packet from text. No destination address");
                return null;
            }

            // Destination
            if (!ParseAddr(Ax25Constants.Destination, parts[0], strict, out string destCallsign, out int destSsid, out bool destHeard))
            {
                Console.WriteLine("Failed to create packet from text. Bad destination address");
                return null;
            }

            packet.SetAddr(Ax25Constants.Destination, destCallsign);
            packet.SetH(Ax25Constants.Destination);
            packet.SetSsid(Ax25Constants.Destination, destSsid);

            // Digipeaters
            for (int i = 1; i < parts.Length && packet.NumAddr < Ax25Constants.MaxAddrs; i++)
            {
                int k = packet.NumAddr;
                string digiAddr = parts[i];

                // Hack for q construct from APRS-IS
                if (!strict && digiAddr.Length >= 2 && digiAddr[0] == 'q' && digiAddr[1] == 'A')
                {
                    digiAddr = "Q" + digiAddr.Substring(1, 1) + char.ToUpper(digiAddr[2]) + digiAddr.Substring(3);
                }

                if (!ParseAddr(k, digiAddr, strict, out string digiCallsign, out int digiSsid, out bool digiHeard))
                {
                    Console.WriteLine("Failed to create packet from text. Bad digipeater address");
                    return null;
                }

                packet.SetAddr(k, digiCallsign);
                packet.SetSsid(k, digiSsid);

                if (digiHeard)
                {
                    for (int j = k; j >= Ax25Constants.Repeater1; j--)
                    {
                        packet.SetH(j);
                    }
                }
            }

            // Process information part - translate <0xNN> to bytes
            byte[] infoBytes = new byte[Ax25Constants.MaxInfoLen];
            int infoLen = 0;
            int idx = 0;

            while (idx < infoPart.Length && infoLen < Ax25Constants.MaxInfoLen)
            {
                if (idx + 5 < infoPart.Length &&
                    infoPart[idx] == '<' &&
                    infoPart[idx + 1] == '0' &&
                    infoPart[idx + 2] == 'x' &&
                    infoPart[idx + 5] == '>')
                {
                    string hexStr = infoPart.Substring(idx + 3, 2);
                    if (byte.TryParse(hexStr, System.Globalization.NumberStyles.HexNumber, null, out byte b))
                    {
                        infoBytes[infoLen++] = b;
                        idx += 6;
                        continue;
                    }
                }

                infoBytes[infoLen++] = (byte)infoPart[idx];
                idx++;
            }

            // Append info part
            Array.Copy(infoBytes, 0, packet.FrameData, packet.FrameLen, infoLen);
            packet.FrameLen += infoLen;

            return packet;
        }

        /// <summary>
        /// Create a packet from frame data
        /// </summary>
        public static Packet FromFrame(byte[] fbuf, int flen, ALevel alevel)
        {
            if (flen < Ax25Constants.MinPacketLen || flen > Ax25Constants.MaxPacketLen)
            {
                Console.WriteLine($"Frame length {flen} not in allowable range of {Ax25Constants.MinPacketLen} to {Ax25Constants.MaxPacketLen}.");
                return null;
            }

            var packet = new Packet();
            Array.Copy(fbuf, packet.FrameData, flen);
            packet.FrameData[flen] = 0;
            packet.FrameLen = flen;

            packet.NumAddr = -1;
            packet.GetNumAddr();

            return packet;
        }

        /// <summary>
        /// Duplicate a packet
        /// </summary>
        public Packet Dup()
        {
            var newPacket = new Packet();
            Array.Copy(FrameData, newPacket.FrameData, FrameData.Length);
            newPacket.FrameLen = FrameLen;
            newPacket.NumAddr = NumAddr;
            newPacket.Modulo = Modulo;
            newPacket.ReleaseTime = ReleaseTime;

            return newPacket;
        }

        /// <summary>
        /// Parse an address with optional SSID
        /// </summary>
        public static bool ParseAddr(int position, string inAddr, bool strict, 
            out string outAddr, out int outSsid, out bool outHeard)
        {
            outAddr = "";
            outSsid = 0;
            outHeard = false;

            if (string.IsNullOrEmpty(inAddr))
            {
                Console.WriteLine($"Address \"{inAddr}\" is empty.");
                return false;
            }

            // Check for q-construct in strict mode
            if (strict && inAddr.Length >= 2 && inAddr.Substring(0, 2) == "qA")
            {
                Console.WriteLine($"Address \"{inAddr}\" is a \"q-construct\" used for communicating with");
                Console.WriteLine("APRS Internet Servers. It should never appear when going over the radio.");
            }

            int maxLen = strict ? 6 : (Ax25Constants.MaxAddrLen - 1);
            StringBuilder addr = new StringBuilder();

            int i = 0;
            while (i < inAddr.Length && inAddr[i] != '-' && inAddr[i] != '*')
            {
                if (addr.Length >= maxLen)
                {
                    Console.WriteLine($"Address is too long. \"{inAddr}\" has more than {maxLen} characters.");
                    return false;
                }

                if (!char.IsLetterOrDigit(inAddr[i]))
                {
                    Console.WriteLine($"Address, \"{inAddr}\" contains character other than letter or digit in character position {i + 1}.");
                    return false;
                }

                if (strict && char.IsLower(inAddr[i]) && !inAddr.StartsWith("qA"))
                {
                    Console.WriteLine($"Address has lower case letters. \"{inAddr}\" must be all upper case.");
                    return false;
                }

                addr.Append(inAddr[i]);
                i++;
            }

            outAddr = addr.ToString();

            // Parse SSID
            if (i < inAddr.Length && inAddr[i] == '-')
            {
                i++;
                StringBuilder ssidStr = new StringBuilder();

                while (i < inAddr.Length && char.IsLetterOrDigit(inAddr[i]))
                {
                    if (ssidStr.Length >= 2)
                    {
                        Console.WriteLine($"SSID is too long. SSID part of \"{inAddr}\" has more than 2 characters.");
                        return false;
                    }

                    if (strict && !char.IsDigit(inAddr[i]))
                    {
                        Console.WriteLine($"SSID must be digits. \"{inAddr}\" has letters in SSID.");
                        return false;
                    }

                    ssidStr.Append(inAddr[i]);
                    i++;
                }

                if (int.TryParse(ssidStr.ToString(), out int ssid))
                {
                    if (ssid < 0 || ssid > 15)
                    {
                        Console.WriteLine($"SSID out of range. SSID of \"{inAddr}\" not in range of 0 to 15.");
                        return false;
                    }
                    outSsid = ssid;
                }
            }

            // Check for asterisk
            if (i < inAddr.Length && inAddr[i] == '*')
            {
                outHeard = true;
                i++;

                if (strict == true) // Only complain if strict is exactly true (not just non-zero)
                {
                    Console.WriteLine($"\"*\" is not allowed at end of address \"{inAddr}\" here.");
                    return false;
                }
            }

            // Should be at end
            if (i < inAddr.Length)
            {
                Console.WriteLine($"Invalid character \"{inAddr[i]}\" found in address \"{inAddr}\".");
                return false;
            }

            return true;
        }

        /// <summary>
        /// Get number of addresses in packet
        /// </summary>
        public int GetNumAddr()
        {
            if (NumAddr >= 0)
                return NumAddr;

            NumAddr = 0;
            int addrBytes = 0;

            for (int a = 0; a < FrameLen && addrBytes == 0; a++)
            {
                if ((FrameData[a] & Ax25Constants.SsidLastMask) != 0)
                {
                    addrBytes = a + 1;
                }
            }

            if (addrBytes % 7 == 0)
            {
                int addrs = addrBytes / 7;
                if (addrs >= Ax25Constants.MinAddrs && addrs <= Ax25Constants.MaxAddrs)
                {
                    NumAddr = addrs;
                }
            }

            return NumAddr;
        }

        /// <summary>
        /// Get number of repeater addresses
        /// </summary>
        public int GetNumRepeaters()
        {
            if (NumAddr >= 2)
                return NumAddr - 2;
            return 0;
        }

        /// <summary>
        /// Get address with SSID
        /// </summary>
        public string GetAddrWithSsid(int n)
        {
            if (n < 0 || n >= NumAddr)
            {
                Console.WriteLine($"Internal error: GetAddrWithSsid({n}), num_addr={NumAddr}");
                return "??????";
            }

            StringBuilder station = new StringBuilder();
            for (int i = 0; i < 6; i++)
            {
                station.Append((char)((FrameData[n * 7 + i] >> 1) & 0x7F));
            }

            // Trim trailing spaces
            string result = station.ToString().TrimEnd(' ');

            if (string.IsNullOrEmpty(result))
            {
                Console.WriteLine($"Station address, in position {n}, is empty! This is not a valid AX.25 frame.");
            }

            int ssid = GetSsid(n);
            if (ssid != 0)
            {
                result += $"-{ssid}";
            }

            return result;
        }

        /// <summary>
        /// Get address without SSID
        /// </summary>
        public string GetAddrNoSsid(int n)
        {
            if (n < 0 || n >= NumAddr)
            {
                Console.WriteLine($"Internal error: GetAddrNoSsid({n}), num_addr={NumAddr}");
                return "??????";
            }

            StringBuilder station = new StringBuilder();
            for (int i = 0; i < 6; i++)
            {
                station.Append((char)((FrameData[n * 7 + i] >> 1) & 0x7F));
            }

            string result = station.ToString().TrimEnd(' ');

            if (string.IsNullOrEmpty(result))
            {
                Console.WriteLine($"Station address, in position {n}, is empty! This is not a valid AX.25 frame.");
            }

            return result;
        }

        /// <summary>
        /// Get SSID of address
        /// </summary>
        public int GetSsid(int n)
        {
            if (n >= 0 && n < NumAddr)
            {
                return (FrameData[n * 7 + 6] & Ax25Constants.SsidSsidMask) >> Ax25Constants.SsidSsidShift;
            }

            Console.WriteLine($"Internal error: GetSsid({n}), num_addr={NumAddr}");
            return 0;
        }

        /// <summary>
        /// Set SSID of address
        /// </summary>
        public void SetSsid(int n, int ssid)
        {
            if (n >= 0 && n < NumAddr)
            {
                FrameData[n * 7 + 6] = (byte)((FrameData[n * 7 + 6] & ~Ax25Constants.SsidSsidMask) |
                    ((ssid << Ax25Constants.SsidSsidShift) & Ax25Constants.SsidSsidMask));
            }
            else
            {
                Console.WriteLine($"Internal error: SetSsid({n},{ssid}), num_addr={NumAddr}");
            }
        }

        /// <summary>
        /// Get "has been repeated" flag
        /// </summary>
        public bool GetH(int n)
        {
            if (n >= 0 && n < NumAddr)
            {
                return ((FrameData[n * 7 + 6] & Ax25Constants.SsidHMask) >> Ax25Constants.SsidHShift) != 0;
            }

            Console.WriteLine($"Internal error: GetH({n}), num_addr={NumAddr}");
            return false;
        }

        /// <summary>
        /// Set "has been repeated" flag
        /// </summary>
        public void SetH(int n)
        {
            if (n >= 0 && n < NumAddr)
            {
                FrameData[n * 7 + 6] |= Ax25Constants.SsidHMask;
            }
            else
            {
                Console.WriteLine($"Internal error: SetH({n}), num_addr={NumAddr}");
            }
        }

        /// <summary>
        /// Get index of station we heard
        /// </summary>
        public int GetHeard()
        {
            int result = Ax25Constants.Source;

            for (int i = Ax25Constants.Repeater1; i < GetNumAddr(); i++)
            {
                if (GetH(i))
                {
                    result = i;
                }
            }

            return result;
        }

        /// <summary>
        /// Get first repeater that has not been repeated
        /// </summary>
        public int GetFirstNotRepeated()
        {
            for (int i = Ax25Constants.Repeater1; i < GetNumAddr(); i++)
            {
                if (!GetH(i))
                {
                    return i;
                }
            }
            return -1;
        }

        /// <summary>
        /// Get RR bits
        /// </summary>
        public int GetRr(int n)
        {
            if (n >= 0 && n < NumAddr)
            {
                return (FrameData[n * 7 + 6] & Ax25Constants.SsidRrMask) >> Ax25Constants.SsidRrShift;
            }

            Console.WriteLine($"Internal error: GetRr({n}), num_addr={NumAddr}");
            return 0;
        }

        /// <summary>
        /// Set address
        /// </summary>
        public void SetAddr(int n, string ad)
        {
            if (string.IsNullOrEmpty(ad))
            {
                Console.WriteLine($"Set address error! Station address for position {n} is empty!");
                return;
            }

            if (n >= 0 && n < NumAddr)
            {
                // Set existing address
                if (!ParseAddr(n, ad, false, out string callsign, out int ssid, out bool heard))
                    return;

                // Clear and set address
                for (int i = 0; i < 6; i++)
                {
                    FrameData[n * 7 + i] = (byte)(' ' << 1);
                }

                for (int i = 0; i < callsign.Length && i < 6; i++)
                {
                    FrameData[n * 7 + i] = (byte)(callsign[i] << 1);
                }

                SetSsid(n, ssid);
            }
            else if (n == NumAddr)
            {
                // Append new address
                InsertAddr(n, ad);
            }
            else
            {
                Console.WriteLine($"Internal error, SetAddr, bad position {n} for '{ad}'");
            }
        }

        /// <summary>
        /// Insert address at position
        /// </summary>
        public void InsertAddr(int n, string ad)
        {
            if (string.IsNullOrEmpty(ad))
            {
                Console.WriteLine($"Set address error! Station address for position {n} is empty!");
                return;
            }

            if (NumAddr >= Ax25Constants.MaxAddrs)
                return;

            if (n < Ax25Constants.Repeater1 || n >= Ax25Constants.MaxAddrs)
                return;

            // Clear last address flag
            FrameData[NumAddr * 7 - 1] &= unchecked((byte)~Ax25Constants.SsidLastMask);

            NumAddr++;

            // Shift addresses
            Array.Copy(FrameData, n * 7, FrameData, (n + 1) * 7, FrameLen - (n * 7));
            for (int i = 0; i < 6; i++)
            {
                FrameData[n * 7 + i] = (byte)(' ' << 1);
            }
            FrameData[n * 7 + 6] = Ax25Constants.SsidRrMask;
            FrameLen += 7;

            // Set last address flag
            FrameData[NumAddr * 7 - 1] |= Ax25Constants.SsidLastMask;

            // Parse and set address
            if (!ParseAddr(n, ad, false, out string callsign, out int ssid, out bool heard))
                return;

            for (int i = 0; i < callsign.Length && i < 6; i++)
            {
                FrameData[n * 7 + i] = (byte)(callsign[i] << 1);
            }

            SetSsid(n, ssid);
        }

        /// <summary>
        /// Remove address at position
        /// </summary>
        public void RemoveAddr(int n)
        {
            if (n < Ax25Constants.Repeater1 || n >= Ax25Constants.MaxAddrs)
                return;

            // Clear last address flag
            FrameData[NumAddr * 7 - 1] &= unchecked((byte)~Ax25Constants.SsidLastMask);

            NumAddr--;

            // Shift addresses down
            Array.Copy(FrameData, (n + 1) * 7, FrameData, n * 7, FrameLen - ((n + 1) * 7));
            FrameLen -= 7;

            // Set last address flag
            FrameData[NumAddr * 7 - 1] |= Ax25Constants.SsidLastMask;
        }

        /// <summary>
        /// Get information field
        /// </summary>
        public byte[] GetInfo(out int length)
        {
            if (NumAddr >= 2)
            {
                int offset = GetInfoOffset();
                length = GetNumInfo();
                byte[] info = new byte[length];
                Array.Copy(FrameData, offset, info, 0, length);
                return info;
            }

            // Not AX.25, treat whole packet as info
            length = FrameLen;
            byte[] allInfo = new byte[length];
            Array.Copy(FrameData, 0, allInfo, 0, length);
            return allInfo;
        }

        /// <summary>
        /// Set information field
        /// </summary>
        public void SetInfo(byte[] newInfo, int newInfoLen)
        {
            var oldInfo = GetInfo(out int oldInfoLen);
            FrameLen -= oldInfoLen;

            if (newInfoLen < 0) newInfoLen = 0;
            if (newInfoLen > Ax25Constants.MaxInfoLen) newInfoLen = Ax25Constants.MaxInfoLen;

            int offset = GetInfoOffset();
            Array.Copy(newInfo, 0, FrameData, offset, newInfoLen);
            FrameLen += newInfoLen;
        }

        /// <summary>
        /// Truncate info at first CR or LF
        /// </summary>
        public int CutAtCrlf()
        {
            var info = GetInfo(out int infoLen);

            for (int j = 0; j < infoLen; j++)
            {
                if (info[j] == '\r' || info[j] == '\n')
                {
                    int chop = infoLen - j;
                    FrameLen -= chop;
                    return chop;
                }
            }

            return 0;
        }

        /// <summary>
        /// Get data type identifier
        /// </summary>
        public int GetDti()
        {
            if (NumAddr >= 2)
            {
                return FrameData[GetInfoOffset()];
            }
            return ' ';
        }

        /// <summary>
        /// Get control byte
        /// </summary>
        public int GetControl()
        {
            if (FrameLen == 0) return -1;
            if (NumAddr >= 2)
            {
                return FrameData[GetControlOffset()];
            }
            return -1;
        }

        /// <summary>
        /// Get second control byte
        /// </summary>
        public int GetC2()
        {
            if (FrameLen == 0) return -1;
            if (NumAddr >= 2)
            {
                int offset2 = GetControlOffset() + 1;
                if (offset2 < FrameLen)
                {
                    return FrameData[offset2];
                }
            }
            return -1;
        }

        /// <summary>
        /// Get protocol ID
        /// </summary>
        public int GetPid()
        {
            if (FrameLen == 0) return -1;
            if (NumAddr >= 2)
            {
                return FrameData[GetPidOffset()];
            }
            return -1;
        }

        /// <summary>
        /// Set protocol ID
        /// </summary>
        public void SetPid(int pid)
        {
            if (pid == 0)
                pid = Ax25Constants.PidNoLayer3;

            if (FrameLen == 0) return;

            // Check if it's I or UI frame
            var frameType = GetFrameType(out var cr, out string desc, out int pf, out int nr, out int ns);
            if (frameType != Ax25FrameType.I && frameType != Ax25FrameType.U_UI)
            {
                Console.WriteLine($"SetPid(0x{pid:X2}): Packet type is not I or UI.");
                return;
            }

            if (NumAddr >= 2)
            {
                FrameData[GetPidOffset()] = (byte)pid;
            }
        }

        /// <summary>
        /// Format all addresses for display
        /// </summary>
        public string FormatAddrs()
        {
            if (NumAddr == 0)
                return "";

            StringBuilder result = new StringBuilder();
            result.Append(GetAddrWithSsid(Ax25Constants.Source));
            result.Append(">");
            result.Append(GetAddrWithSsid(Ax25Constants.Destination));

            int heard = GetHeard();
            for (int i = Ax25Constants.Repeater1; i < NumAddr; i++)
            {
                result.Append(",");
                result.Append(GetAddrWithSsid(i));
                if (i == heard)
                {
                    result.Append("*");
                }
            }

            result.Append(":");
            return result.ToString();
        }

        /// <summary>
        /// Format via path for display
        /// </summary>
        public string FormatViaPath()
        {
            if (NumAddr == 0)
                return "";

            StringBuilder result = new StringBuilder();
            int heard = GetHeard();

            for (int i = Ax25Constants.Repeater1; i < NumAddr; i++)
            {
                if (i > Ax25Constants.Repeater1)
                {
                    result.Append(",");
                }
                result.Append(GetAddrWithSsid(i));
                if (i == heard)
                {
                    result.Append("*");
                }
            }

            return result.ToString();
        }

        /// <summary>
        /// Pack frame for transmission
        /// </summary>
        public int Pack(byte[] result)
        {
            Array.Copy(FrameData, result, FrameLen);
            return FrameLen;
        }

        /// <summary>
        /// Get frame type
        /// </summary>
        public Ax25FrameType GetFrameType(out CmdRes cr, out string desc, out int pf, out int nr, out int ns)
        {
            desc = "????";
            cr = CmdRes.Cr11;
            pf = -1;
            nr = -1;
            ns = -1;

            int c = GetControl();
            if (c < 0)
            {
                desc = "Not AX.25";
                return Ax25FrameType.NotAX25;
            }

            int c2 = 0;

            // Attempt to determine modulo
            if (Modulo == Ax25Modulo.Unknown && (c & 3) == 1 && GetC2() != -1)
            {
                Modulo = Ax25Modulo.Modulo128;
            }
            else if (Modulo == Ax25Modulo.Unknown && (c & 1) == 0 && 
                     GetInfoOffset() < FrameLen && FrameData[GetInfoOffset()] == 0xF0)
            {
                Modulo = Ax25Modulo.Modulo128;
            }

            if (Modulo == Ax25Modulo.Modulo128)
            {
                c2 = GetC2();
            }

            int dstC = (FrameData[Ax25Constants.Destination * 7 + 6] & Ax25Constants.SsidHMask) != 0 ? 1 : 0;
            int srcC = (FrameData[Ax25Constants.Source * 7 + 6] & Ax25Constants.SsidHMask) != 0 ? 1 : 0;

            string crText, pfText;
            if (dstC != 0)
            {
                if (srcC != 0) { cr = CmdRes.Cr11; crText = "cc=11"; pfText = "p/f"; }
                else { cr = CmdRes.Cmd; crText = "cmd"; pfText = "p"; }
            }
            else
            {
                if (srcC != 0) { cr = CmdRes.Res; crText = "res"; pfText = "f"; }
                else { cr = CmdRes.Cr00; crText = "cc=00"; pfText = "p/f"; }
            }

            if ((c & 1) == 0)
            {
                // Information frame
                if (Modulo == Ax25Modulo.Modulo128)
                {
                    ns = (c >> 1) & 0x7F;
                    pf = c2 & 1;
                    nr = (c2 >> 1) & 0x7F;
                }
                else
                {
                    ns = (c >> 1) & 7;
                    pf = (c >> 4) & 1;
                    nr = (c >> 5) & 7;
                }

                desc = $"I {crText}, n(s)={ns}, n(r)={nr}, {pfText}={pf}, pid=0x{GetPid():X2}";
                return Ax25FrameType.I;
            }
            else if ((c & 2) == 0)
            {
                // Supervisory frame
                if (Modulo == Ax25Modulo.Modulo128)
                {
                    pf = c2 & 1;
                    nr = (c2 >> 1) & 0x7F;
                }
                else
                {
                    pf = (c >> 4) & 1;
                    nr = (c >> 5) & 7;
                }

                switch ((c >> 2) & 3)
                {
                    case 0: desc = $"RR {crText}, n(r)={nr}, {pfText}={pf}"; return Ax25FrameType.S_RR;
                    case 1: desc = $"RNR {crText}, n(r)={nr}, {pfText}={pf}"; return Ax25FrameType.S_RNR;
                    case 2: desc = $"REJ {crText}, n(r)={nr}, {pfText}={pf}"; return Ax25FrameType.S_REJ;
                    case 3: desc = $"SREJ {crText}, n(r)={nr}, {pfText}={pf}"; return Ax25FrameType.S_SREJ;
                }
            }
            else
            {
                // Unnumbered frame
                pf = (c >> 4) & 1;

                switch (c & 0xEF)
                {
                    case 0x6F: desc = $"SABME {crText}, {pfText}={pf}"; return Ax25FrameType.U_SABME;
                    case 0x2F: desc = $"SABM {crText}, {pfText}={pf}"; return Ax25FrameType.U_SABM;
                    case 0x43: desc = $"DISC {crText}, {pfText}={pf}"; return Ax25FrameType.U_DISC;
                    case 0x0F: desc = $"DM {crText}, {pfText}={pf}"; return Ax25FrameType.U_DM;
                    case 0x63: desc = $"UA {crText}, {pfText}={pf}"; return Ax25FrameType.U_UA;
                    case 0x87: desc = $"FRMR {crText}, {pfText}={pf}"; return Ax25FrameType.U_FRMR;
                    case 0x03: desc = $"UI {crText}, {pfText}={pf}"; return Ax25FrameType.U_UI;
                    case 0xAF: desc = $"XID {crText}, {pfText}={pf}"; return Ax25FrameType.U_XID;
                    case 0xE3: desc = $"TEST {crText}, {pfText}={pf}"; return Ax25FrameType.U_TEST;
                    default: desc = "U other???"; return Ax25FrameType.U;
                }
            }

            return Ax25FrameType.NotAX25;
        }

        /// <summary>
        /// Check if packet is APRS format
        /// </summary>
        public bool IsAprs()
        {
            if (FrameLen == 0) return false;

            int ctrl = GetControl();
            int pid = GetPid();

            return NumAddr >= 2 && ctrl == Ax25Constants.UiFrame && pid == Ax25Constants.PidNoLayer3;
        }

        /// <summary>
        /// Check if packet is null/empty
        /// </summary>
        public bool IsNullFrame()
        {
            return FrameLen == 0;
        }

        /// <summary>
        /// Calculate dedupe CRC (excludes digipeaters)
        /// </summary>
        public ushort DedupeCrc()
        {
            string src = GetAddrWithSsid(Ax25Constants.Source);
            string dest = GetAddrWithSsid(Ax25Constants.Destination);
            var info = GetInfo(out int infoLen);

            // Remove trailing CR/LF/space
            while (infoLen >= 1 && (info[infoLen - 1] == '\r' ||
                                     info[infoLen - 1] == '\n' ||
                                     info[infoLen - 1] == ' '))
            {
                infoLen--;
            }

            ushort crc = 0xFFFF;
            crc = FcsCalc.Crc16(Encoding.ASCII.GetBytes(src), src.Length, crc);
            crc = FcsCalc.Crc16(Encoding.ASCII.GetBytes(dest), dest.Length, crc);
            crc = FcsCalc.Crc16(info, infoLen, crc);

            return crc;
        }

        /// <summary>
        /// Calculate CRC for entire frame (for multimodem duplicate detection)
        /// </summary>
        public ushort MultiModemCrc()
        {
            byte[] fbuf = new byte[Ax25Constants.MaxPacketLen];
            int flen = Pack(fbuf);

            ushort crc = 0xFFFF;
            crc = FcsCalc.Crc16(fbuf, flen, crc);

            return crc;
        }

        /// <summary>
        /// Print in safe format with non-printable as hex
        /// </summary>
        public static void SafePrint(string str, int len, bool asciiOnly)
        {
            if (len < 0)
                len = str.Length;

            if (len > str.Length)
                len = str.Length;

            StringBuilder safe = new StringBuilder();

            for (int i = 0; i < len; i++)
            {
                char ch = str[i];

                if (ch == ' ' && (i == len - 1 || str[i + 1] == '\0'))
                {
                    safe.Append($"<0x{(int)ch:X2}>");
                }
                else if (ch < ' ' || ch == 0x7F || ch == 0xFE || ch == 0xFF ||
                         (asciiOnly && ch >= 0x80))
                {
                    safe.Append($"<0x{(int)ch:X2}>");
                }
                else
                {
                    safe.Append(ch);
                }
            }

            Console.Write(safe.ToString());
        }

        /// <summary>
        /// Convert audio level to text
        /// </summary>
        public static bool AlevelToText(ALevel alevel, out string text)
        {
            if (alevel.Rec < 0)
            {
                text = "";
                return false;
            }

            if (alevel.Mark >= 0 && alevel.Space < 0)
            {
                // Baseband
                text = $"{alevel.Rec}({alevel.Mark:+0;-0}/{alevel.Space:+0;-0})";
            }
            else if ((alevel.Mark == -1 && alevel.Space == -1) ||
                     (alevel.Mark == -99 && alevel.Space == -99))
            {
                // PSK or FM demodulator
                text = $"{alevel.Rec}";
            }
            else if (alevel.Mark == -2 && alevel.Space == -2)
            {
                // DTMF
                text = $"{alevel.Rec}";
            }
            else
            {
                // AFSK
                text = $"{alevel.Rec}({alevel.Mark}/{alevel.Space})";
            }

            return true;
        }

        // Helper methods for offset calculations
        private int GetControlOffset()
        {
            return NumAddr * 7;
        }

        private int GetNumControl()
        {
            int c = FrameData[GetControlOffset()];

            if ((c & 0x01) == 0)
            {
                // I frame
                return (Modulo == Ax25Modulo.Modulo128) ? 2 : 1;
            }

            if ((c & 0x03) == 1)
            {
                // S frame
                return (Modulo == Ax25Modulo.Modulo128) ? 2 : 1;
            }

            return 1; // U frame
        }

        private int GetPidOffset()
        {
            return GetControlOffset() + GetNumControl();
        }

        private int GetNumPid()
        {
            int c = FrameData[GetControlOffset()];

            if ((c & 0x01) == 0 || c == 0x03 || c == 0x13)
            {
                // I or UI frame
                int pidOffset = GetPidOffset();
                if (pidOffset < FrameLen)
                {
                    int pid = FrameData[pidOffset];
                    if (pid == Ax25Constants.PidEscapeCharacter)
                    {
                        return 2;
                    }
                    return 1;
                }
            }

            return 0;
        }

        private int GetInfoOffset()
        {
            return GetControlOffset() + GetNumControl() + GetNumPid();
        }

        private int GetNumInfo()
        {
            int len = FrameLen - NumAddr * 7 - GetNumControl() - GetNumPid();
            if (len < 0)
                len = 0;
            return len;
        }
    }

    #endregion
}
