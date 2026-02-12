/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
using static HTCommander.Radio;

namespace HTCommander
{
    internal class ChannelImport
    {
        public static List<RadioChannelInfo> DecodeChannelsFile(string filename)
        {
            List<RadioChannelInfo> importChannels = new List<RadioChannelInfo>();
            string[] lines = File.ReadAllLines(filename);
            if ((lines == null) || (lines.Length < 2)) return importChannels;
            Dictionary<string, int> headers = lines[0].Split(',').Select((h, i) => new { h, i }).ToDictionary(x => Utils.RemoveQuotes(x.h.Trim()), x => x.i);

            // File format 1
            if (headers.ContainsKey("Location") && headers.ContainsKey("Name") && headers.ContainsKey("Frequency") && headers.ContainsKey("Mode"))
            {
                for (int i = 1; i < lines.Length; i++)
                {
                    RadioChannelInfo c = null;
                    try { c = ParseChannel1(lines[i].Split(','), headers); } catch (Exception) { }
                    if (c != null) { importChannels.Add(c); }
                }
            }

            // File format 2
            if (headers.ContainsKey("title") && headers.ContainsKey("tx_freq") && headers.ContainsKey("rx_freq"))
            {
                for (int i = 1; i < lines.Length; i++)
                {
                    RadioChannelInfo c = null;
                    try { c = ParseChannel2(lines[i].Split(','), headers); } catch (Exception) { }
                    if (c != null) { importChannels.Add(c); }
                }
            }

            // File format 2
            if (headers.ContainsKey("Frequency Output") && headers.ContainsKey("Frequency Input") && headers.ContainsKey("Description") && headers.ContainsKey("PL Output Tone") && headers.ContainsKey("PL Input Tone") && headers.ContainsKey("Mode"))
            {
                for (int i = 1; i < lines.Length; i++)
                {
                    RadioChannelInfo c = null;
                    try { c = ParseChannel3(lines[i].Split(','), headers); } catch (Exception) { }
                    if (c != null) { importChannels.Add(c); }
                }
            }

            return importChannels;
        }

