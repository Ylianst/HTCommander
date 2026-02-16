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
using System.IO;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class ImagePreviewForm : Form
    {
        private Image previewImage;

        public ImagePreviewForm(string imagePath)
        {
            InitializeComponent();

            try
            {
                // Load a copy of the image so the file is not locked
                using (var temp = Image.FromFile(imagePath))
                {
                    previewImage = new Bitmap(temp);
                }

                pictureBox.Image = previewImage;
                Text = "Image Preview - " + Path.GetFileName(imagePath);

                // Size the form to fit the image with some reasonable limits
                int maxWidth = Math.Min(previewImage.Width + 40, Screen.PrimaryScreen.WorkingArea.Width - 100);
                int maxHeight = Math.Min(previewImage.Height + 60, Screen.PrimaryScreen.WorkingArea.Height - 100);
                ClientSize = new Size(Math.Max(maxWidth, 200), Math.Max(maxHeight, 150));
                StartPosition = FormStartPosition.CenterParent;
            }
            catch
            {
                Text = "Image Preview";
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                previewImage?.Dispose();
                components?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
