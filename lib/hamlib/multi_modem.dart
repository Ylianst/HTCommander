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
// multi_modem.dart - Use multiple modems in parallel to increase chances of decoding
//
// Ported from C# HamLib/MultiModem.cs
//

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'audio_config.dart';
import 'ax25_pad.dart';
import 'correction_info.dart';
import 'hdlc_rec2.dart';

/// FEC type for received signal.
enum FecType {
  none, // 0
  fx25, // 1
  il2p, // 2
}

/// Candidate packet for best selection.
class _CandidatePacket {
  Packet? packetP;
  ALevel alevel = ALevel();
  double speedError = 0.0;
  FecType fecType = FecType.none;
  int retries = RetryType.none;
  int age = 0;
  int crc = 0;
  int score = 0;
  CorrectionInfo? correctionInfo;
}

/// Event arguments for packet ready event.
class PacketReadyEventArgs {
  int channel = 0;
  int subchannel = 0;
  int slice = 0;
  Packet? packet;
  ALevel audioLevel = ALevel();
  FecType fecType = FecType.none;
  int retries = RetryType.none;
  String spectrum = '';
  int ctagNum = -1; // FX.25 correlation tag number (-1 = none)
  CorrectionInfo? correctionInfo; // Detailed error correction information
}

/// Multi-modem manager - coordinates multiple demodulators and slicers.
class MultiModem {
  // Constants
  static const int _maxRadioChannels = 6;
  static const int _maxSubchannels = 9;
  static const int _maxSlicers = 9;
  static const int _processAfterBits = 3;

  // Audio configuration
  AudioConfig? _audioConfig;

  // Candidates for further processing
  late List<List<List<_CandidatePacket>>> _candidates;

  // Process age tracking
  late List<int> _processAge;

  // DC average tracking
  late List<double> _dcAverage;

  // FX.25 busy state (simplified for now)
  late List<bool> _fx25Busy;

  // Packet ready listeners (mirror C# event with += semantics).
  final List<void Function(PacketReadyEventArgs)> _packetReadyListeners = [];

  MultiModem() {
    _candidates = List.generate(
      _maxRadioChannels,
      (_) => List.generate(
        _maxSubchannels,
        (_) => List.generate(_maxSlicers, (_) => _CandidatePacket()),
      ),
    );
    _processAge = List<int>.filled(_maxRadioChannels, 0);
    _dcAverage = List<double>.filled(_maxRadioChannels, 0.0);
    _fx25Busy = List<bool>.filled(_maxRadioChannels, false);
  }

  /// Register a packet ready handler (mirror of C# `PacketReady +=`).
  void addPacketReady(void Function(PacketReadyEventArgs) handler) {
    _packetReadyListeners.add(handler);
  }

  /// Initialize multi-modem with audio configuration.
  void init(AudioConfig audioConfig) {
    _audioConfig = audioConfig;

    // Clear candidates
    for (int chan = 0; chan < _maxRadioChannels; chan++) {
      for (int subchan = 0; subchan < _maxSubchannels; subchan++) {
        for (int slice = 0; slice < _maxSlicers; slice++) {
          _candidates[chan][subchan][slice] = _CandidatePacket();
        }
      }
    }

    // Calculate process age for each channel
    for (int chan = 0; chan < _maxRadioChannels; chan++) {
      if (audioConfig.channelMedium[chan] == Medium.radio) {
        if (audioConfig.channels[chan].baud <= 0) {
          print('Internal error, chan=$chan, MultiModem.Init');
          audioConfig.channels[chan].baud = 1200; // Default
        }

        int realBaud = audioConfig.channels[chan].baud;

        // Adjust for multi-bit modems
        if (audioConfig.channels[chan].modemType == ModemType.qpsk) {
          realBaud = audioConfig.channels[chan].baud ~/ 2;
        } else if (audioConfig.channels[chan].modemType == ModemType.psk8) {
          realBaud = audioConfig.channels[chan].baud ~/ 3;
        }

        final int adevIndex = AudioConfig.channelToDevice(chan);
        final int samplesPerSec = audioConfig.devices[adevIndex].samplesPerSec;

        _processAge[chan] = _processAfterBits * samplesPerSec ~/ realBaud;
      }
    }
  }

  /// Get DC average for a channel (scaled to +- 200).
  int getDcAverage(int chan) {
    if (chan < 0 || chan >= _maxRadioChannels) return 0;
    // Scale to +- 200 so it will be like the deviation measurement
    return (_dcAverage[chan] * (200.0 / 32767.0)).toInt();
  }

