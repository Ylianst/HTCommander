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

namespace HTCommander
{
    public class Torrent
    {
        private MainForm parent;
        public List<TorrentFile> Files = new List<TorrentFile>();

        public Torrent(MainForm parent)
        {
            this.parent = parent;
        }

        public bool Add(TorrentFile file)
        {
            if (Files.Contains(file)) return false;
            Files.Add(file);
            return true;
        }

        public bool Remove(TorrentFile file)
        {
            if (!Files.Contains(file)) return false;
            Files.Remove(file);
            return true;
        }

        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {

        }
    }

    public class TorrentFile
    {
        public enum TorrentModes : int
        {
            Pause = 0,
            Request = 1,
            Sharing = 2
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
