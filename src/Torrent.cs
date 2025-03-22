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
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

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
    }
}
