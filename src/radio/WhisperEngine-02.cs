/*
Adaptation for Whisper.net based on original DeepSpeech code structure.
Requires Whisper.net, Whisper.net.Runtime, and NAudio NuGet packages.
Ensure a Whisper GGML model file (e.g., ggml-base.en.bin) is available.
*/

using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using System.Text; // Needed for StringBuilder
using NAudio.Wave;
using Whisper.net;
using Whisper.net.Ggml; // Or your chosen GgmlType

namespace HTCommander.radio // Use your original namespace
{
    public class WhisperEngine : SpeechToText
    {
        private AsyncWhisperRecognizer whisperRecognizer;
        private readonly string _modelPath; // Store model path

        public event RadioAudio.OnVoiceTextReady onFinalResultReady;
        public event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

        // Constructor now takes the model path
        public WhisperEngine()
        {
            _modelPath = "ggml-base.bin";
            //DownloadModelIfNotExistsAsync();
        }

        /*
        public async Task DownloadModelIfNotExistsAsync()
        {
            if (!File.Exists(_modelPath))
            {
                var modelStreamTask = WhisperGgmlDownloader.Default.GetGgmlModelAsync(GgmlType.Base);
                using (var fileWriter = File.OpenWrite(_modelPath))
                using (var modelStream = await modelStreamTask)
                {
                    if (modelStream != null)
                    {
                        byte[] buffer = new byte[8192]; // You can adjust the buffer size
                        int bytesRead;
                        while ((bytesRead = await modelStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                        {
                            await fileWriter.WriteAsync(buffer, 0, bytesRead);
                        }
                    }
                }
            }
        }
        */

        public void StartVoiceSegment()
        {
            // Dispose previous recognizer if exists
            whisperRecognizer?.Dispose();

            // Create and initialize the async recognizer
            whisperRecognizer = new AsyncWhisperRecognizer(_modelPath);
            whisperRecognizer.IntermediateResultReady += Whisper_IntermediateResultReady;
            whisperRecognizer.FinalResultReady += Whisper_FinalResultReady;
            whisperRecognizer.StartStreaming(); // Send start command
            Console.WriteLine("WhisperEngine: Voice segment started.");
        }

        // Reset essentially finishes the current segment and starts a new one
        public void ResetVoiceSegment()
        {
            Console.WriteLine("WhisperEngine: Resetting voice segment...");
            // Finish the current stream (which triggers FinalResultReady)
            // and immediately start a new one.
            whisperRecognizer?.ResetStreaming();
        }

        public void ProcessAudioChunk(byte[] data, int index, int length, string channel)
        {
            // Ensure data is copied before queuing, as original buffer might be reused
            byte[] chunkCopy = new byte[length];
            Buffer.BlockCopy(data, index, chunkCopy, 0, length);
            whisperRecognizer?.ProcessAudioChunk(chunkCopy, channel); // Queue the copied chunk
        }

        public void Dispose()
        {
            Console.WriteLine("WhisperEngine: Disposing...");
            whisperRecognizer?.Dispose();
            whisperRecognizer = null;
        }

        private void Whisper_FinalResultReady(string text, string channel, DateTime t)
        {
            Console.WriteLine($"WhisperEngine: Final Result Ready for channel '{channel}' at {t}: {text}");
            onFinalResultReady?.Invoke(text, channel, t);
        }

        private void Whisper_IntermediateResultReady(string text, string channel, DateTime t)
        {
            // Note: For Whisper, this is typically a confirmed segment
            Console.WriteLine($"WhisperEngine: Intermediate Result (Segment) Ready for channel '{channel}' at {t}: {text}");
            onIntermediateResultReady?.Invoke(text, channel, t);
        }

        // --- Inner Classes for Async Handling and Whisper Interaction ---

        /// <summary>
        /// Wraps WhisperStreamingRecognizer to run operations on a background thread.
        /// </summary>
        private class AsyncWhisperRecognizer : IDisposable
        {
            private enum CommandType { Start, Process, Reset, Shutdown }

