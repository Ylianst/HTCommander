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

// Protocol: AGW Packet Engine (AGWPE) TCP API
// Reference: https://www.on7lds.net/42/sites/default/files/AGWPEAPI.HTM

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using static System.Collections.Specialized.BitVector32;

namespace HTCommander
{
    /// <summary>
    /// Represents the 36-byte AGW PE API frame header.
    /// </summary>
    public class AgwpeFrame
    {
        public byte Port { get; set; }
        public byte[] Reserved1 { get; set; } = new byte[3];
        public byte DataKind { get; set; }
        public byte Reserved2 { get; set; }
        public byte PID { get; set; }
        public byte Reserved3 { get; set; }
        public string CallFrom { get; set; }
        public string CallTo { get; set; }
        public uint DataLen { get; set; }
        public uint User { get; set; }
        public byte[] Data { get; set; } = Array.Empty<byte>();

        public static async Task<AgwpeFrame> ReadAsync(NetworkStream stream, CancellationToken ct)
        {
            byte[] header = new byte[36];
            int read = 0;
            while (read < header.Length)
            {
                int n = await stream.ReadAsync(header, read, header.Length - read, ct);
                if (n == 0) throw new IOException("Disconnected");
                read += n;
            }

            var frame = new AgwpeFrame
            {
                Port = header[0],
                Reserved1 = header.Skip(1).Take(3).ToArray(),
                DataKind = header[4],
                Reserved2 = header[5],
                PID = header[6],
                Reserved3 = header[7],
                CallFrom = Encoding.ASCII.GetString(header, 8, 10).TrimEnd('\0', ' '),
                CallTo = Encoding.ASCII.GetString(header, 18, 10).TrimEnd('\0', ' '),
                DataLen = BitConverter.ToUInt32(header, 28),
                User = BitConverter.ToUInt32(header, 32)
            };

            if (frame.DataLen > 0)
            {
                frame.Data = new byte[frame.DataLen];
                int offset = 0;
                while (offset < frame.Data.Length)
                {
                    int n = await stream.ReadAsync(frame.Data, offset, (int)frame.DataLen - offset, ct);
                    if (n == 0) throw new IOException("Disconnected before payload complete");
                    offset += n;
                }
            }

            return frame;
        }

        public byte[] ToBytes()
        {
            byte[] buffer = new byte[36 + (Data?.Length ?? 0)];
            buffer[0] = Port;
            Array.Copy(Reserved1, 0, buffer, 1, 3);
            buffer[4] = DataKind;
            buffer[5] = Reserved2;
            buffer[6] = PID;
            buffer[7] = Reserved3;

            Encoding.ASCII.GetBytes((CallFrom ?? "").PadRight(10, '\0'), 0, 10, buffer, 8);
            Encoding.ASCII.GetBytes((CallTo ?? "").PadRight(10, '\0'), 0, 10, buffer, 18);

            BitConverter.GetBytes(Data?.Length ?? 0).CopyTo(buffer, 28);
            BitConverter.GetBytes(User).CopyTo(buffer, 32);

            if (Data != null && Data.Length > 0)
                Array.Copy(Data, 0, buffer, 36, Data.Length);

            return buffer;
        }
    }


    /// <summary>
    /// Manages the send/receive logic for a single connected TCP client.
    /// Handles message framing (4-byte length prefix) and queued sending.
    /// </summary>
    public class TcpClientHandler : IDisposable
    {
        private readonly TcpClient _client;
        private readonly NetworkStream _stream;
        private readonly AgwpeSocketServer _server;
        private readonly ConcurrentQueue<byte[]> _sendQueue = new ConcurrentQueue<byte[]>();
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private readonly Task _sendTask;
        private readonly Task _receiveTask;

        public Guid Id { get; }
        public IPEndPoint EndPoint => (IPEndPoint)_client.Client.RemoteEndPoint;

        public bool SendMonitoringFrames = false;

        public TcpClientHandler(TcpClient client, AgwpeSocketServer server)
        {
            Id = Guid.NewGuid();
            _client = client;
            _stream = client.GetStream();
            _server = server;

            // Start dedicated tasks for sending and receiving
            _sendTask = Task.Run(ProcessSendQueueAsync, _cts.Token);
            _receiveTask = Task.Run(ReceiveLoopAsync, _cts.Token);
        }

        /// <summary>
        /// Enqueues a message to be sent to this client.
        /// </summary>
        public void EnqueueSend(byte[] data)
        {
            _sendQueue.Enqueue(data);
        }

