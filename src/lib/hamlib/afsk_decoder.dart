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
// afsk_decoder.dart - AFSK decoder
//
// Ported from C# HamLib/AfskDecoder.cs
//

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_config.dart';
import 'ax25_pad.dart';
import 'correction_info.dart';
import 'demod_9600.dart';
import 'demod_afsk.dart';
import 'fcs_calc.dart';
import 'fx25.dart';
import 'fx25_rec.dart';
import 'hdlc_rec.dart';
import 'hdlc_rec2.dart';
import 'ihdlc_receiver.dart';
import 'multi_modem.dart';
import 'wav_file.dart';

/// Format a byte as a two-digit uppercase hex string.
String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

/// Decodes AFSK audio from WAV files using the ported demodulator components.
class AfskDecoder {
  final PacketCollector _packetCollector;
  late HdlcRecWithCollector _hdlcRecCollector;
  double _errorRate = 0.0;
  final math.Random _random = math.Random();
  final int _totalBits = 0;
  final int _flippedBits = 0;

  AfskDecoder() : _packetCollector = PacketCollector();

  /// Set the bit error rate for testing error correction.
  void setErrorRate(double errorRate) {
    _errorRate = math.max(0.0, math.min(1.0, errorRate));
  }

  /// Get statistics on bit flipping.
  (int total, int flipped) getBitErrorStats() {
    return (_totalBits, _flippedBits);
  }

  /// Event handler for displaying frames as they are received.
  void _onFrameReceived(FrameReceivedEventArgs e) {
    // Create packet from frame
    final ALevel alevel =
        ALevel(e.audioLevel.rec, e.audioLevel.mark, e.audioLevel.space);
    final Packet? packet = Packet.fromFrame(e.frame, e.frameLength, alevel);

    if (packet != null && packet.isAprs()) {
      // Display decoded message
      stdout.writeln('**Source: ${packet.getAddrWithSsid(Ax25Constants.source)}');
      stdout.writeln('  Destination: ${packet.getAddrWithSsid(Ax25Constants.destination)}');

      // Display correction information if available
      final CorrectionInfo? ci = e.correctionInfo;
      if (ci != null && ci.correctionType != RetryType.none) {
        String correctionMsg;
        switch (ci.correctionType) {
          case RetryType.invertSingle:
            correctionMsg =
                'Corrected 1 bit (position ${ci.correctedBitPositions.join(", ")})';
            break;
          case RetryType.invertDouble:
            correctionMsg =
                'Corrected 2 adjacent bits (positions ${ci.correctedBitPositions.join(", ")})';
            break;
          case RetryType.invertTriple:
            correctionMsg =
                'Corrected 3 adjacent bits (positions ${ci.correctedBitPositions.join(", ")})';
            break;
          case RetryType.invertTwoSep:
            correctionMsg =
                'Corrected 2 separated bits (positions ${ci.correctedBitPositions.join(", ")})';
            break;
          default:
            correctionMsg = 'Unknown correction applied';
            break;
        }
        stdout.writeln('  Fix Applied: $correctionMsg');
      } else {
        stdout.writeln('  Fix Applied: No correction needed (CRC valid)');
      }

      // Extract and display message
      final Uint8List info = packet.getInfo();
      final int infoLen = info.length;
      final StringBuffer message = StringBuffer();
      for (int i = 0; i < infoLen; i++) {
        if (info[i] >= 32 && info[i] <= 126) {
          message.writeCharCode(info[i]);
        }
      }

      stdout.writeln('  Message: ${message.toString()}');
    }
  }