  /// Process a single audio sample.
  void processSample(int chan, int audioSample) {
    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return;

    if (chan < 0 || chan >= _maxRadioChannels) return;

    // Accumulate an average DC bias level
    _dcAverage[chan] = _dcAverage[chan] * 0.999 + audioSample * 0.001;

    // Validate configuration
    if (cfg.channels[chan].numSubchan <= 0 ||
        cfg.channels[chan].numSubchan > _maxSubchannels ||
        cfg.channels[chan].numSlicers <= 0 ||
        cfg.channels[chan].numSlicers > _maxSlicers) {
      print('ERROR! Something is seriously wrong in MultiModem.ProcessSample');
      print(
        'chan = $chan, num_subchan = ${cfg.channels[chan].numSubchan} '
        '[max $_maxSubchannels], num_slicers = ${cfg.channels[chan].numSlicers} '
        '[max $_maxSlicers]',
      );
      print(
        'Please report this message and include a copy of your configuration.',
      );
      return;
    }

    // Age candidates and check if they're ready to process
    for (int subchan = 0; subchan < cfg.channels[chan].numSubchan; subchan++) {
      for (int slice = 0; slice < cfg.channels[chan].numSlicers; slice++) {
        if (_candidates[chan][subchan][slice].packetP != null) {
          _candidates[chan][subchan][slice].age++;

          if (_candidates[chan][subchan][slice].age > _processAge[chan]) {
            if (_fx25Busy[chan]) {
              // Reset age if FX.25 is busy
              _candidates[chan][subchan][slice].age = 0;
            } else {
              _pickBestCandidate(chan);
            }
          }
        }
      }
    }
  }

  /// Process a received frame.
  void processRecFrame(
    int chan,
    int subchan,
    int slice,
    Uint8List fbuf,
    int flen,
    ALevel alevel,
    int retries,
    FecType fecType, [
    int ctagNum = -1,
    CorrectionInfo? correctionInfo,
  ]) {
    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return;

    assert(chan >= 0 && chan < _maxRadioChannels);
    assert(subchan >= 0 && subchan < _maxSubchannels);
    assert(slice >= 0 && slice < _maxSlicers);

    Packet? pp;

    // Special encapsulation for AIS & EAS
    if (cfg.channels[chan].modemType == ModemType.ais) {
      // AIS to NMEA conversion would go here
      const String monfmt = 'AIS>APRS,NOGATE:{AIS_DATA}';
      pp = Packet.fromText(monfmt, false);
    } else if (cfg.channels[chan].modemType == ModemType.eas) {
      // EAS encapsulation
      const String monfmt = 'EAS>APRS,NOGATE:{EAS_DATA}';
      pp = Packet.fromText(monfmt, false);
    } else {
      pp = Packet.fromFrame(fbuf, flen, alevel);
    }

    processRecPacket(
      chan,
      subchan,
      slice,
      pp,
      alevel,
      retries,
      fecType,
      ctagNum,
      correctionInfo,
    );
  }

  /// Process a received packet.
  void processRecPacket(
    int chan,
    int subchan,
    int slice,
    Packet? pp,
    ALevel alevel,
    int retries,
    FecType fecType, [
    int ctagNum = -1,
    CorrectionInfo? correctionInfo,
  ]) {
    if (pp == null) {
      print('Unexpected internal problem in MultiModem.ProcessRecPacket');
      return;
    }

    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return;

    // If only one demodulator/slicer, and no FX.25 in progress, push it through immediately
    if (cfg.channels[chan].numSubchan == 1 &&
        cfg.channels[chan].numSlicers == 1 &&
        !_fx25Busy[chan]) {
      const bool dropIt = false;

      // ignore: dead_code
      if (dropIt) {
        // Packet deleted (simulated drop)
      } else {
        // Send directly to application
        _onPacketReady(
          PacketReadyEventArgs()
            ..channel = chan
            ..subchannel = subchan
            ..slice = slice
            ..packet = pp
            ..audioLevel = alevel
            ..fecType = fecType
            ..retries = retries
            ..spectrum = ''
            ..ctagNum = ctagNum
            ..correctionInfo = correctionInfo,
        );
      }
      return;
    }

    // Otherwise, save for later selection
    if (_candidates[chan][subchan][slice].packetP != null) {
      // Replace existing candidate (FX.25 has priority)
      _candidates[chan][subchan][slice].packetP = null;
    }

    _candidates[chan][subchan][slice].packetP = pp;
    _candidates[chan][subchan][slice].alevel = alevel;
    _candidates[chan][subchan][slice].fecType = fecType;
    _candidates[chan][subchan][slice].retries = retries;
    _candidates[chan][subchan][slice].age = 0;
    _candidates[chan][subchan][slice].crc = pp.multiModemCrc();
    _candidates[chan][subchan][slice].correctionInfo = correctionInfo;
  }

