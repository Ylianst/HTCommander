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
using System.Timers;
using System.Collections.Generic;
using static HTCommander.AX25Packet;
using System.Text;

namespace HTCommander
{
    public class AX25Session
    {
        private Radio radio = null;
        private MainForm parent = null;
        public Dictionary<string, object> sessionState = new Dictionary<string, object>();

        public delegate void StateChangedHandler(AX25Session sender, ConnectionState state);
        public event StateChangedHandler StateChanged;

        public delegate void DataReceivedHandler(AX25Session sender, byte[] data);
        public event DataReceivedHandler DataReceivedEvent;
        public event DataReceivedHandler UiDataReceivedEvent;

        public delegate void ErrorHandler(AX25Session sender, string error);
        public event ErrorHandler ErrorEvent;

        private void OnErrorEvent(string error) { Trace("ERROR: " + error); if (ErrorEvent != null) { ErrorEvent(this, error); } }
        private void OnStateChangedEvent(ConnectionState state) { if (StateChanged != null) { StateChanged(this, state); } }
        private void OnUiDataReceivedEvent(byte[] data) { if (UiDataReceivedEvent != null) { UiDataReceivedEvent(this, data); } }
        private void OnDataReceivedEvent(byte[] data) { if (DataReceivedEvent != null) { DataReceivedEvent(this, data); } }

        public enum ConnectionState
        {
            DISCONNECTED = 1,
            CONNECTED = 2,
            CONNECTING = 3,
            DISCONNECTING = 4
        }

        private enum TimerNames { Connect, Disconnect, T1, T2, T3 }

        public int MaxFrames = 4;
        public int PacketLength = 256;
        public int Retries = 3;
        public int HBaud = 600; // 1200
        public bool Modulo128 = false;
        public bool Traceing = true;

        private void Trace(string msg) { if (Traceing) { parent.Debug("X25: " + msg); } }

        private void SetConnectionState(ConnectionState state)
        {
            if (state != _state.Connection)
            {
                _state.Connection = state;
                OnStateChangedEvent(state);
                if (state == ConnectionState.DISCONNECTED) { _state.SendBuffer.Clear(); Addresses = null; sessionState.Clear(); }
            }
        }

        private class State
        {
            public ConnectionState Connection { get; set; } = ConnectionState.DISCONNECTED;
            public byte ReceiveSequence { get; set; } = 0;
            public byte SendSequence { get; set; } = 0;
            public byte RemoteReceiveSequence { get; set; } = 0;
            public bool RemoteBusy { get; set; } = false;
            public bool SentREJ { get; set; } = false;
            public bool SentSREJ { get; set; } = false;
            public int GotREJSequenceNum { get; set; } = -1;
            public int GotSREJSequenceNum { get; set; } = -1;
            public List<AX25Packet> SendBuffer { get; set; } = new List<AX25Packet>();
        }
        private readonly State _state = new State();

        private class Timers
        {
            public Timer Connect { get; set; } = new Timer();
            public Timer Disconnect { get; set; } = new Timer();
            public Timer T1 { get; set; } = new Timer();
            public Timer T2 { get; set; } = new Timer();
            public Timer T3 { get; set; } = new Timer();
            public int ConnectAttempts { get; set; } = 0;
            public int DisconnectAttempts { get; set; } = 0;
            public int T1Attempts { get; set; } = 0;
            public int T3Attempts { get; set; } = 0;
        }
        private readonly Timers _timers = new Timers();

        public ConnectionState CurrentState { get { return _state.Connection; } }

        public List<AX25Address> Addresses = null;

        public int SendBufferLength => _state.SendBuffer.Count;