  /// Decode AFSK audio from WAV file with debug output.
  String? decodeFromWavWithDebug(String inputFile) {
    try {
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln('                  AFSK DECODER - STARTING');
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln();

      // Read the WAV file
      stdout.writeln('[STEP 1] Reading WAV file...');
      final (samples, wavParams) = WavFile.read(inputFile);

      stdout.writeln('  ✓ Read ${samples.length} samples from $inputFile');
      stdout.writeln('  ✓ Sample rate: ${wavParams.sampleRate} Hz');
      stdout.writeln('  ✓ Duration: ${WavFile.getDuration(samples, wavParams.sampleRate).toStringAsFixed(2)} seconds');
      stdout.writeln('  ✓ First few samples: ${samples[0]}, ${samples[1]}, ${samples[2]}, ${samples[3]}, ${samples[4]}');
      stdout.writeln();

      // Setup audio configuration
      stdout.writeln('[STEP 2] Configuring AFSK demodulator...');
      final AudioConfig audioConfig = AudioConfig();
      audioConfig.devices[0].defined = true;
      audioConfig.devices[0].samplesPerSec = wavParams.sampleRate;
      audioConfig.devices[0].bitsPerSample = wavParams.bitsPerSample;
      audioConfig.devices[0].numChannels = wavParams.numChannels;

      // Configure for AFSK 1200 baud
      audioConfig.channelMedium[0] = Medium.radio;
      audioConfig.channels[0].modemType = ModemType.afsk;
      audioConfig.channels[0].markFreq = 1200;
      audioConfig.channels[0].spaceFreq = 2200;
      audioConfig.channels[0].baud = 1200;
      audioConfig.channels[0].numSubchan = 1;

      stdout.writeln('  ✓ Modem: AFSK 1200 baud');
      stdout.writeln('  ✓ Mark frequency: 1200 Hz');
      stdout.writeln('  ✓ Space frequency: 2200 Hz');
      stdout.writeln();

      // Create HDLC receiver with packet collector
      stdout.writeln('[STEP 3] Initializing HDLC receiver...');
      final HdlcRecWithCollector hdlcRecCollector =
          HdlcRecWithCollector(_packetCollector, debugMode: true);
      hdlcRecCollector.init(audioConfig);
      stdout.writeln('  ✓ HDLC receiver initialized');
      stdout.writeln();

      // Create and initialize demodulator with error injection if configured
      stdout.writeln('[STEP 4] Initializing AFSK demodulator (Profile A)...');
      IHdlcReceiver receiver = hdlcRecCollector.getHdlcRec();
      if (_errorRate > 0.0) {
        receiver = BitErrorInjector(
            receiver, _errorRate, _random, _totalBits, _flippedBits);
        stdout.writeln('  ✓ Bit error injection enabled at ${(_errorRate * 100).toStringAsFixed(5)}%');
      }
      final DemodAfsk demodAfsk = DemodAfsk(receiver);
      final DemodulatorState demodState = DemodulatorState();
      demodAfsk.init(
        wavParams.sampleRate,
        audioConfig.channels[0].baud,
        audioConfig.channels[0].markFreq,
        audioConfig.channels[0].spaceFreq,
        'A',
        demodState,
      );
      stdout.writeln('  ✓ Demodulator initialized');
      stdout.writeln('  ✓ PLL step per sample: ${demodState.pllStepPerSample}');
      stdout.writeln('  ✓ Low-pass filter taps: ${demodState.lpFilterTaps}');
      stdout.writeln();

      // Process all samples
      stdout.writeln('[STEP 5] Processing audio samples...');
      stdout.writeln('  Processing ${samples.length} samples...');
      const int chan = 0;
      const int subchan = 0;

      for (int i = 0; i < samples.length; i++) {
        demodAfsk.processSample(chan, subchan, samples[i], demodState);

        // Progress indicator every 10000 samples
        if ((i + 1) % 10000 == 0) {
          final double progress = (i + 1) * 100.0 / samples.length;
          stdout.write('\r  Progress: ${progress.toStringAsFixed(1)}% (${i + 1}/${samples.length} samples)');
        }
      }
      stdout.writeln('\r  ✓ Completed: 100.0% (${samples.length}/${samples.length} samples)');
      stdout.writeln();

      // Check for collected packets
      stdout.writeln('[STEP 6] Checking for decoded packets...');
      final List<Packet> packets = _packetCollector.getPackets();

      stdout.writeln('  Found ${packets.length} packet(s)');

      // Display bit error statistics if error injection was enabled
      if (_errorRate > 0.0) {
        stdout.writeln();
        stdout.writeln('Bit Error Statistics:');
        stdout.writeln('  Total bits processed: $_totalBits');
        stdout.writeln('  Bits flipped: $_flippedBits');
        stdout.writeln('  Actual error rate: ${(_totalBits > 0 ? (_flippedBits * 100.0 / _totalBits) : 0.0).toStringAsFixed(5)}%');
      }
      stdout.writeln();

      // Display all bits received by HDLC decoder (RAW bits before NRZI)
      final List<int> allBits = hdlcRecCollector.getHdlcRec().getAllReceivedBits();
      stdout.writeln('[BIT DUMP] Total RAW bits received by HDLC decoder: ${allBits.length}');

      // Display NRZI decoded bits
      final List<int> decodedBits =
          hdlcRecCollector.getHdlcRec().getAllDecodedBits();
      stdout.writeln('[BIT DUMP] Total bits after NRZI decoding: ${decodedBits.length}');
      stdout.writeln();

      if (allBits.isNotEmpty) {
        stdout.writeln('════════════════════════════════════════════════════════════');
        stdout.writeln('         RAW BITS SENT TO HDLC DECODER (before NRZI)');
        stdout.writeln('════════════════════════════════════════════════════════════');
        stdout.writeln();

        // Display as binary (80 bits per line)
        stdout.writeln('Binary format (80 bits per line, with spaces every 8 bits):');
        stdout.writeln();
        for (int i = 0; i < allBits.length; i++) {
          stdout.write(allBits[i]);
          if ((i + 1) % 80 == 0) {
            stdout.writeln('  // Bits ${i - 79} to $i');
          } else if ((i + 1) % 8 == 0) {
            stdout.write(' ');
          }
        }
        if (allBits.length % 80 != 0) {
          stdout.writeln('  // Bits ${(allBits.length ~/ 80) * 80} to ${allBits.length - 1}');
        }
        stdout.writeln();

        // Display as hex bytes
        stdout.writeln('Hex format (bytes, 16 per line):');
        stdout.writeln();
        int byteCount = 0;
        for (int i = 0; i + 7 < allBits.length; i += 8) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            byteVal = (byteVal << 1) | allBits[i + bit];
          }
          stdout.write('${_hex2(byteVal)} ');
          byteCount++;
          if (byteCount % 16 == 0) {
            stdout.writeln(' // Bytes ${byteCount - 15} to $byteCount');
          }
        }
        if (byteCount % 16 != 0) {
          stdout.writeln(' // Bytes ${(byteCount ~/ 16) * 16 + 1} to $byteCount');
        }
        stdout.writeln();
        stdout.writeln('Total: $byteCount complete bytes (${allBits.length} bits)');

        // Show first 16 bytes as ASCII if printable
        stdout.writeln();
        stdout.writeln('First bytes as ASCII (if printable):');
        for (int i = 0; i + 7 < math.min(allBits.length, 128); i += 8) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            byteVal = (byteVal << 1) | allBits[i + bit];
          }
          final int c = byteVal;
          if (c >= 32 && c <= 126) {
            stdout.write(String.fromCharCode(c));
          } else {
            stdout.write('[${_hex2(byteVal)}]');
          }
        }
        stdout.writeln();
        stdout.writeln();
      }

      // Display NRZI decoded bits
      if (decodedBits.isNotEmpty) {
        stdout.writeln('════════════════════════════════════════════════════════════');
        stdout.writeln('         BITS AFTER NRZI DECODING (HDLC bit stream)');
        stdout.writeln('════════════════════════════════════════════════════════════');
        stdout.writeln();

        // Display as binary (80 bits per line)
        stdout.writeln('Binary format (80 bits per line, with spaces every 8 bits):');
        stdout.writeln();
        for (int i = 0; i < decodedBits.length; i++) {
          stdout.write(decodedBits[i]);
          if ((i + 1) % 80 == 0) {
            stdout.writeln('  // Bits ${i - 79} to $i');
          } else if ((i + 1) % 8 == 0) {
            stdout.write(' ');
          }
        }
        if (decodedBits.length % 80 != 0) {
          stdout.writeln('  // Bits ${(decodedBits.length ~/ 80) * 80} to ${decodedBits.length - 1}');
        }
        stdout.writeln();

        // Display as hex bytes
        stdout.writeln('Hex format (bytes, 16 per line):');
        stdout.writeln();
        int decodedByteCount = 0;
        for (int i = 0; i + 7 < decodedBits.length; i += 8) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            byteVal = (byteVal << 1) | decodedBits[i + bit];
          }
          stdout.write('${_hex2(byteVal)} ');
          decodedByteCount++;
          if (decodedByteCount % 16 == 0) {
            stdout.writeln(' // Bytes ${decodedByteCount - 15} to $decodedByteCount');
          }
        }
        if (decodedByteCount % 16 != 0) {
          stdout.writeln(' // Bytes ${(decodedByteCount ~/ 16) * 16 + 1} to $decodedByteCount');
        }
        stdout.writeln();
        stdout.writeln('Total: $decodedByteCount complete bytes (${decodedBits.length} bits)');

        // Show first bytes as ASCII if printable
        stdout.writeln();
        stdout.writeln('First bytes as ASCII (if printable):');
        for (int i = 0; i + 7 < math.min(decodedBits.length, 128); i += 8) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            byteVal = (byteVal << 1) | decodedBits[i + bit];
          }
          final int c = byteVal;
          if (c >= 32 && c <= 126) {
            stdout.write(String.fromCharCode(c));
          } else {
            stdout.write('[${_hex2(byteVal)}]');
          }
        }
        stdout.writeln();

        // Look for HDLC flag patterns (0x7E = 01111110)
        stdout.writeln();
        stdout.writeln('HDLC Flag Pattern Analysis (looking for 0x7E = 01111110):');
        for (int i = 0; i + 7 < decodedBits.length; i += 8) {
          // ignore: unused_local_variable
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            byteVal = (byteVal << 1) | decodedBits[i + bit];
          }
        }
        stdout.writeln();
        stdout.writeln();
      }

      // Extract message from first packet
      final Packet packet = packets[0];
      final Uint8List info = packet.getInfo();
      final int infoLen = info.length;

      // Convert to string, removing control bytes
      final StringBuffer message = StringBuffer();
      for (int i = 0; i < infoLen; i++) {
        if (info[i] >= 32 && info[i] <= 126) {
          message.writeCharCode(info[i]);
        }
      }

      final String result = message.toString();

      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln('                  DECODE SUCCESSFUL!');
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln();
      stdout.writeln('  Packets decoded: ${packets.length}');
      stdout.writeln('  Source: ${packet.getAddrWithSsid(Ax25Constants.source)}');
      stdout.writeln('  Destination: ${packet.getAddrWithSsid(Ax25Constants.destination)}');
      stdout.writeln('  Message length: $infoLen bytes');
      stdout.writeln();
      stdout.writeln('  Message: $result');
      stdout.writeln();

      return result;
    } catch (ex, st) {
      stdout.writeln('Error decoding file: $ex');
      stdout.writeln('$st');
      return null;
    }
  }

  /// Decode AFSK audio from WAV file (without debug messages).
  String? decodeFromWav(String inputFile, [bool use9600 = false]) {
    try {
      // Read the WAV file
      final (samples, wavParams) = WavFile.read(inputFile);

      // Setup audio configuration
      final AudioConfig audioConfig = AudioConfig();
      audioConfig.devices[0].defined = true;
      audioConfig.devices[0].samplesPerSec = wavParams.sampleRate;
      audioConfig.devices[0].bitsPerSample = wavParams.bitsPerSample;
      audioConfig.devices[0].numChannels = wavParams.numChannels;

      // Configure for selected baud rate
      audioConfig.channelMedium[0] = Medium.radio;
      if (use9600) {
        audioConfig.channels[0].modemType = ModemType.scramble;
        audioConfig.channels[0].baud = 9600;
      } else {
        audioConfig.channels[0].modemType = ModemType.afsk;
        audioConfig.channels[0].markFreq = 1200;
        audioConfig.channels[0].spaceFreq = 2200;
        audioConfig.channels[0].baud = 1200;
      }
      audioConfig.channels[0].numSubchan = 1;

      // Create HDLC receiver with packet collector and register for frame events
      _hdlcRecCollector =
          HdlcRecWithCollector(_packetCollector, debugMode: false);
      _hdlcRecCollector.getHdlcRec().addFrameReceived(_onFrameReceived);
      _hdlcRecCollector.init(audioConfig);

      // Create and initialize demodulator with error injection if configured
      IHdlcReceiver receiver = _hdlcRecCollector.getHdlcRec();
      if (_errorRate > 0.0) {
        receiver = BitErrorInjector(
            receiver, _errorRate, _random, _totalBits, _flippedBits);
      }

      const int chan = 0;
      const int subchan = 0;

      if (use9600) {
        // Use 9600 baud baseband demodulator
        final DemodulatorState demodState = DemodulatorState();
        final Demod9600State state9600 = Demod9600State();

        const int upsample = 1; // No upsampling for now
        Demod9600.init(wavParams.sampleRate, upsample,
            audioConfig.channels[0].baud, demodState, state9600);

        // Process all samples with 9600 baud demodulator
        for (int i = 0; i < samples.length; i++) {
          Demod9600.processSample(
              chan, samples[i], upsample, demodState, state9600, receiver);
        }
      } else {
        // Use AFSK 1200 baud demodulator
        final DemodAfsk demodAfsk = DemodAfsk(receiver);
        final DemodulatorState demodState = DemodulatorState();
        demodAfsk.init(
          wavParams.sampleRate,
          audioConfig.channels[0].baud,
          audioConfig.channels[0].markFreq,
          audioConfig.channels[0].spaceFreq,
          'A',
          demodState,
        );

        // Process all samples with AFSK demodulator
        for (int i = 0; i < samples.length; i++) {
          demodAfsk.processSample(chan, subchan, samples[i], demodState);
        }
      }

      // Display bit error statistics if error injection was enabled
      if (_errorRate > 0.0 && _totalBits > 0) {
        stdout.writeln();
        stdout.writeln('Bit Error Statistics:');
        stdout.writeln('  Total bits processed: $_totalBits');
        stdout.writeln('  Bits flipped: $_flippedBits');
        stdout.writeln('  Actual error rate: ${(_flippedBits * 100.0 / _totalBits).toStringAsFixed(5)}%');
        stdout.writeln();
      }

      // Return first decoded message if available
      final List<Packet> packets = _packetCollector.getPackets();
      if (packets.isNotEmpty) {
        final Packet packet = packets[0];
        final Uint8List info = packet.getInfo();
        final int infoLen = info.length;

        // Convert to string, removing control bytes
        final StringBuffer message = StringBuffer();
        for (int i = 0; i < infoLen; i++) {
          if (info[i] >= 32 && info[i] <= 126) {
            message.writeCharCode(info[i]);
          }
        }

        return message.toString();
      }

      return null;
    } catch (ex) {
      stdout.writeln('Error decoding file: $ex');
      return null;
    }
  }

  /// Decode AFSK audio from WAV file with FX.25 error correction support.
  String? decodeFromWavFx25(String inputFile, [bool use9600 = false]) {
    try {
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln('            AFSK DECODER - FX.25 MODE (WITH FEC)');
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln();

      // Initialize FX.25 subsystem with debug level 3 (maximum verbosity)
      stdout.writeln('[STEP 1] Initializing FX.25 subsystem...');
      Fx25.init(3);
      stdout.writeln('  ✓ FX.25 error correction enabled');
      stdout.writeln('  ✓ Reed-Solomon codecs initialized');
      stdout.writeln('  ✓ Debug level: ${Fx25.getDebugLevel()}');
      stdout.writeln();

      // Read the WAV file
      stdout.writeln('[STEP 2] Reading WAV file...');
      final (samples, wavParams) = WavFile.read(inputFile);

      stdout.writeln('  ✓ Read ${samples.length} samples from $inputFile');
      stdout.writeln('  ✓ Sample rate: ${wavParams.sampleRate} Hz');
      stdout.writeln('  ✓ Duration: ${WavFile.getDuration(samples, wavParams.sampleRate).toStringAsFixed(2)} seconds');
      stdout.writeln();

      // Setup audio configuration
      stdout.writeln('[STEP 3] Configuring demodulator...');
      final AudioConfig audioConfig = AudioConfig();
      audioConfig.devices[0].defined = true;
      audioConfig.devices[0].samplesPerSec = wavParams.sampleRate;
      audioConfig.devices[0].bitsPerSample = wavParams.bitsPerSample;
      audioConfig.devices[0].numChannels = wavParams.numChannels;

      // Configure for selected baud rate
      audioConfig.channelMedium[0] = Medium.radio;
      if (use9600) {
        audioConfig.channels[0].modemType = ModemType.scramble;
        audioConfig.channels[0].baud = 9600;
        stdout.writeln('  ✓ Modem: 9600 baud (baseband/scrambled)');
      } else {
        audioConfig.channels[0].modemType = ModemType.afsk;
        audioConfig.channels[0].markFreq = 1200;
        audioConfig.channels[0].spaceFreq = 2200;
        audioConfig.channels[0].baud = 1200;
        stdout.writeln('  ✓ Modem: AFSK 1200 baud');
        stdout.writeln('  ✓ Mark frequency: 1200 Hz');
        stdout.writeln('  ✓ Space frequency: 2200 Hz');
      }
      audioConfig.channels[0].numSubchan = 1;
      stdout.writeln();

      // Create MultiModem for packet collection with FX.25 support
      stdout.writeln('[STEP 4] Initializing FX.25 receiver chain...');
      final MultiModem multiModem = MultiModem();
      multiModem.init(audioConfig);

      // Set up packet collector using event handler
      final Fx25PacketCollector fx25PacketCollector = Fx25PacketCollector();
      multiModem.addPacketReady((e) {
        if (e.packet != null) {
          // Store packet, FEC type, correlation tag, and errors corrected
          final int errorsCorrected =
              (e.fecType == FecType.fx25) ? e.retries : 0;
          fx25PacketCollector.addPacket(
              e.packet!, e.fecType, e.ctagNum, errorsCorrected);

          // Display correlation tag info immediately
          if (e.fecType == FecType.fx25) {
            stdout.writeln('  [FX.25] Packet received with FEC (correlation tag 0x${_hex2(e.ctagNum)}, $errorsCorrected errors corrected)');
          } else {
            stdout.writeln('  [AX.25] Packet received without FEC (plain AX.25)');
          }
        }
      });

      stdout.writeln('  ✓ FX.25 receiver initialized');
      stdout.writeln('  ✓ Ready to decode frames with error correction');
      stdout.writeln();

      // Create FX.25 receiver that connects to MultiModem
      stdout.writeln('[STEP 5] Initializing AFSK demodulator with BOTH AX.25 and FX.25...');
      final Fx25Rec fx25Rec = Fx25Rec(multiModem);

      // Create HDLC receiver for plain AX.25 frames
      final HdlcRec2 hdlcRec = HdlcRec2();
      hdlcRec.init(audioConfig);

      // Connect HDLC receiver to MultiModem for plain AX.25 packets
      hdlcRec.addFrameReceived((e) {
        final ALevel alevel =
            ALevel(e.audioLevel.rec, e.audioLevel.mark, e.audioLevel.space);
        final Packet? packet = Packet.fromFrame(e.frame, e.frameLength, alevel);
        if (packet != null) {
          // Check if bit correction was applied
          String correctionMsg =
              '  [AX.25] Packet received without FEC (plain AX.25)';
          final CorrectionInfo? ci = e.correctionInfo;
          if (ci != null && ci.correctionType != RetryType.none) {
            correctionMsg +=
                ' with ${ci.correctedBitPositions.length} bit(s) corrected';
          }

          fx25PacketCollector.addPacket(
              packet, FecType.none, -1, 0, e.correctionInfo);
          stdout.writeln(correctionMsg);
        }
      });

      stdout.writeln('  ✓ AX.25 and FX.25 decoders initialized');
      if (_errorRate > 0.0) {
        stdout.writeln('  ✓ Bit error injection enabled at ${(_errorRate * 100).toStringAsFixed(5)}%');
      }

      // Create dual receiver wrapper that feeds bits to both HDLC and FX.25
      IHdlcReceiver dualReceiver = HdlcRecWithFx25Nrzi(hdlcRec, fx25Rec);

      // Wrap with bit error injector if configured
      if (_errorRate > 0.0) {
        dualReceiver = BitErrorInjector(
            dualReceiver, _errorRate, _random, _totalBits, _flippedBits);
      }

      stdout.writeln('  ✓ Demodulator initialized');
      stdout.writeln();

      // Process all samples
      stdout.writeln('[STEP 6] Processing audio samples...');
      stdout.writeln('  Processing ${samples.length} samples...');
      const int chan = 0;
      const int subchan = 0;

      if (use9600) {
        // Use 9600 baud demodulator
        final DemodulatorState demodState = DemodulatorState();
        final Demod9600State state9600 = Demod9600State();

        const int upsample = 1; // No upsampling for now
        Demod9600.init(wavParams.sampleRate, upsample,
            audioConfig.channels[0].baud, demodState, state9600);

        for (int i = 0; i < samples.length; i++) {
          Demod9600.processSample(
              chan, samples[i], upsample, demodState, state9600, dualReceiver);

          // Progress indicator every 10000 samples
          if ((i + 1) % 10000 == 0) {
            final double progress = (i + 1) * 100.0 / samples.length;
            stdout.write('\r  Progress: ${progress.toStringAsFixed(1)}% (${i + 1}/${samples.length} samples)');
          }
        }
      } else {
        // Use AFSK 1200 baud demodulator
        final DemodAfsk demodAfsk = DemodAfsk(dualReceiver);
        final DemodulatorState demodState = DemodulatorState();
        demodAfsk.init(
          wavParams.sampleRate,
          audioConfig.channels[0].baud,
          audioConfig.channels[0].markFreq,
          audioConfig.channels[0].spaceFreq,
          'A',
          demodState,
        );

        for (int i = 0; i < samples.length; i++) {
          demodAfsk.processSample(chan, subchan, samples[i], demodState);

          // Progress indicator every 10000 samples
          if ((i + 1) % 10000 == 0) {
            final double progress = (i + 1) * 100.0 / samples.length;
            stdout.write('\r  Progress: ${progress.toStringAsFixed(1)}% (${i + 1}/${samples.length} samples)');
          }
        }
      }
      stdout.writeln('\r  ✓ Completed: 100.0% (${samples.length}/${samples.length} samples)');
      stdout.writeln();

      // Check for collected packets
      stdout.writeln('[STEP 7] Checking for decoded packets...');
      final List<Packet> packets = fx25PacketCollector.getPackets();

      stdout.writeln('  Found ${packets.length} packet(s)');

      // Display bit error statistics if error injection was enabled
      if (_errorRate > 0.0 && _totalBits > 0) {
        stdout.writeln();
        stdout.writeln('Bit Error Statistics:');
        stdout.writeln('  Total bits processed: $_totalBits');
        stdout.writeln('  Bits flipped: $_flippedBits');
        stdout.writeln('  Actual error rate: ${(_flippedBits * 100.0 / _totalBits).toStringAsFixed(5)}%');
      }
      stdout.writeln();

      if (packets.isEmpty) {
        stdout.writeln('No packets decoded.');
        return null;
      }

      // Display results for all packets
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln('              FX.25 DECODE SUCCESSFUL!');
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln();

      final StringBuffer allMessages = StringBuffer();

      int fecCount = 0;
      int plainCount = 0;

      for (int i = 0; i < packets.length; i++) {
        final Packet packet = packets[i];
        final FecType fecType = fx25PacketCollector.getFecType(i);
        final Uint8List info = packet.getInfo();
        final int infoLen = info.length;

        // Count FEC vs plain packets
        if (fecType == FecType.fx25) {
          fecCount++;
        } else {
          plainCount++;
        }

        // Convert to string, removing control bytes
        final StringBuffer message = StringBuffer();
        for (int j = 0; j < infoLen; j++) {
          if (info[j] >= 32 && info[j] <= 126) {
            message.writeCharCode(info[j]);
          }
        }

        final String result = message.toString();
        if (allMessages.isNotEmpty) {
          allMessages.write(' | ');
        }
        allMessages.write(result);

        stdout.writeln('[PACKET ${i + 1}]');

        // Display FEC status, correlation tag, and errors corrected
        if (fecType == FecType.fx25) {
          final int ctagNum = fx25PacketCollector.getCtagNum(i);
          final int errorsCorrected =
              fx25PacketCollector.getErrorsCorrected(i);
          stdout.writeln('  FEC Type: FX.25 (with error correction)');
          if (ctagNum >= 0) {
            stdout.writeln('  Correlation Tag: 0x${_hex2(ctagNum)}');
          }
          if (errorsCorrected > 0) {
            stdout.writeln('  Fix Applied: Corrected $errorsCorrected Reed-Solomon symbol(s)');
          } else {
            stdout.writeln('  Fix Applied: No errors detected (clean reception)');
          }
        } else {
          stdout.writeln('  FEC Type: None (plain AX.25)');

          // Check if bit correction was applied
          final CorrectionInfo? correctionInfo =
              fx25PacketCollector.getCorrectionInfo(i);
          if (correctionInfo != null &&
              correctionInfo.correctionType != RetryType.none) {
            String correctionMsg;
            switch (correctionInfo.correctionType) {
              case RetryType.invertSingle:
                correctionMsg =
                    'Corrected 1 bit (position ${correctionInfo.correctedBitPositions.join(", ")})';
                break;
              case RetryType.invertDouble:
                correctionMsg =
                    'Corrected 2 adjacent bits (positions ${correctionInfo.correctedBitPositions.join(", ")})';
                break;
              case RetryType.invertTriple:
                correctionMsg =
                    'Corrected 3 adjacent bits (positions ${correctionInfo.correctedBitPositions.join(", ")})';
                break;
              case RetryType.invertTwoSep:
                correctionMsg =
                    'Corrected 2 separated bits (positions ${correctionInfo.correctedBitPositions.join(", ")})';
                break;
              default:
                correctionMsg = 'Unknown correction applied';
                break;
            }
            stdout.writeln('  Fix Applied: $correctionMsg');
          } else {
            stdout.writeln('  Fix Applied: No correction needed (CRC valid)');
          }
        }

        stdout.writeln('  Source: ${packet.getAddrWithSsid(Ax25Constants.source)}');
        stdout.writeln('  Destination: ${packet.getAddrWithSsid(Ax25Constants.destination)}');
        stdout.writeln('  Message length: $infoLen bytes');
        stdout.writeln('  Message: $result');
        stdout.writeln();
      }

      stdout.writeln('Total packets: ${packets.length} ($fecCount with FX.25 FEC, $plainCount plain AX.25)');
      stdout.writeln();

      return allMessages.toString();
    } catch (ex, st) {
      stdout.writeln('Error decoding file: $ex');
      stdout.writeln('$st');
      return null;
    }
  }

  /// Verify FCS of a frame.
  static bool verifyFcs(Uint8List frame, int length) {
    if (length < 2) return false;

    // Calculate FCS on all but last 2 bytes
    final int calculated = FcsCalc.calculate(frame, length - 2);

    // Extract FCS from last 2 bytes
    final int received = (frame[length - 2] | (frame[length - 1] << 8)) & 0xFFFF;

    return calculated == received;
  }

  /// Parse AX.25 address field.
  static String parseAddress(Uint8List addressBytes) {
    if (addressBytes.length != 7) return 'INVALID';

    final StringBuffer callsign = StringBuffer();

    // Extract callsign (first 6 bytes, shifted right by 1)
    for (int i = 0; i < 6; i++) {
      final int c = addressBytes[i] >> 1;
      if (c != 32) {
        callsign.writeCharCode(c);
      }
    }

    // Extract SSID from 7th byte
    final int ssid = (addressBytes[6] >> 1) & 0x0F;
    if (ssid != 0) {
      callsign.write('-');
      callsign.write(ssid);
    }

    return callsign.toString();
  }
}

