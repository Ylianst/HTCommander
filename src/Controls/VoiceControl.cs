/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using System.Drawing.Drawing2D;
using System.Collections.Generic;
using System.ComponentModel;

namespace HTCommander
{
    public partial class VoiceControl : UserControl
    {
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public List<VoiceMessage> Messages = new List<VoiceMessage>();

        [Category("Appearance")]
        [DefaultValue(10)]
        public int CornerRadius { get; set; } = 10;

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Color MessageBoxColor { get { return messageBoxColor; } set { messageBoxColor = value; messageBoxBrush = new SolidBrush(messageBoxColor); } }

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Color MessageBoxAuthColor { get { return messageBoxAuthColor; } set { messageBoxAuthColor = value; messageBoxAuthBrush = new SolidBrush(messageBoxAuthColor); } }

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Color MessageBoxBadColor { get { return messageBoxBadColor; } set { messageBoxBadColor = value; messageBoxBadBrush = new SolidBrush(messageBoxBadColor); } }

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Color CallsignTextColor { get { return callsignTextColor; } set { callsignTextColor = value; callsignTextBrush = new SolidBrush(callsignTextColor); } }

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Color TextColor { get { return textColor; } set { textColor = value; } }

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Font CallsignFont { get; set; } = new Font("Arial", 8);

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public Font MessageFont { get; set; } = new Font("Arial", 10);

        [Category("Layout")]
        [DefaultValue(100)]
        public int MinWidth { get; set; } = 100;

        /// <summary>
        /// Gets the effective maximum width for message boxes (80% of control width minus scrollbar).
        /// </summary>
        [Browsable(false)]
        public int EffectiveMaxWidth
        {
            get
            {
                int controlWidth = Width - chatScrollBar.Width - (SideMargins * 2) - (MessageBoxMargin * 2);
                return (int)(controlWidth * 0.9);
            }
        }

        [Category("Layout")]
        [DefaultValue(12)]
        public int MessageBoxMargin { get; set; } = 12;

        [Category("Layout")]
        [DefaultValue(10)]
        public int SideMargins { get; set; } = 10;

        [Category("Layout")]
        [DefaultValue(4)]
        public int InterMessageMargin { get; set; } = 4;

        [Category("Layout")]
        [DefaultValue(2)]
        public int ShadowOffset { get; set; } = 2;

