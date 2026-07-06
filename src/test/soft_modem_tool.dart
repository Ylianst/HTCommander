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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/ax25_pad.dart';
import 'package:htcommander/hamlib/correction_info.dart';
import 'package:htcommander/hamlib/demod_9600.dart';
import 'package:htcommander/hamlib/demod_afsk.dart';
import 'package:htcommander/hamlib/demod_psk.dart';
import 'package:htcommander/hamlib/fx25.dart';
import 'package:htcommander/hamlib/fx25_rec.dart';
import 'package:htcommander/hamlib/fx25_send.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/hdlc_rec.dart';
import 'package:htcommander/hamlib/hdlc_rec2.dart';
import 'package:htcommander/hamlib/hdlc_send.dart';
import 'package:htcommander/hamlib/ihdlc_receiver.dart';
import 'package:htcommander/hamlib/multi_modem.dart';
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
  required int fxMode,
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

  final bool useFx25 = fxMode > 0;
  Fx25Send? fx25Send;
  if (useFx25) {
    Fx25.init(0);
    fx25Send = Fx25Send();
    fx25Send.init(genTone);
  }

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
    if (useFx25) {
      // FX.25 wraps the AX.25 frame in a Reed-Solomon codeblock. sendFrame
      // appends the FCS itself, so pass the un-FCS'd frame.
      fx25Send!.sendFrame(chan, packet.frameData, packet.frameLen, fxMode);
    } else {
      hdlcSend.sendFrame(chan, packet.frameData, packet.frameLen, false);
    }
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
      'Modulation: ${profile.modemType.name}'
      '${useFx25 ? "   FEC: FX.25 ($fxMode check bytes)" : ""}');
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

  int axCount = 0; // decoded via plain AX.25 (no FEC)
  int fxCount = 0; // decoded via FX.25 (Reed-Solomon FEC)

  // Plain AX.25/HDLC receiver.
  final HdlcRec2 hdlcRec = HdlcRec2();
  hdlcRec.addFrameReceived((FrameReceivedEventArgs e) {
    final Packet? packet = Packet.fromFrame(e.frame, e.frameLength, ALevel());
    if (packet == null) return;
    axCount++;
    print('[AX.25]  ${_packetToMonitor(packet)}');
  });
  hdlcRec.init(cfg);

  // FX.25 receiver (Reed-Solomon FEC). Decoded frames arrive via MultiModem.
  Fx25.init(0);
  final MultiModem multiModem = MultiModem();
  multiModem.init(cfg);
  multiModem.addPacketReady((PacketReadyEventArgs e) {
    final Packet? packet = e.packet;
    if (packet == null || e.fecType != FecType.fx25) return;
    fxCount++;
    final CorrectionInfo? ci = e.correctionInfo;
    final int corrected = ci?.rsSymbolsCorrected ?? -1;
    final String tag = e.ctagNum >= 0
        ? '0x${e.ctagNum.toRadixString(16).padLeft(2, '0')}'
        : '?';
    final String fec = corrected > 0
        ? 'corrected $corrected RS symbol(s)'
        : (corrected == 0 ? 'no errors' : 'FEC');
    print('[FX.25 tag=$tag $fec]  ${_packetToMonitor(packet)}');
  });
  final Fx25Rec fx25Rec = Fx25Rec(multiModem);

  // Bridge feeds each demodulated bit to both receivers. The FX.25 decoder
  // needs the NRZI-decoded bit (Direwolf: fx25_rec_bit(dbit)); the HDLC
  // receiver does its own NRZI decoding from the raw bit.
  final _DecodeBridge bridge = _DecodeBridge(hdlcRec, fx25Rec);

  const int chan = 0;
  const int subchan = 0;

  switch (profile.demodKind) {
    case _DemodKind.afsk:
      final DemodAfsk demod = DemodAfsk(bridge);
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
      final DemodPsk demod = DemodPsk(bridge);
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
          bridge,
        );
      }
      break;
  }

  final double seconds = WavFile.getDuration(samples, sampleRate);
  print('');
  print('Read ${samples.length} samples (${seconds.toStringAsFixed(2)} s) '
      'at $sampleRate Hz from $inputFile');
  print('Decoded ${axCount + fxCount} packet(s): $axCount AX.25, '
      '$fxCount FX.25   Baud: $baud   Modulation: ${profile.modemType.name}');
  return (axCount + fxCount) > 0 ? 0 : 1;
}

