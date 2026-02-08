/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Net.Sockets;
using System.Collections.Generic;

namespace HTCommander
{
    public class SmtpServer
    {
        private MainForm mainForm;
        private TcpListener listener;
        private Thread listenerThread;
        private bool running;
        public readonly int Port;
        private List<SmtpSession> sessions = new List<SmtpSession>();

        public SmtpServer(MainForm mainForm, int port)
        {
            this.mainForm = mainForm;
            this.Port = port;
        }

        public void Start()
        {
            try
            {
                listener = new TcpListener(IPAddress.Loopback, Port);
                listener.Start();
                running = true;
                listenerThread = new Thread(ListenerLoop);
                listenerThread.IsBackground = true;
                listenerThread.Start();
                //mainForm.Debug($"SMTP server started on port {Port}");
            }
            catch (Exception ex)
            {
                //mainForm.Debug($"SMTP server failed to start: {ex.Message}");
            }
        }

        public void Stop()
        {
            running = false;
            if (listener != null) listener.Stop();
            lock (sessions)
            {
                SmtpSession[] sessionArray = new SmtpSession[sessions.Count];
                sessions.CopyTo(sessionArray, 0);
                foreach (var session in sessionArray)
                {
                    session.Close();
                }
                sessions.Clear();
            }
            //mainForm.Debug("SMTP server stopped");
        }