        public AX25Session(MainForm parent, Radio radio)
        {
            this.parent = parent;
            this.radio = radio;

            // Initialize Timers and their callbacks
            _timers.Connect.Elapsed += ConnectTimerCallback;
            _timers.Disconnect.Elapsed += DisconnectTimerCallback;

            // Sent I-frame Acknowledgement Timer (6.7.1.3 and 4.4.5.1). This is started when a single
            // I-frame is sent, or when the last I-frame in a sequence of I-frames is sent. This is
            // cleared by the reception of an acknowledgement for the I-frame (or by the link being
            // reset). If this timer expires, we follow 6.4.11 - we're supposed to send an RR/RNR with
            // the P-bit set and then restart the timer. After N attempts, we reset the link.
            _timers.T1.Elapsed += T1TimerCallback;

            // Response Delay Timer (6.7.1.2). This is started when an I-frame is received. If
            // subsequent I-frames are received, the timer should be restarted. When it expires
            // an RR for the received data can be sent or an I-frame if there are any new packets
            // to send.
            _timers.T2.Elapsed += T2TimerCallback;

            // Poll Timer (6.7.1.3 and 4.4.5.2). This is started when T1 is not running (there are
            // no outstanding I-frames). When it times out and RR or RNR should be transmitted
            // and T1 started.
            _timers.T3.Elapsed += T3TimerCallback;
        }

        private void EmitPacket(AX25Packet packet)
        {
            Trace("EmitPacket");
            if (parent.activeChannelIdLock < 0) return;
            radio.TransmitTncData(packet, parent.activeChannelIdLock);
        }

        // Milliseconds required to transmit the largest possible packet
        private int GetMaxPacketTime()
        {
            return (int)Math.Floor((double)((600 + (PacketLength * 8)) / HBaud) * 1000);
        }

        // This isn't great, but we need to give the TNC time to
        // finish transmitting any packets we've sent to it before we
        // can reasonably start expecting a response from the remote
        // side. A large settings.maxFrames value coupled with a
        // large number of sent but unacknowledged frames could lead
        // to a very long interval.
        private int GetTimeout()
        {
            int multiplier = 0;
            foreach (AX25Packet packet in _state.SendBuffer) { if (packet.sent) { multiplier++; } }
            return (GetMaxPacketTime() * Math.Max(1, Addresses.Count - 2) * 4) + (GetMaxPacketTime() * Math.Max(1, multiplier));
        }

        private void SetTimer(TimerNames timerName)
        {
            ClearTimer(timerName); // Clear any currently running timer
            if (Addresses == null) return;

            Timer timer = null;
            switch (timerName)
            {
                case TimerNames.Connect: timer = _timers.Connect; break;
                case TimerNames.Disconnect: timer = _timers.Disconnect; break;
                case TimerNames.T1: timer = _timers.T1; break;
                case TimerNames.T2: timer = _timers.T2; break;
                case TimerNames.T3: timer = _timers.T3; break;
                default: return; // Invalid timer name
            }

            timer.Interval = GetTimerTimeout(timerName); // Get timeout based on timerName
            Trace("SetTimer " + timerName.ToString() + " to " + timer.Interval + "ms");
            timer.Enabled = true;
            timer.Start();
        }

        private double GetTimerTimeout(TimerNames timerName)
        {
            switch (timerName)
            {
                case TimerNames.Connect: return GetTimeout();
                case TimerNames.Disconnect: return GetTimeout();
                case TimerNames.T1: return GetTimeout();
                case TimerNames.T2: return GetMaxPacketTime() * 2;
                case TimerNames.T3: return GetTimeout() * 7;
                default: return 0; // Or throw an exception for invalid timer name if needed
            }
        }

