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
using System.Text;
using System.Timers;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// YAPP (Yet Another Protocol for Packet) Implementation for HTCommander
    /// 
    /// This module implements the YAPP protocol for binary file transfer over packet radio.
    /// Based on YAPP protocol specification v1.1 by Jeff Jacobsen (WA7MBL) and extensions
    /// for YappC (YAPP with checksums) and resume functionality.
    /// 
    /// Supports downloading files from remote stations via the terminal.
    /// </summary>
    public class YappTransfer
    {
        private readonly AX25Session session;
        private readonly MainForm parent;
        private Timer timeoutTimer;
        
        // YAPP Control Characters (from specification)
        private static class Control
        {
            public const byte ACK = 0x06;
            public const byte ENQ = 0x05;
            public const byte SOH = 0x01;    // Start of Header
            public const byte STX = 0x02;    // Start of Text (Data)
            public const byte ETX = 0x03;    // End of Text (EOF)
            public const byte EOT = 0x04;    // End of Transmission
            public const byte NAK = 0x15;    // Negative Acknowledge
            public const byte CAN = 0x18;    // Cancel
            public const byte DLE = 0x10;    // Data Link Escape
        }
        
        // YAPP Packet Types
        private enum PacketType
        {
            // Acknowledgments
            RR = 0x01,    // Receive Ready
            RF = 0x02,    // Receive File  
            AF = 0x03,    // Ack EOF
            AT = 0x04,    // Ack EOT
            CA = 0x05,    // Cancel Ack
            RT = Control.ACK,  // Receive TPK (YappC)
            
            // Requests
            SI = 0x01,    // Send Init
            RI = 0x02,    // Receive Init
            
            // Data packets (use control chars directly)
            HD = Control.SOH,  // Header
            DT = Control.STX,  // Data
            EF = Control.ETX,  // End of File
            ET = Control.EOT,  // End of Transmission
            
            // Error/Control packets
            NR = Control.NAK,  // Not Ready
            RE = Control.NAK,  // Resume
            CN = Control.CAN,  // Cancel
            TX = Control.DLE   // Text
        }
        
        public enum YappState
        {
            Idle,
            R,    // Receive Init
            RH,   // Receive Header
            RD,   // Receive Data
            CW    // Cancel Wait
        }
        
        public enum YappMode
        {
            None,
            Receive
        }
        
        // Transfer state
        public YappState CurrentState { get; private set; } = YappState.Idle;
        public YappMode Mode { get; private set; } = YappMode.None;
        
        // Configuration
        public bool UseChecksum { get; set; } = true;       // YappC support
        public bool EnableResume { get; set; } = true;      // Resume support
        public int MaxRetries { get; set; } = 3;            // Maximum retry attempts
        public int TimeoutMs { get; set; } = 60000;         // 60 seconds
        public int BlockSize { get; set; } = 128;           // Default block size
        
        // File transfer properties
        private string currentFilename;
        private long fileSize;
        private long bytesTransferred;
        private long resumeOffset;
        private FileStream fileStream;
        private string downloadPath;
        private int retryCount;
        private bool useChecksumForTransfer;
        
        // Events
        public event EventHandler<YappProgressEventArgs> ProgressChanged;
        public event EventHandler<YappCompleteEventArgs> TransferComplete;
        public event EventHandler<YappErrorEventArgs> TransferError;
        
        public YappTransfer(AX25Session session, MainForm parent)
        {
            this.session = session ?? throw new ArgumentNullException(nameof(session));
            this.parent = parent ?? throw new ArgumentNullException(nameof(parent));
            
            // Subscribe to session events
            // Note: We do NOT subscribe to DataReceivedEvent here because ProcessIncomingData
            // is already being called from MainForm, which prevents duplicate packet processing
            session.StateChanged += OnSessionStateChanged;
            
            // Setup timeout timer
            timeoutTimer = new Timer();
            timeoutTimer.Elapsed += OnTimeout;
            timeoutTimer.AutoReset = false;
        }
        
        /// <summary>
        /// Start receive mode to accept incoming file transfers
        /// </summary>
        /// <param name="downloadPath">Directory path where files will be saved</param>
        public void StartReceiveMode(string downloadPath = null)
        {
            if (CurrentState != YappState.Idle)
            {
                OnError("Transfer already in progress");
                return;
            }
            
            this.downloadPath = downloadPath ?? Path.GetTempPath();
            
            // Ensure download directory exists
            if (!Directory.Exists(this.downloadPath))
            {
                try
                {
                    Directory.CreateDirectory(this.downloadPath);
                }
                catch (Exception ex)
                {
                    OnError($"Cannot create download directory: {ex.Message}");
                    return;
                }
            }
            
            Mode = YappMode.Receive;
            SetState(YappState.R);
            
            Log("YAPP receive mode activated, waiting for incoming transfers...");
            //parent?.AppendTerminalText($"[YAPP] Ready to receive files in: {this.downloadPath}\r\n", System.Drawing.Color.Blue);
        }
        
        /// <summary>
        /// Cancel the current transfer
        /// </summary>
        public void CancelTransfer(string reason = "Transfer cancelled by user")
        {
            if (CurrentState == YappState.Idle)
                return;
                
            Log($"Cancelling transfer: {reason}");
            
            SendCancel(reason);
            SetState(YappState.CW);
            
            CleanupTransfer();
            
            // Update UI
            parent?.updateTerminalFileTransferProgress(MainForm.TerminalFileTransferStates.Idle, "", 0, 0);
            
            OnError($"Transfer cancelled: {reason}");
        }
        
        /// <summary>
        /// Process incoming data and determine if it's YAPP protocol data
        /// Called from MainForm to route YAPP data before terminal display
        /// </summary>
        /// <param name="data">Incoming data bytes</param>
        /// <returns>True if data was handled by YAPP, false otherwise</returns>
        public bool ProcessIncomingData(byte[] data)
        {
            if (data == null || data.Length < 1)
                return false;

            // Always check for YAPP Send Init packet first
            if (IsYappTransferRequest(data))
            {
                // Auto-start receive mode if not already active
                if (Mode != YappMode.Receive)
                {
                    string downloadPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "HTCommander Downloads");
                    StartReceiveMode(downloadPath);
                }
                
                // Process the SI packet
                ProcessYappPacket(data);
                return true;
            }

            // If in receive mode, check if this is other YAPP data
            if (Mode == YappMode.Receive && IsYappData(data))
            {
                ProcessYappPacket(data);
                return true;
            }

            return false;
        }
        /// <summary>
        /// Automatically start YAPP in receive mode when session begins
        /// Called when AX25 session is established
        /// </summary>
        public void EnableAutoReceive()
        {
            string downloadPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "HTCommander Downloads");
            StartReceiveMode(downloadPath);
        }
        
        /// <summary>
        /// Check if data is a YAPP transfer request (SI packet)
        /// </summary>
        private bool IsYappTransferRequest(byte[] data)
        {
            return data.Length >= 2 && data[0] == Control.ENQ && data[1] == (byte)PacketType.SI;
        }
        
        /// <summary>
        /// Check if data contains YAPP protocol packets
        /// </summary>
        private bool IsYappData(byte[] data)
        {
            if (data.Length < 1) return false;

            byte firstByte = data[0];

            // Check for YAPP control characters and packet types
            return firstByte == Control.ENQ ||  // SI (Send Init) or RI (Receive Init)
                   firstByte == Control.SOH ||  // HD (Header)
                   firstByte == Control.STX ||  // DT (Data)
                   firstByte == Control.ETX ||  // EF (End of File)  
                   firstByte == Control.EOT ||  // ET (End of Transmission)
                   firstByte == Control.ACK ||  // Various ACK types (RR, RF, AF, AT, CA, RT)
                   firstByte == Control.NAK ||  // NR (Not Ready) or RE (Resume)
                   firstByte == Control.CAN ||  // CN (Cancel)
                   firstByte == Control.DLE;    // TX (Text - server mode)
        }
        
        private void OnDataReceived(AX25Session sender, byte[] data)
        {
            if (data == null || data.Length < 1)
                return;
                
            try
            {
                ProcessYappPacket(data);
            }
            catch (Exception ex)
            {
                Log($"Error processing YAPP packet: {ex.Message}");
                OnError($"Protocol error: {ex.Message}");
            }
        }
        
        private void OnSessionStateChanged(AX25Session sender, AX25Session.ConnectionState state)
        {
            if (state == AX25Session.ConnectionState.DISCONNECTED)
            {
                if (CurrentState != YappState.Idle)
                {
                    Log("Session disconnected during transfer");
                    //parent?.AppendTerminalText("[YAPP] Session disconnected during transfer\r\n", System.Drawing.Color.Red);
                }
                // Always reset YAPP state when session disconnects
                Reset();
            }
        }
        
        private void ProcessYappPacket(byte[] data)
        {
            if (CurrentState == YappState.Idle)
                return; // Not in YAPP mode
                
            byte type = data[0];
            
            switch (CurrentState)
            {
                case YappState.R:
                    ProcessReceiveInitState(data, type);
                    break;
                    
                case YappState.RH:
                    ProcessReceiveHeaderState(data, type);
                    break;
                    
                case YappState.RD:
                    ProcessReceiveDataState(data, type);
                    break;
                    
                case YappState.CW:
                    ProcessCancelWaitState(data, type);
                    break;
            }
        }
        
        /*
        private void CheckForIncomingTransfer(byte[] data)
        {
            if (data.Length >= 2 && data[0] == Control.ENQ && data[1] == (byte)PacketType.SI)
            {
                Log("Received SI (Send Init) - incoming file transfer request");
                
                // Send RR (Receive Ready) to accept the transfer
                SendReceiveReady();
                SetState(YappState.RH);
                StartTimeout();
                
                parent?.AppendTerminalText("[YAPP] Incoming file transfer request received\r\n", System.Drawing.Color.Green);
            }
        }
        */
        
        private void ProcessReceiveInitState(byte[] data, byte type)
        {
            if (type == Control.ENQ && data.Length >= 2 && data[1] == (byte)PacketType.SI)
            {
                // SI packet in R state - start transfer
                Log("Received SI (Send Init) - incoming file transfer request");
                
                // Send RR (Receive Ready) to accept the transfer
                SendReceiveReady();
                SetState(YappState.RH);
                StartTimeout();
                
                parent?.AppendTerminalString(false, null, null, "Incoming YAPP file transfer request received");
            }
            else if (type == Control.SOH) // HD - Header packet
            {
                ProcessHeaderPacket(data);
            }
            else if (type == Control.EOT) // ET - End of Transmission
            {
                SendAckEOT();
                CompleteTransfer();
            }
            else if (type == Control.CAN) // CN - Cancel
            {
                ProcessCancelPacket(data);
            }
        }
        
        private void ProcessReceiveHeaderState(byte[] data, byte type)
        {
            if (type == Control.SOH) // HD - Header packet
            {
                ProcessHeaderPacket(data);
            }
            else if (type == Control.EOT) // ET - End of Transmission
            {
                SendAckEOT();
                CompleteTransfer();
            }
            else if (type == Control.CAN) // CN - Cancel
            {
                ProcessCancelPacket(data);
            }
        }
        
        private void ProcessReceiveDataState(byte[] data, byte type)
        {
            if (type == Control.STX) // DT - Data packet
            {
                ProcessDataPacket(data);
            }
            else if (type == Control.ETX) // EF - End of File
            {
                ProcessEndOfFile();
            }
            else if (type == Control.CAN) // CN - Cancel
            {
                ProcessCancelPacket(data);
            }
        }
        
        private void ProcessCancelWaitState(byte[] data, byte type)
        {
            if (type == Control.ACK && data.Length >= 2 && data[1] == (byte)PacketType.CA) // CA - Cancel Ack
            {
                Log("Received CA (Cancel Acknowledge)");
                CleanupTransfer();
            }
            else if (type == Control.CAN) // CN - Another cancel
            {
                SendCancelAck();
            }
        }
        
        private void ProcessHeaderPacket(byte[] data)
        {
            if (data.Length < 3)
            {
                SendNotReady("Invalid header packet");
                return;
            }
            
            byte length = data[1];
            if (data.Length < 2 + length)
            {
                SendNotReady("Incomplete header packet");
                return;
            }
            
            byte[] headerData = new byte[length];
            Array.Copy(data, 2, headerData, 0, length);
            
            // Parse header: filename NUL filesize NUL [date time NUL]
            List<string> parts = ParseNullSeparatedStrings(headerData);
            
            if (parts.Count < 2)
            {
                SendNotReady("Invalid header format");
                return;
            }
            
            currentFilename = parts[0];
            
            if (!long.TryParse(parts[1], out fileSize))
            {
                SendNotReady("Invalid file size");
                return;
            }
            
            Log($"Received header: {currentFilename}, {fileSize} bytes");
            
            // Check if we should resume an existing file
            string filePath = Path.Combine(downloadPath, currentFilename);
            resumeOffset = 0;
            
            if (EnableResume && File.Exists(filePath))
            {
                FileInfo existingFile = new FileInfo(filePath);
                resumeOffset = existingFile.Length;
                
                if (resumeOffset > 0 && resumeOffset < fileSize)
                {
                    Log($"Resuming transfer at {resumeOffset} bytes");
                    bytesTransferred = resumeOffset;
                    
                    // Send resume request
                    SendResume(resumeOffset, UseChecksum);
                    SetState(YappState.RD);
                    
                    // Open file for appending
                    try
                    {
                        fileStream = new FileStream(filePath, FileMode.Append, FileAccess.Write);
                        useChecksumForTransfer = UseChecksum;
                        
                        // Update UI
                        parent?.updateTerminalFileTransferProgress(
                            MainForm.TerminalFileTransferStates.Receiving, 
                            currentFilename, 
                            (int)fileSize, 
                            (int)bytesTransferred);
                            
                        OnProgress();
                    }
                    catch (Exception ex)
                    {
                        SendNotReady($"Cannot open file for resume: {ex.Message}");
                    }
                    return;
                }
                else if (resumeOffset >= fileSize)
                {
                    Log("File already complete");
                    SendNotReady("File already exists and is complete");
                    return;
                }
            }
            
            // Create new file
            try
            {
                fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write);
                bytesTransferred = 0;
                resumeOffset = 0;
                
                Log($"Created file: {filePath}");
            }
            catch (Exception ex)
            {
                SendNotReady($"Cannot create file: {ex.Message}");
                return;
            }
            
            SetState(YappState.RD);
            
            // Send appropriate response based on checksum support
            if (UseChecksum)
            {
                SendReceiveTPK(); // Request YappC mode
                useChecksumForTransfer = true;
            }
            else
            {
                SendReceiveFile(); // Standard YAPP mode
                useChecksumForTransfer = false;
            }
            
            // Update UI
            parent?.updateTerminalFileTransferProgress(
                MainForm.TerminalFileTransferStates.Receiving, 
                currentFilename, 
                (int)fileSize, 
                (int)bytesTransferred);
                
            OnProgress();
        }
        
        private void ProcessDataPacket(byte[] data)
        {
            if (data.Length < 2)
            {
                CancelTransfer("Invalid data packet");
                return;
            }
            
            byte lengthByte = data[1];
            int dataLength = lengthByte == 0 ? 256 : lengthByte;
            
            byte[] packetData;
            
            if (useChecksumForTransfer)
            {
                // YappC mode - last byte is checksum
                if (data.Length < dataLength + 3)
                {
                    CancelTransfer("Invalid YappC data packet length");
                    return;
                }
                
                packetData = new byte[dataLength];
                Array.Copy(data, 2, packetData, 0, dataLength);
                
                byte checksum = data[2 + dataLength];
                
                // Verify checksum
                byte calculatedChecksum = 0;
                foreach (byte b in packetData)
                {
                    calculatedChecksum = (byte)((calculatedChecksum + b) & 0xFF);
                }
                
                if (calculatedChecksum != checksum)
                {
                    Log($"Checksum mismatch: expected {checksum}, got {calculatedChecksum}");
                    CancelTransfer("Checksum error - data corruption detected");
                    return;
                }
            }
            else
            {
                // Standard YAPP mode
                if (data.Length < dataLength + 2)
                {
                    CancelTransfer("Invalid YAPP data packet length");
                    return;
                }
                
                packetData = new byte[dataLength];
                Array.Copy(data, 2, packetData, 0, dataLength);
            }
            
            // Write data to file
            try
            {
                fileStream.Write(packetData, 0, packetData.Length);
                fileStream.Flush();
                bytesTransferred += packetData.Length;
                
                Log($"Received data block: {packetData.Length} bytes ({bytesTransferred}/{fileSize})");
                
                // Update UI
                parent?.updateTerminalFileTransferProgress(
                    MainForm.TerminalFileTransferStates.Receiving, 
                    currentFilename, 
                    (int)fileSize, 
                    (int)bytesTransferred);
                
                OnProgress();
                RestartTimeout();
                
                // IMPORTANT: Send ACK to request next data block
                // In YAPP, the receiver must acknowledge each data block to continue the transfer
                SendDataAck();
            }
            catch (Exception ex)
            {
                CancelTransfer($"File write error: {ex.Message}");
            }
        }
        
        private void ProcessEndOfFile()
        {
            Log("Received EF (End of File)");
            
            if (fileStream != null)
            {
                fileStream.Close();
                fileStream = null;
            }
            
            SendAckEOF();
            
            // Notify file completion with specific file details
            string completedFile = Path.Combine(downloadPath, currentFilename);
            parent?.AppendTerminalString(false, null, null, $"YAPP file completed: {currentFilename} ({bytesTransferred} bytes)");
            
            OnFileComplete();
            
            SetState(YappState.RH); // Back to receive header for potential next file
        }
        
        private void ProcessCancelPacket(byte[] data)
        {
            string reason = "Transfer cancelled";
            if (data.Length > 2)
            {
                byte length = data[1];
                if (length > 0 && data.Length >= 2 + length)
                {
                    reason = Encoding.UTF8.GetString(data, 2, length);
                }
            }
            
            Log($"Received CN: {reason}");
            SendCancelAck();
            SetState(YappState.CW);
            
            OnError($"Remote cancelled: {reason}");
        }
        
        #region Packet Sending Methods
        
        private void SendReceiveReady()
        {
            Log("Sending RR (Receive Ready)");
            byte[] packet = { Control.ACK, (byte)PacketType.RR };
            session.Send(packet);
        }
        
        private void SendReceiveFile()
        {
            Log("Sending RF (Receive File)");
            byte[] packet = { Control.ACK, (byte)PacketType.RF };
            session.Send(packet);
        }
        
        private void SendReceiveTPK()
        {
            Log("Sending RT (Receive TPK - YappC mode)");
            byte[] packet = { Control.ACK, Control.ACK };
            session.Send(packet);
        }
        
        private void SendAckEOF()
        {
            Log("Sending AF (Ack EOF)");
            byte[] packet = { Control.ACK, (byte)PacketType.AF };
            session.Send(packet);
        }
        
        private void SendAckEOT()
        {
            Log("Sending AT (Ack EOT)");
            byte[] packet = { Control.ACK, (byte)PacketType.AT };
            session.Send(packet);
        }
        
        private void SendNotReady(string reason)
        {
            Log($"Sending NR (Not Ready): {reason}");
            byte[] reasonBytes = Encoding.UTF8.GetBytes(reason);
            byte[] packet = new byte[2 + reasonBytes.Length];
            packet[0] = Control.NAK;
            packet[1] = (byte)reasonBytes.Length;
            Array.Copy(reasonBytes, 0, packet, 2, reasonBytes.Length);
            session.Send(packet);
        }
        
        private void SendCancel(string reason = "Transfer cancelled")
        {
            Log($"Sending CN (Cancel): {reason}");
            byte[] reasonBytes = Encoding.UTF8.GetBytes(reason);
            byte[] packet = new byte[2 + reasonBytes.Length];
            packet[0] = Control.CAN;
            packet[1] = (byte)reasonBytes.Length;
            Array.Copy(reasonBytes, 0, packet, 2, reasonBytes.Length);
            session.Send(packet);
        }
        
        private void SendCancelAck()
        {
            Log("Sending CA (Cancel Ack)");
            byte[] packet = { Control.ACK, (byte)PacketType.CA };
            session.Send(packet);
        }
        
        private void SendDataAck()
        {
            // In YAPP protocol, after receiving a data block, send an ACK to request the next block
            // This is typically an RR (Receive Ready) to indicate we're ready for more data
            Log("Sending data ACK (ready for next block)");
            byte[] packet = { Control.ACK, (byte)PacketType.RR };
            session.Send(packet);
        }
        
        private void SendResume(long receivedLength, bool useYappC)
        {
            Log($"Sending RE (Resume) at {receivedLength} bytes, YappC: {useYappC}");
            
            List<byte> data = new List<byte>();
            data.Add((byte)'R');  // Resume marker
            data.Add(0x00);       // NUL
            
            // Received length in ASCII
            byte[] lengthBytes = Encoding.ASCII.GetBytes(receivedLength.ToString());
            data.AddRange(lengthBytes);
            data.Add(0x00);       // NUL
            
            // Add 'C' flag for YappC if requested
            if (useYappC)
            {
                data.Add((byte)'C');
                data.Add(0x00);   // NUL
            }
            
            byte[] packet = new byte[2 + data.Count];
            packet[0] = Control.NAK;
            packet[1] = (byte)data.Count;
            data.CopyTo(packet, 2);
            
            session.Send(packet);
        }
        
        #endregion
        
        #region Helper Methods
        
        private List<string> ParseNullSeparatedStrings(byte[] data)
        {
            List<string> result = new List<string>();
            List<byte> current = new List<byte>();
            
            foreach (byte b in data)
            {
                if (b == 0x00)
                {
                    if (current.Count > 0)
                    {
                        result.Add(Encoding.UTF8.GetString(current.ToArray()));
                        current.Clear();
                    }
                }
                else
                {
                    current.Add(b);
                }
            }
            
            if (current.Count > 0)
            {
                result.Add(Encoding.UTF8.GetString(current.ToArray()));
            }
            
            return result;
        }
        
        private void SetState(YappState newState)
        {
            if (CurrentState != newState)
            {
                Log($"State change: {CurrentState} -> {newState}");
                CurrentState = newState;
                
                if (newState == YappState.Idle)
                {
                    StopTimeout();
                    Mode = YappMode.None;
                }
                else
                {
                    RestartTimeout();
                }
            }
        }
        
        private void StartTimeout()
        {
            timeoutTimer.Interval = TimeoutMs;
            timeoutTimer.Start();
        }
        
        private void RestartTimeout()
        {
            timeoutTimer.Stop();
            StartTimeout();
        }
        
        private void StopTimeout()
        {
            timeoutTimer.Stop();
        }
        
        private void OnTimeout(object sender, ElapsedEventArgs e)
        {
            Log($"Timeout in state {CurrentState}");
            
            if (retryCount < MaxRetries)
            {
                retryCount++;
                Log($"Retry {retryCount}/{MaxRetries}");
                RestartTimeout();
            }
            else
            {
                Log("Max retries exceeded");
                CancelTransfer("Timeout - max retries exceeded");
            }
        }
        
        private void CompleteTransfer()
        {
            Log("Transfer completed successfully");
            
            // Store current mode before cleanup
            bool wasInReceiveMode = (Mode == YappMode.Receive);
            
            CleanupTransfer();
            
            // Update UI
            parent?.updateTerminalFileTransferProgress(MainForm.TerminalFileTransferStates.Idle, "", 0, 0);
            
            // Display overall transfer completion message
            //parent?.AppendTerminalString(false, null, null, "YAPP transfer completed successfully");
            
            // Fire the TransferComplete event (for EOT - end of all transfers)
            TransferComplete?.Invoke(this, new YappCompleteEventArgs
            {
                Filename = "",
                FileSize = 0,
                BytesTransferred = 0,
                FilePath = ""
            });
            
            // Return to listening if we were in receive mode
            if (wasInReceiveMode)
            {
                SetState(YappState.R);
                Log("Ready for next file transfer");
            }
            CurrentState = YappState.Idle;
        }
        
        private void CleanupTransfer()
        {
            StopTimeout();
            
            if (fileStream != null)
            {
                try
                {
                    fileStream.Close();
                }
                catch (Exception ex)
                {
                    Log($"Error closing file: {ex.Message}");
                }
                fileStream = null;
            }
            
            // Don't change state here - let the caller decide
            // This allows better control of state transitions
            
            retryCount = 0;
            currentFilename = null;
            fileSize = 0;
            bytesTransferred = 0;
            resumeOffset = 0;
            useChecksumForTransfer = false;
        }
        
        private void Log(string message)
        {
            parent?.Debug($"YAPP: {message}");
        }
        
        #endregion
        
        #region Event Handlers
        
        private void OnProgress()
        {
            ProgressChanged?.Invoke(this, new YappProgressEventArgs
            {
                Filename = currentFilename,
                FileSize = fileSize,
                BytesTransferred = bytesTransferred,
                Percentage = fileSize > 0 ? (int)((bytesTransferred * 100) / fileSize) : 0
            });
        }
        
        private void OnFileComplete()
        {
            TransferComplete?.Invoke(this, new YappCompleteEventArgs
            {
                Filename = currentFilename,
                FileSize = fileSize,
                BytesTransferred = bytesTransferred,
                FilePath = Path.Combine(downloadPath, currentFilename)
            });
        }
        
        
        private void OnError(string error)
        {
            // Store current mode before cleanup
            bool wasInReceiveMode = (Mode == YappMode.Receive);
            
            CleanupTransfer();
            
            TransferError?.Invoke(this, new YappErrorEventArgs
            {
                Error = error,
                Filename = currentFilename
            });
            
            // Return to listening if we were in receive mode
            if (wasInReceiveMode)
            {
                SetState(YappState.R);
                Log("Ready for next file transfer after error");
            }
            else
            {
                SetState(YappState.Idle);
            }
        }
        
        #endregion
        
        /// <summary>
        /// Reset YAPP state to prepare for a new session
        /// Called when AX25 session is closed to clean up properly
        /// </summary>
        public void Reset()
        {
            Log("Resetting YAPP state");
            
            CleanupTransfer();
            SetState(YappState.Idle);
            Mode = YappMode.None;
            
            // Update UI
            parent?.updateTerminalFileTransferProgress(MainForm.TerminalFileTransferStates.Idle, "", 0, 0);
        }
        
        public void Dispose()
        {
            CleanupTransfer();
            
            if (session != null)
            {
                session.DataReceivedEvent -= OnDataReceived;
                session.StateChanged -= OnSessionStateChanged;
            }
            
            timeoutTimer?.Dispose();
        }
    }
    
    #region Event Args Classes
    
    public class YappProgressEventArgs : EventArgs
    {
        public string Filename { get; set; }
        public long FileSize { get; set; }
        public long BytesTransferred { get; set; }
        public int Percentage { get; set; }
    }
    
    public class YappCompleteEventArgs : EventArgs
    {
        public string Filename { get; set; }
        public long FileSize { get; set; }
        public long BytesTransferred { get; set; }
        public string FilePath { get; set; }
    }
    
    public class YappErrorEventArgs : EventArgs
    {
        public string Error { get; set; }
        public string Filename { get; set; }
    }
    
    #endregion
}
