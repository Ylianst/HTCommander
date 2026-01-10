/*
Copyright 2026 Ylian Saint-Hilaire

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
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web;
using Windows.Storage.Streams;

namespace HTCommander
{
    // A class to hold a message to be sent
    public class WebSocketMessage
    {
        public byte[] Data { get; }
        public WebSocketMessageType MessageType { get; }

        public WebSocketMessage(byte[] data, WebSocketMessageType messageType)
        {
            Data = data;
            MessageType = messageType;
        }
    }

    // New class to manage sending for a single WebSocket
    public class WebSocketSender : IDisposable
    {
        private readonly WebSocket _webSocket;
        private readonly MainForm _parent;
        private readonly ConcurrentQueue<WebSocketMessage> _sendQueue = new ConcurrentQueue<WebSocketMessage>();
        private readonly SemaphoreSlim _sendLock = new SemaphoreSlim(1, 1); // Ensures only one send operation at a time
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private Task _sendingTask;

        public WebSocket WebSocket => _webSocket;
        public Guid Id { get; }

        public WebSocketSender(Guid id, WebSocket webSocket, MainForm parent)
        {
            Id = id;
            _webSocket = webSocket;
            _parent = parent;
            _sendingTask = Task.Run(() => ProcessSendQueue());
        }

        public void EnqueueSend(byte[] data, WebSocketMessageType messageType)
        {
            _sendQueue.Enqueue(new WebSocketMessage(data, messageType));
            // Signal the sending task that there's new data
            // (The SemaphoreSlim in ProcessSendQueue naturally handles this if it's waiting)
        }

        private Task ProcessSendQueue()
        {
            /*
            try
            {
                while (!_cts.Token.IsCancellationRequested)
                {
                    if (_sendQueue.IsEmpty)
                    {
                        await Task.Delay(50, _cts.Token); // Wait a bit if queue is empty
                        continue;
                    }

                    await _sendLock.WaitAsync(_cts.Token); // Acquire the lock for sending
                    try
                    {
                        if (_sendQueue.TryDequeue(out var message))
                        {
                            if (_webSocket.State == WebSocketState.Open)
                            {
                                await _webSocket.SendAsync(new ArraySegment<byte>(message.Data), message.MessageType, true, _cts.Token);
                                //_parent.Debug($"Sent to {Id}: {Encoding.UTF8.GetString(message.Data)}"); // Optional: log sent messages
                            }
                            else
                            {
                                _parent.Debug($"WebSocket {Id} not open, dropping message.");
                            }
                        }
                    }
                    catch (WebSocketException wsEx)
                    {
                        _parent.Debug($"WebSocket error sending to {Id}: {wsEx.Message}");
                        // Consider what to do here: maybe requeue, or disconnect the client
                    }
                    catch (OperationCanceledException)
                    {
                        // Task was cancelled, exit loop
                        break;
                    }
                    catch (Exception ex)
                    {
                        _parent.Debug($"Error sending data to {Id}: {ex.Message}");
                    }
                    finally
                    {
                        _sendLock.Release(); // Release the lock
                    }
                }
            }
            catch (OperationCanceledException)
            {
                _parent.Debug($"Sending task for {Id} cancelled.");
            }
            catch (Exception ex)
            {
                _parent.Debug($"Fatal error in sending task for {Id}: {ex.Message}");
            }
            */
            return null;
        }

        public void Dispose()
        {
            _cts.Cancel();
            _sendingTask?.Wait(TimeSpan.FromSeconds(2)); // Wait for the sending task to finish gracefully
            _sendLock.Dispose();
            _cts.Dispose();
        }
    }


    public class HttpsWebSocketServer
    {
        private MainForm parent;
        private readonly HttpListener _listener;
        private readonly ConcurrentDictionary<Guid, WebSocketSender> _webSockets = new ConcurrentDictionary<Guid, WebSocketSender>();
        private CancellationTokenSource _cts;
        private Task _serverTask;
        public int port;

        public HttpsWebSocketServer(MainForm parent, int port)
        {
            this.port = port;
            this.parent = parent;
            _listener = new HttpListener();
            _listener.Prefixes.Add("http://+:" + port + "/");
        }

        public void Start()
        {
            if (_serverTask != null && !_serverTask.IsCompleted)
            {
                //parent.Debug("Server is already running.");
                return;
            }

            _cts = new CancellationTokenSource();
            _serverTask = Task.Run(() => StartAsync(_cts.Token), _cts.Token);
            //parent.Debug("Server starting...");
        }

        public void Stop()
        {
            if (_cts == null)
            {
                //parent.Debug("Server is not running.");
                return;
            }

            //parent.Debug("Stopping server...");
            _cts.Cancel();
            _listener.Stop();

            if (_serverTask != null && !_serverTask.IsCompleted)
            {
                try
                {
                    _serverTask.Wait(TimeSpan.FromSeconds(5));
                }
                catch (OperationCanceledException) { }
                catch (Exception ex)
                {
                    //parent.Debug($"Error waiting for server task to complete: {ex.Message}");
                }
            }

            foreach (var kvp in _webSockets)
            {
                var id = kvp.Key;
                var wsSender = kvp.Value;
                var ws = wsSender.WebSocket; // Get the underlying WebSocket

                if (ws.State == WebSocketState.Open || ws.State == WebSocketState.CloseReceived)
                {
                    try
                    {
                        ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Server shutting down", CancellationToken.None).Wait();
                    }
                    catch (Exception ex)
                    {
                        //parent.Debug($"Error closing WebSocket {id}: {ex.Message}");
                    }
                }
                wsSender.Dispose(); // Dispose the WebSocketSender, which disposes the WebSocket
            }
            _webSockets.Clear();

            _cts.Dispose();
            _cts = null;
            _serverTask = null;

            //parent.Debug("Server stopped.");
        }

        private async Task StartAsync(CancellationToken cancellationToken)
        {
            _listener.Start();
            //parent.Debug("Server started on " + string.Join(", ", _listener.Prefixes));

            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    HttpListenerContext context;
                    try
                    {
                        context = await _listener.GetContextAsync();
                    }
                    catch (HttpListenerException ex)
                    {
                        if (ex.ErrorCode == 995)
                        {
                            break;
                        }
                        //parent.Debug($"HttpListenerException: {ex.Message}");
                        continue;
                    }
                    catch (Exception ex)
                    {
                        //parent.Debug($"Error getting HTTP context: {ex.Message}");
                        continue;
                    }

                    if (context.Request.IsWebSocketRequest)
                    {
                        _ = HandleWebSocketClientAsync(context, cancellationToken);
                    }
                    else
                    {
                        HandleHttpRequest(context);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                //parent.Debug("Server task cancelled.");
            }
            catch (Exception ex)
            {
                //parent.Debug("Server error: " + ex.Message);
            }
            finally
            {
                _listener.Stop();
                //parent.Debug("HttpListener stopped.");
            }
        }

        private Task HandleWebSocketClientAsync(HttpListenerContext context, CancellationToken cancellationToken)
        {
            /*
            string localpath = context.Request.Url.LocalPath;
            if (localpath.Length > 0) { localpath = localpath.Substring(1); }
            if (localpath != "websocket.aspx")
            {
                context.Response.StatusCode = 404;
                byte[] buffer = Encoding.UTF8.GetBytes("404 - Not Found");
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
                context.Response.Close();
                return;
            }

            WebSocket webSocket = null;
            Guid id = Guid.Empty;
            WebSocketSender webSocketSender = null;

            try
            {
                var wsContext = await context.AcceptWebSocketAsync(null);
                webSocket = wsContext.WebSocket;
                id = Guid.NewGuid();
                webSocketSender = new WebSocketSender(id, webSocket, parent);
                _webSockets.TryAdd(id, webSocketSender);

                parent.Debug($"WebSocket connected: {id}");

                if (parent.radio.State == Radio.RadioState.Connected) { webSocketSender.EnqueueSend(Encoding.UTF8.GetBytes("wasconnected"), WebSocketMessageType.Text); }
                else if (parent.radio.State == Radio.RadioState.Connecting) { webSocketSender.EnqueueSend(Encoding.UTF8.GetBytes("connecting"), WebSocketMessageType.Text); }
                else { webSocketSender.EnqueueSend(Encoding.UTF8.GetBytes("disconnected"), WebSocketMessageType.Text); }

                var buffer = new byte[65536]; // 64KB buffer
                while (webSocket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
                {
                    WebSocketReceiveResult result;
                    try
                    {
                        result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
                    }
                    catch (WebSocketException ex) when (ex.WebSocketErrorCode == WebSocketError.ConnectionClosedPrematurely)
                    {
                        parent.Debug($"WebSocket {id} connection closed prematurely: {ex.Message}");
                        break;
                    }
                    catch (OperationCanceledException)
                    {
                        break; // Server is shutting down
                    }
                    catch (Exception ex)
                    {
                        parent.Debug($"Error receiving from WebSocket {id}: {ex.Message}");
                        break;
                    }

                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await webSocket.CloseAsync(result.CloseStatus.Value, result.CloseStatusDescription, CancellationToken.None);
                        parent.Debug($"WebSocket {id} closed by client. Status: {result.CloseStatus}, Description: {result.CloseStatusDescription}");
                        break;
                    }
                    else if (result.MessageType == WebSocketMessageType.Text)
                    {
                        string message = Encoding.UTF8.GetString(buffer, 0, result.Count);

                        if ((message == "connect") && (parent.radio.State == Radio.RadioState.Disconnected))
                        {
                            parent.connectToolStripMenuItem_Click(this, null);
                        }
                        if ((message == "disconnect") && (parent.radio.State == Radio.RadioState.Connected))
                        {
                            parent.radio.Disconnect();
                        }
                    }
                    else if (result.MessageType == WebSocketMessageType.Binary)
                    {
                        if (result.Count < 5) continue;
                        byte[] receivedData = new byte[result.Count];
                        Array.Copy(buffer, 0, receivedData, 0, result.Count);
                        bool forward = true;

                        // Check if we are channel locked, if so, don't allow channel changing.
                        int group = Utils.GetShort(receivedData, 0);
                        int cmd = Utils.GetShort(receivedData, 2);
                        //if ((group == 2) && (cmd == 11) && (parent.activeChannelIdLock != -1)) { forward = false; } // WRITE_SETTINGS 

                        //if (forward) { parent.radio.SendRawCommand(receivedData); }
                    }
                }
            }
            catch (Exception ex)
            {
                //parent.Debug($"WebSocket client {id} error: {ex.Message}");
            }
            finally
            {
                if (webSocketSender != null)
                {
                    if (_webSockets.TryRemove(id, out _))
                    {
                        //parent.Debug($"WebSocket {id} removed from active connections.");
                    }
                    if (webSocket.State == WebSocketState.Open || webSocket.State == WebSocketState.CloseReceived)
                    {
                        try
                        {
                            await webSocket.CloseAsync(WebSocketCloseStatus.InternalServerError, "Server error or disconnect", CancellationToken.None);
                        }
                        catch (Exception ex)
                        {
                            //parent.Debug($"Error closing WebSocket {id} in finally block: {ex.Message}");
                        }
                    }
                    webSocketSender.Dispose(); // Dispose the WebSocketSender
                }
            }
            */
            return null;
        }

        private void HandleHttpRequest(HttpListenerContext context)
        {
            try
            {
                // Get the requested URL path
                string urlPath = context.Request.Url.AbsolutePath;
                if (urlPath == "/") { urlPath = "/index.html"; }

                // Decode URL and normalize it
                string relativePath = HttpUtility.UrlDecode(urlPath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));

                // Security check: prevent path traversal
                if (relativePath.Contains(".."))
                {
                    context.Response.StatusCode = (int)HttpStatusCode.BadRequest;
                    using (var writer = new StreamWriter(context.Response.OutputStream))
                    {
                        writer.Write("400 - Bad Request");
                    }
                    return;
                }

                // Base path to /web under the executable
                string basePath = Path.Combine(AppContext.BaseDirectory, "web");

                // Full path to the requested file
                string filePath = Path.Combine(basePath, relativePath);

                // Ensure the full path is still inside /web directory
                if (!filePath.StartsWith(basePath, StringComparison.OrdinalIgnoreCase))
                {
                    context.Response.StatusCode = (int)HttpStatusCode.Forbidden;
                    using (var writer = new StreamWriter(context.Response.OutputStream))
                    {
                        writer.Write("403 - Forbidden");
                    }
                    return;
                }

                // Check if file exists
                if (File.Exists(filePath))
                {
                    byte[] fileBytes = File.ReadAllBytes(filePath);
                    string mimeType = GetMimeType(filePath);

                    if (urlPath == "/index.html")
                    {
                        string html = UTF8Encoding.UTF8.GetString(fileBytes);
                        html = html.Replace("var websocketMode = false;", "var websocketMode = true;");
                        fileBytes = UTF8Encoding.UTF8.GetBytes(html);
                    }

                    context.Response.ContentType = mimeType;
                    context.Response.ContentLength64 = fileBytes.Length;
                    context.Response.StatusCode = (int)HttpStatusCode.OK;
                    context.Response.OutputStream.Write(fileBytes, 0, fileBytes.Length);
                }
                else
                {
                    context.Response.StatusCode = (int)HttpStatusCode.NotFound;
                    using (var writer = new StreamWriter(context.Response.OutputStream))
                    {
                        writer.Write("404 - File Not Found");
                    }
                }
            }
            catch (Exception ex)
            {
                context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;
                using (var writer = new StreamWriter(context.Response.OutputStream))
                {
                    writer.Write("500 - Internal Server Error\n" + ex.Message);
                }
            }
            finally
            {
                context.Response.OutputStream.Close();
            }
        }

        private string GetMimeType(string filePath)
        {
            string extension = Path.GetExtension(filePath).ToLowerInvariant();

            switch (extension)
            {
                case ".html":
                case ".htm":
                    return "text/html";
                case ".css":
                    return "text/css";
                case ".js":
                    return "application/javascript";
                case ".json":
                    return "application/json";
                case ".png":
                    return "image/png";
                case ".jpg":
                case ".jpeg":
                    return "image/jpeg";
                case ".gif":
                    return "image/gif";
                case ".svg":
                    return "image/svg+xml";
                default:
                    return "application/octet-stream";
            }
        }

        /*
        private void HandleHttpRequest(HttpListenerContext context)
        {
            string selfFolder = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
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

            string filePath = Path.Combine("C:\\Tmp\\HTCommanderWeb", localpath);
            if (File.Exists(filePath))
            {
                byte[] buffer = File.ReadAllBytes(filePath);
                if (localpath == "index.html")
                {
                    string html = UTF8Encoding.UTF8.GetString(buffer);
                    html = html.Replace("var websocketMode = false;", "var websocketMode = true;");
                    buffer = UTF8Encoding.UTF8.GetBytes(html);
                }
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
        */

        public void BroadcastString(string data)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(data);
            foreach (var kvp in _webSockets)
            {
                var webSocketSender = kvp.Value;
                webSocketSender.EnqueueSend(bytes, WebSocketMessageType.Text);
            }
        }

        public void BroadcastBinary(byte[] data)
        {
            foreach (var kvp in _webSockets)
            {
                var webSocketSender = kvp.Value;
                webSocketSender.EnqueueSend(data, WebSocketMessageType.Binary);
            }
        }
    }
}