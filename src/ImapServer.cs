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
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using HTCommander.radio;

namespace HTCommander
{
    public class ImapServer
    {
        private MainForm mainForm;
        private TcpListener listener;
        private Thread listenerThread;
        private bool running;
        public readonly int Port;
        private List<ImapSession> sessions = new List<ImapSession>();

        public ImapServer(MainForm mainForm, int port)
        {
            this.mainForm = mainForm;
            this.Port = port;
        }

        public void Start()
        {
            try
            {
                listener = new TcpListener(IPAddress.Any, Port);
                listener.Start();
                running = true;
                listenerThread = new Thread(ListenerLoop);
                listenerThread.IsBackground = true;
                listenerThread.Start();
                mainForm.Debug($"IMAP server started on port {Port}");
            }
            catch (Exception ex)
            {
                mainForm.Debug($"IMAP server failed to start: {ex.Message}");
            }
        }

        public void Stop()
        {
            running = false;
            if (listener != null) listener.Stop();
            lock (sessions)
            {
                ImapSession[] sessionArray = new ImapSession[sessions.Count];
                sessions.CopyTo(sessionArray, 0);
                foreach (var session in sessionArray)
                {
                    session.Close();
                }
                sessions.Clear();
            }
            mainForm.Debug("IMAP server stopped");
        }

        private void ListenerLoop()
        {
            while (running)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    ImapSession session = new ImapSession(this, mainForm, client);
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

        public void RemoveSession(ImapSession session)
        {
            lock (sessions)
            {
                sessions.Remove(session);
            }
        }
    }

    public class ImapSession
    {
        private ImapServer server;
        private MainForm mainForm;
        private TcpClient client;
        private StreamReader reader;
        private StreamWriter writer;
        private bool authenticated;
        private string username;
        private int selectedMailbox = -1;
        private Dictionary<int, uint> messageUids = new Dictionary<int, uint>();
        private Dictionary<int, HashSet<string>> messageFlags = new Dictionary<int, HashSet<string>>();
        private uint uidNext = 1;

        // IMAP folder names mapped to mailbox indices
        private readonly Dictionary<string, int> folderToMailbox = new Dictionary<string, int>
        {
            { "INBOX", 0 },
            { "Outbox", 1 },
            { "Drafts", 2 },
            { "Sent", 3 },
            { "Archive", 4 },
            { "Trash", 5 }
        };

        private readonly Dictionary<int, string> mailboxToFolder = new Dictionary<int, string>
        {
            { 0, "INBOX" },
            { 1, "Outbox" },
            { 2, "Drafts" },
            { 3, "Sent" },
            { 4, "Archive" },
            { 5, "Trash" }
        };

        public ImapSession(ImapServer server, MainForm mainForm, TcpClient client)
        {
            this.server = server;
            this.mainForm = mainForm;
            this.client = client;
            this.reader = new StreamReader(client.GetStream(), Encoding.UTF8);
            this.writer = new StreamWriter(client.GetStream(), Encoding.UTF8) { AutoFlush = true };
        }

        public void Run()
        {
            try
            {
                mainForm.Debug("IMAP: Client connected");
                writer.WriteLine("* OK HTCommander IMAP Server Ready");

                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    
                    mainForm.Debug($"IMAP C: {line}");
                    ProcessCommand(line);
                }
            }
            catch (IOException)
            {
                // Connection closed by client, normal disconnect
            }
            catch (ObjectDisposedException)
            {
                // Stream/socket was disposed, normal during shutdown
            }
            catch (InvalidOperationException ex)
            {
                // This is expected when LOGOUT is called, don't log as error
                if (!ex.Message.Contains("LOGOUT"))
                    mainForm.Debug($"IMAP session error: {ex.Message}");
            }
            catch (Exception ex)
            {
                // Only log if not a connection-related error
                if (!ex.Message.Contains("Cannot access a disposed object"))
                    mainForm.Debug($"IMAP session error: {ex.Message}");
            }
            finally
            {
                Close();
            }
        }

