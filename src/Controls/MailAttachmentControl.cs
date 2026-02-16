/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.ComponentModel;
using System.Drawing.Drawing2D;

namespace HTCommander
{
    public partial class MailAttachmentControl : UserControl
    {
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string Filename { get { return filenameLabel.Text; } set { filenameLabel.Text = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public byte[] FileData;

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public bool AllowRemove
        {
            get { return removePictureBox.Visible; }
            set {
                removeToolStripMenuItem.Visible = value;
                removePictureBox.Visible = value;
                toolStripMenuItem1.Visible = value;
                filenameLabel.Width = value ? 233 : 262;
                filenameLabel.Cursor = value ? Cursors.Default : Cursors.Hand;
            }
        }
        public MailAttachmentControl()
        {
            InitializeComponent();
        }

        private int _cornerRadius = 4;

        [Category("Appearance")]
        [Description("The radius of the rounded corners.")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        [DefaultValue(4)]
        public int CornerRadius
        {
            get { return _cornerRadius; }
            set
            {
                _cornerRadius = Math.Max(0, value); // Ensure non-negative radius
                Invalidate();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);

            if (_cornerRadius > 0)
            {
                Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
                GraphicsPath path = GetRoundedRectPath(bounds, _cornerRadius);
                using (Brush brush = new SolidBrush(ForeColor)) { e.Graphics.FillPath(brush, path); }
                using (Pen pen = new Pen(ForeColor)) { e.Graphics.DrawPath(pen, path); }
            }
            else
            {
                // If no corner radius, just draw the default rectangle
                using (Brush brush = new SolidBrush(BackColor)) { e.Graphics.FillRectangle(brush, ClientRectangle); }
                using (Pen pen = new Pen(ForeColor)) { e.Graphics.DrawRectangle(pen, ClientRectangle); }
            }
        }

        private GraphicsPath GetRoundedRectPath(Rectangle bounds, int radius)
        {
            int diameter = radius * 2;
            Size size = new Size(diameter, diameter);
            Rectangle arc = new Rectangle(bounds.Location, size);
            GraphicsPath path = new GraphicsPath();

            if (radius == 0)
            {
                path.AddRectangle(bounds);
                return path;
            }

            // top left arc
            path.AddArc(arc, 180, 90);

            // top right arc
            arc.X = bounds.Right - diameter;
            path.AddArc(arc, 270, 90);

            // bottom right arc
            arc.Y = bounds.Bottom - diameter;
            path.AddArc(arc, 0, 90);

            // bottom left arc
            arc.X = bounds.Left;
            path.AddArc(arc, 90, 90);

            path.CloseFigure();
            return path;
        }

        private void filenameLabel_Click(object sender, EventArgs e)
        {
            if (removePictureBox.Visible) return;
            if ((FileData == null) || (FileData.Length == 0)) return;
            saveFileDialog.FileName = Filename;
            if (saveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                File.WriteAllBytes(saveFileDialog.FileName, FileData);
            }
        }

        private void removePictureBox_Click(object sender, EventArgs e)
        {
            Parent.Controls.Remove(this);
        }

        private void saveAsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((FileData == null) || (FileData.Length == 0)) return;
            saveFileDialog.FileName = Filename;
            if (saveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                File.WriteAllBytes(saveFileDialog.FileName, FileData);
            }
        }
    }
}
