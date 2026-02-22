/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using WinBluetooth = Windows.Devices.Bluetooth;
using WinRfcomm = Windows.Devices.Bluetooth.Rfcomm;
using NAudio.Wave;
using NAudio.CoreAudioApi;
using NAudio.Wave.SampleProviders;

namespace HTCommander
{
    public class RadioAudio : IDisposable
    {
        private Radio parent;
        private const int ReceiveBufferSize = 1024;
        private readonly DataBrokerClient broker;
        private readonly int DeviceId;
        private readonly string MacAddress;

        // Bluetooth connection resources
        private Windows.Networking.Sockets.StreamSocket bluetoothSocket = null;
        private WinRfcomm.RfcommDeviceService rfcommService = null;
        private Stream winRtInputStream = null;
        private Stream winRtOutputStream = null;
        private CancellationTokenSource audioLoopCts = null;
        private readonly object connectionLock = new object();
        private Task audioLoopTask = null;
        private bool isConnecting = false;

        // SBC codec
        private SbcDecoder sbcDecoder;
        private SbcEncoder sbcEncoder;
        private SbcFrame sbcDecoderFrame;
        private SbcFrame sbcEncoderFrame;

        private WasapiOut waveOut = null;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;
        private NetworkStream audioStream;
        public string currentChannelName = "";
        public int currentChannelId = 0;
        private int pcmInputSizePerFrame; // Expected PCM bytes per encode call
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

        public RadioAudio(Radio radio, int deviceid, string mac) 
        { 
            parent = radio;
            DeviceId = deviceid;
            MacAddress = mac;
            broker = new DataBrokerClient();
            
            // Subscribe to Data Broker commands for audio control
            broker.Subscribe(DeviceId, "SetOutputAudioDevice", OnSetOutputAudioDevice);
            broker.Subscribe(DeviceId, "SetOutputVolume", OnSetOutputVolume);
            broker.Subscribe(DeviceId, "TransmitVoicePCM", OnTransmitVoicePCM);
            broker.Subscribe(DeviceId, "StartRecording", OnStartRecording);
            broker.Subscribe(DeviceId, "StopRecording", OnStopRecording);
            broker.Subscribe(DeviceId, "CancelVoiceTransmit", OnCancelVoiceTransmit);
            
            // Initialize output volume from stored value
            OutputVolume = broker.GetValue<float>(DeviceId, "OutputVolume", 1.0f);
        }
        
        // Data Broker event handlers
        private void OnSetOutputAudioDevice(int deviceId, string name, object data)
        {
            if (data is string audioDeviceId)
            {
                SetOutputDevice(audioDeviceId);
                broker.Dispatch(DeviceId, "OutputAudioDevice", audioDeviceId, store: true);
            }
        }
        
        private void OnSetOutputVolume(int deviceId, string name, object data)
        {
            if (data is float volume)
            {
                OutputVolume = volume;
                if (volumeProvider != null) { volumeProvider.Volume = volume; }
                broker.Dispatch(DeviceId, "OutputVolume", volume, store: true);
            }
            else if (data is int volumeInt)
            {
                float vol = volumeInt / 100f;
                OutputVolume = vol;
                if (volumeProvider != null) { volumeProvider.Volume = vol; }
                broker.Dispatch(DeviceId, "OutputVolume", vol, store: true);
            }
        }
        
        private void OnTransmitVoicePCM(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            // Support both simple byte[] and object with PlayLocally flag
            byte[] pcmData = null;
            bool playLocally = false;
            
            if (data is byte[] directPcmData)
            {
                // Simple byte array - default to no local playback
                pcmData = directPcmData;
                playLocally = false;
            }
            else
            {
                // Try to extract from anonymous object with Data and PlayLocally properties
                try
                {
                    var type = data.GetType();
                    var dataProp = type.GetProperty("Data");
                    var playLocallyProp = type.GetProperty("PlayLocally");
                    
                    if (dataProp != null)
                    {
                        pcmData = dataProp.GetValue(data) as byte[];
                    }
                    if (playLocallyProp != null)
                    {
                        object playValue = playLocallyProp.GetValue(data);
                        if (playValue is bool b) playLocally = b;
                    }
                }
                catch (Exception) { return; }
            }
            
            if (pcmData != null && pcmData.Length > 0)
            {
                TransmitVoice(pcmData, 0, pcmData.Length, playLocally);
            }
        }
        
        private void OnStartRecording(int deviceId, string name, object data)
        {
            if (data is string filename && !string.IsNullOrEmpty(filename))
            {
                StartRecording(filename);
                broker.Dispatch(DeviceId, "Recording", true, store: true);
            }
        }
        
        private void OnStopRecording(int deviceId, string name, object data)
        {
            StopRecording();
            broker.Dispatch(DeviceId, "Recording", false, store: true);
        }
        
        private void OnCancelVoiceTransmit(int deviceId, string name, object data)
        {
            CancelVoiceTransmit();
        }

