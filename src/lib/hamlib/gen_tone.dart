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
// gen_tone.dart - AFSK tone generation for encoding
//
// Ported from C# HamLib/GenTone.cs
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_buffer.dart';
import 'audio_config.dart';

/// Generates AFSK tones for audio encoding.
class GenTone {
  static const double _ticksPerCycle = 256.0 * 256.0 * 256.0 * 256.0;
  // ignore: unused_field
  static const int _phaseShift180 = 128 << 24;
  static const int _phaseShift90 = 64 << 24;
  static const int _phaseShift45 = 32 << 24;

  late AudioConfig _audioConfig;
  final AudioBuffer _audioBuffer;
  final Int16List _sineTable;
  // ignore: unused_field
  int _amp16bit = 0;

  // Per-channel state
  late List<int> _ticksPerSample;
  late List<int> _ticksPerBit;
  late List<int> _f1ChangePerSample;
  late List<int> _f2ChangePerSample;
  late List<double> _samplesPerSymbol;
  late List<int> _tonePhase;
  late List<int> _bitLenAcc;
  late List<int> _lfsr;
  late List<int> _bitCount;
  late List<int> _saveBit;
  late List<int> _prevDat;

  GenTone(this._audioBuffer) : _sineTable = Int16List(256) {
    _ticksPerSample = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _ticksPerBit = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _f1ChangePerSample = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _f2ChangePerSample = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _samplesPerSymbol = List<double>.filled(AudioConfig.maxRadioChannels, 0.0);
    _tonePhase = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _bitLenAcc = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _lfsr = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _bitCount = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _saveBit = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _prevDat = List<int>.filled(AudioConfig.maxRadioChannels, 0);
  }

