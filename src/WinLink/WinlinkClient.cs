/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Net.Sockets;
using System.Net.Security;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Security.Cryptography.X509Certificates;

namespace HTCommander
{
    // Class to hold debug traffic entries
    public class WinlinkDebugEntry
    {
        public string Address { get; set; }
        public bool Outgoing { get; set; }
        public string Data { get; set; }
        public bool IsStateMessage { get; set; }
    }

    public class WinlinkClient : IDisposable
    {
        public enum TransportType { X25, TCP }
        public enum ConnectionState { DISCONNECTED, CONNECTED, CONNECTING, DISCONNECTING }

        private DataBrokerClient broker;
        private TransportType transportType = TransportType.TCP;
        private Dictionary<string, object> sessionState = new Dictionary<string, object>();
        private bool _disposed = false;
        
        // TCP specific fields
        private TcpClient tcpClient;
        private Stream tcpStream; // Changed to Stream to support both NetworkStream and SslStream
        private bool tcpRunning = false;
        private string remoteAddress = "";
        private ConnectionState currentState = ConnectionState.DISCONNECTED;
        private bool useTls = false;
        
        // Radio lock fields for X25 transport
        private int lockedRadioId = -1;
        private StationInfoClass connectedStation = null;
        
        // AX25Session for X25 transport
        private AX25Session ax25Session = null;
        private bool pendingDisconnect = false;

        // Debug traffic history buffer (last 1000 entries)
        private const int MaxDebugHistorySize = 1000;
        private List<WinlinkDebugEntry> debugHistory = new List<WinlinkDebugEntry>();
        private readonly object debugHistoryLock = new object();

        public WinlinkClient()
        {
            this.broker = new DataBrokerClient();
            
            // Subscribe to broker events to start syncing
            broker.Subscribe(1, "WinlinkSync", OnWinlinkSync);
            broker.Subscribe(1, "WinlinkDisconnect", OnWinlinkDisconnect);
            broker.Subscribe(1, "WinlinkDebugClear", OnWinlinkDebugClearHistory);
            broker.Subscribe(1, "WinlinkDebugHistoryRequest", OnWinlinkDebugHistoryRequest);
        }

        private void OnWinlinkSync(int deviceId, string name, object data)
        {
            if (_disposed) return;
            
            // Ignore if we are already busy (not disconnected)
            if (currentState != ConnectionState.DISCONNECTED) return;
            
            // Start sync - data should contain server info or radio/station info
            // Expected for TCP: { Server = "server.winlink.org", Port = 8772, UseTls = true }
            // Expected for Radio: { RadioId = int, Station = StationInfoClass }
            if (data == null) return;
            
            var dataType = data.GetType();
            string server = (string)dataType.GetProperty("Server")?.GetValue(data);
            
            if (!string.IsNullOrEmpty(server))
            {
                // TCP/Internet sync
                int port = (int)(dataType.GetProperty("Port")?.GetValue(data) ?? 8772);
                bool useTls = (bool)(dataType.GetProperty("UseTls")?.GetValue(data) ?? true);
                
                transportType = TransportType.TCP;
                _ = ConnectTcp(server, port, useTls);
            }
            else
            {
                // X25/Radio sync - check for RadioId and Station
                int? radioId = (int?)dataType.GetProperty("RadioId")?.GetValue(data);
                object stationObj = dataType.GetProperty("Station")?.GetValue(data);
                
                if (radioId.HasValue && stationObj is StationInfoClass station)
                {
                    StartRadioSync(radioId.Value, station);
                }
                else
                {
                    // Legacy X25 connection handling
                    transportType = TransportType.X25;
                }
            }
        }
        
