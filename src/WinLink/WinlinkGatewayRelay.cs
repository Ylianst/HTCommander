/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Net.Sockets;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading.Tasks;

namespace HTCommander
{
    /// <summary>
    /// Manages a TCP/TLS connection to the Winlink CMS gateway (server.winlink.org:8773)
    /// for relaying Winlink protocol traffic between a BBS radio client and the internet gateway.
    /// The relay logs in using the connecting station's callsign, obtains the ;PQ: challenge,
    /// and then transparently relays all Winlink B2F protocol traffic.
    /// </summary>
    public class WinlinkGatewayRelay : IDisposable
    {
        private TcpClient tcpClient;
        private Stream tcpStream;
        private bool tcpRunning = false;
        private bool disposed = false;
        private readonly string server;
        private readonly int port;
        private readonly bool useTls;
        private readonly DataBrokerClient broker;
        private readonly int deviceId;

        /// <summary>
        /// The ;PQ: challenge string received from the CMS gateway during login.
        /// Null if no challenge was received (e.g., CMS does not require auth).
        /// </summary>
        public string PQChallenge { get; private set; }

        /// <summary>
        /// The [WL2K-...] banner string received from the CMS gateway.
        /// </summary>
        public string WL2KBanner { get; private set; }

        /// <summary>
        /// Whether the relay is currently connected to the CMS gateway.
        /// </summary>
        public bool IsConnected => tcpClient != null && tcpClient.Connected && tcpRunning;

        /// <summary>
        /// Fired when line-based data is received from the CMS gateway.
        /// The string includes the line content (without trailing \r).
        /// </summary>
        public event Action<string> LineReceived;

        /// <summary>
        /// Fired when raw binary data is received from the CMS gateway.
        /// Used during binary mail block transfer.
        /// </summary>
        public event Action<byte[]> BinaryDataReceived;

        /// <summary>
        /// Fired when the CMS gateway connection is lost or closed.
        /// </summary>
        public event Action Disconnected;

        /// <summary>
        /// When true, incoming data is forwarded as raw binary via BinaryDataReceived.
        /// When false, incoming data is parsed as lines and forwarded via LineReceived.
        /// </summary>
        public bool BinaryMode { get; set; } = false;

        /// <summary>
        /// Creates a new WinlinkGatewayRelay.
        /// </summary>
        /// <param name="deviceId">The BBS device ID (for logging).</param>
        /// <param name="server">CMS server hostname.</param>
        /// <param name="port">CMS server port.</param>
        /// <param name="useTls">Whether to use TLS.</param>
        public WinlinkGatewayRelay(int deviceId, DataBrokerClient broker, string server = "server.winlink.org", int port = 8773, bool useTls = true)
        {
            this.deviceId = deviceId;
            this.broker = broker;
            this.server = server;
            this.port = port;
            this.useTls = useTls;
        }

        /// <summary>
        /// Connects to the CMS gateway and performs the initial login handshake
        /// using the specified station callsign. Returns true if the connection
        /// and login succeed and a session prompt is received.
        /// </summary>
        /// <param name="stationCallsign">The callsign to log in with (the remote station's callsign).</param>
        /// <param name="timeoutMs">Connection timeout in milliseconds.</param>
        /// <returns>True if connected and handshake completed successfully.</returns>
        public async Task<bool> ConnectAsync(string stationCallsign, int timeoutMs = 15000)
        {
            try
            {
                broker.LogInfo($"[BBS/{deviceId}/Relay] Connecting to CMS gateway {server}:{port} for station {stationCallsign}");

                tcpClient = new TcpClient();

                // Connect with timeout
                var connectTask = tcpClient.ConnectAsync(server, port);
                if (await Task.WhenAny(connectTask, Task.Delay(timeoutMs)) != connectTask)
                {
                    broker.LogError($"[BBS/{deviceId}/Relay] Connection timed out");
                    CleanupTcp();
                    return false;
                }
                await connectTask; // Propagate any exception

                if (useTls)
                {
                    NetworkStream networkStream = tcpClient.GetStream();
                    SslStream sslStream = new SslStream(networkStream, false, ValidateServerCertificate, null);
                    try
                    {
                        await sslStream.AuthenticateAsClientAsync(server);
                        tcpStream = sslStream;
                    }
                    catch (Exception ex)
                    {
                        broker.LogError($"[BBS/{deviceId}/Relay] TLS authentication failed: {ex.Message}");
                        sslStream.Close();
                        CleanupTcp();
                        return false;
                    }
                }
                else
                {
                    tcpStream = tcpClient.GetStream();
                }

                tcpRunning = true;

                // Perform the login handshake synchronously (read prompts, send responses)
                bool handshakeOk = await PerformHandshake(stationCallsign, timeoutMs);
                if (!handshakeOk)
                {
                    broker.LogError($"[BBS/{deviceId}/Relay] Handshake failed");
                    Disconnect();
                    return false;
                }

                broker.LogInfo($"[BBS/{deviceId}/Relay] Connected and handshake complete. PQ={PQChallenge ?? "(none)"}");

                // Start the receive loop for ongoing relay
                _ = Task.Run(() => ReceiveLoop());

                return true;
            }
            catch (Exception ex)
            {
                broker.LogError($"[BBS/{deviceId}/Relay] Connection failed: {ex.Message}");
                CleanupTcp();
                return false;
            }
        }