        /// <summary>
        /// Disposes of all resources used by RadioAudio, including the data broker.
        /// </summary>
        public void Dispose()
        {
            // Stop audio streaming first
            Stop();

            // Dispose recording if active
            try { recording?.Dispose(); } catch (Exception) { }
            recording = null;

            // Dispose wave output
            try { waveOut?.Stop(); } catch (Exception) { }
            try { waveOut?.Dispose(); } catch (Exception) { }
            waveOut = null;
            waveProvider = null;
            volumeProvider = null;

            // Cancel any ongoing transmission
            try { transmissionTokenSource?.Cancel(); } catch (Exception) { }
            try { transmissionTokenSource?.Dispose(); } catch (Exception) { }
            transmissionTokenSource = null;

            // Clear queues
            while (pcmQueue.TryDequeue(out _)) { }

            // Dispose the data broker client
            broker?.Dispose();

            // Clear parent reference
            parent = null;
        }

        private void Debug(string msg) { broker.Dispatch(1, "LogInfo", $"[RadioAudio/{DeviceId}]: {msg}", store: false); }
        
        /// <summary>
        /// Fast calculation of max amplitude from 16-bit PCM data, normalized to 0.0-1.0
        /// </summary>
        private static unsafe float CalculatePcmAmplitude(byte[] pcmData, int bytesRecorded)
        {
            if (pcmData == null || bytesRecorded < 2) return 0f;
            short max = 0;
            fixed (byte* ptr = pcmData)
            {
                short* samples = (short*)ptr;
                int count = bytesRecorded / 2;
                for (int i = 0; i < count; i++)
                {
                    short val = samples[i];
                    if (val < 0) val = (short)-val; // Absolute value
                    if (val > max) max = val;
                }
            }
            return Math.Min(1.0f, max / 32768f);
        }
        
        private void DispatchAudioStateChanged(bool enabled) { broker.Dispatch(DeviceId, "AudioState", enabled, store: true); }
        private void DispatchVoiceTransmitStateChanged(bool transmitting) { broker.Dispatch(DeviceId, "VoiceTransmitStateChanged", transmitting, store: false); }
        private void DispatchAudioDataAvailable(byte[] data, int offset, int length, string channelName, bool transmit, bool muted) { broker.Dispatch(DeviceId, "AudioDataAvailable", new { Data = data, Offset = offset, Length = length, ChannelName = channelName, Transmit = transmit, Muted = muted, AudioRunStartTime = audioRunStartTime, Usage = parent.LockUsage }, store: false); }
        private void DispatchAudioDataStart() { audioRunStartTime = DateTime.Now; broker.Dispatch(DeviceId, "AudioDataStart", new { StartTime = audioRunStartTime, ChannelName = currentChannelName }, store: false); }
        private void DispatchAudioDataEnd() { broker.Dispatch(DeviceId, "AudioDataEnd", audioRunStartTime, store: false); broker.Dispatch(DeviceId, "OutputAmplitude", 0f, store: false); }

        // Audio run state tracking
        private bool inAudioRun = false;
        private DateTime audioRunStartTime = DateTime.MinValue;

        public bool IsAudioEnabled { get { return running; } }

        private static unsafe int UnescapeBytesInPlace(byte[] buffer)
        {
            if (buffer == null || buffer.Length == 0) return 0;
            fixed (byte* pBuffer = buffer)
            {
                byte* src = pBuffer;
                byte* dst = pBuffer;
                byte* end = pBuffer + buffer.Length;
                while (src < end)
                {
                    if (*src == 0x7d) // Escape byte
                    {
                        src++;
                        if (src < end) { *dst = (byte)(*src ^ 0x20); dst++; } else { break; }
                    }
                    else { *dst = *src; dst++; }
                    src++;
                }
                return (int)(dst - pBuffer); // New length after unescaping
            }
        }

        private static unsafe byte[] EscapeBytes(byte cmd, byte[] b, int len)
        {
            // Estimate worst case: each byte could expand to 2 bytes (if it needs escaping), plus 2 for start/end
            int maxLen = 2 + len * 2;
            byte[] result = new byte[maxLen];
            fixed (byte* bPtr = b)
            fixed (byte* rPtr = result)
            {
                byte* src = bPtr;
                byte* dest = rPtr;
                *dest++ = 0x7e;
                *dest++ = cmd;
                for (int i = 0; i < len; i++)
                {
                    byte currentByte = *src++;
                    if (currentByte == 0x7d || currentByte == 0x7e)
                    {
                        *dest++ = 0x7d;
                        *dest++ = (byte)(currentByte ^ 0x20);
                    }
                    else { *dest++ = currentByte; }
                }
                *dest++ = 0x7e;
                int finalLen = (int)(dest - rPtr);
                // Resize array to actual length
                Array.Resize(ref result, finalLen);
            }
            return result;
        }

