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
using System.IO;
using System.Net;
using System.Linq;
using System.Text;
using System.Threading;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Collections.Concurrent;

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
        private readonly TncSocketServer _server;
        private readonly ConcurrentQueue<byte[]> _sendQueue = new ConcurrentQueue<byte[]>();
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private readonly Task _sendTask;
        private readonly Task _receiveTask;

        public Guid Id { get; }
        public IPEndPoint EndPoint => (IPEndPoint)_client.Client.RemoteEndPoint;

        public bool SendMonitoringFrames = false;

        public TcpClientHandler(TcpClient client, TncSocketServer server)
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
                    _server.OnDebugMessage($"TNC error sending to {Id}: {ex.Message}");
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
                    _server.OnDebugMessage($"TNC error receiving from {Id}: {ex.Message}");
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
    public class TncSocketServer
    {
        public event Action<Guid> ClientConnected;
        public event Action<Guid> ClientDisconnected;
        public event Action<Guid, byte[]> MessageReceived;
        public event Action<string> DebugMessage;

        private readonly MainForm parent;
        private readonly TcpListener _listener;
        private readonly ConcurrentDictionary<Guid, TcpClientHandler> _clients = new ConcurrentDictionary<Guid, TcpClientHandler>();
        private CancellationTokenSource _cts;
        private Task _serverTask;

        public int Port { get; }

        public TncSocketServer(MainForm parent, int port)
        {
            this.parent = parent;
            Port = port;
            _listener = new TcpListener(IPAddress.Any, Port);
        }

        public void Start()
        {
            if (_serverTask != null && !_serverTask.IsCompleted)
            {
                OnDebugMessage("TNC server is already running.");
                return;
            }

            OnDebugMessage("TNC server starting...");
            _cts = new CancellationTokenSource();
            _listener.Start();
            _serverTask = Task.Run(() => AcceptClientsAsync(_cts.Token), _cts.Token);
        }

        public void Stop()
        {
            if (_cts == null)
            {
                OnDebugMessage("TNC server is not running.");
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
                OnDebugMessage($"TNC error waiting for server task: {ex.Message}");
            }

            var clientList = _clients.Values.ToList();
            foreach (var client in clientList) { client.Dispose(); }

            _clients.Clear();
            _cts.Dispose();
            _cts = null;
            _serverTask = null;
            OnDebugMessage("TNC server stopped.");
        }

        private async Task AcceptClientsAsync(CancellationToken cancellationToken)
        {
            OnDebugMessage($"TNC server started on port {Port}.");
            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    TcpClient client = await _listener.AcceptTcpClientAsync();

                    var clientHandler = new TcpClientHandler(client, this);
                    if (_clients.TryAdd(clientHandler.Id, clientHandler))
                    {
                        ClientConnected?.Invoke(clientHandler.Id);
                        OnDebugMessage($"TNC client connected: {clientHandler.EndPoint}");
                    }
                    else
                    {
                        OnDebugMessage($"TNC failed to add client.");
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
                OnDebugMessage($"TNC Server accept loop error: {ex.Message}");
            }
            finally
            {
                OnDebugMessage("TNC Server is no longer accepting new clients.");
            }
        }

        public void BroadcastFrame(TncDataFragment frame)
        {
            AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
            if ((p == null) || (p.addresses.Count < 2)) return; // Invalid packet, ignore
            DateTime now = DateTime.Now;
            string str = "1:Fm " + p.addresses[1].CallSignWithId + " To " + p.addresses[0].CallSignWithId + " <UI pid=" + p.pid + " Len=" + p.data.Length + " >[" + now.Hour + ":" + now.Minute + ":" + now.Second + "]\r" + p.dataStr;
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
                OnDebugMessage("TNC Received an invalid or empty message.");
                return;
            }

            try
            {
                // Parse directly into AgwpeFrame
                // No Parse() method exists, use ReadAsync instead normally,
                // but here we can just log that this path shouldn't be used anymore
                OnDebugMessage("TNC OnMessageReceived should not be used directly with AGW frames.");
            }
            catch (Exception ex)
            {
                OnDebugMessage($"TNC Error parsing AGW frame: {ex.Message}");
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
                OnDebugMessage($"TNC sent AGW response to client {clientId}.");
            }
            else
            {
                OnDebugMessage($"TNC Failed to find client {clientId} to send response.");
            }
        }

        internal void OnAgwpeFrameReceived(Guid clientId, AgwpeFrame frame)
        {
            //OnDebugMessage($"TNC received frame: Kind={(char)frame.DataKind} From={frame.CallFrom} To={frame.CallTo} Len={frame.DataLen}");
            ProcessAgwCommand(clientId, frame);
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
                case 'R': // Register application
                    HandleRegister(clientId, frame);
                    break;

                case 'G': // Get channel info
                    HandleGetChannel(clientId, frame);
                    break;

                case 'X': // Disconnect / un-register
                    OnDebugMessage($"TNC client unregistered.");
                    break;

                case 'D': // Data frame from app
                    HandleDataFrame(clientId, frame);
                    break;

                case 'K': // Connect request
                    HandleConnectRequest(clientId, frame);
                    break;

                case 'U': // UI (unproto) frame
                    HandleUnproto(clientId, frame);
                    break;

                case 'M': // Send UNPROTO Information (from client to radio)
                    HandleSendUnproto(clientId, frame);
                    break;

                case 'm': // Toggle monitoring frames
                    if (_clients.TryGetValue(clientId, out TcpClientHandler clientHandler))
                    {
                        clientHandler.SendMonitoringFrames = !clientHandler.SendMonitoringFrames;
                        if (clientHandler.SendMonitoringFrames) OnDebugMessage($"TNC enable monitoring frames");
                        else OnDebugMessage($"TNC disable monitoring frames");
                    }
                    break;
                default:
                    OnDebugMessage($"TNC unknown data kind '{(char)frame.DataKind}' (0x{frame.DataKind:X2})");
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

        // -----------------------------
        // Handlers
        // -----------------------------

        private void HandleRegister(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC client registered, CallFrom={frame.CallFrom}");

            // Example reply: echo back registration ok
            var reply = new AgwpeFrame
            {
                Port = frame.Port,
                DataKind = (byte)'R',
                CallFrom = frame.CallFrom,
                CallTo = "AGWPE",
                Data = Array.Empty<byte>()
            };
            SendFrame(clientId, reply);
        }

        private void HandleGetChannel(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC client requested channel info");

            // Example reply with dummy values
            var channelInfo = Encoding.UTF8.GetBytes("1;Port1 Handi-Talky Commander;");
            var reply = new AgwpeFrame
            {
                DataKind = (byte)'G',
                Data = channelInfo
            };
            SendFrame(clientId, reply);
        }

        private void HandleDataFrame(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC data frame from {frame.CallFrom} to {frame.CallTo}, {frame.DataLen} bytes.");

            // Echo back as an example
            var reply = new AgwpeFrame
            {
                Port = frame.Port,
                DataKind = (byte)'d', // response data frame
                CallFrom = frame.CallTo,
                CallTo = frame.CallFrom,
                Data = frame.Data
            };
            SendFrame(clientId, reply);
        }

        private void HandleConnectRequest(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC connect request from {frame.CallFrom} to {frame.CallTo}");

            // Example: always accept
            var reply = new AgwpeFrame
            {
                Port = frame.Port,
                DataKind = (byte)'C', // Connect accepted
                CallFrom = frame.CallTo,
                CallTo = frame.CallFrom,
                Data = Array.Empty<byte>()
            };
            SendFrame(clientId, reply);
        }

        private void HandleUnproto(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC UI frame from {frame.CallFrom} to {frame.CallTo}, {frame.DataLen} bytes");

            // Example: broadcast to all clients
            var broadcast = new AgwpeFrame
            {
                Port = frame.Port,
                DataKind = (byte)'U',
                CallFrom = frame.CallFrom,
                CallTo = frame.CallTo,
                Data = frame.Data
            };
            //Broadcast(broadcast.ToBytes());
        }

        private void HandleSendUnproto(Guid clientId, AgwpeFrame frame)
        {
            OnDebugMessage($"TNC M frame (Send UNPROTO) from {frame.CallFrom} to {frame.CallTo}, {frame.DataLen} bytes");
            if (parent.radio.State != Radio.RadioState.Connected) return;
            try
            {
                // Construct AX25Packet for UNPROTO (UI) frame
                var addresses = new System.Collections.Generic.List<AX25Address>
                {
                    AX25Address.GetAddress(frame.CallTo),
                    AX25Address.GetAddress(frame.CallFrom)
                };
                var packet = new AX25Packet(addresses, frame.Data, DateTime.Now);
                packet.channel_id = parent.radio.HtStatus.curr_ch_id;
                packet.channel_name = parent.radio.currentChannelName;
                parent.radio.TransmitTncData(packet); // Send to radio
            }
            catch (Exception ex)
            {
                OnDebugMessage($"TNC error sending UNPROTO frame to radio: {ex.Message}");
            }
        }

        internal void RemoveClient(Guid clientId)
        {
            if (_clients.TryRemove(clientId, out var clientHandler))
            {
                OnDebugMessage($"TNC client disconnected: {clientId}");
                ClientDisconnected?.Invoke(clientId);
            }
        }
    }
}