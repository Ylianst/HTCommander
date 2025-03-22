using System;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AddTorrentFileForm: Form
    {
        public MainForm parent;
        public TorrentFile torrentFile = null;

        public AddTorrentFileForm(MainForm parent)
        {
            this.parent = parent;
            InitializeComponent();
            UpdateInfo();
            compressionLabel.Text = string.Empty;
        }

        private void fileSelectButton_Click(object sender, EventArgs e)
        {
            if (openFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                Import(openFileDialog.FileName);
            }
        }

        public bool Import(string filename)
        {
            FileInfo fileInfo = new FileInfo(filename);
            if (fileInfo.Length > 10000000)
            {
                MessageBox.Show(this, "File is too large, maximum size is 10MB", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                fileNameTextBox.Text = compressionLabel.Text = string.Empty;
                torrentFile = null;
                return false;
            }
            if (fileInfo.Name.Length > 100)
            {
                MessageBox.Show(this, "File name is too long, maximum length is 100 characters", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                fileNameTextBox.Text = compressionLabel.Text = string.Empty;
                torrentFile = null;
                return false;
            }

            fileNameTextBox.Text = fileInfo.Name;
            compressionLabel.Text = "Compressing...";
            byte[] data = File.ReadAllBytes(filename);
            byte[] name = UTF8Encoding.UTF8.GetBytes(fileInfo.Name);
            byte[] data0 = new byte[data.Length + name.Length + 1];
            data0[0] = (byte)name.Length;
            Array.Copy(name, 0, data0, 1, name.Length);
            Array.Copy(data, 0, data0, name.Length + 1, data.Length);
            byte[] data1 = Utils.CompressBrotli(data0);
            byte[] data2 = Utils.CompressDeflate(data0);
            byte[] dataSelected = null;

            torrentFile = new TorrentFile();
            torrentFile.Completed = true;
            torrentFile.Callsign = parent.callsign;
            torrentFile.StationId = parent.stationId;
            torrentFile.FileName = fileInfo.Name;
            torrentFile.Mode = TorrentFile.TorrentModes.Sharing; // Share
            torrentFile.Size = (int)fileInfo.Length;

            if ((data2.Length < data1.Length) && (data2.Length < data0.Length))
            {
                compressionLabel.Text = "Deflate, " + fileInfo.Length + " -> " + data2.Length + " bytes";
                torrentFile.Compression = TorrentFile.TorrentCompression.Deflate;
                torrentFile.CompressedSize = data2.Length + 1;
                dataSelected = data2;
            }
            else if ((data1.Length < data2.Length) && (data1.Length < data0.Length))
            {
                compressionLabel.Text = "Brotli, " + fileInfo.Length + " -> " + data1.Length + " bytes";
                torrentFile.Compression = TorrentFile.TorrentCompression.Brotli;
                torrentFile.CompressedSize = data1.Length + 1;
                dataSelected = data1;
            }
            else
            {
                compressionLabel.Text = "None, " + data0.Length + " bytes";
                torrentFile.Compression = TorrentFile.TorrentCompression.None;
                torrentFile.CompressedSize = data0.Length + 1;
                dataSelected = data0;
            }

            if (torrentFile.CompressedSize > 1000000)
            {
                MessageBox.Show(this, "File is too large, maximum size is 1MB after compression", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                fileNameTextBox.Text = compressionLabel.Text = string.Empty;
                torrentFile = null;
                return false;
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

            descriptionTextBox.Focus();
            return true;
        }

        private void UpdateInfo()
        {
            okButton.Enabled = (fileNameTextBox.Text.Length > 0) && (descriptionTextBox.Text.Length > 0);
        }

        private void descriptionTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void AddTorrentFileForm_Load(object sender, EventArgs e)
        {
            descriptionTextBox.Focus();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            torrentFile.Description = descriptionTextBox.Text;
            torrentFile.Description = torrentFile.Description.Substring(0, Math.Min(torrentFile.Description.Length, 200));
            DialogResult = DialogResult.OK;
        }
    }
}