/// Bit error injector wrapper - flips bits randomly at a specified rate.
class BitErrorInjector implements IHdlcReceiver {
  final IHdlcReceiver _innerReceiver;
  final double _errorRate;
  final math.Random _random;
  // These mirror the C# fields. The original `ref` parameters were never
  // written back, so the counts stay local; they are accumulated here only as
  // a faithful side effect of the original implementation.
  // ignore: unused_field
  int _totalBits;
  // ignore: unused_field
  int _flippedBits;

  // Note: the C# constructor accepted `ref int totalBits, ref int flippedBits`
  // but only read their initial values (it never wrote back), so the counts are
  // local to this injector. The Dart port mirrors that behavior with by-value
  // parameters.
  BitErrorInjector(this._innerReceiver, this._errorRate, math.Random? random,
      int totalBits, int flippedBits)
      : _random = random ?? math.Random(),
        _totalBits = totalBits,
        _flippedBits = flippedBits;

  @override
  void recBit(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove) {
    _totalBits++;

    // Randomly flip the bit based on error rate
    if (_random.nextDouble() < _errorRate) {
      raw = raw ^ 1; // Flip the bit (0->1 or 1->0)
      _flippedBits++;
    }

    // Forward the (possibly modified) bit to the inner receiver
    _innerReceiver.recBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    _innerReceiver.dcdChange(chan, subchan, slice, dcdOn);
  }
}

