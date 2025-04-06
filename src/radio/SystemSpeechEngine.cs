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

using System.IO;
using System.Threading;
using System.Collections.Generic;
using System.Speech.AudioFormat; // Requires reference to System.Speech assembly
using System.Speech.Recognition;
using System;

namespace HTCommander.radio
{
    public class SystemSpeechEngine : SpeechToText
	{
		private SpeechRecognitionEngine recognizer = null;
		private SpeechStreamer recognizerAudioStream = null;
		private string lastChannel;
		private DateTime firstFrame = DateTime.MinValue;

		public event RadioAudio.OnVoiceTextReady onFinalResultReady;
		public event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

		public void StartVoiceSegment()
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

		public void ResetVoiceSegment()
		{
			recognizerAudioStream.Close();
			recognizer.RecognizeAsyncStop();
			recognizer.Dispose();

			//Debug("Recognize Break");

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

		private void Recognizer_SpeechRecognized(object sender, SpeechRecognizedEventArgs e)
        {
            if (e.Result != null)
            {
				if (onFinalResultReady != null) { onFinalResultReady(e.Result.Text, lastChannel, firstFrame); }
				//Debug($"Recognized: {e.Result.Text} (Confidence: {e.Result.Confidence:P1})");
			}
			else
			{
				//Debug("Recognized: (null result)");
			}
		}

		private void Recognizer_RecognizeCompleted(object sender, RecognizeCompletedEventArgs e)
		{
			if (e.Error != null)
			{
				//Debug($"Completed with error: {e.Error.Message}");
			}
			else if (e.Cancelled)
			{
				//Debug("Recognition cancelled.");
			}
			else if (e.InputStreamEnded)
			{
				//Debug("Recognition completed (stream ended).");
			}
			else
			{
				//Debug("Recognition completed."); // Generic completion
			}
		}

		private void Recognizer_SpeechRecognitionRejected(object sender, SpeechRecognitionRejectedEventArgs e)
		{
			// NOP
		}

		public void ProcessAudioChunk(byte[] data, int index, int length, string channel)
		{
			if (firstFrame == DateTime.MinValue) { firstFrame = DateTime.Now; lastChannel = channel; }
            if (recognizerAudioStream != null) { recognizerAudioStream.Write(data, index, length); }
		}

		public void Dispose()
		{
			recognizerAudioStream.Close();
			recognizer.RecognizeAsyncStop();
			recognizer.Dispose();
			recognizerAudioStream = null;
			recognizer = null;
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

	}
}
