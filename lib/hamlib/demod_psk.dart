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
// demod_psk.dart - PSK (Phase Shift Keying) Demodulator
// Port of demod_psk.c from Dire Wolf
//
// Ported from C# HamLib/DemodPsk.cs
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_config.dart';
import 'demod_afsk.dart';
import 'dsp.dart';
import 'ihdlc_receiver.dart';

/// PSK-specific demodulator state.
class PskState {
  V26Alternative v26Alt =
      V26Alternative.unspecified; // Which alternative when V.26
  final Float32List sinTable256 = Float32List(
    256,
  ); // Precomputed sin table for speed

  // Optional band pass pre-filter before phase detector
  int usePrefilter = 0; // True to enable it
  double prefilterBaud = 0; // Cutoff frequencies as fraction of baud rate
  double preFilterWidthSym = 0; // Length in number of symbol times
  BpWindowType preWindow = BpWindowType.truncated; // Window type
  int preFilterTaps = 0; // Size of pre filter in audio samples
  final Float32List audioIn = Float32List(
    Dsp.maxFilterSize,
  ); // Audio input buffer
  final Float32List preFilter = Float32List(
    Dsp.maxFilterSize,
  ); // Pre-filter coefficients

  // Use local oscillator or correlate with previous sample
  int pskUseLo = 0; // Use local oscillator rather than self correlation
  int loStep = 0; // How much to advance LO phase per sample
  int loPhase = 0; // Local oscillator phase accumulator

  // After mixing with LO before low pass filter
  final Float32List iRaw = Float32List(Dsp.maxFilterSize); // signal * LO cos
  final Float32List qRaw = Float32List(Dsp.maxFilterSize); // signal * LO sin

  // Delay line for correlation with previous symbol
  int bOffs = 0; // Symbol length based on sample rate and baud
  int cOffs = 0; // To get cos component of previous symbol
  int sOffs = 0; // To get sin component of previous symbol
  double delayLineWidthSym = 0; // Delay line width in symbols
  int delayLineTaps = 0; // In audio samples
  final Float32List delayLine = Float32List(
    Dsp.maxFilterSize,
  ); // Delay line buffer

  // Low pass filter
  double lpfBaud = 0; // Cutoff frequency as fraction of baud
  double lpFilterWidthSym = 0; // Length in number of symbol times
  int lpFilterTaps = 0; // Size of low pass filter in audio samples
  BpWindowType lpWindow = BpWindowType.truncated; // Window type
  final Float32List lpFilter = Float32List(
    Dsp.maxFilterSize,
  ); // Low pass filter coefficients
}

/// Extended demodulator state for PSK.
class PskDemodulatorState extends DemodulatorState {
  ModemType modemType = ModemType.qpsk; // QPSK or 8PSK
  final PskState psk = PskState(); // PSK-specific state
}

/// PSK Demodulator for 2400 and 4800 bps Phase Shift Keying.
class DemodPsk {
  // Phase to Gray code conversion tables
  static const List<int> _phaseToGrayV26 = [0, 1, 3, 2];
  static const List<int> _phaseToGrayV27 = [1, 0, 2, 3, 7, 6, 4, 5];

  // DCD detection constants
  static const int _dcdThreshOn = 30; // Hysteresis for DCD detect
  static const int _dcdThreshOff = 6;
  static const int _dcdGoodWidth = 512;

  final IHdlcReceiver _hdlcRec;

  DemodPsk(this._hdlcRec);

  /// Add sample to buffer and shift the rest down.
  static void _pushSample(double val, Float32List buff, int size) {
    buff.setRange(1, size, buff.sublist(0, size - 1));
    buff[0] = val;
  }

  /// FIR filter convolution kernel.
  static double _convolve(
    Float32List data,
    Float32List filter,
    int filterSize,
  ) {
    double sum = 0.0;
    for (int j = 0; j < filterSize; j++) {
      sum += filter[j] * data[j];
    }
    return sum;
  }

  /// Fast atan2 approximation.
  static double _myAtan2f(double y, double x) {
    if (y == 0 && x == 0) return 0.0; // Handle special case
    return math.atan2(y, x);
  }