        /// <summary>
        /// Reads lines from the CMS gateway during the initial login, handling the
        /// "Callsign :", "Password :", [WL2K-...] banner, ;PQ: challenge, and > prompt.
        /// </summary>
        private async Task<bool> PerformHandshake(string stationCallsign, int timeoutMs)
        {
            byte[] buffer = new byte[4096];
            StringBuilder lineBuffer = new StringBuilder();
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            bool gotPrompt = false;

            while (tcpRunning && DateTime.UtcNow < deadline)
            {
                // Set read timeout
                int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                if (remaining <= 0) break;

                try
                {
                    var readTask = tcpStream.ReadAsync(buffer, 0, buffer.Length);
                    if (await Task.WhenAny(readTask, Task.Delay(Math.Min(remaining, 10000))) != readTask)
                    {
                        break; // Timeout
                    }

                    int bytesRead = await readTask;
                    if (bytesRead <= 0) break;

                    string chunk = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                    lineBuffer.Append(chunk);

                    // Process complete lines
                    string accumulated = lineBuffer.ToString();
                    while (true)
                    {
                        int crIdx = accumulated.IndexOf('\r');
                        int nlIdx = accumulated.IndexOf('\n');
                        int lineEnd = -1;
                        int skipLen = 0;

                        if (crIdx >= 0 && nlIdx >= 0)
                        {
                            if (crIdx < nlIdx) { lineEnd = crIdx; skipLen = (nlIdx == crIdx + 1) ? 2 : 1; }
                            else { lineEnd = nlIdx; skipLen = 1; }
                        }
                        else if (crIdx >= 0) { lineEnd = crIdx; skipLen = 1; }
                        else if (nlIdx >= 0) { lineEnd = nlIdx; skipLen = 1; }
                        else break;

                        string line = accumulated.Substring(0, lineEnd);
                        accumulated = accumulated.Substring(lineEnd + skipLen);
                        lineBuffer.Clear();
                        lineBuffer.Append(accumulated);

                        broker.LogInfo($"[BBS/{deviceId}/Relay] CMS << {line}");

                        // Handle prompts
                        if (line.Trim().Equals("Callsign :", StringComparison.OrdinalIgnoreCase))
                        {
                            broker.LogInfo($"[BBS/{deviceId}/Relay] Sending callsign: {stationCallsign}");
                            SendRaw(stationCallsign + "\r");
                            continue;
                        }

                        if (line.Trim().Equals("Password :", StringComparison.OrdinalIgnoreCase))
                        {
                            broker.LogInfo($"[BBS/{deviceId}/Relay] Sending password");
                            SendRaw("CMSTelnet\r");
                            continue;
                        }

                        // Capture [WL2K-...] banner
                        if (line.Trim().StartsWith("[WL2K-") && line.Trim().EndsWith("$]"))
                        {
                            WL2KBanner = line.Trim();
                            broker.LogInfo($"[BBS/{deviceId}/Relay] Got WL2K banner: {WL2KBanner}");
                            continue;
                        }

                        // Capture ;PQ: challenge
                        if (line.Trim().StartsWith(";PQ:"))
                        {
                            PQChallenge = line.Trim().Substring(4).Trim();
                            broker.LogInfo($"[BBS/{deviceId}/Relay] Got PQ challenge: {PQChallenge}");
                            continue;
                        }

                        // Check for session prompt (ends with >)
                        if (line.Trim().EndsWith(">"))
                        {
                            gotPrompt = true;
                            break;
                        }
                    }

                    if (gotPrompt) break;
                }
                catch (Exception ex)
                {
                    broker.LogError($"[BBS/{deviceId}/Relay] Handshake read error: {ex.Message}");
                    return false;
                }
            }

            return gotPrompt;
        }

