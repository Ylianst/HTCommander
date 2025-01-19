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
using System.Drawing.Drawing2D;
using System.Collections.Generic;

namespace HTCommander
{
    public partial class ChatControl : UserControl
    {
        public List<ChatMessage> Messages = new List<ChatMessage>();
        public int CornerRadius { get; set; } = 10;
        public Color MessageBoxColor { get { return messageBoxColor; } set { messageBoxColor = value; messageBoxBrush = new SolidBrush(messageBoxColor); } }
        public Color CallsignTextColor { get { return callsignTextColor; } set { callsignTextColor = value; callsignTextBrush = new SolidBrush(callsignTextColor); } }
        public Color TextColor { get { return textColor; } set { textColor = value; textBrush = new SolidBrush(textColor); } }
        public Font CallsignFont { get; set; } = new Font("Arial", 8);
        public Font MessageFont { get; set; } = new Font("Arial", 10);
        public int MinWidth { get; set; } = 100;
        public int MaxWidth { get; set; } = 300;
        public int MessageBoxMargin { get; set; } = 12;
        public int SideMargins { get; set; } = 10;
        public int InterMessageMargin { get; set; } = 4;
        public int ShadowOffset { get; set; } = 2;
        public ImageList Images { get; set; }


        private Color callsignTextColor = Color.Gray;
        private Color textColor = Color.Black;
        private Color messageBoxColor = Color.LightBlue;
        //private Color shadowColor;
        //private Color backColor;
        private Brush callsignTextBrush;
        private Brush textBrush;
        private Brush messageBoxBrush;
        private Brush shadowBrush;
        private Brush backBrush;
        private bool resized = false;
        private float totalHeight = -1;
        private float firstMessageLocation = 0;

        private StringFormat nearFormat = new StringFormat { Alignment = StringAlignment.Near };
        private StringFormat centerFormat = new StringFormat { Alignment = StringAlignment.Center };
        private StringFormat farFormat = new StringFormat { Alignment = StringAlignment.Far };


        public ChatControl()
        {
            InitializeComponent();
            this.MouseWheel += ChatControl_MouseWheel;
        }

        private void ChatControl_Paint(object sender, PaintEventArgs e)
        {
            if (callsignTextBrush == null) { callsignTextBrush = new SolidBrush(callsignTextColor); }
            if (textBrush == null) { textBrush = new SolidBrush(TextColor); }
            if (messageBoxBrush == null) { messageBoxBrush = new SolidBrush(MessageBoxColor); }
            if (shadowBrush == null) { shadowBrush = new SolidBrush(Color.FromArgb(150, 0, 0, 0)); } // Semi-transparent black
            if (backBrush == null) { backBrush = new SolidBrush(this.BackColor); }

            // Compute the height and location of each message
            if ((totalHeight < 0) || (resized)) { totalHeight = ComputeMessageHeights(e.Graphics) + (SideMargins * 2); resized = false; }
            firstMessageLocation = Height - totalHeight;
            if (totalHeight < Height)
            {
                chatScrollBar.Value = 0;
                chatScrollBar.Maximum = 0;
            }
            else
            {
                int newMax = (int)(totalHeight - Height);
                int newMax2 = newMax + 99;
                if (chatScrollBar.Maximum != newMax2)
                {
                    double oldRatio = 1;
                    if (chatScrollBar.Maximum > 0) {
                        if (chatScrollBar.Value >= newMax) { oldRatio = 1; }
                        else { oldRatio = ((double)(chatScrollBar.Value) / (double)(chatScrollBar.Maximum)); }
                    }
                    chatScrollBar.Maximum = newMax2;
                    chatScrollBar.Value = (int)(oldRatio * (double)(newMax2));
                    chatScrollBar.SmallChange = 20;
                    chatScrollBar.LargeChange = 100;
                }
                firstMessageLocation = (int)(0 - chatScrollBar.Value);
                if (firstMessageLocation < (0 - newMax)) { firstMessageLocation = (0 - newMax); }
            }
            resized = false;

            // Set up graphics quality
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            // Fill the background
            e.Graphics.FillRectangle(backBrush, ClientRectangle);

            // Draw each message
            ChatMessage prevChatMessage = null;
            foreach (ChatMessage chatMessage in Messages)
            {
                if (chatMessage.Visible == false) continue;

                // Only draw messages that are within view
                if (((firstMessageLocation + chatMessage.DrawTop + chatMessage.DrawHeight) >= 0) && ((firstMessageLocation + chatMessage.DrawTop) < Height))
                {
                    DrawChatMessage(chatMessage, e.Graphics, firstMessageLocation + chatMessage.DrawTop, prevChatMessage);
                }
                prevChatMessage = chatMessage;
            }
        }

