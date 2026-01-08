using System;
using System.Collections.Generic;
using System.Text;
using System.Windows.Forms;
using static HTCommander.TncDataFragment;

namespace HTCommander.Controls
{
    public partial class PacketCaptureTabUserControl : UserControl
    {
        private MainForm mainForm;

        public PacketCaptureTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;

            // Enable double buffering for packetDecodeListView to prevent flickering
            typeof(ListView).InvokeMember("DoubleBuffered",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.SetProperty,
                null, packetsListView, new object[] { true });

            // Load settings from registry
            showPacketDecodeToolStripMenuItem.Checked = (mainForm.registry.ReadInt("showPacketDecode", 0) == 1);
            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;
        }

        public void AddPacket(TncDataFragment fragment)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action<TncDataFragment>(AddPacket), fragment); return; }

            ListViewItem l = new ListViewItem(new string[] { fragment.time.ToShortTimeString(), fragment.channel_name, FragmentToShortString(fragment) });
            l.ImageIndex = fragment.incoming ? 5 : 4;
            l.Tag = fragment;
            packetsListView.Items.Insert(0, l);
        }

        public void AddPackets(List<ListViewItem> listViewItems)
        {
            packetsListView.Items.AddRange(listViewItems.ToArray());
        }

        public void AddPacket(ListViewItem listViewItem)
        {
            packetsListView.Items.Insert(0, listViewItem);
        }

        public void Clear()
        {
            packetsListView.Items.Clear();
            packetDecodeListView.Items.Clear();
        }

        public string FragmentToShortString(TncDataFragment fragment)
        {
            StringBuilder sb = new StringBuilder();

            if ((fragment.data != null) && (fragment.data.Length > 3) && (fragment.data[0] == 1))
            {
                // This is the short binary protocol format.
                int i = 0;
                Dictionary<byte, byte[]> decodedMessage = Utils.DecodeShortBinaryMessage(fragment.data);
                foreach (var item in decodedMessage)
                {
                    if (i++ > 0) sb.Append(", ");
                    if (item.Key == 0x20) { sb.Append("Callsign: " + UTF8Encoding.UTF8.GetString(item.Value)); }
                    else if (item.Key == 0x24) { sb.Append("Msg: " + UTF8Encoding.UTF8.GetString(item.Value)); }
                    else sb.Append(item.Key + ": " + Utils.BytesToHex(item.Value));
                }
                return sb.ToString();
            }

            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
            if (packet == null)
            {
                return Utils.BytesToHex(fragment.data);
            }
            else
            {
                if (packet.addresses.Count > 1)
                {
                    AX25Address addr = packet.addresses[1];
                    sb.Append(addr.ToString() + ">");
                }
                if (packet.addresses.Count > 0)
                {
                    AX25Address addr = packet.addresses[0];
                    sb.Append(addr.ToString());
                }
                for (int i = 2; i < packet.addresses.Count; i++)
                {
                    AX25Address addr = packet.addresses[i];
                    sb.Append("," + addr.ToString() + ((addr.CRBit1) ? "*" : ""));
                }

                if (sb.Length > 0) { sb.Append(": "); }

                if ((fragment.channel_name == "APRS") && (packet.type == AX25Packet.FrameType.U_FRAME))
                {
                    sb.Append(packet.dataStr);
                }
                else
                {
                    if (packet.type == AX25Packet.FrameType.U_FRAME)
                    {
                        sb.Append(packet.type.ToString().Replace("_", "-"));
                        string hex = Utils.BytesToHex(packet.data);
                        if (hex.Length > 0) { sb.Append(": " + hex); }
                    }
                    else
                    {
                        sb.Append(packet.type.ToString().Replace("_", "-") + ", NR:" + packet.nr + ", NS:" + packet.ns);
                        string hex = Utils.BytesToHex(packet.data);
                        if (hex.Length > 0) { sb.Append(": " + hex); }
                    }
                }
            }
            return sb.ToString().Replace("\r", "").Replace("\n", "");
        }

        public void addPacketDecodeLine(int group, string title, string value)
        {
            ListViewItem l = new ListViewItem(new string[] { title, value });
            l.Group = packetDecodeListView.Groups[group];
            packetDecodeListView.Items.Add(l);
        }

        private void packetsListView_Resize(object sender, EventArgs e)
        {
            // Auto-resize the Data column to fit content
            columnHeader9.Width = -2;
        }

        private void packetsListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            packetDecodeListView.BeginUpdate();
            packetDecodeListView.Items.Clear();
            if (packetsListView.SelectedItems.Count == 0)
            {
                packetDecodeListView.EndUpdate();
                return;
            }
            ListViewItem l = packetsListView.SelectedItems[0];
            if (l.Tag == null)
            {
                packetDecodeListView.EndUpdate();
                return;
            }
            TncDataFragment fragment = (TncDataFragment)l.Tag;
            if (fragment.channel_id >= 0) { addPacketDecodeLine(1, "Channel", (fragment.incoming ? "Received" : "Sent") + " on " + (fragment.channel_id + 1)); }
            addPacketDecodeLine(1, "Time", fragment.time.ToString());
            if (fragment.data != null)
            {
                addPacketDecodeLine(1, "Size", fragment.data.Length + " byte" + (fragment.data.Length > 1 ? "s" : ""));
                addPacketDecodeLine(1, "Data", ASCIIEncoding.ASCII.GetString(fragment.data));
                addPacketDecodeLine(1, "Data HEX", Utils.BytesToHex(fragment.data));
            }

            string encoding = "";
            if (fragment.encoding == FragmentEncodingType.Loopback) { encoding = "Loopback"; }
            if (fragment.encoding == FragmentEncodingType.HardwareAfsk1200) { encoding = "Hardware AFSK 1200 baud"; }
            if (fragment.encoding == FragmentEncodingType.SoftwareAfsk1200) { encoding = "Software AFSK 1200 baud"; }
            if (fragment.encoding == FragmentEncodingType.SoftwarePsk2400) { encoding = "Software PSK 2400 baud"; }
            if (fragment.encoding == FragmentEncodingType.SoftwarePsk4800) { encoding = "Software PSK 4800 baud"; }
            if (fragment.encoding == FragmentEncodingType.SoftwareG3RUH9600) { encoding = "Software G3RUH 9600 baud"; }
            if (encoding != "")
            {
                if (fragment.frame_type == TncDataFragment.FragmentFrameType.AX25) { encoding += ", AX.25"; }
                if (fragment.frame_type == TncDataFragment.FragmentFrameType.FX25) { encoding += ", FX.25"; }
                if (fragment.corrections == 0) { encoding += ", No Corrections"; }
                if (fragment.corrections == 1) { encoding += ", 1 Correction"; }
                if (fragment.corrections > 1) { encoding += ", " + fragment.corrections + " Corrections"; }
                addPacketDecodeLine(0, "Encoding", encoding);
            }

            if ((fragment.data.Length > 3) && (fragment.data[0] == 1))
            {
                // This is the short binary protocol format.
                Dictionary<byte, byte[]> decodedMessage = Utils.DecodeShortBinaryMessage(fragment.data);
                foreach (var item in decodedMessage)
                {
                    if (item.Key == 0x20) { addPacketDecodeLine(7, "Callsign", UTF8Encoding.UTF8.GetString(item.Value)); }
                    else if (item.Key == 0x24) { addPacketDecodeLine(7, "Message", UTF8Encoding.UTF8.GetString(item.Value)); }
                    else addPacketDecodeLine(7, $"Key: {item.Key}", Utils.BytesToHex(item.Value));
                }
            }
            else
            {
                // Try normal AX.25 packet format
                StringBuilder sb = new StringBuilder();
                AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
                if (packet == null)
                {
                    addPacketDecodeLine(2, "Decode", "AX25 Decoder failed to decode packet.");
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
                        addPacketDecodeLine(2, "Address " + (i + 1), sb.ToString());
                    }
                    addPacketDecodeLine(2, "Type", packet.type.ToString().Replace("_", "-"));
                    sb.Clear();
                    sb.Append("NS:" + packet.ns + ", NR:" + packet.nr);
                    if (packet.command) { sb.Append(", Command"); }
                    if (packet.pollFinal) { sb.Append(", PollFinal"); }
                    if (packet.modulo128) { sb.Append(", Modulo128"); }
                    if (sb.Length > 2) { addPacketDecodeLine(2, "Control", sb.ToString()); }
                    if (packet.pid > 0) { addPacketDecodeLine(2, "Protocol ID", packet.pid.ToString()); }
                    if (packet.dataStr != null) { addPacketDecodeLine(3, "Data", packet.dataStr); }
                    if (packet.data != null) { addPacketDecodeLine(3, "Data HEX", Utils.BytesToHex(packet.data)); }

                    if (packet.pid == 242)
                    {
                        byte[] decompressedData = null;
                        try { decompressedData = Utils.DecompressBrotli(packet.data); } catch { }
                        if (decompressedData != null)
                        {
                            addPacketDecodeLine(6, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                            addPacketDecodeLine(6, "Data HEX", Utils.BytesToHex(decompressedData));
                            byte[] deflateBuf = Utils.CompressDeflate(decompressedData);
                            addPacketDecodeLine(6, "Stats", $"Brotli {decompressedData.Length} --> {packet.data.Length}, Deflate would have been {deflateBuf.Length}");
                        }
                    }

                    if (packet.pid == 243)
                    {
                        byte[] decompressedData = null;
                        try { decompressedData = Utils.DecompressDeflate(packet.data); } catch { }
                        if (decompressedData != null)
                        {
                            addPacketDecodeLine(6, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                            addPacketDecodeLine(6, "Data HEX", Utils.BytesToHex(decompressedData));
                            byte[] brotliBuf = Utils.CompressBrotli(decompressedData);
                            addPacketDecodeLine(6, "Stats", $"Deflate {decompressedData.Length} --> {packet.data.Length}, Brotli would have been {brotliBuf.Length}");
                        }
                    }

                    if ((packet.type == AX25Packet.FrameType.U_FRAME) && (packet.pid == 240))
                    {
                        aprsparser.AprsPacket aprsPacket = aprsparser.AprsPacket.Parse(packet);
                        if (aprsPacket == null)
                        {
                            addPacketDecodeLine(4, "Decode", "APRS Decoder failed to decode packet.");
                        }
                        else
                        {
                            addPacketDecodeLine(4, "Type", aprsPacket.DataType.ToString());
                            if (aprsPacket.TimeStamp != null) { addPacketDecodeLine(4, "Time Stamp", aprsPacket.TimeStamp.ToString()); }
                            if (!string.IsNullOrEmpty(aprsPacket.DestCallsign.StationCallsign)) { addPacketDecodeLine(4, "Destination", aprsPacket.DestCallsign.StationCallsign.ToString()); }
                            if (!string.IsNullOrEmpty(aprsPacket.ThirdPartyHeader)) { addPacketDecodeLine(4, "ThirdParty Header", aprsPacket.ThirdPartyHeader); }
                            if (!string.IsNullOrEmpty(aprsPacket.InformationField)) { addPacketDecodeLine(4, "Information", aprsPacket.InformationField.ToString()); }
                            if (!string.IsNullOrEmpty(aprsPacket.Comment)) { addPacketDecodeLine(4, "Comment", aprsPacket.Comment.ToString()); }
                            if (aprsPacket.SymbolTableIdentifier != 0) { addPacketDecodeLine(4, "Symbol Code", aprsPacket.SymbolTableIdentifier.ToString()); }

                            if (aprsPacket.Position.Speed != 0) { addPacketDecodeLine(5, "Speed", aprsPacket.Position.Speed.ToString()); }
                            if (aprsPacket.Position.Altitude != 0) { addPacketDecodeLine(5, "Altitude", aprsPacket.Position.Altitude.ToString()); }
                            if (aprsPacket.Position.Ambiguity != 0) { addPacketDecodeLine(5, "Ambiguity", aprsPacket.Position.Ambiguity.ToString()); }
                            if (aprsPacket.Position.Course != 0) { addPacketDecodeLine(5, "Course", aprsPacket.Position.Course.ToString()); }
                            if (!string.IsNullOrEmpty(aprsPacket.Position.Gridsquare)) { addPacketDecodeLine(5, "Gridsquare", aprsPacket.Position.Gridsquare.ToString()); }
                            if (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) { addPacketDecodeLine(5, "Latitude", aprsPacket.Position.CoordinateSet.Latitude.Value.ToString()); }
                            if (aprsPacket.Position.CoordinateSet.Longitude.Value != 0) { addPacketDecodeLine(5, "Longitude", aprsPacket.Position.CoordinateSet.Longitude.Value.ToString()); }
                        }
                    }
                }
            }
            packetDecodeListView.EndUpdate();
        }

        private void packetsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            packetsContextMenuStrip.Show(packetsMenuPictureBox, e.Location);
        }

        private void showPacketDecodeToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            mainForm.registry.WriteInt("showPacketDecode", showPacketDecodeToolStripMenuItem.Checked ? 1 : 0);
            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;
        }

        private void packetsListContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (packetsListView.SelectedItems.Count == 0) { e.Cancel = true; return; }
        }

        private void packetsContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            saveToFileToolStripMenuItem1.Enabled = (packetsListView.Items.Count > 0);
        }

        private void packetDataContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            copyToClipboardToolStripMenuItem.Visible = (packetDecodeListView.SelectedItems.Count > 0);
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

        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.SelectedItems)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString());
            }
            if ((sb.Length > 0) && (savePacketsFileDialog.ShowDialog(this) == DialogResult.OK))
            {
                System.IO.File.WriteAllText(savePacketsFileDialog.FileName, sb.ToString());
            }
        }

        private void saveToFileToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.Items)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString());
            }
            if ((sb.Length > 0) && (savePacketsFileDialog.ShowDialog(this) == DialogResult.OK))
            {
                System.IO.File.WriteAllText(savePacketsFileDialog.FileName, sb.ToString());
            }
        }

        private void openFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (openPacketsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                PacketCaptureViewerForm form = new PacketCaptureViewerForm(mainForm, openPacketsFileDialog.FileName);
                form.Show(mainForm);
            }
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

        private void clearPacketsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, "Clear packets?", "Packet Capture", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                Clear();
            }
        }
    }
}