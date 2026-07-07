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
// Round-trip a WAV through the Bluetooth SBC codec to inject the same
// compression artifacts the radio's audio link adds:
//   dart run test/soft_modem_tool.dart sbc clean.wav artifact.wav
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
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

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
// SBC round-trip (encode + decode through the Bluetooth SBC codec)
// ---------------------------------------------------------------------------

/// Map a WAV sample rate to the matching SBC header frequency. SBC only knows
/// four rates; anything else keeps the default 32 kHz (the DSP is sample-rate
/// agnostic, so only the header metadata differs).
SbcFrequency _sbcFrequencyForRate(int rate) {
  switch (rate) {
    case 16000:
      return SbcFrequency.freq16K;
    case 32000:
      return SbcFrequency.freq32K;
    case 44100:
      return SbcFrequency.freq44K1;
    case 48000:
      return SbcFrequency.freq48K;
    default:
      return SbcFrequency.freq32K;
  }
}

/// Encode the input WAV to SBC frames and immediately decode them back to PCM,
/// writing the reconstructed audio. This mirrors what the radio does over its
/// Bluetooth audio link (see lib/radio/radio_audio.dart), so the output carries
/// the same lossy SBC compression artifacts real received audio has.
int _runSbc({
  required String inputFile,
  required String outputFile,
  required int bitpool,
  required int blocks,
  required int subbands,
  required bool loudness,
  required bool msbc,
}) {
  final File input = File(inputFile);
  if (!input.existsSync()) {
    stderr.writeln('WAV file not found: $inputFile');
    return 2;
  }

  final (Int16List samples, WavParams wavParams) = WavFile.read(inputFile);
  if (wavParams.numChannels != 1) {
    stderr.writeln('Only mono WAV files are supported (the radio SBC link is '
        'mono). Got ${wavParams.numChannels} channels.');
    return 2;
  }

  // Frame configuration. Defaults mirror the radio's audio link
  // (lib/radio/radio_audio.dart): 32 kHz mono, 16 blocks, 8 subbands,
  // loudness allocation, bitpool 18.
  final SbcFrame frame = SbcFrame();
  if (msbc) {
    frame.isMsbc = true; // 16 kHz, 15 blocks, 8 subbands, bitpool 26
  } else {
    frame
      ..frequency = _sbcFrequencyForRate(wavParams.sampleRate)
      ..mode = SbcMode.mono
      ..allocationMethod = loudness
          ? SbcBitAllocationMethod.loudness
          : SbcBitAllocationMethod.snr
      ..blocks = blocks
      ..subbands = subbands
      ..bitpool = bitpool;
    if (!frame.isValid()) {
      stderr.writeln('Invalid SBC configuration (blocks=$blocks '
          'subbands=$subbands bitpool=$bitpool).');
      return 2;
    }
  }

  // A single encoder/decoder pair reused across every frame: both keep
  // filterbank history between frames, exactly like the streaming radio link.
  final SbcEncoder encoder = SbcEncoder();
  final SbcDecoder decoder = SbcDecoder();

  // Reference frame (mSBC substitutes its own fixed config inside encode()).
  final SbcFrame refFrame = msbc ? SbcFrame.createMsbc() : frame;
  final int samplesPerFrame = refFrame.blocks * refFrame.subbands;

  final List<int> outSamples = <int>[];
  final Int16List frameBuf = Int16List(samplesPerFrame);
  int frameCount = 0;
  int encodeFailures = 0;
  int decodeFailures = 0;

  for (int off = 0; off < samples.length; off += samplesPerFrame) {
    // Copy one frame of PCM, zero-padding a short final frame.
    for (int i = 0; i < samplesPerFrame; i++) {
      final int idx = off + i;
      frameBuf[i] = idx < samples.length ? samples[idx] : 0;
    }

    final Uint8List? encoded = encoder.encode(frameBuf, null, frame);
    if (encoded == null) {
      encodeFailures++;
      for (int i = 0; i < samplesPerFrame && off + i < samples.length; i++) {
        outSamples.add(samples[off + i]);
      }
      continue;
    }

    final SbcDecodeResult result = decoder.decode(encoded);
    if (!result.success) {
      decodeFailures++;
      for (int i = 0; i < samplesPerFrame && off + i < samples.length; i++) {
        outSamples.add(samples[off + i]);
      }
      continue;
    }

    outSamples.addAll(result.pcmLeft);
    frameCount++;
  }

  final Int16List outPcm = Int16List.fromList(outSamples);
  WavFile.write(outputFile, outPcm, wavParams);

  final int frameSize = refFrame.getFrameSize();
  final int bitrate = refFrame.getBitrate();
  final double seconds = WavFile.getDuration(samples, wavParams.sampleRate);
  print('SBC round-trip: $inputFile -> $outputFile');
  print('  ${msbc ? "mSBC" : "SBC"}  ${refFrame.getFrequencyHz()} Hz mono  '
      'blocks=${refFrame.blocks}  subbands=${refFrame.subbands}  '
      'bitpool=${refFrame.bitpool}');
  print('  Frame: $frameSize bytes / $samplesPerFrame samples   '
      'Bitrate: ${(bitrate / 1000).toStringAsFixed(1)} kbps   '
      'Codec delay: ${refFrame.getDelay()} samples');
  print('  Frames: $frameCount   In: ${samples.length} samples '
      '(${seconds.toStringAsFixed(2)} s)   Out: ${outPcm.length} samples');
  if (encodeFailures > 0 || decodeFailures > 0) {
    print('  WARNING: $encodeFailures encode / $decodeFailures decode '
        'failure(s) (original PCM passed through those frames).');
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Loopback (raw-frame round trip at many lengths - BSS length sweep)
// ---------------------------------------------------------------------------

/// Encode a single raw HDLC frame (arbitrary bytes, e.g. a BSS packet) to PCM.
/// The FCS is appended by hdlcSend.sendFrame, exactly like the software modem.
Int16List _encodeRawFramePcm(
  _ModemProfile profile,
  int sampleRate,
  int amplitude,
  Uint8List data,
) {
  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);
  final AudioBuffer audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
  final GenTone genTone = GenTone(audioBuffer);
  genTone.init(cfg, amplitude);
  final HdlcSend hdlcSend = HdlcSend(genTone, cfg);

  const int chan = 0;
  audioBuffer.clearAll();

  if (profile.demodKind == _DemodKind.g3ruh) {
    _appendSilence(audioBuffer, sampleRate ~/ 2);
  }
  hdlcSend.sendFlags(chan, cfg.channels[chan].txdelay, false, null);
  hdlcSend.sendFrame(chan, data, data.length, false);
  hdlcSend.sendFlags(chan, cfg.channels[chan].txtail, true, (device) {});
  if (profile.demodKind == _DemodKind.g3ruh) {
    _appendSilence(audioBuffer, sampleRate ~/ 2);
  }

  return audioBuffer.getAndClear(0);
}

/// Demodulate PCM and return every raw HDLC frame the receiver accepts (FCS
/// valid), with the 2-byte FCS already stripped. Uses HdlcRec2 with the same
/// configuration the software modem uses in production.
List<Uint8List> _decodePcmRawFrames(
  _ModemProfile profile,
  int sampleRate,
  Int16List samples,
) {
  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);
  final List<Uint8List> frames = <Uint8List>[];

  final HdlcRec2 hdlcRec = HdlcRec2();
  hdlcRec.addFrameReceived((FrameReceivedEventArgs e) {
    frames.add(Uint8List.fromList(e.frame.sublist(0, e.frameLength)));
  });
  hdlcRec.init(cfg);

  _runDemod(profile, sampleRate, samples, hdlcRec);
  return frames;
}

