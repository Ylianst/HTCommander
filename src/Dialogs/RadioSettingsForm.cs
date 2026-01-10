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

using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioSettingsForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public RadioSettingsForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }

        public void UpdateInfo()
        {
            if (radio.Settings == null) return;
            addItem("VFO A", "Channel " + (radio.Settings.channel_a + 1));
            addItem("VFO B", "Channel " + (radio.Settings.channel_b + 1));

            addItem("Scan", radio.Settings.scan.ToString());
            addItem("AGHFP Call Mode", radio.Settings.aghfp_call_mode.ToString());
            addItem("Double Channel", radio.Settings.double_channel.ToString());
            addItem("Squelch Level", radio.Settings.squelch_level.ToString());

            addItem("Tail elim", radio.Settings.tail_elim.ToString());
            addItem("Auto relay en", radio.Settings.auto_relay_en.ToString());
            addItem("Auto power on", radio.Settings.auto_power_on.ToString());
            addItem("Keep AGHFP link", radio.Settings.keep_aghfp_link.ToString());
            addItem("Mic gain", radio.Settings.mic_gain.ToString());
            addItem("TX hold time", radio.Settings.tx_hold_time.ToString());
            addItem("TX time limit", radio.Settings.tx_time_limit.ToString());

            addItem("Local Speaker", radio.Settings.local_speaker.ToString());
            addItem("BT mic gain", radio.Settings.bt_mic_gain.ToString());
            addItem("Adaptive Response", radio.Settings.adaptive_response.ToString());
            addItem("DIS Tone", radio.Settings.dis_tone.ToString());
            addItem("Power saving mode", radio.Settings.power_saving_mode.ToString());

            addItem("Auto power off", radio.Settings.auto_power_off.ToString());

            string auto_share_loc_ch;
            if (radio.Settings.auto_share_loc_ch == 0) { auto_share_loc_ch = "Current"; } else { auto_share_loc_ch = "Channel " + radio.Settings.auto_share_loc_ch; }
            addItem("Auto share location ch", auto_share_loc_ch);

            addItem("HW speaker", radio.Settings.hm_speaker.ToString());
            addItem("Positioning system", radio.Settings.positioning_system.ToString());
            addItem("Time offset", radio.Settings.time_offset.ToString());
            addItem("Use freq range 2", radio.Settings.use_freq_range_2.ToString());
            addItem("PTT lock", radio.Settings.ptt_lock.ToString());
            addItem("Leading sync bit en", radio.Settings.leading_sync_bit_en.ToString());
            addItem("Pairing at power on", radio.Settings.pairing_at_power_on.ToString());

            addItem("Screen Timeout", radio.Settings.screen_timeout.ToString());
            addItem("VFO x", radio.Settings.vfo_x.ToString());
            addItem("Imperial Units", radio.Settings.imperial_unit.ToString());

            addItem("Weather Mode", radio.Settings.wx_mode.ToString());
            addItem("NOAA Channel", radio.Settings.noaa_ch.ToString());
            addItem("VFOl tx power", radio.Settings.vfol_tx_power_x.ToString());

            addItem("VFO2 tx power", radio.Settings.vfo2_tx_power_x.ToString());
            addItem("Dis digital mute", radio.Settings.dis_digital_mute.ToString());
            addItem("Signaling ecc en", radio.Settings.signaling_ecc_en.ToString());
            addItem("Ch data lock", radio.Settings.ch_data_lock.ToString());

            addItem("VFO1 mod freq", radio.Settings.vfo1_mod_freq_x.ToString());
            addItem("VFO2 mod freq", radio.Settings.vfo2_mod_freq_x.ToString());
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in mainListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            mainListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void RadioSettingsForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            //parent.radioSettingsForm = null;
        }
    }
}