        private void ProcessCommand(string line)
        {
            // Parse IMAP command: tag command [args...]
            string[] parts = line.Split(new[] { ' ' }, 3);
            if (parts.Length < 2) return;

            string tag = parts[0];
            string command = parts[1].ToUpper();
            string args = parts.Length > 2 ? parts[2] : "";

            try
            {
                switch (command)
                {
                    case "CAPABILITY":
                        HandleCapability(tag);
                        break;
                    case "AUTHENTICATE":
                        HandleAuthenticate(tag, args);
                        break;
                    case "LOGIN":
                        HandleLogin(tag, args);
                        break;
                    case "LSUB":
                        HandleLsub(tag, args);
                        break;
                    case "LIST":
                        HandleList(tag, args);
                        break;
                    case "SELECT":
                        HandleSelect(tag, args);
                        break;
                    case "EXAMINE":
                        HandleExamine(tag, args);
                        break;
                    case "STATUS":
                        HandleStatus(tag, args);
                        break;
                    case "FETCH":
                        HandleFetch(tag, args);
                        break;
                    case "STORE":
                        HandleStore(tag, args);
                        break;
                    case "COPY":
                        HandleCopy(tag, args);
                        break;
                    case "EXPUNGE":
                        HandleExpunge(tag);
                        break;
                    case "SEARCH":
                        HandleSearch(tag, args);
                        break;
                    case "CLOSE":
                        HandleClose(tag);
                        break;
                    case "LOGOUT":
                        HandleLogout(tag);
                        break;
                    case "NOOP":
                        SendResponse(tag, "OK NOOP completed");
                        break;
                    case "UID":
                        HandleUidCommand(tag, args);
                        break;
                    case "APPEND":
                        HandleAppend(tag, args);
                        break;
                    default:
                        SendResponse(tag, $"BAD Unknown command: {command}");
                        break;
                }
            }
            catch (Exception ex)
            {
                // Don't log or respond if connection is already closed
                if (ex is IOException || ex is InvalidOperationException)
                {
                    // Connection closed, exit gracefully
                    return;
                }
                mainForm.Debug($"IMAP command error: {ex.Message}");
                try
                {
                    SendResponse(tag, $"BAD Command failed: {ex.Message}");
                }
                catch
                {
                    // Can't send response, connection is closed
                }
            }
        }

        private void HandleCapability(string tag)
        {
            writer.WriteLine("* CAPABILITY IMAP4rev1 AUTH=PLAIN UIDPLUS");
            SendResponse(tag, "OK CAPABILITY completed");
        }

        private void HandleLogin(string tag, string args)
        {
            // Parse LOGIN username password
            string[] parts = ParseImapString(args);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid LOGIN command");
                return;
            }

            string user = parts[0];
            string pass = parts[1];

            // Authenticate - accept multiple username formats
            if (IsValidUsername(user) && pass == mainForm.winlinkPassword)
            {
                authenticated = true;
                username = user;
                mainForm.Debug($"IMAP: User {username} authenticated");
                // Send capability info with successful login response (RFC 3501 requirement)
                SendResponse(tag, "OK [CAPABILITY IMAP4rev1 AUTH=PLAIN UIDPLUS] LOGIN completed");
            }
            else
            {
                mainForm.Debug($"IMAP: Authentication failed for {user}");
                SendResponse(tag, "NO LOGIN failed");
            }
        }

        private void HandleAuthenticate(string tag, string args)
        {
            // Thunderbird uses AUTHENTICATE PLAIN
            // For now, just reject it and let it fall back to LOGIN
            SendResponse(tag, "NO AUTHENTICATE not supported, use LOGIN");
        }

        private void HandleLsub(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // LSUB lists subscribed folders - for simplicity, return all folders
            foreach (var folder in folderToMailbox.Keys)
            {
                writer.WriteLine($"* LSUB () \"/\" \"{folder}\"");
            }
            
            SendResponse(tag, "OK LSUB completed");
        }

