/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// A data handler that stores packets to a file and maintains a running list of the last 2000 packets in memory.
    /// Listens for UniqueDataFrame events on device 1 and saves them to "packets.ptcap".
    /// Other modules can request the packet list via the Data Broker.
    /// </summary>
    public class PacketStore : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly object _lock = new object();
        private bool _disposed = false;

        /// <summary>
        /// Maximum number of packets to keep in memory.
        /// </summary>
        private const int MaxPacketsInMemory = 2000;

        /// <summary>
        /// The filename for storing packets.
        /// </summary>
        private const string PacketFileName = "packets.ptcap";

        /// <summary>
        /// The list of recent packets, kept in chronological order (newest at the end).
        /// </summary>
        private readonly List<TncDataFragment> _packets = new List<TncDataFragment>();

        /// <summary>
        /// The path to the app data folder.
        /// </summary>
        private readonly string _appDataPath;

        /// <summary>
        /// File stream for appending packets.
        /// </summary>
        private FileStream _packetFile;

        /// <summary>
        /// Creates a new PacketStore that listens for UniqueDataFrame events and stores packets.
        /// </summary>
        public PacketStore()
        {
            _appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander");

            // Ensure the directory exists
            if (!Directory.Exists(_appDataPath))
            {
                Directory.CreateDirectory(_appDataPath);
            }

            // Load existing packets from file
            LoadPackets();

            // Open the file for appending new packets
            OpenPacketFile();

            _broker = new DataBrokerClient();

            // Subscribe to UniqueDataFrame events on device 1
            _broker.Subscribe(1, "UniqueDataFrame", OnUniqueDataFrame);

            // Subscribe to requests for the packet list on device 1
            _broker.Subscribe(1, "RequestPacketList", OnRequestPacketList);

            // Notify subscribers that PacketStore is ready and packets are loaded (stored so late subscribers can check)
            _broker.Dispatch(1, "PacketStoreReady", true, store: true);
        }

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        /// <summary>
        /// Gets the number of packets currently stored in memory.
        /// </summary>
        public int PacketCount
        {
            get
            {
                lock (_lock)
                {
                    return _packets.Count;
                }
            }
        }

        /// <summary>
        /// Gets a copy of the current packet list.
        /// </summary>
        /// <returns>A list of TncDataFragment packets.</returns>
        public List<TncDataFragment> GetPackets()
        {
            lock (_lock)
            {
                return new List<TncDataFragment>(_packets);
            }
        }

        /// <summary>
        /// Opens the packet file for appending.
        /// </summary>
        private void OpenPacketFile()
        {
            try
            {
                _packetFile = File.Open(Path.Combine(_appDataPath, PacketFileName), FileMode.Append, FileAccess.Write, FileShare.Read);
            }
            catch (Exception)
            {
                _packetFile = null;
            }
        }

        /// <summary>
        /// Loads the last 2000 packets from the file.
        /// </summary>
        private void LoadPackets()
        {
            string filePath = Path.Combine(_appDataPath, PacketFileName);
            string[] lines = null;

            try
            {
                if (File.Exists(filePath))
                {
                    lines = File.ReadAllLines(filePath);
                }
            }
            catch (Exception)
            {
                return;
            }

            if (lines == null || lines.Length == 0) return;

            // If the packet file is big, load only the last MaxPacketsInMemory packets
            int startIndex = 0;
            if (lines.Length > MaxPacketsInMemory)
            {
                startIndex = lines.Length - MaxPacketsInMemory;
            }

            lock (_lock)
            {
                for (int i = startIndex; i < lines.Length; i++)
                {
                    try
                    {
                        TncDataFragment fragment = ParsePacketLine(lines[i]);
                        if (fragment != null)
                        {
                            _packets.Add(fragment);
                        }
                    }
                    catch (Exception)
                    {
                        // Skip malformed lines
                    }
                }
            }
        }

        /// <summary>
        /// Parses a packet line from the file into a TncDataFragment.
        /// </summary>
        /// <param name="line">The line to parse.</param>
        /// <returns>A TncDataFragment, or null if the line is invalid.</returns>
        public static TncDataFragment ParsePacketLine(string line)
        {
            string[] s = line.Split(',');
            if (s.Length < 3) return null;

            DateTime t = new DateTime(long.Parse(s[0]));
            bool incoming = (s[1] == "1");

            // Check for supported fragment types
            if (s[2] != "TncFrag" && s[2] != "TncFrag2" && s[2] != "TncFrag3" && s[2] != "TncFrag4") return null;

            int cid = int.Parse(s[3]);
            int rid = -1;
            string cn = cid.ToString();
            byte[] f;
            TncDataFragment.FragmentEncodingType encoding = TncDataFragment.FragmentEncodingType.Unknown;
            TncDataFragment.FragmentFrameType frame_type = TncDataFragment.FragmentFrameType.Unknown;
            int corrections = -1;
            string radioMac = null;

            if (s[2] == "TncFrag")
            {
                if (s.Length < 5) return null;
                f = Utils.HexStringToByteArray(s[4]);
            }
            else if (s[2] == "TncFrag2")
            {
                if (s.Length < 7) return null;
                rid = 0;
                int.TryParse(s[4], out rid);
                cn = s[5];
                f = Utils.HexStringToByteArray(s[6]);
            }
            else if (s[2] == "TncFrag3")
            {
                if (s.Length < 10) return null;
                rid = 0;
                int.TryParse(s[4], out rid);
                cn = s[5];
                f = Utils.HexStringToByteArray(s[6]);
                encoding = (TncDataFragment.FragmentEncodingType)int.Parse(s[7]);
                frame_type = (TncDataFragment.FragmentFrameType)int.Parse(s[8]);
                corrections = int.Parse(s[9]);
            }
            else if (s[2] == "TncFrag4")
            {
                if (s.Length < 10) return null;
                rid = 0;
                int.TryParse(s[4], out rid);
                cn = s[5];
                f = Utils.HexStringToByteArray(s[6]);
                encoding = (TncDataFragment.FragmentEncodingType)int.Parse(s[7]);
                frame_type = (TncDataFragment.FragmentFrameType)int.Parse(s[8]);
                corrections = int.Parse(s[9]);
                if (s.Length > 10 && !string.IsNullOrEmpty(s[10])) { radioMac = s[10]; }
            }
            else
            {
                return null;
            }

            TncDataFragment fragment = new TncDataFragment(true, 0, f, cid, rid);
            fragment.time = t;
            fragment.channel_name = cn;
            fragment.incoming = incoming;
            fragment.encoding = encoding;
            fragment.frame_type = frame_type;
            fragment.corrections = corrections;
            fragment.RadioMac = radioMac;

            return fragment;
        }

        /// <summary>
        /// Handles incoming UniqueDataFrame events and stores the packet.
        /// </summary>
        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is TncDataFragment frame)) return;

            // Set the timestamp if not already set
            if (frame.time == default(DateTime))
            {
                frame.time = DateTime.Now;
            }

            // Write to file
            WritePacketToFile(frame);

            // Add to memory list
            lock (_lock)
            {
                _packets.Add(frame);

                // Trim to MaxPacketsInMemory
                while (_packets.Count > MaxPacketsInMemory)
                {
                    _packets.RemoveAt(0);
                }
            }

            // Dispatch an event to notify that a new packet was stored
            _broker.Dispatch(1, "PacketStored", frame, store: false);
        }

        /// <summary>
        /// Handles requests for the packet list.
        /// </summary>
        private void OnRequestPacketList(int deviceId, string name, object data)
        {
            if (_disposed) return;

            // Dispatch the current packet list
            List<TncDataFragment> packets = GetPackets();
            _broker.Dispatch(1, "PacketList", packets, store: false);
        }

        /// <summary>
        /// Writes a packet to the file.
        /// </summary>
        /// <param name="frame">The packet to write.</param>
        private void WritePacketToFile(TncDataFragment frame)
        {
            if (_packetFile == null) return;

            try
            {
                string line = frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString() + "\r\n";
                byte[] bytes = Encoding.UTF8.GetBytes(line);
                _packetFile.Write(bytes, 0, bytes.Length);
                _packetFile.Flush();
            }
            catch (Exception)
            {
                // Ignore write errors
            }
        }

        /// <summary>
        /// Clears all packets from memory. Does not affect the file.
        /// </summary>
        public void ClearMemory()
        {
            lock (_lock)
            {
                _packets.Clear();
            }
        }

        /// <summary>
        /// Disposes the handler, unsubscribing from the broker and closing the file.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the handler.
        /// </summary>
        /// <param name="disposing">True if called from Dispose(), false if called from finalizer.</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    // Dispose the broker client (unsubscribes)
                    _broker?.Dispose();

                    // Close the packet file
                    if (_packetFile != null)
                    {
                        try
                        {
                            _packetFile.Close();
                            _packetFile.Dispose();
                        }
                        catch (Exception) { }
                        _packetFile = null;
                    }

                    // Clear the memory
                    lock (_lock)
                    {
                        _packets.Clear();
                    }
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~PacketStore()
        {
            Dispose(false);
        }
    }
}
