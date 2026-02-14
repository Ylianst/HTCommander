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
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class SstvSendForm : Form
    {
        private Image _originalImage;
        private string _selectedMode;

        /// <summary>
        /// SSTV mode definition with name, resolution, and transmit time.
        /// </summary>
        private class SstvModeInfo
        {
            public string Name { get; set; }
            public int Width { get; set; }
            public int Height { get; set; }
            public int TransmitSeconds { get; set; }

            public string TransmitTimeString
            {
                get
                {
                    if (TransmitSeconds < 60) return $"{TransmitSeconds}s";
                    int min = TransmitSeconds / 60;
                    int sec = TransmitSeconds % 60;
                    return sec > 0 ? $"{min}m {sec}s" : $"{min}m";
                }
            }

            public override string ToString()
            {
                return $"{Name}  ({Width} x {Height})";
            }
        }

        /// <summary>
        /// All supported SSTV modes with their native resolutions and approximate transmit times.
        /// Transmit times are computed from the encoder timing constants (including VIS header).
        /// </summary>
        private static readonly SstvModeInfo[] SstvModes = new SstvModeInfo[]
        {
            new SstvModeInfo { Name = "Robot 36 Color",      Width = 320, Height = 240, TransmitSeconds = 36 },
            new SstvModeInfo { Name = "Robot 72 Color",      Width = 320, Height = 240, TransmitSeconds = 73 },
            new SstvModeInfo { Name = "Martin 1",            Width = 320, Height = 256, TransmitSeconds = 115 },
            new SstvModeInfo { Name = "Martin 2",            Width = 320, Height = 256, TransmitSeconds = 59 },
            new SstvModeInfo { Name = "Scottie 1",           Width = 320, Height = 256, TransmitSeconds = 110 },
            new SstvModeInfo { Name = "Scottie 2",           Width = 320, Height = 256, TransmitSeconds = 72 },
            new SstvModeInfo { Name = "Scottie DX",          Width = 320, Height = 256, TransmitSeconds = 270 },
            new SstvModeInfo { Name = "Wraase SC2\u2013180", Width = 320, Height = 256, TransmitSeconds = 183 },
            new SstvModeInfo { Name = "PD 50",               Width = 320, Height = 256, TransmitSeconds = 51 },
            new SstvModeInfo { Name = "PD 90",               Width = 320, Height = 256, TransmitSeconds = 91 },
            new SstvModeInfo { Name = "PD 120",              Width = 640, Height = 496, TransmitSeconds = 127 },
            new SstvModeInfo { Name = "PD 160",              Width = 512, Height = 400, TransmitSeconds = 162 },
            new SstvModeInfo { Name = "PD 180",              Width = 640, Height = 496, TransmitSeconds = 188 },
            new SstvModeInfo { Name = "PD 240",              Width = 640, Height = 496, TransmitSeconds = 249 },
            new SstvModeInfo { Name = "PD 290",              Width = 800, Height = 616, TransmitSeconds = 290 },
        };

        /// <summary>
        /// Gets the selected SSTV mode name (e.g. "Robot 36 Color").
        /// </summary>
        public string SelectedMode => _selectedMode;

        /// <summary>
        /// Gets the preview image scaled to the selected mode's resolution.
        /// </summary>
        public Image ScaledImage { get; private set; }

        public SstvSendForm()
        {
            InitializeComponent();
        }

        /// <summary>
        /// Sets the source image to be transmitted.
        /// </summary>
        public void SetImage(Image image)
        {
            _originalImage = image;
            UpdatePreview();
        }

        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);

            // Populate mode dropdown
            modeComboBox.Items.Clear();
            int defaultIndex = 0;
            for (int i = 0; i < SstvModes.Length; i++)
            {
                modeComboBox.Items.Add(SstvModes[i]);
                if (SstvModes[i].Name == "Robot 36 Color") { defaultIndex = i; }
            }
            modeComboBox.SelectedIndex = defaultIndex;
        }

        private void modeComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdatePreview();
        }

        /// <summary>
        /// Updates the preview image based on the currently selected mode.
        /// </summary>
        private void UpdatePreview()
        {
            if (_originalImage == null) return;
            if (modeComboBox.SelectedItem == null) return;

            var mode = (SstvModeInfo)modeComboBox.SelectedItem;
            _selectedMode = mode.Name;

            // Update transmit time label
            resolutionLabel.Text = $"~{mode.TransmitTimeString}";

            // Create a scaled copy at the mode's resolution
            var scaled = ScaleImageToFill(_originalImage, mode.Width, mode.Height);

            // Free previous scaled image
            ScaledImage?.Dispose();
            ScaledImage = scaled;

            // Show in PictureBox
            previewPictureBox.Image = scaled;
        }

        /// <summary>
        /// Scales and crops the source image to exactly fill the target dimensions,
        /// preserving aspect ratio by center-cropping the excess.
        /// </summary>
        private static Bitmap ScaleImageToFill(Image source, int targetWidth, int targetHeight)
        {
            float sourceAspect = (float)source.Width / source.Height;
            float targetAspect = (float)targetWidth / targetHeight;

            int srcX, srcY, srcW, srcH;

            if (sourceAspect > targetAspect)
            {
                // Source is wider - crop left/right
                srcH = source.Height;
                srcW = (int)(source.Height * targetAspect);
                srcX = (source.Width - srcW) / 2;
                srcY = 0;
            }
            else
            {
                // Source is taller - crop top/bottom
                srcW = source.Width;
                srcH = (int)(source.Width / targetAspect);
                srcX = 0;
                srcY = (source.Height - srcH) / 2;
            }

            var result = new Bitmap(targetWidth, targetHeight);
            using (var g = Graphics.FromImage(result))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(source,
                    new Rectangle(0, 0, targetWidth, targetHeight),
                    new Rectangle(srcX, srcY, srcW, srcH),
                    GraphicsUnit.Pixel);
            }

            return result;
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
            Close();
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            _originalImage = null; // Don't dispose - caller owns it
        }
    }
}