/// Run the demodulator that matches [profile], feeding every recovered bit to
/// [sink] (an HdlcRec2, an FX.25 bridge, etc.).
void _runDemod(
  _ModemProfile profile,
  int sampleRate,
  Int16List samples,
  IHdlcReceiver sink,
) {
  const int chan = 0;
  const int subchan = 0;

  switch (profile.demodKind) {
    case _DemodKind.afsk:
      final DemodAfsk demod = DemodAfsk(sink);
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
      final DemodPsk demod = DemodPsk(sink);
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
        Demod9600.processSample(chan, sample, 1, state, state9600, sink);
      }
      break;
  }
}

/// Encode a raw frame exactly the way the production software modem does
/// (lib/radio/software_modem.dart _buildBundledPcm): 1/10 s leading silence for
/// PTT keyup, TXDELAY preamble, then FX.25 FEC (16 check bytes) when the frame
/// meets the AX.25 minimum length (>= 15 data bytes) or plain AX.25 otherwise,
/// TXTAIL postamble, 1/10 s trailing silence.
Int16List _encodeRawFrameProdPcm(
  _ModemProfile profile,
  int sampleRate,
  int amplitude,
  Uint8List data,
) {
  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);
  final AudioBuffer audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
  final GenTone genTone = GenTone(audioBuffer);
  genTone.init(cfg, amplitude);
  final HdlcSend hdlcSend = HdlcSend(genTone, cfg);
  Fx25.init(0);
  final Fx25Send fx25Send = Fx25Send();
  fx25Send.init(genTone);

  const int chan = 0;
  audioBuffer.clearAll();

  _appendSilence(audioBuffer, sampleRate ~/ 10); // PTT keyup silence
  if (profile.demodKind == _DemodKind.g3ruh) {
    _appendSilence(audioBuffer, sampleRate ~/ 2);
  }

  hdlcSend.sendFlags(chan, cfg.channels[chan].txdelay, false, null);

  const int ax25MinDataLen = 14 + 1; // two addresses + control
  const int fx25SmallestFec = 16;
  int sent = -1;
  if (data.length >= ax25MinDataLen) {
    sent = fx25Send.sendFrame(chan, data, data.length, fx25SmallestFec);
  }
  if (sent < 0) {
    hdlcSend.sendFrame(chan, data, data.length, false);
  }

  hdlcSend.sendFlags(chan, cfg.channels[chan].txtail, true, (device) {});
  _appendSilence(audioBuffer, sampleRate ~/ 10);
  if (profile.demodKind == _DemodKind.g3ruh) {
    _appendSilence(audioBuffer, sampleRate ~/ 2);
  }

  return audioBuffer.getAndClear(0);
}

