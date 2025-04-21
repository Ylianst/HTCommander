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
using System.Linq;

namespace HTCommander
{
    public partial class AmplitudeHistoryBar: UserControl
    {
        private readonly Queue<float> amplitudeHistory = new Queue<float>();
        private readonly int historyLength = 8; // number of points (~seconds based on your buffer rate)
        private readonly Timer redrawTimer;

        public AmplitudeHistoryBar()
        {
            InitializeComponent();
            DoubleBuffered = true;
            redrawTimer = new Timer { Interval = 50 }; // redraw every 50ms
            redrawTimer.Tick += (s, e) => Invalidate();
            redrawTimer.Start();
        }

        public void ProcessAudioData(byte[] buffer, int bytesRecorded)
        {
            short maxSample = 0;
            for (int i = 0; i < bytesRecorded; i += 2) // 16-bit mono = 2 bytes per sample
            {
                maxSample = Math.Max(maxSample, BitConverter.ToInt16(buffer, i));
            }
            AddSample(Math.Min(1.0F, maxSample / 32768F));
        }

        public void AddSample(float amplitude)
        {
            lock (amplitudeHistory)
            {
                if (amplitudeHistory.Count >= historyLength)
                    amplitudeHistory.Dequeue();

                amplitudeHistory.Enqueue(amplitude);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(this.BackColor);

            Brush barBrush = new SolidBrush(this.ForeColor);

            float maxHeight = Height;
            float currentAmplitude = 0;

            lock (amplitudeHistory)
            {
                if (amplitudeHistory.Count > 0)
                {
                    //currentAmplitude = amplitudeHistory.Last(); // latest value
                    // Optionally, you can calculate the average or max of the history
                    currentAmplitude = amplitudeHistory.Max(); // max of history
                }
            }

            float barHeight = currentAmplitude * maxHeight;
            float barWidth = Width;

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
