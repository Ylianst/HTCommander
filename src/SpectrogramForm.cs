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
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using Spectrogram;

namespace HTCommander
{
    public partial class SpectrogramForm: Form
    {
        private MainForm parent;
        private SpectrogramGenerator spec;
        private Colormap[] cmaps;
        private int cbFftSize = 0;
        private int heightDiff = 0;
        private bool roll = false;
        private int maxFrequency = 16000;
        public readonly int SampleRate = 2;
        public double AmplitudeFrac { get; private set; }
        public double TotalSamples { get; private set; }
        public double TotalTimeSec { get { return (double)TotalSamples / SampleRate; } }
        private readonly List<double> audio = new List<double>();
        public int SamplesInMemory { get { return audio.Count; } }

        public SpectrogramForm(MainForm parent)
        {
            this.parent = parent;
            InitializeComponent();

            // Load Settings
            maxFrequency = (int)parent.registry.ReadInt("SpecMaxFrequency", 16000);
            hzToolStripMenuItem.Checked = (maxFrequency == 16000);
            hzToolStripMenuItem1.Checked = (maxFrequency == 8000);
            hzToolStripMenuItem2.Checked = (maxFrequency == 4000);
            pbScaleVert.Visible = scaleToolStripMenuItem.Checked = (parent.registry.ReadInt("SpecShowScale", 0) == 1);
            roll = rollToolStripMenuItem.Checked = (parent.registry.ReadInt("SpecRoll", 0) == 1);
            cbFftSize = (int)parent.registry.ReadInt("SpecLarge", 0);
            largeToolStripMenuItem1.Checked = (cbFftSize == 1);
        }

        private void StartListening()
        {
            int sampleRate = 32000;
            int fftSize = 1 << (9 + cbFftSize); // cbFftSize.SelectedIndex
            int stepSize = fftSize / 20;

            pbSpectrogram.Image?.Dispose();
            pbSpectrogram.Image = null;
            spec = new SpectrogramGenerator(sampleRate, fftSize, stepSize, maxFreq: maxFrequency); // Max: 6200, 100, 100
            pbSpectrogram.Height = spec.Height;

            pbScaleVert.Image?.Dispose();
            pbScaleVert.Image = spec.GetVerticalScale(pbScaleVert.Width);
            pbScaleVert.Height = spec.Height;

            int refHeight = GetRefHeight();
            int h = refHeight + (refHeight * cbFftSize) + heightDiff;
            this.MinimumSize = new Size(200, h);
            this.MaximumSize = new Size(65535, h);
            this.Height = h;
        }

        private void updateTimer_Tick(object sender, EventArgs e)
        {
            if (spec == null) return;
            spec.Add(GetNewAudio(), process: false);
            double multiplier = 100 / 20.0;

            if (spec.FftsToProcess > 0)
            {
                spec.Process();
                spec.SetFixedWidth(pbSpectrogram.Width);
                Bitmap bmpSpec = new Bitmap(spec.Width, spec.Height, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
                using (var bmpSpecIndexed = spec.GetBitmap(multiplier, true, roll: roll))
                using (var gfx = Graphics.FromImage(bmpSpec))
                using (var pen = new Pen(Color.White))
                {
                    gfx.DrawImage(bmpSpecIndexed, 0, 0);
                    if (roll) { gfx.DrawLine(pen, spec.NextColumnIndex, 0, spec.NextColumnIndex, pbSpectrogram.Height); }
                }
                pbSpectrogram.Image?.Dispose();
                pbSpectrogram.Image = bmpSpec;
            }
        }

        public void AddAudioData(byte[] Buffer, int BytesRecorded)
        {
            int bytesPerSample = 2;
            int newSampleCount = BytesRecorded / bytesPerSample;
            double[] buffer = new double[newSampleCount];
            double peak = 0;
            for (int i = 0; i < newSampleCount; i++)
            {
                buffer[i] = BitConverter.ToInt16(Buffer, i * bytesPerSample);
                peak = Math.Max(peak, buffer[i]);
            }
            lock (audio) { audio.AddRange(buffer); }
            AmplitudeFrac = peak / (1 << 15);
            TotalSamples += newSampleCount;
        }
        private double[] GetNewAudio()
        {
            lock (audio)
            {
                double[] values = new double[audio.Count];
                for (int i = 0; i < values.Length; i++) { values[i] = audio[i]; }
                audio.RemoveRange(0, values.Length);
                return values;
            }
        }

        private void SpectrogramForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            updateTimer.Enabled = false;
            parent.spectrogramForm = null;
        }

        private int GetRefHeight()
        {
            return (maxFrequency * 256 / 16000);
        }

        private void SpectrogramForm_Load(object sender, EventArgs e)
        {
            heightDiff = this.Height - pbSpectrogram.Height;
            this.Height = GetRefHeight() + heightDiff;
            StartListening();

            string selectedColor = parent.registry.ReadString("SpecColor", "Viridis");
            cmaps = Colormap.GetColormaps();
            for (int i = 0; i < cmaps.Length; i++)
            {
                Colormap cmap = cmaps[i];
                ToolStripMenuItem m = new ToolStripMenuItem(cmap.Name);
                m.Tag = i;
                m.Click += colorToolStripMenuItem_Click;
                m.Checked = (cmap.Name == selectedColor);
                if (cmap.Name == selectedColor) { spec.Colormap = cmap; }
                colorsToolStripMenuItem.DropDownItems.Add(m);
            }
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void largeToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            cbFftSize = largeToolStripMenuItem1.Checked ? 1 : 0;
            parent.registry.WriteInt("SpecLarge", cbFftSize);
            StartListening();
        }

        private void rollToolStripMenuItem_Click(object sender, EventArgs e)
        {
            roll = rollToolStripMenuItem.Checked;
            parent.registry.WriteInt("SpecRoll", roll ? 1 : 0);
        }

        private void scaleToolStripMenuItem_Click(object sender, EventArgs e)
        {
            pbScaleVert.Visible = scaleToolStripMenuItem.Checked;
            parent.registry.WriteInt("SpecShowScale", scaleToolStripMenuItem.Checked ? 1 : 0);
        }

        private void hzToolStripMenuItem_Click(object sender, EventArgs e)
        {
            maxFrequency = 16000;
            parent.registry.WriteInt("SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = true;
            hzToolStripMenuItem1.Checked = false;
            hzToolStripMenuItem2.Checked = false;
            StartListening();
        }

        private void hzToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            maxFrequency = 8000;
            parent.registry.WriteInt("SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = false;
            hzToolStripMenuItem1.Checked = true;
            hzToolStripMenuItem2.Checked = false;
            StartListening();
        }

        private void hzToolStripMenuItem2_Click(object sender, EventArgs e)
        {
            maxFrequency = 4000;
            parent.registry.WriteInt("SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = false;
            hzToolStripMenuItem1.Checked = false;
            hzToolStripMenuItem2.Checked = true;
            StartListening();
        }

        private void colorToolStripMenuItem_Click(object sender, EventArgs e)
        {
            ToolStripMenuItem m = (ToolStripMenuItem)sender;
            spec.Colormap = cmaps[(int)m.Tag];
            foreach (ToolStripMenuItem n in colorsToolStripMenuItem.DropDownItems) { n.Checked = (n == m); }
            parent.registry.WriteString("SpecColor", spec.Colormap.Name);
        }
    }
}
