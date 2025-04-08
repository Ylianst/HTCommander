using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using System.Text; // Needed for StringBuilder
using NAudio.Wave; // Add NAudio.Core and NAudio.Wasapi/WinMM/Asio etc. NuGet packages
using Whisper.net;

namespace HTCommander.radio // Use your original namespace
{
    public class WhisperEngine : SpeechToText
    {
        private AsyncWhisperRecognizer _whisperRecognizer;
        private readonly string _modelPath; // Store model path
        private readonly WaveFormat _inputAudioFormat; // Define your expected input format
        private byte[] audioBuffer = null;
        private int audioBufferLength = 0;

        // Event for the final aggregated text when Finish/Reset is called
        public event RadioAudio.OnVoiceTextReady onFinalResultReady;
        // Event for each confirmed segment detected by Whisper
        public event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

        // "ggml-tiny.bin", "ggml-base.bin"
        // Constructor now takes the model path and expected input format
        public WhisperEngine(string modelPath = "ggml-base.bin", int inputSampleRate = 32000, int inputBits = 16, int inputChannels = 1)
        {
            // Basic validation
            if (string.IsNullOrWhiteSpace(modelPath))
                throw new ArgumentNullException(nameof(modelPath));
            if (!File.Exists(modelPath))
                throw new FileNotFoundException($"Whisper model file not found: {modelPath}", modelPath);


            _modelPath = modelPath;
            _inputAudioFormat = new WaveFormat(inputSampleRate, inputBits, inputChannels);
            Console.WriteLine($"WhisperEngine: Initialized with model '{_modelPath}' and expected input format: {_inputAudioFormat}");


            // Consider downloading model here if needed (your commented code is a good start)
            // await DownloadModelIfNotExistsAsync(); // Make constructor async if using this
        }

        /*
        public async Task DownloadModelIfNotExistsAsync()
        {
            // Your model download logic here...
            // Ensure robust error handling and stream disposal
        }
        */