        /// <summary>
        /// Starts a Winlink sync using a radio with the specified station.
        /// Locks the radio and begins the X25 connection process.
        /// </summary>
        private void StartRadioSync(int radioId, StationInfoClass station)
        {
            if (radioId <= 0 || station == null) return;
            
            // Get the current region from HtStatus
            RadioHtStatus htStatus = broker.GetValue<RadioHtStatus>(radioId, "HtStatus", null);
            int regionId = htStatus?.curr_region ?? 0;
            
            // Look up the channel ID from the channel name
            int channelId = -1;
            if (!string.IsNullOrEmpty(station.Channel))
            {
                RadioChannelInfo[] channels = broker.GetValue<RadioChannelInfo[]>(radioId, "Channels", null);
                if (channels != null)
                {
                    for (int i = 0; i < channels.Length; i++)
                    {
                        if (channels[i] != null && channels[i].name_str == station.Channel)
                        {
                            channelId = i;
                            break;
                        }
                    }
                }
            }
            
            // If no channel found, report error and don't lock the radio
            if (channelId < 0)
            {
                StateMessage("Channel '" + station.Channel + "' not found on radio.");
                return;
            }
            
            // Store the radio and station for later unlock
            lockedRadioId = radioId;
            connectedStation = station;
            
            // Lock the radio to Winlink usage
            var lockData = new SetLockData
            {
                Usage = "Winlink",
                RegionId = regionId,
                ChannelId = channelId
            };
            broker.Dispatch(radioId, "SetLock", lockData, store: false);
            
            // Set up X25 transport
            transportType = TransportType.X25;
            
            // Clear debug history for new session
            broker.Dispatch(1, "WinlinkDebugClear", true, store: false);
            
            StateMessage("Connecting to " + station.Callsign + " via radio...");
            
            // Initialize the AX25Session and start the connection
            InitializeAX25Session(radioId, station);
        }
        
        /// <summary>
        /// Initializes an AX25Session and starts connecting to the station.
        /// </summary>
        private void InitializeAX25Session(int radioId, StationInfoClass station)
        {
            // Dispose any existing session
            DisposeAX25Session();
            
            // Get our callsign from settings
            string myCallsignWithId = broker.GetValue<string>(0, "Callsign", "N0CALL-0");
            string myCallsign;
            int myStationId;
            if (!Utils.ParseCallsignWithId(myCallsignWithId, out myCallsign, out myStationId))
            {
                myCallsign = myCallsignWithId;
                myStationId = 0;
            }
            
            // Parse the destination callsign
            string destCallsign;
            int destStationId;
            if (!Utils.ParseCallsignWithId(station.Callsign, out destCallsign, out destStationId))
            {
                destCallsign = station.Callsign;
                destStationId = 0;
            }
            
            // Create the session
            ax25Session = new AX25Session(radioId);
            ax25Session.CallSignOverride = myCallsign;
            ax25Session.StationIdOverride = myStationId;
            
            // Subscribe to session events
            ax25Session.StateChanged += OnAX25SessionStateChanged;
            ax25Session.DataReceivedEvent += OnAX25SessionDataReceived;
            ax25Session.ErrorEvent += OnAX25SessionError;
            
            // Create addresses: destination, source
            List<AX25Address> addresses = new List<AX25Address>();
            addresses.Add(AX25Address.GetAddress(destCallsign, destStationId)); // Destination
            addresses.Add(AX25Address.GetAddress(myCallsign, myStationId)); // Source
            
            // Start the connection
            ax25Session.Connect(addresses);
        }
        
        /// <summary>
        /// Disposes the current AX25Session and cleans up resources.
        /// </summary>
        private void DisposeAX25Session()
        {
            if (ax25Session != null)
            {
                // Unsubscribe from events
                ax25Session.StateChanged -= OnAX25SessionStateChanged;
                ax25Session.DataReceivedEvent -= OnAX25SessionDataReceived;
                ax25Session.ErrorEvent -= OnAX25SessionError;
                
                // Disconnect if connected
                if (ax25Session.CurrentState == AX25Session.ConnectionState.CONNECTED ||
                    ax25Session.CurrentState == AX25Session.ConnectionState.CONNECTING)
                {
                    ax25Session.Disconnect();
                }
                
                // Dispose the session
                ax25Session.Dispose();
                ax25Session = null;
            }
        }
        
        /// <summary>
        /// Handles AX25Session state change events.
        /// </summary>
        private void OnAX25SessionStateChanged(AX25Session sender, AX25Session.ConnectionState state)
        {
            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    SetConnectionState(ConnectionState.CONNECTED);
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    SetConnectionState(ConnectionState.CONNECTING);
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    pendingDisconnect = false;
                    SetConnectionState(ConnectionState.DISCONNECTED);
                    DisposeAX25Session();
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
                    SetConnectionState(ConnectionState.DISCONNECTING);
                    break;
            }
        }
        
        /// <summary>
        /// Handles AX25Session data received events.
        /// </summary>
        private void OnAX25SessionDataReceived(AX25Session sender, byte[] data)
        {
            if (data == null || data.Length == 0) return;
            
            // Copy session state from AX25Session
            sessionState = sender.sessionState;
            if (sender.Addresses != null && sender.Addresses.Count > 0)
            {
                remoteAddress = sender.Addresses[0].ToString();
            }
            
            // Process the received data
            ProcessStream(data);
        }
        
