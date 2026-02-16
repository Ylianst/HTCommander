/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using System.ComponentModel;

namespace HTCommander
{
    public partial class TorrentBlocksUserControl : UserControl
    {
        private byte[][] _blocks;
        private const int BlockSize = 12;
        private const int BlockMargin = 2;
        private const int ShadowOffset = 2;
        private readonly Color ShadowColor = Color.FromArgb(64, Color.Black); // Semi-transparent black

        public TorrentBlocksUserControl()
        {
            InitializeComponent();
            // Enable double buffering for smoother drawing
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.DoubleBuffer, true);
            this.MouseWheel += vScrollBar_MouseWheel;
        }

        private void vScrollBar_MouseWheel(object sender, MouseEventArgs e)
        {
            // Calculate the new value
            vScrollBar.Value = Math.Max(vScrollBar.Minimum, Math.Min(vScrollBar.Maximum - ClientSize.Height, (vScrollBar.Value - (e.Delta / 4))));
            Invalidate();
        }

        [Browsable(false)]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        public byte[][] Blocks
        {
            get { return _blocks; }
            set
            {
                _blocks = value;
                // Recalculate the scrollable area and redraw when the blocks change
                UpdateScrollableSize();
                Invalidate(); // Trigger a repaint
            }
        }

        private void UpdateScrollableSize()
        {
            int realWidth = ClientSize.Width - vScrollBar.Width; // Account for scrollbar width
            if (_blocks != null && _blocks.Length > 0 && realWidth > 0)
            {
                int blocksPerRow = Math.Max(1, realWidth / (BlockSize + BlockMargin));
                int totalRows = (int)Math.Ceiling((double)_blocks.Length / blocksPerRow);
                int contentHeight = totalRows * (BlockSize + BlockMargin);
                vScrollBar.Minimum = 0;
                vScrollBar.Maximum = Math.Max(0, contentHeight);
                vScrollBar.LargeChange = Math.Max(1, ClientSize.Height);
                vScrollBar.SmallChange = BlockSize + BlockMargin;
                // Ensure the current value is within the new range
                vScrollBar.Value = Math.Min(vScrollBar.Value, vScrollBar.Maximum);
            }
            else
            {
                vScrollBar.Minimum = 0;
                vScrollBar.Maximum = 0;
            }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            // Recalculate the scrollable area on resize
            UpdateScrollableSize();
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            int realWidth = ClientSize.Width - vScrollBar.Width;

            if (_blocks == null || _blocks.Length == 0) { return; }

            int blocksPerRow = Math.Max(1, realWidth / (BlockSize + BlockMargin));
            int x = 0, y = 0;
            int scrollOffset = vScrollBar.Value;

            using (SolidBrush receivedBrush = new SolidBrush(Color.Green)) // You can customize the color
            using (Pen notReceivedPen = new Pen(Color.Gray)) // You can customize the color
            using (SolidBrush shadowBrush = new SolidBrush(ShadowColor)) // Brush for the shadow
            {
                for (int i = 0; i < _blocks.Length; i++)
                {
                    // Calculate the position of the current block
                    x = (i % blocksPerRow) * (BlockSize + BlockMargin);
                    y = (i / blocksPerRow) * (BlockSize + BlockMargin) - scrollOffset;

                    // Calculate shadow position
                    int shadowX = x + ShadowOffset;
                    int shadowY = y + ShadowOffset;

                    // Draw the shadow
                    if (shadowX <= ClientSize.Width - vScrollBar.Width && shadowX + BlockSize >= 0 && shadowY <= ClientSize.Height && shadowY + BlockSize >= 0)
                    {
                        e.Graphics.FillRectangle(shadowBrush, shadowX, shadowY, BlockSize, BlockSize);
                    }

                    // Check if the block is within the visible area
                    if (x <= ClientSize.Width - vScrollBar.Width && x + BlockSize >= 0 && y <= ClientSize.Height && y + BlockSize >= 0)
                    {
                        if (_blocks[i] != null)
                        {
                            e.Graphics.FillRectangle(receivedBrush, x, y, BlockSize, BlockSize);
                        }
                        else
                        {
                            e.Graphics.DrawRectangle(notReceivedPen, x, y, BlockSize, BlockSize);
                        }
                    }
                }
            }
        }
        private void VScrollBar_ValueChanged(object sender, EventArgs e)
        {
            Invalidate();
        }
    }
}