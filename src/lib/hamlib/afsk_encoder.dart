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
// afsk_encoder.dart - AFSK encoder for creating WAV files
//
// Ported from C# HamLib/AfskEncoder.cs
//

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'audio_buffer.dart';
import 'audio_config.dart';
import 'gen_tone.dart';
import 'hdlc_send.dart';
import 'wav_file.dart';

/// Encodes messages to AFSK audio in WAV format.
class AfskEncoder {
  late AudioConfig _audioConfig;
  late GenTone _genTone;
  late HdlcSend _hdlcSend;
  late AudioBuffer _audioBuffer;

  AfskEncoder() {
    // Set up default configuration for AFSK 1200 baud
    _configureFor1200Baud();
  }

  void _configureFor1200Baud() {
    _audioConfig = AudioConfig();
    _audioConfig.devices[0].defined = true;
    _audioConfig.devices[0].samplesPerSec = 44100;
    _audioConfig.devices[0].bitsPerSample = 16;
    _audioConfig.devices[0].numChannels = 1;

    _audioConfig.channelMedium[0] = Medium.radio;
    _audioConfig.channels[0].modemType = ModemType.afsk;
    _audioConfig.channels[0].markFreq = 1200;
    _audioConfig.channels[0].spaceFreq = 2200;
    _audioConfig.channels[0].baud = 1200;
    _audioConfig.channels[0].txdelay = 30; // 300ms
    _audioConfig.channels[0].txtail = 10; // 100ms

    _audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
    _genTone = GenTone(_audioBuffer);
    _genTone.init(_audioConfig, 50); // 50% amplitude

    _hdlcSend = HdlcSend(_genTone, _audioConfig);
  }

  void _configureFor9600Baud() {
    _audioConfig = AudioConfig();
    _audioConfig.devices[0].defined = true;
    _audioConfig.devices[0].samplesPerSec = 44100;
    _audioConfig.devices[0].bitsPerSample = 16;
    _audioConfig.devices[0].numChannels = 1;

    _audioConfig.channelMedium[0] = Medium.radio;
    _audioConfig.channels[0].modemType =
        ModemType.scramble; // Use scrambled baseband for 9600
    _audioConfig.channels[0].baud = 9600;
    _audioConfig.channels[0].txdelay = 30; // 300ms
    _audioConfig.channels[0].txtail = 10; // 100ms

    _audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
    _genTone = GenTone(_audioBuffer);
    _genTone.init(_audioConfig, 50); // 50% amplitude

    _hdlcSend = HdlcSend(_genTone, _audioConfig);
  }

  /// Encode a message to AFSK/9600 baud and save as WAV file.
  void encodeToWav(String message, String outputFile, [bool use9600 = false]) {
    // Reconfigure if needed
    if (use9600) {
      _configureFor9600Baud();
    } else {
      _configureFor1200Baud();
    }

    const int chan = 0;

    // Clear any previous data
    _audioBuffer.clearAll();

    // Create the frame data
    final Uint8List frameData = _createAx25Frame(message);

    // Generate preamble flags (txdelay)
    final int txdelayFlags = _audioConfig.channels[chan].txdelay;
    _hdlcSend.sendFlags(chan, txdelayFlags, false, null);

    // Send the actual frame
    _hdlcSend.sendFrame(chan, frameData, frameData.length, false);

    // Generate postamble flags (txtail)
    final int txtailFlags = _audioConfig.channels[chan].txtail;
    _hdlcSend.sendFlags(chan, txtailFlags, true, (device) {});

    // Get the audio samples
    final Int16List samples = _audioBuffer.getAndClear(0);

    // Write to WAV file
    final WavParams wavParams = WavParams()
      ..sampleRate = _audioConfig.devices[0].samplesPerSec
      ..bitsPerSample = _audioConfig.devices[0].bitsPerSample
      ..numChannels = _audioConfig.devices[0].numChannels;

    WavFile.write(outputFile, samples, wavParams);

    print('Encoded ${samples.length} samples to $outputFile');
    print(
      'Duration: ${WavFile.getDuration(samples, wavParams.sampleRate).toStringAsFixed(2)} seconds',
    );
    print('Baud rate: ${_audioConfig.channels[chan].baud}');
    print('Modulation: ${_audioConfig.channels[chan].modemType.name}');
  }

  /// Create a basic AX.25 UI frame.
  Uint8List _createAx25Frame(String message) {
    final List<int> frame = <int>[];

    // Destination address: "APRS" (typical APRS destination)
    _addAddress(frame, 'APRS', 0, false);

    // Source address: "NOCALL" with SSID 0
    _addAddress(frame, 'NOCALL', 0, true); // Last address bit set

    // Control field: 0x03 (UI frame)
    frame.add(0x03);

    // Protocol ID: 0xF0 (no layer 3)
    frame.add(0xF0);

    // Information field (the message)
    final List<int> messageBytes = ascii.encode(message);
    frame.addAll(messageBytes);

    return Uint8List.fromList(frame);
  }

  /// Add an AX.25 address to the frame.
  void _addAddress(List<int> frame, String callsign, int ssid, bool isLast) {
    // Pad callsign to 6 characters
    callsign = callsign.padRight(6, ' ').substring(0, 6);

    // Each character shifted left by 1
    for (final int c in callsign.codeUnits) {
      frame.add((c << 1) & 0xFF);
    }

    // SSID byte: bits 7-5 reserved (usually 011), bits 4-1 are SSID,
    // bit 0 is last address flag.
    int ssidByte = 0x60 | ((ssid & 0x0F) << 1);
    if (isLast) {
      ssidByte |= 0x01;
    }
    frame.add(ssidByte);
  }
}
