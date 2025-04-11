using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace HTCommander.radio
{
    // Class to hold progress information
    public class DownloadProgressInfo
    {
        public long BytesDownloaded { get; }
        public long? TotalBytes { get; }
        public double Percentage => TotalBytes.HasValue && TotalBytes > 0 ? (double)BytesDownloaded / TotalBytes.Value * 100.0 : 0;
        public bool IsComplete { get; }
        public bool IsCancelled { get; }
        public Exception Error { get; }

        // Constructor for progress updates
        public DownloadProgressInfo(long bytesDownloaded, long? totalBytes)
        {
            BytesDownloaded = bytesDownloaded;
            TotalBytes = totalBytes;
        }

        // Constructor for final states (completion, cancellation, error)
        public DownloadProgressInfo(long bytesDownloaded, long? totalBytes, bool isComplete = false, bool isCancelled = false, Exception error = null)
            : this(bytesDownloaded, totalBytes)
        {
            IsComplete = isComplete;
            IsCancelled = isCancelled;
            Error = error;
        }
    }

    public class FileDownloader : IDisposable
    {
        // HttpClient is intended to be instantiated once and re-used throughout the life of an application.
        // Instantiating an HttpClient class for every request will exhaust the number of sockets available under heavy loads.
        private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromDays(1) }; // Long timeout for large files

        private CancellationTokenSource _cts;

        /// <summary>
        /// Downloads a file asynchronously.
        /// </summary>
        /// <param name="url">The URL of the file to download.</param>
        /// <param name="outputPath">The full path where the file should be saved.</param>
        /// <param name="progress">Callback for reporting progress.</param>
        /// <param name="cancellationTokenSource">Token source for cancellation.</param>
        /// <returns>A task representing the asynchronous operation.</returns>
        public async Task DownloadFileAsync(string url, string outputPath, IProgress<DownloadProgressInfo> progress, CancellationTokenSource cancellationTokenSource)
        {
            _cts = cancellationTokenSource ?? throw new ArgumentNullException(nameof(cancellationTokenSource));
            var cancellationToken = _cts.Token;

            long totalBytesRead = 0;
            long? totalDownloadSize = null;
            bool downloadFinishedGracefully = false;

            try
            {
                // Ensure the directory exists
                string directory = Path.GetDirectoryName(outputPath);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // Send GET request, read headers first
                using (HttpResponseMessage response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
                {
                    response.EnsureSuccessStatusCode(); // Throw exception for non-success status codes (4xx, 5xx)

                    totalDownloadSize = response.Content.Headers.ContentLength;
                    progress?.Report(new DownloadProgressInfo(0, totalDownloadSize)); // Initial report with total size

                    // Get the response stream
                    using (Stream contentStream = await response.Content.ReadAsStreamAsync())
                    // Use FileStream with async option
                    using (FileStream fileStream = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None, bufferSize: 8192, useAsync: true))
                    {
                        byte[] buffer = new byte[8192]; // 8KB buffer
                        int bytesRead;

                        // Read from network stream and write to file stream asynchronously
                        while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken)) > 0)
                        {
                            await fileStream.WriteAsync(buffer, 0, bytesRead, cancellationToken);
                            totalBytesRead += bytesRead;

                            // Report progress
                            progress?.Report(new DownloadProgressInfo(totalBytesRead, totalDownloadSize));
                        }
                    }
                }

                // If loop completes without cancellation, report completion
                progress?.Report(new DownloadProgressInfo(totalBytesRead, totalDownloadSize, isComplete: true));
                downloadFinishedGracefully = true;
            }
            catch (OperationCanceledException) // Catch TaskCanceledException as well if using older .NET versions
            {
                // Cancellation requested
                progress?.Report(new DownloadProgressInfo(totalBytesRead, totalDownloadSize, isCancelled: true));
            }
            catch (HttpRequestException httpEx)
            {
                // Handle specific HTTP request errors (network issues, DNS errors, non-success status)
                progress?.Report(new DownloadProgressInfo(totalBytesRead, totalDownloadSize, error: httpEx));
            }
            catch (Exception ex)
            {
                // Handle other potential errors (e.g., file I/O errors)
                progress?.Report(new DownloadProgressInfo(totalBytesRead, totalDownloadSize, error: ex));
            }
            finally
            {
                // Clean up partially downloaded file if cancelled or errored
                if (!downloadFinishedGracefully && File.Exists(outputPath))
                {
                    try
                    {
                        File.Delete(outputPath);
                    }
                    catch (IOException ioEx)
                    {
                        // Log or report error during cleanup if necessary
                        Console.WriteLine($"Warning: Could not delete partial file '{outputPath}': {ioEx.Message}");
                    }
                }
            }
        }

        /// <summary>
        /// Requests cancellation of the current download operation.
        /// </summary>
        public void CancelDownload()
        {
            _cts?.Cancel();
        }

        /// <summary>
        /// Dispose the CancellationTokenSource if it exists.
        /// HttpClient is static and generally shouldn't be disposed here unless
        /// this class manages its lifecycle exclusively.
        /// </summary>
        public void Dispose()
        {
            _cts?.Dispose();
            // Do not dispose _httpClient here if it's static/shared
        }
    }
}