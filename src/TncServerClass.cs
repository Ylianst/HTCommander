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
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander
{
    /// <summary>
    /// Manages the send/receive logic for a single connected TCP client.
    /// Handles message framing (4-byte length prefix) and queued sending.
    /// </summary>
    public class TcpClientHandler : IDisposable
    {
        // KISS protocol special characters
        private const byte FEND = 0xC0;  // Frame End
        private const byte FESC = 0xDB;  // Frame Escape
        private const byte TFEND = 0xDC; // Transposed Frame End
        private const byte TFESC = 0xDD; // Transposed Frame Escape

        private readonly TcpClient _client;
        private readonly NetworkStream _stream;
        private readonly TncSocketServer _server; // Reference to the parent server
        private readonly ConcurrentQueue<byte[]> _sendQueue = new ConcurrentQueue<byte[]>();
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private readonly Task _sendTask;
        private readonly Task _receiveTask;

        public Guid Id { get; }
        public IPEndPoint EndPoint => (IPEndPoint)_client.Client.RemoteEndPoint;

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
        /// Enqueues a raw data frame (pre-KISS-encoding) to be sent to this client.
        /// </summary>
        public void EnqueueSend(byte[] data)
        {
            _sendQueue.Enqueue(data);
        }

        /// <summary>
        /// Encodes raw data into a KISS frame and sends it.
        /// </summary>
        private async Task ProcessSendQueueAsync()
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    if (_sendQueue.TryDequeue(out var data))
                    {
                        // Encode the raw data into a valid KISS frame with delimiters and escaping.
                        byte[] kissFrame = EncodeKissFrame(data);

                        // Write the KISS frame to the stream.
                        await _stream.WriteAsync(kissFrame, 0, kissFrame.Length, _cts.Token);
                    }
                    else
                    {
                        // Wait a bit if the queue is empty to avoid busy-waiting.
                        await Task.Delay(50, _cts.Token);
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (IOException) { Disconnect(); break; }
                catch (Exception ex)
                {
                    _server.OnDebugMessage($"TNC error sending to {Id}: {ex.Message}");
                    Disconnect();
                    break;
                }
            }
        }

        /// <summary>
        /// Listens for incoming data, assembling and decoding KISS frames.
        /// This handles partial frames received over multiple TCP packets.
        /// </summary>
        private async Task ReceiveLoopAsync()
        {
            // Buffer to hold data read from the stream.
            var readBuffer = new byte[1024];
            // Buffer to build a single KISS frame. Using MemoryStream for efficiency.
            var frameBuffer = new MemoryStream();

            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    int bytesRead = await _stream.ReadAsync(readBuffer, 0, readBuffer.Length, _cts.Token);
                    if (bytesRead == 0)
                    {
                        // Client disconnected gracefully.
                        break;
                    }

                    // 00000000580000004B4B37565A5400000000000000000000000000000000000000000000000000006D00000000000000000000000000000000000000000000000000000000000000000000004700000000000000000000000000000000000000000000000000000000000000
                    _server.OnDebugMessage($"TNC data received: {Utils.BytesToHex(readBuffer, 0, bytesRead)}");

                    // Process each byte received.
                    for (int i = 0; i < bytesRead; i++)
                    {
                        byte currentByte = readBuffer[i];

                        if (currentByte == FEND)
                        {
                            // A FEND byte signifies the end of a frame.
                            // If the buffer has data, process it as a complete frame.
                            if (frameBuffer.Length > 0)
                            {
                                ProcessKissFrame(frameBuffer.ToArray());
                                // Reset the buffer for the next frame.
                                frameBuffer.SetLength(0);
                                frameBuffer.Position = 0;
                            }
                            // Multiple FENDs in a row are ignored (they are just delimiters).
                        }
                        else
                        {
                            // Not a delimiter, so add the byte to our frame buffer.
                            frameBuffer.WriteByte(currentByte);
                        }
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (IOException) { break; }
                catch (Exception ex)
                {
                    _server.OnDebugMessage($"TNC error receiving from {Id}: {ex.Message}");
                    break;
                }
            }
            Disconnect();
        }

        /// <summary>
        /// Decodes a received KISS frame (un-escaping special characters)
        /// and passes it to the server.
        /// </summary>
        /// <param name="frameData">The raw bytes received between FEND delimiters.</param>
        private void ProcessKissFrame(byte[] frameData)
        {
            if (frameData == null || frameData.Length == 0) return;

            var decodedFrame = new MemoryStream();
            bool isEscaped = false;

            foreach (byte b in frameData)
            {
                if (isEscaped)
                {
                    if (b == TFEND)
                    {
                        decodedFrame.WriteByte(FEND);
                    }
                    else if (b == TFESC)
                    {
                        decodedFrame.WriteByte(FESC);
                    }
                    // Any other byte following an escape is a protocol error,
                    // but we can be lenient and just append it.
                    else
                    {
                        // Optional: Log protocol error.
                        // _server.OnDebugMessage($"KISS protocol error: Invalid escape sequence from {Id}");
                        decodedFrame.WriteByte(b);
                    }
                    isEscaped = false;
                }
                else if (b == FESC)
                {
                    isEscaped = true;
                }
                else
                {
                    decodedFrame.WriteByte(b);
                }
            }

            string hexMessage = Utils.BytesToHex(decodedFrame.ToArray());
            _server.OnDebugMessage($"TNC frame received: {hexMessage}");

            _server.OnMessageReceived(Id, decodedFrame.ToArray());
        }

        /// <summary>
        /// Encodes a raw data packet into a KISS-compliant frame, adding delimiters
        /// and escaping special characters.
        /// </summary>
        /// <param name="rawData">The raw command and data to be sent.</param>
        /// <returns>A fully-formed KISS frame ready for transmission.</returns>
        private byte[] EncodeKissFrame(byte[] rawData)
        {
            var encodedFrame = new MemoryStream();

            // Start with a FEND delimiter.
            encodedFrame.WriteByte(FEND);

            // Add data, escaping special characters as needed.
            foreach (byte b in rawData)
            {
                if (b == FEND)
                {
                    encodedFrame.WriteByte(FESC);
                    encodedFrame.WriteByte(TFEND);
                }
                else if (b == FESC)
                {
                    encodedFrame.WriteByte(FESC);
                    encodedFrame.WriteByte(TFESC);
                }
                else
                {
                    encodedFrame.WriteByte(b);
                }
            }

            // End with a FEND delimiter.
            encodedFrame.WriteByte(FEND);

            return encodedFrame.ToArray();
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
        // Events to communicate with the MainForm without a direct reference
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

            // Disconnect all clients
            var clientList = _clients.Values.ToList();
            foreach (var client in clientList)
            {
                client.Dispose();
            }

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
                // This is expected when _listener.Stop() is called.
            }
            catch (OperationCanceledException)
            {
                // This is expected when the cancellation token is triggered.
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

        /// <summary>
        /// Broadcasts a message to all connected clients.
        /// </summary>
        public void Broadcast(byte[] data)
        {
            foreach (var client in _clients.Values)
            {
                client.EnqueueSend(data);
            }
        }

        internal void OnDebugMessage(string message) { parent.Debug(message); }

        internal void OnMessageReceived(Guid clientId, byte[] message)
        {
            if (message == null || message.Length == 0) { return; }

            MessageReceived?.Invoke(clientId, message);

            string hexMessage = Utils.BytesToHex(message);
            //string textMessage = Encoding.UTF8.GetString(message);
            OnDebugMessage($"TNC received: {hexMessage}");

            // Example of parsing binary data, assuming you have a `Utils` class
            // if (message.Length >= 4)
            // {
            //     int group = Utils.GetShort(message, 0);
            //     int cmd = Utils.GetShort(message, 2);
            //     _parent.radio.SendRawCommand(message);
            // }
        }

        internal void RemoveClient(Guid clientId)
        {
            if (_clients.TryRemove(clientId, out var clientHandler))
            {
                OnDebugMessage($"TNC client disconnected: {clientId}");
                ClientDisconnected?.Invoke(clientId);
                // The handler's Dispose method will be called, cleaning up the TcpClient
            }
        }
    }
}