  /// Reinterpret a value as a signed 32-bit integer.
  static int _toInt32(int v) {
    v &= 0xFFFFFFFF;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Translate phase shift between two symbols into 2 or 3 bits.
  static int _phaseShiftToSymbol(
    double phaseShift,
    int bitsPerSymbol,
    List<int> bitQuality,
  ) {
    assert(bitsPerSymbol == 2 || bitsPerSymbol == 3);
    final int n = 1 << bitsPerSymbol;
    assert(n == 4 || n == 8);

    // Scale angle to 1 per symbol then separate into integer and fractional parts
    double a = phaseShift * n / (math.pi * 2.0);
    while (a >= n) {
      a -= n;
    }
    while (a < 0) {
      a += n;
    }
    int i = a.toInt();
    if (i == n) {
      i = n - 1; // Should be < N. Watch out for possible roundoff errors
    }
    final double f = a - i;
    assert(i >= 0 && i < n);
    assert(f >= -0.001 && f <= 1.001);

    // Interpolate between the ideal angles to get a level of certainty
    int result = 0;
    for (int b = 0; b < bitsPerSymbol; b++) {
      final double demod = bitsPerSymbol == 2
          ? ((_phaseToGrayV26[i] >> b) & 1) * (1.0 - f) +
                ((_phaseToGrayV26[(i + 1) & 3] >> b) & 1) * f
          : ((_phaseToGrayV27[i] >> b) & 1) * (1.0 - f) +
                ((_phaseToGrayV27[(i + 1) & 7] >> b) & 1) * f;

      // Slice to get boolean value and quality measurement
      if (demod >= 0.5) result |= 1 << b;
      bitQuality[b] = (100.0 * 2.0 * (demod - 0.5).abs()).round();
    }
    return result;
  }

  /// Initialize PSK demodulator.
  void init(
    ModemType modemType,
    V26Alternative v26Alt,
    int samplesPerSec,
    int bps,
    String profile,
    PskDemodulatorState d,
  ) {
    int correctBaud; // baud is not same as bits/sec here!
    int carrierFreq;

    d.modemType = modemType;
    d.psk.v26Alt = v26Alt;
    d.numSlicers = 1; // Haven't thought about this yet. Is it even applicable?

    if (modemType == ModemType.qpsk) {
      assert(d.psk.v26Alt != V26Alternative.unspecified);

      correctBaud = bps ~/ 2;
      carrierFreq = 1800;

      switch (profile.toUpperCase()) {
        case 'P': // Self correlation technique
          d.psk.usePrefilter = 0; // No bandpass filter
          d.psk.lpfBaud = 0.60;
          d.psk.lpFilterWidthSym = 1.061;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.95;
          d.pllSearchingInertia = 0.50;
          break;

        case 'Q': // Self correlation technique with prefilter
          d.psk.usePrefilter = 1; // Add a bandpass filter
          d.psk.prefilterBaud = 1.3;
          d.psk.preFilterWidthSym = 1.497;
          d.psk.preWindow = BpWindowType.cosine;
          d.psk.lpfBaud = 0.60;
          d.psk.lpFilterWidthSym = 1.061;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.87;
          d.pllSearchingInertia = 0.50;
          break;

        case 'S': // Mix with local oscillator with prefilter
          d.psk.pskUseLo = 1;
          d.psk.usePrefilter = 1; // Add a bandpass filter
          d.psk.prefilterBaud = 0.55;
          d.psk.preFilterWidthSym = 2.014;
          d.psk.preWindow = BpWindowType.flattop;
          d.psk.lpfBaud = 0.60;
          d.psk.lpFilterWidthSym = 1.061;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;

        case 'R': // Mix with local oscillator
        default:
          d.psk.pskUseLo = 1;
          d.psk.usePrefilter = 0; // No bandpass filter
          d.psk.lpfBaud = 0.70;
          d.psk.lpFilterWidthSym = 1.007;
          d.psk.lpWindow = BpWindowType.truncated;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
      }

      d.psk.delayLineWidthSym = 1.25; // Delay line > 13/12 * symbol period
      d.psk.cOffs = ((11.0 / 12.0) * samplesPerSec / correctBaud).round();
      d.psk.bOffs = (samplesPerSec / correctBaud).round();
      d.psk.sOffs = ((13.0 / 12.0) * samplesPerSec / correctBaud).round();
    } else {
      // 8PSK
      correctBaud = bps ~/ 3;
      carrierFreq = 1800;

      switch (profile.toUpperCase()) {
        case 'T': // Self correlation technique
          d.psk.usePrefilter = 0; // No bandpass filter
          d.psk.lpfBaud = 1.15;
          d.psk.lpFilterWidthSym = 0.871;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.95;
          d.pllSearchingInertia = 0.50;
          break;

        case 'U': // Self correlation technique with prefilter
          d.psk.usePrefilter = 1; // Add a bandpass filter
          d.psk.prefilterBaud = 0.9;
          d.psk.preFilterWidthSym = 0.571;
          d.psk.preWindow = BpWindowType.flattop;
          d.psk.lpfBaud = 1.15;
          d.psk.lpFilterWidthSym = 0.871;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.87;
          d.pllSearchingInertia = 0.50;
          break;

        case 'W': // Mix with local oscillator with prefilter
          d.psk.pskUseLo = 1;
          d.psk.usePrefilter = 1; // Add a bandpass filter
          d.psk.prefilterBaud = 0.85;
          d.psk.preFilterWidthSym = 0.844;
          d.psk.preWindow = BpWindowType.cosine;
          d.psk.lpfBaud = 0.85;
          d.psk.lpFilterWidthSym = 0.844;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;

        case 'V': // Mix with local oscillator
        default:
          d.psk.pskUseLo = 1;
          d.psk.usePrefilter = 0; // No bandpass filter
          d.psk.lpfBaud = 0.85;
          d.psk.lpFilterWidthSym = 0.844;
          d.psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
      }

      d.psk.delayLineWidthSym = 1.25; // Delay line > 10/9 * symbol period
      d.psk.cOffs = ((8.0 / 9.0) * samplesPerSec / correctBaud).round();
      d.psk.bOffs = (samplesPerSec / correctBaud).round();
      d.psk.sOffs = ((10.0 / 9.0) * samplesPerSec / correctBaud).round();
    }

    // Initialize local oscillator if used
    if (d.psk.pskUseLo != 0) {
      d.psk.loStep =
          (math.pow(256.0, 4) * carrierFreq / samplesPerSec).round() &
          0xFFFFFFFF;

      // Pre-compute sin table for speed
      for (int j = 0; j < 256; j++) {
        d.psk.sinTable256[j] = math.sin(2.0 * math.pi * j / 256.0);
      }
    }

    // Calculate timing constants
    d.pllStepPerSample =
        (DemodulatorState.ticksPerPllCycle * correctBaud / samplesPerSec)
            .round();

    // Convert symbol times to number of taps
    d.psk.preFilterTaps =
        (d.psk.preFilterWidthSym * samplesPerSec / correctBaud).round();
    d.psk.delayLineTaps =
        (d.psk.delayLineWidthSym * samplesPerSec / correctBaud).round();
    d.psk.lpFilterTaps = (d.psk.lpFilterWidthSym * samplesPerSec / correctBaud)
        .round();

    // Validate filter sizes
    if (d.psk.preFilterTaps > Dsp.maxFilterSize) {
      print(
        'Calculated pre filter size of ${d.psk.preFilterTaps} is too large.',
      );
      throw StateError('Pre filter size too large');
    }

    if (d.psk.delayLineTaps > Dsp.maxFilterSize) {
      print(
        'Calculated delay line size of ${d.psk.delayLineTaps} is too large.',
      );
      throw StateError('Delay line size too large');
    }

    if (d.psk.lpFilterTaps > Dsp.maxFilterSize) {
      print(
        'Calculated low pass filter size of ${d.psk.lpFilterTaps} is too large.',
      );
      throw StateError('Low pass filter size too large');
    }

    // Generate prefilter if enabled
    if (d.psk.usePrefilter != 0) {
      double f1 = carrierFreq - d.psk.prefilterBaud * correctBaud;
      double f2 = carrierFreq + d.psk.prefilterBaud * correctBaud;

      if (f1 <= 0) {
        print("Prefilter of $f1 to $f2 Hz doesn't make sense.");
        f1 = 10;
      }

      f1 = f1 / samplesPerSec;
      f2 = f2 / samplesPerSec;

      Dsp.genBandpass(
        f1,
        f2,
        d.psk.preFilter,
        d.psk.preFilterTaps,
        d.psk.preWindow,
      );
    }

    // Generate lowpass filter
    final double fc = correctBaud * d.psk.lpfBaud / samplesPerSec;
    Dsp.genLowpass(fc, d.psk.lpFilter, d.psk.lpFilterTaps, d.psk.lpWindow);

    // No point in having multiple numbers for signal level
    d.alevelMarkPeak = -1;
    d.alevelSpacePeak = -1;
  }

  /// Process one audio sample through the PSK demodulator.
  void processSample(int chan, int subchan, int sam, PskDemodulatorState d) {
    const int slice = 0; // Would it make sense to have more than one?

    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan < AudioConfig.maxSlicers);

    // Scale to nice number for plotting during debug
    double fsam = sam / 16384.0;

    // Optional bandpass filter before the phase detector
    if (d.psk.usePrefilter != 0) {
      _pushSample(fsam, d.psk.audioIn, d.psk.preFilterTaps);
      fsam = _convolve(d.psk.audioIn, d.psk.preFilter, d.psk.preFilterTaps);
    }

    if (d.psk.pskUseLo != 0) {
      // Mix with local oscillator to obtain phase
      final double samXCos =
          fsam * d.psk.sinTable256[((d.psk.loPhase >> 24) + 64) & 0xff];
      _pushSample(samXCos, d.psk.iRaw, d.psk.lpFilterTaps);
      final double i = _convolve(
        d.psk.iRaw,
        d.psk.lpFilter,
        d.psk.lpFilterTaps,
      );

      final double samXSin =
          fsam * d.psk.sinTable256[(d.psk.loPhase >> 24) & 0xff];
      _pushSample(samXSin, d.psk.qRaw, d.psk.lpFilterTaps);
      final double q = _convolve(
        d.psk.qRaw,
        d.psk.lpFilter,
        d.psk.lpFilterTaps,
      );

      final double a = _myAtan2f(i, q);

      // This is just a delay line of one symbol time
      _pushSample(a, d.psk.delayLine, d.psk.delayLineTaps);
      final double delta = a - d.psk.delayLine[d.psk.bOffs];

      int gray;
      final List<int> bitQuality = List<int>.filled(3, 0);
      if (d.modemType == ModemType.qpsk) {
        if (d.psk.v26Alt == V26Alternative.b) {
          gray = _phaseShiftToSymbol(
            delta + (-math.pi / 4),
            2,
            bitQuality,
          ); // MFJ compatible
        } else {
          gray = _phaseShiftToSymbol(delta, 2, bitQuality); // Classic
        }
      } else {
        gray = _phaseShiftToSymbol(delta, 3, bitQuality); // 8-PSK
      }
      _nudgePll(chan, subchan, slice, gray, d, bitQuality);

      d.psk.loPhase = (d.psk.loPhase + d.psk.loStep) & 0xFFFFFFFF;
    } else {
      // Correlate with previous symbol. We are looking for the phase shift.
      _pushSample(fsam, d.psk.delayLine, d.psk.delayLineTaps);

      final double samXCos = fsam * d.psk.delayLine[d.psk.cOffs];
      _pushSample(samXCos, d.psk.iRaw, d.psk.lpFilterTaps);
      final double i = _convolve(
        d.psk.iRaw,
        d.psk.lpFilter,
        d.psk.lpFilterTaps,
      );

      final double samXSin = fsam * d.psk.delayLine[d.psk.sOffs];
      _pushSample(samXSin, d.psk.qRaw, d.psk.lpFilterTaps);
      final double q = _convolve(
        d.psk.qRaw,
        d.psk.lpFilter,
        d.psk.lpFilterTaps,
      );

      int gray;
      final List<int> bitQuality = List<int>.filled(3, 0);
      final double delta = _myAtan2f(i, q);

      if (d.modemType == ModemType.qpsk) {
        if (d.psk.v26Alt == V26Alternative.b) {
          gray = _phaseShiftToSymbol(
            delta + (math.pi / 2),
            2,
            bitQuality,
          ); // MFJ compatible
        } else {
          gray = _phaseShiftToSymbol(
            delta + (3 * math.pi / 4),
            2,
            bitQuality,
          ); // Classic
        }
      } else {
        gray = _phaseShiftToSymbol(delta + (3 * math.pi / 2), 3, bitQuality);
      }
      _nudgePll(chan, subchan, slice, gray, d, bitQuality);
    }
  }

