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
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Linq;

namespace HTCommander
{
    public partial class AmplitudeHistoryBar: UserControl
    {
        private readonly Queue<float> amplitudeHistory = new Queue<float>();
        private readonly int historyLength = 2; // number of points (~seconds based on your buffer rate)
        private readonly Timer redrawTimer;
        private float currentAmplitude = 0;
        private float paintedAmplitude = 0;

        public AmplitudeHistoryBar()
        {
            InitializeComponent();
            DoubleBuffered = true;
            redrawTimer = new Timer { Interval = 50 }; // redraw every 50ms
            redrawTimer.Tick += RedrawTimer_Tick;
            redrawTimer.Start();
        }

        private void RedrawTimer_Tick(object sender, EventArgs e)
        {
            // Do not redraw if amplitude hasn't changed
            if (this.Visible && (currentAmplitude != paintedAmplitude)) Invalidate();
        }

        private static unsafe short FindMaxSampleUnsafe(byte[] bytes, int bytesRecorded)
        {
            short max = 0;
            fixed (byte* ptr = bytes)
            {
                short* samples = (short*)ptr;
                int count = bytesRecorded / 2;
                for (int i = 0; i < count; i++)
                {
                    short val = samples[i];
                    if (val > max) { max = val; }
                }
            }
            return max;
        }

        public void ProcessAudioData(byte[] buffer, int bytesRecorded)
        {
            if (this.Visible) { AddSample(Math.Min(1.0F, FindMaxSampleUnsafe(buffer, bytesRecorded) / 32768F)); }
        }

        public void ProcessAudioData(float value)
        {
            if (this.Visible) { AddSample(Math.Min(1.0F, Math.Max(0.0F, value))); }
        }

        public void AddSample(float amplitude)
        {
            lock (amplitudeHistory)
            {
                if (amplitudeHistory.Count >= historyLength) amplitudeHistory.Dequeue();
                amplitudeHistory.Enqueue(amplitude);
                currentAmplitude = amplitudeHistory.Max();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(this.BackColor);
            Brush barBrush = new SolidBrush(this.ForeColor);
            float maxHeight = Height;
            float barHeight = currentAmplitude * maxHeight;
            float barWidth = Width;
            paintedAmplitude = currentAmplitude;
            e.Graphics.FillRectangle(
                barBrush,
                0,
                maxHeight - barHeight, // draw from bottom up
                barWidth,
                barHeight
            );
        }
    }
}