  /// Pick the best candidate from all available options.
  void _pickBestCandidate(int chan) {
    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return;

    if (cfg.channels[chan].numSlicers < 1) {
      cfg.channels[chan].numSlicers = 1;
    }

    final int numBars =
        cfg.channels[chan].numSlicers * cfg.channels[chan].numSubchan;
    final List<int> spectrum = List<int>.filled(numBars + 1, 0x5F /* '_' */);

    int bestN = 0;
    int bestScore = 0;

    // Build spectrum display and calculate scores
    for (int n = 0; n < numBars; n++) {
      final int j = _subchanFromN(n, chan);
      final int k = _sliceFromN(n, chan);

      // Build the spectrum display
      if (_candidates[chan][j][k].packetP == null) {
        spectrum[n] = 0x5F; // '_'
      } else if (_candidates[chan][j][k].fecType != FecType.none) {
        // FX.25 or IL2P
        final int retries = _candidates[chan][j][k].retries;
        if (retries <= 9) {
          spectrum[n] = 0x30 + retries; // '0' + retries
        } else {
          spectrum[n] = 0x2B; // '+'
        }
      } else if (_candidates[chan][j][k].retries == RetryType.none) {
        spectrum[n] = 0x7C; // '|'
      } else if (_candidates[chan][j][k].retries == RetryType.invertSingle) {
        spectrum[n] = 0x3A; // ':'
      } else {
        spectrum[n] = 0x2E; // '.'
      }

      // Calculate beginning score based on effort to get valid frame CRC
      if (_candidates[chan][j][k].packetP == null) {
        _candidates[chan][j][k].score = 0;
      } else {
        if (_candidates[chan][j][k].fecType != FecType.none) {
          // Has FEC
          _candidates[chan][j][k].score =
              9000 - 100 * _candidates[chan][j][k].retries;
        } else {
          // Regular AX.25
          _candidates[chan][j][k].score =
              RetryType.max * 1000 -
              (_candidates[chan][j][k].retries * 1000) +
              1;
        }
      }
    }

    // Bump up score if others nearby have the same CRC
    for (int n = 0; n < numBars; n++) {
      final int j = _subchanFromN(n, chan);
      final int k = _sliceFromN(n, chan);

      if (_candidates[chan][j][k].packetP != null) {
        for (int m = 0; m < numBars; m++) {
          final int mj = _subchanFromN(m, chan);
          final int mk = _sliceFromN(m, chan);

          if (m != n && _candidates[chan][mj][mk].packetP != null) {
            if (_candidates[chan][j][k].crc == _candidates[chan][mj][mk].crc) {
              _candidates[chan][j][k].score += (numBars + 1) - (m - n).abs();
            }
          }
        }
      }
    }

    // Find best score
    for (int n = 0; n < numBars; n++) {
      final int j = _subchanFromN(n, chan);
      final int k = _sliceFromN(n, chan);

      if (_candidates[chan][j][k].packetP != null) {
        if (_candidates[chan][j][k].score > bestScore) {
          bestScore = _candidates[chan][j][k].score;
          bestN = n;
        }
      }
    }

    if (bestScore == 0) {
      print(
        'Unexpected internal problem in MultiModem.PickBestCandidate. '
        'How can best score be zero?',
      );
    }

    // Delete those not chosen
    for (int n = 0; n < numBars; n++) {
      final int j = _subchanFromN(n, chan);
      final int k = _sliceFromN(n, chan);

      if (n != bestN && _candidates[chan][j][k].packetP != null) {
        _candidates[chan][j][k].packetP = null;
      }
    }

    // Pass along the best one
    final int bestJ = _subchanFromN(bestN, chan);
    final int bestK = _sliceFromN(bestN, chan);

    const bool dropIt = false;

    // ignore: dead_code
    if (dropIt) {
      _candidates[chan][bestJ][bestK].packetP = null;
    } else {
      _onPacketReady(
        PacketReadyEventArgs()
          ..channel = chan
          ..subchannel = bestJ
          ..slice = bestK
          ..packet = _candidates[chan][bestJ][bestK].packetP
          ..audioLevel = _candidates[chan][bestJ][bestK].alevel
          ..fecType = _candidates[chan][bestJ][bestK].fecType
          ..retries = _candidates[chan][bestJ][bestK].retries
          ..spectrum = String.fromCharCodes(spectrum.sublist(0, numBars))
          ..correctionInfo = _candidates[chan][bestJ][bestK].correctionInfo,
      );

      // Clear ownership
      _candidates[chan][bestJ][bestK].packetP = null;
    }

    // Clear in preparation for next time
    for (int subchan = 0; subchan < _maxSubchannels; subchan++) {
      for (int slice = 0; slice < _maxSlicers; slice++) {
        _candidates[chan][subchan][slice] = _CandidatePacket();
      }
    }
  }

  /// Helper: Get subchannel from linear index.
  int _subchanFromN(int n, int chan) {
    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return 0;
    return n % cfg.channels[chan].numSubchan;
  }

  /// Helper: Get slice from linear index.
  int _sliceFromN(int n, int chan) {
    final AudioConfig? cfg = _audioConfig;
    if (cfg == null) return 0;
    return n ~/ cfg.channels[chan].numSubchan;
  }

  /// Set FX.25 busy state for a channel.
  void setFx25Busy(int chan, bool busy) {
    if (chan >= 0 && chan < _maxRadioChannels) {
      _fx25Busy[chan] = busy;
    }
  }

  /// Raise packet ready event.
  void _onPacketReady(PacketReadyEventArgs e) {
    for (final l in List.of(_packetReadyListeners)) {
      l(e);
    }
  }
}