        /// <summary>
        /// Handles AX25Session error events.
        /// </summary>
        private void OnAX25SessionError(AX25Session sender, string error)
        {
            StateMessage("Session error: " + error);
        }
        
        /// <summary>
        /// Unlocks the radio that was locked for Winlink usage.
        /// </summary>
        private void UnlockRadio()
        {
            if (lockedRadioId > 0)
            {
                var unlockData = new SetUnlockData { Usage = "Winlink" };
                broker.Dispatch(lockedRadioId, "SetUnlock", unlockData, store: false);
                lockedRadioId = -1;
                connectedStation = null;
            }
        }

        private void OnWinlinkDisconnect(int deviceId, string name, object data)
        {
            if (_disposed) return;
            
            if (transportType == TransportType.TCP)
            {
                DisconnectTcp();
            }
            else if (transportType == TransportType.X25)
            {
                DisconnectX25();
            }
        }
        
        /// <summary>
        /// Disconnects the X25/AX25 session.
        /// </summary>
        private void DisconnectX25()
        {
            if (ax25Session == null) return;
            
            // If we're already waiting for disconnect to complete, don't do anything
            if (pendingDisconnect) return;
            
            // Start the graceful disconnect process
            if (ax25Session.CurrentState == AX25Session.ConnectionState.CONNECTED ||
                ax25Session.CurrentState == AX25Session.ConnectionState.CONNECTING)
            {
                pendingDisconnect = true;
                ax25Session.Disconnect();
            }
            else
            {
                // Session is already disconnected or disconnecting
                DisposeAX25Session();
                SetConnectionState(ConnectionState.DISCONNECTED);
            }
        }

        private void OnWinlinkDebugClearHistory(int deviceId, string name, object data)
        {
            if (_disposed) return;
            
            // Clear the debug history buffer
            lock (debugHistoryLock)
            {
                debugHistory.Clear();
            }
        }

        private void OnWinlinkDebugHistoryRequest(int deviceId, string name, object data)
        {
            if (_disposed) return;
            
            // Send the debug history to the requester
            List<WinlinkDebugEntry> historyCopy;
            lock (debugHistoryLock)
            {
                historyCopy = new List<WinlinkDebugEntry>(debugHistory);
            }
            
            // Dispatch the history via broker
            broker.Dispatch(1, "WinlinkDebugHistory", historyCopy, store: false);
        }

        private void AddToDebugHistory(string address, bool outgoing, string data, bool isStateMessage = false)
        {
            if (string.IsNullOrEmpty(data)) return;
            
            lock (debugHistoryLock)
            {
                // Add new entry
                debugHistory.Add(new WinlinkDebugEntry
                {
                    Address = address,
                    Outgoing = outgoing,
                    Data = data,
                    IsStateMessage = isStateMessage
                });
                
                // Trim to max size if needed
                while (debugHistory.Count > MaxDebugHistorySize)
                {
                    debugHistory.RemoveAt(0);
                }
            }
        }

        private void TransportSend(string output)
        {
            if (!string.IsNullOrEmpty(output))
            {
                string[] dataStrs = output.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                foreach (string str in dataStrs)
                {
                    if (str.Length == 0) continue;
                    string trimmedStr = str.Trim();
                    // Add to debug history
                    AddToDebugHistory(remoteAddress, true, trimmedStr, false);
                    // Use broker to dispatch debug traffic (device 1 for non-persistent state)
                    broker.Dispatch(1, "WinlinkTraffic", new { Address = remoteAddress, Outgoing = true, Data = trimmedStr }, store: false);
                }

                if (transportType == TransportType.TCP)
                {
                    SendTcp(output);
                }
            }
        }

        private void TransportSend(byte[] data)
        {
            if ((data != null) && (data.Length > 0))
            {
                if (transportType == TransportType.TCP)
                {
                    SendTcp(data);
                }
            }
        }

        private void StateMessage(string msg)
        {
            // Add to debug history (state messages are special entries)
            if (!string.IsNullOrEmpty(msg))
            {
                AddToDebugHistory(remoteAddress, false, msg, true);
            }
            // Dispatch state message via broker (device 1 for non-persistent state)
            broker.Dispatch(1, "WinlinkStateMessage", msg, store: false);
        }