        private void ClearTimer(TimerNames timerName)
        {
            Trace("ClearTimer " + timerName.ToString());
            Timer timer = null;
            switch (timerName)
            {
                case TimerNames.Connect: timer = _timers.Connect; break;
                case TimerNames.Disconnect: timer = _timers.Disconnect; break;
                case TimerNames.T1: timer = _timers.T1; break;
                case TimerNames.T2: timer = _timers.T2; break;
                case TimerNames.T3: timer = _timers.T3; break;
                default: return; // Invalid timer name
            }

            timer.Stop();
            timer.Enabled = false;

            switch (timerName)
            {
                case TimerNames.Connect: _timers.ConnectAttempts = 0; break;
                case TimerNames.Disconnect: _timers.DisconnectAttempts = 0; break;
                case TimerNames.T1: _timers.T1Attempts = 0; break;
                case TimerNames.T3: _timers.T3Attempts = 0; break;
            }
        }

        private void ReceiveAcknowledgement(AX25Packet packet)
        {
            // first, scan the sent packets. If it's a packet we've already
            // sent and it's earlier than the incoming packet's NR count,
            // it was received and we can discard it.
            Trace("ReceiveAcknowledgement");
            for (int p = 0; p < _state.SendBuffer.Count; p++)
            {
                if (_state.SendBuffer[p].sent
                    && (_state.SendBuffer[p].ns != packet.nr)
                    && (DistanceBetween(packet.nr, _state.SendBuffer[p].ns, (byte)(Modulo128 ? 128 : 8)) <= MaxFrames)
                )
                { _state.SendBuffer.RemoveAt(p); p--; }
            }

            // set the current receive to the received packet's NR count
            _state.RemoteReceiveSequence = packet.nr;
        }

        private void SendRR(bool pollFinal)
        {
            Trace("SendRR");
            EmitPacket(
                new AX25Packet(
                    Addresses,
                    _state.ReceiveSequence,
                    _state.SendSequence,
                    pollFinal,
                    true,
                    FrameType.S_FRAME_RR
                )
            );
        }

        // distanceBetween(leader, follower, modulus)
        // Find the difference between 'leader' and 'follower' modulo 'modulus'.
        private int DistanceBetween(byte l, byte f, byte m)
        {
            return (l < f) ? (l + (m - f)) : (l - f);
        }

        // Send the packets in the out queue.
        //
        // If the REJ sequence number is set, we resend outstanding
        // packets and any new packets (up to maxFrames)
        //
        // Otherwise, we just send new packets (up to maxFrames)
        private void Drain(bool resent = true)
        {
            Trace("Drain, Packets in Queue: " + _state.SendBuffer.Count + ", Resend: " + resent);
            if (_state.RemoteBusy) { ClearTimer(TimerNames.T1); return; }

            byte sequenceNum = _state.SendSequence;
            if (_state.GotREJSequenceNum > 0) { sequenceNum = (byte)_state.GotREJSequenceNum; }

            bool startTimer = false;
            for (int packetIndex = 0; packetIndex < _state.SendBuffer.Count; packetIndex++)
            {
                if (DistanceBetween(sequenceNum, _state.RemoteReceiveSequence, (byte)(Modulo128 ? 128 : 8)) < MaxFrames)
                {
                    _state.SendBuffer[packetIndex].nr = _state.ReceiveSequence;
                    if (!_state.SendBuffer[packetIndex].sent)
                    {
                        _state.SendBuffer[packetIndex].ns = _state.SendSequence;
                        _state.SendBuffer[packetIndex].sent = true;
                        _state.SendSequence = (byte)((_state.SendSequence + 1) % (Modulo128 ? 128 : 8));
                    }
                    else if (!resent) { continue; } // If this packet was sent already, ignore and continue
                    startTimer = true;
                    EmitPacket(_state.SendBuffer[packetIndex]);

                    sequenceNum = (byte)((sequenceNum + 1) % (Modulo128 ? 128 : 8));
                }
            }

            if ((_state.GotREJSequenceNum < 0) && !startTimer)
            {
                SendRR(false);
                //startTimer = true; // Not sure why we would take to enable T1 here?
            }

            _state.GotREJSequenceNum = -1;
            if (startTimer) { SetTimer(TimerNames.T1); } else { ClearTimer(TimerNames.T1); }
        }