  /// Digital Phase Locked Loop for symbol timing recovery.
  void _nudgePll(
    int chan,
    int subchan,
    int slice,
    int demodBits,
    PskDemodulatorState d,
    List<int> bitQuality,
  ) {
    final SlicerState s = d.slicer[slice];

    s.prevDClockPll = s.dataClockPll;

    // Perform the add as unsigned to avoid signed overflow error
    s.dataClockPll = _toInt32(
      (s.dataClockPll & 0xFFFFFFFF) + (d.pllStepPerSample & 0xFFFFFFFF),
    );

    if (s.dataClockPll < 0 && s.prevDClockPll >= 0) {
      // Overflow of PLL counter - this is where we sample the data
      if (d.modemType == ModemType.qpsk) {
        final int gray = demodBits;
        _hdlcRec.recBit(
          chan,
          subchan,
          slice,
          (gray >> 1) & 1,
          false,
          bitQuality[1],
        );
        _hdlcRec.recBit(chan, subchan, slice, gray & 1, false, bitQuality[0]);
      } else {
        final int gray = demodBits;
        _hdlcRec.recBit(
          chan,
          subchan,
          slice,
          (gray >> 2) & 1,
          false,
          bitQuality[2],
        );
        _hdlcRec.recBit(
          chan,
          subchan,
          slice,
          (gray >> 1) & 1,
          false,
          bitQuality[1],
        );
        _hdlcRec.recBit(chan, subchan, slice, gray & 1, false, bitQuality[0]);
      }
      s.pllSymbolCount++;
      _pllDcdEachSymbol(d, chan, subchan, slice);
    }

    // If demodulated data has changed, pull the PLL phase closer to zero
    if (demodBits != s.prevDemodData) {
      _pllDcdSignalTransition(d, slice, s.dataClockPll);

      final int before = s.dataClockPll; // Treat as signed
      if (s.dataDetect != 0) {
        s.dataClockPll = (s.dataClockPll * d.pllLockedInertia).floor();
      } else {
        s.dataClockPll = (s.dataClockPll * d.pllSearchingInertia).floor();
      }
      s.pllNudgeTotal += s.dataClockPll - before;
    }

    // Remember demodulator output so we can compare next time
    s.prevDemodData = demodBits;
  }