        private void SetConnectionState(ConnectionState state)
        {
            if (state != currentState)
            {
                currentState = state;
                ProcessTransportStateChange(state);
                
                // Dispatch connection state change via broker (device 1 for non-persistent state)
                broker.Dispatch(1, "WinlinkConnectionState", state.ToString(), store: false);
                
                // Dispatch busy state - busy when not disconnected
                bool isBusy = (state != ConnectionState.DISCONNECTED);
                broker.Dispatch(1, "WinlinkBusy", isBusy, store: false);
                
                if (state == ConnectionState.DISCONNECTED)
                {
                    sessionState.Clear();
                    remoteAddress = "";
                    
                    // Unlock the radio when disconnected
                    UnlockRadio();
                }
            }
        }

        // TCP Connection Methods
        public async Task<bool> ConnectTcp(string server, int port, bool useTls = false)
        {
            if (transportType != TransportType.TCP)
            {
                StateMessage("Error: Cannot use TCP connection with X25 transport type.");
                return false;
            }

            if (currentState != ConnectionState.DISCONNECTED)
            {
                StateMessage("Error: Already connected or connecting.");
                return false;
            }

            try
            {
                SetConnectionState(ConnectionState.CONNECTING);
                remoteAddress = server + ":" + port;
                this.useTls = useTls;
                
                // Dispatch clear command via broker (device 1 for non-persistent state)
                broker.Dispatch(1, "WinlinkDebugClear", true, store: false);
                
                StateMessage("Connecting to " + server + "...");
                tcpClient = new TcpClient();
                await tcpClient.ConnectAsync(server, port);
                
                if (useTls)
                {
                    StateMessage("Establishing secure connection...");
                    // Wrap the network stream with SSL/TLS
                    NetworkStream networkStream = tcpClient.GetStream();
                    SslStream sslStream = new SslStream(
                        networkStream,
                        false,
                        new RemoteCertificateValidationCallback(ValidateServerCertificate),
                        null
                    );
                    
                    try
                    {
                        await sslStream.AuthenticateAsClientAsync(server);
                        tcpStream = sslStream;
                        StateMessage("Secure connection established.");
                    }
                    catch (Exception ex)
                    {
                        StateMessage("TLS/SSL authentication failed: " + ex.Message);
                        sslStream.Close();
                        throw;
                    }
                }
                else
                {
                    tcpStream = tcpClient.GetStream();
                }
                
                SetConnectionState(ConnectionState.CONNECTED);
                
                // Start receiving data
                tcpRunning = true;
                _ = Task.Run(() => TcpReceiveLoop());
                
                return true;
            }
            catch (Exception ex)
            {
                StateMessage("TCP Connection failed: " + ex.Message);
                SetConnectionState(ConnectionState.DISCONNECTED);
                CleanupTcp();
                return false;
            }
        }

        // Certificate validation callback for SSL/TLS
        private bool ValidateServerCertificate(
            object sender,
            X509Certificate certificate,
            X509Chain chain,
            SslPolicyErrors sslPolicyErrors)
        {
            if (sslPolicyErrors == SslPolicyErrors.None)
            {
                return true;
            }

            StateMessage("Certificate validation error: " + sslPolicyErrors.ToString());
            
            // Log certificate details for debugging
            if (certificate != null)
            {
                StateMessage("Certificate Subject: " + certificate.Subject);
                StateMessage("Certificate Issuer: " + certificate.Issuer);
            }
            
            // For production, you should return false here to reject invalid certificates
            // For now, we'll be strict and reject invalid certificates
            return false;
        }

        public void DisconnectTcp()
        {
            if (transportType != TransportType.TCP) return;
            
            SetConnectionState(ConnectionState.DISCONNECTING);
            tcpRunning = false;
            CleanupTcp();
            SetConnectionState(ConnectionState.DISCONNECTED);
        }

        private void CleanupTcp()
        {
            try
            {
                if (tcpStream != null)
                {
                    tcpStream.Close();
                    tcpStream.Dispose();
                    tcpStream = null;
                }
                if (tcpClient != null)
                {
                    tcpClient.Close();
                    tcpClient.Dispose();
                    tcpClient = null;
                }
            }
            catch { }
        }

        private void SendTcp(string data)
        {
            if (tcpStream != null && tcpStream.CanWrite)
            {
                try
                {
                    byte[] buffer = UTF8Encoding.UTF8.GetBytes(data);
                    tcpStream.Write(buffer, 0, buffer.Length);
                    tcpStream.Flush();
                }
                catch (Exception ex)
                {
                    StateMessage("TCP Send error: " + ex.Message);
                    DisconnectTcp();
                }
            }
        }