/// Decode PCM the way production does: an HdlcRec2 and an Fx25Rec both fed from
/// the demodulator, with the plain-HDLC copy suppressed while FX.25 is mid-block
/// (software_modem.dart _onFrameReceived). A frame carried inside an FX.25 block
/// is therefore only recovered if the FX.25 receiver delivers it.
List<Uint8List> _decodePcmProdFrames(
  _ModemProfile profile,
  int sampleRate,
  Int16List samples,
) {
  final AudioConfig cfg = _buildAudioConfig(profile, sampleRate);
  final List<Uint8List> frames = <Uint8List>[];

  final HdlcRec2 hdlcRec = HdlcRec2();

  Fx25.init(0);
  final MultiModem multiModem = MultiModem();
  multiModem.init(cfg);
  final Fx25Rec fx25Rec = Fx25Rec(multiModem);

  hdlcRec.addFrameReceived((FrameReceivedEventArgs e) {
    // Production suppression: drop the plain HDLC copy while FX.25 is mid-block.
    if (fx25Rec.isBusy(e.channel)) return;
    frames.add(Uint8List.fromList(e.frame.sublist(0, e.frameLength)));
  });
  hdlcRec.init(cfg);

  multiModem.addPacketReady((PacketReadyEventArgs e) {
    if (e.fecType != FecType.fx25 || e.packet == null) return;
    final Packet p = e.packet!;
    frames.add(Uint8List.fromList(p.frameData.sublist(0, p.frameLen)));
  });

  final _DecodeBridge bridge = _DecodeBridge(hdlcRec, fx25Rec);
  _runDemod(profile, sampleRate, samples, bridge);
  return frames;
}

