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
using System.Threading;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using InTheHand.Net;
using InTheHand.Net.Sockets;
using InTheHand.Net.Bluetooth;
using NAudio.Wave;
using NAudio.CoreAudioApi;
using NAudio.Wave.SampleProviders;
using HTCommander.radio;
using System.Diagnostics;

namespace HTCommander
{
    public class RadioAudio
    {
        private Radio parent;
        private const int ReceiveBufferSize = 1024;
        private BluetoothClient connectionClient;
        private LibSbc.sbc_struct sbcContext;
        private LibSbc.sbc_struct sbcContext2;
        private bool isSbcInitialized = false;
        private WasapiOut waveOut = null;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;
        private NetworkStream audioStream;
        public bool speechToText = false;
        private WhisperEngine speechToTextEngine = null;
        public string currentChannelName = "";
        public string voiceLanguage = "auto";
        public string voiceModel = null;
        private int pcmInputSizePerFrame; // Expected PCM bytes per encode call
        //private int sbcOutputSizePerFrame; // Max SBC bytes generated per encode call
        private byte[] sbcOutputBuffer; // Reusable buffer for SBC frame output
        private BufferedWaveProvider waveProvider = null;
        private float OutputVolume = 1;
        private float InputVolume = 1;
        private VolumeSampleProvider volumeProvider;
        public bool Recording { get { return recording != null; } }
        private WaveFileWriter recording = null;
        private MMDevice currentOutputDevice = null;

        public void StartRecording(string filename)
        {
            if (recording != null) { recording.Dispose(); recording = null; }
            recording = new WaveFileWriter(filename, new WaveFormat(32000, 16, 1));
        }

        public void StopRecording()
        {
            recording.Dispose();
            recording = null;
        }

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        public delegate void AudioStateChangedHandler(RadioAudio sender, bool enabled);
        public event AudioStateChangedHandler OnAudioStateChanged;
        public delegate void OnTextReadyHandler(string text, string channel, DateTime time, bool completed);
        public event OnTextReadyHandler onTextReady;
        public delegate void OnProcessingVoiceHandler(bool listening, bool processing);
        public event OnProcessingVoiceHandler onProcessingVoice;

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

