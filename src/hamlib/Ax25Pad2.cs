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

//
// Ax25Pad2.cs - AX.25 packet assembler and disassembler, part 2
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Extended AX.25 frame construction methods for U, S, and I frames.
    /// The original ax25_pad.cs was written with APRS in mind and handles UI frames.
    /// This adds support for the more general cases of AX.25 frames.
    /// </summary>
    public static class Ax25Pad2
    {
        #region U Frame Construction

        /// <summary>
        /// Construct a U (Unnumbered) frame.
        /// </summary>
        /// <param name="addrs">Array of addresses (destination, source, digipeaters)</param>
        /// <param name="numAddr">Number of addresses, range 2..10</param>
        /// <param name="cr">Command/response flag: Cmd for command, Res for response</param>
        /// <param name="ftype">Frame type (SABME, SABM, DISC, DM, UA, FRMR, UI, XID, TEST)</param>
        /// <param name="pf">Poll/Final flag</param>
        /// <param name="pid">Protocol ID (used ONLY for UI type, normally 0xF0)</param>
        /// <param name="pinfo">Data for Info field (allowed for UI, XID, TEST, FRMR)</param>
        /// <param name="infoLen">Length of Info field</param>
        /// <returns>New packet object, or null on error</returns>
        public static Packet UFrame(string[] addrs, int numAddr, CmdRes cr, Ax25FrameType ftype,
            int pf, int pid, byte[] pinfo, int infoLen)
        {
            var thisP = new Packet();
            if (thisP == null)
                return null;

            thisP.Modulo = Ax25Modulo.Unknown;

            if (!SetAddrs(thisP, addrs, numAddr, cr))
            {
                Console.WriteLine("Internal error in UFrame: Could not set addresses for U frame.");
                return null;
            }

            int ctrl = 0;
            int t = 999; // 1 = must be cmd, 0 = must be response, 2 = can be either
            int i = 0;   // Is Info part allowed?

            switch (ftype)
            {
                case Ax25FrameType.U_SABME:  ctrl = 0x6F; t = 1; break;
                case Ax25FrameType.U_SABM:   ctrl = 0x2F; t = 1; break;
                case Ax25FrameType.U_DISC:   ctrl = 0x43; t = 1; break;
                case Ax25FrameType.U_DM:     ctrl = 0x0F; t = 0; break;
                case Ax25FrameType.U_UA:     ctrl = 0x63; t = 0; break;
                case Ax25FrameType.U_FRMR:   ctrl = 0x87; t = 0; i = 1; break;
                case Ax25FrameType.U_UI:     ctrl = 0x03; t = 2; i = 1; break;
                case Ax25FrameType.U_XID:    ctrl = 0xAF; t = 2; i = 1; break;
                case Ax25FrameType.U_TEST:   ctrl = 0xE3; t = 2; i = 1; break;

                default:
                    Console.WriteLine($"Internal error in UFrame: Invalid ftype {ftype} for U frame.");
                    return null;
            }

            if (pf != 0)
                ctrl |= 0x10;

            // Check command/response validity
            if (t != 2)
            {
                if (cr != (CmdRes)t)
                {
                    Console.WriteLine($"Internal error in UFrame: U frame, cr is {cr} but must be {t}. ftype={ftype}");
                }
            }

            // Add control byte
            thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;

            // Add PID for UI frames
            if (ftype == Ax25FrameType.U_UI)
            {
                // Definitely don't want pid value of 0 (not in valid list)
                // or 0xff (which means more bytes follow)
                if (pid < 0 || pid == 0 || pid == 0xFF)
                {
                    Console.WriteLine($"Internal error in UFrame: U frame, Invalid pid value 0x{pid:X2}.");
                    pid = Ax25Constants.PidNoLayer3;
                }
                thisP.FrameData[thisP.FrameLen++] = (byte)pid;
            }

            // Add information field if allowed and provided
            if (i != 0)
            {
                if (pinfo != null && infoLen > 0)
                {
                    if (infoLen > Ax25Constants.MaxInfoLen)
                    {
                        Console.WriteLine($"Internal error in UFrame: U frame, Invalid information field length {infoLen}.");
                        infoLen = Ax25Constants.MaxInfoLen;
                    }
                    Array.Copy(pinfo, 0, thisP.FrameData, thisP.FrameLen, infoLen);
                    thisP.FrameLen += infoLen;
                }
            }
            else
            {
                if (pinfo != null && infoLen > 0)
                {
                    Console.WriteLine("Internal error in UFrame: Info part not allowed for U frame type.");
                }
            }

            thisP.FrameData[thisP.FrameLen] = 0;

            Debug.Assert(thisP.FrameLen <= Ax25Constants.MaxPacketLen);

            return thisP;
        }

        #endregion

        #region S Frame Construction

        /// <summary>
        /// Construct an S (Supervisory) frame.
        /// </summary>
        /// <param name="addrs">Array of addresses (destination, source, digipeaters)</param>
        /// <param name="numAddr">Number of addresses, range 2..10</param>
        /// <param name="cr">Command/response flag: Cmd for command, Res for response</param>
        /// <param name="ftype">Frame type (RR, RNR, REJ, SREJ)</param>
        /// <param name="modulo">8 or 128 (determines 1 or 2 control bytes)</param>
        /// <param name="nr">N(R) field - receive sequence number</param>
        /// <param name="pf">Poll/Final flag</param>
        /// <param name="pinfo">Data for Info field (allowed only for SREJ)</param>
        /// <param name="infoLen">Length of Info field</param>
        /// <returns>New packet object, or null on error</returns>
        public static Packet SFrame(string[] addrs, int numAddr, CmdRes cr, Ax25FrameType ftype,
            int modulo, int nr, int pf, byte[] pinfo, int infoLen)
        {
            var thisP = new Packet();
            if (thisP == null)
                return null;

            if (!SetAddrs(thisP, addrs, numAddr, cr))
            {
                Console.WriteLine("Internal error in SFrame: Could not set addresses for S frame.");
                return null;
            }

            if (modulo != 8 && modulo != 128)
            {
                Console.WriteLine($"Internal error in SFrame: Invalid modulo {modulo} for S frame.");
                modulo = 8;
            }
            thisP.Modulo = (Ax25Modulo)modulo;

            if (nr < 0 || nr >= modulo)
            {
                Console.WriteLine($"Internal error in SFrame: Invalid N(R) {nr} for S frame.");
                nr &= (modulo - 1);
            }

            // Erratum: The AX.25 spec is not clear about whether SREJ should be command, response, or both.
            // The underlying X.25 spec clearly says it is response only. Let's go with that.
            if (ftype == Ax25FrameType.S_SREJ && cr != CmdRes.Res)
            {
                Console.WriteLine("Internal error in SFrame: SREJ must be response.");
            }

            int ctrl = 0;
            switch (ftype)
            {
                case Ax25FrameType.S_RR:   ctrl = 0x01; break;
                case Ax25FrameType.S_RNR:  ctrl = 0x05; break;
                case Ax25FrameType.S_REJ:  ctrl = 0x09; break;
                case Ax25FrameType.S_SREJ: ctrl = 0x0D; break;

                default:
                    Console.WriteLine($"Internal error in SFrame: Invalid ftype {ftype} for S frame.");
                    return null;
            }

            if (modulo == 8)
            {
                // Modulo 8: single control byte
                if (pf != 0)
                    ctrl |= 0x10;
                ctrl |= (nr << 5);
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;
            }
            else
            {
                // Modulo 128: two control bytes
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;

                ctrl = (pf & 1);
                ctrl |= (nr << 1);
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;
            }

            // Add information field for SREJ if provided
            if (ftype == Ax25FrameType.S_SREJ)
            {
                if (pinfo != null && infoLen > 0)
                {
                    if (infoLen > Ax25Constants.MaxInfoLen)
                    {
                        Console.WriteLine($"Internal error in SFrame: SREJ frame, Invalid information field length {infoLen}.");
                        infoLen = Ax25Constants.MaxInfoLen;
                    }
                    Array.Copy(pinfo, 0, thisP.FrameData, thisP.FrameLen, infoLen);
                    thisP.FrameLen += infoLen;
                }
            }
            else
            {
                if (pinfo != null || infoLen != 0)
                {
                    Console.WriteLine("Internal error in SFrame: Info part not allowed for RR, RNR, REJ frame.");
                }
            }

            thisP.FrameData[thisP.FrameLen] = 0;

            Debug.Assert(thisP.FrameLen <= Ax25Constants.MaxPacketLen);

            return thisP;
        }

        #endregion

        #region I Frame Construction

        /// <summary>
        /// Construct an I (Information) frame.
        /// </summary>
        /// <param name="addrs">Array of addresses (destination, source, digipeaters)</param>
        /// <param name="numAddr">Number of addresses, range 2..10</param>
        /// <param name="cr">Command/response flag: Cmd for command, Res for response</param>
        /// <param name="modulo">8 or 128 (determines 1 or 2 control bytes)</param>
        /// <param name="nr">N(R) field - receive sequence number</param>
        /// <param name="ns">N(S) field - send sequence number</param>
        /// <param name="pf">Poll/Final flag</param>
        /// <param name="pid">Protocol ID (normally 0xF0 for no layer 3)</param>
        /// <param name="pinfo">Data for Info field</param>
        /// <param name="infoLen">Length of Info field</param>
        /// <returns>New packet object, or null on error</returns>
        public static Packet IFrame(string[] addrs, int numAddr, CmdRes cr, int modulo,
            int nr, int ns, int pf, int pid, byte[] pinfo, int infoLen)
        {
            var thisP = new Packet();
            if (thisP == null)
                return null;

            if (!SetAddrs(thisP, addrs, numAddr, cr))
            {
                Console.WriteLine("Internal error in IFrame: Could not set addresses for I frame.");
                return null;
            }

            if (modulo != 8 && modulo != 128)
            {
                Console.WriteLine($"Internal error in IFrame: Invalid modulo {modulo} for I frame.");
                modulo = 8;
            }
            thisP.Modulo = (Ax25Modulo)modulo;

            if (nr < 0 || nr >= modulo)
            {
                Console.WriteLine($"Internal error in IFrame: Invalid N(R) {nr} for I frame.");
                nr &= (modulo - 1);
            }

            if (ns < 0 || ns >= modulo)
            {
                Console.WriteLine($"Internal error in IFrame: Invalid N(S) {ns} for I frame.");
                ns &= (modulo - 1);
            }

            int ctrl = 0;

            if (modulo == 8)
            {
                // Modulo 8: single control byte
                ctrl = (nr << 5) | (ns << 1);
                if (pf != 0)
                    ctrl |= 0x10;
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;
            }
            else
            {
                // Modulo 128: two control bytes
                ctrl = ns << 1;
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;

                ctrl = nr << 1;
                if (pf != 0)
                    ctrl |= 0x01;
                thisP.FrameData[thisP.FrameLen++] = (byte)ctrl;
            }

            // Add PID
            // Definitely don't want pid value of 0 (not in valid list)
            // or 0xff (which means more bytes follow)
            if (pid < 0 || pid == 0 || pid == 0xFF)
            {
                Console.WriteLine($"Warning: Client application provided invalid PID value, 0x{pid:X2}, for I frame.");
                pid = Ax25Constants.PidNoLayer3;
            }
            thisP.FrameData[thisP.FrameLen++] = (byte)pid;

            // Add information field
            if (pinfo != null && infoLen > 0)
            {
                if (infoLen > Ax25Constants.MaxInfoLen)
                {
                    Console.WriteLine($"Internal error in IFrame: I frame, Invalid information field length {infoLen}.");
                    infoLen = Ax25Constants.MaxInfoLen;
                }
                Array.Copy(pinfo, 0, thisP.FrameData, thisP.FrameLen, infoLen);
                thisP.FrameLen += infoLen;
            }

            thisP.FrameData[thisP.FrameLen] = 0;

            Debug.Assert(thisP.FrameLen <= Ax25Constants.MaxPacketLen);

            return thisP;
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Set address fields in the packet.
        /// </summary>
        /// <param name="pp">Packet object</param>
        /// <param name="addrs">Array of addresses</param>
        /// <param name="numAddr">Number of addresses (2..10)</param>
        /// <param name="cr">Command/response flag</param>
        /// <returns>True on success, false on error</returns>
        private static bool SetAddrs(Packet pp, string[] addrs, int numAddr, CmdRes cr)
        {
            Debug.Assert(pp.FrameLen == 0);
            Debug.Assert(cr == CmdRes.Cmd || cr == CmdRes.Res);

            if (numAddr < Ax25Constants.MinAddrs || numAddr > Ax25Constants.MaxAddrs)
            {
                Console.WriteLine($"INTERNAL ERROR: SetAddrs, num_addr = {numAddr}");
                return false;
            }

            for (int n = 0; n < numAddr; n++)
            {
                int offset = n * 7;
                bool strict = true;

                if (!Packet.ParseAddr(n, addrs[n], strict, out string oaddr, out int ssid, out bool heard))
                {
                    return false;
                }

                // Fill in address (6 bytes, shifted left 1 bit)
                for (int i = 0; i < 6; i++)
                {
                    if (i < oaddr.Length)
                        pp.FrameData[offset + i] = (byte)(oaddr[i] << 1);
                    else
                        pp.FrameData[offset + i] = (byte)(' ' << 1);
                }

                // Fill in SSID byte
                byte ssidByte = (byte)(0x60 | ((ssid & 0xF) << 1));

                // Set command/response flag
                switch (n)
                {
                    case Ax25Constants.Destination:
                        if (cr == CmdRes.Cmd)
                            ssidByte |= 0x80;
                        break;

                    case Ax25Constants.Source:
                        if (cr == CmdRes.Res)
                            ssidByte |= 0x80;
                        break;

                    default:
                        // Digipeaters don't set C/R bit
                        break;
                }

                // Set last address bit if this is the final address
                if (n == numAddr - 1)
                {
                    ssidByte |= 0x01;
                }

                pp.FrameData[offset + 6] = ssidByte;
                pp.FrameLen += 7;
            }

            pp.NumAddr = numAddr;
            return true;
        }

        #endregion

        #region Test/Debug Methods

        /// <summary>
        /// Test harness for creating various frame types.
        /// This is equivalent to the main() function in the C version when PAD2TEST is defined.
        /// </summary>
        public static void RunTests()
        {
            Console.WriteLine("=== AX25 Pad2 Test Suite ===\n");

            string[] addrs = new string[Ax25Constants.MaxAddrs];
            addrs[0] = "W2UB";
            addrs[1] = "WB2OSZ-15";
            int numAddr = 2;

            // Test U frames
            Console.WriteLine("\n=== Testing U Frames ===\n");

            for (Ax25FrameType ftype = Ax25FrameType.U_SABME; ftype <= Ax25FrameType.U_TEST; ftype++)
            {
                for (int pf = 0; pf <= 1; pf++)
                {
                    int cmin = 0, cmax = 1;

                    // Determine valid command/response values for this frame type
                    switch (ftype)
                    {
                        case Ax25FrameType.U_SABME:
                        case Ax25FrameType.U_SABM:
                        case Ax25FrameType.U_DISC:
                            cmin = 1; cmax = 1; // Command only
                            break;
                        case Ax25FrameType.U_DM:
                        case Ax25FrameType.U_UA:
                        case Ax25FrameType.U_FRMR:
                            cmin = 0; cmax = 0; // Response only
                            break;
                        case Ax25FrameType.U_UI:
                        case Ax25FrameType.U_XID:
                        case Ax25FrameType.U_TEST:
                            cmin = 0; cmax = 1; // Either
                            break;
                    }

                    for (int cr = cmin; cr <= cmax; cr++)
                    {
                        Console.WriteLine($"\nConstruct U frame, cr={cr}, ftype={ftype}, pid=0xF0");

                        var pp = UFrame(addrs, numAddr, (CmdRes)cr, ftype, pf, 0xF0, null, 0);
                        if (pp != null)
                        {
                            PrintFrameInfo(pp);
                        }
                    }
                }
            }

            // Test S frames
            Console.WriteLine("\n\n=== Testing S Frames ===\n");

            addrs[2] = "DIGI1-1";
            numAddr = 3;

            for (Ax25FrameType ftype = Ax25FrameType.S_RR; ftype <= Ax25FrameType.S_SREJ; ftype++)
            {
                for (int pf = 0; pf <= 1; pf++)
                {
                    // Test modulo 8
                    int modulo = 8;
                    int nr = modulo / 2 + 1;

                    for (int cr = 0; cr <= 1; cr++)
                    {
                        Console.WriteLine($"\nConstruct S frame (mod {modulo}), cr={cr}, ftype={ftype}");

                        var pp = SFrame(addrs, numAddr, (CmdRes)cr, ftype, modulo, nr, pf, null, 0);
                        if (pp != null)
                        {
                            PrintFrameInfo(pp);
                        }
                    }

                    // Test modulo 128
                    modulo = 128;
                    nr = modulo / 2 + 1;

                    for (int cr = 0; cr <= 1; cr++)
                    {
                        Console.WriteLine($"\nConstruct S frame (mod {modulo}), cr={cr}, ftype={ftype}");

                        var pp = SFrame(addrs, numAddr, (CmdRes)cr, ftype, modulo, nr, pf, null, 0);
                        if (pp != null)
                        {
                            PrintFrameInfo(pp);
                        }
                    }
                }
            }

            // Test SREJ with info field
            Console.WriteLine("\n\nConstruct Multi-SREJ S frame with info");
            byte[] srejInfo = { 1 << 1, 2 << 1, 3 << 1, 4 << 1 };
            var srejPacket = SFrame(addrs, numAddr, CmdRes.Res, Ax25FrameType.S_SREJ, 128, 127, 1, srejInfo, srejInfo.Length);
            if (srejPacket != null)
            {
                PrintFrameInfo(srejPacket);
            }

            // Test I frames
            Console.WriteLine("\n\n=== Testing I Frames ===\n");

            byte[] testInfo = System.Text.Encoding.ASCII.GetBytes("The rain in Spain stays mainly on the plain.");

            for (int pf = 0; pf <= 1; pf++)
            {
                // Test modulo 8
                int modulo = 8;
                int nr = 0x55 & (modulo - 1);
                int ns = 0xAA & (modulo - 1);

                for (int cr = 0; cr <= 1; cr++)
                {
                    Console.WriteLine($"\nConstruct I frame (mod {modulo}), cr={cr}, pid=0xF0");

                    var pp = IFrame(addrs, numAddr, (CmdRes)cr, modulo, nr, ns, pf, 0xF0, testInfo, testInfo.Length);
                    if (pp != null)
                    {
                        PrintFrameInfo(pp);
                    }
                }

                // Test modulo 128
                modulo = 128;
                nr = 0x55 & (modulo - 1);
                ns = 0xAA & (modulo - 1);

                for (int cr = 0; cr <= 1; cr++)
                {
                    Console.WriteLine($"\nConstruct I frame (mod {modulo}), cr={cr}, pid=0xF0");

                    var pp = IFrame(addrs, numAddr, (CmdRes)cr, modulo, nr, ns, pf, 0xF0, testInfo, testInfo.Length);
                    if (pp != null)
                    {
                        PrintFrameInfo(pp);
                    }
                }
            }

            Console.WriteLine("\n\n=== SUCCESS! ===\n");
        }

        /// <summary>
        /// Print frame information for debugging.
        /// </summary>
        private static void PrintFrameInfo(Packet pp)
        {
            Console.WriteLine($"  Addresses: {pp.FormatAddrs()}");
            
            var ftype = pp.GetFrameType(out var cr, out string desc, out int pf, out int nr, out int ns);
            Console.WriteLine($"  Type: {desc}");
            
            var info = pp.GetInfo(out int infoLen);
            if (infoLen > 0)
            {
                Console.Write("  Info: ");
                for (int i = 0; i < Math.Min(infoLen, 50); i++)
                {
                    if (info[i] >= 32 && info[i] < 127)
                        Console.Write((char)info[i]);
                    else
                        Console.Write($"<{info[i]:X2}>");
                }
                if (infoLen > 50)
                    Console.Write("...");
                Console.WriteLine();
            }

            Console.Write("  Raw: ");
            for (int i = 0; i < Math.Min(pp.FrameLen, 50); i++)
            {
                Console.Write($"{pp.FrameData[i]:X2} ");
            }
            if (pp.FrameLen > 50)
                Console.Write("...");
            Console.WriteLine();
        }

        #endregion
    }
}