        /// <summary>
        /// Sends a string to the CMS gateway.
        /// </summary>
        public void SendLine(string line)
        {
            if (!IsConnected) return;
            broker.LogInfo($"[BBS/{deviceId}/Relay] CMS >> {line}");
            SendRaw(line + "\r");
        }

        /// <summary>
        /// Sends raw string data to the CMS gateway (no \r appended).
        /// </summary>
        public void SendRaw(string data)
        {
            if (!IsConnected) return;
            try
            {
                byte[] bytes = Encoding.UTF8.GetBytes(data);
                tcpStream.Write(bytes, 0, bytes.Length);
                tcpStream.Flush();
            }
            catch (Exception ex)
            {
                broker.LogError($"[BBS/{deviceId}/Relay] Send error: {ex.Message}");
                Disconnect();
            }
        }

        /// <summary>
        /// Sends raw binary data to the CMS gateway.
        /// </summary>
        public void SendBinary(byte[] data)
        {
            if (!IsConnected) return;
            try
            {
                tcpStream.Write(data, 0, data.Length);
                tcpStream.Flush();
            }
            catch (Exception ex)
            {
                broker.LogError($"[BBS/{deviceId}/Relay] Binary send error: {ex.Message}");
                Disconnect();
            }
        }

        /// <summary>
        /// Disconnects from the CMS gateway.
        /// </summary>
        public void Disconnect()
        {
            if (!tcpRunning && tcpClient == null) return;
            broker.LogInfo($"[BBS/{deviceId}/Relay] Disconnecting from CMS gateway");
            tcpRunning = false;
            CleanupTcp();
            Disconnected?.Invoke();
        }

        /// <summary>
        /// Background receive loop that forwards incoming CMS data to the BBS session.
        /// </summary>
        private async Task ReceiveLoop()
        {
            byte[] buffer = new byte[8192];

            while (tcpRunning && tcpClient != null && tcpClient.Connected)
            {
                try
                {
                    int bytesRead = await tcpStream.ReadAsync(buffer, 0, buffer.Length);
                    if (bytesRead <= 0) break;

                    byte[] data = new byte[bytesRead];
                    Array.Copy(buffer, 0, data, 0, bytesRead);

                    if (BinaryMode)
                    {
                        BinaryDataReceived?.Invoke(data);
                    }
                    else
                    {
                        // Parse into lines and forward
                        string chunk = Encoding.UTF8.GetString(data);
                        string[] lines = chunk.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                        foreach (string line in lines)
                        {
                            if (line.Length == 0) continue;
                            broker.LogInfo($"[BBS/{deviceId}/Relay] CMS << {line}");
                            LineReceived?.Invoke(line);
                        }
                    }
                }
                catch (Exception ex)
                {
                    if (tcpRunning)
                    {
                        broker.LogError($"[BBS/{deviceId}/Relay] Receive error: {ex.Message}");
                    }
                    break;
                }
            }

            // Connection closed
            if (tcpRunning)
            {
                broker.LogInfo($"[BBS/{deviceId}/Relay] CMS connection closed");
                tcpRunning = false;
                CleanupTcp();
                Disconnected?.Invoke();
            }
        }

        private bool ValidateServerCertificate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors)
        {
            if (sslPolicyErrors == SslPolicyErrors.None) return true;
            broker.LogError($"[BBS/{deviceId}/Relay] Certificate validation error: {sslPolicyErrors}");
            return false;
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

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposed)
            {
                if (disposing)
                {
                    tcpRunning = false;
                    CleanupTcp();
                }
                disposed = true;
            }
        }
    }
}
