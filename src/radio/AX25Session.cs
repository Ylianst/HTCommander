/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Timers;
using System.Collections.Generic;
using static HTCommander.AX25Packet;
using System.Text;
using System.Linq;

namespace HTCommander
{
    /// <summary>
    /// Implements the AX.25 data link layer protocol for connected-mode communication.
    /// Uses the DataBroker for sending and receiving packets through a specified radio device.
    /// Supports both standard (modulo-8) and extended (modulo-128) sequence numbering.
    /// </summary>
    public class AX25Session : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly int _radioDeviceId;
        private bool _disposed = false;
        
        /// <summary>
        /// Custom session state dictionary for storing application-specific data.
        /// This is cleared when the session disconnects.
        /// </summary>
        public Dictionary<string, object> sessionState = new Dictionary<string, object>();

        /// <summary>Delegate for connection state change events.</summary>
        public delegate void StateChangedHandler(AX25Session sender, ConnectionState state);
        
        /// <summary>Raised when the connection state changes.</summary>
        public event StateChangedHandler StateChanged;

        /// <summary>Delegate for data received events.</summary>
        public delegate void DataReceivedHandler(AX25Session sender, byte[] data);
        
        /// <summary>Raised when I-frame data is received from the remote station.</summary>
        public event DataReceivedHandler DataReceivedEvent;
        
        /// <summary>Raised when UI-frame data is received (connectionless data).</summary>
        public event DataReceivedHandler UiDataReceivedEvent;

        /// <summary>Delegate for error events.</summary>
        public delegate void ErrorHandler(AX25Session sender, string error);
        
        /// <summary>Raised when an error occurs in the session.</summary>
        public event ErrorHandler ErrorEvent;

        /// <summary>
        /// Optional callsign override. If set, uses this callsign instead of the one from DataBroker.
        /// </summary>
        public string CallSignOverride = null;
        
        /// <summary>
        /// Optional station ID override. If >= 0, uses this ID instead of the one from DataBroker.
        /// </summary>
        public int StationIdOverride = -1;

        /// <summary>
        /// Gets the callsign to use for this session. Uses override if set, otherwise gets from DataBroker.
        /// </summary>
        public string SessionCallsign
        {
            get
            {
                if (CallSignOverride != null) { return CallSignOverride; }
                return DataBroker.GetValue<string>(0, "CallSign", "NOCALL");
            }
        }

        /// <summary>
        /// Gets the station ID to use for this session. Uses override if set, otherwise gets from DataBroker.
        /// </summary>
        public int SessionStationId
        {
            get
            {
                if (StationIdOverride >= 0) { return StationIdOverride; }
                return DataBroker.GetValue<int>(0, "StationId", 0);
            }
        }

        /// <summary>
        /// Gets the radio device ID associated with this session.
        /// </summary>
        public int RadioDeviceId => _radioDeviceId;

        private void OnErrorEvent(string error) { Trace("ERROR: " + error); ErrorEvent?.Invoke(this, error); }
        private void OnStateChangedEvent(ConnectionState state) { StateChanged?.Invoke(this, state); }
        private void OnUiDataReceivedEvent(byte[] data) { UiDataReceivedEvent?.Invoke(this, data); }
        private void OnDataReceivedEvent(byte[] data) { DataReceivedEvent?.Invoke(this, data); }

        /// <summary>
        /// Connection state of the AX.25 session.
        /// </summary>
        public enum ConnectionState
        {
            DISCONNECTED = 1,
            CONNECTED = 2,
            CONNECTING = 3,
            DISCONNECTING = 4
        }

        private enum TimerNames { Connect, Disconnect, T1, T2, T3 }

        /// <summary>Maximum number of outstanding I-frames (window size).</summary>
        public int MaxFrames = 4;
        
        /// <summary>Maximum size of data payload in each I-frame.</summary>
        public int PacketLength = 256;
        
        /// <summary>Number of retries before giving up on a connection.</summary>
        public int Retries = 3;
        
        /// <summary>Baud rate used for timeout calculations.</summary>
        public int HBaud = 1200;
        
