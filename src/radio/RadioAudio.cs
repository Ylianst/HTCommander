using System;
using System.IO;
using System.Text;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using InTheHand.Net;
using InTheHand.Net.Sockets;
using InTheHand.Net.Bluetooth;
using NAudio.Wave;

namespace HTCommander
{
    public class RadioAudio
    {
        private const int ReceiveBufferSize = 1024;
        private BluetoothClient connectionClient;
        private LibSbc.sbc_struct sbcContext;
        private bool isSbcInitialized = false;
        private WaveOutEvent waveOut;
        //private RawSourceWaveStream waveSource;
        private BufferedWaveProvider waveProvider;
        private WaveFormat waveFormat;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;

        private void Debug(string msg)
        {
            if (OnDebugMessage != null) { OnDebugMessage(msg); }
        }
        private static string BytesToHex(byte[] data, int index, int length)
        {
            if (data == null) return "";
            StringBuilder Result = new StringBuilder(data.Length * 2);
            string HexAlphabet = "0123456789ABCDEF";
            for (int i = index; i < length; i++)
            {
                byte B = data[i];
                Result.Append(HexAlphabet[(int)(B >> 4)]);
                Result.Append(HexAlphabet[(int)(B & 0xF)]);
            }
            return Result.ToString();
        }

        private static byte[] UnescapeBytes(byte[] b)
        {
            var outList = new List<byte>();
            int i = 0;
            while (i < b.Length)
            {
                if (b[i] == 0x7d)
                {
                    i++;
                    if (i < b.Length) // Make sure we don't go out of bounds
                    {
                        outList.Add((byte)(b[i] ^ 0x20));
                    }
                    else
                    {
                        // Handle the case where 0x7d is the last byte (shouldn't happen in a valid escaped sequence)
                        // You might want to throw an exception or handle it differently based on your requirements.
                        // For now, we'll just break the loop.
                        break;
                    }
                }
                else
                {
                    outList.Add(b[i]);
                }
                i++;
            }
            return outList.ToArray();
        }

        private static byte[] EscapeBytes(byte[] b)
        {
            var outList = new List<byte>();
            foreach (byte currentByte in b)
            {
                if (currentByte == 0x7d || currentByte == 0x7e)
                {
                    outList.Add(0x7d);
                    outList.Add((byte)(currentByte ^ 0x20));
                }
                else
                {
                    outList.Add(currentByte);
                }
            }
            return outList.ToArray();
        }

        private static byte[] ExtractData(ref MemoryStream inputStream)
        {
            byte[] extractedData = null;
            long startPosition = -1;
            long endPosition = -1;

            // Read the entire stream into a byte array for easier processing
            byte[] buffer = inputStream.ToArray();

            // Find the first occurrence of 0x7e
            for (int i = 0; i < buffer.Length; i++)
            {
                if (buffer[i] == 0x7e) { startPosition = i; break; }
            }

            if (startPosition == -1)
            {
                // No start marker found, return null
                inputStream.Position = 0; // Reset the stream position
                return null;
            }

            // We found the end of the previous frame, move to next frame
            if ((startPosition < (buffer.Length - 1)) && (buffer[startPosition + 1] == 0x7e)) { startPosition++; }

            // If a start marker is found, look for the next 0x7e
            if (startPosition != -1)
            {
                for (int i = (int)startPosition + 1; i < buffer.Length; i++)
                {
                    if (buffer[i] == 0x7e) { endPosition = i; break; }
                }
            }

            // If both start and end markers are found
            if (startPosition != -1 && endPosition != -1 && endPosition > startPosition)
            {
                // Extract the data between the markers
                //extractedData = buffer.Skip((int)startPosition + 1).Take((int)(endPosition - startPosition - 1)).ToArray();

                extractedData = new byte[(int)(endPosition - startPosition - 1)];
                Array.Copy(buffer, (int)startPosition + 1, extractedData, 0, extractedData.Length);

                // Create a new MemoryStream with the data after the second 0x7e
                MemoryStream remainingStream = new MemoryStream();
                if (endPosition + 1 < buffer.Length)
                {
                    remainingStream.Write(buffer, (int)endPosition + 1, buffer.Length - (int)endPosition - 1);
                }

                inputStream = remainingStream;
            }
            else
            {
                // If no start and end markers are found, or they are not in the correct order,
                // just reset the MemoryStream to its original state (after reading).
                inputStream.Position = 0;
            }

            return extractedData;
        }