        public static RadioChannelInfo ParseChannel1(string[] parts, Dictionary<string, int> headers)
        {
            RadioChannelInfo r = new RadioChannelInfo();

            // --- Basic Info ---
            r.channel_id = Utils.TryParseInt(Utils.GetValue(parts, headers, "Location")) ?? 0; // Default or handle error
            r.name_str = Utils.GetValue(parts, headers, "Name");
            double? rxFreqMHz = Utils.TryParseDouble(Utils.GetValue(parts, headers, "Frequency"));
            r.rx_freq = rxFreqMHz.HasValue ? (int)Math.Round(rxFreqMHz.Value * 1000000) : 0; // Store in Hz

            // --- Power Level ---
            r.tx_at_max_power = true; // Default to High
            r.tx_at_med_power = false;
            string powerStr = Utils.GetValue(parts, headers, "Power");
            if (!string.IsNullOrEmpty(powerStr) && powerStr.EndsWith("W", StringComparison.OrdinalIgnoreCase))
            {
                if (float.TryParse(powerStr.Substring(0, powerStr.Length - 1), NumberStyles.Any, CultureInfo.InvariantCulture, out float powerWatts))
                {
                    if (powerWatts <= 1.0f) { r.tx_at_max_power = false; r.tx_at_med_power = false; } // Low Power
                    else if (powerWatts <= 4.0f) { r.tx_at_max_power = false; r.tx_at_med_power = true; }  // Medium Power
                    else { r.tx_at_max_power = true; r.tx_at_med_power = false; } // High Power
                }
            }

            // --- Frequency: Duplex, Offset, Split ---
            string duplexValue = Utils.GetValue(parts, headers, "Duplex");
            string offsetValueStr = Utils.GetValue(parts, headers, "Offset");
            double? offsetMHz = Utils.TryParseDouble(offsetValueStr);

            if (duplexValue.Equals("split", StringComparison.OrdinalIgnoreCase) && offsetMHz.HasValue)
            {
                // 'Split' means the 'Offset' column *is* the TX frequency in MHz
                r.tx_freq = (int)Math.Round(offsetMHz.Value * 1000000);
            }
            else if (!string.IsNullOrEmpty(duplexValue) && (duplexValue == "+" || duplexValue == "-") && offsetMHz.HasValue)
            {
                // Standard duplex offset
                int offsetHz = (int)Math.Round(offsetMHz.Value * 1000000);
                int duplexSign = (duplexValue == "+") ? 1 : -1;
                r.tx_freq = r.rx_freq + (duplexSign * offsetHz);
            }
            else
            {
                // Simplex or invalid/missing duplex info
                r.tx_freq = r.rx_freq;
            }

            // --- Tone / Sub-Audio ---
            string toneMode = Utils.GetValue(parts, headers, "Tone");
            r.rx_sub_audio = 0; // Default to none
            r.tx_sub_audio = 0; // Default to none

            // Safely get potential tone/code values
            double? rToneFreq = Utils.TryParseDouble(Utils.GetValue(parts, headers, "rToneFreq"));
            double? cToneFreq = Utils.TryParseDouble(Utils.GetValue(parts, headers, "cToneFreq"));

            int rToneFreqValue = 0;
            int cToneFreqValue = 0;
            if (rToneFreq.HasValue) rToneFreqValue = (int)Math.Round(rToneFreq.Value * 100);
            if (cToneFreq.HasValue) cToneFreqValue = (int)Math.Round(cToneFreq.Value * 100);

            int? dtcsCode = Utils.TryParseInt(Utils.GetValue(parts, headers, "DtcsCode"));       // Used for TX DTCS
            int? rxDtcsCode = Utils.TryParseInt(Utils.GetValue(parts, headers, "RxDtcsCode"));   // Used for RX DTCS
            string crossMode = Utils.GetValue(parts, headers, "CrossMode");

            if (toneMode.Equals("Tone", StringComparison.OrdinalIgnoreCase))
            {
                // Standard 'Tone' means TX only. No Rx tone used.
                r.tx_sub_audio = rToneFreqValue;
                r.rx_sub_audio = 0;
            }
            else if (toneMode.Equals("TSQL", StringComparison.OrdinalIgnoreCase))
            {
                // Tone Squelch. Use the same tone for both send and receive.
                r.tx_sub_audio = cToneFreqValue;
                r.rx_sub_audio = cToneFreqValue;
            }
            else if (toneMode.Equals("DTCS", StringComparison.OrdinalIgnoreCase))
            {
                // Standard DTCS (Digital Tone Coded Squelch)
                if (dtcsCode.HasValue)
                {
                    r.tx_sub_audio = dtcsCode.Value;
                    r.rx_sub_audio = dtcsCode.Value;
                }
            }
            else if (toneMode.Equals("Cross", StringComparison.OrdinalIgnoreCase))
            {
                if (crossMode.Equals("Tone->Tone", StringComparison.OrdinalIgnoreCase))
                {
                    r.tx_sub_audio = rToneFreqValue;
                    r.rx_sub_audio = cToneFreqValue;
                }
                else if (crossMode.Equals("Tone->", StringComparison.OrdinalIgnoreCase))
                {
                    r.tx_sub_audio = 0;
                    r.rx_sub_audio = rToneFreqValue;
                }
                else if (crossMode.Equals("->Tone", StringComparison.OrdinalIgnoreCase))
                {
                    r.tx_sub_audio = cToneFreqValue;
                    r.rx_sub_audio = 0;
                }
                else if (crossMode.Equals("DTCS->DTCS", StringComparison.OrdinalIgnoreCase))
                {
                    if (dtcsCode.HasValue) { r.tx_sub_audio = dtcsCode.Value; }
                    r.rx_sub_audio = rxDtcsCode.Value;
                }
                else if (crossMode.Equals("Tone->DTCS", StringComparison.OrdinalIgnoreCase))
                {
                    r.tx_sub_audio = rToneFreqValue;
                    if (rxDtcsCode.HasValue) { r.rx_sub_audio = rxDtcsCode.Value; }
                }
                else if (crossMode.Equals("DTCS->Tone", StringComparison.OrdinalIgnoreCase))
                {
                    if (dtcsCode.HasValue) { r.tx_sub_audio = dtcsCode.Value; }
                    r.rx_sub_audio = cToneFreqValue;
                }
                else if (crossMode.Equals("DTCS->", StringComparison.OrdinalIgnoreCase))
                {
                    if (dtcsCode.HasValue) { r.tx_sub_audio = dtcsCode.Value; }
                    r.rx_sub_audio = 0;
                }
                else if (crossMode.Equals("->DTCS", StringComparison.OrdinalIgnoreCase))
                {
                    r.tx_sub_audio = 0;
                    if (rxDtcsCode.HasValue) { r.rx_sub_audio = rxDtcsCode.Value; }
                }
            }

            // --- Mode and Bandwidth ---
            string mode = Utils.GetValue(parts, headers, "Mode");
            // Defaults
            r.rx_mod = RadioModulationType.FM;
            r.tx_mod = RadioModulationType.FM;
            r.bandwidth = RadioBandwidthType.WIDE;

            if (mode.Equals("NFM", StringComparison.OrdinalIgnoreCase)) { r.rx_mod = r.tx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.NARROW; }
            else if (mode.Equals("FM", StringComparison.OrdinalIgnoreCase)) { r.rx_mod = r.tx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.WIDE; }
            else if (mode.Equals("DMR", StringComparison.OrdinalIgnoreCase)) { r.rx_mod = r.tx_mod = RadioModulationType.DMR; r.bandwidth = RadioBandwidthType.NARROW; } // DMR is typically 12.5kHz -> Narrow
            else if (mode.Equals("AM", StringComparison.OrdinalIgnoreCase)) { r.rx_mod = r.tx_mod = RadioModulationType.AM; r.bandwidth = RadioBandwidthType.WIDE; }
            // Add other modes like C4FM, P25 etc. as needed

            // --- Other Fields ---
            // Parse Skip, Comment, URCALL, RPT1CALL, RPT2CALL, DVCODE etc. if needed
            // Example: r.comment = GetValue(parts, headers, "Comment");

            return r;
        }