        private void Renumber()
        {
            Trace("Renumber");
            for (int p = 0; p < _state.SendBuffer.Count; p++)
            {
                _state.SendBuffer[p].ns = (byte)(p % (Modulo128 ? 128 : 8));
                _state.SendBuffer[p].nr = 0;
                _state.SendBuffer[p].sent = false;
            }
        }

        private void ConnectTimerCallback(Object sender, ElapsedEventArgs e)
        {
            Trace("Timer - Connect");
            if (_timers.ConnectAttempts >= (Retries - 1))
            {
                ClearTimer(TimerNames.Connect);
                SetConnectionState(ConnectionState.DISCONNECTED);
                return;
            }
            ConnectEx();
        }

        private void DisconnectTimerCallback(Object sender, ElapsedEventArgs e)
        {
            Trace("Timer - Disconnect");
            if (_timers.DisconnectAttempts >= (Retries - 1))
            {
                ClearTimer(TimerNames.Disconnect);
                EmitPacket(
                    new AX25Packet(
                        Addresses,
                        _state.ReceiveSequence,
                        _state.SendSequence,
                        false,
                        false,
                        FrameType.U_FRAME_DM
                    )
                );
                SetConnectionState(ConnectionState.DISCONNECTED);
                return;
            }
            Disconnect();
        }

        // Sent I-frame Acknowledgement Timer (6.7.1.3 and 4.4.5.1). This is started when a single
        // I frame is sent, or when the last I-frame in a sequence of I-frames is sent. This is
        // cleared by the reception of an acknowledgement for the I-frame (or by the link being
        // reset). If this timer expires, we follow 6.4.11 - we're supposed to send an RR/RNR with
        // the P-bit set and then restart the timer. After N attempts, we reset the link.
        private void T1TimerCallback(Object sender, ElapsedEventArgs e)
        {
            Trace("** Timer - T1 expired");
            if (_timers.T1Attempts >= Retries)
            {
                ClearTimer(TimerNames.T1);
                Disconnect(); // ConnectEx();
                return;
            }
            _timers.T1Attempts++;
            SendRR(true);
        }

        // Response Delay Timer (6.7.1.2). This is started when an I-frame is received. If
        // subsequent I-frames are received, the timer should be restarted. When it expires
        // an RR for the received data can be sent or an I-frame if there are any new packets
        // to send.
        private void T2TimerCallback(Object sender, ElapsedEventArgs e)
        {
            Trace("** Timer - T2 expired");
            ClearTimer(TimerNames.T2);
            Drain(true);
        }

        // Poll Timer (6.7.1.3 and 4.4.5.2). This is started when T1 is not running (there are
        // no outstanding I-frames). When it times out an RR or RNR should be transmitted
        // and T1 started.
        private void T3TimerCallback(Object sender, ElapsedEventArgs e)
        {
            Trace("** Timer - T3 expired");
            if (_timers.T1.Enabled) return; // Don't interfere if T1 is active
            if (_timers.T3Attempts >= Retries) // Use T3 specific retry count if you separate them
            {
                ClearTimer(TimerNames.T3);
                Disconnect(); // Or just set state to DISCONNECTED as per recommendation 4
                return;
            }
            _timers.T3Attempts++;
            //SendRR(true); // Send RR with Poll bit set to solicit response (or RNR if remote busy logic applied here)
            //SetTimer(TimerNames.T1); // Start T1 to wait for acknowledgement of this RR/RNR
        }

        public bool Connect(List<AX25Address> addresses)
        {
            Trace("Connect");
            if (CurrentState != ConnectionState.DISCONNECTED) return false;
            if ((addresses == null) || (addresses.Count < 2)) return false;
            Addresses = addresses;
            _state.SendBuffer.Clear();
            ClearTimer(TimerNames.Connect);
            ClearTimer(TimerNames.T1);
            ClearTimer(TimerNames.T2);
            ClearTimer(TimerNames.T3);
            return ConnectEx();
        }