/// Collects decoded packets from the HDLC receiver.
class PacketCollector {
  final List<Packet> _packets = <Packet>[];

  void addPacket(Packet packet) {
    _packets.add(packet);
  }

  List<Packet> getPackets() {
    return _packets;
  }

  void clear() {
    _packets.clear();
  }
}

/// Collects decoded packets from FX.25 receiver via MultiModem.
class Fx25PacketCollector {
  final List<_PacketInfo> _packets = <_PacketInfo>[];

  void addPacket(Packet packet, FecType fecType,
      [int ctagNum = -1,
      int errorsCorrected = 0,
      CorrectionInfo? correctionInfo]) {
    _packets.add(_PacketInfo()
      ..packet = packet
      ..fecType = fecType
      ..ctagNum = ctagNum
      ..errorsCorrected = errorsCorrected
      ..correctionInfo = correctionInfo);
  }

  List<Packet> getPackets() {
    final List<Packet> packets = <Packet>[];
    for (final _PacketInfo info in _packets) {
      packets.add(info.packet);
    }
    return packets;
  }

  FecType getFecType(int index) {
    if (index >= 0 && index < _packets.length) {
      return _packets[index].fecType;
    }
    return FecType.none;
  }

  int getCtagNum(int index) {
    if (index >= 0 && index < _packets.length) {
      return _packets[index].ctagNum;
    }
    return -1;
  }

