using System;
using System.Timers;
using System.Collections.Generic;
using aprsparser;

namespace HTCommander
{
    public class AprsStack
    {
        private MainForm parent;
        private Timer retryTimer;

        // Contains a record of incoming messages for the last 5 minutes
        private List<AprsInboundMessageRecord> inboundRecords = new List<AprsInboundMessageRecord>();

        // Contains a record of outgoing messages that needs to be retried until a ACK is received or 3 retries have been completed.
        private List<AprsOutboundMessageRecord> outboundRecords = new List<AprsOutboundMessageRecord>();

        private class AprsInboundMessageRecord
        {
            public AprsInboundMessageRecord(DateTime time, string msgTag) { this.time = time; this.msgTag = msgTag; }
            public DateTime time;
            public string msgTag;
            public int ackCount = 0;
        }
        private class AprsOutboundMessageRecord
        {
            public AprsOutboundMessageRecord(DateTime nextRetry, AX25Packet packet, int channelId, int regionId) { this.nextRetry = nextRetry; this.packet = packet; this.channelId = channelId; this.regionId = regionId; }
            public DateTime nextRetry;
            public AX25Packet packet;
            public int channelId;
            public int regionId;
            public int retryCount;
        }

        public AprsStack(MainForm parent)
        {
            this.parent = parent;
            retryTimer = new Timer(250);
            retryTimer.Elapsed += RetryTimerElapsed;
        }

        private AprsInboundMessageRecord isDuplicate(DateTime time, string msgTag)
        {
            while ((inboundRecords.Count > 0) && (inboundRecords[0].time.AddMinutes(5) < time)) { inboundRecords.RemoveAt(0); }
            foreach (AprsInboundMessageRecord record in inboundRecords) { if (record.msgTag == msgTag) { return record; } }
            AprsInboundMessageRecord r = new AprsInboundMessageRecord(time, msgTag);
            inboundRecords.Add(r);
            return r;
        }

        public void Reset()
        {
            retryTimer.Stop();
            outboundRecords.Clear();
            inboundRecords.Clear();
        }

        private void RetryTimerElapsed(object sender, ElapsedEventArgs e)
        {
            List<AprsOutboundMessageRecord> toRetry = new List<AprsOutboundMessageRecord>();

            lock (outboundRecords) // Important: Lock when accessing shared resources
            {
                DateTime now = DateTime.Now;
                foreach (AprsOutboundMessageRecord record in outboundRecords)
                {
                    if (record.nextRetry <= now)
                    {
                        toRetry.Add(record);
                        record.nextRetry = record.nextRetry.AddSeconds(8); // Set next retry time
                        record.retryCount++;
                    }
                }

                foreach (AprsOutboundMessageRecord record in toRetry)
                {
                    parent.radio.TransmitTncData(record.packet, record.channelId, record.regionId);
                    if (record.retryCount >= 2) { outboundRecords.Remove(record); }
                }

                if (outboundRecords.Count == 0) { retryTimer.Stop(); }
            }
        }

        // Called when a packet is sent out
        public int ProcessOutgoing(AX25Packet packet, int channelId = -1, int regionId = -1)
        {
            AprsOutboundMessageRecord r = new AprsOutboundMessageRecord(DateTime.Now.AddSeconds(5), packet, channelId, regionId);
            outboundRecords.Add(r);
            int size = parent.radio.TransmitTncData(packet, channelId, regionId); // Transmit the packet the first time
            retryTimer.Start();
            return size;
        }

        // Called when a APRS packet is received
        public bool ProcessIncoming(AprsPacket aprs)
        {
            if ((aprs == null) || (aprs.Packet == null)) return true;
            if (aprs.Packet.addresses.Count < 2) return false;
            if (aprs.Packet.incoming == false) return true;

            // Check if this packet is for us
            if ((aprs.DataType == PacketDataType.Message) && (aprs.MessageData.Addressee == parent.callsign + "-" + parent.stationId) || (aprs.MessageData.Addressee == parent.callsign))
            {
                // This is a general message, we need at ACK it.
                if ((aprs.MessageData.MsgType == MessageType.mtGeneral))
                {
                    AprsInboundMessageRecord r = isDuplicate(aprs.Packet.time, aprs.Packet.addresses[1].address + "-" + aprs.Packet.addresses[1].SSID + "-" + aprs.MessageData.SeqId);

                    // Send back a confirmation of receipt
                    if ((parent.allowTransmit == true) && (r.ackCount <= 3))
                    {
                        List<AX25Address> addresses = new List<AX25Address>(aprs.Packet.addresses.Count);
                        addresses.Add(aprs.Packet.addresses[0]);
                        addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));
                        for (int i = 2; i < aprs.Packet.addresses.Count; i++)
                        {
                            addresses.Add(AX25Address.GetAddress(aprs.Packet.addresses[i].address, aprs.Packet.addresses[i].SSID));
                        }

                        // APRS format
                        string aprsAddr = ":" + aprs.Packet.addresses[1].address;
                        if (aprs.Packet.addresses[1].SSID > 0) { aprsAddr += "-" + aprs.Packet.addresses[1].SSID; }
                        while (aprsAddr.Length < 10) { aprsAddr += " "; }
                        AX25Packet rpacket = new AX25Packet(addresses, aprsAddr + ":ack" + aprs.MessageData.SeqId, DateTime.Now);
                        parent.radio.TransmitTncData(rpacket, aprs.Packet.channel_id);
                    }

                    // Check if we already got this message
                    return (r.ackCount++ == 0);
                }

                // This is an APRS ACK
                if ((aprs.MessageData.MsgType == MessageType.mtAck))
                {
                    AprsOutboundMessageRecord found = null;
                    foreach (AprsOutboundMessageRecord r in outboundRecords)
                    {
                        if (r.packet.messageId.ToString() == aprs.MessageData.SeqId) { found = r; break; }
                    }
                    if (found != null) { outboundRecords.Remove(found); }
                }
            }
            return true;
        }

    }
}