            private abstract class RecognizerCommand { }
            private class StartCommand : RecognizerCommand { }
            private class ProcessCommand : RecognizerCommand
            {
                public byte[] Data { get; }
                public string Channel { get; }
                public ProcessCommand(byte[] data, string channel) { Data = data; Channel = channel; }
            }
            // Reset combines Finish and Start for simplicity in this model
            private class ResetCommand : RecognizerCommand { }
            private class ShutdownCommand : RecognizerCommand { }

            private readonly BlockingCollection<RecognizerCommand> _commandQueue;
            private readonly Task _processingTask;
            private readonly CancellationTokenSource _cts;
            private readonly SynchronizationContext _capturedContext;
            private bool _isDisposed = false;
            private WhisperStreamingRecognizer _recognizerInstance; // Only accessed by the background thread
            private readonly string _modelPath;

            // Events marshalled back to the captured context
            public event Action<string, string, DateTime> IntermediateResultReady;
            public event Action<string, string, DateTime> FinalResultReady;
            public event Action<Exception> ProcessingErrorOccurred; // Optional: For error reporting

            public AsyncWhisperRecognizer(string modelPath)
            {
                _modelPath = modelPath; // Store path for the background thread
                _commandQueue = new BlockingCollection<RecognizerCommand>();
                _cts = new CancellationTokenSource();
                _capturedContext = SynchronizationContext.Current;

                _processingTask = Task.Run(() => ProcessingLoop(_modelPath, _cts.Token));
            }

            public void StartStreaming()
            {
                CheckDisposed();
                TryAddCommand(new StartCommand());
            }

            // ProcessAudioChunk now only takes data and channel, as index/length were handled by copying
            public void ProcessAudioChunk(byte[] audioData, string channel)
            {
                CheckDisposed();
                if (audioData == null || audioData.Length == 0) return;
                // Data is already a copy from WhisperEngine
                TryAddCommand(new ProcessCommand(audioData, channel));
            }

            // Renamed from FinishStreamingAsync as it now resets state too
            public void ResetStreaming()
            {
                CheckDisposed();
                TryAddCommand(new ResetCommand());
                // We don't return a Task here, FinalResultReady event handles the result
            }


            private void TryAddCommand(RecognizerCommand command)
            {
                try
                {
                    _commandQueue.Add(command, _cts.Token);
                }
                catch (OperationCanceledException) { CheckDisposed(); } // Throw if disposed
                catch (InvalidOperationException) { CheckDisposed(); } // Throw if disposed (queue completed)
                catch (Exception ex) // Catch other potential Add errors
                {
                    Console.WriteLine($"AsyncWhisperRecognizer: Error adding command {command.GetType().Name}: {ex.Message}");
                    RaiseProcessingError(ex);
                }
            }


            private void ProcessingLoop(string modelPath, CancellationToken token)
            {
                try
                {
                    // Initialize Whisper on the background thread
                    _recognizerInstance = new WhisperStreamingRecognizer(modelPath);

                    // Hook up internal events to marshalling handlers
                    _recognizerInstance.SegmentReceived += OnInnerSegmentReceived; // Use Whisper's event name
                    _recognizerInstance.SegmentFinished += OnInnerSegmentFinished; // Custom event for final result

                    Console.WriteLine("AsyncWhisperRecognizer: Background thread started, Whisper model loaded.");

                    while (!token.IsCancellationRequested)
                    {
                        RecognizerCommand command = null;
                        try
                        {
                            command = _commandQueue.Take(token);
                        }
                        catch (OperationCanceledException) { break; }
                        catch (InvalidOperationException) { break; } // Queue completed

                        try // Catch errors during command processing
                        {
                            switch (command)
                            {
                                case StartCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Start command.");
                                    _recognizerInstance.StartStreaming();
                                    break;

                                case ProcessCommand pc:
                                    _recognizerInstance.ProcessAudioChunk(pc.Data, 0, pc.Data.Length, pc.Channel);
                                    break;

                                case ResetCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Reset command.");
                                    // Finish triggers the final event, Start resets state
                                    _recognizerInstance.FinishStreaming();
                                    _recognizerInstance.StartStreaming();
                                    break;

                                case ShutdownCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Shutdown command.");
                                    goto Shutdown;

                                default:
                                    Console.WriteLine($"Warning: Unknown command type: {command?.GetType().Name}");
                                    break;
                            }
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"AsyncWhisperRecognizer: Error processing command {command?.GetType().Name}: {ex.ToString()}");
                            RaiseProcessingError(ex);
                            // If Reset failed, we might be in an inconsistent state
                            if (command is ResetCommand)
                            {
                                // Maybe try to force a cleanup or just report error
                                Console.WriteLine("AsyncWhisperRecognizer: CRITICAL - Reset command failed.");
                            }
                        }
                    }
                }
                catch (Exception ex) // Catch initialization errors
                {
                    Console.WriteLine($"AsyncWhisperRecognizer: Fatal error during initialization or loop: {ex.ToString()}");
                    RaiseProcessingError(ex);
                }

