using System;
using System.IO;
using System.Text;

namespace HTCommander
{
    public class BinaryDataFile
    {
        private readonly string _filePath;
        private FileStream _fileStream;
        private BinaryWriter _writer;
        private BinaryReader _reader;
        private bool _isOpened = false;

        // Constants for data types
        private const int DataTypeInt = 1;
        private const int DataTypeString = 2;
        private const int DataTypeByteArray = 3;

        public BinaryDataFile(string filePath)
        {
            _filePath = filePath;
        }

        /// <summary>
        /// Opens the binary file for reading and writing.
        /// </summary>
        public void Open()
        {
            if (!_isOpened)
            {
                _fileStream = new FileStream(_filePath, FileMode.OpenOrCreate, FileAccess.ReadWrite);
                _writer = new BinaryWriter(_fileStream);
                _reader = new BinaryReader(_fileStream);
                _isOpened = true;
            }
        }

        /// <summary>
        /// Closes the binary file and releases associated resources.
        /// </summary>
        public void Close()
        {
            if (_isOpened)
            {
                _writer?.Dispose();
                _reader?.Dispose();
                _fileStream?.Dispose();
                _writer = null;
                _reader = null;
                _fileStream = null;
                _isOpened = false;
            }
        }

        /// <summary>
        /// Sets the file stream's seek pointer to the beginning of the file.
        /// </summary>
        public void SeekToBegin()
        {
            if (_isOpened && _fileStream != null)
            {
                _fileStream.Seek(0, SeekOrigin.Begin);
            }
        }

        /// <summary>
        /// Sets the file stream's seek pointer to the end of the file.
        /// </summary>
        public void SeekToEnd()
        {
            if (_isOpened && _fileStream != null)
            {
                _fileStream.Seek(0, SeekOrigin.End);
            }
        }

        /// <summary>
        /// Appends a new record to the binary file. The file must be opened before calling this method.
        /// </summary>
        /// <param name="userType">The user-defined type of the data.</param>
        /// <param name="data">The data to append (can be an int, string, or byte array).</param>
        /// <exception cref="InvalidOperationException">Thrown if the file is not open.</exception>
        public void AppendRecord(int userType, object data)
        {
            if (data == null) return;
            if (!_isOpened || _writer == null)
            {
                throw new InvalidOperationException("The file must be opened before appending a record.");
            }

            int dataType;
            int dataLength = 0;
            byte[] dataBytes = null;

            if (data is int intValue)
            {
                dataType = DataTypeInt;
                dataLength = sizeof(int);
                dataBytes = BitConverter.GetBytes(intValue);
            }
            else if (data is string stringValue)
            {
                dataType = DataTypeString;
                dataBytes = Encoding.UTF8.GetBytes(stringValue);
                dataLength = dataBytes.Length;
            }
            else if (data is byte[] byteArrayValue)
            {
                dataType = DataTypeByteArray;
                dataBytes = byteArrayValue;
                dataLength = byteArrayValue.Length;
            }
            else
            {
                throw new ArgumentException("Unsupported data type. Must be int, string, or byte array.");
            }

            // Calculate total record size
            int recordSize = sizeof(int) + sizeof(int) + sizeof(int) + dataLength;

            // Write the record
            _writer.Write(recordSize);
            _writer.Write(userType);
            _writer.Write(dataType);
            _writer.Write(dataBytes);
        }

        /// <summary>
        /// Reads the next record from the currently opened file and advances the stream pointer.
        /// </summary>
        /// <returns>A tuple containing the user type and the data, or null if the end of the file is reached.</returns>
        /// <exception cref="InvalidOperationException">Thrown if the file is not open.</exception>
        public int ReadNextRecord(out object data)
        {
            data = null;
            if (!_isOpened || _reader == null || _fileStream == null)
            {
                throw new InvalidOperationException("The file must be opened before reading a record.");
            }

            if (_fileStream.Position >= _fileStream.Length)
            {
                return 0; // End of file reached
            }

            int recordSize = _reader.ReadInt32();
            int userType = _reader.ReadInt32();
            int dataType = _reader.ReadInt32();

            switch (dataType)
            {
                case DataTypeInt:
                    data = _reader.ReadInt32();
                    break;
                case DataTypeString:
                    int stringLength = recordSize - (sizeof(int) * 3);
                    byte[] stringBytes = _reader.ReadBytes(stringLength);
                    data = Encoding.UTF8.GetString(stringBytes);
                    break;
                case DataTypeByteArray:
                    int byteArrayLength = recordSize - (sizeof(int) * 3);
                    data = _reader.ReadBytes(byteArrayLength);
                    break;
                default:
                    // Skip the rest of the record if the data type is unknown
                    int bytesToSkip = recordSize - (sizeof(int) * 3);
                    _fileStream.Seek(bytesToSkip, SeekOrigin.Current);
                    throw new InvalidDataException($"Unknown data type: {dataType}");
            }

            return userType;
        }
    }
}