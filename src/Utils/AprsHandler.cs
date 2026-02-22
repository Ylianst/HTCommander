/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Collections.Generic;
using aprsparser;

namespace HTCommander
{
    /// <summary>
    /// A data handler that processes incoming APRS packets from the APRS channel.
    /// It subscribes to UniqueDataFrame events, decodes AX.25 and APRS frames,
    /// validates authentication codes when present, and stores the last 1000 APRS frames.
    /// On startup, it loads previous APRS packets from the PacketStore.
    /// </summary>
    public class AprsHandler : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly object _lock = new object();
        private bool _disposed = false;
        private bool _storeReady = false;

        /// <summary>
        /// Maximum number of APRS frames to keep in history.
        /// </summary>
        private const int MaxFrameHistory = 1000;

        /// <summary>
        /// List of recently received APRS packets, limited to MaxFrameHistory entries.
        /// </summary>
        private readonly List<AprsPacket> _aprsFrames = new List<AprsPacket>();

        /// <summary>
        /// List of stations used for authentication password lookup.
        /// </summary>
        private List<StationInfoClass> _stations = new List<StationInfoClass>();

        /// <summary>
        /// The local station callsign with station ID (e.g., "K7VZT-5").
        /// </summary>
        private string _localCallsignWithId;

        /// <summary>
        /// Gets whether the APRS store is ready (historical packets have been loaded).
        /// </summary>
        public bool IsStoreReady => _storeReady;

        /// <summary>
        /// Creates a new AprsHandler that listens for UniqueDataFrame events and processes APRS packets.
        /// </summary>
        public AprsHandler()
        {
            _broker = new DataBrokerClient();

            // Subscribe to UniqueDataFrame events from all devices
            _broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);

            // Subscribe to PacketStoreReady to know when we can request historical packets
            _broker.Subscribe(1, "PacketStoreReady", OnPacketStoreReady);

            // Subscribe to PacketList to receive the list of historical packets
            _broker.Subscribe(1, "PacketList", OnPacketList);

            // Subscribe to SendAprsMessage events from the UI
            _broker.Subscribe(1, "SendAprsMessage", OnSendAprsMessage);

            // Subscribe to RequestAprsPackets to provide current packet list on-demand
            _broker.Subscribe(1, "RequestAprsPackets", OnRequestAprsPackets);

            // Subscribe to Stations updates from device 0
            _broker.Subscribe(0, "Stations", OnStationsUpdate);

            // Get the initial stations list from the DataBroker
            var initialStations = _broker.GetValue<List<StationInfoClass>>(0, "Stations", null);
            if (initialStations != null)
            {
                lock (_lock)
                {
                    _stations = initialStations;
                }
            }

            // Subscribe to CallSign and StationId changes from device 0
            _broker.Subscribe(0, new[] { "CallSign", "StationId" }, OnCallsignOrStationIdChanged);

            // Initialize the local callsign with station ID
            UpdateLocalCallsignWithId();

            // Check if PacketStore is already ready (in case we're created after PacketStore)
            if (_broker.HasValue(1, "PacketStoreReady"))
            {
                // Request the packet list immediately
                _broker.Dispatch(1, "RequestPacketList", null, store: false);
            }