        private static RadioChannelInfo ParseChannel2(string[] parts, Dictionary<string, int> headers)
        {
            RadioChannelInfo r = new RadioChannelInfo();
            r.channel_id = 0;
            r.name_str = parts[headers["title"]];
            r.tx_freq = int.Parse(parts[headers["tx_freq"]]);
            r.rx_freq = int.Parse(parts[headers["rx_freq"]]);
            r.tx_sub_audio = int.Parse(parts[headers["tx_sub_audio(CTCSS=freq/DCS=number)"]]);
            r.rx_sub_audio = int.Parse(parts[headers["rx_sub_audio(CTCSS=freq/DCS=number)"]]);
            string power = parts[headers["tx_power(H/M/L)"]];
            r.tx_at_max_power = (power == "H");
            r.tx_at_med_power = (power == "M");
            r.bandwidth = (parts[headers["bandwidth(12500/25000)"]] == "25000") ? RadioBandwidthType.WIDE : RadioBandwidthType.NARROW;
            r.scan = (parts[headers["scan(0=OFF/1=ON)"]] == "1");
            r.talk_around = (parts[headers["talk around(0=OFF/1=ON)"]] == "1");
            r.pre_de_emph_bypass = (parts[headers["pre_de_emph_bypass(0=OFF/1=ON)"]] == "1");
            r.sign = (parts[headers["sign(0=OFF/1=ON)"]] == "1");
            r.tx_disable = (parts[headers["tx_dis(0=OFF/1=ON)"]] == "1");
            r.mute = (parts[headers["mute(0=OFF/1=ON)"]] == "1");
            string rx_mod = parts[headers["rx_modulation(0=FM/1=AM)"]];
            if (rx_mod == "AM") { r.rx_mod = RadioModulationType.AM; }
            if (rx_mod == "DMR") { r.rx_mod = RadioModulationType.DMR; }
            if (rx_mod == "FM") { r.rx_mod = RadioModulationType.FM; }
            if (rx_mod == "FO") { r.rx_mod = RadioModulationType.FM; }
            string tx_mod = parts[headers["tx_modulation(0=FM/1=AM)"]];
            if (tx_mod == "AM") { r.tx_mod = RadioModulationType.AM; }
            if (tx_mod == "DMR") { r.tx_mod = RadioModulationType.DMR; }
            if (tx_mod == "FM") { r.tx_mod = RadioModulationType.FM; }
            if (tx_mod == "FO") { r.tx_mod = RadioModulationType.FM; }
            return r;
        }

