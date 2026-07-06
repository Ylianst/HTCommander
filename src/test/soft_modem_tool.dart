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
// soft_modem_tool.dart - Command line tool to encode/decode packets with the
// HTCommander software modem (lib/hamlib). It mirrors Direwolf's `gen_packets`
// and `atest` so the two implementations can be cross-checked.
//
// Encode data -> WAV (like gen_packets):
//   dart run test/soft_modem_tool.dart encode -B 1200 -o output.wav data.txt
//
// Decode WAV -> data (like atest):
//   dart run test/soft_modem_tool.dart decode -B 1200 output.wav
//
// The input data file uses the TNC2 monitor format, one packet per line:
//   WB2OSZ-15>APDW17,WIDE1-1:Hello, world!
//
// Supported -B (baud) values:
//   300   AFSK 1600/1800 Hz (Bell 103, HF)
//   1200  AFSK 1200/2200 Hz (Bell 202, VHF)   [app: AFSK1200]
//   2400  QPSK  V.26 alt B, 1800 Hz carrier     [app: PSK2400]
//   4800  8PSK  V.26 alt B, 1800 Hz carrier     [app: PSK4800]
//   9600  G3RUH scrambled/baseband              [app: G3RUH9600]
//

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/ax25_pad.dart';
import 'package:htcommander/hamlib/demod_9600.dart';
import 'package:htcommander/hamlib/demod_afsk.dart';
import 'package:htcommander/hamlib/demod_psk.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/hdlc_rec.dart';
import 'package:htcommander/hamlib/hdlc_rec2.dart';
import 'package:htcommander/hamlib/hdlc_send.dart';
import 'package:htcommander/hamlib/wav_file.dart';

/// Which demodulator family a modem profile uses.
enum _DemodKind { afsk, psk, g3ruh }

/// A modem configuration for a given `-B` baud value. Mirrors the settings used
/// by lib/radio/software_modem.dart so the tool exercises the real modem code.
class _ModemProfile {
  final ModemType modemType;
  final int markFreq;
  final int spaceFreq;

  /// Symbol/bit rate stored in the channel config (used by GenTone).
  final int channelBaud;

  /// Actual bits per second (used by the PSK demodulator init).
  final int bps;

  final V26Alternative v26Alt;
  final _DemodKind demodKind;

  /// Demodulator profile letter (e.g. 'A' for AFSK, 'B' for PSK).
  final String demodProfile;

  const _ModemProfile({
    required this.modemType,
    required this.markFreq,
    required this.spaceFreq,
    required this.channelBaud,
    required this.bps,
    required this.v26Alt,
    required this.demodKind,
    required this.demodProfile,
  });
}

_ModemProfile? _profileForBaud(int baud) {
  switch (baud) {
    case 300:
      return const _ModemProfile(
        modemType: ModemType.afsk,
        markFreq: 1600,
        spaceFreq: 1800,
        channelBaud: 300,
        bps: 300,
        v26Alt: V26Alternative.unspecified,
        demodKind: _DemodKind.afsk,
        demodProfile: 'A',
      );
    case 1200:
      return const _ModemProfile(
        modemType: ModemType.afsk,
        markFreq: 1200,
        spaceFreq: 2200,
        channelBaud: 1200,
        bps: 1200,
        v26Alt: V26Alternative.unspecified,
        demodKind: _DemodKind.afsk,
        demodProfile: 'A',
      );
    case 2400:
      return const _ModemProfile(
        modemType: ModemType.qpsk,
        markFreq: 1800,
        spaceFreq: 1800,
        // Direwolf treats achan.baud as bits-per-second for PSK; GenTone and
        // the demodulator both derive the 1200 symbol/s rate from it.
        channelBaud: 2400,
        bps: 2400,
        v26Alt: V26Alternative.b,
        demodKind: _DemodKind.psk,
        demodProfile: 'B',
      );
    case 4800:
      return const _ModemProfile(
        modemType: ModemType.psk8,
        markFreq: 1800,
        spaceFreq: 1800,
        // bits-per-second; symbol rate is baud/3 = 1600 symbol/s.
        channelBaud: 4800,
        bps: 4800,
        v26Alt: V26Alternative.b,
        demodKind: _DemodKind.psk,
        demodProfile: 'B',
      );
    case 9600:
      return const _ModemProfile(
        // G3RUH 9600 requires the transmit side to scramble the bit stream;
        // the demodulator always descrambles. ModemType.baseband would send
        // un-scrambled data and fail to decode.
        modemType: ModemType.scramble,
        markFreq: 0,
        spaceFreq: 0,
        channelBaud: 9600,
        bps: 9600,
        v26Alt: V26Alternative.unspecified,
        demodKind: _DemodKind.g3ruh,
        demodProfile: 'A',
      );
    default:
      return null;
  }
}

