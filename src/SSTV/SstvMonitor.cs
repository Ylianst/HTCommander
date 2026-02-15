/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace HTCommander.SSTV
{
    /// <summary>
    /// Event arguments for SSTV decoding start.
    /// </summary>
    public class SstvDecodingStartedEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    /// <summary>
    /// Event arguments for SSTV decoding progress.
    /// </summary>
    public class SstvDecodingProgressEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int CurrentLine { get; set; }
        public int TotalLines { get; set; }
        public float PercentComplete => TotalLines > 0 ? (CurrentLine / (float)TotalLines) * 100f : 0f;
    }

    /// <summary>
    /// Event arguments for SSTV decoding completion.
    /// </summary>
    public class SstvDecodingCompleteEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        /// <summary>
        /// The decoded image as a Bitmap. Caller is responsible for disposing.
        /// </summary>
        public Bitmap Image { get; set; }
    }

    /// <summary>
    /// Wraps the SSTV Decoder to provide event-driven notifications for
    /// auto-detection, progress, and completion of SSTV image decoding.
    /// Feed it received PCM audio and it will fire events as images are detected and decoded.
    /// </summary>
    public class SstvMonitor : IDisposable
    {
        private Decoder _decoder;
        private PixelBuffer _scopeBuffer;
        private PixelBuffer _imageBuffer;
        private readonly int _sampleRate;
        private readonly object _lock = new object();
        private bool _disposed = false;

        // State tracking for event detection
        private int _previousLine = -1;
        private bool _isDecoding = false;
        private string _currentModeName = null;
        private int _lastProgressLine = -1;
        private const int ProgressLineInterval = 10; // Fire progress every N lines

        /// <summary>
        /// Fired when SSTV decoding starts (VIS header detected, mode identified).
        /// </summary>
        public event EventHandler<SstvDecodingStartedEventArgs> DecodingStarted;

        /// <summary>
        /// Fired when new scan lines have been decoded (progress update).
        /// </summary>
        public event EventHandler<SstvDecodingProgressEventArgs> DecodingProgress;

        /// <summary>
        /// Fired when a complete SSTV image has been decoded.
        /// </summary>
        public event EventHandler<SstvDecodingCompleteEventArgs> DecodingComplete;

        /// <summary>
        /// Creates a new SstvMonitor.
        /// </summary>
        /// <param name="sampleRate">Audio sample rate in Hz (must match the PCM data fed in). Default 32000.</param>
        public SstvMonitor(int sampleRate = 32000)
        {
            _sampleRate = sampleRate;
            Initialize();
        }

        /// <summary>
        /// Initializes the decoder for detecting a new image.
        /// </summary>
        private void Initialize()
        {
            // PD 290 is the largest mode at 800x616, use that as the buffer size
            _scopeBuffer = new PixelBuffer(800, 616);
            _imageBuffer = new PixelBuffer(800, 616);
            _imageBuffer.Line = -1;

            _decoder = new Decoder(_scopeBuffer, _imageBuffer, "Raw", _sampleRate);
            _previousLine = -1;
            _isDecoding = false;
            _currentModeName = null;
            _lastProgressLine = -1;
        }

        /// <summary>
        /// Resets the decoder to prepare for detecting a new image.
        /// </summary>
        public void Reset()
        {
            lock (_lock)
            {
                Initialize();
            }
        }

        /// <summary>
        /// Feeds 16-bit signed PCM audio data (little-endian) to the SSTV decoder.
        /// Events will fire on the calling thread as images are detected and decoded.
        /// </summary>
        /// <param name="pcmData">Byte array containing 16-bit signed PCM samples.</param>
        /// <param name="offset">Offset into the byte array.</param>
        /// <param name="length">Number of bytes to process (must be even).</param>
        public void ProcessPcm16(byte[] pcmData, int offset, int length)
        {
            if (_disposed) return;
            if (pcmData == null || length <= 0) return;

            // Convert 16-bit signed PCM to float samples normalized to -1..1
            int sampleCount = length / 2;
            float[] samples = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                int byteIndex = offset + i * 2;
                if (byteIndex + 1 >= offset + length) break;
                short sample = (short)(pcmData[byteIndex] | (pcmData[byteIndex + 1] << 8));
                samples[i] = sample / 32768f;
            }

            ProcessFloatSamples(samples);
        }

        /// <summary>
        /// Feeds float audio samples (normalized -1..1) to the SSTV decoder.
        /// </summary>
        /// <param name="samples">Array of float audio samples.</param>
        public void ProcessFloatSamples(float[] samples)
        {
            if (_disposed) return;
            if (samples == null || samples.Length == 0) return;

            // Collect events to fire outside the lock to prevent deadlocks
            SstvDecodingStartedEventArgs startedArgs = null;
            SstvDecodingProgressEventArgs progressArgs = null;
            SstvDecodingCompleteEventArgs completeArgs = null;

            lock (_lock)
            {
                if (_decoder == null) return;

                // Process through the decoder (channel 0 = mono)
                bool newLines = _decoder.Process(samples, 0);

                int currentLine = _imageBuffer.Line;
                int height = _imageBuffer.Height;

                // Detect decoding START: Line transitions from negative to 0+ with a known mode
                if (!_isDecoding && currentLine >= 0 && currentLine < height && _decoder.CurrentMode != null)
                {
                    _isDecoding = true;
                    _currentModeName = _decoder.CurrentMode.GetName();
                    _lastProgressLine = 0;

                    startedArgs = new SstvDecodingStartedEventArgs
                    {
                        ModeName = _currentModeName,
                        Width = _decoder.CurrentMode.GetWidth(),
                        Height = _decoder.CurrentMode.GetHeight()
                    };
                }

                // Detect PROGRESS: new lines were decoded, throttled by interval
                if (_isDecoding && newLines && currentLine > _previousLine && currentLine < height)
                {
                    if (currentLine - _lastProgressLine >= ProgressLineInterval)
                    {
                        _lastProgressLine = currentLine;
                        progressArgs = new SstvDecodingProgressEventArgs
                        {
                            ModeName = _currentModeName,
                            CurrentLine = currentLine,
                            TotalLines = height
                        };
                    }
                }

                // Detect COMPLETION: Line reached or exceeded Height
                if (_isDecoding && currentLine >= height && _previousLine < height)
                {
                    Bitmap image = ExtractImage();

                    completeArgs = new SstvDecodingCompleteEventArgs
                    {
                        ModeName = _currentModeName,
                        Width = image?.Width ?? 0,
                        Height = image?.Height ?? 0,
                        Image = image
                    };

                    // Reset for next image
                    _isDecoding = false;
                    _currentModeName = null;
                    _previousLine = -1;
                    _lastProgressLine = -1;

                    // Re-initialize decoder for the next potential image
                    Initialize();
                }
                else
                {
                    _previousLine = currentLine;
                }
            }

            // Fire events outside the lock to prevent deadlocks with callers
            if (startedArgs != null) DecodingStarted?.Invoke(this, startedArgs);
            if (progressArgs != null) DecodingProgress?.Invoke(this, progressArgs);
            if (completeArgs != null) DecodingComplete?.Invoke(this, completeArgs);
        }

        /// <summary>
        /// Extracts the decoded image from the pixel buffer as a Bitmap.
        /// </summary>
        /// <returns>A new Bitmap containing the decoded image, or null on failure.</returns>
        private Bitmap ExtractImage()
        {
            try
            {
                int width = _imageBuffer.Width;
                int height = _imageBuffer.Height;
                int[] pixels = _imageBuffer.Pixels;

                if (width <= 0 || height <= 0 || pixels == null || pixels.Length < width * height)
                    return null;

                // Apply post-processing if the mode supports it (e.g., HF Fax horizontal shift)
                int[] finalPixels = pixels;
                int finalWidth = width;
                int finalHeight = height;

                if (_decoder.CurrentMode != null)
                {
                    finalPixels = _decoder.CurrentMode.PostProcessScopeImage(pixels, width, height);
                    int modeWidth = _decoder.CurrentMode.GetWidth();
                    if (finalPixels.Length != width * height && modeWidth > 0 && finalPixels.Length == modeWidth * height)
                    {
                        finalWidth = modeWidth;
                    }
                }

                Bitmap bmp = new Bitmap(finalWidth, finalHeight, PixelFormat.Format32bppArgb);
                BitmapData bmpData = bmp.LockBits(
                    new Rectangle(0, 0, finalWidth, finalHeight),
                    ImageLockMode.WriteOnly,
                    PixelFormat.Format32bppArgb);
                Marshal.Copy(finalPixels, 0, bmpData.Scan0, finalWidth * finalHeight);
                bmp.UnlockBits(bmpData);
                return bmp;
            }
            catch
            {
                return null;
            }
        }

        /// <summary>
        /// Extracts a partial image from the pixel buffer at full resolution.
        /// Decoded lines are filled in; remaining lines are black.
        /// Returns null if no lines have been decoded yet.
        /// Caller is responsible for disposing the returned Bitmap.
        /// </summary>
        public Bitmap GetPartialImage()
        {
            lock (_lock)
            {
                if (_imageBuffer == null || _imageBuffer.Line <= 0) return null;

                try
                {
                    int width = _imageBuffer.Width;
                    int fullHeight = _imageBuffer.Height;
                    int decodedLines = Math.Min(_imageBuffer.Line, fullHeight);
                    int[] pixels = _imageBuffer.Pixels;

                    if (width <= 0 || fullHeight <= 0 || pixels == null || pixels.Length < width * decodedLines)
                        return null;

                    // Create a full-size pixel array initialized to opaque black
                    int totalPixels = width * fullHeight;
                    int[] fullPixels = new int[totalPixels];
                    unchecked
                    {
                        int opaqueBlack = (int)0xFF000000;
                        for (int i = 0; i < totalPixels; i++) { fullPixels[i] = opaqueBlack; }
                    }

                    // Copy decoded lines into the full-size array
                    Array.Copy(pixels, 0, fullPixels, 0, width * decodedLines);

                    Bitmap bmp = new Bitmap(width, fullHeight, PixelFormat.Format32bppArgb);
                    BitmapData bmpData = bmp.LockBits(
                        new Rectangle(0, 0, width, fullHeight),
                        ImageLockMode.WriteOnly,
                        PixelFormat.Format32bppArgb);
                    Marshal.Copy(fullPixels, 0, bmpData.Scan0, totalPixels);
                    bmp.UnlockBits(bmpData);
                    return bmp;
                }
                catch
                {
                    return null;
                }
            }
        }

        public void Dispose()
        {
            _disposed = true;
            lock (_lock)
            {
                _decoder = null;
                _scopeBuffer = null;
                _imageBuffer = null;
            }
        }
    }
}