        private static RadioChannelInfo ParseChannel3(string[] parts, Dictionary<string, int> headers)
        {
            for (int i = 0; i < parts.Length; i++) { parts[i] = Utils.RemoveQuotes(parts[i].Trim()); }

            RadioChannelInfo r = new RadioChannelInfo();
            r.channel_id = 0;
            r.name_str = parts[headers["Description"]];
            if (r.name_str.Length > 10) { r.name_str = r.name_str.Substring(0, 10); }

            double? rxFreqMHz = Utils.TryParseDouble(Utils.GetValue(parts, headers, "Frequency Input"));
            r.rx_freq = rxFreqMHz.HasValue ? (int)Math.Round(rxFreqMHz.Value * 1000000) : 0; // Store in Hz

            double? txFreqMHz = Utils.TryParseDouble(Utils.GetValue(parts, headers, "Frequency Output"));
            r.tx_freq = txFreqMHz.HasValue ? (int)Math.Round(txFreqMHz.Value * 1000000) : 0; // Store in Hz
            if (r.rx_freq == 0) { r.rx_freq = r.tx_freq; }
            if (r.tx_freq == 0) { r.tx_freq = r.rx_freq; }
            if ((r.tx_freq == 0) && (r.rx_freq == 0)) return null;

            string rx_mod = parts[headers["Mode"]];
            if (rx_mod == "AM") { r.rx_mod = RadioModulationType.AM; r.bandwidth = RadioBandwidthType.WIDE; }
            //else if (rx_mod == "DMR") { r.rx_mod = RadioModulationType.DMR; r.bandwidth = RadioBandwidthType.WIDE; }
            else if (rx_mod == "FM") { r.rx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.WIDE; }
            else if (rx_mod == "FMN") { r.rx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.NARROW; }
            else return null;
            r.tx_mod = r.rx_mod;

            string rx_sub = parts[headers["PL Output Tone"]];
            string tx_sub = parts[headers["PL Input Tone"]];
            if (tx_sub.Length == 0) { tx_sub = rx_sub; } // If no TX tone, use RX tone
            if (rx_sub.Length == 0) { rx_sub = tx_sub; } // If no RX tone, use TX tone

            if (rx_sub.EndsWith(" PL"))
            {
                double? rx_sub_audio = Utils.TryParseDouble(rx_sub.Substring(0, rx_sub.Length - 3));
                r.rx_sub_audio = rx_sub_audio.HasValue ? (int)Math.Round(rx_sub_audio.Value * 100) : 0;
            }
            //else if (rx_sub.EndsWith(" DCS")) { r.rx_sub_audio = int.Parse(rx_sub.Substring(0, rx_sub.Length - 4)); }
            //else if (rx_sub.EndsWith(" DPL")) { r.rx_sub_audio = int.Parse(rx_sub.Substring(0, rx_sub.Length - 4)); }

            if (tx_sub.EndsWith(" PL"))
            {
                double? tx_sub_audio = Utils.TryParseDouble(rx_sub.Substring(0, rx_sub.Length - 3));
                r.tx_sub_audio = tx_sub_audio.HasValue ? (int)Math.Round(tx_sub_audio.Value * 100) : 0;
            }
            //else if (tx_sub.EndsWith(" DCS")) { r.tx_sub_audio = int.Parse(tx_sub.Substring(0, tx_sub.Length - 4)); }
            //else if (tx_sub.EndsWith(" DPL")) { r.tx_sub_audio = int.Parse(tx_sub.Substring(0, tx_sub.Length - 4)); }

            r.scan = false;
            r.tx_disable = false;
            r.mute = false;
            r.tx_at_max_power = true;
            r.tx_at_med_power = false;
            r.talk_around = false;
            r.pre_de_emph_bypass = false;

            return r;
        }

