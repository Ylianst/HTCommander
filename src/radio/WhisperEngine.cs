/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Speech.Synthesis;
using System.Speech.AudioFormat;
using System.Collections.Generic;
using NAudio.Wave;
using Whisper.net;

namespace HTCommander.radio // Use your original namespace
{
    public class VoiceEngine
    {
        private MemoryStream audioStream = new MemoryStream();
        private SpeechSynthesizer synthesizer = null;
        private bool Processing = false;
        private RadioAudio radioAudio;
        private bool ttsAvailable = false;

        public VoiceEngine(RadioAudio radioAudio)
        {
            this.radioAudio = radioAudio;

            // Initialize the synthesizer with error handling
            try
            {
                synthesizer = new SpeechSynthesizer();
                synthesizer.SetOutputToAudioStream(audioStream, new SpeechAudioFormatInfo(32000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
                string selectedVoice = DataBroker.GetValue<string>(0, "Voice", "Microsoft Zira Desktop");
                try { synthesizer.SelectVoice(selectedVoice); } catch (Exception) { } // Use voice from settings, default to Zira
                synthesizer.Rate = 0; // Set the rate to 0 for normal speed
                synthesizer.Volume = 100; // Set volume to maximum
                synthesizer.SpeakCompleted += Synthesizer_SpeakCompleted;
                ttsAvailable = true;
            }
            catch (System.Runtime.InteropServices.COMException ex)
            {
                // Log the error but don't crash the application
                Console.WriteLine("Warning: Text-to-Speech is not available on this system.");
                Console.WriteLine($"Error: {ex.Message}");
                Console.WriteLine("To enable TTS, please install the Windows Speech Platform Runtime:");
                Console.WriteLine("  1. Download Microsoft Speech Platform Runtime 11.0");
                Console.WriteLine("  2. Install a language pack (e.g., MSSpeech_TTS_en-US_ZiraPro)");
                Console.WriteLine("  3. Or run: regsvr32 %windir%\\system32\\speech\\common\\sapi.dll");
                ttsAvailable = false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Warning: Failed to initialize Text-to-Speech: {ex.Message}");
                ttsAvailable = false;
            }
        }

        public bool IsTtsAvailable()
        {
            return ttsAvailable;
        }

        public bool SetVoice(string voiceName)
        {
            if (!ttsAvailable || synthesizer == null) return false;
            try { synthesizer.SelectVoice(voiceName); } catch (Exception) { return false; }
            return true;
        }

        public bool Speak(string text, string voice)
        {
            if (!ttsAvailable || synthesizer == null) return false; // TTS not available
            if (Processing) return false; // Already processing another speech
            Processing = true;
            try { synthesizer.SelectVoice(voice); } catch (Exception) { return false; }
            synthesizer.SpeakAsync(text);
            return true;
        }

        private void Synthesizer_SpeakCompleted(object sender, SpeakCompletedEventArgs e)
        {
            if (!ttsAvailable || synthesizer == null) return;
            Task.Run(() =>
            {
                byte[] speech = audioStream.ToArray();
                if (speech.Length > 0)
                {
                    BoostVolume(speech, speech.Length, 5f); // Boost volume
                    radioAudio.TransmitVoice(speech, 0, speech.Length, true);
                }
                audioStream.SetLength(0);
                Processing = false;
            });
        }

        private void BoostVolume(byte[] buffer, int bytesRecorded, float volume)
        {
            for (int i = 0; i < bytesRecorded; i += 2)
            {
                short sample = (short)(buffer[i] | (buffer[i + 1] << 8));
                int boosted = (int)(sample * volume);

                // Clamp to prevent clipping
                if (boosted > short.MaxValue) boosted = short.MaxValue;
                if (boosted < short.MinValue) boosted = short.MinValue;

                buffer[i] = (byte)(boosted & 0xFF);
                buffer[i + 1] = (byte)((boosted >> 8) & 0xFF);
            }
        }

        public bool Morse(string text)
        {
            Task.Run(() =>
            {
                byte[] speech = MorseCodeEngine.GenerateMorsePcm(text);
                if (speech.Length > 0)
                {
                    BoostVolume(speech, speech.Length, 5f); // Boost volume
                    radioAudio.TransmitVoice(speech, 0, speech.Length, true);
                }
            });
            return true;
        }

    }

    public class WhisperEngine
    {
        private WhisperProcessor _processor; // The core Whisper processor
        private readonly WaveFormat _sourceAudioFormat = new WaveFormat(32000, 16, 1);
        private readonly WaveFormat _targetAudioFormat = new WaveFormat(16000, 16, 1);
        private byte[] audioBuffer = null;
        private int audioBufferLength = 0;
        private DateTime audioBufferTime = DateTime.MinValue;
        private string audioBufferChannel = null;
        private int audioTimeOffset = 0;
        private DateTime processingAudioBufferTime = DateTime.MinValue;
        private string processingAudioBufferChannel = null;
        private int processingAudioTimeOffset = 0;
        private bool processingAudioCompleted = false;
        private bool processing = false;
        private bool disposed = false;
        private List<ProcessingHold> ProcessingHolds = new List<ProcessingHold>();
        private List<WhisperToken> Tokens = new List<WhisperToken>();
        private List<WhisperToken> NewTokens = new List<WhisperToken>();

        public delegate void OnTextReadyHandler(string text, string channel, DateTime time, bool completed);
        public event OnTextReadyHandler onTextReady;
        public delegate void OnProcessingVoiceHandler(bool processing);
        public event OnProcessingVoiceHandler onProcessingVoice;

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        private void Debug(string msg) { if (OnDebugMessage != null) { OnDebugMessage(msg); } }

        // Holding buffer for audio data
        private class ProcessingHold
        {
            public ProcessingHold(DateTime time, int offset, string channel, float[] buffer, bool completed)
            {
                holdAudioBufferTime = time;
                holdAudioBufferChannel = channel;
                holdAudioBuffer = buffer;
                holdAudioTimeOffset = offset;
                holdAudioCompleted = completed;
            }
            public DateTime holdAudioBufferTime;
            public string holdAudioBufferChannel;
            public float[] holdAudioBuffer;
            public int holdAudioTimeOffset;
            public bool holdAudioCompleted;
        }

        // "ggml-tiny.bin", "ggml-base.bin"
        // Constructor now takes the model path and expected input format
        public WhisperEngine(string modelPath, string language)
        {
            Task.Run(() =>
            {
                try
                {
                    // Basic validation
                    if (string.IsNullOrWhiteSpace(modelPath)) throw new ArgumentNullException(nameof(modelPath));
                    if (!File.Exists(modelPath)) throw new FileNotFoundException($"Whisper model file not found: {modelPath}", modelPath);

                    // --- Factory and Processor Initialization ---
                    WhisperFactory factory = WhisperFactory.FromPath(modelPath);
                    if (factory == null) throw new InvalidOperationException("WhisperFactory.FromPath returned null.");
                    WhisperProcessorBuilder builder = factory.CreateBuilder();
                    if (builder == null) throw new InvalidOperationException("WhisperFactory.CreateBuilder returned null.");

                    // --- Configure the processor ---
                    builder = builder.WithThreads(Math.Max(1, Environment.ProcessorCount / 2));
                    if (language == "auto") { builder = builder.WithLanguageDetection(); } else { builder = builder.WithLanguage(language); }
                    builder = builder.WithTokenTimestamps();
                    builder = builder.WithSegmentEventHandler(OnWhisperInternalSegmentReceived);

                    _processor = builder.Build();
                    if (_processor == null) throw new InvalidOperationException("WhisperProcessorBuilder.Build returned null.");
                }
                catch (Exception ex)
                {
                    Debug(ex.Message);
                }
            });
        }

        public void StartVoiceSegment()
        {

        }

        // Reset finishes the current segment and starts a new one
        public void ResetVoiceSegment()
        {
            ProcessAudioChunk(null, 0, 0, null);
        }

        // Complete finishes the current segment, forcing processing of any remaining audio
        public void CompleteVoiceSegment()
        {
            ProcessAudioChunk(null, 0, 0, null);
        }

        int segmentsOverlap = 512000;

        public void ProcessAudioChunk(byte[] data, int index, int length, string channel)
        {
            if (_processor == null) return;
            if (disposed) return;
            if (length > 0)
            {
                // Collect the time and channel of the first audio frame
                if (audioBufferChannel == null)
                {
                    audioBufferTime = DateTime.Now;
                    audioBufferChannel = channel;
                }

                // Gather up a bunch of audio data
                if (audioBuffer == null) { audioBuffer = new byte[1280000]; audioBufferLength = 0; }
                Array.Copy(data, index, audioBuffer, audioBufferLength, length);
                audioBufferLength += length;
            }
            else
            {
                // If we are done and it's a tiny amount of audio, just ignore it
                if (audioBufferLength < 5000) { audioBufferLength = 0; }
            }

            if ((audioBufferLength > 0) && ((audioBufferLength > (audioBuffer.Length - 16384)) || (length == 0)))
            {
                // Resample the audio from 32kHz to 16kHz
                int originalAudioBufferLength = audioBufferLength;
                byte[] pcm16kBytes = ResampleAudioChunk(audioBuffer, 0, audioBufferLength);
                if (pcm16kBytes == null || pcm16kBytes.Length == 0) return;

                // Reset the buffer for the next chunk
                if (length > 0)
                {
                    Array.Copy(audioBuffer, audioBufferLength - segmentsOverlap, audioBuffer, 0, segmentsOverlap);
                    audioBufferLength = segmentsOverlap;
                }
                else
                {
                    audioBufferLength = 0;
                }

                if (processing == false)
                {
                    // Convert 16-bit PCM bytes to float[] (-1.0 to 1.0) and process it
                    processing = true;
                    if (onProcessingVoice != null) { onProcessingVoice(true); }
                    processingAudioBufferTime = audioBufferTime;
                    processingAudioBufferChannel = audioBufferChannel;
                    processingAudioTimeOffset = audioTimeOffset;
                    processingAudioCompleted = (length == 0);
                    try
                    {
                        Task.Run(() =>
                        {
                            try
                            {
                                _processor.Process(ConvertPcm16ToFloat32(pcm16kBytes));
                            }
                            catch (Exception ex) { Console.WriteLine(ex.Message); }
                        })
                        .ContinueWith(task =>
                        {
                            if (task.IsCompleted) { OnWhispeCompleted(); }
                        }
                        );
                    }
                    catch (Exception ex) { Console.WriteLine(ex.Message); }
                }
                else
                {
                    if (ProcessingHolds.Count < 5)
                    {
                        lock (ProcessingHolds)
                        {
                            ProcessingHolds.Add(new ProcessingHold(audioBufferTime, audioTimeOffset, audioBufferChannel, ConvertPcm16ToFloat32(pcm16kBytes), length == 0));
                        }
                    }
                    else
                    {
                        lock (ProcessingHolds) { ProcessingHolds.Clear(); }
                        if (onTextReady != null) { onTextReady(null, "CPU Overloaded, Audio processing skipped.", DateTime.Now, true); }
                    }
                }
                if (length == 0)
                {
                    audioBufferChannel = null;
                    audioTimeOffset = 0;
                }
                else
                {
                    audioTimeOffset += ((originalAudioBufferLength - segmentsOverlap) / 640) + 25; // There is 64 bytes in the buffer for each millisecond (32 kHz, 16 bits)
                }
            }
        }

        public void Dispose()
        {
            disposed = true;
            if (_processor != null) { _processor.DisposeAsync(); }
            _processor = null;
            audioBuffer = null;
        }

        private void OnWhisperInternalSegmentReceived(SegmentData segment)
        {
            foreach (var token in segment.Tokens) {
                if (token.Text.StartsWith("[") && token.Text.EndsWith("]")) continue;
                NewTokens.Add(token);
            }
        }

        private void OnWhispeCompleted()
        {
            if (Tokens.Count == 0)
            {
                Tokens.AddRange(NewTokens);
            }
            else
            {
                // Merge the new tokens with the existing ones
                Tokens = MergeTokens(Tokens, NewTokens, processingAudioTimeOffset);
                NewTokens.Clear();
            }

            if (Tokens.Count > 600) { processingAudioCompleted = true; } // Over 600 tokens, reset the token window.
            if (onTextReady != null) { onTextReady(TokensToString(Tokens), processingAudioBufferChannel, processingAudioBufferTime, processingAudioCompleted); }
            if (processingAudioCompleted) { Tokens.Clear(); NewTokens.Clear(); }

            // We are done, process the next round
            lock (ProcessingHolds)
            {
                if (ProcessingHolds.Count > 0)
                {
                    ProcessingHold p = ProcessingHolds[0];
                    ProcessingHolds.RemoveAt(0);
                    processingAudioBufferTime = p.holdAudioBufferTime;
                    processingAudioBufferChannel = p.holdAudioBufferChannel;
                    processingAudioTimeOffset = p.holdAudioTimeOffset;
                    processingAudioCompleted = p.holdAudioCompleted;
                    try
                    {
                        Task.Run(() => {
                            try{ if (_processor != null) { _processor.Process(p.holdAudioBuffer); } } catch (Exception ex) { Console.WriteLine(ex.Message); }
                        })
                        .ContinueWith(task => { if (task.IsCompleted) { OnWhispeCompleted(); } });
                    }
                    catch (Exception ex) { Console.WriteLine(ex.Message); }
                }
                else
                {
                    processing = false;
                }
            }
            if ((onProcessingVoice != null) && (processing == false)) { onProcessingVoice(false); }
        }

        private float[] ConvertPcm16ToFloat32(byte[] pcm16Bytes)
        {
            int outIndex = 0, sampleCount = pcm16Bytes.Length / 2;
            float[] floatBuffer = new float[sampleCount];
            for (int i = 0; i < pcm16Bytes.Length - 1; i += 2) // Ensure we don't read past bounds
            {
                short sample = BitConverter.ToInt16(pcm16Bytes, i); // Assuming little-endian architecture
                floatBuffer[outIndex++] = (float)sample / 32768.0f; // Normalize to range [-1.0, 1.0]
            }
            return floatBuffer;
        }

        private byte[] ResampleAudioChunk(byte[] inputBytes, int inputIndex, int inputLength)
        {
            using (var sourceStream = new RawSourceWaveStream(inputBytes, inputIndex, inputLength, _sourceAudioFormat))
            using (var resampler = new MediaFoundationResampler(sourceStream, _targetAudioFormat)) // Use MediaFoundationResampler (requires Windows Media Foundation)
            // using (var resampler = new WaveFormatConversionStream(_targetAudioFormat, sourceStream)) // Alternative: WaveFormatConversionStream (more basic, cross-platform)
            {
                // Estimate output size reasonably
                int estimatedOutputLength = (int)((double)inputLength * _targetAudioFormat.SampleRate / _sourceAudioFormat.SampleRate * _targetAudioFormat.Channels / _sourceAudioFormat.Channels * _targetAudioFormat.BitsPerSample / _sourceAudioFormat.BitsPerSample);
                estimatedOutputLength = Math.Max(estimatedOutputLength, _targetAudioFormat.BlockAlign * 16); // Ensure some minimum

                using (var ms = new MemoryStream(estimatedOutputLength))
                {
                    // Buffer size can impact performance, 4k-8k is often reasonable
                    int bytesRead;
                    byte[] buffer = new byte[resampler.WaveFormat.AverageBytesPerSecond / 10]; // ~100ms buffer
                    while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0) { ms.Write(buffer, 0, bytesRead); }
                    return ms.ToArray();
                }
            }
        }

        private string TokensToString(List<WhisperToken> tokens)
        {
            StringBuilder sb = new StringBuilder();
            foreach (var token in tokens) {
                //if (token.Text.StartsWith("[") && token.Text.EndsWith("]")) continue;
                sb.Append(token.Text);
            }
            return sb.ToString();
        }

        private static WhisperToken CreateWhisperToken(string text, long start, long end, float probability)
        {
            WhisperToken t = new WhisperToken();
            t.Text = text;
            t.Start = start;
            t.End = end;
            t.Probability = probability;
            return t;
        }

        // --- Configuration ---
        // Minimum number of consecutive matching tokens to consider a reliable overlap
        private const int MinMatchLength = 3;
        // Time tolerance when comparing token start times during matching
        private const int TimeTolerance = 100; // In seconds. Adjust based on observed jitter.

        /*
        /// <summary>
        /// Merges a new list of tokens into an existing list, using an offset.
        /// It attempts to find a matching sequence in the overlap to determine
        /// the best midpoint cut-off.
        /// </summary>
        /// <param name="existingTokens">The list of tokens already merged.</param>
        /// <param name="newTokensArray">The new tokens from the next overlapping chunk.</param>
        /// <param name="newChunkOffsetSec">The start time (in seconds) of the audio chunk
        /// that produced newTokensArray, relative to the start of the first chunk.</param>
        /// <returns>A new list containing the merged tokens.</returns>
        public static List<WhisperToken> MergeTokens10(
            List<WhisperToken> existingTokens,
            List<WhisperToken> newTokensArray,
            long newChunkOffsetSec)
        {
            // --- Basic Edge Cases ---
            if (newTokensArray == null || newTokensArray.Count == 0)
            {
                return new List<WhisperToken>(existingTokens ?? new List<WhisperToken>());
            }

            if (existingTokens == null || existingTokens.Count == 0)
            {
                // Adjust timestamps of new tokens and return them
                return newTokensArray.Select(t => CreateWhisperToken(
                                                t.Text,
                                                t.Start + newChunkOffsetSec,
                                                t.End + newChunkOffsetSec,
                                                0))
                                    .ToList();
            }

            // --- Prepare New Tokens with Adjusted Timestamps ---
            // Create a list and adjust times globally
            List<WhisperToken> adjustedNewTokens = newTokensArray.Select(t => CreateWhisperToken(
                                                        t.Text,
                                                        t.Start + newChunkOffsetSec,
                                                        t.End + newChunkOffsetSec,
                                                        0))
                                                    .ToList();

            // --- Check for Non-Overlapping Case ---
            float lastExistingEndTime = existingTokens.LastOrDefault()?.End ?? 0f;
            float firstNewStartTime = adjustedNewTokens.FirstOrDefault()?.Start ?? float.MaxValue;

            if (lastExistingEndTime < firstNewStartTime)
            {
                // No time overlap, simply concatenate
                List<WhisperToken> combined = new List<WhisperToken>(existingTokens);
                combined.AddRange(adjustedNewTokens);
                return combined;
            }


            // --- Find Best Matching Sequence in Overlap ---
            int bestMatchLength = 0;
            int bestExistingMatchEndIndex = -1; // Index of the *last* token in the matched sequence in existingTokens
            int bestNewMatchStartIndex = -1;    // Index of the *first* token in the matched sequence in adjustedNewTokens

            // Iterate backwards through existing tokens, starting from potential overlap
            int searchStartExisting = existingTokens.FindIndex(t => t.End >= newChunkOffsetSec);
            if (searchStartExisting == -1) searchStartExisting = 0; // Should not happen if overlap exists, but safety first

            for (int i = existingTokens.Count - 1; i >= searchStartExisting; i--)
            {
                // Iterate forwards through new tokens
                for (int j = 0; j < adjustedNewTokens.Count; j++)
                {
                    // Check if current pair (i, j) potentially starts a match
                    if (existingTokens[i].Text == adjustedNewTokens[j].Text &&
                        Math.Abs(existingTokens[i].Start - adjustedNewTokens[j].Start) < TimeTolerance)
                    {
                        // Found a potential start, now extend the match
                        int currentMatchLength = 0;
                        while (i + currentMatchLength < existingTokens.Count &&
                               j + currentMatchLength < adjustedNewTokens.Count &&
                               existingTokens[i + currentMatchLength].Text == adjustedNewTokens[j + currentMatchLength].Text &&
                               Math.Abs(existingTokens[i + currentMatchLength].Start - adjustedNewTokens[j + currentMatchLength].Start) < TimeTolerance)
                        {
                            currentMatchLength++;
                        }

                        // Check if this is the best match found so far
                        // Prioritize longer matches. If lengths are equal, prioritize matches occurring later in existingTokens.
                        if (currentMatchLength >= MinMatchLength && currentMatchLength >= bestMatchLength) // Use >= to favour later matches of same length
                        {
                            bestMatchLength = currentMatchLength;
                            bestExistingMatchEndIndex = i + currentMatchLength - 1; // Last index of the match in existing
                            bestNewMatchStartIndex = j;                             // First index of the match in new
                        }

                        // Optimization: If we found a match starting at j, we don't need to check
                        // subsequent j's for the same i, as we want the *longest* match extension.
                        // However, a new potential match could start later in adjustedNewTokens for the *same* i
                        // if the first attempt didn't pan out long enough. So, continue the inner loop.
                    }
                }
                // Optimization: If we found a very long match, we might stop early,
                // but it's safer to check all possibilities unless performance is critical.
            }


            // --- Determine Cut-off Point and Merge ---
            List<WhisperToken> mergedTokens = new List<WhisperToken>();
            int splitIndexExisting = -1; // Index of last token to take from existingTokens
            int splitIndexNew = -1;      // Index of first token to take from adjustedNewTokens

            if (bestMatchLength >= MinMatchLength)
            {
                // Found a reliable match - use midpoint of the *match*
                Console.WriteLine($"Found match length: {bestMatchLength}, ExistingEndIdx: {bestExistingMatchEndIndex}, NewStartIdx: {bestNewMatchStartIndex}");

                int matchMidpointRelative = bestMatchLength / 2; // Integer division gives floor, which is fine
                splitIndexExisting = bestExistingMatchEndIndex - (bestMatchLength - 1) + matchMidpointRelative; // Index of token at midpoint in existing
                splitIndexNew = bestNewMatchStartIndex + matchMidpointRelative + 1;                            // Index of token *after* midpoint in new

                // --- Sanity checks for indices ---
                if (splitIndexExisting < 0) splitIndexExisting = 0;
                if (splitIndexExisting >= existingTokens.Count) splitIndexExisting = existingTokens.Count - 1;
                if (splitIndexNew < 0) splitIndexNew = 0;
                // No check needed for splitIndexNew >= adjustedNewTokens.Count, slicing handles it

                Console.WriteLine($"Calculated split: Take existing up to index {splitIndexExisting}, start new from index {splitIndexNew}");

            }
            else
            {
                // No reliable match found - Fallback to simple time-based midpoint
                // Calculate midpoint time relative to the start of the *new* chunk's original time range
                // Assumes a nominal chunk duration (e.g., 20s) and overlap (e.g., 8s)
                // Example: new chunk starts at 12s, duration 20s. Overlap is 8s. Midpoint is 12s + 8s/2 = 16s.
                // This needs knowledge of the *intended* overlap duration. Let's estimate from offset.
                // We can estimate the overlap end time based on the last token of the previous chunk.
                float estimatedOverlapStartTime = newChunkOffsetSec;
                float estimatedOverlapEndTime = Math.Min(existingTokens.Last().End, adjustedNewTokens.Last().Start); // Approx end of shared time
                if (estimatedOverlapEndTime <= estimatedOverlapStartTime)
                {
                    // Handle cases where overlap is minimal or negative time due calculation noise
                    estimatedOverlapEndTime = estimatedOverlapStartTime + 1.0f; // Assume at least 1 sec overlap if calculated is bad
                }

                float fallbackMidpointTime = estimatedOverlapStartTime + (estimatedOverlapEndTime - estimatedOverlapStartTime) / 2.0f;

                Console.WriteLine($"No reliable match found. Using fallback time midpoint: {fallbackMidpointTime:F2}s");


                // Find the index right BEFORE the midpoint time in existingTokens
                splitIndexExisting = existingTokens.FindLastIndex(t => t.Start < fallbackMidpointTime);
                if (splitIndexExisting == -1) splitIndexExisting = 0; // Take none if midpoint is before the first token

                // Find the index AT or AFTER the midpoint time in adjustedNewTokens
                splitIndexNew = adjustedNewTokens.FindIndex(t => t.Start >= fallbackMidpointTime);
                if (splitIndexNew == -1) splitIndexNew = adjustedNewTokens.Count; // Take none if midpoint is after the last token

                Console.WriteLine($"Fallback split: Take existing up to index {splitIndexExisting}, start new from index {splitIndexNew}");
            }

            // --- Perform the Merge ---
            // Add tokens from the existing list up to the split point
            mergedTokens.AddRange(existingTokens.Take(splitIndexExisting + 1));

            // Add tokens from the new list starting from the split point
            if (splitIndexNew < adjustedNewTokens.Count)
            {
                mergedTokens.AddRange(adjustedNewTokens.Skip(splitIndexNew));
            }

            // --- Final check for monotonicity (optional but good practice) ---
            for (int k = 1; k < mergedTokens.Count; k++)
            {
                if (mergedTokens[k].Start < mergedTokens[k - 1].Start)
                {
                    // This indicates an issue in the merge logic or timestamp inconsistency
                    Console.WriteLine($"Warning: Timestamp monotonicity violation at index {k}: {mergedTokens[k - 1]} followed by {mergedTokens[k]}");
                    // Corrective action could be attempted here, e.g., adjusting start times,
                    // but it's often better to flag it and refine the merge logic.
                    // Simple fix: Adjust start time of current token if slightly off
                    if (mergedTokens[k].Start < mergedTokens[k - 1].End)
                    {
                        mergedTokens[k].Start = mergedTokens[k - 1].End;
                    }
                }
                // Ensure EndTime >= StartTime
                if (mergedTokens[k].End < mergedTokens[k].Start)
                {
                    mergedTokens[k].End = mergedTokens[k].Start; // Simple fix
                }
            }

            return mergedTokens;
        }
        */

        /// <summary>
        /// Merges a new list of tokens into an existing list, using an offset
        /// and token probabilities to improve the cut-off decision within matched sequences.
        /// </summary>
        /// <param name="existingTokens">The list of tokens already merged.</param>
        /// <param name="newTokensArray">The new tokens from the next overlapping chunk.</param>
        /// <param name="newChunkOffsetSec">The start time (in seconds) of the audio chunk
        /// that produced newTokensArray, relative to the start of the first chunk.</param>
        /// <returns>A new list containing the merged tokens.</returns>
        public static List<WhisperToken> MergeTokens(
            List<WhisperToken> existingTokens,
            List<WhisperToken> newTokensArray,
            int newChunkOffsetSec)
        {
            // --- Basic Edge Cases ---
            if (newTokensArray == null || newTokensArray.Count == 0)
            {
                return new List<WhisperToken>(existingTokens ?? new List<WhisperToken>());
            }

            if (existingTokens == null || existingTokens.Count == 0)
            {
                // Adjust timestamps of new tokens and return them
                return newTokensArray.Select(t => CreateWhisperToken(
                                                t.Text,
                                                t.Start + newChunkOffsetSec, // Use .Start
                                                t.End + newChunkOffsetSec,   // Use .End
                                                t.Probability))
                                    .ToList();
            }

            // --- Prepare New Tokens with Adjusted Timestamps ---
            List<WhisperToken> adjustedNewTokens = newTokensArray.Select(t => CreateWhisperToken(
                                                        t.Text,
                                                        t.Start + newChunkOffsetSec, // Use .Start
                                                        t.End + newChunkOffsetSec,   // Use .End
                                                        t.Probability))
                                                    .ToList();

            // --- Check for Non-Overlapping Case ---
            float lastExistingEndTime = existingTokens.LastOrDefault()?.End ?? 0f; // Use .End
            float firstNewStartTime = adjustedNewTokens.FirstOrDefault()?.Start ?? float.MaxValue; // Use .Start

            if (lastExistingEndTime < firstNewStartTime)
            {
                List<WhisperToken> combined = new List<WhisperToken>(existingTokens);
                combined.AddRange(adjustedNewTokens);
                return combined;
            }

            // --- Find Best Matching Sequence in Overlap ---
            int bestMatchLength = 0;
            int bestMatchStartIdxExisting = -1; // Start index of the match in existingTokens
            int bestMatchStartIdxNew = -1;      // Start index of the match in adjustedNewTokens
            int bestMatchEndIdxExisting = -1;   // End index of the match in existingTokens


            // Iterate backwards through existing tokens, starting from potential overlap
            int searchStartExisting = existingTokens.FindIndex(t => t.End >= newChunkOffsetSec); // Use .End
            if (searchStartExisting == -1) searchStartExisting = 0;

            for (int i = existingTokens.Count - 1; i >= searchStartExisting; i--)
            {
                for (int j = 0; j < adjustedNewTokens.Count; j++)
                {
                    // Check if current pair (i, j) potentially starts a match
                    if (existingTokens[i].Text == adjustedNewTokens[j].Text &&
                        Math.Abs(existingTokens[i].Start - adjustedNewTokens[j].Start) < TimeTolerance) // Use .Start
                    {
                        int currentMatchLength = 0;
                        while (i + currentMatchLength < existingTokens.Count &&
                               j + currentMatchLength < adjustedNewTokens.Count &&
                               existingTokens[i + currentMatchLength].Text == adjustedNewTokens[j + currentMatchLength].Text &&
                               Math.Abs(existingTokens[i + currentMatchLength].Start - adjustedNewTokens[j + currentMatchLength].Start) < TimeTolerance) // Use .Start
                        {
                            currentMatchLength++;
                        }

                        if (currentMatchLength >= MinMatchLength && currentMatchLength >= bestMatchLength)
                        {
                            bestMatchLength = currentMatchLength;
                            bestMatchStartIdxExisting = i;
                            bestMatchEndIdxExisting = i + currentMatchLength - 1;
                            bestMatchStartIdxNew = j;
                        }
                    }
                }
            }

            // --- Determine Cut-off Point and Merge ---
            List<WhisperToken> mergedTokens = new List<WhisperToken>();
            int splitIndexExisting = -1; // Index of LAST token to take from existingTokens
            int splitIndexNew = -1;      // Index of FIRST token to take from adjustedNewTokens

            if (bestMatchLength >= MinMatchLength)
            {
                // --- Found a reliable match - Use probability at midpoint ---
                //Console.WriteLine($"Found match length: {bestMatchLength}, ExistingMatchIdx: [{bestMatchStartIdxExisting}-{bestMatchEndIdxExisting}], NewMatchStartIdx: {bestMatchStartIdxNew}");

                // Calculate the index corresponding to the midpoint of the matched sequence
                int midMatchIdxRelative = bestMatchLength / 2;
                int midIndexExisting = bestMatchStartIdxExisting + midMatchIdxRelative;
                int midIndexNew = bestMatchStartIdxNew + midMatchIdxRelative;

                // Get the tokens at the midpoint from both lists
                WhisperToken tokenMidExisting = existingTokens[midIndexExisting];
                WhisperToken tokenMidNew = adjustedNewTokens[midIndexNew];

                //Console.WriteLine($"Midpoint Compare: Existing='{tokenMidExisting}' vs New='{tokenMidNew}'");

                // Decide based on probability
                if (tokenMidExisting.Probability >= tokenMidNew.Probability)
                {
                    // Prefer the existing token's version at the midpoint
                    splitIndexExisting = midIndexExisting; // Take existing up to and including this token
                    splitIndexNew = midIndexNew + 1;       // Start new list *after* the corresponding midpoint token
                    //Console.WriteLine($"Decision: Prefer Existing (P={tokenMidExisting.Probability:F3} >= P={tokenMidNew.Probability:F3}). Split after existing idx {splitIndexExisting}, start new idx {splitIndexNew}");
                }
                else
                {
                    // Prefer the new token's version at the midpoint
                    splitIndexExisting = midIndexExisting - 1; // Take existing up to the token *before* the midpoint
                    splitIndexNew = midIndexNew;               // Start new list *at* the midpoint token
                    //Console.WriteLine($"Decision: Prefer New (P={tokenMidNew.Probability:F3} > P={tokenMidExisting.Probability:F3}). Split after existing idx {splitIndexExisting}, start new idx {splitIndexNew}");
                }

                // --- Sanity checks for indices ---
                if (splitIndexExisting < -1) splitIndexExisting = -1; // Allow -1 for taking none from existing
                if (splitIndexNew < 0) splitIndexNew = 0;
                // No check needed for splitIndexNew >= adjustedNewTokens.Count, slicing handles it
            }
            else
            {
                // --- No reliable match found - Fallback to simple time-based midpoint ---
                float estimatedOverlapStartTime = newChunkOffsetSec;
                // Use End time of last existing token or Start time of last new token as potential end bounds
                float estimatedOverlapEndTime = Math.Min(existingTokens.Last().End, adjustedNewTokens.Last().Start); // Use .End, .Start
                if (estimatedOverlapEndTime <= estimatedOverlapStartTime)
                {
                    estimatedOverlapEndTime = estimatedOverlapStartTime + 1.0f; // Assume min 1 sec overlap
                }
                float fallbackMidpointTime = estimatedOverlapStartTime + (estimatedOverlapEndTime - estimatedOverlapStartTime) / 2.0f;

                //Console.WriteLine($"No reliable match found. Using fallback time midpoint: {fallbackMidpointTime:F2}s");

                // Find the index right BEFORE the midpoint time in existingTokens
                splitIndexExisting = existingTokens.FindLastIndex(t => t.Start < fallbackMidpointTime); // Use .Start
                                                                                                        // If midpoint is before *any* token starts, this will be -1, which is correct (take none).

                // Find the index AT or AFTER the midpoint time in adjustedNewTokens
                splitIndexNew = adjustedNewTokens.FindIndex(t => t.Start >= fallbackMidpointTime); // Use .Start
                if (splitIndexNew == -1) splitIndexNew = adjustedNewTokens.Count; // Take none if midpoint is after the last token starts

                //Console.WriteLine($"Fallback split: Take existing up to index {splitIndexExisting}, start new from index {splitIndexNew}");
            }

            // --- Perform the Merge ---
            // Add tokens from the existing list up to the split point
            // `Take` needs count, so index + 1
            mergedTokens.AddRange(existingTokens.Take(splitIndexExisting + 1));

            // Add tokens from the new list starting from the split point
            if (splitIndexNew < adjustedNewTokens.Count)
            {
                mergedTokens.AddRange(adjustedNewTokens.Skip(splitIndexNew));
            }

            // --- Final check for monotonicity ---
            for (int k = 1; k < mergedTokens.Count; k++)
            {
                // Check if current token starts before previous one *started* (more robust than checking against previous End)
                if (mergedTokens[k].Start < mergedTokens[k - 1].Start + 0.01f) // Added small tolerance
                {
                    //Console.WriteLine($"Warning: Timestamp monotonicity violation at index {k}: {mergedTokens[k - 1]} followed by {mergedTokens[k]}");
                    // Simple fix: Adjust Start time if it overlaps significantly with previous *End* time
                    if (mergedTokens[k].Start < mergedTokens[k - 1].End)
                    {
                        mergedTokens[k].Start = mergedTokens[k - 1].End;
                    }
                }
                // Ensure End >= Start
                if (mergedTokens[k].End < mergedTokens[k].Start)
                {
                    //Console.WriteLine($"Warning: Correcting End time for token at index {k}: {mergedTokens[k]}");
                    mergedTokens[k].End = mergedTokens[k].Start;
                }
            }

            return mergedTokens;
        }

    }
}