        private void SendTcp(byte[] data)
        {
            if (tcpStream != null && tcpStream.CanWrite)
            {
                try
                {
                    tcpStream.Write(data, 0, data.Length);
                    tcpStream.Flush();
                }
                catch (Exception ex)
                {
                    StateMessage("TCP Send error: " + ex.Message);
                    DisconnectTcp();
                }
            }
        }

        private async Task TcpReceiveLoop()
        {
            byte[] buffer = new byte[8192];
            
            while (tcpRunning && tcpClient != null && tcpClient.Connected)
            {
                try
                {
                    int bytesRead = await tcpStream.ReadAsync(buffer, 0, buffer.Length);
                    
                    if (bytesRead > 0)
                    {
                        byte[] data = new byte[bytesRead];
                        Array.Copy(buffer, 0, data, 0, bytesRead);
                        
                        // Process received data - broker handles UI thread marshalling
                        ProcessStream(data);
                    }
                    else
                    {
                        // Connection closed by remote
                        break;
                    }
                }
                catch (Exception ex)
                {
                    if (tcpRunning)
                    {
                        StateMessage("TCP Receive error: " + ex.Message);
                    }
                    break;
                }
            }

            // Connection closed
            if (tcpRunning)
            {
                DisconnectTcp();
            }
        }

        // X25 Support Methods (called from external code for X25 transport)
        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            if (transportType != TransportType.X25) return;

            remoteAddress = session.Addresses[0].ToString();
            