        public static void WriteChannelsToFile(RadioChannelInfo[] channels, string filename, int format)
        {
            if (format == 1)
            {
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)");
                foreach (RadioChannelInfo c in channels)
                {
                    if ((c != null) && (c.tx_freq != 0) && (c.rx_freq != 0))
                    {
                        string power = "L";
                        if (c.tx_at_max_power) { power = "H"; }
                        if (c.tx_at_med_power) { power = "M"; }
                        string[] values = new string[] { c.name_str, c.tx_freq.ToString(), c.rx_freq.ToString(), c.tx_sub_audio.ToString(), c.rx_sub_audio.ToString(), power, c.bandwidth == RadioBandwidthType.NARROW ? "12500" : "25000", c.scan ? "1" : "0", c.talk_around ? "1" : "0", c.pre_de_emph_bypass ? "1" : "0", c.sign ? "1" : "0", c.tx_disable ? "1" : "0", c.mute ? "1" : "0", ((int)c.rx_mod).ToString(), ((int)c.tx_mod).ToString() };
                        sb.AppendLine(string.Join(",", values));
                    }
                }
                File.WriteAllText(filename, sb.ToString());
            }
            if (format == 2)
            {
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power");
                for (int i = 0; i < channels.Length; i++)
                {
                    RadioChannelInfo c = channels[i];
                    if ((c != null) && (c.tx_freq != 0) && (c.rx_freq != 0))
                    {
                        string duplex = "";
                        if (c.tx_freq < c.rx_freq) { duplex = "-"; }
                        if (c.tx_freq > c.rx_freq) { duplex = "+"; }

                        double offset = ((double)Math.Abs(c.tx_freq - c.rx_freq)) / 1000000;

                        // (None),Tone,TSQL,DTCS,DTCS-R,TSQL-R,Cross
                        string tone = "";
                        string rToneFreq = "";
                        string cToneFreq = "";
                        string DtcsCode = "";
                        string DtcsPolarity = "";
                        if ((c.tx_sub_audio >= 1000) && (c.rx_sub_audio >= 1000))
                        {
                            tone = "TONE";
                            rToneFreq = ((double)c.rx_sub_audio / 100).ToString();
                            cToneFreq = ((double)c.tx_sub_audio / 100).ToString();
                        }
                        else if ((c.tx_sub_audio > 0) && (c.rx_sub_audio > 0) && (c.tx_sub_audio < 1000) && (c.rx_sub_audio < 1000) && (c.rx_sub_audio == c.tx_sub_audio))
                        {
                            tone = "DTCS";
                            DtcsCode = c.rx_sub_audio.ToString();
                            DtcsPolarity = "NN";
                        }

                        string Mode = c.rx_mod.ToString();
                        if (c.rx_mod == RadioModulationType.FM)
                        {
                            if (c.bandwidth == RadioBandwidthType.WIDE) { Mode = "FM"; }
                            if (c.bandwidth == RadioBandwidthType.NARROW) { Mode = "NFM"; }
                        }

                        string Power = "";
                        if (c.tx_at_max_power) { Power = "5.0W"; }
                        else if (c.tx_at_med_power) { Power = "3.0W"; }
                        else { Power = "1.0W"; }

                        string[] values = new string[] { i.ToString(), c.name_str, (((double)c.rx_freq) / 1000000).ToString("F6"), duplex, offset.ToString("F6"), tone, rToneFreq, cToneFreq, DtcsCode, DtcsPolarity, Mode, "", "", Power };
                        sb.AppendLine(string.Join(",", values));
                    }
                }
                File.WriteAllText(filename, sb.ToString());
            }
        }
    }
}
