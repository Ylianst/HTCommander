/*
Copyright 2026 Ylian Saint-Hilaire

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

//
// wav_file.dart - WAV file reading and writing
//
// Ported from C# HamLib/WavFile.cs
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// WAV file parameters.
class WavParams {
  int sampleRate = 44100;
  int bitsPerSample = 16;
  int numChannels = 1;
}

/// Handles reading and writing of WAV audio files.
class WavFile {
  WavFile._();

  static const int _wavHeaderSize = 44;

  /// Write audio samples to a WAV file.
  static void write(String filename, Int16List samples, WavParams parameters) {
    final int dataSize = samples.length * 2;
    final int fileSize = _wavHeaderSize + dataSize - 8;

    final Uint8List out = Uint8List(_wavHeaderSize + dataSize);
    final ByteData bd = ByteData.view(out.buffer);

    // RIFF header
    out.setRange(0, 4, ascii.encode('RIFF'));
    bd.setInt32(4, fileSize, Endian.little);
    out.setRange(8, 12, ascii.encode('WAVE'));

    // fmt sub-chunk
    out.setRange(12, 16, ascii.encode('fmt '));
    bd.setInt32(16, 16, Endian.little); // Sub-chunk size (16 for PCM)
    bd.setInt16(20, 1, Endian.little); // Audio format (1 = PCM)
    bd.setInt16(22, parameters.numChannels, Endian.little);
    bd.setInt32(24, parameters.sampleRate, Endian.little);
    bd.setInt32(
      28,
      parameters.sampleRate *
          parameters.numChannels *
          parameters.bitsPerSample ~/
          8,
      Endian.little,
    ); // Byte rate
    bd.setInt16(
      32,
      parameters.numChannels * parameters.bitsPerSample ~/ 8,
      Endian.little,
    ); // Block align
    bd.setInt16(34, parameters.bitsPerSample, Endian.little);

    // data sub-chunk
    out.setRange(36, 40, ascii.encode('data'));
    bd.setInt32(40, dataSize, Endian.little);

    // Write sample data
    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(_wavHeaderSize + i * 2, samples[i], Endian.little);
    }

    File(filename).writeAsBytesSync(out);
  }

  /// Read audio samples from a WAV file.
  ///
  /// Returns a record of the decoded samples and the file parameters.
  static (Int16List samples, WavParams parameters) read(String filename) {
    final Uint8List bytes = File(filename).readAsBytesSync();
    final ByteData bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    int pos = 0;

    String readTag() {
      final String s = String.fromCharCodes(bytes, pos, pos + 4);
      pos += 4;
      return s;
    }

    int readInt32() {
      final int v = bd.getInt32(pos, Endian.little);
      pos += 4;
      return v;
    }

    int readInt16() {
      final int v = bd.getInt16(pos, Endian.little);
      pos += 2;
      return v;
    }

    // Read RIFF header
    final String riff = readTag();
    if (riff != 'RIFF') {
      throw const FormatException('Not a valid WAV file (missing RIFF header)');
    }

    readInt32(); // fileSize
    final String wave = readTag();
    if (wave != 'WAVE') {
      throw const FormatException('Not a valid WAV file (missing WAVE header)');
    }

    // Find the fmt sub-chunk. Some recorders (e.g. USB audio capture) insert a
    // JUNK padding chunk between WAVE and fmt, so scan past any non-fmt chunks.
    String fmt = readTag();
    int fmtSize = readInt32();
    while (fmt != 'fmt ' && pos < bytes.length) {
      pos += fmtSize + (fmtSize & 1); // chunks are word-aligned
      fmt = readTag();
      fmtSize = readInt32();
    }
    if (fmt != 'fmt ') {
      throw const FormatException('Not a valid WAV file (missing fmt header)');
    }

    final int audioFormat = readInt16();
    if (audioFormat != 1) {
      throw UnsupportedError('Only PCM format is supported');
    }

    final WavParams parameters = WavParams()
      ..numChannels = readInt16()
      ..sampleRate = readInt32();

    readInt32(); // byteRate
    readInt16(); // blockAlign
    parameters.bitsPerSample = readInt16();

    // Skip any extra format bytes
    if (fmtSize > 16) {
      pos += fmtSize - 16;
    }

    // Find data sub-chunk (there might be other chunks)
    String chunkId;
    int chunkSize;
    do {
      chunkId = readTag();
      chunkSize = readInt32();

      if (chunkId != 'data') {
        // Skip this chunk (word-aligned)
        pos += chunkSize + (chunkSize & 1);
      }
    } while (chunkId != 'data' && pos < bytes.length);

    if (chunkId != 'data') {
      throw const FormatException('No data chunk found in WAV file');
    }

    // Read sample data as interleaved frames.
    final int bytesPerSample = parameters.bitsPerSample ~/ 8;
    final int totalSamples = chunkSize ~/ bytesPerSample;

    final Int16List interleaved = Int16List(totalSamples);
    if (parameters.bitsPerSample == 16) {
      for (int i = 0; i < totalSamples; i++) {
        interleaved[i] = readInt16();
      }
    } else if (parameters.bitsPerSample == 8) {
      for (int i = 0; i < totalSamples; i++) {
        // Convert 8-bit unsigned to 16-bit signed
        final int b = bytes[pos++];
        interleaved[i] = (b - 128) * 256;
      }
    } else {
      throw UnsupportedError(
        'Bits per sample ${parameters.bitsPerSample} not supported',
      );
    }

    // Down-mix multi-channel audio to mono so the demodulators (which expect a
    // single stream) see one sample per frame at the file's sample rate.
    final int channels = parameters.numChannels < 1 ? 1 : parameters.numChannels;
    if (channels == 1) {
      return (interleaved, parameters);
    }

    final int frames = totalSamples ~/ channels;
    final Int16List samples = Int16List(frames);
    for (int f = 0; f < frames; f++) {
      int sum = 0;
      final int base = f * channels;
      for (int c = 0; c < channels; c++) {
        sum += interleaved[base + c];
      }
      samples[f] = (sum ~/ channels).clamp(-32768, 32767);
    }

    return (samples, parameters);
  }

  /// Get duration of a WAV file in seconds.
  static double getDuration(Int16List samples, int sampleRate) {
    return samples.length / sampleRate;
  }
}
