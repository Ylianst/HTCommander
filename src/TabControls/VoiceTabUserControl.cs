/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander.Controls
{
    public partial class VoiceTabUserControl : UserControl
    {
        private MainForm mainForm;

        public VoiceTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;
        }

        // Properties to access internal controls
        public RichTextBox VoiceHistoryTextBox => voiceHistoryTextBox;
        public TextBox SpeakTextBox => speakTextBox;
        public Button SpeakButton => speakButton;
        public Button VoiceEnableButton => voiceEnableButton;
        public Button CancelVoiceButton => cancelVoiceButton;
        public Label VoiceProcessingLabel => voiceProcessingLabel;
        public Panel VoiceBottomPanel => voiceBottomPanel;

        public bool IsSpeakMode => speakToolStripMenuItem.Checked;

        public void SetSpeakMode(bool speakMode)
        {
            speakToolStripMenuItem.Checked = speakMode;
            morseToolStripMenuItem.Checked = !speakMode;
            speakButton.Text = speakMode ? "&Speak" : "&Morse";
        }

        private void voiceEnableButton_Click(object sender, EventArgs e)
        {
            //mainForm?.OnVoiceEnableButtonClick();
        }

        private void speakButton_Click(object sender, EventArgs e)
        {
            //mainForm?.OnSpeakButtonClick();
        }

        private void speakTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                //mainForm?.OnSpeakButtonClick();
            }
        }

        private void speakToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetSpeakMode(true);
        }

        private void morseToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetSpeakMode(false);
        }

        private void cancelVoiceButton_Click(object sender, EventArgs e)
        {
            //mainForm?.OnCancelVoiceButtonClick();
        }

        private void clearHistoryToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //mainForm?.OnClearVoiceHistoryClick();
        }

        private void voiceMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            voiceTabContextMenuStrip.Show(voiceMenuPictureBox, e.Location);
        }
    }
}