        /// <summary>Use modulo-128 mode for extended sequence numbers (up to 127 outstanding frames).</summary>
        public bool Modulo128 = false;
        
        /// <summary>Enable trace logging for debugging.</summary>
        public bool Tracing = true;

        private void Trace(string msg)
        {
            if (Tracing && _broker != null)
            {
                _broker.LogInfo($"[AX25Session/{_radioDeviceId}] {msg}");
            }
        }

        private void SetConnectionState(ConnectionState state)
        {
            if (state != _state.Connection)
            {
                _state.Connection = state;
                OnStateChangedEvent(state);
                if (state == ConnectionState.DISCONNECTED) { 
                    _state.SendBuffer.Clear(); 
                    _state.ReceiveBuffer.Clear(); 
                    Addresses = null; 
                    sessionState.Clear(); 
                }
            }
        }

        /// <summary>
        /// Internal state for the AX.25 session protocol.
        /// </summary>
        private class State
        {
            /// <summary>Current connection state.</summary>
            public ConnectionState Connection { get; set; } = ConnectionState.DISCONNECTED;
            
            /// <summary>Next expected receive sequence number (V(R)).</summary>
            public byte ReceiveSequence { get; set; } = 0;
            
            /// <summary>Next send sequence number (V(S)).</summary>
            public byte SendSequence { get; set; } = 0;
            
            /// <summary>Last acknowledged sequence number from remote (N(R)).</summary>
            public byte RemoteReceiveSequence { get; set; } = 0;
            
            /// <summary>Indicates if the remote station is busy (RNR received).</summary>
            public bool RemoteBusy { get; set; } = false;
            
            /// <summary>Indicates if we've sent a REJ frame.</summary>
            public bool SentREJ { get; set; } = false;
            
            /// <summary>Indicates if we've sent a SREJ frame.</summary>
            public bool SentSREJ { get; set; } = false;
            
            /// <summary>Sequence number from received REJ frame, -1 if none.</summary>
            public int GotREJSequenceNum { get; set; } = -1;
            
            /// <summary>Sequence number from received SREJ frame, -1 if none.</summary>
            public int GotSREJSequenceNum { get; set; } = -1;
            
            /// <summary>Buffer of I-frames waiting to be sent or awaiting acknowledgment.</summary>
            public List<AX25Packet> SendBuffer { get; set; } = new List<AX25Packet>();
            
            /// <summary>Buffer for out-of-order received I-frames, keyed by sequence number.</summary>
            public Dictionary<byte, AX25Packet> ReceiveBuffer { get; set; } = new Dictionary<byte, AX25Packet>();
        }
        private readonly State _state = new State();

        /// <summary>
        /// Internal timers for the AX.25 session protocol.
        /// </summary>
        private class Timers
        {
            /// <summary>Timer for connection establishment retries.</summary>
            public Timer Connect { get; set; } = new Timer();
            
            /// <summary>Timer for disconnection retries.</summary>
            public Timer Disconnect { get; set; } = new Timer();
            
            /// <summary>T1: Outstanding I-frame acknowledgment timer.</summary>
            public Timer T1 { get; set; } = new Timer();
            
            /// <summary>T2: Response delay timer for received I-frames.</summary>
            public Timer T2 { get; set; } = new Timer();
            
            /// <summary>T3: Idle poll timer when no outstanding I-frames.</summary>
            public Timer T3 { get; set; } = new Timer();
            
            public int ConnectAttempts { get; set; } = 0;
            public int DisconnectAttempts { get; set; } = 0;
            public int T1Attempts { get; set; } = 0;
            public int T3Attempts { get; set; } = 0;
        }
        private readonly Timers _timers = new Timers();

        /// <summary>
        /// Gets the current connection state of the session.
        /// </summary>
        public ConnectionState CurrentState => _state.Connection;

        /// <summary>
        /// Gets or sets the list of addresses for this session (destination, source, and optional digipeaters).
        /// </summary>
        public List<AX25Address> Addresses = null;

        /// <summary>
        /// Gets the number of packets in the send buffer awaiting transmission or acknowledgment.
        /// </summary>
        public int SendBufferLength => _state.SendBuffer.Count;
        