        /// <summary>
        /// Processes the send queue, sending messages one by one.
        /// </summary>
        private async Task ProcessSendQueueAsync()
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    if (_sendQueue.TryDequeue(out var data))
                    {
                        await _stream.WriteAsync(data, 0, data.Length, _cts.Token);
                    }
                    else
                    {
                        await Task.Delay(50, _cts.Token);
                    }
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (IOException)
                {
                    Disconnect();
                    break;
                }
                catch (Exception ex)
                {
                    _server.OnDebugMessage($"AGWPE error sending to {Id}: {ex.Message}");
                    Disconnect();
                    break;
                }
            }
        }

        /// <summary>
        /// Listens for incoming data from the client.
        /// </summary>
        private async Task ReceiveLoopAsync()
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    var frame = await AgwpeFrame.ReadAsync(_stream, _cts.Token);

                    _server.OnAgwpeFrameReceived(Id, frame);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (IOException)
                {
                    break; // disconnected
                }
                catch (Exception ex)
                {
                    _server.OnDebugMessage($"AGWPE error receiving from {Id}: {ex.Message}");
                    break;
                }
            }

            Disconnect();
        }

        /// <summary>
        /// Disconnects the client and signals the server to remove it.
        /// </summary>
        public void Disconnect()
        {
            if (!_cts.IsCancellationRequested)
            {
                _cts.Cancel();
            }
            _server.RemoveClient(Id);
        }

        public void Dispose()
        {
            Disconnect();
            _stream?.Dispose();
            _client?.Dispose();
            _cts?.Dispose();
        }
    }

    /// <summary>
    /// A TCP server that listens for clients, manages connections, and broadcasts messages.
    /// </summary>
    public class AgwpeSocketServer
    {
        public event Action<Guid> ClientConnected;
        public event Action<Guid> ClientDisconnected;
        public event Action<Guid, byte[]> MessageReceived;
        public event Action<string> DebugMessage;

        private readonly MainForm parent;
        private readonly TcpListener _listener;
        private readonly ConcurrentDictionary<Guid, TcpClientHandler> _clients = new ConcurrentDictionary<Guid, TcpClientHandler>();
        private readonly ConcurrentDictionary<Guid, HashSet<string>> _registeredCallsigns = new ConcurrentDictionary<Guid, HashSet<string>>();
        private CancellationTokenSource _cts;
        private Task _serverTask;
        public string SessionTo = null;
        public string SessionFrom = null;

        public int Port { get; }

        public AgwpeSocketServer(MainForm parent, int port)
        {
            this.parent = parent;
            Port = port;
            _listener = new TcpListener(IPAddress.Any, Port);
        }

        public void Start()
        {
            if (_serverTask != null && !_serverTask.IsCompleted)
            {
                OnDebugMessage("AGWPE server is already running.");
                return;
            }

            OnDebugMessage("AGWPE server starting...");
            _cts = new CancellationTokenSource();
            _listener.Start();
            _serverTask = Task.Run(() => AcceptClientsAsync(_cts.Token), _cts.Token);
        }

        public void Stop()
        {
            if (_cts == null)
            {
                OnDebugMessage("AGWPE server is not running.");
                return;
            }

            OnDebugMessage("Stopping TNC server...");
            _cts.Cancel();
            _listener.Stop();

            try
            {
                _serverTask?.Wait(TimeSpan.FromSeconds(3));
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                OnDebugMessage($"AGWPE error waiting for server task: {ex.Message}");
            }

            var clientList = _clients.Values.ToList();
            foreach (var client in clientList) { client.Dispose(); }

            _clients.Clear();
            _cts.Dispose();
            _cts = null;
            _serverTask = null;
            OnDebugMessage("AGWPE server stopped.");
        }

        private async Task AcceptClientsAsync(CancellationToken cancellationToken)
        {
            OnDebugMessage($"AGWPE server started on port {Port}.");
            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    TcpClient client = await _listener.AcceptTcpClientAsync();

                    var clientHandler = new TcpClientHandler(client, this);
                    if (_clients.TryAdd(clientHandler.Id, clientHandler))
                    {
                        ClientConnected?.Invoke(clientHandler.Id);
                        OnDebugMessage($"AGWPE client connected: {clientHandler.EndPoint}");
                    }
                    else
                    {
                        OnDebugMessage($"AGWPE failed to add client.");
                        client.Close();
                    }
                }
            }
            catch (SocketException ex) when (ex.SocketErrorCode == SocketError.Interrupted)
            {
                // Expected when _listener.Stop() is called.
            }
            catch (OperationCanceledException)
            {
                // Expected when the cancellation token is triggered.
            }
            catch (Exception ex)
            {
                OnDebugMessage($"AGWPE Server accept loop error: {ex.Message}");
            }
            finally
            {
                OnDebugMessage("AGWPE Server is no longer accepting new clients.");
            }
        }

        public void BroadcastFrame(TncDataFragment frame)
        {
            AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
            if ((p == null) || (p.addresses.Count < 2) || (p.type != AX25Packet.FrameType.U_FRAME_UI)) return; // Invalid packet, ignore
            DateTime now = DateTime.Now;
            string str = "1:Fm " + p.addresses[1].CallSignWithId + " To " + p.addresses[0].CallSignWithId + " <UI pid=" + p.pid + " Len=" + p.data.Length + " >[" + now.Hour.ToString("D2") + ":" + now.Minute.ToString("D2") + ":" + now.Second.ToString("D2") + "]\r" + p.dataStr;
            if (!str.EndsWith("\r") && !str.EndsWith("\n")) { str += "\r"; }
            AgwpeFrame aframe = new AgwpeFrame()
            {
                Port = 0,
                DataKind = 0x55, // 'U',
                CallFrom = p.addresses[1].CallSignWithId,
                CallTo = p.addresses[0].CallSignWithId,
                DataLen = (uint)p.data.Length,
                Data = ASCIIEncoding.ASCII.GetBytes(str)
            };
            BroadcastFrame(aframe);
        }

        public void BroadcastFrame(AgwpeFrame frame)
        {
            var data = frame.ToBytes();
            foreach (var client in _clients.Values)
            {
                if (client.SendMonitoringFrames) { client.EnqueueSend(data); }
            }
        }

        internal void OnDebugMessage(string message) { parent.Debug(message); }

        /// <summary>
        /// Handles the raw byte message received from a client and processes it as an AGW frame.
        /// </summary>
        internal void OnMessageReceived(Guid clientId, byte[] message)
        {
            if (message == null || message.Length < 36)
            {
                OnDebugMessage("AGWPE Received an invalid or empty message.");
                return;
            }

            try
            {
                // Parse directly into AgwpeFrame
                // No Parse() method exists, use ReadAsync instead normally,
                // but here we can just log that this path shouldn't be used anymore
                OnDebugMessage("AGWPE OnMessageReceived should not be used directly with AGW frames.");
            }
            catch (Exception ex)
            {
                OnDebugMessage($"AGWPE Error parsing AGW frame: {ex.Message}");
            }
        }

        /// <summary>
        /// Sends an AGW frame back to a specific client.
        /// </summary>
        private void SendToClient(Guid clientId, byte[] data)
        {
            if (_clients.TryGetValue(clientId, out var clientHandler))
            {
                clientHandler.EnqueueSend(data);
                OnDebugMessage($"AGWPE sent AGW response to client {clientId}.");
            }
            else
            {
                OnDebugMessage($"AGWPE Failed to find client {clientId} to send response.");
            }
        }

        internal void OnAgwpeFrameReceived(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"AGWPE received frame: Kind={(char)frame.DataKind} From={frame.CallFrom} To={frame.CallTo} Len={frame.DataLen}");
            ProcessAgwCommand(clientId, frame);
        }

        public void SendSessionDataToClient(Guid clientId, byte[] data)
        {
            if ((data == null) || (data.Length == 0)) return;

            // Create an AGWPE frame for the session data
            var frame = new AgwpeFrame
            {
                Port = 0, // Default port
                DataKind = (byte)'D', // Data frame
                CallFrom = SessionTo,
                CallTo = SessionFrom,
                DataLen = (uint)data.Length,
                Data = data
            };
            SendFrameToClient(clientId, frame);
        }

        // Signal we connected to another station
        public void SendSessionConnectToClient(Guid clientId)
        {
            // Create an AGWPE frame for the session connection
            var frame = new AgwpeFrame
            {
                Port = 0, // Default port
                DataKind = (byte)'C', // Connection
                CallFrom = SessionTo,
                CallTo = SessionFrom,
                Data = ASCIIEncoding.ASCII.GetBytes("*** CONNECTED With " + SessionTo)
            };
            SendFrameToClient(clientId, frame);
        }

        // Signal that another station connected to us
        public void SendSessionConnectToClientEx(Guid clientId)
        {
            // Create an AGWPE frame for the session connection
            var frame = new AgwpeFrame
            {
                Port = 0, // Default port
                DataKind = (byte)'C', // Connection
                CallFrom = SessionTo,
                CallTo = SessionFrom,
                Data = ASCIIEncoding.ASCII.GetBytes("*** CONNECTED To Station " + SessionFrom)
            };
            SendFrameToClient(clientId, frame);
        }

        public void SendSessionDisconnectToClient(Guid clientId)
        {
            // Create an AGWPE frame for the session disconnect
            var frame = new AgwpeFrame
            {
                Port = 0, // Default port
                DataKind = (byte)'d', // Disconnect
                CallFrom = SessionTo,
                CallTo = SessionFrom
            };
            SendFrameToClient(clientId, frame);
        }

        private void SendFrameToClient(Guid clientId, AgwpeFrame frame)
        {
            if (_clients.TryGetValue(clientId, out var client))
            {
                client.EnqueueSend(frame.ToBytes());
            }
        }

        /// <summary>
        /// Processes a parsed AGW command frame and returns a response.
        /// This is the core logic for the TNC side of the API.
        /// </summary>
        internal void ProcessAgwCommand(Guid clientId, AgwpeFrame frame)
        {
            switch ((char)frame.DataKind)
            {
                case 'G': // Get channel info
                    {
                        OnDebugMessage($"AGWPE client requested channel info");

                        // Example reply with dummy values
                        var channelInfo = Encoding.UTF8.GetBytes("1;Port1 Handi-Talky Commander;");
                        var reply = new AgwpeFrame
                        {
                            DataKind = (byte)'G',
                            Data = channelInfo
                        };
                        SendFrame(clientId, reply);
                    }
                    break;
                case 'X': // Register application
                    {
                        bool success = false;
                        if (!string.IsNullOrWhiteSpace(frame.CallFrom))
                        {
                            Guid? cid = GetClientIdByCallsign(frame.CallFrom);
                            if ((cid == null) || (cid == Guid.Empty))
                            {
                                var set = _registeredCallsigns.GetOrAdd(clientId, _ => new HashSet<string>());
                                lock (set) { set.Add(frame.CallFrom); }
                                OnDebugMessage($"AGWPE client registered callsign '{frame.CallFrom}'");
                                success = true;
                            }
                        }
                        
                        // Return confirmation
                        byte[] data = new byte[1];
                        data[0] = (byte)(success ? 1 : 0);
                        AgwpeFrame aframe = new AgwpeFrame()
                        {
                            Port = frame.Port,
                            DataKind = (byte)'X', // Register application
                            CallFrom = frame.CallFrom,
                            DataLen = (uint)data.Length,
                            Data = data
                        };
                        SendFrame(clientId, aframe);
                    }
                    break;
                case 'x': // Disconnect / un-register
                    {
                        if (!string.IsNullOrWhiteSpace(frame.CallFrom))
                        {
                            if (_registeredCallsigns.TryGetValue(clientId, out var set))
                            {
                                lock (set) { set.Remove(frame.CallFrom); }
                                OnDebugMessage($"AGWPE client unregistered callsign '{frame.CallFrom}'");
                            }
                        }
                    }
                    break;
                case 'D': // Data frame from app
                    {
                        if ((parent.radio.State == Radio.RadioState.Connected) && (parent.activeStationLock != null) && (parent.activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE) && (parent.session.CurrentState == AX25Session.ConnectionState.CONNECTED))
                        {
                            OnDebugMessage($"AGWPE data frame from {frame.CallFrom} to {frame.CallTo}, {frame.DataLen} bytes.");
                            parent.session.Send(frame.Data);
                        }
                    }
                    break;
                case 'M': // Send UNPROTO Information (from client to radio)
                    {
                        OnDebugMessage($"AGWPE M frame (Send UNPROTO) from {frame.CallFrom} to {frame.CallTo}, {frame.DataLen} bytes");
                        if (parent.radio.State != Radio.RadioState.Connected) return;
                        // Construct AX25Packet for UNPROTO (UI) frame
                        var addresses = new System.Collections.Generic.List<AX25Address>
                        {
                            AX25Address.GetAddress(frame.CallTo),
                            AX25Address.GetAddress(frame.CallFrom)
                        };
                        var p = new AX25Packet(addresses, frame.Data, DateTime.Now);
                        p.channel_id = parent.radio.HtStatus.curr_ch_id;
                        p.channel_name = parent.radio.currentChannelName;
                        parent.radio.TransmitTncData(p); // Send to radio

                        // Return the frame back to the client
                        DateTime now = DateTime.Now;
                        string str = (frame.Port + 1) + ":Fm " + p.addresses[1].CallSignWithId + " To " + p.addresses[0].CallSignWithId + " <UI pid=" + p.pid + " Len=" + p.data.Length + " >[" + now.Hour.ToString("D2") + ":" + now.Minute.ToString("D2") + ":" + now.Second.ToString("D2") + "]\r" + ASCIIEncoding.ASCII.GetString(frame.Data);
                        if (!str.EndsWith("\r") && !str.EndsWith("\n")) { str += "\r"; }
                        AgwpeFrame aframe = new AgwpeFrame()
                        {
                            Port = frame.Port,
                            DataKind = (byte)'T', // Send UNPROTO response
                            CallFrom = p.addresses[0].CallSignWithId,
                            CallTo = p.addresses[1].CallSignWithId,
                            DataLen = (uint)p.data.Length,
                            Data = ASCIIEncoding.ASCII.GetBytes(str)
                        };
                        SendFrame(clientId, aframe);
                    }
                    break;
                case 'C': // AX25 Session Connect Request
                    {
                        OnDebugMessage($"AGWPE session connect request.");

                        if ((parent.radio.State != Radio.RadioState.Connected) || (parent.activeStationLock != null))
                        {
                            OnDebugMessage($"AGWPE cannot connect, radio is not connected or busy.");
                            // Disconnect
                            var reply = new AgwpeFrame
                            {
                                Port = frame.Port,
                                DataKind = (byte)'d', // disconnect
                                CallFrom = frame.CallTo,
                                CallTo = frame.CallFrom
                            };
                            SendFrame(clientId, reply);
                            return;
                        }

                        // Save AX25 session to/from
                        SessionFrom = frame.CallFrom;
                        SessionTo = frame.CallTo;

                        // Lock the station to the current channel
                        StationInfoClass station = new StationInfoClass();
                        station.StationType = StationInfoClass.StationTypes.AGWPE;
                        station.TerminalProtocol = StationInfoClass.TerminalProtocols.X25Session;
                        station.Callsign = frame.CallTo;
                        station.AgwpeClientId = clientId; // Associate with this TNC client
                        parent.ActiveLockToStation(station, parent.radio.Settings.channel_a);
                        break;
                    }
                case 'd': // AX25 Session Disconnect Request
                    {
                        OnDebugMessage($"AGWPE session disconnect request.");

                        // Release the station lock
                        if ((parent.activeStationLock != null) && (parent.activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE) && (parent.activeStationLock.AgwpeClientId == clientId))
                        {
                            // This will also disconnect any AX25 session.
                            parent.ActiveLockToStation(null, -1);
                        }

                        // Confirm the disconnection
                        var reply = new AgwpeFrame
                        {
                            Port = frame.Port,
                            DataKind = (byte)'d', // disconnect
                            CallFrom = frame.CallTo,
                            CallTo = frame.CallFrom
                        };
                        SendFrame(clientId, reply);
                    }
                    break;
                case 'm': // Toggle monitoring frames
                    {
                        if (_clients.TryGetValue(clientId, out TcpClientHandler clientHandler))
                        {
                            clientHandler.SendMonitoringFrames = !clientHandler.SendMonitoringFrames;
                            if (clientHandler.SendMonitoringFrames) OnDebugMessage($"AGWPE enable monitoring frames");
                            else OnDebugMessage($"AGWPE disable monitoring frames");
                        }
                        break;
                    }
                default:
                    OnDebugMessage($"AGWPE unknown data kind '{(char)frame.DataKind}' (0x{frame.DataKind:X2})");
                    break;
            }
        }

        private void SendFrame(Guid clientId, AgwpeFrame frame)
        {
            if (_clients.TryGetValue(clientId, out var client))
            {
                client.EnqueueSend(frame.ToBytes());
            }
        }

        /// <summary>
        /// Returns the clientId for a registered callsign, or null if not found.
        /// </summary>
        public Guid? GetClientIdByCallsign(string callsign)
        {
            foreach (var kvp in _registeredCallsigns)
            {
                lock (kvp.Value)
                {
                    if (kvp.Value.Contains(callsign))
                        return kvp.Key;
                }
            }
            return null;
        }

        /// <summary>
        /// Returns the total number of registered clients.
        /// </summary>
        public int GetRegisteredClientCount()
        {
            return _registeredCallsigns.Count;
        }

        internal void RemoveClient(Guid clientId)
        {
            // Remove all registrations for this client
            _registeredCallsigns.TryRemove(clientId, out _);
            if (_clients.TryRemove(clientId, out var clientHandler))
            {
                OnDebugMessage($"AGWPE client disconnected: {clientId}");
                ClientDisconnected?.Invoke(clientId);
            }
        }
    }
}