        [Category("Appearance")]
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Visible)]
        public ImageList Images { get; set; }


        private Color callsignTextColor = Color.Gray;
        private Color textColor = Color.Black;
        private Color messageBoxColor = Color.LightBlue;
        private Color messageBoxAuthColor = Color.LightGreen;
        private Color messageBoxBadColor = Color.Pink;
        //private Color shadowColor;
        //private Color backColor;
        private Brush callsignTextBrush;
        private Brush messageBoxBrush;
        private Brush messageBoxAuthBrush;
        private Brush messageBoxBadBrush;
        private Brush shadowBrush;
        private Brush backBrush;
        private bool resized = false;
        private float totalHeight = -1;
        private float firstMessageLocation = 0;

        private StringFormat nearFormat = new StringFormat { Alignment = StringAlignment.Near };
        private StringFormat centerFormat = new StringFormat { Alignment = StringAlignment.Center };
        private StringFormat farFormat = new StringFormat { Alignment = StringAlignment.Far };

        private const int SstvThumbnailHeight = 100;

        /// <summary>
        /// Gets the full path to an SSTV image file.
        /// </summary>
        public static string GetSstvImagePath(string filename)
        {
            return System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HTCommander", "SSTV", filename);
        }

        /// <summary>
        /// Gets the cached thumbnail for the given voice message, generating it on first access.
        /// Handles both completed images (from file) and partial images (in-progress SSTV).
        /// Returns null if no image is available.
        /// </summary>
        private static Image GetSstvThumbnail(VoiceMessage voiceMessage)
        {
            if (voiceMessage == null) return null;

            // If there's a partial image (in-progress SSTV), always regenerate thumbnail from it
            if (voiceMessage.PartialImage != null)
            {
                voiceMessage.Thumbnail?.Dispose();
                voiceMessage.Thumbnail = null;

                try
                {
                    int srcWidth = voiceMessage.PartialImage.Width;
                    int srcHeight = voiceMessage.PartialImage.Height;
                    if (srcWidth <= 0 || srcHeight <= 0) return null;

                    int thumbWidth = (int)((double)srcWidth / srcHeight * SstvThumbnailHeight);
                    if (thumbWidth <= 0) thumbWidth = 1;
                    var thumb = new Bitmap(thumbWidth, SstvThumbnailHeight);
                    using (var g = Graphics.FromImage(thumb))
                    {
                        g.Clear(Color.Black); // Black background for unreceived lines
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.DrawImage(voiceMessage.PartialImage, 0, 0, thumbWidth, SstvThumbnailHeight);
                    }
                    voiceMessage.Thumbnail = thumb;
                    return thumb;
                }
                catch
                {
                    return null;
                }
            }

            // Completed image from file
            if (string.IsNullOrEmpty(voiceMessage.Filename)) return null;
            if (voiceMessage.Thumbnail != null) return voiceMessage.Thumbnail;

            try
            {
                string fullPath = GetSstvImagePath(voiceMessage.Filename);
                if (!System.IO.File.Exists(fullPath)) return null;

                using (var original = Image.FromFile(fullPath))
                {
                    int thumbWidth = (int)((double)original.Width / original.Height * SstvThumbnailHeight);
                    var thumb = new Bitmap(thumbWidth, SstvThumbnailHeight);
                    using (var g = Graphics.FromImage(thumb))
                    {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.DrawImage(original, 0, 0, thumbWidth, SstvThumbnailHeight);
                    }
                    voiceMessage.Thumbnail = thumb;
                    return thumb;
                }
            }
            catch
            {
                return null;
            }
        }


        public VoiceControl()
        {
            InitializeComponent();
            this.MouseWheel += VoiceControl_MouseWheel;
        }

        private void VoiceControl_Paint(object sender, PaintEventArgs e)
        {
            if (callsignTextBrush == null) { callsignTextBrush = new SolidBrush(callsignTextColor); }
            if (messageBoxBrush == null) { messageBoxBrush = new SolidBrush(MessageBoxColor); }
            if (messageBoxAuthBrush == null) { messageBoxAuthBrush = new SolidBrush(MessageBoxAuthColor); }
            if (messageBoxBadBrush == null) { messageBoxBadBrush = new SolidBrush(MessageBoxBadColor); }
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
            VoiceMessage prevVoiceMessage = null;
            foreach (VoiceMessage voiceMessage in Messages)
            {
                if (voiceMessage.Visible == false) continue;

                // Only draw messages that are within view
                if (((firstMessageLocation + voiceMessage.DrawTop + voiceMessage.DrawHeight) >= 0) && ((firstMessageLocation + voiceMessage.DrawTop) < Height))
                {
                    DrawVoiceMessage(voiceMessage, e.Graphics, firstMessageLocation + voiceMessage.DrawTop, prevVoiceMessage);
                }
                prevVoiceMessage = voiceMessage;
            }
        }

        private float ComputeMessageHeights(Graphics g)
        {
            // Update the location of each message
            float currentLocation = 0;
            VoiceMessage previousVoiceMessage = null;
            foreach (VoiceMessage voiceMessage in Messages)
            {
                if (voiceMessage.Visible == false)
                {
                    voiceMessage.DrawHeight = 0;
                }
                else
                {
                    voiceMessage.DrawHeight = GetVoiceMessageHeight(voiceMessage, g, previousVoiceMessage);
                    previousVoiceMessage = voiceMessage;
                }
                voiceMessage.DrawTop = currentLocation;
                currentLocation += voiceMessage.DrawHeight;
            }
            return currentLocation;
        }

        private float GetVoiceMessageHeight(VoiceMessage voiceMessage, Graphics g, VoiceMessage previousVoiceMessage)
        {
            SizeF timeLineSize = SizeF.Empty;
            if ((previousVoiceMessage == null) || (previousVoiceMessage.Time.AddMinutes(30).CompareTo(voiceMessage.Time) < 0))
            {
                timeLineSize = TextRenderer.MeasureText(voiceMessage.Time.ToString(), CallsignFont);
            }
            SizeF callSignSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(voiceMessage.Route) && ((previousVoiceMessage == null) || (previousVoiceMessage.Route != voiceMessage.Route)))
            {
                callSignSize = TextRenderer.MeasureText(voiceMessage.Route, CallsignFont);
            }
            SizeF messageSize = SizeF.Empty;
            if (voiceMessage.Encoding == VoiceTextEncodingType.Picture && (!string.IsNullOrEmpty(voiceMessage.Filename) || voiceMessage.PartialImage != null))
            {
                // For picture messages, size is based on the thumbnail image
                Image thumb = GetSstvThumbnail(voiceMessage);
                if (thumb != null)
                {
                    messageSize = new SizeF(thumb.Width, thumb.Height);
                }
                else if (!string.IsNullOrEmpty(voiceMessage.Message))
                {
                    int maxMessageWidth = Math.Max(EffectiveMaxWidth, MinWidth);
                    messageSize = TextRenderer.MeasureText(voiceMessage.Message, MessageFont, new Size(maxMessageWidth, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
                }
            }
            else if (!string.IsNullOrEmpty(voiceMessage.Message))
            {
                // Calculate the maximum width for the message box (80% of control width)
                int maxMessageWidth = Math.Max(EffectiveMaxWidth, MinWidth);
                
                messageSize = TextRenderer.MeasureText(voiceMessage.Message, MessageFont, new Size(maxMessageWidth, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
            }
            bool hasMessageContent = (messageSize.Width > 0 && messageSize.Height > 0);
            return timeLineSize.Height + callSignSize.Height + (hasMessageContent ? messageSize.Height + (MessageBoxMargin * 2) : 0) + InterMessageMargin;
        }

        private void DrawVoiceMessage(VoiceMessage voiceMessage, Graphics g, float top, VoiceMessage previousVoiceMessage)
        {
            top += InterMessageMargin;

            SizeF timeLineSize = SizeF.Empty;
            if ((previousVoiceMessage == null) || (previousVoiceMessage.Time.AddMinutes(30).CompareTo(voiceMessage.Time) < 0))
            {
                string timeString;
                if ((previousVoiceMessage == null) || (DateTime.Now.ToShortDateString() != voiceMessage.Time.ToShortDateString()))
                {
                    timeString = voiceMessage.Time.ToString();
                }
                else
                {
                    timeString = voiceMessage.Time.ToShortTimeString();
                }

                timeLineSize = TextRenderer.MeasureText(timeString, CallsignFont);
                var textRect = new Rectangle(SideMargins, (int)top, ClientRectangle.Width - chatScrollBar.Width - (SideMargins * 2), (int)timeLineSize.Height);
                TextRenderer.DrawText(g, timeString, CallsignFont, textRect, callsignTextColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.WordBreak);
            }

            SizeF callSignSize = SizeF.Empty;
            if (!string.IsNullOrEmpty(voiceMessage.Route) && ((previousVoiceMessage == null) || (previousVoiceMessage.Route != voiceMessage.Route)))
            {
                callSignSize = TextRenderer.MeasureText(voiceMessage.Route, CallsignFont);
                var textRect = new Rectangle(SideMargins, (int)(timeLineSize.Height + top), ClientRectangle.Width - chatScrollBar.Width - (SideMargins * 2), (int)callSignSize.Height);
                TextFormatFlags routeFlags = voiceMessage.Sender ? TextFormatFlags.Right : TextFormatFlags.Left;
                TextRenderer.DrawText(g, voiceMessage.Route, CallsignFont, textRect, callsignTextColor, routeFlags | TextFormatFlags.WordBreak);
            }

            SizeF messageSize = SizeF.Empty;
            bool isPicture = voiceMessage.Encoding == VoiceTextEncodingType.Picture && (!string.IsNullOrEmpty(voiceMessage.Filename) || voiceMessage.PartialImage != null);
            Image sstvThumb = isPicture ? GetSstvThumbnail(voiceMessage) : null;

            if (isPicture && sstvThumb != null)
            {
                messageSize = new SizeF(sstvThumb.Width, sstvThumb.Height);
            }
            else if (!string.IsNullOrEmpty(voiceMessage.Message))
            {
                // Calculate the maximum width for the message box (80% of control width, same as GetVoiceMessageHeight)
                int maxMessageWidth = Math.Max(EffectiveMaxWidth, MinWidth);
                
                messageSize = TextRenderer.MeasureText(voiceMessage.Message, MessageFont, new Size(maxMessageWidth, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
            }

            if (messageSize.Width <= 0 || messageSize.Height <= 0)
            {
                // No message content - set click rect on the route string area if present
                if (callSignSize.Width > 0 && callSignSize.Height > 0)
                {
                    voiceMessage.DrawRect = new RectangleF(
                        SideMargins,
                        timeLineSize.Height,
                        ClientRectangle.Width - chatScrollBar.Width - (SideMargins * 2),
                        callSignSize.Height);
                }
                else
                {
                    voiceMessage.DrawRect = RectangleF.Empty;
                }
                return;
            }

            {
                // Draw Shadow
                RectangleF r = new RectangleF(
                    voiceMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins + ShadowOffset : ShadowOffset + SideMargins,
                    top + timeLineSize.Height + callSignSize.Height + ShadowOffset,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));
                using (GraphicsPath shadowPath = CreateRoundedRectanglePath(r, CornerRadius))
                {
                    g.FillPath(shadowBrush, shadowPath);
                }

                // Draw Message Box
                RectangleF r2 = new RectangleF(
                    voiceMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins : SideMargins,
                    top + timeLineSize.Height + callSignSize.Height,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));
                using (GraphicsPath messageBoxPath = CreateRoundedRectanglePath(r2, CornerRadius))
                {
                    if (voiceMessage.AuthState == AX25Packet.AuthState.Success)
                    {
                        g.FillPath(messageBoxAuthBrush, messageBoxPath);
                    }
                    else if (voiceMessage.AuthState == AX25Packet.AuthState.Failed)
                    {
                        g.FillPath(messageBoxBadBrush, messageBoxPath);
                    }
                    else
                    {
                        g.FillPath(messageBoxBrush, messageBoxPath);
                    }
                }

                // Set the click rect
                voiceMessage.DrawRect = new RectangleF(
                    voiceMessage.Sender ? Width - messageSize.Width - (MessageBoxMargin * 2) - chatScrollBar.Width - SideMargins : SideMargins,
                    timeLineSize.Height + callSignSize.Height,
                    messageSize.Width + (MessageBoxMargin * 2),
                    messageSize.Height + (MessageBoxMargin * 2));

                if (isPicture && sstvThumb != null)
                {
                    // Draw the SSTV thumbnail image inside the message box
                    Rectangle imgRect = new Rectangle(
                        (int)(voiceMessage.Sender ? Width - messageSize.Width - MessageBoxMargin - chatScrollBar.Width - SideMargins : MessageBoxMargin + SideMargins),
                        (int)(top + timeLineSize.Height + callSignSize.Height + MessageBoxMargin),
                        sstvThumb.Width,
                        sstvThumb.Height);
                    g.DrawImage(sstvThumb, imgRect);
                }
                else
                {
                    // Draw Message text
                    Rectangle textRect = new Rectangle(
                        (int)(voiceMessage.Sender ? Width - messageSize.Width - MessageBoxMargin - chatScrollBar.Width - SideMargins : MessageBoxMargin + SideMargins),
                        (int)(top + timeLineSize.Height + callSignSize.Height + MessageBoxMargin + 2),
                        (int)messageSize.Width,
                        (int)messageSize.Height);

                    TextRenderer.DrawText(g, voiceMessage.Message, MessageFont, textRect, textColor, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
                }

                // Draw the image icon (e.g., location pin)
                if ((Images != null) && (voiceMessage.ImageIndex >= 0) && (voiceMessage.ImageIndex < Images.Images.Count))
                {
                    // Retrieve the image from resources
                    Image myImage = Images.Images[voiceMessage.ImageIndex];
                    Rectangle destRect = new Rectangle(voiceMessage.Sender ? (int)(r2.X - (Images.ImageSize.Width / 2)) : (int)(r2.X + r2.Width - (Images.ImageSize.Width / 2)), (int)(top + timeLineSize.Height + callSignSize.Height + MessageBoxMargin), Images.ImageSize.Width, Images.ImageSize.Height);
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

        private void VoiceControl_Resize(object sender, EventArgs e)
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

        /// <summary>
        /// Clears all messages from the control.
        /// </summary>
        public void Clear()
        {
            Messages.Clear();
            resized = true;
            totalHeight = -1;
            chatScrollBar.Value = 0;
            Invalidate();
        }

        /// <summary>
        /// Adds a new message to the control.
        /// </summary>
        /// <param name="message">The message to add.</param>
        /// <param name="scrollToBottom">Whether to scroll to the bottom after adding.</param>
        public void AddMessage(VoiceMessage message, bool scrollToBottom = true)
        {
            Messages.Add(message);
            UpdateMessages(scrollToBottom);
        }

        /// <summary>
        /// Gets the current partial (incomplete) message if one exists.
        /// </summary>
        /// <returns>The partial message, or null if none exists.</returns>
        public VoiceMessage GetPartialMessage()
        {
            if (Messages.Count == 0) return null;
            var lastMessage = Messages[Messages.Count - 1];
            return lastMessage.IsCompleted ? null : lastMessage;
        }

        /// <summary>
        /// Updates or creates a partial message. Used for in-progress speech-to-text.
        /// If the last message is incomplete, it updates it. Otherwise, it creates a new one.
        /// If the message text is null or empty after trimming, no entry is created.
        /// </summary>
        /// <param name="text">The message text.</param>
        /// <param name="channel">The channel/route.</param>
        /// <param name="time">The timestamp.</param>
        /// <param name="completed">Whether the message is complete.</param>
        /// <param name="isReceived">Whether the message was received (true) or sent (false).</param>
        /// <param name="encoding">The encoding type.</param>
        /// <param name="latitude">Latitude coordinate if location data is available.</param>
        /// <param name="longitude">Longitude coordinate if location data is available.</param>
        public void UpdatePartialMessage(string text, string channel, DateTime time, bool completed, bool isReceived, VoiceTextEncodingType encoding, double latitude = 0, double longitude = 0, string source = null, string destination = null, string filename = null, int duration = 0, Image partialImage = null)
        {
            string trimmedText = text?.Trim() ?? "";
            var partial = GetPartialMessage();
            
            // Determine if message has a valid location
            bool hasLocation = (latitude != 0 || longitude != 0);
            int imageIndex = hasLocation ? 3 : -1;
            
            if (partial != null)
            {
                if (string.IsNullOrEmpty(trimmedText) && completed && encoding != VoiceTextEncodingType.Recording && encoding != VoiceTextEncodingType.Picture)
                {
                    // Empty completed message - remove the partial entry
                    Messages.Remove(partial);
                }
                else
                {
                    // Update existing partial message
                    partial.Message = trimmedText;
                    partial.Route = FormatRoute(channel, encoding, source, destination, duration);
                    partial.SenderCallSign = source;
                    partial.Time = time;
                    partial.Sender = !isReceived;
                    partial.Encoding = encoding;
                    partial.IsCompleted = completed;
                    partial.Latitude = latitude;
                    partial.Longitude = longitude;
                    partial.ImageIndex = imageIndex;
                    partial.Filename = filename;

                    // Handle partial image updates for progressive SSTV
                    if (partialImage != null)
                    {
                        partial.PartialImage?.Dispose();
                        partial.PartialImage = partialImage;
                        partial.Thumbnail?.Dispose();
                        partial.Thumbnail = null; // Force thumbnail regeneration
                    }
                    else if (completed)
                    {
                        // Completed - clear partial image, let filename-based loading take over
                        partial.PartialImage?.Dispose();
                        partial.PartialImage = null;
                        partial.Thumbnail?.Dispose();
                        partial.Thumbnail = null; // Force thumbnail regeneration from file
                    }
                }
            }
            else
            {
                // Don't create new message if text is empty (except for Recording and Picture entries)
                if (string.IsNullOrEmpty(trimmedText) && encoding != VoiceTextEncodingType.Recording && encoding != VoiceTextEncodingType.Picture)
                {
                    return;
                }
                
                // Create new message
                var message = new VoiceMessage(
                    FormatRoute(channel, encoding, source, destination, duration),
                    source,
                    trimmedText,
                    time,
                    !isReceived,
                    imageIndex,
                    encoding
                );
                message.IsCompleted = completed;
                message.Latitude = latitude;
                message.Longitude = longitude;
                message.Filename = filename;
                if (partialImage != null)
                {
                    message.PartialImage = partialImage;
                }
                Messages.Add(message);
            }
            
            UpdateMessages(true);
        }

        /// <summary>
        /// Formats the route string to include encoding type.
        /// </summary>
        private string FormatRoute(string channel, VoiceTextEncodingType encoding, string source = null, string destination = null, int duration = 0)
        {
            string encodingStr = GetEncodingTypeName(encoding);
            if (encoding == VoiceTextEncodingType.Recording && duration > 0)
            {
                encodingStr = "Recording " + FormatDuration(duration);
            }
            string callsignPart = "";
            if (!string.IsNullOrEmpty(source))
            {
                callsignPart = !string.IsNullOrEmpty(destination)
                    ? $" {source} > {destination}"
                    : $" {source}";
            }
            if (string.IsNullOrEmpty(channel))
            {
                return encodingStr + callsignPart;
            }
            return $"[{channel}] {encodingStr}{callsignPart}";
        }

        /// <summary>
        /// Formats a duration in seconds into a human-readable string.
        /// Less than 60 seconds: "34s", 60 or more: "5m 34s".
        /// </summary>
        private string FormatDuration(int totalSeconds)
        {
            if (totalSeconds < 60) return $"{totalSeconds}s";
            int minutes = totalSeconds / 60;
            int seconds = totalSeconds % 60;
            return seconds > 0 ? $"{minutes}m {seconds}s" : $"{minutes}m";
        }

        /// <summary>
        /// Gets the display name for a VoiceTextEncodingType.
        /// </summary>
        private string GetEncodingTypeName(VoiceTextEncodingType encoding)
        {
            switch (encoding)
            {
                case VoiceTextEncodingType.Voice: return "Voice";
                case VoiceTextEncodingType.Morse: return "Morse";
                case VoiceTextEncodingType.VoiceClip: return "Clip";
                case VoiceTextEncodingType.AX25: return "AX.25";
                case VoiceTextEncodingType.BSS: return "Chat";
                case VoiceTextEncodingType.Picture: return "SSTV";
                default: return encoding.ToString();
            }
        }

        /// <summary>
        /// Scrolls the control to the bottom.
        /// </summary>
        public void ScrollToBottom()
        {
            chatScrollBar.Value = chatScrollBar.Maximum;
            Invalidate();
        }

        private void VoiceControl_MouseWheel(object sender, MouseEventArgs e)
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

        public VoiceMessage GetVoiceMessageAtXY(int x, int y)
        {
            // Find the voice message the user clicked on
            if (y < firstMessageLocation) return null;
            int ty = (int)(y - firstMessageLocation);
            VoiceMessage clickedVoiceMessage = null;
            foreach (VoiceMessage voiceMessage in Messages)
            {
                if (voiceMessage.DrawTop > ty) break;
                clickedVoiceMessage = voiceMessage;
            }
            if (clickedVoiceMessage == null) return null;
            ty -= (int)clickedVoiceMessage.DrawTop;

            // Check if the click is within the message box
            if (IsPointInRectangleF(x, ty, clickedVoiceMessage.DrawRect) == false) return null;

            return clickedVoiceMessage;
        }

        private void VoiceControl_MouseClick(object sender, MouseEventArgs e)
        {
            VoiceMessage msg = GetVoiceMessageAtXY(e.X, e.Y);
        }
    }
}
