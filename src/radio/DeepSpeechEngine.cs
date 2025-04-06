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
using System.Threading.Tasks;
using System.Collections.Concurrent;
using NAudio.Wave;
using DeepSpeechClient;
using DeepSpeechClient.Models;

namespace HTCommander.radio
{
    public class DeepSpeechEngine : SpeechToText
    {
        private AsyncDeepSpeechRecognizer deepSpeech;

        public event RadioAudio.OnVoiceTextReady onFinalResultReady;
        public event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

        public void StartVoiceSegment() {
            deepSpeech = new AsyncDeepSpeechRecognizer("deepspeech-0.9.3-models.pbmm", "deepspeech-0.9.3-models.scorer");
            deepSpeech.IntermediateResultReady += DeepSpeech_IntermediateResultReady;
            deepSpeech.FinalResultReady += DeepSpeech_FinalResultReady;
            deepSpeech.StartStreaming();
        }

        public void ResetVoiceSegment() {
            Task<string> _ = deepSpeech.FinishStreamingAsync();
            deepSpeech.StartStreaming();
        }

        public void ProcessAudioChunk(byte[] data, int index, int length) {
            deepSpeech.ProcessAudioChunk(data, index, length);
        }

        public void Dispose() { }
        private void DeepSpeech_FinalResultReady(string text)
        {
            if (onFinalResultReady != null) { onFinalResultReady(text); }
        }

        private void DeepSpeech_IntermediateResultReady(string text)
        {
            if (onIntermediateResultReady != null) { onIntermediateResultReady(text); }
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
                _model.SetModelBeamWidth(500); // Example: Adjust beam width if needed
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
                        int bytesRead;
                        byte[] buffer = new byte[length / 2];
                        while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            // Convert byte[] to short[] as DeepSpeech expects 16-bit samples
                            short[] shortBuffer = new short[bytesRead / 2];
                            Buffer.BlockCopy(buffer, 0, shortBuffer, 0, bytesRead);
                            _model.FeedAudioContent(_deepSpeechStream, shortBuffer, (uint)shortBuffer.Length);
                        }
                    }

                    DateTime now = DateTime.Now;
                    if (lastIntermediate.AddSeconds(1) < now)
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
                        //_model.FreeStream(_deepSpeechStream); // This causes a crash!!
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
}
