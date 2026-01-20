/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;

namespace HTCommander
{
    public class Torrent : IDisposable
    {
        private DataBrokerClient broker;
        private bool Active = false;
        public List<TorrentFile> Files = new List<TorrentFile>();
        public TorrentFile Advertised = null;
        public List<TorrentFile> Stations = new List<TorrentFile>();
        public const int DefaultBlockSize = 170;
        public bool FirstDiscovery = true;
        private List<int> lockedTorrentRadios = new List<int>();
        private System.Timers.Timer advertisementTimer;

        public Torrent()
        {
            broker = new DataBrokerClient();
            
            // Subscribe to UniqueDataFrame from all devices to receive torrent packets
            broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnDataFrameReceived);
            
            // Subscribe to LockState from all devices to track locked radios
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);
            
            // Subscribe to UI commands
            broker.Subscribe(0, "TorrentAddFile", OnTorrentAddFile);
            broker.Subscribe(0, "TorrentRemoveFile", OnTorrentRemoveFile);
            broker.Subscribe(0, "TorrentSetFileMode", OnTorrentSetFileMode);
            broker.Subscribe(0, "TorrentGetFiles", OnTorrentGetFiles);
            broker.Subscribe(0, "TorrentGetStations", OnTorrentGetStations);
            
            // Load persisted torrent files from disk
            LoadTorrentFilesFromDisk();
            
            broker.LogInfo("[Torrent] Torrent handler initialized");
            
