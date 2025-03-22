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
using System.Windows.Forms;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Linq;

namespace HTCommander
{
    public class Torrent
    {
        private MainForm parent;
        private bool Active = false;
        public List<TorrentFile> Files = new List<TorrentFile>();
        public TorrentFile Advertised = null;
        public Dictionary<string, TorrentFile> Stations = new Dictionary<string, TorrentFile>();

        public Torrent(MainForm parent)
        {
            this.parent = parent;
        }

        public bool Add(TorrentFile file)
        {
            if (Files.Contains(file)) return false;
            Files.Add(file);
            UpdateAdvertised();
            return true;
        }

        public bool Remove(TorrentFile file)
        {
            if (!Files.Contains(file)) return false;
            Files.Remove(file);
            UpdateAdvertised();
            return true;
        }

        public void Activate(bool active)
        {
            if (Active == active) return;
            Active = active;
        }

        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {

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
                    if ((file.Id == tFile.Id) && (file.Callsign == tFile.Callsign) && (tFile.StationId == file.StationId)) {
                        found = true;
                        if (file.FileName != tFile.FileName) { file.FileName = tFile.FileName; changed = true; }
                        if (file.Description != tFile.Description) { file.Description = tFile.Description; changed = true; }
                        break;
                    }
                }
                if (!found) { Files.Add(tFile); }
                changed = true;
            }

            // If we have files that are not in the updated list, remove them.
            // TODO

            if (changed) { parent.updateTorrentList(); }
        }

        private void UpdateAdvertised()
        {
            MemoryStream ms = new MemoryStream();
            BinaryWriter bw = new BinaryWriter(ms);
            byte[] buf;

            buf = Encoding.UTF8.GetBytes(parent.callsign);
            bw.Write((byte)1); // Version
            bw.Write((byte)1);

            buf = Encoding.UTF8.GetBytes(parent.callsign);
            bw.Write((byte)2); // Callsign
            bw.Write((byte)buf.Length);
            bw.Write(buf);

            if (parent.stationId != 0)
            {
                bw.Write((byte)3); // Station Id
                bw.Write((byte)parent.stationId);
            }

            int filecount = 0;
            foreach (TorrentFile file in Files)
            {
                if ((file.Callsign == parent.callsign) && (file.StationId == parent.stationId) && (file.Id.Length == 12))
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
            torrentFile.Callsign = parent.callsign;
            torrentFile.StationId = parent.stationId;
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
            int blockSize = 100;
            int blockCount = dataSelected.Length / blockSize;
            if ((dataSelected.Length % blockSize) != 0) { blockCount++; }
            torrentFile.Blocks = new byte[blockCount][];
            for (int i = 0; i < blockCount; i++)
            {
                int thisBlockSize = Math.Min(blockSize, dataSelected.Length - (i * blockSize));
                torrentFile.Blocks[i] = new byte[thisBlockSize];
                Array.Copy(dataSelected, i * blockSize, torrentFile.Blocks[i], 0, thisBlockSize);
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
        public string FileName; // File name
        public string Description; // File description, max 200 bytes
        public int Size; // File size
        public int CompressedSize; // Compressed file size
        public TorrentCompression Compression = TorrentCompression.Unknown; // Compression type
        public byte[][] Blocks; // Blocks
        public TorrentModes Mode = TorrentModes.Pause; // Sharing mode
        public bool Completed = false; // File complete
        public bool ReceivedLastBlock = false;
        public ListViewItem ListViewItem;

        public int TotalBlocks { get { if (Blocks != null) { return Blocks.Length; } else { return 0; } } }
        public int ReceivedBlocks {
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
            for (int i = 0; i < Blocks.Length; i++) {
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