        private bool ConnectEx()
        {
            Trace("ConnectEx");
            SetConnectionState(ConnectionState.CONNECTING);
            _state.ReceiveSequence = 0;
            _state.SendSequence = 0;
            _state.RemoteReceiveSequence = 0;
            _state.RemoteBusy = false;

            _state.GotREJSequenceNum = -1;
            ClearTimer(TimerNames.Disconnect);
            ClearTimer(TimerNames.T3);
            EmitPacket(
                new AX25Packet(
                    Addresses,
                    _state.ReceiveSequence,
                    _state.SendSequence,
                    true,
                    true,
                    Modulo128 ? FrameType.U_FRAME_SABME : FrameType.U_FRAME_SABM
                )
            );
            Renumber();
            _timers.ConnectAttempts++;
            if (_timers.ConnectAttempts >= Retries)
            {
                ClearTimer(TimerNames.Connect);
                SetConnectionState(ConnectionState.DISCONNECTED);
                return true;
            }
            if (!_timers.Connect.Enabled) { SetTimer(TimerNames.Connect); }
            return true;
        }

        public void Disconnect()
        {
            if (_state.Connection == ConnectionState.DISCONNECTED) return;
            Trace("Disconnect");
            ClearTimer(TimerNames.Connect);
            ClearTimer(TimerNames.T1);
            ClearTimer(TimerNames.T2);
            ClearTimer(TimerNames.T3);
            if (_state.Connection != ConnectionState.CONNECTED)
            {
                OnErrorEvent("ax25.Session.disconnect: Not connected.");
                SetConnectionState(ConnectionState.DISCONNECTED);
                ClearTimer(TimerNames.Disconnect);
                return;
            }
            if (_timers.DisconnectAttempts >= Retries)
            {
                ClearTimer(TimerNames.Disconnect);
                EmitPacket(
                    new AX25Packet(
                        Addresses,
                        _state.ReceiveSequence,
                        _state.SendSequence,
                        false,
                        false,
                        FrameType.U_FRAME_DM
                    )
                );
                SetConnectionState(ConnectionState.DISCONNECTED);
                return;
            }
            _timers.DisconnectAttempts++;
            SetConnectionState(ConnectionState.DISCONNECTING);
            EmitPacket(
                new AX25Packet(
                    Addresses,
                    _state.ReceiveSequence,
                    _state.SendSequence,
                    true,
                    true,
                    FrameType.U_FRAME_DISC
                )
            );
            if (!_timers.Disconnect.Enabled) { SetTimer(TimerNames.Disconnect); }
        }

        public void Send(string info)
        {
            Send(UTF8Encoding.UTF8.GetBytes(info));
        }

        // Add a new packet to our send queue.
        // If the t2 timer is not running, we can just send all the packets.
        // If the t2 timer is running, we need to wait for it to expire, then
        // we can send them.
        public void Send(byte[] info)
        {
            Trace("Send");
            if ((info == null) || (info.Length == 0)) return;
            int packetLength = PacketLength;
            for (int i = 0; i < info.Length; i += packetLength)
            {
                int length = Math.Min(packetLength, info.Length - i);
                byte[] packetInfo = new byte[length];
                Array.Copy(info, i, packetInfo, 0, length);

                _state.SendBuffer.Add(
                    new AX25Packet(Addresses, 0, 0, false, true, FrameType.I_FRAME, packetInfo)
                );
            }

            // Check if timer is not enabled using Timer.Enabled property
            if (!_timers.T2.Enabled) { Drain(false); }
        }

