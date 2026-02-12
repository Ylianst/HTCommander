/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows.Forms;

namespace HTCommander
{
    /// <summary>
    /// Represents an audio clip that can be recorded and played back
    /// </summary>
    public class AudioClip
    {
        public string Name { get; set; }
        public string FileName { get; set; }
        public DateTime RecordedDate { get; set; }
        public TimeSpan Duration { get; set; }
        public long FileSize { get; set; }
        public float[] WaveformData { get; set; }
        
        // UI-related property (not serialized)
        [System.Text.Json.Serialization.JsonIgnore]
        public ListViewItem ListViewItem { get; set; }

        public AudioClip()
        {
            Name = "";
            FileName = "";
            RecordedDate = DateTime.Now;
            Duration = TimeSpan.Zero;
            FileSize = 0;
            WaveformData = new float[0];
        }

        public AudioClip(string name, string fileName)
        {
            Name = name;
            FileName = fileName;
            RecordedDate = DateTime.Now;
            Duration = TimeSpan.Zero;
            FileSize = 0;
            WaveformData = new float[0];
        }

        /// <summary>
        /// Gets the full file path for this clip
        /// </summary>
        public string GetFullPath()
        {
            string clipFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HTCommander",
                "AudioClips"
            );
            return Path.Combine(clipFolder, FileName);
        }

        /// <summary>
        /// Checks if the audio file exists on disk
        /// </summary>
        public bool FileExists()
        {
            return File.Exists(GetFullPath());
        }

        /// <summary>
        /// Gets a formatted duration string (MM:SS)
        /// </summary>
        public string GetDurationString()
        {
            return Duration.ToString(@"mm\:ss");
        }

        /// <summary>
        /// Gets a formatted file size string
        /// </summary>
        public string GetFileSizeString()
        {
            if (FileSize < 1024)
                return $"{FileSize} B";
            else if (FileSize < 1024 * 1024)
                return $"{FileSize / 1024} KB";
            else
                return $"{FileSize / (1024 * 1024)} MB";
        }
    }

    /// <summary>
    /// Manages audio clip storage, loading, and persistence
    /// </summary>
    public class AudioClipManager
    {
        private const string MetadataFileName = "clip_metadata.json";
        private string clipFolder;
        private string metadataPath;

        public List<AudioClip> Clips { get; private set; }

        public AudioClipManager()
        {
            clipFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HTCommander",
                "AudioClips"
            );
            metadataPath = Path.Combine(clipFolder, MetadataFileName);
            Clips = new List<AudioClip>();

            // Ensure the clip folder exists
            EnsureClipFolderExists();
        }

        /// <summary>
        /// Ensures the audio clips folder exists
        /// </summary>
        private void EnsureClipFolderExists()
        {
            if (!Directory.Exists(clipFolder))
            {
                Directory.CreateDirectory(clipFolder);
            }
        }

        /// <summary>
        /// Loads all clips from the metadata file
        /// </summary>
        public void LoadClips()
        {
            Clips.Clear();

            if (!File.Exists(metadataPath))
            {
                return;
            }

            try
            {
                string json = File.ReadAllText(metadataPath);
                var loadedClips = JsonSerializer.Deserialize<List<AudioClip>>(json);
                
                if (loadedClips != null)
                {
                    // Only add clips whose files actually exist
                    foreach (var clip in loadedClips)
                    {
                        if (clip.FileExists())
                        {
                            Clips.Add(clip);
                        }
                    }
                }
            }
            catch (Exception)
            {
                // If loading fails, start with empty list
                Clips.Clear();
            }
        }

        /// <summary>
        /// Saves all clips to the metadata file
        /// </summary>
        public void SaveClips()
        {
            try
            {
                EnsureClipFolderExists();
                
                var options = new JsonSerializerOptions
                {
                    WriteIndented = true
                };
                
                string json = JsonSerializer.Serialize(Clips, options);
                File.WriteAllText(metadataPath, json);
            }
            catch (Exception)
            {
                // Silently fail - clip files are still on disk
            }
        }

        /// <summary>
        /// Adds a new clip to the collection
        /// </summary>
        public void AddClip(AudioClip clip)
        {
            Clips.Add(clip);
            SaveClips();
        }

        /// <summary>
        /// Removes a clip from the collection and optionally deletes the file
        /// </summary>
        public void RemoveClip(AudioClip clip, bool deleteFile = true)
        {
            Clips.Remove(clip);
            
            if (deleteFile && clip.FileExists())
            {
                try
                {
                    File.Delete(clip.GetFullPath());
                }
                catch (Exception)
                {
                    // File deletion failed, but still remove from metadata
                }
            }
            
            SaveClips();
        }

        /// <summary>
        /// Renames a clip (updates metadata only, not the file)
        /// </summary>
        public bool RenameClip(AudioClip clip, string newName)
        {
            // Check for duplicate names
            if (Clips.Any(c => c != clip && c.Name.Equals(newName, StringComparison.OrdinalIgnoreCase)))
            {
                return false;
            }

            clip.Name = newName;
            SaveClips();
            return true;
        }

        /// <summary>
        /// Generates a unique default name for a new clip
        /// </summary>
        public string GenerateDefaultName()
        {
            int maxNumber = 0;
            
            foreach (var clip in Clips)
            {
                // Look for names like "Clip 001", "Clip 002", etc.
                if (clip.Name.StartsWith("Clip "))
                {
                    string numberPart = clip.Name.Substring(5).TrimStart();
                    if (int.TryParse(numberPart, out int number))
                    {
                        maxNumber = Math.Max(maxNumber, number);
                    }
                }
            }

            return $"Clip {(maxNumber + 1):D3}";
        }

        /// <summary>
        /// Generates a unique file name for a new clip
        /// </summary>
        public string GenerateFileName()
        {
            string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            string fileName = $"clip_{timestamp}.wav";
            
            // Ensure uniqueness
            int counter = 1;
            while (File.Exists(Path.Combine(clipFolder, fileName)))
            {
                fileName = $"clip_{timestamp}_{counter}.wav";
                counter++;
            }
            
            return fileName;
        }

        /// <summary>
        /// Gets the total size of all clip files
        /// </summary>
        public long GetTotalClipsSize()
        {
            return Clips.Sum(c => c.FileSize);
        }

        /// <summary>
        /// Validates a clip name
        /// </summary>
        public bool IsValidClipName(string name, AudioClip excludeClip = null)
        {
            if (string.IsNullOrWhiteSpace(name))
                return false;

            // Check for invalid characters
            char[] invalidChars = Path.GetInvalidFileNameChars();
            if (name.IndexOfAny(invalidChars) >= 0)
                return false;

            // Check for duplicate names
            if (Clips.Any(c => c != excludeClip && c.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
                return false;

            return true;
        }

        /// <summary>
        /// Gets the clips folder path
        /// </summary>
        public string GetClipsFolder()
        {
            return clipFolder;
        }
    }
}