/// Encode/decode a mono PCM buffer through the radio's SBC codec (32 kHz mono,
/// 16 blocks, 8 subbands, loudness, bitpool 18) to add Bluetooth compression
/// artifacts. A single encoder/decoder pair is reused so the filterbank state
/// carries over, matching the streaming radio link.
Int16List _sbcRoundTripPcm(Int16List samples, int sampleRate) {
  final SbcFrame frame = SbcFrame()
    ..frequency = _sbcFrequencyForRate(sampleRate)
    ..mode = SbcMode.mono
    ..allocationMethod = SbcBitAllocationMethod.loudness
    ..blocks = 16
    ..subbands = 8
    ..bitpool = 18;

  final SbcEncoder encoder = SbcEncoder();
  final SbcDecoder decoder = SbcDecoder();
  final int samplesPerFrame = frame.blocks * frame.subbands;
  final Int16List frameBuf = Int16List(samplesPerFrame);
  final List<int> out = <int>[];

  for (int off = 0; off < samples.length; off += samplesPerFrame) {
    for (int i = 0; i < samplesPerFrame; i++) {
      final int idx = off + i;
      frameBuf[i] = idx < samples.length ? samples[idx] : 0;
    }
    final Uint8List? encoded = encoder.encode(frameBuf, null, frame);
    if (encoded == null) continue;
    final SbcDecodeResult result = decoder.decode(encoded);
    if (!result.success) continue;
    out.addAll(result.pcmLeft);
  }

  return Int16List.fromList(out);
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Add additive white Gaussian noise (Box-Muller) to a PCM buffer, returning a
/// new buffer. Simulates a weak/noisy RF signal.
Int16List _addAwgn(Int16List samples, double stddev, math.Random rng) {
  if (stddev <= 0) return samples;
  final Int16List out = Int16List(samples.length);
  for (int i = 0; i < samples.length; i++) {
    final double u1 = rng.nextDouble().clamp(1e-12, 1.0);
    final double u2 = rng.nextDouble();
    final double g =
        math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
    final int v = (samples[i] + g * stddev).round();
    out[i] = v < -32768 ? -32768 : (v > 32767 ? 32767 : v);
  }
  return out;
}

/// Build a realistic BSS message packet: 0x01 + callsign field (type 0x20) +
/// message field (type 0x24) of `messageLen` bytes. Mirrors the packets the
/// radio sends, e.g. 0107204B4B37565A540424646464 = callsign "KK7VZT",
/// message "ddd" (three 0x64 bytes).
Uint8List _buildBssMessagePacket(String callsign, int messageLen) {
  final List<int> out = <int>[0x01];
  final List<int> call = callsign.codeUnits;
  out.add(call.length + 1); // length byte includes the type byte
  out.add(0x20); // callsign field type
  out.addAll(call);
  out.add(messageLen + 1); // length byte includes the type byte
  out.add(0x24); // message field type
  for (int i = 0; i < messageLen; i++) {
    out.add(0x64); // 'd'
  }
  return Uint8List.fromList(out);
}

/// Sweep raw-frame (BSS-style) lengths through a full encode -> [SBC] -> decode
/// round trip and report which lengths reliably survive. Each frame starts with
/// the 0x01 BSS indicator followed by random bytes, so bit-stuffing patterns
/// vary between trials.
int _runLoopback({
  required int baud,
  required int sampleRate,
  required int amplitude,
  required int minLen,
  required int maxLen,
  required int trials,
  required int seed,
  required bool throughSbc,
  required bool bssMode,
  required bool prodMode,
  required double noiseStddev,
}) {
  final _ModemProfile? profile = _profileForBaud(baud);
  if (profile == null) {
    stderr.writeln('Unsupported baud rate: $baud');
    return 2;
  }

  final math.Random rng = math.Random(seed);
  final List<int> failLens = <int>[];
  int totalPass = 0;
  int totalTrials = 0;

  print('Loopback length sweep: baud=$baud rate=$sampleRate Hz '
      'amp=$amplitude ${throughSbc ? "SBC=on" : "SBC=off"} '
      '${prodMode ? "path=production(FX.25-auto)" : "path=plain-AX.25"} '
      '${noiseStddev > 0 ? "noise=${noiseStddev.toStringAsFixed(0)} " : ""}'
      'trials=$trials/len seed=$seed');
  if (bssMode) {
    print('(each frame = real BSS packet: 0x01 + callsign "KK7VZT" + '
        'N-byte message; swept N = message length)');
  } else {
    print('(each frame = 0x01 BSS indicator + random bytes; swept N = total '
        'data length)');
  }
  if (prodMode) {
    print('Production path: frames >= 15 data bytes use FX.25 FEC, shorter '
        'frames use plain AX.25; RX suppresses HDLC copy while FX.25 busy.');
  } else {
    print('FCS added by hdlcSend; demod = production HdlcRec2.');
  }
  print('');

  for (int len = minLen; len <= maxLen; len++) {
    int pass = 0;
    for (int t = 0; t < trials; t++) {
      final Uint8List data;
      if (bssMode) {
        data = _buildBssMessagePacket('KK7VZT', len);
      } else {
        data = Uint8List(len);
        if (len > 0) data[0] = 0x01;
        for (int i = 1; i < len; i++) {
          data[i] = rng.nextInt(256);
        }
      }

      Int16List pcm = prodMode
          ? _encodeRawFrameProdPcm(profile, sampleRate, amplitude, data)
          : _encodeRawFramePcm(profile, sampleRate, amplitude, data);
      if (throughSbc) pcm = _sbcRoundTripPcm(pcm, sampleRate);
      if (noiseStddev > 0) pcm = _addAwgn(pcm, noiseStddev, rng);

      final List<Uint8List> rx = prodMode
          ? _decodePcmProdFrames(profile, sampleRate, pcm)
          : _decodePcmRawFrames(profile, sampleRate, pcm);
      if (rx.any((Uint8List r) => _bytesEqual(r, data))) pass++;
    }

    totalPass += pass;
    totalTrials += trials;
    final bool ok = pass == trials;
    if (!ok) failLens.add(len);
    final String status = ok ? 'ok' : (pass == 0 ? 'FAIL (0%)' : 'FLAKY');
    final int frameLen = bssMode ? (11 + len) : len;
    print('  ${bssMode ? "msg" : "data"} len ${len.toString().padLeft(3)} '
        'bytes (frame ${(frameLen + 2).toString().padLeft(3)} w/FCS): '
        '$pass/$trials  $status');
  }

  print('');
  print('Total: $totalPass/$totalTrials frames recovered.');
  if (failLens.isEmpty) {
    print('All tested lengths passed.');
  } else {
    print('Lengths with failures: ${failLens.join(", ")}');
  }
  return failLens.isEmpty ? 0 : 1;
}

// ---------------------------------------------------------------------------
// FEC diagnostic (show exactly what an FX.25-wrapped frame delivers)
// ---------------------------------------------------------------------------

Uint8List? _parseHex(String s) {
  final String clean = s.replaceAll(RegExp(r'[\s:]'), '');
  if (clean.isEmpty || clean.length.isOdd) return null;
  final Uint8List out = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    final int? b = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return null;
    out[i] = b;
  }
  return out;
}