            // Load the next APRS message ID from the Data Broker (persisted across restarts)
            nextAprsMessageId = _broker.GetValue<int>(0, "NextAprsMessageId", 1);
            if (nextAprsMessageId < 1 || nextAprsMessageId > 999) { nextAprsMessageId = 1; }
        }

        /// <summary>
        /// Updates the local callsign with station ID from the Data Broker values.
        /// </summary>
        private void UpdateLocalCallsignWithId()
        {
            string callsign = _broker.GetValue<string>(0, "CallSign", "");
            int stationIdInt = _broker.GetValue<int>(0, "StationId", 0);
            
            lock (_lock)
            {
                if (string.IsNullOrEmpty(callsign))
                {
                    _localCallsignWithId = null;
                }
                else if (stationIdInt > 0)
                {
                    _localCallsignWithId = callsign + "-" + stationIdInt.ToString();
                }
                else
                {
                    _localCallsignWithId = callsign;
                }
            }
        }

        /// <summary>
        /// Handles CallSign or StationId changes from the DataBroker.
        /// </summary>
        private void OnCallsignOrStationIdChanged(int deviceId, string name, object data)
        {
            if (_disposed) return;
            UpdateLocalCallsignWithId();
        }

        /// <summary>
        /// Handles Stations updates from the DataBroker.
        /// </summary>
        private void OnStationsUpdate(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is List<StationInfoClass> stations)) return;

            lock (_lock)
            {
                _stations = stations;
            }
        }

        private int nextAprsMessageId = 1;

        /// <summary>
        /// Gets the next APRS message ID, cycling from 1 to 999.
        /// Persists the value to the Data Broker for recovery across restarts.
        /// </summary>
        /// <returns>The next message ID.</returns>
        private int GetNextAprsMessageId()
        {
            int msgId = nextAprsMessageId++;
            if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
            _broker.Dispatch(0, "NextAprsMessageId", nextAprsMessageId, store: true);
            return msgId;
        }

        /// <summary>
        /// Handles SendAprsMessage events from the UI to transmit APRS messages.
        /// </summary>
        private void OnSendAprsMessage(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is AprsSendMessageData messageData)) return;

            // Get our callsign and station ID from the DataBroker
            string callsign = _broker.GetValue<string>(0, "CallSign", "");
            int stationIdInt = _broker.GetValue<int>(0, "StationId", 0);
            string stationId = stationIdInt > 0 ? stationIdInt.ToString() : "";

            if (string.IsNullOrEmpty(callsign))
            {
                _broker.LogError("Cannot send APRS message: Callsign not configured");
                return;
            }

            // Build source address with station ID
            string srcCallsignWithId = string.IsNullOrEmpty(stationId) ? callsign : callsign + "-" + stationId;

            // Build the APRS message content with optional authentication
            int msgId = GetNextAprsMessageId();
            DateTime now = DateTime.Now;
            bool authApplied;
            string aprsMessageContent = AddAprsAuth(srcCallsignWithId, messageData.Destination, messageData.Message, msgId, now, out authApplied);

            // Build the address list for the AX.25 frame
            List<AX25Address> addresses = new List<AX25Address>();

            // Destination address (from route if available, otherwise use APRS default)
            string destAddress = "APRS";
            if (messageData.Route != null && messageData.Route.Length >= 2)
            {
                destAddress = messageData.Route[1]; // Route format: [RouteName, Dest, Path1, Path2, ...]
            }
            addresses.Add(AX25Address.GetAddress(destAddress));

            // Source address (our callsign with station ID)
            addresses.Add(AX25Address.GetAddress(srcCallsignWithId));

            // Add digipeater path from route if available
            if (messageData.Route != null && messageData.Route.Length > 2)
            {
                for (int i = 2; i < messageData.Route.Length; i++)
                {
                    if (!string.IsNullOrEmpty(messageData.Route[i]))
                    {
                        addresses.Add(AX25Address.GetAddress(messageData.Route[i]));
                    }
                }
            }

            // Create the AX.25 UI frame
            AX25Packet ax25Packet = new AX25Packet(addresses, aprsMessageContent, now);
            ax25Packet.type = AX25Packet.FrameType.U_FRAME_UI;
            ax25Packet.pid = 240; // No layer 3 protocol
            ax25Packet.command = true;
            ax25Packet.incoming = false;
            ax25Packet.sent = false;
            ax25Packet.authState = authApplied ? AX25Packet.AuthState.Success : AX25Packet.AuthState.None;

            // Find the APRS channel ID for this radio
            int aprsChannelId = GetAprsChannelId(messageData.RadioDeviceId);
            if (aprsChannelId < 0)
            {
                _broker.LogError("Cannot send APRS message: No APRS channel found on radio " + messageData.RadioDeviceId);
                return;
            }

            // Set the channel name on the packet
            ax25Packet.channel_id = aprsChannelId;
            ax25Packet.channel_name = "APRS";

            // Dispatch the TransmitDataFrame event to the radio
            var txData = new TransmitDataFrameData
            {
                Packet = ax25Packet,
                ChannelId = aprsChannelId,
                RegionId = -1 // Not applicable for APRS
            };

            _broker.Dispatch(messageData.RadioDeviceId, "TransmitDataFrame", txData, store: false);

            // Parse and dispatch the outgoing packet so it appears in the UI immediately as a sent message
            AprsPacket aprsPacket = AprsPacket.Parse(ax25Packet);
            if (aprsPacket != null)
            {
                // Store the frame in history
                lock (_lock)
                {
                    _aprsFrames.Add(aprsPacket);
                    while (_aprsFrames.Count > MaxFrameHistory)
                    {
                        _aprsFrames.RemoveAt(0);
                    }
                }

                // Dispatch the AprsFrame event so the UI shows it as sent
                _broker.Dispatch(1, "AprsFrame", new AprsFrameEventArgs(aprsPacket, ax25Packet, null), store: false);
            }
        }

        /// <summary>
        /// Gets the channel ID of the APRS channel for a specific radio.
        /// </summary>
        /// <param name="radioDeviceId">The device ID of the radio.</param>
        /// <returns>The channel ID of the APRS channel, or -1 if not found.</returns>
        private int GetAprsChannelId(int radioDeviceId)
        {
            // Get the channels array from the DataBroker for this radio
            var channels = _broker.GetValue<RadioChannelInfo[]>(radioDeviceId, "Channels", null);
            if (channels == null) return -1;

            // Find the channel named "APRS"
            for (int i = 0; i < channels.Length; i++)
            {
                if (channels[i] != null && channels[i].name_str == "APRS")
                {
                    return i;
                }
            }

            return -1;
        }

        /// <summary>
        /// Handles the PacketStoreReady event by requesting the packet list.
        /// </summary>
        private void OnPacketStoreReady(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (_storeReady) return; // Already processed

            // Request the packet list from PacketStore
            _broker.Dispatch(1, "RequestPacketList", null, store: false);
        }

        /// <summary>
        /// Handles the PacketList event by parsing all historical APRS packets.
        /// </summary>
        private void OnPacketList(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (_storeReady) return; // Already processed

            if (!(data is List<TncDataFragment> packets)) return;

            // Get the local callsign once before processing (avoid repeated lock acquisition)
            string localCallsign;
            lock (_lock)
            {
                localCallsign = _localCallsignWithId;
            }

            // Parse all historical packets from the APRS channel
            lock (_lock)
            {
                foreach (TncDataFragment frame in packets)
                {
                    // Only process frames from the APRS channel
                    if (frame.channel_name != "APRS") continue;

                    // Decode the frame as AX.25
                    AX25Packet ax25Packet = AX25Packet.DecodeAX25Packet(frame);
                    if (ax25Packet == null) continue;

                    // Only process U_FRAME (unnumbered frames, which include UI frames used by APRS)
                    if (ax25Packet.type != AX25Packet.FrameType.U_FRAME_UI && ax25Packet.type != AX25Packet.FrameType.U_FRAME) continue;

                    // Parse the APRS packet
                    AprsPacket aprsPacket = AprsPacket.Parse(ax25Packet);
                    if (aprsPacket == null) continue;

                    // Perform authentication check if an auth code is present
                    if (!string.IsNullOrEmpty(aprsPacket.AuthCode))
                    {
                        bool isSender = false;
                        string srcAddress = null;

                        if (ax25Packet.addresses != null && ax25Packet.addresses.Count >= 2)
                        {
                            srcAddress = ax25Packet.addresses[1].CallSignWithId;

                            if (!string.IsNullOrEmpty(localCallsign) &&
                                srcAddress.Equals(localCallsign, StringComparison.OrdinalIgnoreCase))
                            {
                                isSender = true;
                            }
                        }

                        if (srcAddress != null)
                        {
                            ax25Packet.authState = CheckAprsAuth(isSender, srcAddress, ax25Packet.dataStr, ax25Packet.time);
                        }
                    }
                    else
                    {
                        ax25Packet.authState = AX25Packet.AuthState.None;
                    }

                    // Add to the list
                    _aprsFrames.Add(aprsPacket);
                }

                // Trim the list to maintain the maximum size
                while (_aprsFrames.Count > MaxFrameHistory)
                {
                    _aprsFrames.RemoveAt(0);
                }
            }

            // Mark as ready
            _storeReady = true;

            // Notify subscribers that AprsHandler is ready with historical data
            // Use store: false since we now use on-demand request pattern
            _broker.Dispatch(1, "AprsStoreReady", true, store: false);
        }

        /// <summary>
        /// Handles RequestAprsPackets events to provide the current packet list on-demand.
        /// </summary>
        private void OnRequestAprsPackets(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!_storeReady) return; // Not ready yet

            List<AprsPacket> packets;
            lock (_lock)
            {
                packets = new List<AprsPacket>(_aprsFrames);
            }

            // Dispatch the current packet list to the requester
            _broker.Dispatch(1, "AprsPacketList", packets, store: false);
        }

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        /// <summary>
        /// Gets a copy of the current APRS frame history.
        /// </summary>
        public List<AprsPacket> GetAprsFrames()
        {
            lock (_lock)
            {
                return new List<AprsPacket>(_aprsFrames);
            }
        }

        /// <summary>
        /// Gets the number of APRS frames currently stored.
        /// </summary>
        public int FrameCount
        {
            get
            {
                lock (_lock)
                {
                    return _aprsFrames.Count;
                }
            }
        }

        /// <summary>
        /// Handles incoming UniqueDataFrame events and processes APRS packets.
        /// </summary>
        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is TncDataFragment frame)) return;

            // Only process frames from the APRS channel
            if (frame.channel_name != "APRS") return;

            // Decode the frame as AX.25
            AX25Packet ax25Packet = AX25Packet.DecodeAX25Packet(frame);
            if (ax25Packet == null) return;

            // Only process U_FRAME (unnumbered frames, which include UI frames used by APRS)
            if (ax25Packet.type != AX25Packet.FrameType.U_FRAME_UI && ax25Packet.type != AX25Packet.FrameType.U_FRAME) return;

            // Parse the APRS packet
            AprsPacket aprsPacket = AprsPacket.Parse(ax25Packet);
            if (aprsPacket == null) return;

            // Perform authentication check if an auth code is present
            if (!string.IsNullOrEmpty(aprsPacket.AuthCode))
            {
                // Determine if we are the sender or receiver
                bool isSender = false;
                string srcAddress = null;

                if (ax25Packet.addresses != null && ax25Packet.addresses.Count >= 2)
                {
                    srcAddress = ax25Packet.addresses[1].CallSignWithId; // Source address

                    // Check if we are the sender
                    string localCallsign;
                    lock (_lock)
                    {
                        localCallsign = _localCallsignWithId;
                    }
                    if (!string.IsNullOrEmpty(localCallsign) && 
                        srcAddress.Equals(localCallsign, StringComparison.OrdinalIgnoreCase))
                    {
                        isSender = true;
                    }
                }

                if (srcAddress != null)
                {
                    ax25Packet.authState = CheckAprsAuth(isSender, srcAddress, ax25Packet.dataStr, ax25Packet.time);
                }
            }
            else
            {
                ax25Packet.authState = AX25Packet.AuthState.None;
            }

            // Store the frame
            lock (_lock)
            {
                _aprsFrames.Add(aprsPacket);

                // Trim the list to maintain the maximum size
                while (_aprsFrames.Count > MaxFrameHistory)
                {
                    _aprsFrames.RemoveAt(0);
                }
            }

            // Dispatch the AprsFrame event via Data Broker (only for new frames, not startup-loaded frames)
            _broker.Dispatch(1, "AprsFrame", new AprsFrameEventArgs(aprsPacket, ax25Packet, frame), store: false);

            // Check if we need to send an ACK for this message (use the same radio that received it)
            SendAckIfNeeded(aprsPacket, ax25Packet, frame, deviceId);
        }

        /// <summary>
        /// Sends an ACK message if the received packet is a message addressed to our station.
        /// </summary>
        /// <param name="aprsPacket">The parsed APRS packet.</param>
        /// <param name="ax25Packet">The underlying AX.25 packet.</param>
        /// <param name="frame">The original TNC data fragment.</param>
        /// <param name="radioDeviceId">The device ID of the radio that received the packet.</param>
        private void SendAckIfNeeded(AprsPacket aprsPacket, AX25Packet ax25Packet, TncDataFragment frame, int radioDeviceId)
        {
            // Only process message packets
            if (aprsPacket.DataType != PacketDataType.Message) return;
            if (aprsPacket.MessageData == null) return;

            // Don't ACK ACKs or REJs
            if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck) return;
            if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtRej) return;

            // Only ACK messages that have a sequence ID
            if (string.IsNullOrEmpty(aprsPacket.MessageData.SeqId)) return;

            // Check if the message is addressed to us
            string localCallsign;
            lock (_lock)
            {
                localCallsign = _localCallsignWithId;
            }
            if (string.IsNullOrEmpty(localCallsign)) return;

            // Compare addressee with our callsign (case-insensitive)
            string addressee = aprsPacket.MessageData.Addressee;
            if (string.IsNullOrEmpty(addressee)) return;

            // Also check against callsign without station ID
            string callsignOnly = _broker.GetValue<string>(0, "CallSign", "");
            bool isForUs = addressee.Equals(localCallsign, StringComparison.OrdinalIgnoreCase) ||
                           addressee.Equals(callsignOnly, StringComparison.OrdinalIgnoreCase);

            if (!isForUs) return;

            // Get the source callsign (who sent the message)
            if (ax25Packet.addresses == null || ax25Packet.addresses.Count < 2) return;
            string senderCallsign = ax25Packet.addresses[1].CallSignWithId;

            // Verify the radio has an APRS channel before sending ACK
            int aprsChannelId = GetAprsChannelId(radioDeviceId);
            if (aprsChannelId < 0) return;

            // Build the ACK message
            // Format: :SENDER   :ack{seqId} or with auth: :SENDER   :ack{seqId}}authCode
            string ackMessage = "ack" + aprsPacket.MessageData.SeqId;
            DateTime now = DateTime.Now;

            // Check if we should include authentication in the ACK
            // Include auth if the incoming message had valid authentication
            bool useAuth = (ax25Packet.authState == AX25Packet.AuthState.Success);
            bool authApplied = false;
            string aprsContent;

            if (useAuth)
            {
                // Use the AddAprsAuthNoMsgId method since ACKs don't have their own message ID
                aprsContent = AddAprsAckAuth(localCallsign, senderCallsign, ackMessage, now, out authApplied);
            }
            else
            {
                // No authentication needed
                string paddedAddr = senderCallsign;
                while (paddedAddr.Length < 9) { paddedAddr += " "; }
                aprsContent = ":" + paddedAddr + ":" + ackMessage;
            }

            // Build the address list for the AX.25 frame
            List<AX25Address> addresses = new List<AX25Address>();
            addresses.Add(AX25Address.GetAddress("APRS")); // Destination
            addresses.Add(AX25Address.GetAddress(localCallsign)); // Source (us)

            // Create the AX.25 UI frame for the ACK
            AX25Packet ackAx25Packet = new AX25Packet(addresses, aprsContent, now);
            ackAx25Packet.type = AX25Packet.FrameType.U_FRAME_UI;
            ackAx25Packet.pid = 240; // No layer 3 protocol
            ackAx25Packet.command = true;
            ackAx25Packet.incoming = false;
            ackAx25Packet.sent = false;
            ackAx25Packet.authState = authApplied ? AX25Packet.AuthState.Success : AX25Packet.AuthState.None;

            ackAx25Packet.channel_id = aprsChannelId;
            ackAx25Packet.channel_name = "APRS";

            // Dispatch the TransmitDataFrame event to the radio
            var txData = new TransmitDataFrameData
            {
                Packet = ackAx25Packet,
                ChannelId = aprsChannelId,
                RegionId = -1
            };

            _broker.Dispatch(radioDeviceId, "TransmitDataFrame", txData, store: false);

            // Parse and dispatch the ACK packet so it appears in the UI as sent
            AprsPacket ackAprsPacket = AprsPacket.Parse(ackAx25Packet);
            if (ackAprsPacket != null)
            {
                lock (_lock)
                {
                    _aprsFrames.Add(ackAprsPacket);
                    while (_aprsFrames.Count > MaxFrameHistory)
                    {
                        _aprsFrames.RemoveAt(0);
                    }
                }

                _broker.Dispatch(1, "AprsFrame", new AprsFrameEventArgs(ackAprsPacket, ackAx25Packet, null), store: false);
            }
        }

        /// <summary>
        /// Finds a radio device that has an APRS channel configured.
        /// </summary>
        /// <returns>The device ID of a radio with an APRS channel, or -1 if none found.</returns>
        private int FindRadioWithAprsChannel()
        {
            // Get the list of connected radios from the DataBroker
            var connectedRadios = _broker.GetValue<object>(1, "ConnectedRadios", null);
            if (connectedRadios == null) return -1;

            if (connectedRadios is System.Collections.IEnumerable radioList)
            {
                foreach (var radio in radioList)
                {
                    var radioType = radio.GetType();
                    var deviceIdProp = radioType.GetProperty("DeviceId");
                    if (deviceIdProp != null)
                    {
                        int radioDeviceId = (int)deviceIdProp.GetValue(radio);
                        int channelId = GetAprsChannelId(radioDeviceId);
                        if (channelId >= 0)
                        {
                            return radioDeviceId;
                        }
                    }
                }
            }

            return -1;
        }

        /// <summary>
        /// Adds APRS authentication to an ACK message (no message ID).
        /// </summary>
        /// <param name="srcAddress">The source callsign with station ID.</param>
        /// <param name="destAddress">The destination callsign.</param>
        /// <param name="ackMessage">The ACK message content (e.g., "ack123").</param>
        /// <param name="time">The timestamp for authentication.</param>
        /// <param name="authApplied">Output: whether authentication was applied.</param>
        /// <returns>The formatted APRS ACK message with optional authentication.</returns>
        private string AddAprsAckAuth(string srcAddress, string destAddress, string ackMessage, DateTime time, out bool authApplied)
        {
            // APRS Address - pad to 9 characters
            string aprsAddr = destAddress;
            while (aprsAddr.Length < 9) { aprsAddr += " "; }

            // Search for an APRS authentication key for the destination (the original sender)
            string authPassword = null;
            lock (_lock)
            {
                foreach (StationInfoClass station in _stations)
                {
                    if ((station.StationType == StationInfoClass.StationTypes.APRS) &&
                        (station.Callsign.Equals(destAddress, StringComparison.OrdinalIgnoreCase)) &&
                        !string.IsNullOrEmpty(station.AuthPassword))
                    {
                        authPassword = station.AuthPassword;
                        break;
                    }
                }
            }

            // If the auth key is not present, send without authentication
            if (string.IsNullOrEmpty(authPassword))
            {
                authApplied = false;
                return ":" + aprsAddr + ":" + ackMessage;
            }

            // Compute the current time in minutes since Unix epoch
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes;

            // Compute authentication token
            byte[] authKey = Utils.ComputeSha256Hash(Encoding.UTF8.GetBytes(authPassword));
            string hashInput = minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + ":" + ackMessage;
            byte[] authCode = Utils.ComputeHmacSha256Hash(authKey, Encoding.UTF8.GetBytes(hashInput));
            string authCodeBase64 = Convert.ToBase64String(authCode).Substring(0, 6);

            // Add authentication token to APRS message
            authApplied = true;
            return ":" + aprsAddr + ":" + ackMessage + "}" + authCodeBase64;
        }

        /// <summary>
        /// Adds APRS authentication to a message with message ID.
        /// </summary>
        /// <param name="srcAddress">The source callsign with station ID.</param>
        /// <param name="destAddress">The destination callsign.</param>
        /// <param name="aprsMessage">The APRS message content.</param>
        /// <param name="msgId">The message ID.</param>
        /// <param name="time">The timestamp for authentication.</param>
        /// <param name="authApplied">Output: whether authentication was applied.</param>
        /// <returns>The formatted APRS message with optional authentication.</returns>
        public string AddAprsAuth(string srcAddress, string destAddress, string aprsMessage, int msgId, DateTime time, out bool authApplied)
        {
            // APRS Address - pad to 9 characters
            string aprsAddr = destAddress;
            while (aprsAddr.Length < 9) { aprsAddr += " "; }

            // Search for an APRS authentication key
            string authPassword = null;
            lock (_lock)
            {
                foreach (StationInfoClass station in _stations)
                {
                    if ((station.StationType == StationInfoClass.StationTypes.APRS) &&
                        (station.Callsign.Equals(destAddress, StringComparison.OrdinalIgnoreCase)) &&
                        !string.IsNullOrEmpty(station.AuthPassword))
                    {
                        authPassword = station.AuthPassword;
                        break;
                    }
                }
            }

            // If the auth key is not present, send without authentication
            if (string.IsNullOrEmpty(authPassword))
            {
                authApplied = false;
                return ":" + aprsAddr + ":" + aprsMessage + "{" + msgId;
            }

            // Compute the current time in minutes since Unix epoch
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes;

            // Compute authentication token
            byte[] authKey = Utils.ComputeSha256Hash(Encoding.UTF8.GetBytes(authPassword));
            string hashInput = minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + ":" + aprsMessage + "{" + msgId;
            byte[] authCode = Utils.ComputeHmacSha256Hash(authKey, Encoding.UTF8.GetBytes(hashInput));
            string authCodeBase64 = Convert.ToBase64String(authCode).Substring(0, 6);

            // Add authentication token to APRS message
            authApplied = true;
            return ":" + aprsAddr + ":" + aprsMessage + "}" + authCodeBase64 + "{" + msgId;
        }

        /// <summary>
        /// Adds APRS authentication to a message (without message ID).
        /// </summary>
        /// <param name="srcAddress">The source callsign with station ID.</param>
        /// <param name="destAddress">The destination callsign.</param>
        /// <param name="aprsMessage">The APRS message content.</param>
        /// <param name="time">The timestamp for authentication.</param>
        /// <param name="authApplied">Output: whether authentication was applied.</param>
        /// <returns>The formatted APRS message with optional authentication.</returns>
        public string AddAprsAuthNoMsgId(string srcAddress, string destAddress, string aprsMessage, DateTime time, out bool authApplied)
        {
            // APRS Address - pad to 9 characters
            string aprsAddr = destAddress;
            while (aprsAddr.Length < 9) { aprsAddr += " "; }

            // Search for an APRS authentication key
            string authPassword = null;
            lock (_lock)
            {
                foreach (StationInfoClass station in _stations)
                {
                    if ((station.StationType == StationInfoClass.StationTypes.APRS) &&
                        (station.Callsign.Equals(destAddress, StringComparison.OrdinalIgnoreCase)) &&
                        !string.IsNullOrEmpty(station.AuthPassword))
                    {
                        authPassword = station.AuthPassword;
                        break;
                    }
                }
            }

            // If the auth key is not present, send without authentication
            if (string.IsNullOrEmpty(authPassword))
            {
                authApplied = false;
                return ":" + aprsAddr + aprsMessage;
            }

            // Compute the current time in minutes since Unix epoch
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes;

            // Compute authentication token
            byte[] authKey = Utils.ComputeSha256Hash(Encoding.UTF8.GetBytes(authPassword));
            string hashInput = minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + aprsMessage;
            byte[] authCode = Utils.ComputeHmacSha256Hash(authKey, Encoding.UTF8.GetBytes(hashInput));
            string authCodeBase64 = Convert.ToBase64String(authCode).Substring(0, 6);

            // Add authentication token to APRS message
            authApplied = true;
            return ":" + aprsAddr + aprsMessage + "}" + authCodeBase64;
        }

        /// <summary>
        /// Checks APRS authentication for an incoming message.
        /// </summary>
        /// <param name="sender">True if we are the sender, false if receiver.</param>
        /// <param name="srcAddress">The source callsign with station ID.</param>
        /// <param name="aprsMessage">The raw APRS message string.</param>
        /// <param name="time">The timestamp of the message.</param>
        /// <returns>The authentication state.</returns>
        public AX25Packet.AuthState CheckAprsAuth(bool sender, string srcAddress, string aprsMessage, DateTime time)
        {
            if (string.IsNullOrEmpty(aprsMessage) || aprsMessage.Length < 11) return AX25Packet.AuthState.None;

            string keyAddr;
            string aprsAddr = aprsMessage.Substring(1, 9);

            if (sender)
            {
                // We are the sender, so get the outbound address auth key
                keyAddr = aprsAddr.Trim();
            }
            else
            {
                // We are the receiver, we use the source address auth key
                keyAddr = srcAddress;
            }

            // Search for an APRS authentication key
            string authPassword = null;
            lock (_lock)
            {
                foreach (StationInfoClass station in _stations)
                {
                    if ((station.StationType == StationInfoClass.StationTypes.APRS) &&
                        (station.Callsign.Equals(keyAddr, StringComparison.OrdinalIgnoreCase)) &&
                        !string.IsNullOrEmpty(station.AuthPassword))
                    {
                        authPassword = station.AuthPassword;
                        break;
                    }
                }
            }

            // No auth key found
            if (string.IsNullOrEmpty(authPassword)) return AX25Packet.AuthState.None;

            // Parse the message to extract auth code and message ID
            string msgId = null;
            string messageContent = aprsMessage.Substring(10);

            // Check for message ID (format: message{msgId)
            string[] msplit1 = messageContent.Split('{');
            if (msplit1.Length == 2)
            {
                msgId = msplit1[1];
                messageContent = msplit1[0];
            }

            // Check for auth code (format: message}authCode)
            string[] msplit2 = messageContent.Split('}');
            if (msplit2.Length != 2) return AX25Packet.AuthState.None;

            string authCodeBase64Check = msplit2[1];
            string cleanMessage = msplit2[0];

            // Compute the current time in minutes since Unix epoch
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes - 2;

            // Compute auth key
            byte[] authKey = Utils.ComputeSha256Hash(Encoding.UTF8.GetBytes(authPassword));

            // Build the hash message
            string hashMsg = ":" + srcAddress + ":" + aprsAddr.Trim() + cleanMessage;
            if (msgId != null)
            {
                hashMsg += "{" + msgId;
            }

            // Try a window of 5 minutes to account for time drift
            for (long x = minutesSinceEpoch; x < (minutesSinceEpoch + 5); x++)
            {
                byte[] computedAuth = Utils.ComputeHmacSha256Hash(authKey, Encoding.UTF8.GetBytes(x + hashMsg));
                string authCodeBase64 = Convert.ToBase64String(computedAuth).Substring(0, 6);
                if (authCodeBase64Check == authCodeBase64)
                {
                    return AX25Packet.AuthState.Success; // Verified authentication
                }
            }

            return AX25Packet.AuthState.Failed; // Bad auth
        }

        /// <summary>
        /// Clears all stored APRS frames.
        /// </summary>
        public void ClearFrames()
        {
            lock (_lock)
            {
                _aprsFrames.Clear();
            }
        }

        /// <summary>
        /// Disposes the handler, unsubscribing from the broker.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the handler.
        /// </summary>
        /// <param name="disposing">True if called from Dispose(), false if called from finalizer.</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    // Dispose the broker client (unsubscribes)
                    _broker?.Dispose();

                    // Clear the frames
                    lock (_lock)
                    {
                        _aprsFrames.Clear();
                    }
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~AprsHandler()
        {
            Dispose(false);
        }
    }

    /// <summary>
    /// Data class for sending APRS messages via the Data Broker.
    /// </summary>
    public class AprsSendMessageData
    {
        /// <summary>
        /// The destination callsign for the APRS message.
        /// </summary>
        public string Destination { get; set; }

        /// <summary>
        /// The message text to send.
        /// </summary>
        public string Message { get; set; }

        /// <summary>
        /// The device ID of the radio to use for transmission.
        /// </summary>
        public int RadioDeviceId { get; set; }

        /// <summary>
        /// The APRS route to use (optional). Format: [RouteName, Dest, Path1, Path2, ...]
        /// </summary>
        public string[] Route { get; set; }
    }

    /// <summary>
    /// Event arguments for the AprsFrameReceived event.
    /// </summary>
    public class AprsFrameEventArgs : EventArgs
    {
        /// <summary>
        /// The parsed APRS packet.
        /// </summary>
        public AprsPacket AprsPacket { get; }

        /// <summary>
        /// The underlying AX.25 packet.
        /// </summary>
        public AX25Packet AX25Packet { get; }

        /// <summary>
        /// The original TNC data fragment.
        /// </summary>
        public TncDataFragment Fragment { get; }

        /// <summary>
        /// Creates new AprsFrameEventArgs.
        /// </summary>
        /// <param name="aprsPacket">The parsed APRS packet.</param>
        /// <param name="ax25Packet">The underlying AX.25 packet.</param>
        /// <param name="fragment">The original TNC data fragment.</param>
        public AprsFrameEventArgs(AprsPacket aprsPacket, AX25Packet ax25Packet, TncDataFragment fragment)
        {
            AprsPacket = aprsPacket;
            AX25Packet = ax25Packet;
            Fragment = fragment;
        }
    }
}