        private byte[] ExtractData(ref MemoryStream inputStream)
        {
            while (true)
            {
                if (inputStream.Length < 2) return null;

                if (!inputStream.TryGetBuffer(out ArraySegment<byte> bufferSegment))
                {
                    bufferSegment = new ArraySegment<byte>(inputStream.GetBuffer(), 0, (int)inputStream.Length);
                }

                byte[] buffer = bufferSegment.Array;
                int bufferLength = bufferSegment.Count;
                int start = -1, end = -1;

                // Skip past any leading consecutive 0x7e bytes, keeping the last one as the start marker
                int scanFrom = 0;
                if (bufferLength >= 2 && buffer[0] == 0x7e && buffer[1] == 0x7e) {
                    scanFrom = 1;
                    Debug($"ExtractData: skipping leading consecutive 0x7E bytes, starting scan from index {scanFrom}");
                }
                for (int i = scanFrom; i < bufferLength; i++)
                {
                    if (buffer[i] == 0x7e)
                    {
                        if (start == -1)
                        {
                            start = i;
                        }
                        else
                        {
                            // Found end marker
                            end = i;
                            break;
                        }
                    }
                }

                if (start != -1 && end != -1 && end > start + 1)
                {
                    // Extract data between markers (excluding the 0x7e bytes)
                    int dataLength = end - start - 1;
                    byte[] extractedData = new byte[dataLength];
                    Buffer.BlockCopy(buffer, start + 1, extractedData, 0, dataLength);

                    // Discard the end 0x7e and keep only what follows
                    int remaining = bufferLength - (end + 1);
                    if (remaining > 0)
                    {
                        Buffer.BlockCopy(buffer, end + 1, buffer, 0, remaining);
                        inputStream.SetLength(remaining);
                        inputStream.Position = remaining; // Position at end for next write
                    }
                    else
                    {
                        inputStream.SetLength(0);
                        inputStream.Position = 0;
                    }
                    return extractedData;
                }
                else if (start != -1 && end != -1 && end == start + 1)
                {
                    // Two consecutive 0x7e: discard everything up to and including the first 0x7e,
                    // but keep the second 0x7e as it may be the start marker of the next frame.
                    // remaining is always >= 1 since we're keeping the 0x7e at position 'end'.
                    int remaining = bufferLength - end;
                    Debug($"ExtractData: consecutive 0x7E at positions {start},{end}, discarding {end} bytes before, {remaining} remaining");
                    Buffer.BlockCopy(buffer, end, buffer, 0, remaining);
                    inputStream.SetLength(remaining);
                    inputStream.Position = remaining;
                    continue; // Loop again to try to find a complete frame
                }
                else if (start > 0)
                {
                    // Discard garbage bytes before the first 0x7e marker
                    int remaining = bufferLength - start;
                    Debug($"ExtractData: discarding {start} garbage bytes before first 0x7E, {remaining} remaining");
                    Buffer.BlockCopy(buffer, start, buffer, 0, remaining);
                    inputStream.SetLength(remaining);
                    inputStream.Position = remaining;
                    continue; // Loop again to try to find a complete frame
                }
                else if (start == -1)
                {
                    // No 0x7e found at all - discard everything as garbage
                    Debug($"ExtractData: no 0x7E found in {bufferLength} bytes, discarding all");
                    inputStream.SetLength(0);
                    inputStream.Position = 0;
                    return null;
                }
                else
                {
                    // Only one 0x7e found (start == 0), no end marker yet - wait for more data
                    inputStream.Position = inputStream.Length;
                    return null;
                }
            }
        }

        public void Stop()
        {
            lock (connectionLock)
            {
                if (running == false && audioLoopTask == null) return;
                running = false;
                
                // Cancel the audio loop
                try { audioLoopCts?.Cancel(); } catch (Exception) { }
            }
            
            // Wait for the audio loop to finish (with timeout)
            if (audioLoopTask != null)
            {
                try { audioLoopTask.Wait(TimeSpan.FromSeconds(3)); } catch (Exception) { }
            }
            
            lock (connectionLock)
            {
                // Dispose Bluetooth resources in correct order
                // First close streams, then socket, then service
                try { winRtInputStream?.Close(); } catch (Exception) { }
                try { winRtInputStream?.Dispose(); } catch (Exception) { }
                winRtInputStream = null;
                
                try { winRtOutputStream?.Close(); } catch (Exception) { }
                try { winRtOutputStream?.Dispose(); } catch (Exception) { }
                winRtOutputStream = null;
                
                try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                bluetoothSocket = null;
                
                try { rfcommService?.Dispose(); } catch (Exception) { }
                rfcommService = null;
                
                try { audioStream?.Close(); } catch (Exception) { }
                try { audioStream?.Dispose(); } catch (Exception) { }
                audioStream = null;
                
                try { audioLoopCts?.Dispose(); } catch (Exception) { }
                audioLoopCts = null;
                audioLoopTask = null;
            }
            
            DispatchAudioStateChanged(false);
            
            // Give the OS time to release the socket
            Thread.Sleep(100);
        }

        public void Start()
        {
            lock (connectionLock)
            {
                if (running || isConnecting) return;
                isConnecting = true;
            }
            audioLoopTask = Task.Run(() => { StartAsync(); });
        }