  int getErrorsCorrected(int index) {
    if (index >= 0 && index < _packets.length) {
      return _packets[index].errorsCorrected;
    }
    return 0;
  }

  CorrectionInfo? getCorrectionInfo(int index) {
    if (index >= 0 && index < _packets.length) {
      return _packets[index].correctionInfo;
    }
    return null;
  }

  void clear() {
    _packets.clear();
  }
}

class _PacketInfo {
  late Packet packet;
  FecType fecType = FecType.none;
  int ctagNum = -1;
  int errorsCorrected = 0;
  CorrectionInfo? correctionInfo;
}

/// Wrapper for [Fx25Rec] that implements [IHdlcReceiver].
///
/// Only forwards bits to FX.25 receiver (no AX.25 HDLC decoder).
/// Performs NRZI decoding before passing to FX.25.
class Fx25RecWrapper implements IHdlcReceiver {
  final Fx25Rec _fx25Rec;
  // Previous raw bit for NRZI decoding [chan, subchan, slice]
  final List<List<List<int>>> _prevRaw;

  Fx25RecWrapper(this._fx25Rec)
      : _prevRaw = List.generate(
            6, (_) => List.generate(9, (_) => List<int>.filled(9, 0)));

  /// Process a bit - perform NRZI decoding and feed to FX.25 receiver.
  @override
  void recBit(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove) {
    // NRZI decoding: 0 bit = transition, 1 bit = no change
    // In NRZI: same as previous = logic 1, different from previous = logic 0
    final int dbit = (raw == _prevRaw[chan][subchan][slice]) ? 1 : 0;
    _prevRaw[chan][subchan][slice] = raw;

    // Feed NRZI-decoded bit to FX.25 receiver for correlation tag detection
    // and FEC. Do NOT feed to HDLC receiver - this is FX.25 only mode.
    _fx25Rec.recBit(chan, subchan, slice, dbit);
  }