        private float ComputeMessageHeights(Graphics g)
        {
            // Update the location of each message
            float currentLocation = 0;
            ChatMessage previousChatMessage = null;
            foreach (ChatMessage chatMessage in Messages)
            {
                if (chatMessage.Visible == false)
                {
                    chatMessage.DrawHeight = 0;
                }
                else
                {
                    chatMessage.DrawHeight = GetChatMessageHeight(chatMessage, g, previousChatMessage);
                    previousChatMessage = chatMessage;
                }
                chatMessage.DrawTop = currentLocation;
                currentLocation += chatMessage.DrawHeight;
            }
            return currentLocation;
        }

        private float GetChatMessageHeight(ChatMessage chatMessage, Graphics g, ChatMessage previousChatMessage)
        {
            SizeF timeLineSize = SizeF.Empty;
            if ((previousChatMessage == null) || (previousChatMessage.Time.AddMinutes(30).CompareTo(chatMessage.Time) < 0))
            {
                timeLineSize = g.MeasureString(chatMessage.Time.ToString(), CallsignFont);
            }
            SizeF callSignSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(chatMessage.CallSign) && ((previousChatMessage == null) || (previousChatMessage.CallSign != chatMessage.CallSign)))
            {
                callSignSize = g.MeasureString(chatMessage.CallSign, CallsignFont);
            }
            SizeF messageSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(chatMessage.Message))
            {
                int maxWidth = (int)((Width - chatScrollBar.Width) * 0.8);
                messageSize = g.MeasureString(chatMessage.Message, MessageFont, maxWidth);
            }
            return timeLineSize.Height + callSignSize.Height + messageSize.Height + (MessageBoxMargin * 2) + InterMessageMargin;
        }

        private int GetChatMessageClickBox(ChatMessage chatMessage, int x, int y)
        {
            return 0;
        }

        private void DrawChatMessage(ChatMessage chatMessage, Graphics g, float top, ChatMessage previousChatMessage)
        {
            top += InterMessageMargin;

            SizeF timeLineSize = SizeF.Empty;
            if ((previousChatMessage == null) || (previousChatMessage.Time.AddMinutes(30).CompareTo(chatMessage.Time) < 0))
            {
                string timeString;
                if ((previousChatMessage == null) || (DateTime.Now.ToShortDateString() != chatMessage.Time.ToShortDateString()))
                {
                    timeString = chatMessage.Time.ToString();
                }
                else
                {
                    timeString = chatMessage.Time.ToShortTimeString();
                }

                timeLineSize = g.MeasureString(chatMessage.Time.ToString(), CallsignFont);
                var textRect = new RectangleF(SideMargins, top, ClientRectangle.Width - chatScrollBar.Width - (SideMargins * 2), timeLineSize.Height);
                g.DrawString(timeString, CallsignFont, callsignTextBrush, textRect, centerFormat);
            }

            SizeF callSignSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(chatMessage.CallSign) && ((previousChatMessage == null) || (previousChatMessage.CallSign != chatMessage.CallSign)))
            {
                callSignSize = g.MeasureString(chatMessage.CallSign, CallsignFont);
                var textRect = new RectangleF(SideMargins, timeLineSize.Height + top, ClientRectangle.Width - chatScrollBar.Width - (SideMargins * 2), callSignSize.Height);
                g.DrawString(chatMessage.CallSign, CallsignFont, callsignTextBrush, textRect, chatMessage.Sender ? farFormat : nearFormat);
            }

            SizeF messageSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(chatMessage.Message))
            {
                int maxWidth = (int)((Width - chatScrollBar.Width) * 0.8);
                messageSize = g.MeasureString(chatMessage.Message, MessageFont, maxWidth);

                // Draw Shadow
                RectangleF r = new RectangleF(
                    chatMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins + ShadowOffset : ShadowOffset + SideMargins,
                    top + timeLineSize.Height + callSignSize.Height + ShadowOffset,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));
                using (GraphicsPath shadowPath = CreateRoundedRectanglePath(r, CornerRadius))
                {
                    g.FillPath(shadowBrush, shadowPath);
                }

                // Draw Message Box
                RectangleF r2 = new RectangleF(
                    chatMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins : SideMargins,
                    top + timeLineSize.Height + callSignSize.Height,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));
                using (GraphicsPath messageBoxPath = CreateRoundedRectanglePath(r2, CornerRadius))
                {
                    g.FillPath(messageBoxBrush, messageBoxPath);
                }

                // Set the click rect
                chatMessage.DrawRect = new RectangleF(
                    chatMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins : SideMargins,
                    timeLineSize.Height + callSignSize.Height,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));

                // Draw Message
                RectangleF r3 = new RectangleF(
                    chatMessage.Sender ? Width - messageSize.Width - MessageBoxMargin - chatScrollBar.Width - SideMargins : MessageBoxMargin + SideMargins,
                    top + timeLineSize.Height + callSignSize.Height + MessageBoxMargin + 2,
                    messageSize.Width,
                    messageSize.Height);
                g.DrawString(chatMessage.Message, MessageFont, textBrush, r3);

                // Draw the image
                if ((Images != null) && (chatMessage.ImageIndex >= 0) && (chatMessage.ImageIndex < Images.Images.Count))
                {
                    // Retrieve the image from resources
                    Image myImage = Images.Images[chatMessage.ImageIndex];
                    Rectangle destRect = new Rectangle(chatMessage.Sender ? (int)(r2.X - (Images.ImageSize.Width / 2)) : (int)(r2.X + r2.Width - (Images.ImageSize.Width / 2)), (int)(top + timeLineSize.Height + callSignSize.Height + MessageBoxMargin), Images.ImageSize.Width, Images.ImageSize.Height);
                    g.DrawImage(myImage, destRect);
                }
            }
        }

        private GraphicsPath CreateRoundedRectanglePath(RectangleF rect, int radius)
        {
            int diameter = radius * 2;
            GraphicsPath path = new GraphicsPath();
            path.StartFigure();
            path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Y, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.X, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private void ChatControl_Resize(object sender, EventArgs e)
        {
            resized = true;
            Invalidate();
        }

        private void chatScrollBar_Scroll(object sender, ScrollEventArgs e)
        {
            Invalidate();
        }

        public void UpdateMessages(bool scrollToBottom)
        {
            resized = true;
            if (scrollToBottom == true)
            {
                chatScrollBar.Value = chatScrollBar.Maximum;
            }
            Invalidate();
        }

        private void ChatControl_MouseWheel(object sender, MouseEventArgs e)
        {
            // Calculate the new value
            chatScrollBar.Value = Math.Max(chatScrollBar.Minimum, Math.Min(chatScrollBar.Maximum, (chatScrollBar.Value - (e.Delta / 4))));
            Invalidate();
        }

        public static bool IsPointInRectangleF(float x, float y, RectangleF rectangle)
        {
            // Check if the point (x, y) is within the RectangleF
            return x >= rectangle.X && x <= rectangle.X + rectangle.Width &&
                   y >= rectangle.Y && y <= rectangle.Y + rectangle.Height;
        }

        public ChatMessage GetChatMessageAtXY(int x, int y)
        {
            // Find the chat message the user clicked on
            if (y < firstMessageLocation) return null;
            int ty = (int)(y - firstMessageLocation);
            ChatMessage clickedChatMessage = null;
            foreach (ChatMessage chatMessage in Messages)
            {
                if (chatMessage.DrawTop > ty) break;
                clickedChatMessage = chatMessage;
            }
            if (clickedChatMessage == null) return null;
            ty -= (int)clickedChatMessage.DrawTop;

            // Check if the click is within the message box
            if (IsPointInRectangleF(x, ty, clickedChatMessage.DrawRect) == false) return null;

            return clickedChatMessage;
        }

        private void ChatControl_MouseClick(object sender, MouseEventArgs e)
        {
            ChatMessage msg = GetChatMessageAtXY(e.X, e.Y);


        }
    }
}
