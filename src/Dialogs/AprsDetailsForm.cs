/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using aprsparser;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AprsDetailsForm : Form
    {
        private ChatMessage msg;

        public AprsDetailsForm()
        {
            InitializeComponent();
        }

        public void SetMessage(ChatMessage msg)
        {
            this.msg = msg;
            aprsDetailsListView.Items.Clear();
            if (msg == null) return;
            addItem("Time", msg.Time.ToString());

            AX25Packet packet = (AX25Packet)msg.Tag;

            int i = 1;
            foreach (AX25Address addr in packet.addresses) { addItem("AX.25 Addr " + i, addr.CallSignWithId); i++; }

            AprsPacket aprsPacket = AprsPacket.Parse(packet);
            if (aprsPacket == null)
            {
                addItem("Type", msg.MessageType.ToString());
                if (msg.Message != null) { addItem("Message", msg.Message); }
            }
            else
            {
                addItem("Type", aprsPacket.DataType.ToString());
                if (!string.IsNullOrEmpty(aprsPacket.Comment)) { addItem("Comment", aprsPacket.Comment); }
                if (!string.IsNullOrEmpty(aprsPacket.DestCallsign.StationCallsign)) { addItem("DestCallsign", aprsPacket.DestCallsign.StationCallsign); }
                if (!string.IsNullOrEmpty(aprsPacket.ThirdPartyHeader)) { addItem("ThirdParty Header", aprsPacket.ThirdPartyHeader); }
                if (aprsPacket.MessageData != null) {
                    addItem("MsgType", aprsPacket.MessageData.MsgType.ToString());
                    if (aprsPacket.MessageData.Addressee != null) { addItem("Addressee", aprsPacket.MessageData.Addressee); }
                    if (aprsPacket.MessageData.SeqId != null) { addItem("SeqId", aprsPacket.MessageData.SeqId); }
                    if (aprsPacket.MessageData.MsgText != null) { addItem("MsgText", aprsPacket.MessageData.MsgText); }
                }
                if (aprsPacket.Position != null) {
                    if (aprsPacket.Position.Course != 0) { addItem("Course", aprsPacket.Position.Course.ToString()); }
                    if (aprsPacket.Position.Speed != 0) { addItem("Speed", aprsPacket.Position.Speed.ToString()); }
                    if (aprsPacket.Position.Altitude != 0) { addItem("Altitude", aprsPacket.Position.Altitude.ToString()); }
                    if (aprsPacket.Position.Ambiguity != 0) { addItem("Ambiguity", aprsPacket.Position.Ambiguity.ToString()); }
                    if (!string.IsNullOrEmpty(aprsPacket.Position.Gridsquare)) { addItem("Gridsquare", aprsPacket.Position.Gridsquare.ToString()); }
                    if (aprsPacket.Position.CoordinateSet != null) {
                        if (!string.IsNullOrEmpty(aprsPacket.Position.CoordinateSet.Latitude.Nmea)) { addItem("Latitude", aprsPacket.Position.CoordinateSet.Latitude.Nmea); }
                        if (!string.IsNullOrEmpty(aprsPacket.Position.CoordinateSet.Longitude.Nmea)) { addItem("Longitude", aprsPacket.Position.CoordinateSet.Longitude.Nmea); }
                    }
                }
                if (!string.IsNullOrEmpty(aprsPacket.AuthCode)) {
                    addItem("Authentication", aprsPacket.AuthCode);
                }
            }
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in aprsDetailsListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            aprsDetailsListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        private void AprsDetailsForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            //parent.aprsDetailsForm = null;
        }

        private void closeButton_Click(object sender, System.EventArgs e)
        {
            Close();
        }
    }
}