  /// Handle DCD change - ignored for FX.25 only mode.
  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    // No-op for FX.25 only mode
  }
}

/// Wrapper that feeds bits to both HDLC and FX.25 receivers.
///
/// Performs NRZI decoding for FX.25 while letting HDLC do its own NRZI.
class HdlcRecWithFx25Nrzi implements IHdlcReceiver {
  final IHdlcReceiver _hdlcRec;
  final Fx25Rec _fx25Rec;
  // Previous raw bit for NRZI decoding [chan, subchan, slice]
  final List<List<List<int>>> _prevRaw;

  HdlcRecWithFx25Nrzi(this._hdlcRec, this._fx25Rec)
      : _prevRaw = List.generate(
            6, (_) => List.generate(9, (_) => List<int>.filled(9, 0)));

  /// Process a bit - feed raw bits to HDLC and NRZI-decoded bits to FX.25.
  @override
  void recBit(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove) {
    // Feed raw bits to HDLC receiver (it does its own NRZI decoding)
    _hdlcRec.recBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);

    // Perform NRZI decoding for FX.25
    final int dbit = (raw == _prevRaw[chan][subchan][slice]) ? 1 : 0;
    _prevRaw[chan][subchan][slice] = raw;

    // Feed NRZI-decoded bits to FX.25 receiver for correlation tag detection
    // and FEC.
    _fx25Rec.recBit(chan, subchan, slice, dbit);
  }

  /// Handle DCD change - forward to HDLC receiver.
  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    _hdlcRec.dcdChange(chan, subchan, slice, dcdOn);
  }
}