/// Feeds each demodulated bit to both the HDLC and FX.25 receivers. Mirrors
/// Direwolf's hdlc_rec_bit_new which calls fx25_rec_bit() with the NRZI-decoded
/// bit while the HDLC path works from the raw bit.
class _DecodeBridge implements IHdlcReceiver {
  final HdlcRec2 _hdlc;
  final Fx25Rec _fx25;
  int _prevRaw = 0;

  _DecodeBridge(this._hdlc, this._fx25);

  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
  ) {
    _hdlc.recBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
    // NRZI decode: a '1' is no change, a '0' is a transition. (For 9600 the
    // descrambling already happened in demod_9600 before this bit arrived.)
    final int dbit = (raw == _prevRaw) ? 1 : 0;
    _prevRaw = raw;
    _fx25.recBit(chan, subchan, slice, dbit);
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    _hdlc.dcdChange(chan, subchan, slice, dcdOn);
  }
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
// Corrupt (inject noise / bit errors into a WAV)
// ---------------------------------------------------------------------------

int _runCorrupt({
  required String inputFile,
  required String outputFile,
  required double noiseStddev,
  required int flipCount,
  required int burstLen,
  required double burstAt,
  required int seed,
}) {
  final File input = File(inputFile);
  if (!input.existsSync()) {
    stderr.writeln('WAV file not found: $inputFile');
    return 2;
  }

  final (Int16List samples, WavParams wavParams) = WavFile.read(inputFile);
  final math.Random rng = math.Random(seed);

  int clamp16(int v) => v < -32768 ? -32768 : (v > 32767 ? 32767 : v);

  // Additive white Gaussian noise (Box-Muller). Simulates a weak/noisy signal
  // which produces demodulator bit errors.
  if (noiseStddev > 0) {
    for (int i = 0; i < samples.length; i++) {
      final double u1 = (rng.nextDouble()).clamp(1e-12, 1.0);
      final double u2 = rng.nextDouble();
      final double g =
          math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
      samples[i] = clamp16((samples[i] + g * noiseStddev).round());
    }
  }

  // Randomize a number of individual samples (impulse / scattered errors).
  if (flipCount > 0) {
    for (int n = 0; n < flipCount; n++) {
      final int idx = rng.nextInt(samples.length);
      samples[idx] = clamp16((rng.nextInt(2) * 2 - 1) * 32767);
    }
  }

  // Burst error: heavily corrupt a contiguous run of samples (a fade / weak
  // spot). Strong noise is ADDED so the carrier still carries enough timing
  // for the demodulator to stay in sync while bit decisions get flipped - this
  // produces the localized byte errors Reed-Solomon FEC is designed to recover.
  if (burstLen > 0) {
    int start = (samples.length * burstAt).round();
    if (start < 0) start = 0;
    if (start + burstLen > samples.length) {
      start = math.max(0, samples.length - burstLen);
    }
    const double burstNoise = 18000.0;
    for (int i = start; i < start + burstLen && i < samples.length; i++) {
      final double u1 = (rng.nextDouble()).clamp(1e-12, 1.0);
      final double u2 = rng.nextDouble();
      final double g =
          math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
      samples[i] = clamp16((samples[i] + g * burstNoise).round());
    }
  }

  WavFile.write(outputFile, samples, wavParams);
  print('Corrupted $inputFile -> $outputFile');
  print('  Samples: ${samples.length}   Noise stddev: '
      '${noiseStddev.toStringAsFixed(0)}   Scattered: $flipCount   '
      'Burst: $burstLen samples @ ${(burstAt * 100).toStringAsFixed(0)}%   '
      'Seed: $seed');
  return 0;
}

