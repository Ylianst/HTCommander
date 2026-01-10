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

using aprsparser;
using System;
using System.Drawing;

namespace HTCommander
{
    public class ChatMessage
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

        public ChatMessage(string Route, string SenderCallSign, string Message, DateTime Time, bool Sender, int ImageIndex = -1)
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