/// HDLC receiver wrapper that collects packets using event handler.
class HdlcRecWithCollector {
  final PacketCollector _collector;
  final HdlcRec2 _hdlcRec;
  final bool _debugMode;

  HdlcRecWithCollector(this._collector, {this._debugMode = false})
      : _hdlcRec = HdlcRec2() {
    _hdlcRec.addFrameReceived(_onFrameReceived);
  }

  void init(AudioConfig audioConfig) {
    _hdlcRec.init(audioConfig);
  }

  HdlcRec2 getHdlcRec() {
    return _hdlcRec;
  }

  void recBit(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove) {
    _hdlcRec.recBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
  }

  void recBitNew(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove, PllNudge pll) {
    _hdlcRec.recBitNew(
        chan, subchan, slice, raw, isScrambled, notUsedRemove, pll);
  }

  void _onFrameReceived(FrameReceivedEventArgs e) {
    if (_debugMode) {
      stdout.writeln('\n════════════════════════════════════════════════════════════');
      stdout.writeln('             FRAME RECEIVED EVENT TRIGGERED');
      stdout.writeln('════════════════════════════════════════════════════════════');
      stdout.writeln('  Channel: ${e.channel}, Subchannel: ${e.subchannel}, Slice: ${e.slice}');
      stdout.writeln('  Frame length: ${e.frameLength} bytes');
      stdout.writeln();

      // Display frame in HEX format
      stdout.writeln('Frame Data (HEX):');
      for (int i = 0; i < e.frameLength; i++) {
        stdout.write('${_hex2(e.frame[i])} ');
        if ((i + 1) % 16 == 0) {
          stdout.writeln(' // Bytes ${i - 15} to $i');
        }
      }
      if (e.frameLength % 16 != 0) {
        stdout.writeln(' // Bytes ${(e.frameLength ~/ 16) * 16} to ${e.frameLength - 1}');
      }
      stdout.writeln();

      // Display frame in ASCII format
      stdout.writeln('Frame Data (ASCII):');
      for (int i = 0; i < e.frameLength; i++) {
        final int c = e.frame[i];
        if (c >= 32 && c <= 126) {
          stdout.write(String.fromCharCode(c));
        } else {
          stdout.write('[${_hex2(e.frame[i])}]');
        }
      }
      stdout.writeln();
      stdout.writeln();
    }

    // Create packet from frame
    final ALevel alevel =
        ALevel(e.audioLevel.rec, e.audioLevel.mark, e.audioLevel.space);
    final Packet? packet = Packet.fromFrame(e.frame, e.frameLength, alevel);

    if (packet != null) {
      if (_debugMode) {
        stdout.writeln('  ✓ Packet created successfully');
        stdout.writeln('  ✓ Is APRS: ${packet.isAprs()}');
      }

      if (packet.isAprs()) {
        _collector.addPacket(packet);

        if (_debugMode) {
          stdout.writeln('  ✓ Packet added to collector (total: ${_collector.getPackets().length})');

          // Display decoded packet info
          final DateTime now = DateTime.now();
          final String ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
          stdout.writeln('\n[DECODED PACKET] [$ts]');
          stdout.writeln('  Addresses: ${packet.formatAddrs()}');

          final Uint8List info = packet.getInfo();
          final int infoLen = info.length;
          final StringBuffer message = StringBuffer();
          for (int i = 0; i < infoLen; i++) {
            if (info[i] >= 32 && info[i] <= 126) {
              message.writeCharCode(info[i]);
            }
          }
          stdout.writeln('  Message: ${message.toString()}');
          stdout.writeln();
        }
      } else if (_debugMode) {
        stdout.writeln('  ⚠ Packet is not APRS format');
        stdout.writeln();
      }
    } else if (_debugMode) {
      stdout.writeln('  ✗ Failed to create packet from frame');
      stdout.writeln();
    }
  }
}