// ---------------------------------------------------------------------------
// Argument parsing / main
// ---------------------------------------------------------------------------

void _printUsage() {
  stderr.writeln('''
HTCommander software modem test tool (gen_packets / atest equivalent)

Usage:
  Encode data -> WAV:
    dart run test/soft_modem_tool.dart encode -B <baud> -o <out.wav> [-r <rate>] [-g <amp>] [-X <n>] <data.txt>

  Decode WAV -> data (decodes both AX.25 and FX.25):
    dart run test/soft_modem_tool.dart decode -B <baud> <in.wav>

  Corrupt a WAV (inject noise / bit errors) to test FEC:
    dart run test/soft_modem_tool.dart corrupt [-N <stddev>] [--flip <n>] [-s <seed>] <in.wav> <out.wav>

Options:
  -B <baud>   Modem baud/mode: 300, 1200, 2400, 4800, 9600  (default 1200)
  -o <file>   Output WAV file (encode only)
  -r <rate>   Sample rate in Hz for encoding (default 44100, Direwolf-compatible)
  -g <amp>    Output amplitude 0-100 for encoding (default 50)
  -X <n>      Enable FX.25 FEC on transmit. n = 16, 32, or 64 check bytes.
  -N <stddev> Gaussian noise standard deviation for corrupt (sample units)
  --flip <n>  Randomize n individual samples for corrupt (scattered errors)
  --burst <n> Blank a contiguous run of n samples (burst error / dropout)
  --burst-at <p>  Position of the burst, 0.0-1.0 through the file (default 0.4)
  -s <seed>   RNG seed for corrupt (default 1, for reproducible results)

Data file uses TNC2 monitor format, one packet per line:
  WB2OSZ-15>APDW17,WIDE1-1:Hello, world!
''');
}

int _parseIntOr(String? value, int fallback) {
  if (value == null) return fallback;
  return int.tryParse(value) ?? fallback;
}

double _parseDoubleOr(String? value, double fallback) {
  if (value == null) return fallback;
  return double.tryParse(value) ?? fallback;
}

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(2);
  }

  final String command = args[0].toLowerCase();
  if (command != 'encode' && command != 'decode' && command != 'corrupt') {
    stderr.writeln('Unknown command: ${args[0]}');
    _printUsage();
    exit(2);
  }

  int baud = 1200;
  int sampleRate = 44100;
  int amplitude = 50;
  int fxMode = 0;
  double noiseStddev = 0;
  int flipCount = 0;
  int burstLen = 0;
  double burstAt = 0.4;
  int seed = 1;
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
      case '-X':
        fxMode = _parseIntOr(_next(args, ++i), fxMode);
        break;
      case '-N':
        noiseStddev = _parseDoubleOr(_next(args, ++i), noiseStddev);
        break;
      case '--flip':
        flipCount = _parseIntOr(_next(args, ++i), flipCount);
        break;
      case '--burst':
        burstLen = _parseIntOr(_next(args, ++i), burstLen);
        break;
      case '--burst-at':
        burstAt = _parseDoubleOr(_next(args, ++i), burstAt);
        break;
      case '-s':
        seed = _parseIntOr(_next(args, ++i), seed);
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
      fxMode: fxMode,
    ));
  } else if (command == 'corrupt') {
    if (positional.length < 2) {
      stderr.writeln('corrupt: usage: corrupt [options] <in.wav> <out.wav>');
      _printUsage();
      exit(2);
    }
    if (noiseStddev <= 0 && flipCount <= 0 && burstLen <= 0) {
      noiseStddev = 3000; // sensible default so the command does something
    }
    exit(_runCorrupt(
      inputFile: positional[0],
      outputFile: positional[1],
      noiseStddev: noiseStddev,
      flipCount: flipCount,
      burstLen: burstLen,
      burstAt: burstAt,
      seed: seed,
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