  /// Check if transition occurred at good or bad time.
  void _pllDcdSignalTransition(
    PskDemodulatorState d,
    int slice,
    int dpllPhase,
  ) {
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      d.slicer[slice].goodFlag = 1;
    } else {
      d.slicer[slice].badFlag = 1;
    }
  }

  /// Update DCD state after each symbol.
  void _pllDcdEachSymbol(
    PskDemodulatorState d,
    int chan,
    int subchan,
    int slice,
  ) {
    final SlicerState s = d.slicer[slice];

    s.goodHist = ((s.goodHist << 1) | s.goodFlag) & 0xFF;
    s.goodFlag = 0;

    s.badHist = ((s.badHist << 1) | s.badFlag) & 0xFF;
    s.badFlag = 0;

    // 2 is to detect 'flag' patterns with 2 transitions per octet
    s.score =
        ((s.score << 1) |
            ((_popCount(s.goodHist) - _popCount(s.badHist) >= 2) ? 1 : 0)) &
        0xFFFFFFFF;

    final int score = _popCount(s.score);
    if (score >= _dcdThreshOn) {
      if (s.dataDetect == 0) {
        s.dataDetect = 1;
        _hdlcRec.dcdChange(chan, subchan, slice, true);
      }
    } else if (score <= _dcdThreshOff) {
      if (s.dataDetect != 0) {
        s.dataDetect = 0;
        _hdlcRec.dcdChange(chan, subchan, slice, false);
      }
    }
  }

  /// Count number of set bits (population count).
  int _popCount(int x) {
    x &= 0xFFFFFFFF;
    int count = 0;
    while (x != 0) {
      count++;
      x &= x - 1; // Clear least significant set bit
    }
    return count;
  }
}