        public void StartVoiceSegment()
        {
            Console.WriteLine("WhisperEngine: StartVoiceSegment called.");
            // Dispose previous recognizer if exists
            _whisperRecognizer?.Dispose();
            _whisperRecognizer = null; // Ensure it's cleared

            try
            {
                // Create and initialize the async recognizer
                // Pass the expected INPUT format to the recognizer
                _whisperRecognizer = new AsyncWhisperRecognizer(_modelPath, _inputAudioFormat);

                // Subscribe to events
                _whisperRecognizer.IntermediateResultReady += HandleIntermediateResult; // Hook up confirmed segments
                _whisperRecognizer.FinalResultReady += HandleFinalResult;             // Hook up final text on Reset/Finish
                _whisperRecognizer.ProcessingErrorOccurred += HandleProcessingError; // Optional: Handle errors

                _whisperRecognizer.StartStreaming(); // Send start command (initializes internal state)
                Console.WriteLine("WhisperEngine: AsyncWhisperRecognizer started and streaming command sent.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"WhisperEngine: CRITICAL - Failed to initialize AsyncWhisperRecognizer: {ex}");
                // Clean up if partially initialized
                _whisperRecognizer?.Dispose();
                _whisperRecognizer = null;
                // Rethrow or handle appropriately
                throw;
            }
        }

        // Reset finishes the current segment and starts a new one
        public void ResetVoiceSegment()
        {
            Console.WriteLine("WhisperEngine: Resetting voice segment...");
            // Finish the current stream (which triggers FinalResultReady)
            // and immediately start a new one internally.
            //_whisperRecognizer?.ResetStreaming();
        }

        public void ProcessAudioChunk(byte[] data, int index, int length, string channel)
        {
            if (_whisperRecognizer == null)
            {
                Console.WriteLine("WhisperEngine: Warning - ProcessAudioChunk called but recognizer is not initialized or has been disposed.");
                return;
            }
            if (length == 0) return; // Ignore empty chunks

            // Gather a bunch of data, 1 second worth
            if (audioBuffer == null) { audioBuffer = new byte[1280000]; audioBufferLength = 0; }
            Array.Copy(data, index, audioBuffer, audioBufferLength, length);
            audioBufferLength += length;

            if (audioBufferLength == audioBuffer.Length)
            {
                Console.WriteLine($"WhisperEngine: Queuing audio chunk - Length={audioBufferLength}, Channel='{channel}'"); // Debug Log
                _whisperRecognizer.ProcessAudioChunk(audioBuffer, channel); // Queue the copied chunk

                // Reset the buffer for the next chunk
                byte[] audioBuffer2 = new byte[1280000];
                Array.Copy(audioBuffer, 1280000 - 128000, audioBuffer2, 0, 128000);
                audioBuffer = audioBuffer2;
                audioBufferLength = 128000; // Reset for next chunk
            }
        }

        // --- Event Handlers (Forwarding events) ---
        private void HandleIntermediateResult(string text, string channel, DateTime timestamp)
        {
            //Console.WriteLine($"WhisperEngine: Forwarding Intermediate Result - Channel='{channel}', Time='{timestamp}', Text='{text}'"); // Debug Log
            //onIntermediateResultReady?.Invoke(text, channel, timestamp);
            onFinalResultReady?.Invoke("I: "+ text, channel, timestamp);
        }

        private void HandleFinalResult(string text, string channel, DateTime timestamp)
        {
            //Console.WriteLine($"WhisperEngine: Forwarding Final Result - Channel='{channel}', Time='{timestamp}', Text='{text}'"); // Debug Log
            onFinalResultReady?.Invoke("F: " + text, channel, timestamp);
        }

        private void HandleProcessingError(Exception ex)
        {
            //Console.WriteLine($"WhisperEngine: An error occurred in the async recognizer: {ex}");
            // Decide how to handle errors - maybe stop/reset, log, notify UI?
        }

        // --- IDisposable ---
        private bool _isDisposed = false;
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
                Console.WriteLine("WhisperEngine: Disposing...");
                _whisperRecognizer?.Dispose();
                _whisperRecognizer = null;
            }
            _isDisposed = true;
            Console.WriteLine("WhisperEngine: Disposed.");
        }

        ~WhisperEngine()
        {
            Dispose(false);
        }


        // --- Inner Classes for Async Handling and Whisper Interaction ---

        /// <summary>
        /// Wraps WhisperStreamingRecognizer to run operations on a background thread.
        /// Manages command queue, background task, and event marshalling.
        /// </summary>
        private class AsyncWhisperRecognizer : IDisposable
        {
            // --- Commands for the background thread ---
            private abstract class RecognizerCommand { }
            private class StartCommand : RecognizerCommand { }
            private class ProcessCommand : RecognizerCommand
            {
                public byte[] Data { get; }
                public string Channel { get; }
                public ProcessCommand(byte[] data, string channel) { Data = data; Channel = channel; }
            }
            private class ResetCommand : RecognizerCommand { } // Combines Finish and Start
            private class ShutdownCommand : RecognizerCommand { }

            // --- Member Variables ---
            private readonly BlockingCollection<RecognizerCommand> _commandQueue;
            private readonly Task _processingTask;
            private readonly CancellationTokenSource _cts;
            private readonly SynchronizationContext _capturedContext;
            private WhisperStreamingRecognizer _recognizerInstance; // Accessed only by the background thread
            private readonly string _modelPath;
            private readonly WaveFormat _inputAudioFormat; // Pass input format down
            private volatile bool _isDisposed = false;

            // Store last known results for the timer
            private string _lastChannel = string.Empty;
            private DateTime _lastTimestamp = DateTime.MinValue;
            private string _lastSegmentText = string.Empty; // Last confirmed segment
            private readonly object _timerLock = new object(); // Lock for accessing timer-related state