        private void HandleAppend(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // Parse: APPEND "folder" (\Flags) {size}
            string[] parts = args.Split(new[] { ' ' }, 3);
            if (parts.Length < 3)
            {
                SendResponse(tag, "BAD Invalid APPEND command");
                return;
            }

            string folderName = ParseImapString(parts[0])[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            // Parse flags (optional)
            string flagsStr = parts[1].Trim('(', ')');
            
            // Parse size {396}
            string sizeStr = parts[2].Trim('{', '}');
            if (!int.TryParse(sizeStr, out int messageSize))
            {
                SendResponse(tag, "BAD Invalid message size");
                return;
            }

            // Tell client we're ready to receive the message
            writer.WriteLine("+ Ready for literal data");

            // Read the message data
            char[] buffer = new char[messageSize];
            int totalRead = 0;
            while (totalRead < messageSize)
            {
                int read = reader.Read(buffer, totalRead, messageSize - totalRead);
                if (read == 0) break;
                totalRead += read;
            }

            string messageData = new string(buffer, 0, totalRead);
            
            // Read the trailing CRLF
            reader.ReadLine();

            // Parse the RFC822 message
            WinLinkMail mail = ParseRfc822Message(messageData);
            mail.Mailbox = mailboxIndex;
            mail.MID = Guid.NewGuid().ToString("N").Substring(0, 12).ToUpper();

            mainForm.Mails.Add(mail);
            mainForm.SaveMails();
            mainForm.UpdateMail();

            mainForm.Debug($"IMAP: Email appended to {folderName} - Subject: {mail.Subject}");
            SendResponse(tag, "OK APPEND completed");
        }

        private WinLinkMail ParseRfc822Message(string messageData)
        {
            WinLinkMail mail = new WinLinkMail
            {
                DateTime = DateTime.Now,
                From = "",
                To = "",
                Cc = "",
                Subject = "",
                Body = ""
            };

            StringReader sr = new StringReader(messageData);
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
                        mail.From = line.Substring(5).Trim();
                        // Remove angle brackets if present
                        if (mail.From.Contains("<") && mail.From.Contains(">"))
                        {
                            int start = mail.From.IndexOf('<') + 1;
                            int end = mail.From.IndexOf('>');
                            mail.From = mail.From.Substring(start, end - start);
                        }
                    }
                    else if (line.StartsWith("To:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.To = line.Substring(3).Trim();
                    }
                    else if (line.StartsWith("Cc:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.Cc = line.Substring(3).Trim();
                    }
                    else if (line.StartsWith("Subject:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.Subject = line.Substring(8).Trim();
                    }
                    else if (line.StartsWith("Date:", StringComparison.OrdinalIgnoreCase))
                    {
                        string dateStr = line.Substring(5).Trim();
                        DateTime tempDate;
                        if (DateTime.TryParse(dateStr, out tempDate))
                            mail.DateTime = tempDate;
                    }
                }
                else
                {
                    bodyBuilder.AppendLine(line);
                }
            }

            mail.Body = bodyBuilder.ToString().TrimEnd();
            return mail;
        }

        private bool IsValidUsername(string user)
        {
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
        }

        private void HandleList(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // Parse LIST reference pattern
            // Common formats: LIST "" "*", LIST "" "%", LIST "INBOX" "*"
            string[] parts = ParseImapString(args);
            if (parts.Length < 2)
            {
                // If no args provided, list all folders
                foreach (var folder in folderToMailbox.Keys)
                {
                    writer.WriteLine($"* LIST () \"/\" \"{folder}\"");
                }
                SendResponse(tag, "OK LIST completed");
                return;
            }

            string reference = parts[0];
            string pattern = parts[1];

            // List folders based on pattern
            // "*" means all folders, "%" means top-level folders only
            foreach (var folder in folderToMailbox.Keys)
            {
                // For simplicity, treat both * and % the same (we don't have hierarchy)
                writer.WriteLine($"* LIST () \"/\" \"{folder}\"");
            }
            
            SendResponse(tag, "OK LIST completed");
        }

        private void HandleSelect(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            string folderName = ParseImapString(args)[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            selectedMailbox = mailboxIndex;
            InitializeMailboxState();

            List<WinLinkMail> mails = GetMailsInMailbox(mailboxIndex);
            
            // Generate a consistent UIDVALIDITY based on the mailbox itself
            // This ensures same mailbox always has same UIDVALIDITY
            uint uidValidity = (uint)(mailboxIndex + 1000);
            
            writer.WriteLine($"* {mails.Count} EXISTS");
            writer.WriteLine($"* {mails.Count} RECENT");
            if (mails.Count > 0)
                writer.WriteLine($"* OK [UNSEEN 1]");
            writer.WriteLine($"* OK [UIDVALIDITY {uidValidity}]");
            writer.WriteLine($"* OK [UIDNEXT {uidNext}]");
            writer.WriteLine("* FLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)");
            writer.WriteLine("* OK [PERMANENTFLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)]");
            
            SendResponse(tag, $"OK [READ-WRITE] SELECT completed");
        }

        private void HandleExamine(string tag, string args)
        {
            // Same as SELECT but read-only
            HandleSelect(tag, args);
        }

        private void HandleStatus(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // STATUS "folder" (MESSAGES UNSEEN)
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid STATUS command");
                return;
            }

            string folderName = ParseImapString(parts[0])[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(mailboxIndex);
            writer.WriteLine($"* STATUS \"{folderName}\" (MESSAGES {mails.Count} UNSEEN 0)");
            SendResponse(tag, "OK STATUS completed");
        }

        private void HandleFetch(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set items
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid FETCH command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string items = parts[1].Trim('(', ')').ToUpper();

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            
            mainForm.Debug($"IMAP: FETCH {parts[0]} for mailbox {selectedMailbox}, {mails.Count} mails, {sequences.Count} sequences");

            foreach (int seq in sequences)
            {
                if (seq < 1 || seq > mails.Count)
                {
                    mainForm.Debug($"IMAP: Skipping sequence {seq}, out of range");
                    continue;
                }
                
                int index = seq - 1;
                WinLinkMail mail = mails[index];
                uint uid = messageUids[index];
                
                List<string> fetchItems = new List<string>();

                if (items.Contains("UID"))
                    fetchItems.Add($"UID {uid}");

                if (items.Contains("FLAGS"))
                {
                    string flags = GetFlagsString(index);
                    fetchItems.Add($"FLAGS ({flags})");
                }

                // If we only have basic items (UID, FLAGS, RFC822.SIZE, INTERNALDATE), output them
                bool hasOnlyBasicItems = !items.Contains("BODY") && !items.Contains("RFC822");
                
                mainForm.Debug($"IMAP: seq={seq}, hasOnlyBasicItems={hasOnlyBasicItems}, fetchItems.Count={fetchItems.Count}, items=[{items}]");
                
                if (hasOnlyBasicItems && fetchItems.Count > 0)
                {
                    string response = $"* {seq} FETCH (" + string.Join(" ", fetchItems) + ")";
                    mainForm.Debug($"IMAP: Sending basic FETCH: {response}");
                    writer.WriteLine(response);
                    continue;
                }

                if (items.Contains("INTERNALDATE"))
                    fetchItems.Add($"INTERNALDATE \"{mail.DateTime:dd-MMM-yyyy HH:mm:ss +0000}\"");

                if (items.Contains("RFC822.SIZE") || items.Contains("BODYSTRUCTURE"))
                {
                    string fullMessage = BuildRfc822Message(mail);
                    fetchItems.Add($"RFC822.SIZE {Encoding.UTF8.GetByteCount(fullMessage)}");
                }

                if (items.Contains("BODY.PEEK[HEADER]") || items.Contains("BODY[HEADER]"))
                {
                    string header = BuildRfc822Header(mail);
                    fetchItems.Add($"BODY[HEADER] {{{Encoding.UTF8.GetByteCount(header)}}}");
                    writer.WriteLine(string.Join(" ", fetchItems) + ")");
                    writer.WriteLine(header);
                    continue;
                }

                // Check for BODY.PEEK[HEADER - need to do this when NOT hasOnlyBasicItems
                if (!hasOnlyBasicItems && items.Contains("BODY.PEEK[HEADER"))
                {
                    string header = BuildRfc822Header(mail);
                    int headerSize = Encoding.UTF8.GetByteCount(header);
                    
                    // Add RFC822.SIZE if requested
                    if (items.Contains("RFC822.SIZE"))
                    {
                        string fullMessage = BuildRfc822Message(mail);
                        fetchItems.Add($"RFC822.SIZE {Encoding.UTF8.GetByteCount(fullMessage)}");
                    }
                    
                    fetchItems.Add($"BODY[HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID)] {{{headerSize}}}");
                    
                    mainForm.Debug($"IMAP: Sending BODY.PEEK response for seq {seq}");
                    writer.WriteLine($"* {seq} FETCH (" + string.Join(" ", fetchItems) + ")");
                    writer.Write(header); // Literal data
                    writer.WriteLine(); // CRLF after literal
                    writer.Flush();
                    continue;
                }

                if (items.Contains("BODY[]") || items.Contains("RFC822"))
                {
                    string fullMessage = BuildRfc822Message(mail);
                    fetchItems.Add($"BODY[] {{{Encoding.UTF8.GetByteCount(fullMessage)}}}");
                    writer.WriteLine(string.Join(" ", fetchItems) + ")");
                    writer.WriteLine(fullMessage);
                    continue;
                }

                writer.WriteLine(string.Join(" ", fetchItems) + ")");
            }

            SendResponse(tag, "OK FETCH completed");
        }

        private void HandleStore(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set FLAGS (\Seen \Deleted)
            string[] parts = args.Split(new[] { ' ' }, 3);
            if (parts.Length < 3)
            {
                SendResponse(tag, "BAD Invalid STORE command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string operation = parts[1].ToUpper();
            string flagsStr = parts[2].Trim('(', ')');
            
            bool isAdd = operation.Contains("+");
            bool isRemove = operation.Contains("-");

            foreach (int seq in sequences)
            {
                List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
                if (seq < 1 || seq > mails.Count) continue;
                
                int index = seq - 1;
                
                if (!messageFlags.ContainsKey(index))
                    messageFlags[index] = new HashSet<string>();

                if (isAdd)
                {
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Add(flag.Trim());
                }
                else if (isRemove)
                {
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Remove(flag.Trim());
                }
                else
                {
                    messageFlags[index].Clear();
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Add(flag.Trim());
                }

                writer.WriteLine($"* {seq} FETCH (FLAGS ({GetFlagsString(index)}))");
            }

            SendResponse(tag, "OK STORE completed");
        }

        private void HandleCopy(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set destination-folder
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid COPY command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string destFolder = ParseImapString(parts[1])[0];

            if (!folderToMailbox.TryGetValue(destFolder, out int destMailbox))
            {
                SendResponse(tag, "NO Destination folder not found");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);

            foreach (int seq in sequences)
            {
                if (seq < 1 || seq > mails.Count) continue;
                
                WinLinkMail mail = mails[seq - 1];
                WinLinkMail copy = new WinLinkMail
                {
                    MID = Guid.NewGuid().ToString("N").Substring(0, 12).ToUpper(),
                    From = mail.From,
                    To = mail.To,
                    Cc = mail.Cc,
                    Subject = mail.Subject,
                    Body = mail.Body,
                    DateTime = mail.DateTime,
                    Mailbox = destMailbox,
                    Attachements = mail.Attachements
                };
                
                mainForm.Mails.Add(copy);
            }

            mainForm.SaveMails();
            mainForm.UpdateMail();

            SendResponse(tag, "OK COPY completed");
        }

        private void HandleExpunge(string tag)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            List<int> toDelete = new List<int>();

            for (int i = 0; i < mails.Count; i++)
            {
                if (messageFlags.ContainsKey(i) && messageFlags[i].Contains("\\Deleted"))
                {
                    toDelete.Add(i);
                }
            }

            // Delete in reverse order to maintain indices
            toDelete.Reverse();
            foreach (int index in toDelete)
            {
                WinLinkMail mail = mails[index];
                mail.Mailbox = 5; // Move to Trash
                writer.WriteLine($"* {index + 1} EXPUNGE");
            }

            mainForm.SaveMails();
            mainForm.UpdateMail();
            InitializeMailboxState();

            SendResponse(tag, "OK EXPUNGE completed");
        }

        private void HandleSearch(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            List<int> results = new List<int>();

            // Simple search - just return ALL for now
            if (args.ToUpper().Contains("ALL"))
            {
                for (int i = 0; i < mails.Count; i++)
                {
                    results.Add(i + 1);
                }
            }

            writer.Write("* SEARCH");
            foreach (int seq in results)
            {
                writer.Write($" {seq}");
            }
            writer.WriteLine();

            SendResponse(tag, "OK SEARCH completed");
        }

        private void HandleUidCommand(string tag, string args)
        {
            // UID FETCH, UID STORE, UID SEARCH, UID COPY
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid UID command");
                return;
            }

            string subCommand = parts[0].ToUpper();
            string subArgs = parts[1];

            // Parse the UID set and convert to sequence numbers
            string[] argParts = subArgs.Split(new[] { ' ' }, 2);
            string uidSet = argParts[0];
            string restOfArgs = argParts.Length > 1 ? argParts[1] : "";

            // Convert UID set to sequence set
            List<int> sequences = ParseUidSet(uidSet);
            string sequenceSet = string.Join(",", sequences);

            // For UID FETCH, ensure UID is in the items list
            if (subCommand == "FETCH" && !string.IsNullOrEmpty(restOfArgs))
            {
                string items = restOfArgs.Trim('(', ')').ToUpper();
                if (!items.Contains("UID"))
                {
                    restOfArgs = "(UID " + restOfArgs.TrimStart('(');
                }
            }

            string convertedArgs = sequenceSet + (string.IsNullOrEmpty(restOfArgs) ? "" : " " + restOfArgs);

            // Execute command with converted sequence numbers
            switch (subCommand)
            {
                case "FETCH":
                    HandleFetch(tag, convertedArgs);
                    break;
                case "STORE":
                    HandleStore(tag, convertedArgs);
                    break;
                case "SEARCH":
                    HandleSearch(tag, convertedArgs);
                    break;
                case "COPY":
                    HandleCopy(tag, convertedArgs);
                    break;
                default:
                    SendResponse(tag, $"BAD Unknown UID command: {subCommand}");
                    break;
            }
        }

        private List<int> ParseUidSet(string uidSet)
        {
            List<int> sequences = new List<int>();

            foreach (string part in uidSet.Split(','))
            {
                if (part.Contains(':'))
                {
                    string[] range = part.Split(':');
                    
                    // Handle cases like "1234:*" where * means "to the end"
                    uint startUid;
                    if (!uint.TryParse(range[0], out startUid))
                        continue;
                    
                    uint endUid = range[1] == "*" ? uint.MaxValue : uint.Parse(range[1]);

                    // Find all sequences with UIDs in this range
                    for (int i = 0; i < messageUids.Count; i++)
                    {
                        uint uid = messageUids[i];
                        if (uid >= startUid && uid <= endUid)
                            sequences.Add(i + 1); // Convert to 1-based sequence
                    }
                }
                else
                {
                    if (part == "*")
                    {
                        // "*" means the highest UID
                        if (messageUids.Count > 0)
                            sequences.Add(messageUids.Count);
                    }
                    else
                    {
                        uint uid;
                        if (!uint.TryParse(part, out uid))
                            continue;
                        
                        // Find sequence number for this UID
                        for (int i = 0; i < messageUids.Count; i++)
                        {
                            if (messageUids[i] == uid)
                            {
                                sequences.Add(i + 1); // Convert to 1-based sequence
                                break;
                            }
                        }
                    }
                }
            }

            return sequences.Distinct().OrderBy(x => x).ToList();
        }

        private void HandleClose(string tag)
        {
            selectedMailbox = -1;
            messageUids.Clear();
            messageFlags.Clear();
            SendResponse(tag, "OK CLOSE completed");
        }

        private void HandleLogout(string tag)
        {
            writer.WriteLine("* BYE HTCommander IMAP Server logging out");
            SendResponse(tag, "OK LOGOUT completed");
            Close();
            // Throw exception to exit the read loop gracefully
            throw new InvalidOperationException("Client requested LOGOUT");
        }

        private void InitializeMailboxState()
        {
            messageUids.Clear();
            messageFlags.Clear();
            
            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            for (int i = 0; i < mails.Count; i++)
            {
                // Generate consistent UID from email's MID hash
                // This ensures the same email always has the same UID
                uint uid = (uint)Math.Abs(mails[i].MID.GetHashCode());
                messageUids[i] = uid;
                messageFlags[i] = new HashSet<string>();
                
                // Track highest UID for UIDNEXT
                if (uid >= uidNext)
                    uidNext = uid + 1;
            }
        }

        private List<WinLinkMail> GetMailsInMailbox(int mailboxIndex)
        {
            var mails = mainForm.Mails.Where(m => m.Mailbox == mailboxIndex).ToList();
            
            // Debug: Show all emails and their mailbox indices
            if (mailboxIndex == 1) // Outbox
            {
                mainForm.Debug($"IMAP: Total emails in system: {mainForm.Mails.Count}");
                mainForm.Debug($"IMAP: Emails in Outbox (mailbox {mailboxIndex}): {mails.Count}");
                foreach (var mail in mainForm.Mails)
                {
                    mainForm.Debug($"IMAP:   - Subject: '{mail.Subject}', Mailbox: {mail.Mailbox}, Folder: {(mailboxToFolder.ContainsKey(mail.Mailbox) ? mailboxToFolder[mail.Mailbox] : "Unknown")}");
                }
            }
            
            return mails;
        }

        private string BuildRfc822Header(WinLinkMail mail)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine($"From: {mail.From}");
            sb.AppendLine($"To: {mail.To}");
            if (!string.IsNullOrEmpty(mail.Cc))
                sb.AppendLine($"Cc: {mail.Cc}");
            sb.AppendLine($"Subject: {mail.Subject}");
            sb.AppendLine($"Date: {mail.DateTime:R}");
            sb.AppendLine($"Message-ID: <{mail.MID}@htcommander>");
            sb.AppendLine("MIME-Version: 1.0");
            sb.AppendLine("Content-Type: text/plain; charset=utf-8");
            sb.AppendLine();
            return sb.ToString();
        }

        private string BuildRfc822Message(WinLinkMail mail)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append(BuildRfc822Header(mail));
            sb.AppendLine(mail.Body ?? "");
            return sb.ToString();
        }