String _toHex(Uint8List b) {
  final StringBuffer sb = StringBuffer();
  for (final int v in b) {
    sb.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString().toUpperCase();
}

/// Encode a single frame the production way (FX.25 when data >= 15 bytes) and
/// report EXACTLY what an FX.25-aware receiver and a plain-HDLC-only receiver
/// (a receiver that does not understand FX.25, e.g. Direwolf without FX.25 or a
/// hardware TNC) each deliver, byte-for-byte. Answers whether FX.25 padding
/// leaks into the delivered frame.
int _runFecDiag({
  required int baud,
  required int sampleRate,
  required int amplitude,
  required Uint8List data,
}) {
  final _ModemProfile? profile = _profileForBaud(baud);
  if (profile == null) {
    stderr.writeln('Unsupported baud rate: $baud');
    return 2;
  }

  const int ax25MinDataLen = 14 + 1;
  final bool usesFx25 = data.length >= ax25MinDataLen;

  print('FEC diagnostic: baud=$baud rate=$sampleRate Hz');
  print('Input frame (${data.length} bytes): ${_toHex(data)}');
  print('TX method (production rule >= $ax25MinDataLen data bytes): '
      '${usesFx25 ? "FX.25 (16 check bytes)" : "plain AX.25 (no FEC)"}');
  print('');

  final Int16List pcm =
      _encodeRawFrameProdPcm(profile, sampleRate, amplitude, data);

  // 1) FX.25-aware receiver (what HTCommander's own soft modem uses).
  final List<Uint8List> awareRx =
      _decodePcmProdFrames(profile, sampleRate, pcm);
  print('FX.25-aware receiver delivered ${awareRx.length} frame(s):');
  for (final Uint8List r in awareRx) {
    final bool match = _bytesEqual(r, data);
    print('  ${r.length} bytes: ${_toHex(r)}  '
        '${match ? "== input (exact)" : "!= input"}');
  }

  // 2) Plain-HDLC-only receiver (no FX.25 support - what a legacy TNC/Direwolf
  //    without FX.25 or a hardware radio would decode from the same signal).
  final List<Uint8List> plainRx =
      _decodePcmRawFrames(profile, sampleRate, pcm);
  print('Plain-HDLC-only receiver (no FX.25) delivered '
      '${plainRx.length} frame(s):');
  for (final Uint8List r in plainRx) {
    final bool match = _bytesEqual(r, data);
    print('  ${r.length} bytes: ${_toHex(r)}  '
        '${match ? "== input (exact)" : "!= input"}');
  }

  print('');
  final bool awareOk = awareRx.any((Uint8List r) => _bytesEqual(r, data));
  final bool plainOk = plainRx.any((Uint8List r) => _bytesEqual(r, data));
  print('Result: FX.25-aware RX ${awareOk ? "recovered" : "did NOT recover"} '
      'the exact frame; plain-HDLC RX '
      '${plainOk ? "recovered" : "did NOT recover"} the exact frame.');
  return (awareOk && plainOk) ? 0 : 1;
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

  SBC round-trip (add Bluetooth codec artifacts to a WAV):
    dart run test/soft_modem_tool.dart sbc [--bitpool <n>] [--subbands <4|8>] [--blocks <4|8|12|16>] [--alloc <loudness|snr>] [--msbc] <in.wav> <out.wav>

  Loopback length sweep (find lengths that fail to decode, e.g. BSS):
    dart run test/soft_modem_tool.dart loopback -B <baud> [-r <rate>] [--bss] [--prod] [--sbc] [--min <n>] [--max <n>] [--trials <n>] [-s <seed>]

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
  --bitpool <n>   SBC bitpool for sbc (default 18, the radio's value)
  --subbands <n>  SBC subbands 4 or 8 for sbc (default 8)
  --blocks <n>    SBC blocks 4/8/12/16 for sbc (default 16)
  --alloc <m>     SBC allocation 'loudness' or 'snr' for sbc (default loudness)
  --msbc          Use the mSBC preset (16 kHz, 15 blocks, bitpool 26) for sbc
  --bss           loopback: send real BSS packets (callsign + N-byte message)
  --prod          loopback: use the production TX/RX path (FX.25 for >=15-byte
                  frames, plain AX.25 otherwise, FX.25-busy HDLC suppression)
  --sbc           loopback: route audio through the Bluetooth SBC codec
  --min <n>       loopback: first length to test (default 0)
  --max <n>       loopback: last length to test (default 40)
  --trials <n>    loopback: trials per length (default 5)

The sbc command defaults match the radio's 32 kHz mono link. Generate the
clean WAV at 32 kHz so the round-trip matches on-air audio, e.g.:
  encode -B 2400 -r 32000 -o clean.wav data.txt
  sbc clean.wav artifact.wav
  decode -B 2400 artifact.wav

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
  if (command != 'encode' &&
      command != 'decode' &&
      command != 'corrupt' &&
      command != 'sbc' &&
      command != 'loopback' &&
      command != 'fecdiag') {
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
  int bitpool = 18;
  int blocks = 16;
  int subbands = 8;
  bool loudness = true;
  bool msbc = false;
  int loopMin = 0;
  int loopMax = 40;
  int loopTrials = 5;
  bool loopBss = false;
  bool loopSbc = false;
  bool loopProd = false;
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
      case '--bitpool':
        bitpool = _parseIntOr(_next(args, ++i), bitpool);
        break;
      case '--blocks':
        blocks = _parseIntOr(_next(args, ++i), blocks);
        break;
      case '--subbands':
        subbands = _parseIntOr(_next(args, ++i), subbands);
        break;
      case '--alloc':
        loudness = (_next(args, ++i) ?? 'loudness').toLowerCase() != 'snr';
        break;
      case '--msbc':
        msbc = true;
        break;
      case '--bss':
        loopBss = true;
        break;
      case '--sbc':
        loopSbc = true;
        break;
      case '--prod':
        loopProd = true;
        break;
      case '--min':
        loopMin = _parseIntOr(_next(args, ++i), loopMin);
        break;
      case '--max':
        loopMax = _parseIntOr(_next(args, ++i), loopMax);
        break;
      case '--trials':
        loopTrials = _parseIntOr(_next(args, ++i), loopTrials);
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
  } else if (command == 'sbc') {
    if (positional.length < 2) {
      stderr.writeln('sbc: usage: sbc [options] <in.wav> <out.wav>');
      _printUsage();
      exit(2);
    }
    exit(_runSbc(
      inputFile: positional[0],
      outputFile: positional[1],
      bitpool: bitpool,
      blocks: blocks,
      subbands: subbands,
      loudness: loudness,
      msbc: msbc,
    ));
  } else if (command == 'loopback') {
    exit(_runLoopback(
      baud: baud,
      sampleRate: sampleRate,
      amplitude: amplitude,
      minLen: loopMin,
      maxLen: loopMax,
      trials: loopTrials,
      seed: seed,
      throughSbc: loopSbc,
      bssMode: loopBss,
      prodMode: loopProd,
      noiseStddev: noiseStddev,
    ));
  } else if (command == 'fecdiag') {
    if (positional.isEmpty) {
      stderr.writeln('fecdiag: usage: fecdiag -B <baud> <hex-frame>');
      stderr.writeln('  e.g. fecdiag -B 2400 0107204B4B37565A540424646464');
      exit(2);
    }
    final Uint8List? data = _parseHex(positional.first);
    if (data == null) {
      stderr.writeln('fecdiag: invalid hex frame: ${positional.first}');
      exit(2);
    }
    exit(_runFecDiag(
      baud: baud,
      sampleRate: sampleRate,
      amplitude: amplitude,
      data: data,
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