        /// <summary>
        /// Gets the number of out-of-order packets in the receive buffer.
        /// </summary>
        public int ReceiveBufferLength => _state.ReceiveBuffer.Count;

        /// <summary>
        /// Creates a new AX25 session using the DataBroker for communication.
        /// </summary>
        /// <param name="radioDeviceId">The device ID of the radio to use for transmitting/receiving packets.</param>
        public AX25Session(int radioDeviceId)
        {
            _radioDeviceId = radioDeviceId;
            _broker = new DataBrokerClient();

            // Subscribe to UniqueDataFrame events to receive incoming packets
            _broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);

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
            
            _broker.LogInfo($"[AX25Session] Session created for radio device {radioDeviceId}");
        }

        /// <summary>
        /// Handles incoming UniqueDataFrame events and processes packets for this session.
        /// </summary>
        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (!(data is TncDataFragment frame)) return;
            
            // Only process frames from our radio device
            if (frame.RadioDeviceId != _radioDeviceId) return;
            
            // Parse the AX.25 packet from the frame data
            AX25Packet packet = AX25Packet.DecodeAX25Packet(frame);
            if (packet == null) return;
            
            // Process the received packet
            Receive(packet);
        }

        /// <summary>
        /// Transmits an AX.25 packet via the DataBroker to the associated radio.
        /// </summary>
        private void EmitPacket(AX25Packet packet)
        {
            Trace("EmitPacket");
            
            // Get the lock state to determine which channel to use
            var lockState = DataBroker.GetValue<RadioLockState>(_radioDeviceId, "LockState", null);
            int channelId = lockState?.ChannelId ?? -1;
            int regionId = lockState?.RegionId ?? -1;
            
            var txData = new TransmitDataFrameData
            {
                Packet = packet,
                ChannelId = channelId,
                RegionId = regionId
            };
            
            DataBroker.Dispatch(_radioDeviceId, "TransmitDataFrame", txData, store: false);
        }

        /// <summary>
        /// Disposes of resources used by this session.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes of resources used by this session.
        /// </summary>
        protected virtual void Dispose(bool disposing)
        {
            if (_disposed) return;
            
            if (disposing)
            {
                _broker?.LogInfo($"[AX25Session] Session disposing for radio device {_radioDeviceId}");
                
                // Stop all timers
                ClearTimer(TimerNames.Connect);
                ClearTimer(TimerNames.Disconnect);
                ClearTimer(TimerNames.T1);
                ClearTimer(TimerNames.T2);
                ClearTimer(TimerNames.T3);
                
                // Dispose timers
                _timers.Connect?.Dispose();
                _timers.Disconnect?.Dispose();
                _timers.T1?.Dispose();
                _timers.T2?.Dispose();
                _timers.T3?.Dispose();
                
                // Clear state
                _state.SendBuffer.Clear();
                _state.ReceiveBuffer.Clear();
                Addresses = null;
                sessionState.Clear();
                
                // Unsubscribe from broker and dispose
                _broker?.Dispose();
            }
            
            _disposed = true;
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

        // Check if we have data to send and can piggyback acknowledgment
        private bool ShouldPiggybackAck()
        {
            // If we have unsent packets in the send buffer, we can piggyback the ack
            return _state.SendBuffer.Count > 0 && _state.SendBuffer.Any(p => !p.sent);
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
                int dst = DistanceBetween(sequenceNum, _state.RemoteReceiveSequence, (byte)(Modulo128 ? 128 : 8));
                if (_state.SendBuffer[packetIndex].sent || (dst < MaxFrames))
                {
                    _state.SendBuffer[packetIndex].nr = _state.ReceiveSequence;
                    if (!_state.SendBuffer[packetIndex].sent)
                    {
                        _state.SendBuffer[packetIndex].ns = _state.SendSequence;
                        _state.SendBuffer[packetIndex].sent = true;
                        _state.SendSequence = (byte)((_state.SendSequence + 1) % (Modulo128 ? 128 : 8));
                        sequenceNum = (byte)((sequenceNum + 1) % (Modulo128 ? 128 : 8));
                    }
                    else if (!resent) { continue; } // If this packet was sent already, ignore and continue
                    startTimer = true;
                    EmitPacket(_state.SendBuffer[packetIndex]);
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

        /// <summary>
        /// Initiates a connection to a remote station.
        /// </summary>
        /// <param name="addresses">List of addresses: destination (index 0), source (index 1), and optional digipeaters.</param>
        /// <returns>True if the connection attempt was started, false if already connected or invalid addresses.</returns>
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

        /// <summary>
        /// Internal method to send SABM/SABME and start connection timer.
        /// </summary>
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

        /// <summary>
        /// Initiates a disconnection from the remote station.
        /// </summary>
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

        /// <summary>
        /// Sends data over the connection as a UTF-8 encoded string.
        /// </summary>
        /// <param name="info">The string data to send.</param>
        public void Send(string info)
        {
            Send(UTF8Encoding.UTF8.GetBytes(info));
        }

        /// <summary>
        /// Sends data over the connection. The data is split into I-frames based on PacketLength.
        /// If the T2 timer is not running, packets are sent immediately.
        /// Otherwise, they are queued until the timer expires.
        /// </summary>
        /// <param name="info">The byte data to send.</param>
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

        /// <summary>
        /// Processes a received AX.25 packet. This is called internally when UniqueDataFrame events
        /// are received, but can also be called directly to process packets.
        /// </summary>
        /// <param name="packet">The received AX.25 packet to process.</param>
        /// <returns>True if the packet was processed, false if invalid.</returns>
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
                Trace("Got packet from wrong station: " + packet.addresses[1].CallSignWithId + ", expected: " + Addresses[0].CallSignWithId);
                // Simply ignore packets from other stations - don't respond
                // Responding with DM could interfere with other sessions on the same frequency
                return false;
            }

            // If we are not connected and this is not a connection request, respond with DM (Disconnected Mode)
            if ((Addresses == null) && (packet.type != FrameType.U_FRAME_SABM) && (packet.type != FrameType.U_FRAME_SABME))
            {
                response.addresses = new List<AX25Address>();
                response.addresses.Add(AX25Address.GetAddress(packet.addresses[1].ToString()));
                response.addresses.Add(AX25Address.GetAddress(SessionCallsign, SessionStationId));
                response.command = false;
                response.pollFinal = true;

                // If this is a disconnect frame and we are not connected, respond with UA confirmation
                // Otherwise respond with DM to indicate we're not connected
                if (packet.type == FrameType.U_FRAME_DISC) { response.type = FrameType.U_FRAME_UA; } else { response.type = FrameType.U_FRAME_DM; }
                EmitPacket(response);
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
                    Addresses.Add(AX25Address.GetAddress(SessionCallsign, SessionStationId));
                    response.addresses = Addresses;
                    _state.ReceiveSequence = 0;
                    _state.SendSequence = 0;
                    _state.RemoteReceiveSequence = 0;
                    _state.GotREJSequenceNum = -1;
                    _state.RemoteBusy = false;
                    _state.SendBuffer.Clear();
                    _state.ReceiveBuffer.Clear();
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
                        _state.ReceiveBuffer.Clear();
                        ClearTimer(TimerNames.Connect);
                        ClearTimer(TimerNames.Disconnect);
                        ClearTimer(TimerNames.T1);
                        ClearTimer(TimerNames.T2);
                        ClearTimer(TimerNames.T3);
                        response.type = FrameType.U_FRAME_UA;
                        response.pollFinal = true; // Look like this need to be here.
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
                        _state.ReceiveBuffer.Clear();
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
                        
                        // Check if we can piggyback instead of setting T2 timer
                        if (ShouldPiggybackAck() && (response == null))
                        {
                            Trace("Piggybacking ack on outgoing data after RR");
                            if (!_timers.T2.Enabled) { Drain(false); }
                        }
                        else
                        {
                            SetTimer(TimerNames.T2);
                        }
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
                        
                        // Check if we can piggyback instead of setting T2 timer
                        if (ShouldPiggybackAck() && (response == null))
                        {
                            Trace("Piggybacking ack on outgoing data after REJ");
                            if (!_timers.T2.Enabled) { Drain(false); }
                        }
                        else
                        {
                            SetTimer(TimerNames.T2);
                        }
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
                            // In-sequence packet - process immediately
                            _state.SentREJ = false;
                            _state.ReceiveSequence = (byte)((_state.ReceiveSequence + 1) % (Modulo128 ? 128 : 8));
                            if ((packet.data != null) && (packet.data.Length != 0)) { OnDataReceivedEvent(packet.data); }
                            
                            // Process any buffered packets that are now in sequence
                            ProcessBufferedPackets();
                            
                            // Check if we can piggyback acknowledgment on outgoing data
                            if (ShouldPiggybackAck() && (response == null || !response.pollFinal))
                            {
                                // We have data to send, let the outgoing I-frames carry the ack
                                Trace("Piggybacking ack on outgoing data instead of sending RR");
                                response = null;
                                // Don't set T2 timer, let Drain handle sending data with piggybacked acks
                                if (!_timers.T2.Enabled) { Drain(false); }
                            }
                            else
                            {
                                response = null;
                                SetTimer(TimerNames.T2);
                            }
                        }
                        else if (IsWithinReceiveWindow(packet.ns) && !_state.ReceiveBuffer.ContainsKey(packet.ns))
                        {
                            // Out-of-order packet within receive window - buffer it
                            Trace("Buffering out-of-order packet NS=" + packet.ns + ", expected=" + _state.ReceiveSequence);
                            _state.ReceiveBuffer[packet.ns] = packet;
                            
                            // Send REJ only if we haven't already sent one
                            if (!_state.SentREJ)
                            {
                                response.type = FrameType.S_FRAME_REJ;
                                _state.SentREJ = true;
                            }
                            else
                            {
                                response = null;
                            }
                        }
                        else if (_state.SentREJ)
                        {
                            // Already sent REJ, ignore duplicate or old packets
                            response = null;
                        }
                        else if (!_state.SentREJ)
                        {
                            // Out-of-order packet - send REJ
                            response.type = FrameType.S_FRAME_REJ;
                            _state.SentREJ = true;
                        }
                        
                        ReceiveAcknowledgement(packet);

                        // Only set T2 timer if we're not piggybacking and don't need immediate response
                        if ((response == null) && !ShouldPiggybackAck())
                        {
                            SetTimer(TimerNames.T2);
                        }
                        else if (response != null && response.pollFinal)
                        {
                            // Immediate response required due to poll/final bit
                            // Don't set T2 timer in this case
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
                    response.addresses.Add(AX25Address.GetAddress(SessionCallsign, SessionStationId));
                }
                EmitPacket(response);
            }

            if (newState != this.CurrentState)
            {
                if ((this.CurrentState == ConnectionState.DISCONNECTING) && (newState == ConnectionState.CONNECTED)) { return true; }
                SetConnectionState(newState);
            }

            return true;
        }

        // Process any buffered packets that can now be delivered in sequence
        private void ProcessBufferedPackets()
        {
            byte modulus = (byte)(Modulo128 ? 128 : 8);
            
            while (_state.ReceiveBuffer.ContainsKey(_state.ReceiveSequence))
            {
                AX25Packet bufferedPacket = _state.ReceiveBuffer[_state.ReceiveSequence];
                _state.ReceiveBuffer.Remove(_state.ReceiveSequence);
                
                Trace("Processing buffered packet NS=" + bufferedPacket.ns);
                
                // Deliver the packet data
                if ((bufferedPacket.data != null) && (bufferedPacket.data.Length != 0))
                {
                    OnDataReceivedEvent(bufferedPacket.data);
                }
                
                // Advance the receive sequence
                _state.ReceiveSequence = (byte)((_state.ReceiveSequence + 1) % modulus);
            }
        }

        // Check if a packet sequence number is within the receive window
        private bool IsWithinReceiveWindow(byte ns)
        {
            byte modulus = (byte)(Modulo128 ? 128 : 8);
            int windowSize = MaxFrames;
            
            // Calculate the distance from current receive sequence
            int distance = DistanceBetween(ns, _state.ReceiveSequence, modulus);
            
            // Accept packets within the receive window
            return distance < windowSize;
        }
    }
}