            ConnectionState newState;
            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    newState = ConnectionState.CONNECTED;
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    newState = ConnectionState.DISCONNECTED;
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    newState = ConnectionState.CONNECTING;
                    broker.Dispatch(1, "WinlinkDebugClear", true, store: false);
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
                    newState = ConnectionState.DISCONNECTING;
                    break;
                default:
                    return;
            }
            
            SetConnectionState(newState);
        }

        public void ProcessStream(AX25Session session, byte[] data)
        {
            if (transportType != TransportType.X25) return;
            
            // Copy session state from AX25Session
            sessionState = session.sessionState;
            remoteAddress = session.Addresses[0].ToString();
            
            ProcessStream(data);
        }

        private void ProcessTransportStateChange(ConnectionState state)
        {
            switch (state)
            {
                case ConnectionState.CONNECTED:
                    StateMessage("Connected to " + remoteAddress);
                    break;
                case ConnectionState.DISCONNECTED:
                    StateMessage("Disconnected");
                    StateMessage(null);
                    break;
                case ConnectionState.CONNECTING:
                    StateMessage("Connecting...");
                    break;
                case ConnectionState.DISCONNECTING:
                    StateMessage("Disconnecting...");
                    break;
            }
        }

        private string GetVersion()
        {
            // Get the path of the currently running executable
            string exePath = Application.ExecutablePath;

            // Get the FileVersionInfo for the executable
            FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(exePath);

            // Return the FileVersion as a string
            string[] vers = versionInfo.FileVersion.Split('.');
            return vers[0] + "." + vers[1];
        }

        private string[] ParseProposalResponses(string value)
        {
            value = value.ToUpper().Replace("+", "Y").Replace("R", "N").Replace("-", "N").Replace("=", "L").Replace("H", "L").Replace("!", "A");
            List<string> responses = new List<string>();
            string r = "";
            for (int i = 0; i < value.Length; i++)
            {
                if ((value[i] >= '0') && (value[i] <= '9'))
                {
                    if (!string.IsNullOrEmpty(r)) { r += value[i]; }
                }
                else
                {
                    if (!string.IsNullOrEmpty(r)) { responses.Add(r); r = ""; }
                    r += value[i];
                }
            }
            if (!string.IsNullOrEmpty(r)) { responses.Add(r); }
            return responses.ToArray();
        }

        private void UpdateEmails()
        {
            // All good, save the new state of the mails
            if (sessionState.ContainsKey("OutMails") && sessionState.ContainsKey("OutMailBlocks") && sessionState.ContainsKey("MailProposals"))
            {
                List<WinLinkMail> proposedMails = (List<WinLinkMail>)sessionState["OutMails"];
                List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)sessionState["OutMailBlocks"];
                string[] proposalResponses = ParseProposalResponses((string)sessionState["MailProposals"]);

                // Look at proposal responses and update the mails in the store
                if (proposalResponses.Length == proposedMails.Count)
                {
                    for (int j = 0; j < proposalResponses.Length; j++)
                    {
                        if ((proposalResponses[j] == "Y") || (proposalResponses[j] == "N"))
                        {
                            // Move this mail to Sent mailbox using the broker event
                            string mid = proposedMails[j].MID;
                            broker.Dispatch(0, "MailMove", new { MID = mid, Mailbox = "Sent" }, store: false);
                        }
                    }
                }
            }
        }

        // Process stream data (unified for both TCP and X25)
        private void ProcessStream(byte[] data)
        {
            if ((data == null) || (data.Length == 0)) return;

            // This is embedded mail sent in compressed format
            if (sessionState.ContainsKey("wlMailBinary"))
            {
                MemoryStream blocks = (MemoryStream)sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                StateMessage("Receiving mail, " + blocks.Length + ((blocks.Length < 2) ? " byte" : " bytes"));
                if (ExtractMail(blocks) == true)
                {
                    // We are done with the mail reception
                    sessionState.Remove("wlMailBinary");
                    sessionState.Remove("wlMailBlocks");
                    sessionState.Remove("wlMailProp");
                    TransportSend("FF");
                    
                    // Close TCP session after sending FF
                    if (transportType == TransportType.TCP)
                    {
                        DisconnectTcp();
                    }
                }
                return;
            }

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                
                // Add to debug history (incoming traffic)
                AddToDebugHistory(remoteAddress, false, str, false);
                // Dispatch traffic via broker (device 1 for non-persistent state)
                broker.Dispatch(1, "WinlinkTraffic", new { Address = remoteAddress, Outgoing = false, Data = str }, store: false);

                // Handle TCP callsign prompt
                if ((transportType == TransportType.TCP) && str.Trim().Equals("Callsign :", StringComparison.OrdinalIgnoreCase))
                {
                    // Get callsign and stationId from broker (device 0 for persistent settings)
                    string callsign = broker.GetValue<string>(0, "CallSign", "");
                    int stationId = broker.GetValue<int>(0, "StationId", 0);
                    bool useStationId = broker.GetValue<int>(0, "WinlinkUseStationId", 0) == 1;
                    
                    string callsignResponse = callsign;
                    if (useStationId && stationId > 0) { callsignResponse += "-" + stationId; }
                    callsignResponse += "\r";
                    TransportSend(callsignResponse);
                    StateMessage("Sent callsign: " + callsignResponse.Trim());
                    continue;
                }

                // Handle TCP password prompt
                if ((transportType == TransportType.TCP) && str.Trim().Equals("Password :", StringComparison.OrdinalIgnoreCase))
                {
                    // Send "CMSTelnet" as the password
                    TransportSend("CMSTelnet\r");
                    continue;
                }

                if (str.EndsWith(">") && !sessionState.ContainsKey("SessionStart"))
                {
                    // Only do this once at the start of the session
                    sessionState["SessionStart"] = 1;

                    // Build the big response (Info + Auth + Proposals)
                    StringBuilder sb = new StringBuilder();

                    // Send Information
                    sb.Append("[RMS Express-1.7.28.0-B2FHM$]\r");

                    // Send Authentication
                    if (sessionState.ContainsKey("WinlinkAuth"))
                    {
                        // Get password from broker (device 0 for persistent settings)
                        string winlinkPassword = broker.GetValue<string>(0, "WinlinkPassword", "");
                        string authResponse = WinlinkSecurity.SecureLoginResponse((string)sessionState["WinlinkAuth"], winlinkPassword);
                        if (!string.IsNullOrEmpty(winlinkPassword)) { sb.Append(";PR: " + authResponse + "\r"); }
                        StateMessage("Authenticating...");
                    }

                    // Get mails from MailStore via DataBroker handler
                    MailStore mailStore = DataBroker.GetDataHandler<MailStore>("MailStore");
                    List<WinLinkMail> mails = mailStore?.GetAllMails() ?? new List<WinLinkMail>();

                    // Send proposals with checksum
                    List<WinLinkMail> proposedMails = new List<WinLinkMail>();
                    List<List<Byte[]>> proposedMailsBinary = new List<List<Byte[]>>();
                    int checksum = 0, mailSendCount = 0;
                    foreach (WinLinkMail mail in mails)
                    {
                        if ((mail.Mailbox != "Outbox") || string.IsNullOrEmpty(mail.MID) || (mail.MID.Length != 12)) continue;

                        int uncompressedSize, compressedSize;
                        List<Byte[]> blocks = WinLinkMail.EncodeMailToBlocks(mail, out uncompressedSize, out compressedSize);
                        if (blocks != null)
                        {
                            proposedMails.Add(mail);
                            proposedMailsBinary.Add(blocks);
                            string proposal = "FC EM " + mail.MID + " " + uncompressedSize + " " + compressedSize + " 0\r";
                            sb.Append(proposal);
                            byte[] proposalBin = ASCIIEncoding.ASCII.GetBytes(proposal);
                            for (int i = 0; i < proposalBin.Length; i++) { checksum += proposalBin[i]; }
                            mailSendCount++;
                        }
                    }
                    if (mailSendCount > 0)
                    {
                        // Send proposal checksum
                        checksum = (-checksum) & 0xFF;
                        sb.Append("F> " + checksum.ToString("X2") + "\r");
                        TransportSend(sb.ToString());
                        sessionState["OutMails"] = proposedMails;
                        sessionState["OutMailBlocks"] = proposedMailsBinary;
                        StateMessage("Proposing " + mailSendCount + " mail(s) to send...");
                    }
                    else
                    {
                        // No mail proposals sent, give a chance to the server to send us mails.
                        sb.Append("FF\r");
                        TransportSend(sb.ToString());
                        StateMessage("Checking for new mail...");
                    }
                }
                else
                {
                    string key = str, value = "";
                    int i = str.IndexOf(' ');
                    if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                    // Get password from broker (device 0 for persistent settings)
                    string winlinkPassword = broker.GetValue<string>(0, "WinlinkPassword", "");
                    
                    if ((key == ";PQ:") && (!string.IsNullOrEmpty(winlinkPassword)))
                    {   // Winlink Authentication Request
                        sessionState["WinlinkAuth"] = value;
                    }
                    else if (key == "FS") // "FS YY"
                    {   // Winlink Mail Transfer Approvals
                        if (sessionState.ContainsKey("OutMails") && sessionState.ContainsKey("OutMailBlocks"))
                        {
                            List<WinLinkMail> proposedMails = (List<WinLinkMail>)sessionState["OutMails"];
                            List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)sessionState["OutMailBlocks"];
                            sessionState["MailProposals"] = value;

                            // Look at proposal responses
                            int sentMails = 0;
                            string[] proposalResponses = ParseProposalResponses(value);
                            if (proposalResponses.Length == proposedMails.Count)
                            {
                                int totalSize = 0;
                                for (int j = 0; j < proposalResponses.Length; j++)
                                {
                                    if (proposalResponses[j] == "Y")
                                    {
                                        sentMails++;
                                        foreach (byte[] block in proposedMailsBinary[j]) { TransportSend(block); totalSize += block.Length; }
                                    }
                                }
                                if (sentMails == 1) { StateMessage("Sending mail, " + totalSize + " bytes..."); }
                                else if (sentMails > 1) { StateMessage("Sending " + sentMails + " mails, " + totalSize + " bytes..."); }
                                else
                                {
                                    // Winlink Session Close
                                    UpdateEmails();
                                    StateMessage("No emails to transfer.");
                                    TransportSend("FF\r");
                                }
                            }
                            else
                            {
                                // Winlink Session Close
                                StateMessage("Incorrect proposal response.");
                                TransportSend("FQ\r");
                            }
                        }
                        else
                        {
                            // Winlink Session Close
                            StateMessage("Unexpected proposal response.");
                            TransportSend("FQ\r");
                        }
                    }
                    else if (key == "FF")
                    {
                        // Winlink Session Close
                        UpdateEmails();
                        TransportSend("FQ\r");
                    }
                    else if (key == "FC")
                    {
                        // Winlink Mail Proposal
                        List<string> proposals;
                        if (sessionState.ContainsKey("wlMailProp")) { proposals = (List<string>)sessionState["wlMailProp"]; } else { proposals = new List<string>(); }
                        proposals.Add(value);
                        sessionState["wlMailProp"] = proposals;
                    }
                    else if (key == "F>")
                    {
                        // Winlink Mail Proposals completed, we need to respond
                        if ((sessionState.ContainsKey("wlMailProp")) && (!sessionState.ContainsKey("wlMailBinary")))
                        {
                            List<string> proposals = (List<string>)sessionState["wlMailProp"];
                            List<string> proposals2 = new List<string>();
                            if ((proposals != null) && (proposals.Count > 0))
                            {
                                // Compute the proposal checksum
                                int checksum = 0;
                                foreach (string proposal in proposals)
                                {
                                    byte[] proposalBin = ASCIIEncoding.ASCII.GetBytes("FC " + proposal + "\r");
                                    for (int j = 0; j < proposalBin.Length; j++) { checksum += proposalBin[j]; }
                                }
                                checksum = (-checksum) & 0xFF;
                                if (checksum.ToString("X2") == value)
                                {
                                    // Build a response
                                    string response = "";
                                    int acceptedProposalCount = 0;
                                    foreach (string proposal in proposals)
                                    {
                                        string[] proposalSplit = proposal.Split(' ');
                                        if ((proposalSplit.Length >= 5) && (proposalSplit[0] == "EM") && (proposalSplit[1].Length == 12))
                                        {
                                            int mFullLen, mCompLen, mUnknown;
                                            if (
                                                int.TryParse(proposalSplit[2], out mFullLen) &&
                                                int.TryParse(proposalSplit[3], out mCompLen) &&
                                                int.TryParse(proposalSplit[4], out mUnknown)
                                            )
                                            {
                                                // Check if we already have this email
                                                if (WeHaveEmail(proposalSplit[1]))
                                                {
                                                    response += "N";
                                                }
                                                else
                                                {
                                                    response += "Y";
                                                    proposals2.Add(proposal);
                                                    acceptedProposalCount++;
                                                }
                                            }
                                            else { response += "H"; }
                                        }
                                        else { response += "H"; }
                                    }
                                    TransportSend("FS " + response + "\r");
                                    if (acceptedProposalCount > 0)
                                    {
                                        sessionState["wlMailBinary"] = new MemoryStream();
                                        sessionState["wlMailProp"] = proposals2;
                                    }
                                }
                                else
                                {
                                    // Checksum failed
                                    StateMessage("Checksum Failed");
                                    if (transportType == TransportType.TCP)
                                    {
                                        DisconnectTcp();
                                    }
                                }
                            }
                        }
                    }
                    else if (key == "FQ")
                    {   // Winlink Session Close
                        UpdateEmails();
                        if (transportType == TransportType.TCP)
                        {
                            DisconnectTcp();
                        }
                    }
                }
            }
        }

        private bool ExtractMail(MemoryStream blocks)
        {
            if (sessionState.ContainsKey("wlMailProp") == false) return false;
            List<string> proposals = (List<string>)sessionState["wlMailProp"];
            if ((proposals == null) || (blocks == null)) return false;
            if ((proposals.Count == 0) || (blocks.Length == 0)) return true;

            // Decode the proposal
            string[] proposalSplit = proposals[0].Split(' ');
            string MID = proposalSplit[1];
            int mFullLen, mCompLen;
            int.TryParse(proposalSplit[2], out mFullLen);
            int.TryParse(proposalSplit[3], out mCompLen);

            // See what we got
            bool fail;
            int dataConsumed = 0;
            WinLinkMail mail = WinLinkMail.DecodeBlocksToEmail(blocks.ToArray(), out fail, out dataConsumed);
            if (fail) { StateMessage("Failed to decode mail."); return true; }
            if (mail == null) return false;
            if (dataConsumed > 0)
            {
                if (dataConsumed >= blocks.Length)
                {
                    blocks.SetLength(0);
                }
                else
                {
                    byte[] newBlocks = new byte[blocks.Length - dataConsumed];
                    Array.Copy(blocks.ToArray(), dataConsumed, newBlocks, 0, newBlocks.Length);
                    blocks.SetLength(0);
                    blocks.Write(newBlocks, 0, newBlocks.Length);
                }
            }
            proposals.RemoveAt(0);

            // Set the mailbox to Inbox for received mail
            mail.Mailbox = "Inbox";

            // Add the received mail to the persistent store using broker event
            // The MailStore will check for duplicates internally
            broker.Dispatch(0, "MailAdd", mail, store: false);

            StateMessage("Got mail for " + mail.To + ".");

            return (proposals.Count == 0);
        }

        private bool WeHaveEmail(string mid)
        {
            // Check if mail exists using MailStore via DataBroker handler
            MailStore mailStore = DataBroker.GetDataHandler<MailStore>("MailStore");
            return mailStore?.MailExists(mid) ?? false;
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                // Disconnect if connected
                if (currentState != ConnectionState.DISCONNECTED)
                {
                    if (transportType == TransportType.TCP)
                    {
                        DisconnectTcp();
                    }
                    else if (transportType == TransportType.X25)
                    {
                        DisposeAX25Session();
                    }
                }
                
                // Make sure to unlock any radio
                UnlockRadio();
                
                // Dispose the broker client
                broker?.Dispose();
                broker = null;
                
                _disposed = true;
            }
        }
    }
}