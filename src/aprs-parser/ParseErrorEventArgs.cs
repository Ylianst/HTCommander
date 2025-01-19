using System;

namespace aprsparser
{
    public class ParseErrorEventArgs : EventArgs
    {
        public String Packet { get; private set; }
        public String Error { get; private set; }

        public ParseErrorEventArgs(string packet, string error)
        {
            Packet = packet;
            Error = error;
        }
    }

}
