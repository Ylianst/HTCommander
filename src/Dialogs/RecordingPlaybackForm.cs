/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RecordingPlaybackForm : Form
    {
        private string _filePath;
        private NAudio.Wave.WaveFileReader _waveReader;
        private NAudio.Wave.WaveOutEvent _waveOut;
        private Timer _positionTimer;
        private bool _isPlaying = false;

        public RecordingPlaybackForm(string filePath)
        {
            InitializeComponent();
            _filePath = filePath;

            Text = "Recording - " + Path.GetFileName(filePath);
            fileNameLabel.Text = Path.GetFileName(filePath);

            // Set up position timer
            _positionTimer = new Timer();
            _positionTimer.Interval = 200;
            _positionTimer.Tick += PositionTimer_Tick;

            // Load file info
            try
            {
                using (var reader = new NAudio.Wave.WaveFileReader(_filePath))
                {
                    var duration = reader.TotalTime;
                    durationLabel.Text = FormatTimeSpan(duration);
                    positionLabel.Text = "00:00";
                    trackBar.Maximum = (int)duration.TotalSeconds;
                    trackBar.Value = 0;
                }
            }
            catch (Exception ex)
            {
                durationLabel.Text = "Error";
                MessageBox.Show("Failed to load recording: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void playButton_Click(object sender, EventArgs e)
        {
            if (_isPlaying)
            {
                StopPlayback();
            }
            else
            {
                StartPlayback();
            }
        }

        private void StartPlayback()
        {
            try
            {
                StopPlayback();

                _waveReader = new NAudio.Wave.WaveFileReader(_filePath);
                _waveOut = new NAudio.Wave.WaveOutEvent();
                _waveOut.Init(_waveReader);
                _waveOut.PlaybackStopped += WaveOut_PlaybackStopped;
                _waveOut.Play();

                _isPlaying = true;
                playButton.Text = "Stop";
                _positionTimer.Start();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Failed to play recording: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void StopPlayback()
        {
            _positionTimer.Stop();
            _isPlaying = false;

            if (_waveOut != null)
            {
                _waveOut.PlaybackStopped -= WaveOut_PlaybackStopped;
                _waveOut.Stop();
                _waveOut.Dispose();
                _waveOut = null;
            }

            if (_waveReader != null)
            {
                _waveReader.Dispose();
                _waveReader = null;
            }

            playButton.Text = "Play";
            positionLabel.Text = "00:00";
            trackBar.Value = 0;
        }

        private void WaveOut_PlaybackStopped(object sender, NAudio.Wave.StoppedEventArgs e)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => WaveOut_PlaybackStopped(sender, e)));
                return;
            }

            StopPlayback();
        }

        private void PositionTimer_Tick(object sender, EventArgs e)
        {
            if (_waveReader != null && _isPlaying)
            {
                var position = _waveReader.CurrentTime;
                positionLabel.Text = FormatTimeSpan(position);
                int posSeconds = (int)position.TotalSeconds;
                if (posSeconds <= trackBar.Maximum)
                {
                    trackBar.Value = posSeconds;
                }
            }
        }

        private void trackBar_Scroll(object sender, EventArgs e)
        {
            if (_waveReader != null && _isPlaying)
            {
                _waveReader.CurrentTime = TimeSpan.FromSeconds(trackBar.Value);
            }
        }

        private static string FormatTimeSpan(TimeSpan ts)
        {
            if (ts.TotalHours >= 1)
            {
                return ts.ToString(@"h\:mm\:ss");
            }
            return ts.ToString(@"mm\:ss");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                StopPlayback();
                _positionTimer?.Dispose();
                components?.Dispose();
            }
            base.Dispose(disposing);
        }

        /// <summary>
        /// Gets the full path to a recording file.
        /// </summary>
        public static string GetRecordingPath(string filename)
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HTCommander", "Recordings", filename);
        }
    }
}