        private void ListenerLoop()
        {
            while (running)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    SmtpSession session = new SmtpSession(this, mainForm, client);
                    lock (sessions)
                    {
                        sessions.Add(session);
                    }
                    Thread sessionThread = new Thread(session.Run);
                    sessionThread.IsBackground = true;
                    sessionThread.Start();
                }
                catch (Exception)
                {
                    if (running) Thread.Sleep(100);
                }
            }
        }

        public void RemoveSession(SmtpSession session)
        {
            lock (sessions)
            {
                sessions.Remove(session);
            }
        }
    }

    public class SmtpSession
    {
        private SmtpServer server;
        private MainForm mainForm;
        private TcpClient client;
        private StreamReader reader;
        private StreamWriter writer;
        private string mailFrom;
        private List<string> rcptTo;
        private bool inDataMode;
        private StringBuilder dataBuffer;

        public SmtpSession(SmtpServer server, MainForm mainForm, TcpClient client)
        {
            this.server = server;
            this.mainForm = mainForm;
            this.client = client;
            this.reader = new StreamReader(client.GetStream(), Encoding.UTF8);
            this.writer = new StreamWriter(client.GetStream(), Encoding.UTF8) { AutoFlush = true };
            this.rcptTo = new List<string>();
            this.inDataMode = false;
            this.dataBuffer = new StringBuilder();
        }

        public void Run()
        {
            try
            {
                //mainForm.Debug("SMTP: Client connected from " + ((System.Net.IPEndPoint)client.Client.RemoteEndPoint).Address);

                // RFC 5321 compliant greeting with hostname
                // Use machine name to avoid DNS issues with Outlook
                //string hostname = System.Net.Dns.GetHostName();
                //if (string.IsNullOrEmpty(hostname)) hostname = "localhost";
                //string hostname = "localhost";
                string greeting = "220 localhost ESMTP\r\n";
                byte[] greetingBytes = Encoding.UTF8.GetBytes(greeting);
                client.GetStream().Write(greetingBytes, 0, greetingBytes.Length);
                client.GetStream().Flush();
                //mainForm.Debug($"SMTP S: {greeting.TrimEnd()}");

                // Read with timeout to detect disconnects
                NetworkStream stream = client.GetStream();
                stream.ReadTimeout = 30000; // 30 second timeout
                
                byte[] buffer = new byte[4096];
                StringBuilder lineBuffer = new StringBuilder();
                
                while (true)
                {
                    int bytesRead = 0;
                    try
                    {
                        bytesRead = stream.Read(buffer, 0, buffer.Length);
                    }
                    catch (IOException ioEx)
                    {
                        //mainForm.Debug($"SMTP: Read timeout or connection closed: {ioEx.Message}");
                        break;
                    }
                    
                    if (bytesRead == 0)
                    {
                        //mainForm.Debug("SMTP: Client disconnected (0 bytes read)");
                        break;
                    }

                    string received = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                    //mainForm.Debug($"SMTP: Received {bytesRead} bytes: [{BitConverter.ToString(buffer, 0, bytesRead)}]");
                    //mainForm.Debug($"SMTP: As string: [{received}]");
                    
                    lineBuffer.Append(received);
                    
                    // Process complete lines
                    string bufferedText = lineBuffer.ToString();
                    int newlinePos;
                    
                    while ((newlinePos = bufferedText.IndexOf('\n')) >= 0)
                    {
                        string line = bufferedText.Substring(0, newlinePos).TrimEnd('\r', '\n');
                        bufferedText = bufferedText.Substring(newlinePos + 1);
                        
                        if (!string.IsNullOrWhiteSpace(line) || inDataMode)
                        {
                            //mainForm.Debug($"SMTP C: {line}");

                            if (inDataMode)
                            {
                                ProcessDataLine(line);
                            }
                            else
                            {
                                ProcessCommand(line);
                            }
                        }
                    }
                    
                    lineBuffer.Clear();
                    lineBuffer.Append(bufferedText);
                }
            }
            catch (Exception ex)
            {
                //mainForm.Debug($"SMTP session error: {ex.Message}");
                //mainForm.Debug($"SMTP stack trace: {ex.StackTrace}");
            }
            finally
            {
                Close();
            }
        }

        private void ProcessCommand(string line)
        {
            string[] parts = line.Split(new[] { ' ' }, 2);
            if (parts.Length == 0) return;

            string command = parts[0].ToUpper();
            string args = parts.Length > 1 ? parts[1] : "";

            try
            {
                switch (command)
                {
                    case "HELO":
                    case "EHLO":
                        HandleHelo(command, args);
                        break;
                    case "MAIL":
                        HandleMailFrom(args);
                        break;
                    case "RCPT":
                        HandleRcptTo(args);
                        break;
                    case "DATA":
                        HandleData();
                        break;
                    case "RSET":
                        HandleRset();
                        break;
                    case "NOOP":
                        SendResponse("250 OK");
                        break;
                    case "QUIT":
                        HandleQuit();
                        break;
                    default:
                        SendResponse($"500 Command not recognized: {command}");
                        break;
                }
            }
            catch (Exception ex)
            {
                //mainForm.Debug($"SMTP command error: {ex.Message}");
                SendResponse($"451 Requested action aborted: {ex.Message}");
            }
        }

        private void HandleHelo(string command, string args)
        {
            if (command == "EHLO")
            {
                // RFC 5321 compliant EHLO response with extensions
                SendResponse("250-localhost");
                SendResponse("250-8BITMIME");
                SendResponse("250-SIZE 10240000");
                SendResponse("250 HELP");
            }
            else
            {
                // HELO response
                SendResponse("250 localhost");
            }
        }

        private void HandleMailFrom(string args)
        {
            // Parse MAIL FROM:<address>
            if (!args.ToUpper().StartsWith("FROM:"))
            {
                SendResponse("501 Syntax error in MAIL FROM command");
                return;
            }

            string address = args.Substring(5).Trim();
            if (address.StartsWith("<") && address.EndsWith(">"))
            {
                address = address.Substring(1, address.Length - 2);
            }

            mailFrom = address;
            rcptTo.Clear();
            SendResponse("250 OK");
        }

        private void HandleRcptTo(string args)
        {
            // Parse RCPT TO:<address>
            if (!args.ToUpper().StartsWith("TO:"))
            {
                SendResponse("501 Syntax error in RCPT TO command");
                return;
            }

            string address = args.Substring(3).Trim();
            if (address.StartsWith("<") && address.EndsWith(">"))
            {
                address = address.Substring(1, address.Length - 2);
            }

            rcptTo.Add(address);
            SendResponse("250 OK");
        }

        private void HandleData()
        {
            if (string.IsNullOrEmpty(mailFrom) || rcptTo.Count == 0)
            {
                SendResponse("503 Bad sequence of commands");
                return;
            }

            SendResponse("354 Start mail input; end with <CRLF>.<CRLF>");
            inDataMode = true;
            dataBuffer.Clear();
        }

        private void ProcessDataLine(string line)
        {
            // Check for end of data (single dot on a line)
            if (line == ".")
            {
                inDataMode = false;
                ProcessEmailData();
                return;
            }

            // Handle byte-stuffing (remove leading dot if present)
            if (line.StartsWith(".."))
            {
                line = line.Substring(1);
            }

            dataBuffer.AppendLine(line);
        }

        private bool IsValidUsername(string user)
        {
            /*
            if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(mainForm.callsign))
                return false;

            // Normalize to uppercase for comparison
            user = user.ToUpper();
            string callsign = mainForm.callsign.ToUpper();
            string callsignWithId = callsign;
            if (mainForm.stationId > 0)
                callsignWithId += "-" + mainForm.stationId;

            // Accept: callsign, callsign-stationId, callsign@winlink.org, callsign-stationId@winlink.org
            return user == callsign ||
                   user == callsignWithId ||
                   user == callsign + "@WINLINK.ORG" ||
                   user == callsignWithId + "@WINLINK.ORG";
            */
            return false;
        }

        private void ProcessEmailData()
        {
            try
            {
                string emailData = dataBuffer.ToString();
                
                // Parse email headers and body
                string from = mailFrom;
                string to = string.Join("; ", rcptTo);
                string cc = "";
                string subject = "";
                string body = "";
                DateTime dateTime = DateTime.Now;

                // Simple header parsing
                StringReader sr = new StringReader(emailData);
                string line;
                bool inHeaders = true;
                StringBuilder bodyBuilder = new StringBuilder();

                while ((line = sr.ReadLine()) != null)
                {
                    if (inHeaders)
                    {
                        if (string.IsNullOrWhiteSpace(line))
                        {
                            inHeaders = false;
                            continue;
                        }

                        if (line.StartsWith("From:", StringComparison.OrdinalIgnoreCase))
                        {
                            from = line.Substring(5).Trim();
                            // Remove angle brackets if present
                            if (from.Contains("<") && from.Contains(">"))
                            {
                                int start = from.IndexOf('<') + 1;
                                int end = from.IndexOf('>');
                                from = from.Substring(start, end - start);
                            }
                        }
                        else if (line.StartsWith("To:", StringComparison.OrdinalIgnoreCase))
                        {
                            to = line.Substring(3).Trim();
                        }
                        else if (line.StartsWith("Cc:", StringComparison.OrdinalIgnoreCase))
                        {
                            cc = line.Substring(3).Trim();
                        }
                        else if (line.StartsWith("Subject:", StringComparison.OrdinalIgnoreCase))
                        {
                            subject = line.Substring(8).Trim();
                        }
                        else if (line.StartsWith("Date:", StringComparison.OrdinalIgnoreCase))
                        {
                            string dateStr = line.Substring(5).Trim();
                            DateTime.TryParse(dateStr, out dateTime);
                        }
                    }
                    else
                    {
                        bodyBuilder.AppendLine(line);
                    }
                }

                body = bodyBuilder.ToString().TrimEnd();

                // Create new email and add to Outbox
                WinLinkMail mail = new WinLinkMail
                {
                    MID = Guid.NewGuid().ToString("N").Substring(0, 12).ToUpper(),
                    From = from,
                    To = to,
                    Cc = cc,
                    Subject = subject,
                    Body = body,
                    DateTime = dateTime,
                    Mailbox = "Outbox"
                };

                //mainForm.mailStore.AddMail(mail);
                //mainForm.UpdateMail();

                //mainForm.Debug($"SMTP: Email queued to Outbox - From: {from}, To: {to}, Subject: {subject}");
                SendResponse("250 OK: Message accepted for delivery");
            }
            catch (Exception ex)
            {
                //mainForm.Debug($"SMTP: Error processing email: {ex.Message}");
                SendResponse("554 Transaction failed");
            }
            finally
            {
                // Reset for next message
                mailFrom = null;
                rcptTo.Clear();
                dataBuffer.Clear();
            }
        }

        private void HandleRset()
        {
            mailFrom = null;
            rcptTo.Clear();
            dataBuffer.Clear();
            inDataMode = false;
            SendResponse("250 OK");
        }

        private void HandleQuit()
        {
            SendResponse("221 Bye");
            Close();
            // Throw exception to exit the read loop gracefully
            throw new InvalidOperationException("Client requested QUIT");
        }

        private void SendResponse(string response)
        {
            //mainForm.Debug($"SMTP S: {response}");
            writer.WriteLine(response);
        }

        public void Close()
        {
            try
            {
                client?.Close();
                //mainForm.Debug("SMTP: Client disconnected");
            }
            catch { }
            server.RemoveSession(this);
        }
    }
}
