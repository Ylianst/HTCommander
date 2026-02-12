/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using aprsparser;

namespace HTCommander
{
    public class VoiceMessage
    {
        public string Route;
        public string SenderCallSign;
        public string Message;
        public string MessageId;
        public PacketDataType MessageType;
        public DateTime Time;
        public bool Sender;
        public float DrawTop;
        public float DrawHeight;
        public int ImageIndex;
        public Object Tag;
        public RectangleF DrawRect;
        public bool Visible = true;
        public double Latitude = 0;
        public double Longitude = 0;
        public AX25Packet.AuthState AuthState = AX25Packet.AuthState.Unknown;

        public VoiceMessage(string Route, string SenderCallSign, string Message, DateTime Time, bool Sender, int ImageIndex = -1)
        {
            this.Route = Route;
            this.SenderCallSign = SenderCallSign;
            this.Message = Message;
            this.Time = Time;
            this.Sender = Sender;
            this.ImageIndex = ImageIndex;
        }
    }
}