  /// Initialize tone generator.
  void init(AudioConfig audioConfig, int amp) {
    _audioConfig = audioConfig;
    _amp16bit = (32767 * amp) ~/ 100;

    for (int chan = 0; chan < AudioConfig.maxRadioChannels; chan++) {
      if (_audioConfig.channelMedium[chan] == Medium.radio) {
        final int a = AudioConfig.channelToDevice(chan);

        _tonePhase[chan] = 0;
        _bitLenAcc[chan] = 0;
        _lfsr[chan] = 0;
        _bitCount[chan] = 0;
        _saveBit[chan] = 0;
        _prevDat[chan] = 0;

        _ticksPerSample[chan] =
            (_ticksPerCycle / _audioConfig.devices[a].samplesPerSec + 0.5)
                .toInt();

        final AudioChannelConfig chanConfig = _audioConfig.channels[chan];

        switch (chanConfig.modemType) {
          case ModemType.qpsk:
            chanConfig.markFreq = 1800;
            chanConfig.spaceFreq = chanConfig.markFreq;
            _ticksPerBit[chan] =
                (_ticksPerCycle / (chanConfig.baud * 0.5) + 0.5).toInt();
            _f1ChangePerSample[chan] =
                (chanConfig.markFreq *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            _f2ChangePerSample[chan] = _f1ChangePerSample[chan];
            _samplesPerSymbol[chan] =
                2.0 * _audioConfig.devices[a].samplesPerSec / chanConfig.baud;
            _tonePhase[chan] = _phaseShift45;
            break;

          case ModemType.psk8:
            chanConfig.markFreq = 1800;
            chanConfig.spaceFreq = chanConfig.markFreq;
            _ticksPerBit[chan] =
                (_ticksPerCycle / (chanConfig.baud / 3.0) + 0.5).toInt();
            _f1ChangePerSample[chan] =
                (chanConfig.markFreq *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            _f2ChangePerSample[chan] = _f1ChangePerSample[chan];
            _samplesPerSymbol[chan] =
                3.0 * _audioConfig.devices[a].samplesPerSec / chanConfig.baud;
            break;

          case ModemType.baseband:
          case ModemType.scramble:
          case ModemType.ais:
            _ticksPerBit[chan] = (_ticksPerCycle / chanConfig.baud + 0.5)
                .toInt();
            _f1ChangePerSample[chan] =
                (chanConfig.baud *
                            0.5 *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            _samplesPerSymbol[chan] =
                _audioConfig.devices[a].samplesPerSec / chanConfig.baud;
            break;

          case ModemType.eas:
            _ticksPerBit[chan] = (_ticksPerCycle / 520.833333333333 + 0.5)
                .toInt();
            _samplesPerSymbol[chan] =
                (_audioConfig.devices[a].samplesPerSec / 520.83333 + 0.5)
                    .toInt()
                    .toDouble();
            _f1ChangePerSample[chan] =
                (2083.33333333333 *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            _f2ChangePerSample[chan] =
                (1562.5000000 *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            break;

          default: // AFSK
            _ticksPerBit[chan] = (_ticksPerCycle / chanConfig.baud + 0.5)
                .toInt();
            _samplesPerSymbol[chan] =
                _audioConfig.devices[a].samplesPerSec / chanConfig.baud;
            _f1ChangePerSample[chan] =
                (chanConfig.markFreq *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            _f2ChangePerSample[chan] =
                (chanConfig.spaceFreq *
                            _ticksPerCycle /
                            _audioConfig.devices[a].samplesPerSec +
                        0.5)
                    .toInt();
            break;
        }
      }
    }

    // Generate sine table
    for (int j = 0; j < 256; j++) {
      final double a = (j / 256.0) * (2 * math.pi);
      int s = (math.sin(a) * 32767 * amp / 100.0).toInt();

      if (s < -32768) {
        s = -32768;
      } else if (s > 32767) {
        s = 32767;
      }
      _sineTable[j] = s;
    }
  }

  /// Generate tone for one data bit.
  void putBit(int chan, int dat) {
    final int a = AudioConfig.channelToDevice(chan);

    if (_audioConfig.channelMedium[chan] != Medium.radio) {
      print('Invalid channel $chan for tone generation.');
      return;
    }

    if (dat < 0) {
      // Hack to test receive PLL recovery
      _bitLenAcc[chan] -= _ticksPerBit[chan];
      dat = 0;
    }

    final AudioChannelConfig chanConfig = _audioConfig.channels[chan];

    // Handle multi-bit symbols for QPSK and 8PSK
    if (chanConfig.modemType == ModemType.qpsk) {
      dat &= 1;
      if ((_bitCount[chan] & 1) == 0) {
        _saveBit[chan] = dat;
        _bitCount[chan]++;
        return;
      }

      final int dibit = (_saveBit[chan] << 1) | dat;
      const List<int> gray2phase = [0, 1, 3, 2];
      final int symbol = gray2phase[dibit];
      _tonePhase[chan] =
          (_tonePhase[chan] + symbol * _phaseShift90) & 0xFFFFFFFF;
      if (chanConfig.v26Alt == V26Alternative.b) {
        _tonePhase[chan] = (_tonePhase[chan] + _phaseShift45) & 0xFFFFFFFF;
      }
      _bitCount[chan]++;
    } else if (chanConfig.modemType == ModemType.psk8) {
      dat &= 1;
      if (_bitCount[chan] < 2) {
        _saveBit[chan] = (_saveBit[chan] << 1) | dat;
        _bitCount[chan]++;
        return;
      }

      final int tribit = (_saveBit[chan] << 1) | dat;
      const List<int> gray2phase = [1, 0, 2, 3, 6, 7, 5, 4];
      final int symbol = gray2phase[tribit];
      _tonePhase[chan] =
          (_tonePhase[chan] + symbol * _phaseShift45) & 0xFFFFFFFF;
      _saveBit[chan] = 0;
      _bitCount[chan] = 0;
    }

    // Scrambler for certain modes
    if (chanConfig.modemType == ModemType.scramble &&
        chanConfig.layer2Xmit != Layer2Type.il2p) {
      final int x = (dat ^ (_lfsr[chan] >> 16) ^ (_lfsr[chan] >> 11)) & 1;
      _lfsr[chan] = (_lfsr[chan] << 1) | (x & 1);
      dat = x;
    }

    // Generate audio samples for this bit
    do {
      int sam;

      switch (chanConfig.modemType) {
        case ModemType.afsk:
          _tonePhase[chan] =
              (_tonePhase[chan] +
                  (dat != 0
                      ? _f1ChangePerSample[chan]
                      : _f2ChangePerSample[chan])) &
              0xFFFFFFFF;
          sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
          _putSample(chan, a, sam);
          break;

        case ModemType.eas:
          _tonePhase[chan] =
              (_tonePhase[chan] +
                  (dat != 0
                      ? _f1ChangePerSample[chan]
                      : _f2ChangePerSample[chan])) &
              0xFFFFFFFF;
          sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
          _putSample(chan, a, sam);
          break;

        case ModemType.qpsk:
        case ModemType.psk8:
          _tonePhase[chan] =
              (_tonePhase[chan] + _f1ChangePerSample[chan]) & 0xFFFFFFFF;
          sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
          _putSample(chan, a, sam);
          break;

        case ModemType.baseband:
        case ModemType.scramble:
        case ModemType.ais:
          if (dat != _prevDat[chan]) {
            _tonePhase[chan] =
                (_tonePhase[chan] + _f1ChangePerSample[chan]) & 0xFFFFFFFF;
          } else {
            if ((_tonePhase[chan] & 0x80000000) != 0) {
              _tonePhase[chan] = 0xc0000000; // 270 degrees
            } else {
              _tonePhase[chan] = 0x40000000; // 90 degrees
            }
          }
          sam = _sineTable[(_tonePhase[chan] >> 24) & 0xff];
          _putSample(chan, a, sam);
          break;

        default:
          print(
            'INTERNAL ERROR: Modem type ${chanConfig.modemType} not implemented',
          );
          return;
      }

      _bitLenAcc[chan] += _ticksPerSample[chan];
    } while (_bitLenAcc[chan] < _ticksPerBit[chan]);

    _bitLenAcc[chan] -= _ticksPerBit[chan];
    _prevDat[chan] = dat;
  }

  /// Generate quiet period (silence).
  void putQuietMs(int chan, int timeMs) {
    final int a = AudioConfig.channelToDevice(chan);
    const int sam = 0;
    final int nsamples =
        (timeMs * _audioConfig.devices[a].samplesPerSec / 1000.0 + 0.5).toInt();

    for (int j = 0; j < nsamples; j++) {
      _putSample(chan, a, sam);
    }

    // Avoid abrupt change when it starts up again
    _tonePhase[chan] = 0;
  }

  /// Put a single audio sample.
  void _putSample(int chan, int device, int sample) {
    // Clamp to 16-bit range
    if (sample < -32768) sample = -32768;
    if (sample > 32767) sample = 32767;

    _audioBuffer.put(device, sample);
  }
}