            // Publish initial state
            PublishFilesUpdate();
            PublishStationsUpdate();
            SaveTorrentState();
        }

        public void Dispose()
        {
            StopAdvertising();
            advertisementTimer?.Dispose();
            broker?.Dispose();
        }

        // UI Command Handlers
        private void OnTorrentAddFile(int deviceId, string name, object data)
        {
            if (!(data is TorrentFile file)) return;
            
            if (Add(file))
            {
                broker.LogInfo($"[Torrent] Added file: {file.FileName}");
                PublishFilesUpdate();
            }
        }

        private void OnTorrentRemoveFile(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            byte[] fileId = null;
            
            // Handle TorrentFile object directly
            if (data is TorrentFile torrentFile)
            {
                fileId = torrentFile.Id;
            }
            else
            {
                // Handle anonymous type from UI
                var dataType = data.GetType();
                fileId = dataType.GetProperty("Id")?.GetValue(data) as byte[];
            }
            
            if (fileId == null) return;
            
            // Find file by ID
            TorrentFile file = Files.FirstOrDefault(f => f.Id != null && f.Id.SequenceEqual(fileId));
            if (file != null)
            {
                Files.Remove(file);
                UpdateAdvertised();
                PublishFilesUpdate();
                SaveTorrentState();
                broker.LogInfo($"[Torrent] Removed file: {file.FileName}");
            }
        }

        private void OnTorrentSetFileMode(int deviceId, string name, object data)
        {
            // Expects: { FileId = byte[], Mode = TorrentFile.TorrentModes }
            if (data == null) return;
            
            var dataType = data.GetType();
            byte[] fileId = dataType.GetProperty("FileId")?.GetValue(data) as byte[];
            object modeObj = dataType.GetProperty("Mode")?.GetValue(data);
            
            if (fileId == null || modeObj == null) return;
            
            TorrentFile.TorrentModes mode = (TorrentFile.TorrentModes)modeObj;
            
            // Find file by ID
            TorrentFile file = Files.FirstOrDefault(f => f.Id != null && f.Id.SequenceEqual(fileId));
            if (file != null && file.Mode != mode)
            {
                file.Mode = mode;
                file.WriteTorrentFile();
                broker.LogInfo($"[Torrent] Changed mode for {file.FileName} to {mode}");
                PublishFileUpdate(file);
                SaveTorrentState();
            }
        }

        private void OnTorrentGetFiles(int deviceId, string name, object data)
        {
            // Respond with current files list
            PublishFilesUpdate();
        }

        private void OnTorrentGetStations(int deviceId, string name, object data)
        {
            // Respond with current stations list
            PublishStationsUpdate();
        }

        // State Publishing Methods
        private void PublishFilesUpdate()
        {
            var filesList = Files.Select(f => new
            {
                Id = f.Id,
                ShortId = f.ShortId,
                Callsign = f.Callsign,
                StationId = f.StationId,
                FileName = f.FileName,
                Description = f.Description,
                Size = f.Size,
                CompressedSize = f.CompressedSize,
                Compression = f.Compression.ToString(),
                Mode = f.Mode.ToString(),
                Completed = f.Completed,
                TotalBlocks = f.TotalBlocks,
                ReceivedBlocks = f.ReceivedBlocks,
                Progress = f.TotalBlocks > 0 ? (float)f.ReceivedBlocks / f.TotalBlocks : 0f
            }).ToList();
            
            broker.Dispatch(0, "TorrentFiles", filesList, store: false);
        }

        private void PublishStationsUpdate()
        {
            var stationsList = Stations.Select(s => new
            {
                Id = s.Id,
                ShortId = s.ShortId,
                Callsign = s.Callsign,
                StationId = s.StationId,
                Mode = s.Mode.ToString(),
                Completed = s.Completed,
                TotalBlocks = s.TotalBlocks,
                ReceivedBlocks = s.ReceivedBlocks,
                Progress = s.TotalBlocks > 0 ? (float)s.ReceivedBlocks / s.TotalBlocks : 0f
            }).ToList();
            
            broker.Dispatch(0, "TorrentStations", stationsList, store: false);
        }

        private void PublishFileUpdate(TorrentFile file)
        {
            var fileData = new
            {
                Id = file.Id,
                ShortId = file.ShortId,
                Callsign = file.Callsign,
                StationId = file.StationId,
                FileName = file.FileName,
                Description = file.Description,
                Size = file.Size,
                CompressedSize = file.CompressedSize,
                Compression = file.Compression.ToString(),
                Mode = file.Mode.ToString(),
                Completed = file.Completed,
                TotalBlocks = file.TotalBlocks,
                ReceivedBlocks = file.ReceivedBlocks,
                Progress = file.TotalBlocks > 0 ? (float)file.ReceivedBlocks / file.TotalBlocks : 0f
            };
            
            broker.Dispatch(0, "TorrentFileUpdate", fileData, store: false);
        }

        private void PublishStationUpdate(TorrentFile station)
        {
            var stationData = new
            {
                Id = station.Id,
                ShortId = station.ShortId,
                Callsign = station.Callsign,
                StationId = station.StationId,
                Mode = station.Mode.ToString(),
                Completed = station.Completed,
                TotalBlocks = station.TotalBlocks,
                ReceivedBlocks = station.ReceivedBlocks,
                Progress = station.TotalBlocks > 0 ? (float)station.ReceivedBlocks / station.TotalBlocks : 0f
            };
            
            broker.Dispatch(0, "TorrentStationUpdate", stationData, store: false);
        }

        // State persistence methods
        private void LoadTorrentFilesFromDisk()
        {
            try
            {
                List<TorrentFile> loadedFiles = TorrentFile.ReadTorrentFiles();
                Files.AddRange(loadedFiles);
                broker.LogInfo($"[Torrent] Loaded {loadedFiles.Count} torrent files from disk");
            }
            catch (Exception ex)
            {
                broker.LogError($"[Torrent] Error loading torrent files: {ex.Message}");
            }
        }

        private void SaveTorrentState()
        {
            // Save a summary of torrent state to DataBroker for persistence
            // Note: Actual file data is saved to disk via TorrentFile.WriteTorrentFile()
            // This just stores metadata that survives app restarts
            var torrentState = new
            {
                FileCount = Files.Count,
                LastUpdated = DateTime.Now,
                Files = Files.Select(f => new
                {
                    IdHex = f.Id != null ? Utils.BytesToHex(f.Id) : null,
                    f.Callsign,
                    f.StationId,
                    f.FileName,
                    f.Description,
                    f.Size,
                    f.CompressedSize,
                    Compression = f.Compression.ToString(),
                    Mode = f.Mode.ToString(),
                    f.Completed,
                    f.TotalBlocks,
                    f.ReceivedBlocks
                }).ToList()
            };
            
            broker.Dispatch(0, "TorrentState", torrentState, store: true);
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            if (!(data is RadioLockState lockState)) return;
            
            bool wasActive = lockedTorrentRadios.Count > 0;
            
            if (lockState.IsLocked && lockState.Usage == "Torrent")
            {
                if (!lockedTorrentRadios.Contains(deviceId))
                {
                    lockedTorrentRadios.Add(deviceId);
                    broker.LogInfo($"[Torrent] Radio {deviceId} locked to Torrent mode");
                }
            }
            else
            {
                if (lockedTorrentRadios.Remove(deviceId))
                {
                    broker.LogInfo($"[Torrent] Radio {deviceId} unlocked from Torrent mode");
                }
            }
            
            bool isActive = lockedTorrentRadios.Count > 0;
            
            // Start/stop based on active state change
            if (isActive && !wasActive)
            {
                StartAdvertising();
                FirstDiscovery = true;
                broker.LogInfo("[Torrent] Started advertising");
            }
            else if (!isActive && wasActive)
            {
                StopAdvertising();
                broker.LogInfo("[Torrent] Stopped advertising");
            }
        }

        private void OnDataFrameReceived(int deviceId, string name, object data)
        {
            if (!(data is TncDataFragment frame)) return;
            
            // Only process if usage is "Torrent"
            if (frame.usage != "Torrent") return;
            
            broker.LogInfo($"[Torrent] Received torrent frame from radio {deviceId}");
            
            // Convert to AX25Packet for processing
            List<AX25Address> addresses = new List<AX25Address>();
            AX25Packet packet = new AX25Packet(addresses, frame.data, frame.time);
            ProcessFrame(frame, packet);
        }

        private void StartAdvertising()
        {
            if (advertisementTimer == null)
            {
                advertisementTimer = new System.Timers.Timer(30000); // 30 seconds
                advertisementTimer.Elapsed += OnAdvertisementTimer;
            }
            advertisementTimer.Start();
        }

        private void StopAdvertising()
        {
            advertisementTimer?.Stop();
        }

        private void OnAdvertisementTimer(object sender, System.Timers.ElapsedEventArgs e)
        {
            SendRequestFrame(FirstDiscovery);
            FirstDiscovery = false;
        }

        public void ChannelIsClear()
        {
            // This method is no longer needed with DataBroker pattern
            // Channel clear events are handled by the Radio class
        }

        public bool Add(TorrentFile file)
        {
            if (Files.Contains(file)) return false;
            
            // Set the callsign and station ID from settings if not already set
            if (string.IsNullOrEmpty(file.Callsign))
            {
                file.Callsign = DataBroker.GetValue<string>(0, "CallSign", "NOCALL");
            }
            if (file.StationId == 0)
            {
                file.StationId = DataBroker.GetValue<int>(0, "StationId", 0);
            }
            
            Files.Add(file);
            UpdateAdvertised();
            PublishFilesUpdate();
            SaveTorrentState();
            return true;
        }

        public bool Remove(TorrentFile file)
        {
            if (!Files.Contains(file)) return false;
            Files.Remove(file);
            UpdateAdvertised();
            PublishFilesUpdate();
            SaveTorrentState();
            return true;
        }

        public void Activate(bool active)
        {
            if (Active == active) return;
            Active = active;
            if (active)
            {
                FirstDiscovery = true;
            }
        }

        private TorrentFile FindStationFile(string callsign, int stationId)
        {
            foreach (TorrentFile file in Stations)
            {
                if ((file.Callsign == callsign) && (file.StationId == stationId)) { return file; }
            }
            return null;
        }

        private TorrentFile FindTorrentFileWithShortId(string callsign, int stationId, byte[] shortId)
        {
            if ((Advertised != null) && (Advertised.Callsign == callsign) && (Advertised.StationId == stationId) && Advertised.ShortId.SequenceEqual(shortId))
            {
                return Advertised;
            }
            foreach (TorrentFile file in Files)
            {
                if (file.ShortId.SequenceEqual(shortId) && (file.Callsign == callsign) && (file.StationId == stationId)) { return file; }
            }
            foreach (TorrentFile file in Stations)
            {
                if (file.ShortId.SequenceEqual(shortId) && (file.Callsign == callsign) && (file.StationId == stationId)) { return file; }
            }
            return null;
        }

        public void SendRequest()
        {
            // Send a request frame
            SendRequestFrame(FirstDiscovery);
            FirstDiscovery = false;
        }

        private void SendRequestFrame(bool discovery = false)
        {
            if (lockedTorrentRadios.Count == 0) return;

            MemoryStream ms = new MemoryStream();
            BinaryWriter writer = new BinaryWriter(ms);
            writer.Write((byte)1); // Version
            writer.Write((byte)1);

            // Advertize out files
            if (Advertised == null)
            {
                writer.Write((byte)3); // Advertized No Files
            }
            else
            {
                writer.Write((byte)4); // Advertized Files
                writer.Write(Advertised.Id);
                writer.Write((ushort)Advertised.Blocks.Length);
            }

            // Discovery
            if (discovery)
            {
                writer.Write((byte)7); // Discovery
            }

            List<Request> requests = GetNextRequests();
            string callsign = DataBroker.GetValue<string>(0, "CallSign", "NOCALL");
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);
            byte currentStationId = (byte)stationId;
            string currentCallsign = callsign;
            byte[] currentShortId = null;
            foreach (Request request in requests)
            {
                if ((currentStationId != request.StationId) || (currentCallsign != request.Callsign))
                {
                    writer.Write((byte)2); // Station Id + Callsign
                    writer.Write((byte)request.StationId);
                    byte[] callsignBuf = Encoding.UTF8.GetBytes(request.Callsign);
                    writer.Write((byte)callsignBuf.Length);
                    writer.Write(callsignBuf);
                    currentStationId = request.StationId;
                    currentCallsign = request.Callsign;
                }

                if ((currentShortId == null) || (currentShortId.SequenceEqual(request.ShortId) == false))
                {
                    writer.Write((byte)5); // ShortId
                    writer.Write(request.ShortId);
                    currentShortId = request.ShortId;
                }

                writer.Write((byte)6); // Simple Request
                writer.Write((ushort)request.BlockNumber);
                writer.Write((byte)request.BlockCount);
            }

            // Send the packet to all locked radios
            SendTorrentPacket(ms.ToArray(), 162, "TorrentRequest", DateTime.Now.AddSeconds(30));
        }

        private void SendTorrentPacket(byte[] data, int pid, string tag = null, DateTime? deadline = null)
        {
            if (lockedTorrentRadios.Count == 0) return;
            
            string callsign = DataBroker.GetValue<string>(0, "CallSign", "NOCALL");
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);
            
            foreach (int radioDeviceId in lockedTorrentRadios)
            {
                var lockState = DataBroker.GetValue<RadioLockState>(radioDeviceId, "LockState", null);
                if (lockState == null || !lockState.IsLocked || lockState.Usage != "Torrent") continue;
                
                List<AX25Address> addresses = new List<AX25Address>();
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                
                AX25Packet packet = new AX25Packet(addresses, data, DateTime.Now);
                packet.pid = (byte)pid;
                packet.tag = tag;
                packet.deadline = deadline ?? DateTime.Now.AddSeconds(60);
                
                var txData = new TransmitDataFrameData
                {
                    Packet = packet,
                    ChannelId = lockState.ChannelId,
                    RegionId = lockState.RegionId
                };
                
                DataBroker.Dispatch(radioDeviceId, "TransmitDataFrame", txData, store: false);
            }
        }

        private struct Request
        {
            public string Callsign;
            public byte StationId;
            public byte[] ShortId;
            public int BlockNumber;
            public int BlockCount;
        }

        private List<TorrentFile> GetAllRequestTorrents()
        {
            List<TorrentFile> torrents = new List<TorrentFile>();
            foreach (TorrentFile file in Stations)
            {
                if (file.Mode == TorrentFile.TorrentModes.Request) { torrents.Add(file); }
            }
            foreach (TorrentFile file in Files)
            {
                if (file.Mode == TorrentFile.TorrentModes.Request) { torrents.Add(file); }
            }
            return torrents;
        }

        private List<Request> GetNextRequests()
        {
            List<Request> requests = new List<Request>();

            // Request other files
            List<TorrentFile> allRequestTorrents = GetAllRequestTorrents();
            foreach (TorrentFile file in allRequestTorrents)
            {
                if (file.Mode == TorrentFile.TorrentModes.Request)
                {
                    // Find the first block that is missing and how many more blocks are missing after it
                    int requestBlockIndex = -1;
                    int requestBlockCount = 0;
                    int totalRequestCount = 0;
                    for (int i = 0; i < file.Blocks.Length; i++)
                    {
                        if (file.Blocks[i] == null)
                        {
                            if (requestBlockIndex == -1) { requestBlockIndex = i; }
                            requestBlockCount++;
                            totalRequestCount++;

                            if ((requestBlockCount > 30) || (totalRequestCount > 30))
                            {
                                Request r = new Request(); // Simple Request
                                r.Callsign = file.Callsign;
                                r.StationId = (byte)file.StationId;
                                r.ShortId = file.ShortId;
                                r.BlockNumber = requestBlockIndex;
                                r.BlockCount = requestBlockCount;
                                requests.Add(r);
                                requestBlockIndex = -1;
                                requestBlockCount = 0;
                                if (totalRequestCount > 30) return requests;
                            }
                        }
                        else
                        {
                            if (requestBlockIndex != -1)
                            {
                                Request r = new Request(); // Simple Request
                                r.Callsign = file.Callsign;
                                r.StationId = (byte)file.StationId;
                                r.ShortId = file.ShortId;
                                r.BlockNumber = requestBlockIndex;
                                r.BlockCount = requestBlockCount;
                                requests.Add(r);
                                requestBlockIndex = -1;
                                requestBlockCount = 0;
                                if (totalRequestCount > 30) return requests;
                            }
                        }
                    }

                    if (requestBlockIndex != -1)
                    {
                        Request r = new Request(); // Simple Request
                        r.Callsign = file.Callsign;
                        r.StationId = (byte)file.StationId;
                        r.ShortId = file.ShortId;
                        r.BlockNumber = requestBlockIndex;
                        r.BlockCount = requestBlockCount;
                        requests.Add(r);
                    }
                }
            }

            return requests;
        }

        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {
            if (((p.pid != 162) && (p.pid != 163)) || (p.addresses.Count != 1)) return;

            if (p.pid == 162)
            {
                // This is a control packet
                MemoryStream ms = new MemoryStream(p.data);
                BinaryReader reader = new BinaryReader(ms);

                string callsign = p.addresses[0].address;
                int stationId = p.addresses[0].SSID;
                byte[] shortId = null;

                while (ms.Position < ms.Length)
                {
                    byte recordType = reader.ReadByte();
                    switch (recordType)
                    {
                        case 1: // Version
                            byte version = reader.ReadByte();
                            if (version != 1) return;
                            break;
                        case 2: // Station Id + Callsign
                            stationId = reader.ReadByte();
                            byte len = reader.ReadByte();
                            byte[] data = reader.ReadBytes(len);
                            callsign = Encoding.UTF8.GetString(data);
                            break;
                        case 3: // Advertized No Files
                            TorrentFile xFile = FindStationFile(callsign, stationId);
                            if (xFile != null)
                            {
                                // Remove the station file
                                Stations.Remove(xFile);
                                // TODO: Remove all files from this state
                            }
                            break;
                        case 4: // Advertized Files
                            byte[] sId = reader.ReadBytes(12);
                            int sblockCount = reader.ReadUInt16();
                            TorrentFile sFile = FindStationFile(callsign, stationId);
                            if ((sFile != null) && (sFile.Id.SequenceEqual(sId) == false))
                            {
                                // Remove the old station file
                                Stations.Remove(sFile);
                                sFile = null;
                            }
                            if (sFile == null)
                            {
                                // Create a new station file
                                sFile = new TorrentFile();
                                sFile.Id = sId;
                                sFile.Callsign = callsign;
                                sFile.StationId = stationId;
                                sFile.Blocks = new byte[sblockCount][];
                                sFile.Completed = false;
                                sFile.StationFile = true;
                                sFile.ReceivedLastBlock = true;
                                sFile.Mode = TorrentFile.TorrentModes.Request;
                                Stations.Add(sFile);
                                PublishStationsUpdate();
                            }
                            break;
                        case 5: // Short Id
                            shortId = reader.ReadBytes(6);
                            break;
                        case 6: // Simple Request (Short Id, Block Number, Block Count)
                            if (shortId == null) break;
                            int blockNumber = reader.ReadUInt16();
                            int blockCount = reader.ReadByte();
                            TorrentFile file = FindTorrentFileWithShortId(callsign, stationId, shortId);
                            if (file != null)
                            {
                                // Send the blocks
                                for (int i = blockNumber; i < Math.Min(blockNumber + blockCount, file.Blocks.Length); i++)
                                {
                                    byte[] block = file.Blocks[i];
                                    if (block != null)
                                    {
                                        // Create the block frame
                                        byte[] blockFrame = new byte[block.Length + 8];
                                        Array.Copy(shortId, 0, blockFrame, 0, 6);
                                        if (i == file.Blocks.Length - 1) { blockFrame[5] += 0x01; }
                                        blockFrame[6] = (byte)(i >> 8);
                                        blockFrame[7] = (byte)(i & 0xFF);
                                        Array.Copy(block, 0, blockFrame, 8, block.Length);

                                        // Send the packet
                                        string packetTag = file.Callsign + "-" + file.StationId + "-" + Utils.BytesToHex(shortId) + "-" + i;
                                        SendTorrentPacket(blockFrame, 163, packetTag, DateTime.Now.AddSeconds(60));
                                    }
                                }
                            }
                            break;
                        case 7: // Discovery
                            SendRequestFrame(false);
                            break;
                    }
                }
            }
            else if (p.pid == 163)
            {
                // This is a data block
                string callsign = p.addresses[0].address;
                int stationId = p.addresses[0].SSID;
                byte[] blockShortId = new byte[6];
                Array.Copy(p.data, 0, blockShortId, 0, 6);
                bool lastBlock = ((p.data[5] & 0x01) != 0);
                bool isStationFile = ((p.data[5] & 0x02) != 0);
                blockShortId[5] = (byte)(blockShortId[5] & 0xFE);
                int blockNumber = (p.data[6] << 8) + p.data[7];
                byte[] block = new byte[p.data.Length - 8];
                Array.Copy(p.data, 8, block, 0, block.Length);

                // If we just received data that is in the transmit queue, delete it, someone else sent it
                string packetTag = callsign + "-" + stationId + "-" + Utils.BytesToHex(blockShortId) + "-" + blockNumber;
                // Note: DeleteTransmitByTag would need to be implemented via DataBroker if needed

                if (isStationFile)
                {
                    // See if a station matches this block
                    TorrentFile sfile = null;
                    foreach (TorrentFile file in Stations)
                    {
                        if ((file.Callsign == callsign) && (file.StationId == stationId) && file.ShortId.SequenceEqual(blockShortId) && !file.Completed) { sfile = file; }

                        // If the file is completed, nothing more to do
                        if ((sfile != null) && sfile.Completed) return;

                        // TODO: This is not a known station, create a new TorrentFile for it.

                        if (sfile != null)
                        {
                            if ((file.Blocks == null) && (file.Blocks.Length <= blockNumber)) return;
                            if (file.Blocks[blockNumber] == null)
                            {
                                file.Blocks[blockNumber] = block;
                                file.ReceivedLastBlock = lastBlock;
                                int r = file.IsCompleted();
                                if (r == 1) { file.Completed = true; file.Mode = TorrentFile.TorrentModes.Sharing; UpdateStationAdvertised(file); }
                                if (r == 2) { file.Mode = TorrentFile.TorrentModes.Error; }
                                PublishStationUpdate(file);
                            }
                        }
                    }
                }
                else
                {
                    // See if we have a file that matches this block
                    TorrentFile mfile = null;
                    foreach (TorrentFile file in Files) { if ((file.Callsign == callsign) && (file.StationId == stationId) && file.ShortId.SequenceEqual(blockShortId)) { mfile = file; } }

                    // If the file is completed, nothing more to do
                    if ((mfile != null) && mfile.Completed) return;

                    // TODO: This is not a known file, create a new TorrentFile for it.

                    if (mfile != null)
                    {
                        if (mfile.Blocks == null) { mfile.Blocks = new byte[blockNumber + (lastBlock ? 1 : 40)][]; }
                        if (mfile.Blocks.Length <= blockNumber) { Array.Resize(ref mfile.Blocks, blockNumber + (lastBlock ? 1 : 40)); }
                        if (mfile.Blocks[blockNumber] == null)
                        {
                            mfile.Blocks[blockNumber] = block;
                            mfile.AppendToTorrentFile(blockNumber, false, false, false);
                            mfile.ReceivedLastBlock = lastBlock;
                            int r = mfile.IsCompleted();
                            if (r == 1) { mfile.Completed = true; mfile.Mode = TorrentFile.TorrentModes.Sharing; }
                            if (r == 2) { mfile.Mode = TorrentFile.TorrentModes.Error; }
                            PublishFileUpdate(mfile);
                        }
                    }
                }
            }
        }

        public void UpdateAllStations()
        {
            foreach (TorrentFile file in Stations) { UpdateStationAdvertised(file); }
        }

        private void UpdateStationAdvertised(TorrentFile torrentFile)
        {
            if (torrentFile == null) return;
            if (torrentFile.Completed == false) return;

            // Reassemble all the blocks
            int totalSize = 0;
            foreach (byte[] block in torrentFile.Blocks) { totalSize += block.Length; }
            byte[] bytes = new byte[totalSize];
            for (int i = 0, offset = 0; i < torrentFile.Blocks.Length; i++)
            {
                Array.Copy(torrentFile.Blocks[i], 0, bytes, offset, torrentFile.Blocks[i].Length);
                offset += torrentFile.Blocks[i].Length;
            }

            // Decompress the data if needed
            TorrentFile.TorrentCompression compression = (TorrentFile.TorrentCompression)bytes[0];
            if (compression == TorrentFile.TorrentCompression.Deflate)
            {
                bytes = Utils.DecompressDeflate(bytes, 1, bytes.Length - 1);
            }
            else if (compression == TorrentFile.TorrentCompression.Brotli)
            {
                bytes = Utils.DecompressBrotli(bytes, 1, bytes.Length - 1);
            }

            // Decode the records
            List<TorrentFile> updatedTorrentFiles = new List<TorrentFile>();
            MemoryStream ms = new MemoryStream(bytes);
            BinaryReader br = new BinaryReader(ms);
            string xcallsign = null, xfilename = null, xdescription = null;
            byte xstationId = 0;
            while (ms.Position < ms.Length)
            {
                byte recordType = br.ReadByte();
                switch (recordType)
                {
                    case 1: // Version
                        byte version = br.ReadByte();
                        if (version != 1) return;
                        break;
                    case 2: // Callsign
                        byte len = br.ReadByte();
                        byte[] data = br.ReadBytes(len);
                        xcallsign = Encoding.UTF8.GetString(data);
                        break;
                    case 3: // Station Id
                        xstationId = br.ReadByte();
                        break;
                    case 4: // Filename
                        len = br.ReadByte();
                        data = br.ReadBytes(len);
                        xfilename = Encoding.UTF8.GetString(data);
                        break;
                    case 5: // Description
                        len = br.ReadByte();
                        data = br.ReadBytes(len);
                        xdescription = Encoding.UTF8.GetString(data);
                        break;
                    case 6: // ID + Block Count
                        byte[] id = br.ReadBytes(12);
                        ushort blockCount = br.ReadUInt16();
                        if ((xcallsign != null) && (xfilename != null))
                        {
                            TorrentFile tFile = new TorrentFile();
                            tFile.Id = id;
                            tFile.Callsign = xcallsign;
                            tFile.StationId = xstationId;
                            tFile.FileName = xfilename;
                            tFile.Description = xdescription;
                            tFile.Blocks = new byte[blockCount][];
                            tFile.WriteTorrentFile();
                            updatedTorrentFiles.Add(tFile);
                            xfilename = null;
                            xdescription = null;
                        }
                        break;
                }
            }

            // If we don't have the file, add it. If we have it, check if it changed.
            bool changed = false;
            foreach (TorrentFile tFile in updatedTorrentFiles)
            {
                bool found = false;
                foreach (TorrentFile file in Files)
                {
                    if ((file.ShortId.SequenceEqual(tFile.ShortId)) && (file.Callsign == tFile.Callsign) && (tFile.StationId == file.StationId))
                    {
                        found = true;
                        bool idChanged = false, filenameChanged = false, descriptionChanged = false;
                        if (file.Id == null) { file.Id = tFile.Id; idChanged = true; changed = true; }
                        if (file.FileName != tFile.FileName) { file.FileName = tFile.FileName; filenameChanged = true; changed = true; }
                        if (file.Description != tFile.Description) { file.Description = tFile.Description; descriptionChanged = true; changed = true; }
                        if (filenameChanged || descriptionChanged) { tFile.AppendToTorrentFile(-1, idChanged, filenameChanged, descriptionChanged); }
                        break;
                    }
                }
                if (!found) { Files.Add(tFile); changed = true; }
            }

            // If we have files that are not in the updated list, remove them.
            // TODO
            
            // Publish updates if anything changed
            if (changed)
            {
                PublishFilesUpdate();
            }
        }

        private void UpdateAdvertised()
        {
            MemoryStream ms = new MemoryStream();
            BinaryWriter bw = new BinaryWriter(ms);
            byte[] buf;

            string callsign = DataBroker.GetValue<string>(0, "CallSign", "NOCALL");
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);

            buf = Encoding.UTF8.GetBytes(callsign);
            bw.Write((byte)1); // Version
            bw.Write((byte)1);

            buf = Encoding.UTF8.GetBytes(callsign);
            bw.Write((byte)2); // Callsign
            bw.Write((byte)buf.Length);
            bw.Write(buf);

            if (stationId != 0)
            {
                bw.Write((byte)3); // Station Id
                bw.Write((byte)stationId);
            }

            int filecount = 0;
            foreach (TorrentFile file in Files)
            {
                if ((file.Callsign == callsign) && (file.StationId == stationId) && (file.Id.Length == 12))
                {
                    buf = Encoding.UTF8.GetBytes(file.FileName);
                    bw.Write((byte)4); // Filename
                    bw.Write((byte)buf.Length);
                    bw.Write(buf);

                    if (!string.IsNullOrEmpty(file.Description))
                    {
                        buf = Encoding.UTF8.GetBytes(file.Description);
                        bw.Write((byte)5); // Description
                        bw.Write((byte)buf.Length);
                        bw.Write(buf);
                    }

                    bw.Write((byte)6); // ID + Block Count
                    bw.Write(file.Id);
                    bw.Write((ushort)file.Blocks.Length);
                    filecount++;
                }
            }

            if (filecount == 0) { Advertised = null; return; }

            byte[] data0 = ms.ToArray();
            byte[] data1 = Utils.CompressBrotli(data0);
            byte[] data2 = Utils.CompressDeflate(data0);
            byte[] dataSelected = null;

            TorrentFile torrentFile = new TorrentFile();
            torrentFile.Completed = true;
            torrentFile.StationFile = true;
            torrentFile.Callsign = callsign;
            torrentFile.StationId = stationId;
            torrentFile.Mode = TorrentFile.TorrentModes.Sharing;
            torrentFile.Size = data0.Length;

            if ((data2.Length < data1.Length) && (data2.Length < data0.Length))
            {
                torrentFile.Compression = TorrentFile.TorrentCompression.Deflate;
                torrentFile.CompressedSize = data2.Length + 1;
                dataSelected = data2;
            }
            else if ((data1.Length < data2.Length) && (data1.Length < data0.Length))
            {
                torrentFile.Compression = TorrentFile.TorrentCompression.Brotli;
                torrentFile.CompressedSize = data1.Length + 1;
                dataSelected = data1;
            }
            else
            {
                torrentFile.Compression = TorrentFile.TorrentCompression.None;
                torrentFile.CompressedSize = data0.Length + 1;
                dataSelected = data0;
            }

            // Add compression type byte
            byte[] dataSelected2 = new byte[dataSelected.Length + 1];
            dataSelected2[0] = (byte)torrentFile.Compression;
            Array.Copy(dataSelected, 0, dataSelected2, 1, dataSelected.Length);
            dataSelected = dataSelected2;

            // Hash the file
            torrentFile.Id = Utils.ComputeShortSha256Hash(dataSelected);

            // Create blocks
            int blockCount = dataSelected.Length / DefaultBlockSize;
            if ((dataSelected.Length % DefaultBlockSize) != 0) { blockCount++; }
            torrentFile.Blocks = new byte[blockCount][];
            for (int i = 0; i < blockCount; i++)
            {
                int thisBlockSize = Math.Min(DefaultBlockSize, dataSelected.Length - (i * DefaultBlockSize));
                torrentFile.Blocks[i] = new byte[thisBlockSize];
                Array.Copy(dataSelected, i * DefaultBlockSize, torrentFile.Blocks[i], 0, thisBlockSize);
            }

            // Done
            Advertised = torrentFile;
        }
    }

    public class TorrentFile
    {
        public enum TorrentModes : int
        {
            Pause = 0,
            Request = 1,
            Sharing = 2,
            Error = 3
        }

        public enum TorrentCompression : int
        {
            Unknown = -1,
            None = 0,
            Deflate = 1,
            Brotli = 2
        }

        public string Callsign; // Source Callsign
        public int StationId; // Source Station ID
        public byte[] Id; // First 12 byte of SHA256 hash of compressed file
        private byte[] _ShortId; // First 6 byte of SHA256 hash of compressed file, last bit is cleared
        public bool StationFile = false; // True if this contains a list of files for a station
        public byte[] ShortId { get { if (_ShortId == null) { _ShortId = new byte[6]; Array.Copy(Id, 0, _ShortId, 0, 6); } _ShortId[5] = (byte)((_ShortId[5] & 0xFC) + (StationFile ? 2 : 0)); return _ShortId; } }
        public string FileName; // File name
        public string Description; // File description, max 200 bytes
        public int Size; // File size
        public int CompressedSize; // Compressed file size
        public TorrentCompression Compression = TorrentCompression.Unknown; // Compression type
        public byte[][] Blocks; // Blocks
        public TorrentModes Mode = TorrentModes.Pause; // Sharing mode
        public bool Completed = false; // File complete
        public bool ReceivedLastBlock = false;
        public System.Windows.Forms.ListViewItem ListViewItem;

        public int TotalBlocks { get { if (Blocks != null) { return Blocks.Length; } else { return 0; } } }
        public int ReceivedBlocks
        {
            get
            {
                if (Blocks == null) return 0;
                int count = 0;
                foreach (byte[] block in Blocks) { if (block != null) count++; }
                return count;
            }
        }

        /// <summary>
        /// Returns 0 if not completed, 1 if completed, 2 if there is a hash error
        /// </summary>
        /// <returns></returns>
        public int IsCompleted()
        {
            if (Blocks == null) return 0;

            // Compute the total size of all blocks
            int totalSize = 0;
            for (int i = 0; i < Blocks.Length; i++)
            {
                if (Blocks[i] == null) return 0;
                totalSize += Blocks[i].Length;
            }
            CompressedSize = totalSize;

            // Hash all the blocks
            byte[] hash;
            using (SHA256 sha256 = SHA256.Create())
            {
                // Initialize the hash computation
                sha256.Initialize();

                // Iterate through the array of byte arrays and process each one
                for (int i = 0; i < Blocks.Length; i++)
                {
                    byte[] data = Blocks[i];

                    if (i < Blocks.Length - 1)
                    {
                        // For all but the last array, use TransformBlock
                        sha256.TransformBlock(data, 0, data.Length, data, 0);
                    }
                    else
                    {
                        // For the last array, use TransformFinalBlock to finalize the hash
                        sha256.TransformFinalBlock(data, 0, data.Length);
                    }
                }

                // Get the resulting hash
                hash = new byte[12];
                Array.Copy(sha256.Hash, 0, hash, 0, 12);
            }

            // Compare the hash
            if (Id.SequenceEqual(hash)) { return 1; }
            return 2;
        }

        public byte[] GetFileData()
        {
            // Compute the total size of all blocks
            int totalSize = 0;
            foreach (byte[] block in Blocks) { if (block == null) return null; totalSize += block.Length; }

            // Merge all the blocks
            byte[] data = new byte[totalSize];
            int offset = 0;
            foreach (byte[] block in Blocks)
            {
                Array.Copy(block, 0, data, offset, block.Length);
                offset += block.Length;
            }

            // Decompress the data if needed
            Compression = (TorrentCompression)data[0];
            if (Compression == TorrentCompression.Deflate)
            {
                // Decompress using Deflate
                data = Utils.DecompressDeflate(data, 1, data.Length - 1);
            }
            else if (Compression == TorrentCompression.Brotli)
            {
                // Decompress using Brotli
                data = Utils.DecompressBrotli(data, 1, data.Length - 1);
            }

            // Get the file name
            int fileNameSize = data[0];
            FileName = Encoding.UTF8.GetString(data, 1, fileNameSize);

            // Get the file data
            byte[] fileData = new byte[data.Length - fileNameSize - 1];
            fileData = new byte[data.Length - fileNameSize - 1];
            Array.Copy(data, fileNameSize + 1, fileData, 0, fileData.Length);
            Size = fileData.Length;

            return fileData;
        }

        public static List<TorrentFile> ReadTorrentFiles()
        {
            List<TorrentFile> torrents = new List<TorrentFile>();
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string torrentPath = Path.Combine(appDataPath, "HTCommander", "Torrents");
            if (Directory.Exists(torrentPath))
            {
                string[] files = Directory.GetFiles(torrentPath, "*.httorrent");
                foreach (string file in files)
                {
                    BinaryDataFile binaryDataFile = new BinaryDataFile(file);
                    binaryDataFile.Open();
                    TorrentFile torrentFile = new TorrentFile();
                    object UserData;
                    int UserType;
                    int blockIndex = 0;

                    while ((UserType = binaryDataFile.ReadNextRecord(out UserData)) > 0)
                    {
                        if (UserType == 3) { torrentFile.Id = (byte[])UserData; }
                        else if (UserType == 4) { torrentFile.Callsign = (string)UserData; }
                        else if (UserType == 5) { torrentFile.StationId = (int)UserData; }
                        else if (UserType == 6) { torrentFile.FileName = (string)UserData; }
                        else if (UserType == 7) { torrentFile.Description = (string)UserData; }
                        else if (UserType == 8) { torrentFile.Size = (int)UserData; }
                        else if (UserType == 9) { torrentFile.CompressedSize = (int)UserData; }
                        else if (UserType == 10) { torrentFile.Compression = (TorrentCompression)(int)UserData; }
                        else if (UserType == 11) { torrentFile.Mode = (TorrentModes)(int)UserData; }
                        else if (UserType == 12) { torrentFile.Completed = ((int)UserData != 0); }
                        else if (UserType == 13) { torrentFile.Blocks = new byte[(int)UserData][]; }
                        else if (UserType == 14) { blockIndex = (int)UserData; }
                        else if (UserType == 15) { torrentFile.Blocks[(int)blockIndex] = (byte[])UserData; }
                    }

                    int check = torrentFile.IsCompleted();
                    if (check == 0) { torrentFile.Completed = false; }
                    if (check == 1) { torrentFile.Completed = true; }
                    if (check == 2) { torrentFile.Mode = TorrentModes.Error; }
                    if ((check == 0) && (torrentFile.Mode == TorrentModes.Sharing)) { torrentFile.Mode = TorrentModes.Pause; }
                    if ((check == 1) && (torrentFile.Mode == TorrentModes.Request)) { torrentFile.Mode = TorrentModes.Pause; }

                    torrents.Add(torrentFile);
                    binaryDataFile.Close();
                }
            }
            return torrents;
        }

        public void DeleteTorrentFile()
        {
            // Get the path to the current user's Roaming AppData folder.
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string torrentPath = Path.Combine(appDataPath, "HTCommander", "Torrents");
            // Create the directory if it doesn't exist.
            Directory.CreateDirectory(torrentPath);
            // Create the file path using the Callsign, StationId, and Id.
            string filename = Path.Combine(torrentPath, Callsign + "-" + StationId.ToString() + "-" + Utils.BytesToHex(Id) + ".httorrent");
            if (File.Exists(filename)) { File.Delete(filename); }
        }

        public void AppendToTorrentFile(int blockIndex, bool idChanged, bool updateFilename, bool updateDesc)
        {
            // Get the path to the current user's Roaming AppData folder.
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string torrentPath = Path.Combine(appDataPath, "HTCommander", "Torrents");

            // Create the directory if it doesn't exist.
            Directory.CreateDirectory(torrentPath);

            // Create the file path using the Callsign, StationId, and Id.
            string filename = Path.Combine(torrentPath, Callsign + "-" + StationId.ToString() + "-" + Utils.BytesToHex(Id) + ".httorrent");
            if (File.Exists(filename) == false) { WriteTorrentFile(); return; }

            // Append the record
            BinaryDataFile binaryDataFile = new BinaryDataFile(filename);
            binaryDataFile.Open();
            binaryDataFile.SeekToEnd();
            if (idChanged) { binaryDataFile.AppendRecord(3, Id); }
            if (updateFilename) { binaryDataFile.AppendRecord(6, FileName); }
            if (updateDesc) { binaryDataFile.AppendRecord(6, Description); }
            if (blockIndex >= 0) { binaryDataFile.AppendRecord(14, blockIndex); binaryDataFile.AppendRecord(15, Blocks[blockIndex]); }
            binaryDataFile.Close();
        }

        public void WriteTorrentFile()
        {
            // Get the path to the current user's Roaming AppData folder.
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string torrentPath = Path.Combine(appDataPath, "HTCommander", "Torrents");

            // Create the directory if it doesn't exist.
            Directory.CreateDirectory(torrentPath);

            // Create the file path using the Callsign, StationId, and Id.
            string filename = Path.Combine(torrentPath, Callsign + "-" + StationId.ToString() + "-" + Utils.BytesToHex(Id) + ".httorrent");
            BinaryDataFile binaryDataFile = new BinaryDataFile(filename);
            binaryDataFile.Open();
            binaryDataFile.AppendRecord(1, "HTCommanderTorrent"); // Magic Start
            binaryDataFile.AppendRecord(2, 1); // Version
            binaryDataFile.AppendRecord(3, Id);
            binaryDataFile.AppendRecord(4, Callsign);
            binaryDataFile.AppendRecord(5, StationId);
            binaryDataFile.AppendRecord(6, FileName);
            binaryDataFile.AppendRecord(7, Description);
            binaryDataFile.AppendRecord(8, Size);
            binaryDataFile.AppendRecord(9, CompressedSize);
            binaryDataFile.AppendRecord(10, (int)Compression);
            binaryDataFile.AppendRecord(11, (int)Mode);
            binaryDataFile.AppendRecord(12, (int)(Completed ? 1 : 0));
            if (Blocks != null)
            {
                binaryDataFile.AppendRecord(13, Blocks.Length);
                for (int i = 0; i < Blocks.Length; i++)
                {
                    if (Blocks[i] != null)
                    {
                        binaryDataFile.AppendRecord(14, i);
                        binaryDataFile.AppendRecord(15, Blocks[i]);
                    }
                }
            }
            binaryDataFile.Close();
        }
    }
}
