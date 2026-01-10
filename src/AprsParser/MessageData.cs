namespace aprsparser
{
    // ReSharper disable InconsistentNaming
    public enum MessageType
    {
        mtUnknown,
        mtGeneral,
        mtBulletin,
        mtAnnouncement,
        mtNWS,
        mtAck,
        mtRej,
        mtAutoAnswer
    }
    // ReSharper restore InconsistentNaming

    public class MessageData
    {
        public string Addressee;
        public string SeqId;
        public string MsgText;
        public MessageType MsgType;
        public int MsgIndex;
    }
}