        public float Volume
        {
            get { return volumeProvider?.Volume ?? InputVolume; }
            set { InputVolume = value; if (volumeProvider != null) { volumeProvider.Volume = value; } }
        }

        public void SetOutputDevice(string deviceid)
        {
            try { if ((currentOutputDevice != null) && (currentOutputDevice.ID == deviceid)) { return; } } catch (Exception) { }

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
                    try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); } catch (Exception) { }
                }
                if (targetDevice == null) { Debug("No audio device found."); return; }
            }

            if (waveOut != null) { waveOut.Stop(); waveOut.Dispose(); waveOut = null; }
            waveProvider = null;
            volumeProvider = null;
            if (targetDevice == null) { return; }

            // Configure audio output (adjust format based on SBC parameters)
            WaveFormat waveFormat = new WaveFormat(32000, 16, 1);
            waveProvider = new BufferedWaveProvider(waveFormat);
            waveProvider.DiscardOnBufferOverflow = true;
            waveProvider.BufferDuration = TimeSpan.FromSeconds(2);
            var sampleProvider = waveProvider.ToSampleProvider();
            currentOutputDevice = targetDevice;

            // Wrap with volume control
            volumeProvider = new VolumeSampleProvider(sampleProvider);
            volumeProvider.Volume = OutputVolume;

            waveOut = new WasapiOut(targetDevice, AudioClientShareMode.Shared, true, 50);
            waveOut.Init(volumeProvider);
            waveOut.Play();
        }

        private async void StartAsync()
        {
            CancellationToken cancellationToken;
            
            lock (connectionLock)
            {
                running = true;
                audioLoopCts = new CancellationTokenSource();
                cancellationToken = audioLoopCts.Token;
            }

            // Use WinRT Bluetooth APIs to connect to the device
            WinBluetooth.BluetoothDevice btDevice = null;
            WinRfcomm.RfcommDeviceService rfcommService = null;

            Debug("Attempting to connect using WinRT APIs...");
            try
            {
                // Convert MAC address to the format needed by WinRT (with colons)
                string macFormatted = MacAddress;
                if (!macFormatted.Contains(":"))
                {
                    macFormatted = string.Join(":", Enumerable.Range(0, 6).Select(i => MacAddress.Substring(i * 2, 2)));
                }

                // Get the Bluetooth device by MAC address
                ulong btAddress = Convert.ToUInt64(MacAddress.Replace(":", "").Replace("-", ""), 16);
                btDevice = await WinBluetooth.BluetoothDevice.FromBluetoothAddressAsync(btAddress);
                
                if (btDevice == null)
                {
                    Debug("Could not find Bluetooth device with address: " + MacAddress);
                    running = false;
                    return;
                }

                Debug($"Found device: {btDevice.Name}");

                // Get RFCOMM services from the device
                var rfcommServices = await btDevice.GetRfcommServicesAsync();
                
                if (rfcommServices.Services.Count == 0)
                {
                    Debug("No RFCOMM services found on device");
                    running = false;
                    return;
                }

                // Find the audio service (GenericAudio UUID: 00001203-0000-1000-8000-00805f9b34fb)
                Guid genericAudioUuid = new Guid("00001203-0000-1000-8000-00805f9b34fb");
                
                foreach (var service in rfcommServices.Services)
                {
                    Debug($"Found RFCOMM service: {service.ServiceId.Uuid} - {service.ConnectionServiceName}");
                    if (service.ServiceId.Uuid == genericAudioUuid)
                    {
                        rfcommService = service;
                        break;
                    }
                }

                // If GenericAudio not found, try the second service (index 1) as it might be the audio channel
                if (rfcommService == null && rfcommServices.Services.Count > 1)
                {
                    rfcommService = rfcommServices.Services[0];
                    Debug($"Using service at index 0: {rfcommService.ServiceId.Uuid}");
                }
                else if (rfcommService == null && rfcommServices.Services.Count > 0)
                {
                    rfcommService = rfcommServices.Services[0];
                    Debug($"Using first available service: {rfcommService.ServiceId.Uuid}");
                }

                if (rfcommService == null)
                {
                    Debug("Could not find suitable RFCOMM service");
                    running = false;
                    return;
                }

                // Connect to the RFCOMM service
                bluetoothSocket = new Windows.Networking.Sockets.StreamSocket();
                this.rfcommService = rfcommService;
                await bluetoothSocket.ConnectAsync(
                    rfcommService.ConnectionHostName,
                    rfcommService.ConnectionServiceName,
                    Windows.Networking.Sockets.SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);

                Debug("Successfully connected to the RFCOMM channel.");
            }
            catch (Exception ex)
            {
                Debug($"Connection error: {ex.Message}");
                lock (connectionLock)
                {
                    try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                    bluetoothSocket = null;
                    try { rfcommService?.Dispose(); } catch (Exception) { }
                    this.rfcommService = null;
                    running = false;
                    isConnecting = false;
                }
                return;
            }

            // Create stream wrapper for WinRT socket
            try
            {
                lock (connectionLock)
                {
                    isConnecting = false;
                    if (cancellationToken.IsCancellationRequested)
                    {
                        running = false;
                        try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                        bluetoothSocket = null;
                        try { rfcommService?.Dispose(); } catch (Exception) { }
                        this.rfcommService = null;
                        return;
                    }
                    
                    winRtInputStream = bluetoothSocket.InputStream.AsStreamForRead();
                    winRtOutputStream = bluetoothSocket.OutputStream.AsStreamForWrite();
                    audioStream = null; // We use winRtOutputStream directly now
                }

                // Initialize C# SBC implementation
                sbcDecoder = new SbcDecoder();
                sbcEncoder = new SbcEncoder();

                // Configure decoder frame (will be updated when parsing actual frames)
                sbcDecoderFrame = new SbcFrame
                {
                    Frequency = SbcFrequency.Freq32K,
                    Blocks = 16,
                    Mode = SbcMode.Mono,
                    AllocationMethod = SbcBitAllocationMethod.Loudness,
                    Subbands = 8,
                    Bitpool = 18
                };

                // Configure encoder frame
                sbcEncoderFrame = new SbcFrame
                {
                    Frequency = SbcFrequency.Freq32K,
                    Blocks = 16,
                    Mode = SbcMode.Mono,
                    AllocationMethod = SbcBitAllocationMethod.Loudness,
                    Subbands = 8,
                    Bitpool = 18
                };

                pcmInputSizePerFrame = sbcEncoderFrame.Blocks * sbcEncoderFrame.Subbands * 2; // 16-bit samples
                sbcOutputBuffer = new byte[1024];

                // If the output audio device is not set, use the default one
                if (waveOut == null) { SetOutputDevice(""); }

                MemoryStream accumulator = new MemoryStream();
                const int MaxAccumulatorSize = 64 * 1024; // 64KB safety cap
                
                Debug("Ready to receive data.");
                DispatchAudioStateChanged(true);
                byte[] receiveBuffer = new byte[ReceiveBufferSize];

                while (running && !cancellationToken.IsCancellationRequested)
                {
                    // Receive data asynchronously from WinRT stream with cancellation support
                    int bytesRead;
                    try
                    {
                        bytesRead = await winRtInputStream.ReadAsync(receiveBuffer, 0, receiveBuffer.Length, cancellationToken);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    if (bytesRead > 0)
                    {
                        byte[] frame;
                        accumulator.Write(receiveBuffer, 0, bytesRead);

                        // Safety: if accumulator grows too large without yielding frames, reset it
                        if (accumulator.Length > MaxAccumulatorSize)
                        {
                            Debug($"Accumulator overflow ({accumulator.Length} bytes), resetting.");
                            accumulator.SetLength(0);
                            accumulator.Position = 0;
                        }

                        while ((frame = ExtractData(ref accumulator)) != null)
                        {
                            int uframeLength = UnescapeBytesInPlace(frame);
                            if (uframeLength == 0) break;
                            switch (frame[0])
                            {
                                case 0x00: // Audio normal
                                case 0x03: // Audio odd
                                    if (!inAudioRun)
                                    {
                                        inAudioRun = true;
                                        DispatchAudioDataStart();
                                    }
                                    DecodeSbcFrame(frame, 1, uframeLength - 1);
                                    break;
                                case 0x01: // Audio end
                                    inAudioRun = false;
                                    DispatchAudioDataEnd();
                                    break;
                                case 0x02: // Audio ACK
                                    break;
                                default:
                                    Debug($"Unknown command: {frame[0]}");
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
            catch (Exception ex)
            {
                if (running) { Debug($"Connection error: {ex.Message}"); }
            }
            finally
            {
                lock (connectionLock)
                {
                    running = false;
                    isConnecting = false;
                }

                DispatchAudioStateChanged(false);
                waveOut?.Stop();
                waveOut?.Dispose();
                waveOut = null;

                // Dispose Bluetooth resources in correct order
                lock (connectionLock)
                {
                    try { winRtInputStream?.Close(); } catch (Exception) { }
                    try { winRtInputStream?.Dispose(); } catch (Exception) { }
                    winRtInputStream = null;
                    
                    try { winRtOutputStream?.Close(); } catch (Exception) { }
                    try { winRtOutputStream?.Dispose(); } catch (Exception) { }
                    winRtOutputStream = null;
                    
                    try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                    bluetoothSocket = null;
                    
                    try { rfcommService?.Dispose(); } catch (Exception) { }
                    rfcommService = null;
                    
                    try { audioStream?.Close(); } catch (Exception) { }
                    try { audioStream?.Dispose(); } catch (Exception) { }
                    audioStream = null;
                }

                // SBC cleanup
                sbcDecoder = null;
                sbcEncoder = null;

                Debug("Bluetooth connection closed.");
            }
        }

        private int DecodeSbcFrame(byte[] sbcFrame, int start, int length)
        {
            if (sbcFrame == null || sbcFrame.Length == 0) return 1;

            // Use C# SBC decoder
            try
            {
                int offset = start;
                int remaining = length;
                int totalWritten = 0;

                // Loop through all SBC frames in the buffer
                while (remaining > 0)
                {
                    // Quick sync byte validation: SBC frames start with 0x9C, mSBC with 0xAD
                    byte syncByte = sbcFrame[offset];
                    if (syncByte != 0x9C && syncByte != 0xAD)
                    {
                        break; // Not a valid SBC frame, stop decoding
                    }

                    // Probe frame header to get exact frame size before allocating
                    if (remaining < SbcFrame.HeaderSize) break;
                    byte[] headerProbe = new byte[SbcFrame.HeaderSize];
                    Buffer.BlockCopy(sbcFrame, offset, headerProbe, 0, SbcFrame.HeaderSize);
                    SbcFrame probed = sbcDecoder.Probe(headerProbe);
                    if (probed == null) break;
                    int frameSize = probed.GetFrameSize();
                    if (frameSize <= 0 || frameSize > remaining) break;

                    // Allocate only the exact frame size instead of copying entire remaining buffer
                    byte[] sbcData = new byte[frameSize];
                    Buffer.BlockCopy(sbcFrame, offset, sbcData, 0, frameSize);

                    // Decode one SBC frame
                    if (!sbcDecoder.Decode(sbcData, out short[] pcmLeft, out short[] pcmRight, out SbcFrame frame))
                    {
                        break; // Stop on decode error
                    }

                    // Validate the decoded frame size matches what we probed
                    if (frame.GetFrameSize() != frameSize)
                    {
                        break; // Invalid frame size
                    }

                    // Convert short[] to byte[] (16-bit PCM)
                    int pcmBytes = pcmLeft.Length * 2;
                    if (totalWritten + pcmBytes > pcmFrame.Length)
                    {
                        // Expand buffer if needed
                        Array.Resize(ref pcmFrame, totalWritten + pcmBytes);
                    }

                    Buffer.BlockCopy(pcmLeft, 0, pcmFrame, totalWritten, pcmBytes);
                    totalWritten += pcmBytes;

                    // Advance to next frame
                    offset += frameSize;
                    remaining -= frameSize;
                }

                // Make use of all accumulated PCM data
                if (totalWritten > 0)
                {
                    bool isMuted = parent.IsOnMuteChannel();
                    if (isMuted == false)
                    {
                        if (waveProvider != null)
                        {
                            // If buffered audio exceeds latency cap, discard stale data to catch up
                            if (waveProvider.BufferedDuration.TotalMilliseconds > 800)
                            {
                                waveProvider.ClearBuffer();
                            }
                            try { waveProvider.AddSamples(pcmFrame, 0, totalWritten); }
                            catch (Exception ex) { SetOutputDevice(null); Debug("WaveProvider AddSamples: " + ex.ToString()); }
                        }
                        if (recording != null)
                        {
                            try { recording.Write(pcmFrame, 0, totalWritten); }
                            catch (Exception ex) { Debug("Recording Write Error: " + ex.ToString()); }
                        }
                    }

                    byte[] pcmDataForEvent = new byte[totalWritten];
                    Buffer.BlockCopy(pcmFrame, 0, pcmDataForEvent, 0, totalWritten);
                    DispatchAudioDataAvailable(pcmDataForEvent, 0, totalWritten, currentChannelName, false, isMuted);

                    // Calculate and dispatch output amplitude (after volume is applied conceptually)
                    float amplitude = CalculatePcmAmplitude(pcmDataForEvent, totalWritten) * OutputVolume;
                    broker.Dispatch(DeviceId, "OutputAmplitude", amplitude, store: false);
                }

                return 0;
            }
            catch (Exception ex)
            {
                Debug("C# SBC Decode Error: " + ex.ToString());
                return 2;
            }
        }

        private bool EncodeSbcFrame(byte[] pcmInputData, int pcmOffset, int pcmLength, out byte[] encodedSbcFrame, out int bytesConsumed)
        {
            encodedSbcFrame = null;
            bytesConsumed = 0;
            if (pcmInputData == null) { return false; }
            if (sbcOutputBuffer == null) { return false; }
            if (pcmLength < pcmInputSizePerFrame) { return false; }
            if (pcmOffset < 0 || pcmOffset >= pcmInputData.Length || pcmOffset + pcmInputSizePerFrame > pcmInputData.Length) { return false; }

            // Use C# SBC encoder
            try
            {
                int TotalToConsume = pcmLength;
                int TotalGenerated = 0;
                int totalBytesConsumed = 0;
                byte[] outputBuffer = new byte[1024];
                int outputOffset = 0;

                while ((TotalToConsume >= pcmInputSizePerFrame) && (TotalGenerated < 300))
                {
                    int samplesPerChannel = sbcEncoderFrame.Blocks * sbcEncoderFrame.Subbands;

                    // Convert byte[] PCM to short[]
                    short[] pcmSamples = new short[samplesPerChannel];
                    Buffer.BlockCopy(pcmInputData, pcmOffset + totalBytesConsumed, pcmSamples, 0, samplesPerChannel * 2);

                    // Encode the frame
                    byte[] sbcFrameData = sbcEncoder.Encode(pcmSamples, null, sbcEncoderFrame);
                    if (sbcFrameData == null || sbcFrameData.Length == 0)
                    {
                        break;
                    }

                    // Copy to output buffer
                    if (outputOffset + sbcFrameData.Length > outputBuffer.Length)
                    {
                        break;
                    }
                    Buffer.BlockCopy(sbcFrameData, 0, outputBuffer, outputOffset, sbcFrameData.Length);
                    outputOffset += sbcFrameData.Length;

                    int bytesConsumedThisRound = samplesPerChannel * 2; // 16-bit samples
                    TotalToConsume -= bytesConsumedThisRound;
                    TotalGenerated += sbcFrameData.Length;
                    totalBytesConsumed += bytesConsumedThisRound;
                }

                if (TotalGenerated > 0)
                {
                    encodedSbcFrame = new byte[TotalGenerated];
                    Buffer.BlockCopy(outputBuffer, 0, encodedSbcFrame, 0, TotalGenerated);
                    bytesConsumed = totalBytesConsumed;
                    return true;
                }

                return false;
            }
            catch (Exception ex)
            {
                Debug("C# SBC Encode Error: " + ex.ToString());
                return false;
            }
        }

        private bool VoiceTransmitCancel = false;

        public void CancelVoiceTransmit()
        {
            VoiceTransmitCancel = true;
            transmissionTokenSource?.Cancel();
            
            // Clear local playback buffer
            try { waveProvider?.ClearBuffer(); } catch { }
            
            // Clear any pending PCM data in the queue
            while (pcmQueue.TryDequeue(out _)) { }
            ReminderTransmitPcmAudio = null;
            
            // Immediately send end audio frame to tell the radio to stop transmitting
            byte[] endAudio = { 0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e };
            if (winRtOutputStream != null)
            {
                try
                {
                    winRtOutputStream.Write(endAudio, 0, endAudio.Length);
                    winRtOutputStream.Flush();
                }
                catch { }
            }
        }

        // Voice transmission fields
        private ConcurrentQueue<byte[]> pcmQueue = new ConcurrentQueue<byte[]>();
        private bool isTransmitting = false;
        private CancellationTokenSource transmissionTokenSource = null;
        private TaskCompletionSource<bool> newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        private bool PlayInputBack = false;
        private byte[] ReminderTransmitPcmAudio = null;
        private volatile bool isPlayingBack = false; // Track if PlayPcmBufferAsync is actively streaming

        public bool TransmitVoice(byte[] pcmInputData, int pcmOffset, int pcmLength, bool play)
        {
            // Copy just the relevant slice of PCM data
            PlayInputBack = play;
            VoiceTransmitCancel = false;
            byte[] pcmSlice = new byte[pcmLength];
            Buffer.BlockCopy(pcmInputData, pcmOffset, pcmSlice, 0, pcmLength);
            pcmQueue.Enqueue(pcmSlice);

            // Signal that new data is available
            if (isTransmitting) { newDataAvailable.TrySetResult(true); }

            StartTransmissionIfNeeded();
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
                DispatchVoiceTransmitStateChanged(true);
                try
                {
                    while (!token.IsCancellationRequested)
                    {
                        if (pcmQueue.TryDequeue(out var pcmData))
                        {
                            await ProcessPcmDataAsync(pcmData, token);
                        }
                        else
                        {
                            // Wait for up to 100ms for more data. If none arrives, check if playback is still active.
                            Task delayTask = Task.Delay(100, token);
                            Task signalTask = newDataAvailable.Task;
                            Task completedTask = await Task.WhenAny(delayTask, signalTask);
                            if (completedTask == signalTask)
                            {
                                // New data arrived, reset the signal
                                newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                            }
                            else if (isPlayingBack || (waveProvider != null && waveProvider.BufferedBytes > 0))
                            {
                                // Still playing back audio - wait for it to finish
                                continue;
                            }
                            else { break; }
                        }
                    }
                    // Send end audio frame
                    ReminderTransmitPcmAudio = null;
                    byte[] endAudio = { 0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e };
                    if (winRtOutputStream != null)
                    {
                        await winRtOutputStream.WriteAsync(endAudio, 0, endAudio.Length);
                        await winRtOutputStream.FlushAsync();
                    }
                }
                finally
                {
                    DispatchVoiceTransmitStateChanged(false);
                    Console.WriteLine("Voice transmission stopped.");
                    isTransmitting = false;
                }
            }, token);
        }

        private async Task ProcessPcmDataAsync(byte[] pcmData, CancellationToken token)
        {
            int pcmOffset = 0;
            int pcmLength = pcmData.Length;

            if (ReminderTransmitPcmAudio != null)
            {
                // If there are remaining bytes from the previous call, copy them to the beginning of the buffer
                byte[] pcmData2 = new byte[ReminderTransmitPcmAudio.Length + pcmLength];
                Buffer.BlockCopy(ReminderTransmitPcmAudio, 0, pcmData2, 0, ReminderTransmitPcmAudio.Length);
                Buffer.BlockCopy(pcmData, 0, pcmData2, ReminderTransmitPcmAudio.Length, pcmLength);
                pcmData = pcmData2;
                pcmLength = pcmData2.Length;
                ReminderTransmitPcmAudio = null;
            }

            // Real-time pacing: send audio at approximately the playback rate (32kHz, 16-bit, mono = 64KB/sec)
            const int bytesPerSecond = 32000 * 2; // 32kHz, 16-bit mono
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            int totalBytesSent = 0;

            while ((pcmLength >= pcmInputSizePerFrame) && (!token.IsCancellationRequested))
            {
                int bytesConsumed = 0;
                byte[] encodedSbcFrame;
                if (!EncodeSbcFrame(pcmData, pcmOffset, pcmLength, out encodedSbcFrame, out bytesConsumed)) { break; }

                // Send the audio frame to the radio
                byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);
                if (winRtOutputStream != null)
                {
                    await winRtOutputStream.WriteAsync(escaped, 0, escaped.Length);
                    await winRtOutputStream.FlushAsync();
                }

                // Do extra processing if needed
                if (recording != null)
                {
                    try { recording.Write(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("Recording Write error: " + ex.Message); }
                }
                if (PlayInputBack)
                {
                    try { PlayPcmBufferAsync(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("PlayPcmBufferAsync error: " + ex.Message); }
                }

                byte[] pcmDataForEvent = new byte[bytesConsumed];
                Buffer.BlockCopy(pcmData, pcmOffset, pcmDataForEvent, 0, bytesConsumed);
                try { DispatchAudioDataAvailable(pcmDataForEvent, 0, bytesConsumed, currentChannelName, true, false); } catch (Exception ex) { Debug("GotAudioData error: " + ex.Message); }

                pcmOffset += bytesConsumed;
                pcmLength -= bytesConsumed;
                totalBytesSent += bytesConsumed;

                // Real-time pacing: wait if we're sending faster than real-time playback
                int expectedElapsedMs = (int)((totalBytesSent * 1000L) / bytesPerSecond) - 1000; // Allow 1 second ahead
                int actualElapsedMs = (int)stopwatch.ElapsedMilliseconds;
                int waitMs = expectedElapsedMs - actualElapsedMs;
                if (waitMs > 0 && !token.IsCancellationRequested)
                {
                    await Task.Delay(Math.Min(waitMs, 100), token).ContinueWith(_ => { }); // Cap at 100ms per wait
                }
            }

            // If there are remaining bytes, keep them for the next call
            if (pcmLength != 0)
            {
                ReminderTransmitPcmAudio = new byte[pcmLength];
                Buffer.BlockCopy(pcmData, pcmOffset, ReminderTransmitPcmAudio, 0, pcmLength);
            }
        }

        public void PlayPcmBufferAsync(byte[] pcmInputData, int pcmOffset, int pcmLength)
        {
            var provider = waveProvider; // Capture local reference to avoid null issues
            if (provider == null) return;

            isPlayingBack = true; // Mark that we're actively streaming audio
            try
            {
                int bufferLength = provider.BufferLength;
                int currentOffset = pcmOffset;
                int remainingBytes = pcmLength;

                // Add all samples, waiting for buffer space as needed
                while (remainingBytes > 0 && !VoiceTransmitCancel)
                {
                    // Calculate how much we can add (limited by remaining data)
                    int bytesToAdd = Math.Min(remainingBytes, 1280); // ~20ms at 32kHz mono 16-bit

                    // Wait until there's space in the buffer for this chunk
                    while (provider.BufferedBytes + bytesToAdd > bufferLength && !VoiceTransmitCancel)
                    {
                        Thread.Sleep(10); // Short sleep to keep buffer topped up
                    }

                    if (VoiceTransmitCancel)
                    {
                        try { provider.ClearBuffer(); } catch { }
                        return;
                    }

                    try
                    {
                        provider.AddSamples(pcmInputData, currentOffset, bytesToAdd);
                        currentOffset += bytesToAdd;
                        remainingBytes -= bytesToAdd;
                    }
                    catch (InvalidOperationException)
                    {
                        // Buffer full - wait briefly and retry (don't advance offset)
                        Thread.Sleep(10);
                    }
                }

                if (VoiceTransmitCancel)
                {
                    try { provider.ClearBuffer(); } catch { }
                }
            }
            finally
            {
                isPlayingBack = false; // Done streaming this chunk
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
            Console.WriteLine($"  Blocks        : {blockValues[blocks]}");
            Console.WriteLine($"  Channel Mode       : {channelModes[channelMode]}");
            Console.WriteLine($"  Allocation Method  : {allocation}");
            Console.WriteLine($"  Subbands      : {subbands}");
            Console.WriteLine($"  Bitpool         : {bitpool}");
            Console.WriteLine($"  CRC    : 0x{crc:X2}");
        }
    }
}