        private static byte[] EscapeBytes(byte cmd, byte[] b, int len)
        {
            var outList = new List<byte>();
            outList.Add(0x7e);
            outList.Add(cmd);
            for (int i = 0; i < len; i++)
            {
                byte currentByte = b[i];
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
            outList.Add(0x7e);
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
            get { return volumeProvider?.Volume ?? InputVolume; }
            set { InputVolume = value; if (volumeProvider != null) { volumeProvider.Volume = value; } }
        }

        public void SetOutputDevice(string deviceid)
        {
            MMDevice targetDevice = null;
            MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
            if (deviceid != null)
            {
                if (deviceid.Length > 0)
                {
                    targetDevice = enumerator.GetDevice(deviceid);
                }
                else
                {
                    targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
                }
                if (targetDevice == null) { Debug("No audio device found."); return; }
            }

            if (currentOutputDevice == targetDevice) return;
            if (waveOut != null) { waveOut.Stop(); waveOut.Dispose(); waveOut = null; }
            waveProvider = null;
            volumeProvider = null;
            if (targetDevice == null) { return; }

            // Configure audio output (adjust format based on SBC parameters)
            // These are common A2DP SBC defaults, but the actual device might differ.
            WaveFormat waveFormat = new WaveFormat(32000, 16, 1);
            waveProvider = new BufferedWaveProvider(waveFormat);
            var sampleProvider = waveProvider.ToSampleProvider();
            currentOutputDevice = targetDevice;

            // Wrap with volume control
            volumeProvider = new VolumeSampleProvider(sampleProvider);
            volumeProvider.Volume = OutputVolume;

            waveOut = new WasapiOut(targetDevice, AudioClientShareMode.Shared, true, 50); // ****
            waveOut.Init(volumeProvider);
            waveOut.Play();
        }

        private async void StartAsync(string mac)
        {
            running = true;
            int maxVoiceDecodeTime = 0;
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

            try
            {
                // Initialize SBC context
                sbcContext2 = new LibSbc.sbc_struct();
                int initResult = LibSbc.sbc_init(ref sbcContext2, 0);
                sbcContext2.frequency = LibSbc.SBC_FREQ_32000;
                sbcContext2.blocks = LibSbc.SBC_BLK_16;
                sbcContext2.endian = LibSbc.SBC_LE;
                sbcContext2.mode = LibSbc.SBC_MODE_MONO;
                sbcContext2.allocation = LibSbc.SBC_AM_LOUDNESS;
                sbcContext2.subbands = LibSbc.SBC_SB_8;
                sbcContext2.bitpool = 18;
                if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }

                sbcContext = new LibSbc.sbc_struct();
                initResult = LibSbc.sbc_init(ref sbcContext, 0);
                if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }
                isSbcInitialized = true;

                // Get expected frame sizes
                pcmInputSizePerFrame = (int)LibSbc.sbc_get_codesize(ref sbcContext).ToUInt32();
                //sbcOutputSizePerFrame = (int)LibSbc.sbc_get_frame_length(ref sbcContext).ToUInt32();

                // Allocate reusable output buffer
                //sbcOutputBuffer = new byte[sbcOutputSizePerFrame + 1024];
                sbcOutputBuffer = new byte[1024];

                // If the output audio device is not set, use the default one
                if (waveOut == null) { SetOutputDevice(""); }

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
                                        if (parent.IsOnMuteChannel() == true) break;
                                        if (speechToText && (speechToTextEngine == null))
                                        {
                                            speechToTextEngine = new WhisperEngine(voiceModel, voiceLanguage);
                                            speechToTextEngine.OnDebugMessage += SpeechToTextEngine_OnDebugMessage;
                                            speechToTextEngine.onProcessingVoice += SpeechToTextEngine_onProcessingVoice;
                                            speechToTextEngine.onTextReady += SpeechToTextEngine_onTextReady;
                                            speechToTextEngine.StartVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                            if (onProcessingVoice != null) { onProcessingVoice(true, false); }
                                        }
                                        if (!speechToText && (speechToTextEngine != null))
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            speechToTextEngine.OnDebugMessage -= SpeechToTextEngine_OnDebugMessage;
                                            speechToTextEngine.onProcessingVoice -= SpeechToTextEngine_onProcessingVoice;
                                            speechToTextEngine.onTextReady -= SpeechToTextEngine_onTextReady;
                                            speechToTextEngine.Dispose();
                                            speechToTextEngine = null;
                                            if (onProcessingVoice != null) { onProcessingVoice(false, false); }
                                        }
                                        DecodeSbcFrame(uframe, 1, uframe.Length - 1);
                                        maxVoiceDecodeTime += (uframe.Length - 1);
                                        if ((speechToTextEngine != null) && (maxVoiceDecodeTime > 19200000)) // 5 minutes (32k * 2 * 60 & 5)
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                        }
                                        break;
                                    case 0x01: // Audio end
                                        //Debug("Command: 0x01, Audio End, Size: " + uframe.Length);// + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                        if (speechToTextEngine != null)
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                        }
                                        break;
                                    case 0x02: // Audio ACK
                                        //Debug("Command: 0x02, Audio Ack, Size: " + uframe.Length);// + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
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

                if (speechToTextEngine != null) {
                    speechToTextEngine.ResetVoiceSegment();
                    speechToTextEngine.OnDebugMessage -= SpeechToTextEngine_OnDebugMessage;
                    speechToTextEngine.onProcessingVoice -= SpeechToTextEngine_onProcessingVoice;
                    speechToTextEngine.onTextReady -= SpeechToTextEngine_onTextReady;
                    speechToTextEngine.Dispose();
                    speechToTextEngine = null;
                }

                if (speechToTextEngine != null) { speechToTextEngine.Dispose(); speechToTextEngine = null; }
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

        private void SpeechToTextEngine_OnDebugMessage(string msg)
        {
            Debug("Whisper: " + msg);
        }

        private void SpeechToTextEngine_onTextReady(string text, string channel, DateTime time, bool completed)
        {
            if (onTextReady != null) { onTextReady(text, channel, time, completed); }
        }
        private void SpeechToTextEngine_onProcessingVoice(bool processing)
        {
            if (onProcessingVoice != null) { onProcessingVoice(speechToTextEngine != null, processing); }
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
            IntPtr decodeResult, pcmPtr = pcmHandle.AddrOfPinnedObject();
            UIntPtr written, pcmLen = (UIntPtr)pcmFrame.Length;

            // Decode the SBC frame
            while ((decodeResult = LibSbc.sbc_decode(ref sbcContext, sbcPtr, sbcLen, pcmPtr, pcmLen, out written)).ToInt64() > 0)
            {
                sbcPtr += (int)decodeResult;
                sbcLen -= (int)decodeResult;
                if (waveProvider != null) {
                    try {
                        waveProvider.AddSamples(pcmFrame, 0, (int)written);
                    } catch (Exception) {
                        SetOutputDevice(null);
                    }
                }
                if (recording != null) { recording.Write(pcmFrame, 0, (int)written); }
                if (speechToTextEngine != null) { speechToTextEngine.ProcessAudioChunk(pcmFrame, 0, (int)written, currentChannelName); }
                parent.GotAudioData(pcmFrame, 0, (int)written, currentChannelName, false);
            }

            pcmHandle.Free();
            sbcHandle.Free();
            return 0;
        }

        //private bool VoiceTransmit = false;
        private bool VoiceTransmitCancel = false;
        public delegate void VoiceTransmitStateHandler(RadioAudio sender, bool transmitting);
        public event VoiceTransmitStateHandler OnVoiceTransmitStateChanged;

        public void CancelVoiceTransmit() {
            waveProvider.ClearBuffer();
            VoiceTransmitCancel = true;
            transmissionTokenSource?.Cancel();
        }

        // Fields
        private ConcurrentQueue<byte[]> pcmQueue = new ConcurrentQueue<byte[]>();
        private bool isTransmitting = false;
        private CancellationTokenSource transmissionTokenSource = null;
        private TaskCompletionSource<bool> newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        private bool PlayInputBack = false;

        public bool TransmitVoice(byte[] pcmInputData, int pcmOffset, int pcmLength, bool play)
        {
            // Copy just the relevant slice of PCM data
            PlayInputBack = play;
            byte[] pcmSlice = new byte[pcmLength];
            Buffer.BlockCopy(pcmInputData, pcmOffset, pcmSlice, 0, pcmLength);
            pcmQueue.Enqueue(pcmSlice);

            // Signal that new data is available
            if (isTransmitting) { newDataAvailable.TrySetResult(true); }

            StartTransmissionIfNeeded();
            //if (play) { VoiceTransmitCancel = false; PlayPcmBufferAsync(pcmInputData, pcmOffset, pcmLength); }
            return true;
        }

        private void StartTransmissionIfNeeded()
        {
            if (isTransmitting) return;

            Console.WriteLine("Starting voice transmission...");

            isTransmitting = true;
            transmissionTokenSource = new CancellationTokenSource();
            CancellationToken token = transmissionTokenSource.Token;
            Task.Run(async () =>
            {
                if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, true); }
                try
                {
                    while (!token.IsCancellationRequested)
                    {
                        if (pcmQueue.TryDequeue(out var pcmData)) { await ProcessPcmDataAsync(pcmData, token); } else { break; }
                    }
                    //// Send end audio frame
                    byte[] endAudio = { 0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e };
                    await audioStream.WriteAsync(endAudio, 0, endAudio.Length);
                    await audioStream.FlushAsync();
                }
                finally
                {
                    if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, false); }
                    Console.WriteLine("Voice transmission stopped.");
                    isTransmitting = false;
                }
            }, token);
        }

        private async Task ProcessPcmDataAsync(byte[] pcmData, CancellationToken token)
        {
            int pcmOffset = 0;
            int pcmLength = pcmData.Length;
            int bytesConsumed = 0;
            Task delayTask;
            Task signalTask;
            Task completedTask;

            var stopwatch = Stopwatch.StartNew();
            long bytesSent = 0;

            if (recording != null) { recording.Write(pcmData, 0, pcmData.Length); }
            while ((pcmLength >= pcmInputSizePerFrame) && (!token.IsCancellationRequested))
            {
                byte[] encodedSbcFrame;
                if (!EncodeSbcFrame(pcmData, pcmOffset, pcmLength, out encodedSbcFrame, out bytesConsumed)) break;

                // Send the audio frame to the radio
                byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);
                await audioStream.WriteAsync(escaped, 0, escaped.Length);
                await audioStream.FlushAsync();

                // Do extra processing if needed
                if (PlayInputBack) { PlayPcmBufferAsync(pcmData, pcmOffset, bytesConsumed); }
                parent.GotAudioData(pcmData, pcmOffset, bytesConsumed, currentChannelName, true);
                pcmOffset += bytesConsumed;
                pcmLength -= bytesConsumed;

                // Track how much PCM we are sending
                bytesSent += bytesConsumed;

                // Calculate expected elapsed time
                double expectedSeconds = (double)bytesSent / 64000.0;

                // Get actual elapsed time
                double actualSeconds = stopwatch.Elapsed.TotalSeconds;

                if (PlayInputBack && (expectedSeconds > actualSeconds))
                {
                    int sleepTimeMs = (int)((expectedSeconds - actualSeconds) * 1000);

                    // Wait for either delay or new data
                    delayTask = Task.Delay(sleepTimeMs, token);
                    signalTask = newDataAvailable.Task;
                    completedTask = await Task.WhenAny(delayTask, signalTask);
                    if (completedTask == signalTask)
                    {
                        // New data arrived, reset the signal
                        newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    }
                }
            }

            if ((bytesConsumed == 0) || token.IsCancellationRequested || (pcmQueue.Count > 0) || PlayInputBack) {
                Console.WriteLine("No transmit delay.");
                return;
            }

            // Wait for either delay or new data
            delayTask = Task.Delay(100, token);
            signalTask = newDataAvailable.Task;
            completedTask = await Task.WhenAny(delayTask, signalTask);
            if (completedTask == signalTask)
            {
                // New data arrived, reset the signal
                Console.WriteLine("New data arrived.");
                newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            }
            else
            {
                Console.WriteLine("Delay completed, stopping transmission.");
            }
        }

        /*
        public bool TransmitVoice(byte[] pcmInputData, int pcmOffset, int pcmLength, bool play)
        {
            if (VoiceTransmit == true) { return false; }
            Task.Run(() =>
            {
                VoiceTransmit = true;
                VoiceTransmitCancel = false;
                if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, true); }

                if (recording != null) { recording.Write(pcmInputData, pcmOffset, pcmLength); }
                if (play) { PlayPcmBufferAsync(pcmInputData, pcmOffset, pcmLength); }

                byte[] encodedSbcFrame;
                int bytesConsumed;
                int totalPcmLength = pcmLength;
                while ((pcmLength >= pcmInputSizePerFrame) && (VoiceTransmitCancel == false))
                {
                    // Process the PCM data in chunks, Encode PCM to SBC
                    if (!EncodeSbcFrame(pcmInputData, pcmOffset, pcmLength, out encodedSbcFrame, out bytesConsumed)) break;
                    pcmOffset += bytesConsumed;
                    pcmLength -= bytesConsumed;

                    // Escape the SBC frame
                    byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);

                    // Send the SBC frame over Bluetooth
                    audioStream.WriteAsync(escaped, 0, escaped.Length);
                    audioStream.FlushAsync();

                    // Hold off for a bit to allow the audio to play
                    Thread.Sleep(bytesConsumed / 64);
                    if (VoiceTransmitCancel) break;
                }

                // Send end audio frame
                byte[] endAudio = { 0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e };
                audioStream.WriteAsync(endAudio, 0, endAudio.Length);
                audioStream.FlushAsync();

                // We are done
                VoiceTransmit = false;
                if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, false); }
            });
            return true;
        }
        */

        public void PlayPcmBufferAsync(byte[] pcmInputData, int pcmOffset, int pcmLength)
        {
            Task.Run(() =>
            {
                int bytesPerMillisecond = waveProvider.WaveFormat.AverageBytesPerSecond / 1000;
                int chunkMilliseconds = 20;
                int chunkSize = bytesPerMillisecond * chunkMilliseconds;
                for (int offset = pcmOffset; offset < pcmOffset + pcmLength; offset += chunkSize)
                {
                    int bytesToCopy = Math.Min(chunkSize, pcmOffset + pcmLength - offset);
                    while ((waveProvider.BufferedBytes + bytesToCopy > waveProvider.BufferLength) && (VoiceTransmitCancel == false)) { Thread.Sleep(5); }
                    if (VoiceTransmitCancel == true) {
                        waveProvider.ClearBuffer();
                        return;
                    }
                    waveProvider.AddSamples(pcmInputData, offset, bytesToCopy);
                }
            });
        }

        private bool EncodeSbcFrame(byte[] pcmInputData, int pcmOffset, int pcmLength, out byte[] encodedSbcFrame, out int bytesConsumed)
        {
            encodedSbcFrame = null;
            bytesConsumed = 0;
            if (pcmInputData == null) { return false; }
            if (sbcOutputBuffer == null) { return false; }
            if (pcmLength < pcmInputSizePerFrame) { return false; }
            if (pcmOffset < 0 || pcmOffset >= pcmInputData.Length || pcmOffset + pcmInputSizePerFrame > pcmInputData.Length) { return false; }

            // Pin the PCM input buffer segment
            GCHandle pcmHandle = GCHandle.Alloc(pcmInputData, GCHandleType.Pinned);
            IntPtr pcmPtr = pcmHandle.AddrOfPinnedObject() + pcmOffset;
            //UIntPtr pcmLen = (UIntPtr)pcmInputSizePerFrame; // Process exactly one frame's worth
            UIntPtr pcmLen = (UIntPtr)pcmLength;

            // Pin the reusable SBC output buffer
            GCHandle sbcHandle = GCHandle.Alloc(sbcOutputBuffer, GCHandleType.Pinned);
            IntPtr sbcPtr = sbcHandle.AddrOfPinnedObject();
            UIntPtr sbcBufLen = (UIntPtr)(sbcOutputBuffer.Length); // Max capacity
            IntPtr sbcBytesWritten; // To receive the actual number of bytes written

            int TotalToConsume = pcmLength;
            int TotalGenerated = 0;

            try
            {
                while ((TotalToConsume >= pcmInputSizePerFrame) && (TotalGenerated < 300))
                {
                    // Call the native SBC encode function
                    int bytesConsumedThisRound = (int)LibSbc.sbc_encode(ref sbcContext2, pcmPtr, pcmLen, sbcPtr, sbcBufLen, out sbcBytesWritten).ToInt64();
                    if (bytesConsumedThisRound < 0) return false;
                    int sbcWrittenBytes = (int)sbcBytesWritten.ToInt64();

                    TotalToConsume -= bytesConsumedThisRound;
                    TotalGenerated += sbcWrittenBytes;
                    pcmPtr += bytesConsumedThisRound;
                    pcmLen -= bytesConsumedThisRound;
                    sbcPtr += sbcWrittenBytes;
                    sbcBufLen -= sbcWrittenBytes;
                    bytesConsumed += bytesConsumedThisRound;
                }

                // If bytes were written to the SBC buffer, copy them to the output array
                if (TotalGenerated > 0)
                {
                    encodedSbcFrame = new byte[TotalGenerated];
                    Array.Copy(sbcOutputBuffer, 0, encodedSbcFrame, 0, TotalGenerated);
                }

                return true;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Exception during SBC encoding: {ex.Message}");
                return false;
            }
            finally
            {
                // Unpin the memory handles
                if (sbcHandle.IsAllocated) sbcHandle.Free();
                if (pcmHandle.IsAllocated) pcmHandle.Free();
            }
        }


        public static void ParseSbcFrame(byte[] data)
        {
            if (data.Length < 4)
            {
                Console.WriteLine("Frame too short to be valid.");
                return;
            }

            int index = 0;

            // Sync word
            if (data[index++] != 0x9C)
            {
                Console.WriteLine("Invalid SBC frame: Missing sync word (0x9C).");
                return;
            }

            byte headerByte = data[index++];

            // Sampling Frequency
            int samplingFreq = (headerByte >> 6) & 0x03;
            string[] frequencies = { "16 kHz", "32 kHz", "44.1 kHz", "48 kHz" };

            // Block Count
            int blocks = ((headerByte >> 4) & 0x03);
            int[] blockValues = { 4, 8, 12, 16 };

            // Channel Mode
            int channelMode = (headerByte >> 2) & 0x03;
            string[] channelModes = { "Mono", "Dual Channel", "Stereo", "Joint Stereo" };

            // Allocation Method
            int allocationMethod = (headerByte >> 1) & 0x01;
            string allocation = allocationMethod == 0 ? "Loudness" : "SNR";

            // Subbands
            int subbands = (headerByte & 0x01) == 0 ? 4 : 8;

            // Bitpool
            byte bitpool = data[index++];

            // CRC
            byte crc = data[index++];

            Console.WriteLine("SBC Frame Parsed:");
            Console.WriteLine($"  Sampling Frequency : {frequencies[samplingFreq]}");
            Console.WriteLine($"  Blocks             : {blockValues[blocks]}");
            Console.WriteLine($"  Channel Mode       : {channelModes[channelMode]}");
            Console.WriteLine($"  Allocation Method  : {allocation}");
            Console.WriteLine($"  Subbands           : {subbands}");
            Console.WriteLine($"  Bitpool            : {bitpool}");
            Console.WriteLine($"  CRC                : 0x{crc:X2}");
        }

    }
}
