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

using System.Windows.Forms;

namespace HTCommander
{
    public partial class VoiceDetailsForm : Form
    {
        private VoiceMessage msg;

        public VoiceDetailsForm()
        {
            InitializeComponent();
        }

        public void SetMessage(VoiceMessage msg)
        {
            this.msg = msg;
            voiceDetailsListView.Items.Clear();
            if (msg == null) return;

            addItem("Time", msg.Time.ToString());

            if (!string.IsNullOrEmpty(msg.Route))
            {
                addItem("Route", msg.Route);
            }

            addItem("Encoding", GetEncodingTypeName(msg.Encoding));

            addItem("Direction", msg.Sender ? "Sent" : "Received");

            addItem("Completed", msg.IsCompleted ? "Yes" : "No");

            if (!string.IsNullOrEmpty(msg.SenderCallSign))
            {
                addItem("Callsign", msg.SenderCallSign);
            }

            if (!string.IsNullOrEmpty(msg.Message))
            {
                addItem("Message", msg.Message);
            }

            if (msg.Latitude != 0 || msg.Longitude != 0)
            {
                addItem("Latitude", msg.Latitude.ToString("F6"));
                addItem("Longitude", msg.Longitude.ToString("F6"));
            }
        }

        /// <summary>
        /// Gets the display name for a VoiceTextEncodingType.
        /// </summary>
        private string GetEncodingTypeName(VoiceTextEncodingType encoding)
        {
            switch (encoding)
            {
                case VoiceTextEncodingType.Voice: return "Voice";
                case VoiceTextEncodingType.Morse: return "Morse";
                case VoiceTextEncodingType.VoiceClip: return "Voice Clip";
                case VoiceTextEncodingType.AX25: return "AX.25";
                case VoiceTextEncodingType.BSS: return "Chat";
                case VoiceTextEncodingType.Recording: return "Recording";
                default: return encoding.ToString();
            }
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in voiceDetailsListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            voiceDetailsListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        private void VoiceDetailsForm_FormClosing(object sender, FormClosingEventArgs e)
        {
        }

        private void closeButton_Click(object sender, System.EventArgs e)
        {
            Close();
        }
    }
}