            // --- Events (Raised on the captured SynchronizationContext) ---
            public event Action<string, string, DateTime> IntermediateResultReady; // Confirmed Whisper segment
            public event Action<string, string, DateTime> FinalResultReady;         // Final text on Finish/Reset
            public event Action<string, string, DateTime> SecondTickUpdateReady;    // Fires every second
            public event Action<Exception> ProcessingErrorOccurred;

            public AsyncWhisperRecognizer(string modelPath, WaveFormat inputAudioFormat)
            {
                _modelPath = modelPath;
                _inputAudioFormat = inputAudioFormat; // Store input format
                _commandQueue = new BlockingCollection<RecognizerCommand>();
                _cts = new CancellationTokenSource();
                _capturedContext = SynchronizationContext.Current ?? new SynchronizationContext(); // Ensure we have a context

                Console.WriteLine("AsyncWhisperRecognizer: Starting background processing task...");
                _processingTask = Task.Run(() => ProcessingLoop(_modelPath, _inputAudioFormat, _cts.Token));
            }

            // --- Public Methods (Called from WhisperEngine) ---
            public void StartStreaming() => TryAddCommand(new StartCommand());
            public void ResetStreaming() => TryAddCommand(new ResetCommand());
            public void ProcessAudioChunk(byte[] audioData, string channel)
            {
                if (audioData == null || audioData.Length == 0) return;
                TryAddCommand(new ProcessCommand(audioData, channel));
            }

            // --- Command Queue Handling ---
            private void TryAddCommand(RecognizerCommand command)
            {
                CheckDisposed();
                try
                {
                    if (!_commandQueue.IsAddingCompleted)
                    {
                        _commandQueue.Add(command, _cts.Token);
                    }
                    else
                    {
                        Console.WriteLine($"AsyncWhisperRecognizer: Warning - Tried to add command {command.GetType().Name} after queue completion (during dispose?).");
                    }
                }
                catch (OperationCanceledException) { /* Expected during shutdown */ CheckDisposed(); }
                catch (InvalidOperationException) { /* Expected if queue is completed */ CheckDisposed(); }
                catch (Exception ex)
                {
                    Console.WriteLine($"AsyncWhisperRecognizer: Error adding command {command.GetType().Name}: {ex}");
                    RaiseProcessingError(ex);
                }
            }

            // --- Background Processing Loop ---
            private void ProcessingLoop(string modelPath, WaveFormat inputFormat, CancellationToken token)
            {
                Console.WriteLine("AsyncWhisperRecognizer: Background thread started.");
                try
                {
                    // Initialize Whisper on the background thread
                    _recognizerInstance = new WhisperStreamingRecognizer(modelPath, inputFormat); // Pass input format
                    Console.WriteLine("AsyncWhisperRecognizer: WhisperStreamingRecognizer initialized.");

                    // Hook up internal events from WhisperStreamingRecognizer to marshalling handlers
                    _recognizerInstance.SegmentReceived += OnInnerSegmentReceived; // Whisper confirmed segment
                    _recognizerInstance.SegmentFinished += OnInnerSegmentFinished; // Our final text aggregation

                    while (!token.IsCancellationRequested)
                    {
                        RecognizerCommand command = null;
                        try
                        {
                            command = _commandQueue.Take(token); // Blocks until command or cancellation
                        }
                        catch (OperationCanceledException) { break; } // Exit loop on cancellation
                        catch (InvalidOperationException) { break; } // Exit loop if queue marked complete

                        try // Catch errors during command processing
                        {
                            switch (command)
                            {
                                case StartCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Start command.");
                                    // Reset timer state along with recognizer state
                                    lock (_timerLock)
                                    {
                                        _lastChannel = string.Empty;
                                        _lastTimestamp = DateTime.MinValue;
                                        _lastSegmentText = string.Empty;
                                    }
                                    _recognizerInstance.StartStreaming();
                                    break;

                                case ProcessCommand pc:
                                    // Console.WriteLine($"AsyncWhisperRecognizer: Processing audio chunk - Length={pc.Data.Length}, Channel='{pc.Channel}'"); // Debug Log
                                    if (_lastChannel == string.Empty)
                                    {
                                        _lastChannel = pc.Channel;
                                        _lastTimestamp = DateTime.Now;
                                    }
                                    _recognizerInstance.ProcessAudioChunk(pc.Data, 0, pc.Data.Length, pc.Channel);
                                    break;

                                case ResetCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Reset command.");
                                    _recognizerInstance.FinishStreaming(); // Triggers OnInnerSegmentFinished -> FinalResultReady
                                                                           // Reset timer state
                                    lock (_timerLock)
                                    {
                                        _lastChannel = string.Empty;
                                        _lastTimestamp = DateTime.MinValue;
                                        _lastSegmentText = string.Empty;
                                    }
                                    _recognizerInstance.StartStreaming();  // Start new internal segment state
                                    break;

                                case ShutdownCommand _:
                                    Console.WriteLine("AsyncWhisperRecognizer: Received Shutdown command.");
                                    goto Shutdown; // Exit the loop cleanly

                                default:
                                    Console.WriteLine($"Warning: Unknown command type: {command?.GetType().Name}");
                                    break;
                            }
                        }
                        catch (ObjectDisposedException)
                        {
                            Console.WriteLine($"AsyncWhisperRecognizer: Attempted operation on disposed object during command {command?.GetType().Name}. Likely shutting down.");
                            break; // Exit loop if recognizer disposed unexpectedly
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"AsyncWhisperRecognizer: Error processing command {command?.GetType().Name}: {ex}");
                            RaiseProcessingError(ex);
                            // Consider if error is fatal for the recognizer state
                        }
                    }
                }
                catch (Exception ex) // Catch initialization errors (e.g., model load failed)
                {
                    Console.WriteLine($"AsyncWhisperRecognizer: Fatal error during initialization or processing loop: {ex}");
                    RaiseProcessingError(ex); // Report initialization error
                }

