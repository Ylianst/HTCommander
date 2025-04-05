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
using DeepSpeechClient;
using DeepSpeechClient.Models;
using System.Collections.Concurrent;
using System.Threading.Tasks;

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
        private AsyncDeepSpeechRecognizer deepSpeech;
        public int speechToText = 2;
        
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
            if (speechToText == 1)
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
                recognizerAudioStream = new SpeechStreamer(10000);

                // RecognizeAsync runs in the background. RecognizeCompleted will fire when done.
                // RecognizeMode.Single stops after the first recognized phrase.
                // Use RecognizeMode.Multiple for continuous recognition until StopAsync is called.
                recognizer.SetInputToAudioStream(recognizerAudioStream, formatInfo);
                recognizer.RecognizeAsync(RecognizeMode.Multiple);
            }
            if (speechToText == 2)
            {
                deepSpeech = new AsyncDeepSpeechRecognizer("deepspeech-0.9.3-models.pbmm", "deepspeech-0.9.3-models.scorer");
                //deepSpeech = new AsyncDeepSpeechRecognizer("deepspeech-0.9.3-models.pbmm", null);
                deepSpeech.IntermediateResultReady += DeepSpeech_IntermediateResultReady;
                deepSpeech.FinalResultReady += DeepSpeech_FinalResultReady;
                deepSpeech.StartStreaming();
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
                                        if (recognizerAudioStream != null) {
                                            recognizerAudioStream.Close();
                                            recognizer.RecognizeAsyncStop();
                                            recognizer.Dispose();

                                            Debug("Recognize Break");

                                            // Setup voice-to-text engine
                                            recognizer = new SpeechRecognitionEngine();
                                            recognizer.SpeechRecognized += Recognizer_SpeechRecognized;
                                            recognizer.RecognizeCompleted += Recognizer_RecognizeCompleted;
                                            recognizer.SpeechRecognitionRejected += Recognizer_SpeechRecognitionRejected; // Optional but good
                                            recognizer.LoadGrammar(new DictationGrammar()); // DictationGrammar is simplest for free-form text.

                                            // Define the audio format for the recognizer
                                            SpeechAudioFormatInfo formatInfo = new SpeechAudioFormatInfo(32000, AudioBitsPerSample.Sixteen, AudioChannel.Mono);

                                            // Use our custom pipe stream
                                            recognizerAudioStream = new SpeechStreamer(10000);

                                            // RecognizeAsync runs in the background. RecognizeCompleted will fire when done.
                                            // RecognizeMode.Single stops after the first recognized phrase.
                                            // Use RecognizeMode.Multiple for continuous recognition until StopAsync is called.
                                            recognizer.SetInputToAudioStream(recognizerAudioStream, formatInfo);
                                            recognizer.RecognizeAsync(RecognizeMode.Multiple);
                                        }
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
                if (recognizerAudioStream != null) { recognizerAudioStream.Close(); }
                if (recognizer != null) { recognizer.Dispose(); }
                if (deepSpeech != null) {  deepSpeech.Dispose(); deepSpeech = null; }
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

        private void DeepSpeech_FinalResultReady(string obj)
        {
            Debug("Final: " + obj);
        }

        private void DeepSpeech_IntermediateResultReady(string obj)
        {
            Debug("Intermediate: " + obj);
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
                if (deepSpeech != null) { deepSpeech.ProcessAudioChunk(pcmFrame, 0, (int)written); }
            }

            pcmHandle.Free();
            sbcHandle.Free();
            return 0;
        }
    }

    public class DeepSpeechStreamingRecognizer : IDisposable
    {
        private readonly DeepSpeech _model;
        private readonly WaveFormat _sourceFormat; // Format of the incoming audio (32kHz)
        private readonly WaveFormat _targetFormat; // Format required by DeepSpeech (16kHz)
        private DeepSpeechStream _deepSpeechStream; // Use StreamingState which is the type returned by CreateStream
        private DateTime lastIntermediate;

        // Event to notify subscribers of intermediate results
        public event Action<string> IntermediateResultReady;
        // Event to notify subscribers of the final result for a segment
        public event Action<string> FinalResultReady;

        /// <summary>
        /// Initializes the DeepSpeech streaming recognizer.
        /// </summary>
        /// <param name="modelPath">Path to the DeepSpeech model file (.pbmm).</param>
        /// <param name="scorerPath">Optional path to the language model scorer file (.scorer).</param>
        public DeepSpeechStreamingRecognizer(string modelPath, string scorerPath = null)
        {
            // https://deepspeech.readthedocs.io/en/latest/USING.html
            // https://github.com/mozilla/DeepSpeech/releases/download/v0.9.3/deepspeech-0.9.3-models.pbmm
            // https://github.com/mozilla/DeepSpeech/releases/download/v0.9.3/deepspeech-0.9.3-models.scorer

            if (string.IsNullOrEmpty(modelPath) || !File.Exists(modelPath))
            {
                throw new FileNotFoundException($"DeepSpeech model not found or path is invalid: {modelPath}");
            }

            try
            {
                _model = new DeepSpeech(modelPath);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to initialize DeepSpeech model from {modelPath}. Error: {ex.Message}", ex);
            }

            if (!string.IsNullOrEmpty(scorerPath))
            {
                if (!File.Exists(scorerPath))
                {
                    Console.WriteLine($"Warning: Scorer file not found at: {scorerPath}. Recognition accuracy may be reduced.");
                }
                else
                {
                    try
                    {
                        _model.EnableExternalScorer(scorerPath);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Warning: Failed to enable scorer '{scorerPath}'. Error: {ex.Message}. Proceeding without scorer.");
                    }
                }
            }

            // Set desired model parameters (optional)
            // _model.SetModelBeamWidth(500); // Example: Adjust beam width if needed
            //_model.SetModelBeamWidth(100); // Example: Adjust beam width if needed
            //int sampleRate = _model.GetModelSampleRate();
            //uint beamWidth = _model.GetModelBeamWidth();

            // Define the source audio format (32kHz, 16-bit, Mono PCM)
            _sourceFormat = new WaveFormat(rate: 32000, bits: 16, channels: 1);
            // Define the target audio format required by DeepSpeech (16kHz, 16-bit, Mono PCM)
            _targetFormat = new WaveFormat(rate: 16000, bits: 16, channels: 1); // Standard DeepSpeech requirement

            Console.WriteLine($"DeepSpeech Recognizer initialized. Source Format: {_sourceFormat}, Target Format: {_targetFormat}");
        }

        /// <summary>
        /// Starts a new recognition stream. Must be called before processing audio chunks.
        /// </summary>
        public void StartStreaming()
        {
            if (_deepSpeechStream != null)
            {
                Console.WriteLine("Warning: Streaming already in progress. Call FinishStreaming() before starting a new stream.");
                FinishStreaming(); // Clean up the previous stream
            }
            try
            {
                // Create the stream state directly from the model
                lastIntermediate = DateTime.Now;
                _deepSpeechStream = _model.CreateStream();
                Console.WriteLine("DeepSpeech stream started.");
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to create DeepSpeech stream. Error: {ex.Message}", ex);
            }
        }

        /// <summary>
        /// Processes a chunk of audio data. Resamples and feeds it to the DeepSpeech stream.
        /// </summary>
        /// <param name="audioData">Byte array containing PCM audio data (32kHz, 16-bit, Mono).</param>
        public void ProcessAudioChunk(byte[] audioData, int index, int length)
        {
            if (_deepSpeechStream == null)
            {
                Console.WriteLine("Error: Streaming not started. Call StartStreaming() first.");
                return;
            }
            if (audioData == null || audioData.Length == 0)
            {
                Console.WriteLine("Warning: Received empty audio chunk.");
                return;
            }

            try
            {
                using (var sourceStream = new RawSourceWaveStream(audioData, index, length, _sourceFormat))
                using (var resampler = new MediaFoundationResampler(sourceStream, _targetFormat))
                {
                    int targetBytesPerSecond = _targetFormat.AverageBytesPerSecond;
                    byte[] buffer = new byte[targetBytesPerSecond / 10]; // ~100ms buffer
                    int bytesRead;

                    while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        // Convert byte[] to short[] as DeepSpeech expects 16-bit samples
                        short[] shortBuffer = new short[bytesRead / 2];
                        Buffer.BlockCopy(buffer, 0, shortBuffer, 0, bytesRead);
                        _model.FeedAudioContent(_deepSpeechStream, shortBuffer, (uint)shortBuffer.Length);
                    }
                }

                DateTime now = DateTime.Now;
                if (lastIntermediate.AddSeconds(10) < now)
                {
                    lastIntermediate = now;
                    string intermediateResult = _model.IntermediateDecode(_deepSpeechStream);
                    if (!string.IsNullOrWhiteSpace(intermediateResult))
                    {
                        IntermediateResultReady?.Invoke(intermediateResult);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error processing audio chunk: {ex.Message}");
                // Handle error
            }
        }


        /// <summary>
        /// Finishes the current recognition stream and returns the final transcription.
        /// </summary>
        /// <returns>The final recognized text, or null if streaming was not active.</returns>
        public string FinishStreaming()
        {
            if (_deepSpeechStream == null)
            {
                Console.WriteLine("Warning: FinishStreaming called but streaming was not active.");
                return null;
            }

            string finalResult = null;
            try
            {
                Console.WriteLine("Finishing DeepSpeech stream...");
                finalResult = _model.FinishStream(_deepSpeechStream);
                FinalResultReady?.Invoke(finalResult);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error finishing stream: {ex.Message}");
            }
            finally
            {
                try
                {
                    // Example: Assuming a FreeStream method exists on the model
                    _model.FreeStream(_deepSpeechStream);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error freeing stream resource: {ex.Message}");
                    // This might happen if called twice, etc.
                }

                // The Dispose method on your handle object might just null the pointer,
                // so calling it might still be okay or necessary.
                _deepSpeechStream?.Dispose();
                _deepSpeechStream = null;
                Console.WriteLine("DeepSpeech stream finished and resources potentially freed.");
            }
            return finalResult;
        }

        /// <summary>
        /// Releases resources used by the DeepSpeech model and any active stream.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (disposing)
            {
                // Dispose managed resources
                if (_deepSpeechStream != null)
                {
                    try
                    {
                        _model.FreeStream(_deepSpeechStream);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Error freeing stream resource during dispose: {ex.Message}");
                    }
                    _deepSpeechStream.Dispose(); // Dispose the handle object
                    _deepSpeechStream = null;
                }
                _model?.Dispose(); // Dispose the main DeepSpeech model object
                Console.WriteLine("DeepSpeech Recognizer disposed.");
            }
            // Dispose unmanaged resources here if any
        }

        // Destructor (finalize) - safety net for unmanaged resources if Dispose isn't called
        ~DeepSpeechStreamingRecognizer()
        {
            Dispose(false);
        }
    }

    /// <summary>
    /// Wraps DeepSpeechStreamingRecognizer to run all its operations on a dedicated
    /// background thread, allowing the calling thread (e.g., UI thread) to remain responsive.
    /// Audio chunks are queued for processing.
    /// </summary>
    public class AsyncDeepSpeechRecognizer : IDisposable
    {
        private enum CommandType { Start, Process, Finish, Shutdown }

        private abstract class RecognizerCommand { }
        private class StartCommand : RecognizerCommand { }
        private class ProcessCommand : RecognizerCommand
        {
            public byte[] Data { get; }
            public ProcessCommand(byte[] data) { Data = data; } // Data is already a copy
        }
        private class FinishCommand : RecognizerCommand
        {
            public TaskCompletionSource<string> Tcs { get; }
            public FinishCommand(TaskCompletionSource<string> tcs) { Tcs = tcs; }
        }
        private class ShutdownCommand : RecognizerCommand { }


        private readonly BlockingCollection<RecognizerCommand> _commandQueue;
        private readonly Task _processingTask;
        private readonly CancellationTokenSource _cts;
        private readonly SynchronizationContext _capturedContext;
        private bool _isDisposed = false;
        private DeepSpeechStreamingRecognizer _recognizerInstance; // Only accessed by the background thread

        // Events that will be marshalled back to the captured context (if any)
        public event Action<string> IntermediateResultReady;
        public event Action<string> FinalResultReady;
        public event Action<Exception> ProcessingErrorOccurred;

        /// <summary>
        /// Initializes the async DeepSpeech recognizer. This starts a background thread
        /// where the actual DeepSpeech model will be loaded and processing will occur.
        /// </summary>
        /// <param name="modelPath">Path to the DeepSpeech model file (.pbmm).</param>
        /// <param name="scorerPath">Optional path to the language model scorer file (.scorer).</param>
        public AsyncDeepSpeechRecognizer(string modelPath, string scorerPath = null)
        {
            _commandQueue = new BlockingCollection<RecognizerCommand>();
            _cts = new CancellationTokenSource();
            _capturedContext = SynchronizationContext.Current; // Capture context for event marshalling

            // Start the background processing task
            _processingTask = Task.Run(() => ProcessingLoop(modelPath, scorerPath, _cts.Token));
        }

        /// <summary>
        /// Signals the background thread to start a new recognition stream.
        /// This call returns quickly.
        /// </summary>
        public void StartStreaming()
        {
            CheckDisposed();
            try
            {
                _commandQueue.Add(new StartCommand(), _cts.Token);
            }
            catch (OperationCanceledException)
            {
                // Ignore if cancellation was requested during Add
                CheckDisposed(); // Throw if already disposed
            }
            catch (InvalidOperationException) // Thrown if CompleteAdding called before Add
            {
                CheckDisposed(); // Throw if already disposed
            }
        }

        /// <summary>
        /// Queues an audio chunk for processing on the background thread.
        /// This method copies the relevant portion of the buffer and returns immediately.
        /// </summary>
        /// <param name="audioData">Byte array containing PCM audio data.</param>
        /// <param name="index">Start index in the buffer.</param>
        /// <param name="length">Number of bytes to process from the buffer.</param>
        public void ProcessAudioChunk(byte[] audioData, int index, int length)
        {
            CheckDisposed();
            if (audioData == null || length == 0) return;

            // IMPORTANT: Create a copy of the audio chunk to queue.
            // The original buffer might be reused by the caller before the background thread processes it.
            byte[] chunkCopy = new byte[length];
            Buffer.BlockCopy(audioData, index, chunkCopy, 0, length);

            try
            {
                _commandQueue.Add(new ProcessCommand(chunkCopy), _cts.Token);
            }
            catch (OperationCanceledException)
            {
                CheckDisposed();
            }
            catch (InvalidOperationException)
            {
                CheckDisposed();
            }
        }

        /// <summary>
        /// Signals the background thread to finish the current recognition stream
        /// and returns a Task that completes with the final transcription result.
        /// </summary>
        /// <returns>A Task representing the asynchronous operation, yielding the final string result.</returns>
        public Task<string> FinishStreamingAsync()
        {
            CheckDisposed();
            var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            try
            {
                _commandQueue.Add(new FinishCommand(tcs), _cts.Token);
            }
            catch (Exception ex) when (ex is OperationCanceledException || ex is InvalidOperationException)
            {
                CheckDisposed(); // Throw if disposed
                tcs.TrySetException(new ObjectDisposedException(nameof(AsyncDeepSpeechRecognizer), "Cannot finish streaming as the recognizer is disposed or shutting down."));
            }
            return tcs.Task;
        }


        /// <summary>
        /// The main loop running on the background thread.
        /// </summary>
        private void ProcessingLoop(string modelPath, string scorerPath, CancellationToken token)
        {
            try
            {
                // 1. Initialize the actual recognizer on this thread
                _recognizerInstance = new DeepSpeechStreamingRecognizer(modelPath, scorerPath);

                // Hook up internal events to marshalling handlers
                _recognizerInstance.IntermediateResultReady += OnInnerIntermediateResultReady;
                _recognizerInstance.FinalResultReady += OnInnerFinalResultReady;

                Console.WriteLine("AsyncDeepSpeechRecognizer: Background thread started and inner recognizer initialized.");

                // 2. Process commands from the queue
                while (!token.IsCancellationRequested)
                {
                    RecognizerCommand command = null;
                    try
                    {
                        // Block until a command is available or cancellation is requested
                        command = _commandQueue.Take(token);
                    }
                    catch (OperationCanceledException)
                    {
                        break; // Exit loop if cancellation requested while waiting
                    }
                    catch (InvalidOperationException)
                    {
                        // Queue was marked as completed. Should only happen during shutdown.
                        break;
                    }

                    try // Catch errors during command processing
                    {
                        switch (command)
                        {
                            case StartCommand _:
                                Console.WriteLine("AsyncDeepSpeechRecognizer: Received Start command.");
                                _recognizerInstance.StartStreaming();
                                break;

                            case ProcessCommand pc:
                                // Process the copied audio data
                                _recognizerInstance.ProcessAudioChunk(pc.Data, 0, pc.Data.Length);
                                break;

                            case FinishCommand fc:
                                Console.WriteLine("AsyncDeepSpeechRecognizer: Received Finish command.");
                                string result = _recognizerInstance.FinishStreaming();
                                fc.Tcs.TrySetResult(result); // Signal completion back to the caller
                                break;

                            case ShutdownCommand _:
                                Console.WriteLine("AsyncDeepSpeechRecognizer: Received Shutdown command.");
                                goto Shutdown; // Exit the loop cleanly

                            default:
                                Console.WriteLine($"Warning: Unknown command type received: {command?.GetType().Name}");
                                break;
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"AsyncDeepSpeechRecognizer: Error processing command {command?.GetType().Name}: {ex.Message}");
                        RaiseProcessingError(ex);
                        // Handle specific command errors if needed (e.g., set exception on FinishCommand's TCS)
                        if (command is FinishCommand fcErr)
                        {
                            fcErr.Tcs.TrySetException(ex);
                        }
                    }
                }
            }
            catch (Exception ex) // Catch initialization errors
            {
                Console.WriteLine($"AsyncDeepSpeechRecognizer: Fatal error during initialization or loop: {ex.ToString()}");
                RaiseProcessingError(ex);
                // If initialization fails, subsequent calls will likely fail or throw ObjectDisposedException
                // We should ensure cleanup happens.
            }

        Shutdown:
            Console.WriteLine("AsyncDeepSpeechRecognizer: Shutting down processing loop.");

            // 3. Cleanup resources on this thread
            if (_recognizerInstance != null)
            {
                // Unhook events
                _recognizerInstance.IntermediateResultReady -= OnInnerIntermediateResultReady;
                _recognizerInstance.FinalResultReady -= OnInnerFinalResultReady;

                // Ensure any pending stream is finished before disposing (optional, depends on desired behavior)
                // try { _recognizerInstance.FinishStreaming(); } catch { /* Ignore errors during final finish */ }

                try
                {
                    _recognizerInstance.Dispose();
                    Console.WriteLine("AsyncDeepSpeechRecognizer: Inner recognizer disposed.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"AsyncDeepSpeechRecognizer: Error disposing inner recognizer: {ex.Message}");
                    RaiseProcessingError(ex);
                }
                _recognizerInstance = null;
            }
            _commandQueue.Dispose(); // Dispose the queue
            Console.WriteLine("AsyncDeepSpeechRecognizer: Background thread finished.");
        }

        // --- Event Marshalling ---

        private void OnInnerIntermediateResultReady(string result)
        {
            RaiseEvent(IntermediateResultReady, result);
        }

        private void OnInnerFinalResultReady(string result)
        {
            RaiseEvent(FinalResultReady, result);
        }

        private void RaiseProcessingError(Exception ex)
        {
            RaiseEvent(ProcessingErrorOccurred, ex);
        }

        // Helper to raise events, marshalling if context exists
        private void RaiseEvent<T>(Action<T> eventHandler, T args)
        {
            if (eventHandler == null) return;

            if (_capturedContext != null)
            {
                _capturedContext.Post(state => eventHandler((T)state), args);
            }
            else
            {
                // No context captured (e.g., console app) or marshalling not needed.
                // Invoke directly. Subscriber must handle thread safety if needed.
                try
                {
                    eventHandler(args);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"AsyncDeepSpeechRecognizer: Exception in event handler for {eventHandler.Method.Name}: {ex.Message}");
                    // Consider logging this, but don't let handler exceptions stop the background thread.
                }
            }
        }


        // --- IDisposable Implementation ---

        private void CheckDisposed()
        {
            if (_isDisposed)
            {
                throw new ObjectDisposedException(nameof(AsyncDeepSpeechRecognizer));
            }
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (_isDisposed) return;

            if (disposing)
            {
                Console.WriteLine("AsyncDeepSpeechRecognizer: Dispose called.");
                // Signal the background thread to shut down
                if (!_cts.IsCancellationRequested)
                {
                    // Mark queue as complete for adding *new* items (doesn't affect Take)
                    _commandQueue.CompleteAdding();
                    // Add a specific shutdown command to ensure Take() unblocks if empty
                    // Do this *after* CompleteAdding to avoid races. Add ignores CompleteAdding if queue empty.
                    // Check if already cancelled to avoid adding unnecessarily
                    if (!_cts.IsCancellationRequested)
                    {
                        try
                        {
                            // Use Add with a timeout or token if needed, but Shutdown should be prioritised
                            _commandQueue.Add(new ShutdownCommand());
                        }
                        catch { } // Ignore if queue is already disposed or add fails
                    }

                    _cts.Cancel(); // Signal cancellation
                }

                // Wait for the background task to complete execution and cleanup
                try
                {
                    // Wait reasonable time. Avoid waiting forever if thread is stuck.
                    if (!_processingTask.Wait(TimeSpan.FromSeconds(5)))
                    {
                        Console.WriteLine("Warning: Background processing task did not complete within the timeout during Dispose.");
                        // Log this situation. The thread might be leaked if it's truly stuck.
                    }
                    else
                    {
                        Console.WriteLine("AsyncDeepSpeechRecognizer: Background task completed.");
                    }
                }
                catch (AggregateException ae)
                {
                    // Observe exceptions, especially OperationCanceledException which is expected
                    ae.Handle(ex => ex is OperationCanceledException);
                    Console.WriteLine("AsyncDeepSpeechRecognizer: Background task cancelled as expected during Dispose.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"AsyncDeepSpeechRecognizer: Exception while waiting for background task during Dispose: {ex.Message}");
                }

                _cts.Dispose();
                // _commandQueue is disposed within the ProcessingLoop after it exits.

                Console.WriteLine("AsyncDeepSpeechRecognizer: Dispose finished.");
            }

            _isDisposed = true;
        }

        // Optional: Finalizer as a safety net (though background thread makes it less critical for managed resources)
        ~AsyncDeepSpeechRecognizer()
        {
            Dispose(false);
        }
    }

}