        public bool Receive(AX25Packet packet)
        {
            if ((packet == null) || (packet.addresses.Count < 2)) return false;
            Trace("Receive " + packet.type.ToString());

            AX25Packet response = new AX25Packet(
                    Addresses,
                    _state.ReceiveSequence,
                    _state.SendSequence,
                    false,
                    !packet.command, // Command is flipped for response
                    0
                );

            ConnectionState newState = this.CurrentState;

            // Check if this is for the right station for this session
            // Another station may be trying to initiate a connection while we are busy
            if ((Addresses != null) && (packet.addresses[1].CallSignWithId != Addresses[0].CallSignWithId))
            {
                Trace("Got packet from wrong station: " + packet.addresses[1].CallSignWithId);
                // TODO: Notify we are busy (?)
                response.addresses = new List<AX25Address>();
                response.addresses.Add(AX25Address.GetAddress(packet.addresses[1].ToString()));
                response.addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));
                response.type = FrameType.U_FRAME_DISC;
                response.command = true;
                response.pollFinal = true;
                return false;
            }

            // If this is not a connection frame and we are not connected, respond with a disconnect
            if ((Addresses == null) && (packet.type != FrameType.U_FRAME_SABM) && (packet.type != FrameType.U_FRAME_SABME))
            {
                response.addresses = new List<AX25Address>();
                response.addresses.Add(AX25Address.GetAddress(packet.addresses[1].ToString()));
                response.addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));
                response.type = FrameType.U_FRAME_DISC;
                response.command = true;
                response.pollFinal = true;
                return false;
            }

            switch (packet.type)
            {
                // Set Asynchronous Balanced Mode, aka Connect in 8-frame mode (4.3.3.1)
                // Connect Extended (128-frame mode) (4.3.3.2)
                case FrameType.U_FRAME_SABM:
                case FrameType.U_FRAME_SABME:
                    if (CurrentState != ConnectionState.DISCONNECTED) return false;
                    Addresses = new List<AX25Address>();
                    Addresses.Add(AX25Address.GetAddress(packet.addresses[1].ToString()));
                    Addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));
                    response.addresses = Addresses;
                    _state.ReceiveSequence = 0;
                    _state.SendSequence = 0;
                    _state.RemoteReceiveSequence = 0;
                    _state.GotREJSequenceNum = -1;
                    _state.RemoteBusy = false;
                    _state.SendBuffer.Clear();
                    ClearTimer(TimerNames.Connect);
                    ClearTimer(TimerNames.Disconnect);
                    ClearTimer(TimerNames.T1);
                    ClearTimer(TimerNames.T2);
                    ClearTimer(TimerNames.T3);
                    Modulo128 = (packet.type == FrameType.U_FRAME_SABME);
                    Renumber();
                    response.type = FrameType.U_FRAME_UA;
                    if (packet.command && packet.pollFinal) { response.pollFinal = true; }
                    newState = ConnectionState.CONNECTED;
                    break;

                // Disconnect (4.3.3.3). This is fairly straightforward.
                // If we're connected, reset our state, send a disconnect message,
                // and let the upper layer know the remote disconnected.
                // If we're not connected, reply with a WTF? (DM) message.
                case FrameType.U_FRAME_DISC:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        _state.ReceiveSequence = 0;
                        _state.SendSequence = 0;
                        _state.RemoteReceiveSequence = 0;
                        _state.GotREJSequenceNum = -1;
                        _state.RemoteBusy = false;
                        ClearTimer(TimerNames.Connect);
                        ClearTimer(TimerNames.Disconnect);
                        ClearTimer(TimerNames.T1);
                        ClearTimer(TimerNames.T2);
                        ClearTimer(TimerNames.T3);
                        response.type = FrameType.U_FRAME_UA;
                        EmitPacket(response);
                        SetConnectionState(ConnectionState.DISCONNECTED);
                    }
                    else
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                        EmitPacket(response);
                    }
                    return true; // Early return after sending response.

                // Unnumbered Acknowledge (4.3.3.4). We get this in response to
                // SABM(E) packets and DISC packets. It's not clear what's supposed
                // to happen if we get this when we're in another state. Right now
                // if we're connected, we ignore it.
                case FrameType.U_FRAME_UA:
                    if (_state.Connection == ConnectionState.CONNECTING)
                    {
                        ClearTimer(TimerNames.Connect);
                        ClearTimer(TimerNames.T2);
                        SetTimer(TimerNames.T3);
                        response = null;
                        newState = ConnectionState.CONNECTED;
                    }
                    else if (_state.Connection == ConnectionState.DISCONNECTING)
                    {
                        ClearTimer(TimerNames.Disconnect);
                        ClearTimer(TimerNames.T2);
                        ClearTimer(TimerNames.T3);
                        response = null;
                        newState = ConnectionState.DISCONNECTED;
                    }
                    else if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        response = null;
                    }
                    else
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = false;
                    }
                    break;

                // Disconnected Mode (4.3.3.5).
                // If we're connected and we get this, the remote hasn't gone through the whole connection
                // process. It probably missed part of the connection frames or something. So...start all
                // over and retry the connecection.
                // If we think we're in the middle of setting up a connection and get this, something got
                // out of sync with the remote and it's confused - maybe it didn't hear a disconnect we
                // we sent, or it's replying to a SABM saying it's too busy. If we're trying to disconnect
                // and we get this, everything's cool. Either way, we transition to disconnected mode.
                // If we get this when we're unconnected, we send a WTF? (DM) message as a reply.
                case FrameType.U_FRAME_DM:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        ConnectEx();
                        response = null;
                    }
                    else if (_state.Connection == ConnectionState.CONNECTING || _state.Connection == ConnectionState.DISCONNECTING)
                    {
                        _state.ReceiveSequence = 0;
                        _state.SendSequence = 0;
                        _state.RemoteReceiveSequence = 0;
                        _state.GotREJSequenceNum = -1;
                        _state.RemoteBusy = false;
                        _state.SendBuffer.Clear();
                        ClearTimer(TimerNames.Connect);
                        ClearTimer(TimerNames.Disconnect);
                        ClearTimer(TimerNames.T1);
                        ClearTimer(TimerNames.T2);
                        ClearTimer(TimerNames.T3);
                        response = null;
                        if (_state.Connection == ConnectionState.CONNECTING)
                        {
                            Modulo128 = false;
                            ConnectEx();
                        }
                        else
                        {
                            newState = ConnectionState.DISCONNECTED;
                        }
                    }
                    else
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                // Unnumbered Information (4.3.3.6). We send this to the upper layer as an out-of-band UI packet, but
                // if the pollfinal flag is set internally we fabricate a response for it.
                // XXX handle "uidata" at upper layer - make note of this in the docs
                case FrameType.U_FRAME_UI:
                    if ((packet.data != null) && (packet.data.Length != 0)) { OnUiDataReceivedEvent(packet.data); }
                    if (packet.pollFinal)
                    {
                        response.pollFinal = false;
                        response.type = (_state.Connection == ConnectionState.CONNECTED) ? FrameType.S_FRAME_RR : FrameType.U_FRAME_DM;
                    }
                    else
                    {
                        response = null;
                    }
                    break;

                // Exchange Identification (4.3.3.7). Placeholder pending XID implementation
                case FrameType.U_FRAME_XID:
                    response.type = FrameType.U_FRAME_DM;
                    break;

                // Test (4.3.3.8). Send a test response right away.
                case FrameType.U_FRAME_TEST:
                    response.type = FrameType.U_FRAME_TEST;
                    if (packet.data.Length > 0) { response.data = packet.data; }
                    break;

                // Frame Recovery message. (4.3.3.9). This was removed from the AX25 standard, and if we
                // get one we're just supposed to reset the link.
                case FrameType.U_FRAME_FRMR:
                    if (_state.Connection == ConnectionState.CONNECTING && Modulo128)
                    {
                        Modulo128 = false;
                        ConnectEx();
                        response = null;
                    }
                    else if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        ConnectEx();
                        response = null;
                    }
                    else
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                // Receive Ready (4.3.2.1)
                // Update our counts and handle any connection status changes (pollFinal).
                // Get ready to do a drain by starting the t2 timer. If we get more RR's
                // or IFRAMES, we'll have to reset the t2 timer. 
                case FrameType.S_FRAME_RR:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        _state.RemoteBusy = false;
                        if (packet.command && packet.pollFinal)
                        {
                            response.type = FrameType.S_FRAME_RR;
                            response.pollFinal = true;
                        }
                        else
                        {
                            response = null;
                        }
                        ReceiveAcknowledgement(packet);
                        SetTimer(TimerNames.T2);
                    }
                    else if (packet.command)
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                // Receive Not Ready (4.3.2.2)
                // Just update our counts and handle any connection status changes (pollFinal).
                // Don't send a reply or any data, and clear the t2 timer in case we're about
                // to send some. (Subsequent received packets may restart the t2 timer.)
                // 
                // XXX (Not sure on this) We also need to restart the T1 timer because we
                // probably got this as a reject of an I-frame.
                case FrameType.S_FRAME_RNR:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        _state.RemoteBusy = true;
                        ReceiveAcknowledgement(packet);
                        if (packet.command && packet.pollFinal)
                        {
                            response.type = FrameType.S_FRAME_RR;
                            response.pollFinal = true;
                        }
                        else
                        {
                            response = null;
                        }
                        ClearTimer(TimerNames.T2);
                        SetTimer(TimerNames.T1);
                    }
                    else if (packet.command)
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                // Reject (4.3.2.3). The remote rejected a single connected frame, which means
                // it got something out of order.
                // Leave T1 alone, as this will trigger a resend
                // Set T2, in case we get more data from the remote soon.
                case FrameType.S_FRAME_REJ:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        _state.RemoteBusy = false;
                        if (packet.command && packet.pollFinal)
                        {
                            response.type = FrameType.S_FRAME_RR;
                            response.pollFinal = true;
                        }
                        else
                        {
                            response = null;
                        }
                        ReceiveAcknowledgement(packet);
                        _state.GotREJSequenceNum = packet.nr;
                        SetTimer(TimerNames.T2);
                    }
                    else
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                // Information (4.3.1). This is our data packet.
                case FrameType.I_FRAME:
                    if (_state.Connection == ConnectionState.CONNECTED)
                    {
                        if (packet.pollFinal) { response.pollFinal = true; }
                        if (packet.ns == _state.ReceiveSequence)
                        {
                            _state.SentREJ = false;
                            _state.ReceiveSequence = (byte)((_state.ReceiveSequence + 1) % (Modulo128 ? 128 : 8));
                            if ((packet.data != null) && (packet.data.Length != 0)) { OnDataReceivedEvent(packet.data); }
                            response = null;
                        }
                        else if (_state.SentREJ)
                        {
                            response = null;
                        }
                        else if (!_state.SentREJ)
                        {
                            response.type = FrameType.S_FRAME_REJ;
                            _state.SentREJ = true;
                        }
                        ReceiveAcknowledgement(packet);

                        if ((response == null) || !response.pollFinal)
                        {
                            response = null;
                            SetTimer(TimerNames.T2);
                        }
                    }
                    else if (packet.command)
                    {
                        response.type = FrameType.U_FRAME_DM;
                        response.pollFinal = true;
                    }
                    break;

                default:
                    response = null;
                    break;
            }

            if (response != null)
            {
                if (response.addresses == null)
                {
                    response.addresses = new List<AX25Address>();
                    response.addresses.Add(AX25Address.GetAddress(packet.addresses[1].ToString()));
                    response.addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));
                }
                EmitPacket(response);
            }

            if (newState != this.CurrentState) { SetConnectionState(newState); }

            return true;
        }

    }
}