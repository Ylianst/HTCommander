using System;
using System.IO;
using System.Threading;
using System.Net.Sockets;
using System.Speech.AudioFormat; // Requires reference to System.Speech assembly
using System.Speech.Recognition;
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
        private Radio parent;
        private const int ReceiveBufferSize = 1024;
        private BluetoothClient connectionClient;
        private LibSbc.sbc_struct sbcContext;
        private bool isSbcInitialized = false;
        private WaveOutEvent waveOut;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;
        private NetworkStream audioStream;
        public bool voiceToText = true;

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        public delegate void AudioStateChangedHandler(RadioAudio sender, bool enabled);
        public event AudioStateChangedHandler OnAudioStateChanged;

        public RadioAudio(Radio radio) { parent = radio; }

        private void Debug(string msg) { if (OnDebugMessage != null) { OnDebugMessage(msg); } }

        public bool IsAudioEnabled { get { return running; } }

        private static byte[] UnescapeBytes(byte[] b)
        {
            var outList = new List<byte>();
            int i = 0;
            while (i < b.Length)
            {
                if (b[i] == 0x7d)
                {
                    i++;
                    // Make sure we don't go out of bounds
                    if (i < b.Length) { outList.Add((byte)(b[i] ^ 0x20)); } else { break; }
                }
                else { outList.Add(b[i]); }
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
            for (int i = 0; i < buffer.Length; i++) { if (buffer[i] == 0x7e) { startPosition = i; break; } }

            // No start marker found, return null
            if (startPosition == -1) { inputStream.Position = 0; return null; }

            // We found the end of the previous frame, move to next frame
            if ((startPosition < (buffer.Length - 1)) && (buffer[startPosition + 1] == 0x7e)) { startPosition++; }

            // If a start marker is found, look for the next 0x7e
            if (startPosition != -1) { for (int i = (int)startPosition + 1; i < buffer.Length; i++) { if (buffer[i] == 0x7e) { endPosition = i; break; } } }

            // If both start and end markers are found
            if (startPosition != -1 && endPosition != -1 && endPosition > startPosition)
            {
                // Extract the data between the markers
                //extractedData = buffer.Skip((int)startPosition + 1).Take((int)(endPosition - startPosition - 1)).ToArray();

                extractedData = new byte[(int)(endPosition - startPosition - 1)];
                Array.Copy(buffer, (int)startPosition + 1, extractedData, 0, extractedData.Length);

                // Create a new MemoryStream with the data after the second 0x7e
                MemoryStream remainingStream = new MemoryStream();
                if (endPosition + 1 < buffer.Length) { remainingStream.Write(buffer, (int)endPosition + 1, buffer.Length - (int)endPosition - 1); }
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
            if (running == false) return;
            running = false;
            try { if (audioStream != null) { audioStream.Dispose(); } } catch (Exception) { }
            if (OnAudioStateChanged != null) { OnAudioStateChanged(this, false); }
        }

        public void Start(string mac)
        {
            if (running) return;
            StartAsync(mac);
        }

        public float Volume
        {
            get { return waveOut?.Volume ?? 0; }
            set { if (waveOut != null) { waveOut.Volume = value; } }
        }

        private class SpeechStreamer : Stream
        {
            private AutoResetEvent _writeEvent;
            private List<byte> _buffer;
            private int _buffersize;
            private int _readposition;
            private int _writeposition;
            private bool _reset;

            public SpeechStreamer(int bufferSize)
            {
                _writeEvent = new AutoResetEvent(false);
                _buffersize = bufferSize;
                _buffer = new List<byte>(_buffersize);
                for (int i = 0; i < _buffersize; i++)
                    _buffer.Add(new byte());
                _readposition = 0;
                _writeposition = 0;
            }

            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return true; } }
            public override long Length { get { return -1L; } }
            public override long Position { get { return 0L; } set { } }
            public override long Seek(long offset, SeekOrigin origin) { return 0L; }
            public override void SetLength(long value) { }
            public override int Read(byte[] buffer, int offset, int count)
            {
                int i = 0;
                while (i < count && _writeEvent != null)
                {
                    if (!_reset && _readposition >= _writeposition) { _writeEvent.WaitOne(100, true); continue; }
                    buffer[i] = _buffer[_readposition + offset];
                    _readposition++;
                    if (_readposition == _buffersize) { _readposition = 0; _reset = false; }
                    i++;
                }
                return count;
            }

            public override void Write(byte[] buffer, int offset, int count)
            {
                for (int i = offset; i < offset + count; i++)
                {
                    _buffer[_writeposition] = buffer[i];
                    _writeposition++;
                    if (_writeposition == _buffersize) { _writeposition = 0; _reset = true; }
                }
                _writeEvent.Set();
            }

            public override void Close() { _writeEvent.Close(); _writeEvent = null; base.Close(); }
            public override void Flush() { }
        }

        private async void StartAsync(string mac)
        {
            running = true;
            Guid rfcommServiceUuid = BluetoothService.GenericAudio;
            BluetoothAddress address = BluetoothAddress.Parse(mac);
            BluetoothEndPoint remoteEndPoint = new BluetoothEndPoint(address, rfcommServiceUuid, 2);
            connectionClient = new BluetoothClient();

            // Connect to the remote endpoint asynchronously
            Debug("Attempting to connect...");
            try
            {
                connectionClient.Connect(remoteEndPoint);
            } catch (Exception ex)
            {
                Debug($"Connection error: {ex.Message}");
                connectionClient.Dispose();
                connectionClient = null;
                running = false;
                return;
            }
            Debug("Successfully connected to the RFCOMM channel.");

            SpeechRecognitionEngine recognizer = null;
            SpeechStreamer recognizerAudioStream = null;
            if (voiceToText)
            {
                // Setup voice-to-text engine
                recognizer = new SpeechRecognitionEngine();
                recognizer.SpeechRecognized += Recognizer_SpeechRecognized;
                recognizer.RecognizeCompleted += Recognizer_RecognizeCompleted;
                recognizer.SpeechRecognitionRejected += Recognizer_SpeechRecognitionRejected; // Optional but good
                recognizer.LoadGrammar(new DictationGrammar()); // DictationGrammar is simplest for free-form text.

                // Define the audio format for the recognizer
                SpeechAudioFormatInfo formatInfo = new SpeechAudioFormatInfo(32000, AudioBitsPerSample.Sixteen, AudioChannel.Mono);

                // Use our custom pipe stream
                recognizerAudioStream = new SpeechStreamer(100000);

                // RecognizeAsync runs in the background. RecognizeCompleted will fire when done.
                // RecognizeMode.Single stops after the first recognized phrase.
                // Use RecognizeMode.Multiple for continuous recognition until StopAsync is called.
                recognizer.SetInputToAudioStream(recognizerAudioStream, formatInfo);
                recognizer.RecognizeAsync(RecognizeMode.Multiple);
            }

            try
            {
                // Initialize SBC context
                sbcContext = new LibSbc.sbc_struct();
                int initResult = LibSbc.sbc_init(ref sbcContext, 0);
                if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }
                isSbcInitialized = true;

                // Configure audio output (adjust format based on SBC parameters)
                // These are common A2DP SBC defaults, but the actual device might differ.
                WaveFormat waveFormat = new WaveFormat(32000, 16, 1);
                BufferedWaveProvider waveProvider = new BufferedWaveProvider(waveFormat);
                waveOut = new WaveOutEvent();
                waveOut.Init(waveProvider);
                waveOut.Play();

                MemoryStream accumulator = new MemoryStream();
                using (NetworkStream stream = connectionClient.GetStream())
                {
                    audioStream = stream;
                    Debug("Ready to receive data.");
                    if (OnAudioStateChanged != null) { OnAudioStateChanged(this, true); }
                    byte[] receiveBuffer = new byte[ReceiveBufferSize];

                    while (running && connectionClient.Connected)
                    {
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
                                        if (parent.IsOnMuteChannel() == false) { DecodeSbcFrame(waveProvider, recognizerAudioStream, recognizer, uframe, 1, uframe.Length - 1); }
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
                            if (running) { Debug("Connection closed by remote host."); }
                            break;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                if (running) { Debug($"Connection error: {ex.Message}"); }
            }
            finally
            {
                running = false;
                if (recognizer != null) { recognizer.RecognizeAsyncStop(); }
                if (OnAudioStateChanged != null) { OnAudioStateChanged(this, false); }
                connectionClient?.Close();
                waveOut?.Stop();
                waveOut?.Dispose();
                waveOut = null;
                audioStream = null;
                if (isSbcInitialized) { LibSbc.sbc_finish(ref sbcContext); }
                Debug("Bluetooth connection closed.");
            }
        }

        private void Recognizer_SpeechRecognized(object sender, SpeechRecognizedEventArgs e)
        {
            if (e.Result != null)
            {
                Debug($"Recognized: {e.Result.Text} (Confidence: {e.Result.Confidence:P1})");
            }
            else
            {
                Debug("Recognized: (null result)");
            }
        }

        private void Recognizer_RecognizeCompleted(object sender, RecognizeCompletedEventArgs e)
        {
            if (e.Error != null)
            {
                Debug($"Completed with error: {e.Error.Message}");
            }
            else if (e.Cancelled)
            {
                Debug("Recognition cancelled.");
            }
            else if (e.InputStreamEnded)
            {
                Debug("Recognition completed (stream ended).");
            }
            else
            {
                Debug("Recognition completed."); // Generic completion
            }
        }

        private void Recognizer_SpeechRecognitionRejected(object sender, SpeechRecognitionRejectedEventArgs e)
        {
            if (e.Result != null) // Can still have partial results sometimes
            {
                Debug($"Rejected: {e.Result.Text} (Confidence: {e.Result.Confidence:P1})");
            }
            else
            {
                Debug("Rejected: No speech recognized or matched grammar.");
            }
        }

        private int DecodeSbcFrame(BufferedWaveProvider waveProvider, SpeechStreamer recognizerAudioStream, SpeechRecognitionEngine recognizer, byte[] sbcFrame, int start, int length)
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
            IntPtr decodeResult, pcmPtr = pcmHandle.AddrOfPinnedObject();
            UIntPtr written, pcmLen = (UIntPtr)pcmFrame.Length;

            // Decode the SBC frame
            while ((decodeResult = LibSbc.sbc_decode(ref sbcContext, sbcPtr, sbcLen, pcmPtr, pcmLen, out written)).ToInt64() > 0)
            {
                sbcPtr += (int)decodeResult;
                sbcLen -= (int)decodeResult;
                try { waveProvider.AddSamples(pcmFrame, 0, (int)written); } catch (Exception) { }
                if (recognizerAudioStream != null) { recognizerAudioStream.Write(pcmFrame, 0, (int)written); }
            }

            pcmHandle.Free();
            sbcHandle.Free();
            return 0;
        }

    }
}