        public void Stop()
        {
            running = false;
        }

        public void Start(string mac)
        {
            if (running) return;
            //Task.Run(() => StartAsync(mac));
            StartAsync(mac);
        }

        public float Volume
        {
            get { return waveOut?.Volume ?? 0; }
            set { if (waveOut != null) { waveOut.Volume = value; } }
        }

        private async void StartAsync(string mac)
        {
            running = true;

            // Example: Using the Generic Audio UUID for A2DP Sink
            Guid rfcommServiceUuid = BluetoothService.GenericAudio;

            BluetoothAddress address = BluetoothAddress.Parse(mac);

            // Create the RFCOMM endpoint
            BluetoothEndPoint remoteEndPoint = new BluetoothEndPoint(address, rfcommServiceUuid, 2);

            // Create a new BluetoothClient for the connection
            connectionClient = new BluetoothClient();

            try
            {
                // Connect to the remote endpoint asynchronously
                Debug("Attempting to connect...");
                connectionClient.Connect(remoteEndPoint); // We can fix async later
                Debug("Successfully connected to the RFCOMM channel.");

                // Initialize SBC context with A2DP profile (likely)
                sbcContext = new LibSbc.sbc_struct();
                int initResult = LibSbc.sbc_init(ref sbcContext, 0);
                if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }
                isSbcInitialized = true;

                // Configure audio output (adjust format based on SBC parameters)
                // These are common A2DP SBC defaults, but the actual device might differ.
                int sampleRate = 32000;
                int channels = 1;// (sbcContext.mode == SBC_MODE_MONO) ? 1 : 2;
                int bitsPerSample = 16;
                waveFormat = new WaveFormat(sampleRate, bitsPerSample, channels);
                waveProvider = new BufferedWaveProvider(waveFormat);
                //waveProvider.BufferDuration = new TimeSpan(0, 0, 0, 0, 500);
                waveOut = new WaveOutEvent();
                waveOut.Init(waveProvider);
                waveOut.Play();

                MemoryStream accumulator = new MemoryStream();

                using (NetworkStream stream = connectionClient.GetStream())
                {
                    Debug("Ready to receive data.");
                    byte[] receiveBuffer = new byte[ReceiveBufferSize];

                    while (running && connectionClient.Connected)
                    {
                        try
                        {
                            /*
                            // Receive data asynchronously
                            int bytesRead = await stream.ReadAsync(receiveBuffer, 0, receiveBuffer.Length);

                            if (bytesRead > 0)
                            {
                                accumulator.Write(receiveBuffer, 0, bytesRead);
                                byte[] buffer = accumulator.GetBuffer();
                                long bufferLength = accumulator.Length;
                                long currentPosition = 0;

                                while (currentPosition < bufferLength)
                                {
                                    long startPosition = -1;
                                    long endPosition = -1;

                                    // Find the first occurrence of 0x7e from the current position
                                    for (long i = currentPosition; i < bufferLength; i++)
                                    {
                                        if (buffer[i] == 0x7e) { startPosition = i; break; }
                                    }

                                    // No start marker found in the remaining data
                                    if (startPosition == -1) { break; }

                                    // Move past consecutive 0x7e
                                    if ((startPosition < (bufferLength - 1)) && (buffer[startPosition + 1] == 0x7e)) { startPosition++; }

                                    // Find the next occurrence of 0x7e after the start marker
                                    for (long i = startPosition + 1; i < bufferLength; i++)
                                    {
                                        if (buffer[i] == 0x7e) { endPosition = i; break; }
                                    }

                                    if (endPosition != -1 && endPosition > startPosition)
                                    {
                                        // Extract the data between the markers
                                        byte[] frame = new byte[(int)(endPosition - startPosition - 1)];
                                        Array.Copy(buffer, (int)startPosition + 1, frame, 0, frame.Length);

                                        byte[] uframe = UnescapeBytes(frame);
                                        switch (uframe[0])
                                        {
                                            case 0x00: // Audio normal
                                            case 0x03: // Audio odd
                                                DecodeSbcFrame(uframe, 1, uframe.Length - 1);
                                                break;
                                            case 0x01: // Audio end
                                                //Debug("Command: 0x01, Audio End, Size: " + uframe.Length + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                                break;
                                            case 0x02: // Audio ACK
                                                //Debug("Command: 0x02, Audio Ack, Size: " + uframe.Length + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                                break;
                                            default:
                                                Debug($"Unknown command: {uframe[0]}");
                                                break;
                                        }

                                        // Move the current position past the processed frame
                                        currentPosition = endPosition + 1;
                                    }
                                    else
                                    {
                                        // No complete frame found, exit the inner loop
                                        break;
                                    }
                                }

                                // Create a new MemoryStream with the remaining data
                                if ((bufferLength - currentPosition) > 0)
                                {
                                    byte[] remainingBuffer = new byte[bufferLength - currentPosition];
                                    if (remainingBuffer.Length > 0) { Array.Copy(buffer, currentPosition, remainingBuffer, 0, remainingBuffer.Length); }
                                    accumulator.SetLength(0);
                                    accumulator.Write(remainingBuffer, 0, remainingBuffer.Length);
                                }
                                else
                                {
                                    accumulator.SetLength(0);
                                }
                            }
                            else if (bytesRead == 0)
                            {
                                Debug("Connection closed by remote host.");
                                break;
                            }
                            */

                            // Receive data asynchronously
                            int bytesRead = await stream.ReadAsync(receiveBuffer, 0, receiveBuffer.Length);

                            if (bytesRead > 0)
                            {
                                accumulator.Write(receiveBuffer, 0, bytesRead);
                                byte[] buffer = accumulator.GetBuffer();
                                byte[] frame;
                                while ((frame = ExtractData(ref accumulator)) != null)
                                {
                                    byte[] uframe = UnescapeBytes(frame);
                                    switch (uframe[0])
                                    {
                                        case 0x00: // Audio normal
                                        case 0x03: // Audio odd
                                            DecodeSbcFrame(uframe, 1, uframe.Length - 1);
                                            break;
                                        case 0x01: // Audio end
                                            //Debug("Command: 0x01, Audio End, Size: " + uframe.Length + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                            break;
                                        case 0x02: // Audio ACK
                                            //Debug("Command: 0x02, Audio Ack, Size: " + uframe.Length + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                            break;
                                        default:
                                            Debug($"Unknown command: {uframe[0]}");
                                            break;
                                    }
                                }
                            }
                            else if (bytesRead == 0)
                            {
                                Debug("Connection closed by remote host.");
                                break;
                            }
                        }
                        catch (Exception ex)
                        {
                            Debug($"Error reading from stream: {ex.Message}");
                            break;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Debug($"Connection error: {ex.Message}");
            }
            finally
            {
                running = false;
                connectionClient?.Close();
                waveOut?.Stop();
                waveOut?.Dispose();
                if (isSbcInitialized) { LibSbc.sbc_finish(ref sbcContext); }
                Debug("Bluetooth connection closed.");
            }
        }

        private int DecodeSbcFrame(byte[] sbcFrame, int start, int length)
        {
            if (sbcFrame == null || sbcFrame.Length == 0) return 1;

            // Pin the input SBC frame in memory
            GCHandle sbcHandle = GCHandle.Alloc(sbcFrame, GCHandleType.Pinned);
            IntPtr sbcPtr = sbcHandle.AddrOfPinnedObject() + start;
            UIntPtr sbcLen = (UIntPtr)length;

            // Parse the SBC frame to get its parameters
            IntPtr parsedPtr = LibSbc.sbc_parse(ref sbcContext, sbcPtr, sbcLen);
            if (parsedPtr == IntPtr.Zero) return 2; // Error parsing SBC frame.

            // Allocate a buffer for the decoded PCM data
            GCHandle pcmHandle = GCHandle.Alloc(pcmFrame, GCHandleType.Pinned);
            IntPtr pcmPtr = pcmHandle.AddrOfPinnedObject();
            UIntPtr pcmLen = (UIntPtr)pcmFrame.Length;
            UIntPtr written;//, totalWritten = 0;

            // Decode the SBC frame
            IntPtr decodeResult;
            while ((decodeResult = LibSbc.sbc_decode(ref sbcContext, sbcPtr, sbcLen, pcmPtr, pcmLen, out written)).ToInt64() > 0)
            {
                sbcPtr += (int)decodeResult;
                sbcLen -= (int)decodeResult;
                try { waveProvider.AddSamples(pcmFrame, 0, (int)written); } catch (Exception) { }
            }

            pcmHandle.Free();
            sbcHandle.Free();
            return 0;
        }

    }
}