            Shutdown:
                Console.WriteLine("AsyncWhisperRecognizer: Shutting down processing loop...");

                // Cleanup Whisper resources on this thread
                if (_recognizerInstance != null)
                {
                    Console.WriteLine("AsyncWhisperRecognizer: Disposing WhisperStreamingRecognizer instance...");
                    _recognizerInstance.SegmentReceived -= OnInnerSegmentReceived;
                    _recognizerInstance.SegmentFinished -= OnInnerSegmentFinished;
                    try { _recognizerInstance.Dispose(); }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"AsyncWhisperRecognizer: Error disposing inner recognizer: {ex}");
                        RaiseProcessingError(ex);
                    }
                    _recognizerInstance = null;
                    Console.WriteLine("AsyncWhisperRecognizer: WhisperStreamingRecognizer instance disposed.");
                }

                // Dispose command queue (safe to do after loop exit)
                try { _commandQueue.Dispose(); } catch { /* Ignore */ }

                Console.WriteLine("AsyncWhisperRecognizer: Background thread finished.");
            }

            // --- Event Marshalling ---

            // Called by _recognizerInstance when Whisper detects a segment
            private void OnInnerSegmentReceived(string segmentText, string channel, DateTime startTime)
            {
                // Update state used by the timer
                lock (_timerLock)
                {
                    // Append new segment to the *last known text* for the timer.
                    // Note: This could drift slightly from the final aggregated text if resets happen,
                    // but it provides *some* ongoing text for the timer event.
                    _lastSegmentText += segmentText + " ";
                    _lastChannel = channel;
                    _lastTimestamp = startTime; // Or maybe DateTime.Now? Decide what timestamp means for this event
                                                //Console.WriteLine($"AsyncWhisperRecognizer: OnInnerSegmentReceived - Updated timer state. Text='{_lastSegmentText}'"); // Debug Log
                }

                // Raise the specific event for confirmed segments
                Console.WriteLine($"AsyncWhisperRecognizer: Raising IntermediateResultReady event. Text='{segmentText}'"); // Debug Log
                RaiseEvent(IntermediateResultReady, segmentText, channel, startTime);
            }

            // Called by _recognizerInstance.FinishStreaming()
            private void OnInnerSegmentFinished(string fullText, string channel, DateTime startTime)
            {
                Console.WriteLine($"AsyncWhisperRecognizer: Raising FinalResultReady event. Text='{fullText}'"); // Debug Log
                RaiseEvent(FinalResultReady, fullText, channel, startTime);
            }

            private void RaiseProcessingError(Exception ex)
            {
                RaiseEvent(ProcessingErrorOccurred, ex);
            }

            // Helper to raise events, marshalling to captured context
            private void RaiseEvent<TArg1, TArg2, TArg3>(Action<TArg1, TArg2, TArg3> eventHandler, TArg1 arg1, TArg2 arg2, TArg3 arg3)
            {
                var handler = eventHandler; // Local copy for thread safety
                if (handler == null) return;

                _capturedContext.Post(state =>
                {
                    var args = (Tuple<TArg1, TArg2, TArg3>)state;
                    try { handler(args.Item1, args.Item2, args.Item3); }
                    catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in marshalled event handler for {handler.Method.Name}: {ex}"); }
                }, Tuple.Create(arg1, arg2, arg3));
            }
            // Overload for single arg events (like Exception)
            private void RaiseEvent<T>(Action<T> eventHandler, T arg)
            {
                var handler = eventHandler; // Local copy
                if (handler == null) return;

                _capturedContext.Post(state =>
                {
                    try { handler((T)state); }
                    catch (Exception ex) { Console.WriteLine($"AsyncWhisperRecognizer: Exception in marshalled event handler for {handler.Method.Name}: {ex}"); }
                }, arg);
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
                _isDisposed = true; // Mark disposed early to prevent race conditions adding commands

                if (disposing)
                {
                    Console.WriteLine("AsyncWhisperRecognizer: Dispose called.");
                    // Signal shutdown and wait for task completion
                    if (!_cts.IsCancellationRequested)
                    {
                        Console.WriteLine("AsyncWhisperRecognizer: Requesting shutdown of background task...");
                        // Try adding Shutdown command, but don't worry if queue is already completing
                        try { _commandQueue.Add(new ShutdownCommand()); } catch { /* Ignore */ }
                        _commandQueue.CompleteAdding(); // IMPORTANT: Prevent more commands being added
                        _cts.Cancel(); // Signal cancellation token
                    }

                    // Wait for the background task to complete (with timeout)
                    try
                    {
                        Console.WriteLine("AsyncWhisperRecognizer: Waiting for background task to finish...");
                        if (!_processingTask.Wait(TimeSpan.FromSeconds(10))) // Generous timeout
                        {
                            Console.WriteLine("Warning: Background processing task did not complete within timeout during Dispose.");
                        }
                        else
                        {
                            Console.WriteLine("AsyncWhisperRecognizer: Background task completed.");
                        }
                    }
                    // Ignore exceptions related to task cancellation/completion during shutdown
                    catch (OperationCanceledException) { Console.WriteLine("AsyncWhisperRecognizer: Background task cancelled as expected."); }
                    catch (AggregateException ae) //when (ae.InnerExceptions.Any(e => e is TaskCanceledException || e is OperationCanceledException))
                    { Console.WriteLine("AsyncWhisperRecognizer: Background task cancelled as expected (AggregateException)."); }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"AsyncWhisperRecognizer: Exception waiting for background task during Dispose: {ex}");
                    }

                    _cts.Dispose();
                    // Queue is disposed in the background thread's finally block
                    Console.WriteLine("AsyncWhisperRecognizer: Dispose completed.");
                }
                else // Finalizer path
                {
                    Console.WriteLine("AsyncWhisperRecognizer: Finalizer called. Resources might not be fully released if task is running.");
                    // Best effort: Signal cancellation if not already done.
                    // Cannot reliably wait for the task here.
                    try { _cts?.Cancel(); } catch { }
                    try { _commandQueue?.CompleteAdding(); } catch { }
                }

            }

            ~AsyncWhisperRecognizer()
            {
                Dispose(false);
            }
        }


        /// <summary>
        /// Handles the direct interaction with Whisper.net: initialization,
        /// audio resampling/conversion, processing, and event raising.
        /// Runs on the background thread managed by AsyncWhisperRecognizer.
        /// </summary>
        private class WhisperStreamingRecognizer : IDisposable
        {
            private WhisperProcessor _processor; // The core Whisper processor
            private readonly WaveFormat _sourceAudioFormat; // Expected format of input BYTES
            private readonly WaveFormat _targetAudioFormat; // Required format for Whisper (16kHz, 1ch, 16bit)
            private static readonly int TargetSampleRate = 16000;
            private static readonly int TargetChannels = 1;
            private static readonly int TargetBitDepth = 16; // For the resampling target format

            private DateTime _segmentStartTime = DateTime.MinValue;
            private string _currentChannel = string.Empty;
            private StringBuilder _accumulatedText = new StringBuilder(); // Accumulates text for the SegmentFinished event
            private bool _isDisposed = false;

            // Event fired *internally* when Whisper provides a segment
            public event Action<string, string, DateTime> SegmentReceived;
            // Event fired *internally* when FinishStreaming is called
            public event Action<string, string, DateTime> SegmentFinished;

            // Constructor takes model path and the EXPECTED INPUT format
            public WhisperStreamingRecognizer(string modelPath, WaveFormat inputAudioFormat)
            {
                _sourceAudioFormat = inputAudioFormat ?? throw new ArgumentNullException(nameof(inputAudioFormat));
                _targetAudioFormat = new WaveFormat(TargetSampleRate, TargetBitDepth, TargetChannels);

                Console.WriteLine($"WhisperStreamingRecognizer: Initializing... Source Format: {_sourceAudioFormat}, Target Format: {_targetAudioFormat}");

                try
                {
                    // --- Factory and Processor Initialization ---
                    Console.WriteLine($"WhisperStreamingRecognizer: Loading model from '{modelPath}'...");
                    var factory = WhisperFactory.FromPath(modelPath);
                    if (factory == null) throw new InvalidOperationException("WhisperFactory.FromPath returned null.");

                    Console.WriteLine("WhisperStreamingRecognizer: Creating processor builder...");
                    var builder = factory.CreateBuilder();
                    if (builder == null) throw new InvalidOperationException("WhisperFactory.CreateBuilder returned null.");

                    // --- Configure the processor ---
                    builder = builder
                        .WithLanguage("en") // Or use WithLanguageDetection() / provide language code
                                            //.WithLanguageDetection()
                        .WithThreads(Math.Max(1, Environment.ProcessorCount / 2)); // Example thread count
                                                                                   // Add other options like WithTranslate(true), etc. if needed

                    // **CRITICAL: Hook the event handler HERE**
                    builder = builder.WithSegmentEventHandler(OnWhisperInternalSegmentReceived);
                    //builder = builder.WithProgressHandler(OnWhisperProgress);
                    //builder = builder.WithProgressEventHandler(OnWhisperProgress); // Check Whisper.net docs if a progress handler exists for faster updates

                    Console.WriteLine("WhisperStreamingRecognizer: Building processor...");
                    _processor = builder.Build();
                    if (_processor == null) throw new InvalidOperationException("WhisperProcessorBuilder.Build returned null.");

                    Console.WriteLine("WhisperStreamingRecognizer: Whisper processor created successfully.");
                }
                catch (Exception ex)
                {
                    // Log the full exception, including inner exceptions if present
                    Console.WriteLine($"WhisperStreamingRecognizer: FATAL - Failed to initialize Whisper. Model: '{modelPath}'. Error: {ex}");
                    // Rethrow to signal failure to AsyncWhisperRecognizer's constructor
                    throw new InvalidOperationException($"Failed to initialize Whisper processor from '{modelPath}'", ex);
                }
            }

            /// <summary>Resets internal state for a new stream.</summary>
            public void StartStreaming()
            {
                CheckDisposed();
                Console.WriteLine("WhisperStreamingRecognizer: Starting new stream segment.");
                _segmentStartTime = DateTime.MinValue;
                _currentChannel = string.Empty;
                _accumulatedText.Clear();
                // Processor itself handles stream continuity; we reset our tracking state.
            }

            /// <summary>Processes a chunk: resamples, converts, feeds to Whisper.</summary>
            public void ProcessAudioChunk(byte[] audioData, int index, int length, string channel)
            {
                CheckDisposed();
                if (_processor == null) throw new ObjectDisposedException("WhisperProcessor is not available.");
                if (length == 0) return;

                if (_segmentStartTime == DateTime.MinValue)
                {
                    _segmentStartTime = DateTime.Now; // Record time of first chunk for this segment
                    _currentChannel = channel;
                    Console.WriteLine($"WhisperStreamingRecognizer: First audio chunk received for channel '{channel}' at {_segmentStartTime}. Length={length}");
                }
                //else { Console.WriteLine($"WhisperStreamingRecognizer: Processing chunk. Length={length}"); } // Debug


                try
                {
                    // 1. Resample if necessary
                    byte[] pcm16kBytes;
                    if (_sourceAudioFormat.SampleRate == _targetAudioFormat.SampleRate &&
                        _sourceAudioFormat.BitsPerSample == _targetAudioFormat.BitsPerSample &&
                        _sourceAudioFormat.Channels == _targetAudioFormat.Channels)
                    {
                        // No resampling needed, just copy the relevant part
                        Console.WriteLine("WhisperStreamingRecognizer: Audio format matches target, skipping resampling."); // Debug
                        pcm16kBytes = new byte[length];
                        Buffer.BlockCopy(audioData, index, pcm16kBytes, 0, length);
                    }
                    else
                    {
                        Console.WriteLine("WhisperStreamingRecognizer: Resampling audio chunk..."); // Debug
                        pcm16kBytes = ResampleAudioChunk(audioData, index, length);
                        if (pcm16kBytes == null || pcm16kBytes.Length == 0)
                        {
                            Console.WriteLine("WhisperStreamingRecognizer: Resampling resulted in empty buffer, skipping chunk.");
                            return;
                        }
                        Console.WriteLine($"WhisperStreamingRecognizer: Resampled chunk size: {pcm16kBytes.Length}"); // Debug
                    }


                    // 2. Convert 16-bit PCM bytes to float[] (-1.0 to 1.0)
                    float[] floatBuffer = ConvertPcm16ToFloat32(pcm16kBytes);
                    Console.WriteLine($"WhisperStreamingRecognizer: Converted to float buffer, samples: {floatBuffer.Length}"); // Debug

                    // 3. Feed to Whisper Processor
                    _processor.Process(floatBuffer); // Use ReadOnlySpan<float> if available: floatBuffer.AsSpan()
                    // Results arrive via the OnWhisperInternalSegmentReceived handler attached in the constructor
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"WhisperStreamingRecognizer: Error processing audio chunk: {ex}");
                    // Consider raising an error event or deciding if the stream is corrupted
                }
            }

            /// <summary>Internal handler called directly by Whisper.net processor.</summary>
            private void OnWhisperInternalSegmentReceived(SegmentData segment)
            {
                // This method is called BY WHISPER on its own thread.
                // Do minimal work here. Marshalling happens in AsyncWhisperRecognizer.
                //Console.WriteLine($"WhisperStreamingRecognizer: == Segment Received == Start={segment.Start}, End={segment.End}, Text='{segment.Text}'"); // Essential Log
                Console.WriteLine("D: " + segment.Text);

                // Append text for the final result
                _accumulatedText.Append(segment.Text).Append(" ");

                // Raise our *internal* event. AsyncWhisperRecognizer listens to this.
                SegmentReceived?.Invoke(segment.Text, _currentChannel, _segmentStartTime);
            }

            /*
            // Example placeholder if Whisper.net adds a progress handler
            private void OnWhisperProgress(int progressPercent)
            {
                //Console.WriteLine($"Whisper Progress: {progressPercent}%");
                // If this exists and gives partial text, raise a different event here.
            }
            */

            /// <summary>Signals the end, triggers the final aggregated text event.</summary>
            public void FinishStreaming()
            {
                CheckDisposed();
                Console.WriteLine("WhisperStreamingRecognizer: Finishing stream segment...");

                // Whisper streaming processes as data comes in. The segments have already
                // been received via OnWhisperInternalSegmentReceived. We just need to
                // signal that the current logical segment is done and provide the combined text.

                string finalText = _accumulatedText.ToString().Trim();
                Console.WriteLine($"WhisperStreamingRecognizer: Final accumulated text for segment: '{finalText}' (Channel: '{_currentChannel}')");

                // Raise the *internal* finished event. AsyncWhisperRecognizer listens to this.
                SegmentFinished?.Invoke(finalText, _currentChannel, _segmentStartTime);

                // State (_accumulatedText etc.) is reset by the *next* call to StartStreaming()
            }

            // --- Helper Methods ---

            private byte[] ResampleAudioChunk(byte[] inputBytes, int inputIndex, int inputLength)
            {
                using (var sourceStream = new RawSourceWaveStream(inputBytes, inputIndex, inputLength, _sourceAudioFormat))
                // Use MediaFoundationResampler (requires Windows Media Foundation)
                using (var resampler = new MediaFoundationResampler(sourceStream, _targetAudioFormat))
                // Alternative: WaveFormatConversionStream (more basic, cross-platform)
                // using (var resampler = new WaveFormatConversionStream(_targetAudioFormat, sourceStream))
                {
                    // Estimate output size reasonably
                    int estimatedOutputLength = (int)((double)inputLength * _targetAudioFormat.SampleRate / _sourceAudioFormat.SampleRate * _targetAudioFormat.Channels / _sourceAudioFormat.Channels * _targetAudioFormat.BitsPerSample / _sourceAudioFormat.BitsPerSample);
                    estimatedOutputLength = Math.Max(estimatedOutputLength, _targetAudioFormat.BlockAlign * 16); // Ensure some minimum


                    using (var ms = new MemoryStream(estimatedOutputLength))
                    {
                        // Buffer size can impact performance, 4k-8k is often reasonable
                        byte[] buffer = new byte[resampler.WaveFormat.AverageBytesPerSecond / 10]; // ~100ms buffer
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
                    Console.WriteLine("WhisperStreamingRecognizer: Warning - PCM16 byte array length is odd. Ignoring last byte.");
                    // Or throw new ArgumentException("PCM16 byte array length must be even.");
                }

                int sampleCount = pcm16Bytes.Length / 2;
                float[] floatBuffer = new float[sampleCount];
                int outIndex = 0;

                for (int i = 0; i < pcm16Bytes.Length - 1; i += 2) // Ensure we don't read past bounds
                {
                    // Assuming little-endian architecture
                    short sample = BitConverter.ToInt16(pcm16Bytes, i);
                    // Normalize to range [-1.0, 1.0]
                    floatBuffer[outIndex++] = (float)sample / 32768.0f;
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
                    Console.WriteLine("WhisperStreamingRecognizer: Disposing...");
                    if (_processor != null)
                    {
                        Console.WriteLine("WhisperStreamingRecognizer: Disposing Whisper processor...");
                        try { _processor.Dispose(); }
                        catch (Exception ex) { Console.WriteLine($"WhisperStreamingRecognizer: Error disposing processor: {ex.Message}"); }
                        _processor = null;
                        Console.WriteLine("WhisperStreamingRecognizer: Whisper processor disposed.");
                    }
                }
                _isDisposed = true;
                Console.WriteLine("WhisperStreamingRecognizer: Disposed.");
            }

            ~WhisperStreamingRecognizer()
            {
                Dispose(false);
            }
        }
    }
}