/// Build an AudioConfig for a single radio channel using the given profile.
AudioConfig _buildAudioConfig(_ModemProfile profile, int sampleRate) {
  final AudioConfig cfg = AudioConfig();
  cfg.devices[0].defined = true;
  cfg.devices[0].samplesPerSec = sampleRate;
  cfg.devices[0].bitsPerSample = 16;
  cfg.devices[0].numChannels = 1;

  cfg.channelMedium[0] = Medium.radio;
  cfg.channels[0].numSubchan = 1;
  cfg.channels[0].modemType = profile.modemType;
  cfg.channels[0].markFreq = profile.markFreq;
  cfg.channels[0].spaceFreq = profile.spaceFreq;
  cfg.channels[0].baud = profile.channelBaud;
  cfg.channels[0].v26Alt = profile.v26Alt;
  cfg.channels[0].txdelay = 30; // ~300 ms preamble
  cfg.channels[0].txtail = 10; // ~100 ms tail
  return cfg;
}

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

int _runEncode({
  required int baud,
  required String outputFile,
  required String dataFile,
  required int sampleRate,
  required int amplitude,
}) {
  final _ModemProfile? profile = _profileForBaud(baud);
  if (profile == null) {
    stderr.writeln('Unsupported baud rate: $baud');
    return 2;
  }

  final File input = File(dataFile);
  if (!input.existsSync()) {
    stderr.writeln('Data file not found: $dataFile');
    return 2;
  }

  final List<String> lines = input.readAsLinesSync();

  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);
  final AudioBuffer audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
  final GenTone genTone = GenTone(audioBuffer);
  genTone.init(cfg, amplitude);
  final HdlcSend hdlcSend = HdlcSend(genTone, cfg);

  const int chan = 0;
  audioBuffer.clearAll();

  int packetCount = 0;
  for (final String raw in lines) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final Packet? packet = Packet.fromText(line, false);
    if (packet == null) {
      stderr.writeln('Skipping invalid TNC2 line: $line');
      continue;
    }

    // G3RUH benefits from a little leading/trailing silence.
    if (profile.demodKind == _DemodKind.g3ruh) {
      _appendSilence(audioBuffer, sampleRate ~/ 2);
    }

    hdlcSend.sendFlags(chan, cfg.channels[chan].txdelay, false, null);
    hdlcSend.sendFrame(chan, packet.frameData, packet.frameLen, false);
    hdlcSend.sendFlags(chan, cfg.channels[chan].txtail, true, (device) {});

    if (profile.demodKind == _DemodKind.g3ruh) {
      _appendSilence(audioBuffer, sampleRate ~/ 2);
    }

    packetCount++;
    print('Encoded: $line');
  }

  if (packetCount == 0) {
    stderr.writeln('No valid packets found in $dataFile');
    return 1;
  }

  final Int16List samples = audioBuffer.getAndClear(0);
  final WavParams wavParams = WavParams()
    ..sampleRate = sampleRate
    ..bitsPerSample = 16
    ..numChannels = 1;
  WavFile.write(outputFile, samples, wavParams);

  final double seconds = WavFile.getDuration(samples, sampleRate);
  print('');
  print('Wrote $packetCount packet(s) to $outputFile');
  print('  Baud: $baud   Sample rate: $sampleRate Hz   '
      'Modulation: ${profile.modemType.name}');
  print('  ${samples.length} samples (${seconds.toStringAsFixed(2)} s)');
  return 0;
}

void _appendSilence(AudioBuffer buffer, int numSamples) {
  for (int i = 0; i < numSamples; i++) {
    buffer.put(0, 0);
  }
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

int _runDecode({
  required int baud,
  required String inputFile,
}) {
  final _ModemProfile? profile = _profileForBaud(baud);
  if (profile == null) {
    stderr.writeln('Unsupported baud rate: $baud');
    return 2;
  }

  final File input = File(inputFile);
  if (!input.existsSync()) {
    stderr.writeln('WAV file not found: $inputFile');
    return 2;
  }

  final (Int16List samples, WavParams wavParams) = WavFile.read(inputFile);
  final int sampleRate = wavParams.sampleRate;

  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);

  final HdlcRec2 hdlcRec = HdlcRec2();
  int decoded = 0;

  hdlcRec.addFrameReceived((FrameReceivedEventArgs e) {
    final Packet? packet = Packet.fromFrame(e.frame, e.frameLength, ALevel());
    if (packet == null) return;
    decoded++;
    print('[$decoded] ${_packetToMonitor(packet)}');
  });
  hdlcRec.init(cfg);

  const int chan = 0;
  const int subchan = 0;

  switch (profile.demodKind) {
    case _DemodKind.afsk:
      final DemodAfsk demod = DemodAfsk(hdlcRec);
      final DemodulatorState state = DemodulatorState();
      demod.init(
        sampleRate,
        profile.channelBaud,
        profile.markFreq,
        profile.spaceFreq,
        profile.demodProfile,
        state,
      );
      for (final int sample in samples) {
        demod.processSample(chan, subchan, sample, state);
      }
      break;

    case _DemodKind.psk:
      final DemodPsk demod = DemodPsk(hdlcRec);
      final PskDemodulatorState state = PskDemodulatorState();
      demod.init(
        profile.modemType,
        profile.v26Alt,
        sampleRate,
        profile.bps,
        profile.demodProfile,
        state,
      );
      for (final int sample in samples) {
        demod.processSample(chan, subchan, sample, state);
      }
      break;

    case _DemodKind.g3ruh:
      final DemodulatorState state = DemodulatorState();
      final Demod9600State state9600 = Demod9600State();
      Demod9600.init(sampleRate, 1, profile.bps, state, state9600);
      for (final int sample in samples) {
        Demod9600.processSample(
          chan,
          sample,
          1,
          state,
          state9600,
          hdlcRec,
        );
      }
      break;
  }

  final double seconds = WavFile.getDuration(samples, sampleRate);
  print('');
  print('Read ${samples.length} samples (${seconds.toStringAsFixed(2)} s) '
      'at $sampleRate Hz from $inputFile');
  print('Decoded $decoded packet(s)   Baud: $baud   '
      'Modulation: ${profile.modemType.name}');
  return decoded > 0 ? 0 : 1;
}