            Shutdown:
                Console.WriteLine("AsyncWhisperRecognizer: Shutting down processing loop.");

                // Cleanup resources on this thread
                if (_recognizerInstance != null)
                {
                    _recognizerInstance.SegmentReceived -= OnInnerSegmentReceived;
                    _recognizerInstance.SegmentFinished -= OnInnerSegmentFinished;
                    try { _recognizerInstance.Dispose(); }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"AsyncWhisperRecognizer: Error disposing inner recognizer: {ex.Message}");
                        RaiseProcessingError(ex);
                    }
                    _recognizerInstance = null;
                }
                // Dispose queue only after loop exit
                try { _commandQueue.Dispose(); } catch { }
                Console.WriteLine("AsyncWhisperRecognizer: Background thread finished.");
            }

            // --- Event Marshalling ---

            // Renamed for clarity - this handles Whisper segments
            private void OnInnerSegmentReceived(string segmentText, string channel, DateTime startTime)
            {
                RaiseEvent(IntermediateResultReady, segmentText, channel, startTime);
            }

            // This handles the custom event for the accumulated final text
            private void OnInnerSegmentFinished(string fullText, string channel, DateTime startTime)
            {
                RaiseEvent(FinalResultReady, fullText, channel, startTime);
            }


            private void RaiseProcessingError(Exception ex)
            {
                RaiseEvent(ProcessingErrorOccurred, ex); // Marshall error event
            }

            // Helper to raise events, marshalling if context exists
            private void RaiseEvent<TArg1, TArg2, TArg3>(Action<TArg1, TArg2, TArg3> eventHandler, TArg1 arg1, TArg2 arg2, TArg3 arg3)
            {
                if (eventHandler == null) return;

                if (_capturedContext != null)
                {
                    _capturedContext.Post(state =>
                    {
                        var args = (Tuple<TArg1, TArg2, TArg3>)state;
                        try { eventHandler(args.Item1, args.Item2, args.Item3); }
                        catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in marshalled event handler for {eventHandler.Method.Name}: {ex.Message}"); }
                    }, Tuple.Create(arg1, arg2, arg3));
                }
                else
                {
                    try { eventHandler(arg1, arg2, arg3); }
                    catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in direct event handler for {eventHandler.Method.Name}: {ex.Message}"); }
                }
            }
            private void RaiseEvent<T>(Action<T> eventHandler, T args) // Overload for single arg events like Error
            {
                if (eventHandler == null) return;

                if (_capturedContext != null)
                {
                    _capturedContext.Post(state =>
                    {
                        try { eventHandler((T)state); }
                        catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in marshalled event handler for {eventHandler.Method.Name}: {ex.Message}"); }
                    }, args);
                }
                else
                {
                    try { eventHandler(args); }
                    catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in direct event handler for {eventHandler.Method.Name}: {ex.Message}"); }
                }
            }

            // --- IDisposable Implementation ---
            private void CheckDisposed()
            {
                if (_isDisposed) throw new ObjectDisposedException(nameof(AsyncWhisperRecognizer));
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
                    Console.WriteLine("AsyncWhisperRecognizer: Dispose called.");
                    if (!_cts.IsCancellationRequested)
                    {
                        // Try to gracefully shutdown the background thread
                        TryAddCommand(new ShutdownCommand()); // Signal shutdown
                        _commandQueue.CompleteAdding(); // Stop adding new items
                        _cts.Cancel(); // Signal cancellation token
                    }

                    // Wait for the background task to complete
                    try
                    {
                        if (!_processingTask.Wait(TimeSpan.FromSeconds(5))) // Wait with timeout
                        {
                            Console.WriteLine("Warning: Background processing task did not complete within timeout during Dispose.");
                        }
                        else
                        {
                            Console.WriteLine("AsyncWhisperRecognizer: Background task completed during Dispose.");
                        }
                    }
                    // Ignore AggregateException containing OCE on Wait
                    catch (AggregateException ex)
                    {
                        Console.WriteLine("AsyncWhisperRecognizer: Background task cancelled as expected during Dispose.");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"AsyncWhisperRecognizer: Exception waiting for background task during Dispose: {ex.Message}");
                    }

                    _cts.Dispose();
                    // Queue should be disposed in the loop's finally block
                }

                _isDisposed = true; // Mark as disposed regardless of 'disposing' flag
                Console.WriteLine("AsyncWhisperRecognizer: Dispose finished.");
            }

            ~AsyncWhisperRecognizer()
            {
                Dispose(false);
            }
        }


        /// <summary>
        /// Handles the actual interaction with Whisper.net for streaming recognition.
        /// </summary>
        private class WhisperStreamingRecognizer : IDisposable
        {
            private readonly WhisperProcessor _processor;
            private readonly WaveFormat _sourceFormat; // e.g., 32kHz, 16-bit, Mono
            private readonly WaveFormat _targetFormat; // 16kHz, 16-bit, Mono (for resampling)
            private static readonly int TargetSampleRate = 16000; // Whisper standard
            private static readonly int TargetBitDepth = 16;
            private static readonly int TargetChannels = 1;

            private DateTime _segmentStartTime = DateTime.MinValue;
            private string _currentChannel = string.Empty;
            private StringBuilder _accumulatedText = new StringBuilder(); // Accumulate text for final result
            private bool _isDisposed = false;


            // Event fired when Whisper detects a segment
            public event Action<string, string, DateTime> SegmentReceived;
            // Custom event fired by FinishStreaming to signal the complete text
            public event Action<string, string, DateTime> SegmentFinished;


            public WhisperStreamingRecognizer(string modelPath)
            {
                // --- Model Loading ---
                // Ensure you have the Whisper.net.Runtime package or a specific backend (CPU/GPU).
                // Select GGML type based on your model (Base, Small, Medium, etc.)
                // This often corresponds to the filename e.g., ggml-base.en.bin -> GgmlType.Base
                // You might need to adjust this based on the exact model file used.
                // Let's try to infer, or default to Base if unsure.
                var modelType = GgmlType.Base; // Default
                var modelFileName = Path.GetFileNameWithoutExtension(modelPath).ToLowerInvariant();

                if (modelFileName.Contains("tiny")) modelType = GgmlType.Tiny;
                else if (modelFileName.Contains("base")) modelType = GgmlType.Base;
                else if (modelFileName.Contains("small")) modelType = GgmlType.Small;
                else if (modelFileName.Contains("medium")) modelType = GgmlType.Medium;
                //else if (modelFileName.Contains("large")) modelType = GgmlType.Large;
                // Add more checks if needed for specific model versions (v1, v2, v3)

                Console.WriteLine($"WhisperStreamingRecognizer: Loading model '{modelPath}' identified as type {modelType}...");

                try
                {
                    // --- Factory and Processor Initialization ---
                    // Use FromPath and WhisperProcessorBuilder for configuration
                    var factory = WhisperFactory.FromPath(modelPath); // Add libraryPath if needed

                    // Configure the processor (example options)
                    _processor = factory.CreateBuilder()
                        .WithLanguage("en") // Specify language, or use WithLanguageDetection()
                                            //.WithLanguageDetection() // Or use auto-detection
                         .WithThreads(Math.Max(1, Environment.ProcessorCount / 2)) // Example thread count
                         // Add other options as needed (e.g., WithTranslate(), WithSegmentEventHandler(), etc.)
                         .WithSegmentEventHandler(OnWhisperSegmentReceived) // Hook event handler here
                         .Build();

                    Console.WriteLine("WhisperStreamingRecognizer: Whisper processor created successfully.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"WhisperStreamingRecognizer: FATAL - Failed to initialize Whisper model from {modelPath}. Error: {ex.ToString()}");
                    // Rethrow to stop the background thread initialization
                    throw new InvalidOperationException($"Failed to initialize Whisper model from {modelPath}", ex);
                }

                // --- Audio Format Definitions ---
                _sourceFormat = new WaveFormat(rate: 32000, bits: 16, channels: 1); // As per original code
                _targetFormat = new WaveFormat(TargetSampleRate, TargetBitDepth, TargetChannels); // Whisper standard

                Console.WriteLine($"WhisperStreamingRecognizer Initialized. Source Format: {_sourceFormat}, Target Format: {_targetFormat}");
            }

            /// <summary>
            /// Resets state for a new voice segment.
            /// </summary>
            public void StartStreaming()
            {
                CheckDisposed();
                Console.WriteLine("WhisperStreamingRecognizer: Starting new stream segment.");
                _segmentStartTime = DateTime.MinValue; // Reset start time
                _currentChannel = string.Empty;
                _accumulatedText.Clear(); // Clear previous text
                                          // The processor itself doesn't need resetting, just our state
            }

            /// <summary>
            /// Processes a chunk of audio data (resamples, converts, feeds to Whisper).
            /// </summary>
            public void ProcessAudioChunk(byte[] audioData, int index, int length, string channel)
            {
                CheckDisposed();
                if (audioData == null || length == 0) return;

                if (_segmentStartTime == DateTime.MinValue)
                {
                    _segmentStartTime = DateTime.Now;
                    _currentChannel = channel;
                    Console.WriteLine($"WhisperStreamingRecognizer: First audio chunk received for channel '{channel}' at {_segmentStartTime}.");
                }

                try
                {
                    // 1. Resample using NAudio
                    byte[] resampledBytes = ResampleAudioChunk(audioData, index, length);
                    if (resampledBytes == null || resampledBytes.Length == 0)
                    {
                        Console.WriteLine("WhisperStreamingRecognizer: Resampling resulted in empty buffer, skipping chunk.");
                        return;
                    }

                    // 2. Convert 16-bit PCM bytes to float[] (-1.0 to 1.0)
                    float[] floatBuffer = ConvertPcm16ToFloat32(resampledBytes);

                    // 3. Feed to Whisper Processor
                    // Use ReadOnlySpan for efficiency if possible with your Whisper.net version
                    _processor.Process(floatBuffer.AsSpan());
                    // Results will arrive asynchronously via the OnWhisperSegmentReceived handler
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"WhisperStreamingRecognizer: Error processing audio chunk: {ex.ToString()}");
                    // Consider how to handle errors - skip chunk? Stop processing? Raise error event?
                    // For now, just log it.
                }
            }

            /// <summary>
            /// Called by Whisper.net when a segment is detected and transcribed.
            /// This acts as our "intermediate" result.
            /// </summary>
            private void OnWhisperSegmentReceived(SegmentData segment)
            {
                // This handler is called by the Whisper.net library's internal thread(s).
                // Marshalling back to the correct context happens in AsyncWhisperRecognizer.
                Console.WriteLine($"WhisperStreamingRecognizer: Segment Received: Start={segment.Start}, End={segment.End}, Text='{segment.Text}'");
                _accumulatedText.Append(segment.Text).Append(" "); // Append segment text

                // Raise our internal event - AsyncWhisperRecognizer will marshal it
                SegmentReceived?.Invoke(segment.Text, _currentChannel, _segmentStartTime);
            }

            /// <summary>
            /// Signals the end of the current voice segment and triggers the final result event.
            /// </summary>
            public void FinishStreaming()
            {
                CheckDisposed();
                Console.WriteLine("WhisperStreamingRecognizer: Finishing stream segment.");

                // Whisper's streaming processes data as it comes in. There's no explicit
                // 'flush' needed here like DeepSpeech. The results are already captured
                // in _accumulatedText via OnWhisperSegmentReceived.

                string finalText = _accumulatedText.ToString().Trim();
                Console.WriteLine($"WhisperStreamingRecognizer: Final accumulated text for segment: '{finalText}'");

                // Raise the custom 'finished' event with the full text
                SegmentFinished?.Invoke(finalText, _currentChannel, _segmentStartTime);

                // State is reset by the *next* call to StartStreaming()
            }


            // --- Helper Methods ---

            private byte[] ResampleAudioChunk(byte[] inputBytes, int inputIndex, int inputLength)
            {
                using (var sourceStream = new RawSourceWaveStream(inputBytes, inputIndex, inputLength, _sourceFormat))
                using (var resampler = new MediaFoundationResampler(sourceStream, _targetFormat)) // Or WaveFormatConversionStream
                {
                    // Estimate output buffer size (may be slightly off, but better than fixed small buffer)
                    // Ratio of sample rates * input length
                    int estimatedOutputLength = (int)((double)inputLength * _targetFormat.SampleRate / _sourceFormat.SampleRate);
                    // Ensure minimum size and account for block alignment if needed
                    estimatedOutputLength = Math.Max(estimatedOutputLength, _targetFormat.BlockAlign * 10); // Example adjustment

                    using (var ms = new MemoryStream(estimatedOutputLength))
                    {
                        byte[] buffer = new byte[resampler.WaveFormat.AverageBytesPerSecond]; // Read up to 1s chunks
                        int bytesRead;
                        while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            ms.Write(buffer, 0, bytesRead);
                        }
                        return ms.ToArray();
                    }
                }
            }

            private float[] ConvertPcm16ToFloat32(byte[] pcm16Bytes)
            {
                if (pcm16Bytes.Length % 2 != 0)
                {
                    Console.WriteLine("Warning: PCM16 byte array length is not even. Truncating last byte.");
                    // Consider logging or throwing if this shouldn't happen
                }

                int sampleCount = pcm16Bytes.Length / 2;
                float[] floatBuffer = new float[sampleCount];

                for (int i = 0; i < sampleCount; i++)
                {
                    short sample = BitConverter.ToInt16(pcm16Bytes, i * 2);
                    floatBuffer[i] = (float)sample / 32768.0f; // Normalize to -1.0 to 1.0
                                                               // Clamp values just in case, although ToInt16 should handle range
                                                               // floatBuffer[i] = Math.Max(-1.0f, Math.Min(1.0f, floatBuffer[i]));
                }
                return floatBuffer;
            }


            // --- IDisposable ---

            private void CheckDisposed()
            {
                if (_isDisposed) throw new ObjectDisposedException(nameof(WhisperStreamingRecognizer));
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
                    Console.WriteLine("WhisperStreamingRecognizer: Disposing Whisper processor...");
                    try
                    {
                        _processor?.Dispose(); // Dispose the Whisper processor
                        Console.WriteLine("WhisperStreamingRecognizer: Whisper processor disposed.");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"WhisperStreamingRecognizer: Error disposing processor: {ex.Message}");
                    }
                }
                // No significant unmanaged resources directly held here other than _processor
                _isDisposed = true;
            }

            ~WhisperStreamingRecognizer()
            {
                Dispose(false);
            }
        }
    }
}