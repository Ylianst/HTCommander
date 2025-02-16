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
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Net.WebSockets;
using System.Threading.Tasks;
//using System.Security.Cryptography;
using System.Collections.Concurrent;
//using System.Security.Cryptography.X509Certificates;

namespace HTCommander
{
    public class HttpsWebSocketServer
    {
        private MainForm parent;
        private readonly HttpListener _listener;
        private readonly ConcurrentDictionary<Guid, WebSocket> _webSockets = new ConcurrentDictionary<Guid, WebSocket>();
        //private readonly X509Certificate2 _certificate;
        private CancellationTokenSource _cts;
        private Task _serverTask;
        public int port;

        public HttpsWebSocketServer(MainForm parent, int port)
        {
            this.port = port;
            this.parent = parent;
            //_certificate = GetOrCreateCertificate("cert.pfx", "password");
            _listener = new HttpListener();
            _listener.Prefixes.Add("http://localhost:" + port + "/");
        }

        public void Start()
        {
            if (_serverTask != null && !_serverTask.IsCompleted)
            {
                parent.Debug("Server is already running.");
                return;
            }

            _cts = new CancellationTokenSource();
            //_serverTask = StartAsync(_cts.Token);
            _serverTask = Task.Run(() => StartAsync(_cts.Token), _cts.Token); // Start on a new thread!
            parent.Debug("Server starting...");
        }

        public void Stop()
        {
            if (_cts == null)
            {
                parent.Debug("Server is not running.");
                return;
            }

            parent.Debug("Stopping server...");
            _cts.Cancel();
            _listener.Stop();
            _cts.Dispose();
            _cts = null;
            _serverTask = null;

            foreach (var ws in _webSockets.Values)
            {
                if (ws.State == WebSocketState.Open)
                {
                    ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Server shutting down", CancellationToken.None).Wait();
                }
            }
            _webSockets.Clear();

            parent.Debug("Server stopped.");
        }

        private async Task StartAsync(CancellationToken cancellationToken)
        {
            _listener.Start();
            parent.Debug("Server started on " + string.Join(", ", _listener.Prefixes));

            while (!cancellationToken.IsCancellationRequested)
            {
                var context = await _listener.GetContextAsync();
                if (context.Request.IsWebSocketRequest)
                {
                    _ = HandleWebSocketClientAsync(context);
                }
                else
                {
                    HandleHttpRequest(context);
                }
            }
        }

        private async Task HandleWebSocketClientAsync(HttpListenerContext context)
        {
            try
            {
                var wsContext = await context.AcceptWebSocketAsync(null);
                var webSocket = wsContext.WebSocket;
                var id = Guid.NewGuid();
                _webSockets.TryAdd(id, webSocket);

                parent.Debug($"WebSocket connected: {id}");

                var buffer = new byte[1024];
                while (webSocket.State == WebSocketState.Open)
                {
                    var result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        break;
                    }
                    else if (result.MessageType == WebSocketMessageType.Text)
                    {
                        string message = Encoding.UTF8.GetString(buffer, 0, result.Count);
                        parent.Debug($"Received: {message}");
                    }
                }
            }
            catch (Exception ex)
            {
                parent.Debug("WebSocket error: " + ex.Message);
            }
        }

        private string[] allowedLocalPaths = new string[1] { "index.html" };

        private void HandleHttpRequest(HttpListenerContext context)
        {
            string localpath = context.Request.Url.LocalPath;
            if (localpath.Length > 0) { localpath = localpath.Substring(1); }
            if (localpath == "") { localpath = "index.html"; }

            bool allowed = false;
            for (int i = 0; i < allowedLocalPaths.Length; i++)
            {
                if (allowedLocalPaths[i] == localpath) { allowed = true; break; }
            }

            if (!allowed)
            {
                context.Response.StatusCode = 404;
                byte[] buffer = Encoding.UTF8.GetBytes("404 - Not Found");
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
                context.Response.Close();
                return;
            }

            string filePath = Path.Combine(Directory.GetCurrentDirectory(), localpath);
            if (File.Exists(filePath))
            {
                byte[] buffer = File.ReadAllBytes(filePath);
                context.Response.ContentType = "text/html";
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            }
            else
            {
                context.Response.StatusCode = 404;
                byte[] buffer = Encoding.UTF8.GetBytes("404 - Not Found");
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            }
            context.Response.Close();
        }

        public void BroadcastString(string data)
        {
            foreach (var kvp in _webSockets)
            {
                var webSocket = kvp.Value;
                if (webSocket.State == WebSocketState.Open)
                {
                    _ = SendStringAsync(webSocket, data);
                }
            }
        }

        private async Task SendStringAsync(WebSocket webSocket, string str)
        {
            try
            {
                byte[] data = UTF8Encoding.Default.GetBytes(str);
                await webSocket.SendAsync(new ArraySegment<byte>(data), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error sending binary data: {ex.Message}");
            }
        }

        public void BroadcastBinary(byte[] data)
        {
            foreach (var kvp in _webSockets)
            {
                var webSocket = kvp.Value;
                if (webSocket.State == WebSocketState.Open)
                {
                    _ = SendBinaryAsync(webSocket, data);
                }
            }
        }

        private async Task SendBinaryAsync(WebSocket webSocket, byte[] data)
        {
            try
            {
                await webSocket.SendAsync(new ArraySegment<byte>(data), WebSocketMessageType.Binary, true, CancellationToken.None);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error sending binary data: {ex.Message}");
            }
        }

        /*
        private X509Certificate2 GetOrCreateCertificate(string certPath, string password)
        {
            if (File.Exists(certPath))
            {
                return new X509Certificate2(certPath, password);
            }

            var rsa = RSA.Create(2048);
            var request = new CertificateRequest(
                "CN=" + Dns.GetHostName() + ".local",
                rsa,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);

            request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
            request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
            request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new Oid("1.3.6.1.5.5.7.3.1") }, true));

            var certificate = request.CreateSelfSigned(DateTimeOffset.Now, DateTimeOffset.Now.AddYears(10));
            File.WriteAllBytes(certPath, certificate.Export(X509ContentType.Pfx, password));
            return new X509Certificate2(certPath, password);
        }
        */
    }
}