/// Render a decoded packet in TNC2 monitor format: SRC>DEST[,digi...]:info
String _packetToMonitor(Packet packet) {
  final int numAddr = packet.getNumAddr();
  final StringBuffer sb = StringBuffer();

  if (numAddr < 2) {
    // Not a standard AX.25 frame; just dump the info bytes.
    return _infoToString(packet.getInfo());
  }

  sb.write(packet.getAddrWithSsid(Ax25Constants.source));
  sb.write('>');
  sb.write(packet.getAddrWithSsid(Ax25Constants.destination));

  for (int i = Ax25Constants.repeater1; i < numAddr; i++) {
    sb.write(',');
    sb.write(packet.getAddrWithSsid(i));
    if (packet.getH(i)) sb.write('*'); // has-been-repeated flag
  }

  sb.write(':');
  sb.write(_infoToString(packet.getInfo()));
  return sb.toString();
}

/// Convert an info field to a printable string, escaping non-printable bytes as
/// <0xNN> (the same convention accepted by Packet.fromText).
String _infoToString(Uint8List info) {
  final StringBuffer sb = StringBuffer();
  for (final int b in info) {
    if (b >= 0x20 && b <= 0x7E) {
      sb.writeCharCode(b);
    } else {
      sb.write('<0x${b.toRadixString(16).padLeft(2, '0')}>');
    }
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// Argument parsing / main
// ---------------------------------------------------------------------------

void _printUsage() {
  stderr.writeln('''
HTCommander software modem test tool (gen_packets / atest equivalent)

Usage:
  Encode data -> WAV:
    dart run test/soft_modem_tool.dart encode -B <baud> -o <out.wav> [-r <rate>] [-g <amp>] <data.txt>

  Decode WAV -> data:
    dart run test/soft_modem_tool.dart decode -B <baud> <in.wav>

Options:
  -B <baud>   Modem baud/mode: 300, 1200, 2400, 4800, 9600  (default 1200)
  -o <file>   Output WAV file (encode only)
  -r <rate>   Sample rate in Hz for encoding (default 44100, Direwolf-compatible)
  -g <amp>    Output amplitude 0-100 for encoding (default 50)

Data file uses TNC2 monitor format, one packet per line:
  WB2OSZ-15>APDW17,WIDE1-1:Hello, world!
''');
}

int _parseIntOr(String? value, int fallback) {
  if (value == null) return fallback;
  return int.tryParse(value) ?? fallback;
}

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(2);
  }

  final String command = args[0].toLowerCase();
  if (command != 'encode' && command != 'decode') {
    stderr.writeln('Unknown command: ${args[0]}');
    _printUsage();
    exit(2);
  }

  int baud = 1200;
  int sampleRate = 44100;
  int amplitude = 50;
  String? outputFile;
  final List<String> positional = <String>[];

  for (int i = 1; i < args.length; i++) {
    final String a = args[i];
    switch (a) {
      case '-B':
        baud = _parseIntOr(_next(args, ++i), baud);
        break;
      case '-o':
        outputFile = _next(args, ++i);
        break;
      case '-r':
        sampleRate = _parseIntOr(_next(args, ++i), sampleRate);
        break;
      case '-g':
        amplitude = _parseIntOr(_next(args, ++i), amplitude);
        break;
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        positional.add(a);
    }
  }

  if (command == 'encode') {
    if (positional.isEmpty) {
      stderr.writeln('encode: missing input data file');
      _printUsage();
      exit(2);
    }
    outputFile ??= 'output.wav';
    exit(_runEncode(
      baud: baud,
      outputFile: outputFile,
      dataFile: positional.first,
      sampleRate: sampleRate,
      amplitude: amplitude,
    ));
  } else {
    if (positional.isEmpty) {
      stderr.writeln('decode: missing input WAV file');
      _printUsage();
      exit(2);
    }
    exit(_runDecode(baud: baud, inputFile: positional.first));
  }
}

String? _next(List<String> args, int i) => i < args.length ? args[i] : null;