        private string GetFlagsString(int index)
        {
            if (!messageFlags.ContainsKey(index) || messageFlags[index].Count == 0)
                return "";
            return string.Join(" ", messageFlags[index]);
        }

        private List<int> ParseSequenceSet(string sequenceSet)
        {
            List<int> result = new List<int>();
            
            if (sequenceSet == "*")
            {
                List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
                for (int i = 1; i <= mails.Count; i++)
                    result.Add(i);
                return result;
            }

            foreach (string part in sequenceSet.Split(','))
            {
                if (part.Contains(':'))
                {
                    string[] range = part.Split(':');
                    int start = int.Parse(range[0]);
                    int end = range[1] == "*" ? GetMailsInMailbox(selectedMailbox).Count : int.Parse(range[1]);
                    for (int i = start; i <= end; i++)
                        result.Add(i);
                }
                else
                {
                    result.Add(int.Parse(part));
                }
            }

            return result.Distinct().OrderBy(x => x).ToList();
        }

        private string[] ParseImapString(string input)
        {
            List<string> result = new List<string>();
            bool inQuotes = false;
            StringBuilder current = new StringBuilder();

            for (int i = 0; i < input.Length; i++)
            {
                char c = input[i];

                if (c == '"')
                {
                    inQuotes = !inQuotes;
                }
                else if (c == ' ' && !inQuotes)
                {
                    if (current.Length > 0)
                    {
                        result.Add(current.ToString());
                        current.Clear();
                    }
                }
                else
                {
                    current.Append(c);
                }
            }

            if (current.Length > 0)
                result.Add(current.ToString());

            return result.ToArray();
        }

        private void SendResponse(string tag, string response)
        {
            string line = $"{tag} {response}";
            mainForm.Debug($"IMAP S: {line}");
            writer.WriteLine(line);
        }

        public void Close()
        {
            try
            {
                client?.Close();
                mainForm.Debug("IMAP: Client disconnected");
            }
            catch { }
            server.RemoveSession(this);
        }
    }
}
