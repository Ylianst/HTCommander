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

using aprsparser;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class PacketCaptureViewerForm : Form
    {
        private MainForm parent;
        private string filename;

        public PacketCaptureViewerForm(MainForm parent, string filename)
        {
            this.parent = parent;
            this.filename = filename;
            InitializeComponent();
        }

        private void packetsListView_Resize(object sender, EventArgs e)
        {
            packetsListView.Columns[2].Width = packetsListView.Width - packetsListView.Columns[1].Width - packetsListView.Columns[0].Width - 28;
        }

        private void packetDecodeListView_Resize(object sender, EventArgs e)
        {
            packetDecodeListView.Columns[1].Width = packetDecodeListView.Width - packetDecodeListView.Columns[0].Width - 28;
        }

        private void PacketCaptureViewerForm_Load(object sender, EventArgs e)
        {
            FileInfo fileInfo = new FileInfo(filename);
            Text += " - " + fileInfo.Name;

            // Read the packets file
            string[] lines = null;
            try { lines = File.ReadAllLines(filename); } catch (Exception) { }
            if (lines != null)
            {
                List<ListViewItem> items = new List<ListViewItem>(lines.Length);
                for (int i = 0; i < lines.Length; i++)
                {
                    // Reac the packets
                    string[] s = lines[i].Split(',');
                    DateTime t = new DateTime(long.Parse(s[0]));
                    bool incoming = (s[1] == "1");
                    if ((s[2] != "TncFrag") && (s[2] != "TncFrag2")) continue;
                    int cid = int.Parse(s[3]);
                    int rid = -1;
                    string cn = cid.ToString();
                    byte[] f;
                    if (s[2] == "TncFrag")
                    {
                        f = Utils.HexStringToByteArray(s[4]);
                    }
                    else
                    {
                        rid = int.Parse(s[4]);
                        cn = s[5];
                        f = Utils.HexStringToByteArray(s[6]);
                    }

                    // Process the packets
                    TncDataFragment fragment = new TncDataFragment(true, 0, f, cid, rid);
                    fragment.time = t;
                    fragment.channel_name = cn;
                    fragment.incoming = incoming;

                    // Add to the packet capture tab
                    ListViewItem l = new ListViewItem(new string[] { fragment.time.ToShortTimeString(), fragment.channel_name, Utils.TncDataFragmentToShortString(fragment) });
                    l.ImageIndex = fragment.incoming ? 5 : 4;
                    l.Tag = fragment;
                    items.Add(l);
                }

                items.Sort((a, b) => DateTime.Compare(((TncDataFragment)b.Tag).time, ((TncDataFragment)a.Tag).time));
                packetsListView.Items.AddRange(items.ToArray());
            }
        }

        private void addPacketDecodeLine(int group, string title, string value)
        {
            ListViewItem l = new ListViewItem(new string[] { title, value });
            l.Group = packetDecodeListView.Groups[group];
            packetDecodeListView.Items.Add(l);
        }

        private void packetsListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            packetDecodeListView.Items.Clear();
            if (packetsListView.SelectedItems.Count == 0) return;
            ListViewItem l = packetsListView.SelectedItems[0];
            if (l.Tag == null) return;
            TncDataFragment fragment = (TncDataFragment)l.Tag;
            if (fragment.channel_id >= 0) { addPacketDecodeLine(0, "Channel", (fragment.incoming ? "Received" : "Sent") + " on " + (fragment.channel_id + 1)); }
            addPacketDecodeLine(0, "Time", fragment.time.ToString());
            addPacketDecodeLine(0, "Size", fragment.data.Length + " byte" + (fragment.data.Length > 1 ? "s" : ""));

            StringBuilder sb = new StringBuilder();
            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
            if (packet == null)
            {
                addPacketDecodeLine(1, "Decode", "AX25 Decoder failed to decode packet.");
            }
            else
            {
                for (int i = 0; i < packet.addresses.Count; i++)
                {
                    sb.Clear();
                    AX25Address addr = packet.addresses[i];
                    sb.Append(addr.CallSignWithId);
                    sb.Append("  ");
                    sb.Append((addr.CRBit1) ? "X" : "-");
                    sb.Append((addr.CRBit2) ? "X" : "-");
                    sb.Append((addr.CRBit3) ? "X" : "-");
                    addPacketDecodeLine(1, "Address " + (i + 1), sb.ToString());
                }
                addPacketDecodeLine(1, "Type", packet.type.ToString().Replace("_", "-"));
                sb.Clear();
                sb.Append("NS:" + packet.ns + ", NR:" + packet.nr);
                if (packet.command) { sb.Append(", Command"); }
                if (packet.pollFinal) { sb.Append(", PollFinal"); }
                if (packet.modulo128) { sb.Append(", Modulo128"); }
                if (sb.Length > 2) { addPacketDecodeLine(1, "Control", sb.ToString()); }
                if (packet.pid > 0) { addPacketDecodeLine(1, "Protocol ID", packet.pid.ToString()); }
                if (packet.dataStr != null) { addPacketDecodeLine(2, "Data", packet.dataStr); }
                if (packet.data != null) { addPacketDecodeLine(2, "Data HEX", Utils.BytesToHex(packet.data)); }

                if (packet.pid == 242)
                {
                    byte[] decompressedData = null;
                    try { decompressedData = Utils.DecompressBrotli(packet.data); } catch { }
                    if (decompressedData != null)
                    {
                        addPacketDecodeLine(5, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                        addPacketDecodeLine(5, "Data HEX", Utils.BytesToHex(decompressedData));
                        byte[] deflateBuf = Utils.CompressDeflate(decompressedData);
                        addPacketDecodeLine(5, "Stats", $"Brotli {decompressedData.Length} --> {packet.data.Length}, Deflate would have been {deflateBuf.Length}");
                    }
                }

                if (packet.pid == 243)
                {
                    byte[] decompressedData = null;
                    try { decompressedData = Utils.DecompressDeflate(packet.data); } catch { }
                    if (decompressedData != null)
                    {
                        addPacketDecodeLine(5, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                        addPacketDecodeLine(5, "Data HEX", Utils.BytesToHex(decompressedData));
                        byte[] brotliBuf = Utils.CompressBrotli(decompressedData);
                        addPacketDecodeLine(5, "Stats", $"Deflate {decompressedData.Length} --> {packet.data.Length}, Brotli would have been {brotliBuf.Length}");
                    }
                }

                if ((packet.type == AX25Packet.FrameType.U_FRAME) && (packet.pid == 240))
                {
                    AprsPacket aprsPacket = AprsPacket.Parse(packet);
                    if (aprsPacket == null)
                    {
                        addPacketDecodeLine(3, "Decode", "APRS Decoder failed to decode packet.");
                    }
                    else
                    {
                        addPacketDecodeLine(3, "Type", aprsPacket.DataType.ToString());
                        if (aprsPacket.TimeStamp != null) { addPacketDecodeLine(3, "Time Stamp", aprsPacket.TimeStamp.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.DestCallsign.StationCallsign)) { addPacketDecodeLine(3, "Destination", aprsPacket.DestCallsign.StationCallsign.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.InformationField)) { addPacketDecodeLine(3, "Information", aprsPacket.InformationField.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.Comment)) { addPacketDecodeLine(3, "Comment", aprsPacket.Comment.ToString()); }
                        if (aprsPacket.SymbolTableIdentifier != 0) { addPacketDecodeLine(3, "Symbol Code", aprsPacket.SymbolTableIdentifier.ToString()); }

                        if (aprsPacket.Position.Speed != 0) { addPacketDecodeLine(4, "Speed", aprsPacket.Position.Speed.ToString()); }
                        if (aprsPacket.Position.Altitude != 0) { addPacketDecodeLine(4, "Altitude", aprsPacket.Position.Altitude.ToString()); }
                        if (aprsPacket.Position.Ambiguity != 0) { addPacketDecodeLine(4, "Ambiguity", aprsPacket.Position.Ambiguity.ToString()); }
                        if (aprsPacket.Position.Course != 0) { addPacketDecodeLine(4, "Course", aprsPacket.Position.Course.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.Position.Gridsquare)) { addPacketDecodeLine(4, "Gridsquare", aprsPacket.Position.Gridsquare.ToString()); }
                        if (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) { addPacketDecodeLine(4, "Latitude", aprsPacket.Position.CoordinateSet.Latitude.Value.ToString()); }
                        if (aprsPacket.Position.CoordinateSet.Longitude.Value != 0) { addPacketDecodeLine(4, "Longitude", aprsPacket.Position.CoordinateSet.Longitude.Value.ToString()); }
                    }
                }
            }
        }

        private void packetsListContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (packetsListView.SelectedItems.Count == 0) { e.Cancel = true; return; }
        }

        private void copyHEXValuesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.SelectedItems)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(Utils.BytesToHex(frame.data));
            }
            if (sb.Length > 0) { Clipboard.SetText(sb.ToString()); }
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void packetDataContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            copyToClipboardToolStripMenuItem.Visible = (packetDecodeListView.SelectedItems.Count > 0);
        }

        private void copyToClipboardToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (packetDecodeListView.SelectedItems.Count == 0) return;
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetDecodeListView.SelectedItems)
            {
                sb.AppendLine(l.Text + ", " + l.SubItems[1].Text);
            }
            Clipboard.SetText(sb.ToString());
        }
    }
}
