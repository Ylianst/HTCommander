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
// demod_afsk.dart - AFSK (Audio Frequency Shift Keying) Demodulator
//
// Ported from C# HamLib/DemodAfsk.cs
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_config.dart';
import 'dsp.dart';
import 'ihdlc_receiver.dart';

/// Slicer state for PLL and data detection.
class SlicerState {
  int dataClockPll = 0; // PLL for data clock recovery (32-bit signed)
  int prevDClockPll = 0; // Previous value before incrementing
  int pllSymbolCount = 0; // Number of symbols during nudge accumulation
  int pllNudgeTotal = 0; // Sum of DPLL nudge amounts
  int prevDemodData = 0; // Previous data bit detected
  double prevDemodOutF = 0; // Previous demodulator output (float)
  int lfsr = 0; // Descrambler shift register (for 9600 baud)

  // For detecting phase lock to incoming signal
  int goodFlag = 0; // Set if transition near expected time
  int badFlag = 0; // Set if transition not where expected
  int goodHist = 0; // History of good transitions for past octet
  int badHist = 0; // History of bad transitions for past octet
  int score = 0; // History of good vs bad for past 32 symbols
  int dataDetect = 0; // True when locked on to signal
}

/// AFSK-specific demodulator state.
class AfskState {
  // Local oscillators for Mark, Space, and Center frequencies
  int mOscPhase = 0; // Phase for Mark local oscillator
  int mOscDelta = 0; // How much to change per audio sample
  int sOscPhase = 0; // Phase for Space local oscillator
  int sOscDelta = 0; // How much to change per audio sample
  int cOscPhase = 0; // Phase for Center frequency local oscillator
  int cOscDelta = 0; // How much to change per audio sample

  // Mixer outputs for Mark (profile A)
  final Float32List mIRaw = Float32List(Dsp.maxFilterSize);
  final Float32List mQRaw = Float32List(Dsp.maxFilterSize);

  // Mixer outputs for Space (profile A)
  final Float32List sIRaw = Float32List(Dsp.maxFilterSize);
  final Float32List sQRaw = Float32List(Dsp.maxFilterSize);

  // Mixer outputs for Center (profile B)
  final Float32List cIRaw = Float32List(Dsp.maxFilterSize);
  final Float32List cQRaw = Float32List(Dsp.maxFilterSize);

  // Root Raised Cosine filter settings
  int useRrc = 0; // Use RRC rather than generic low pass
  double rrcWidthSym = 0; // Width of RRC filter in symbols
  double rrcRolloff = 0; // Rolloff factor (0 to 1)

  // For FM demodulator (profile B)
  double prevPhase = 0; // Previous phase for rate calculation
  double normalizeRpsam = 0; // Normalize to -1 to +1 for expected tones
}

/// Demodulator state structure.
class DemodulatorState {
  static const int ticksPerPllCycle = 256 * 256 * 256 * 256; // 2^32

  // Configuration (set during initialization)
  String profile = 'A'; // 'A', 'B', etc.
  int pllStepPerSample = 0; // PLL advance per audio sample

  // Prefilter (bandpass before demodulation)
  int usePrefilter = 0; // True to enable
  double prefilterBaud = 0; // Cutoff as fraction of baud beyond tones
  double preFilterLenSym = 0; // Length in symbol times
  BpWindowType preWindow = BpWindowType.truncated; // Window type
  int preFilterTaps = 0; // Number of filter taps
  final Float32List preFilter = Float32List(Dsp.maxFilterSize);
  final Float32List rawCb = Float32List(
    Dsp.maxFilterSize,
  ); // Audio input circular buffer

  // Low pass filter
  double lpfBaud = 0; // Cutoff as fraction of baud rate
  double lpFilterWidthSym = 0; // Length in symbol times
  BpWindowType lpWindow = BpWindowType.truncated; // Window type
  int lpFilterTaps = 0; // Number of filter taps
  final Float32List lpFilter = Float32List(Dsp.maxFilterSize);

  // AGC (Automatic Gain Control)
  double agcFastAttack = 0;
  double agcSlowDecay = 0;
  double quickAttack = 0; // For signal level reporting
  double sluggishDecay = 0;

  // PLL inertia
  double pllLockedInertia = 0; // When locked on signal
  double pllSearchingInertia = 0; // When searching for signal

  // Peak/valley tracking for AGC
  double mPeak = 0, sPeak = 0;
  double mValley = 0, sValley = 0;

  // Audio level measurements
  double alevelRecPeak = 0;
  double alevelRecValley = 0;
  double alevelMarkPeak = 0;
  double alevelSpacePeak = 0;

  // Slicers (multiple detection thresholds)
  int numSlicers = 0; // Number of slicers in use
  final List<SlicerState> slicer = List.generate(
    AudioConfig.maxSlicers,
    (_) => SlicerState(),
  );

  // AFSK-specific state
  final AfskState afsk = AfskState();
}

/// AFSK Demodulator.
class DemodAfsk {
  static const double _minG = 0.5;
  static const double _maxG = 4.0;
  static const int _dcdThreshOn = 30; // Hysteresis for DCD detect
  static const int _dcdThreshOff = 6;
  static const int _dcdGoodWidth = 512;

  static final Float32List _fcos256Table = Float32List(256);
  static final Float32List _spaceGain = Float32List(AudioConfig.maxSlicers);
  static bool _tablesInitialized = false;

  final IHdlcReceiver _hdlcRec;

  DemodAfsk(this._hdlcRec);

  /// Initialize lookup tables (called once).
  static void _initTables() {
    if (_tablesInitialized) return;

    // Cosine table indexed by unsigned byte
    for (int j = 0; j < 256; j++) {
      _fcos256Table[j] = math.cos(j * 2.0 * math.pi / 256.0);
    }

    // Space gain table for multiple slicers
    _spaceGain[0] = _minG;
    final double step = math
        .pow(
          10.0,
          (math.log(_maxG / _minG) / math.ln10) / (AudioConfig.maxSlicers - 1),
        )
        .toDouble();
    for (int j = 1; j < AudioConfig.maxSlicers; j++) {
      _spaceGain[j] = _spaceGain[j - 1] * step;
    }

    _tablesInitialized = true;
  }

  /// Fast cosine approximation using lookup table.
  static double _fcos256(int x) {
    return _fcos256Table[(x >> 24) & 0xff];
  }

  /// Fast sine approximation using lookup table.
  static double _fsin256(int x) {
    return _fcos256Table[((x >> 24) - 64) & 0xff];
  }

  /// Quick approximation to sqrt(x*x + y*y).
  static double _fastHypot(double x, double y) {
    return math.sqrt(x * x + y * y);
  }

  /// Add sample to buffer and shift the rest down.
  static void _pushSample(double val, Float32List buff, int size) {
    buff.setRange(1, size, buff.sublist(0, size - 1));
    buff[0] = val;
  }

  /// FIR filter convolution kernel.
  static double _convolve(
    Float32List data,
    Float32List filter,
    int filterTaps,
  ) {
    double sum = 0.0;
    for (int j = 0; j < filterTaps; j++) {
      sum += filter[j] * data[j];
    }
    return sum;
  }

  /// Automatic Gain Control. Result settles to 1 unit peak to peak.
  ///
  /// Returns a record of `(result, peak, valley)`.
  static (double, double, double) _agc(
    double input,
    double fastAttack,
    double slowDecay,
    double peak,
    double valley,
  ) {
    if (input >= peak) {
      peak = input * fastAttack + peak * (1.0 - fastAttack);
    } else {
      peak = input * slowDecay + peak * (1.0 - slowDecay);
    }

    if (input <= valley) {
      valley = input * fastAttack + valley * (1.0 - fastAttack);
    } else {
      valley = input * slowDecay + valley * (1.0 - slowDecay);
    }

    // Clip to envelope
    double x = input;
    if (x > peak) x = peak;
    if (x < valley) x = valley;

    if (peak > valley) {
      return ((x - 0.5 * (peak + valley)) / (peak - valley), peak, valley);
    }
    return (0.0, peak, valley);
  }

  /// Reinterpret a value as a signed 32-bit integer.
  static int _toInt32(int v) {
    v &= 0xFFFFFFFF;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Initialize AFSK demodulator.
  void init(
    int samplesPerSec,
    int baud,
    int markFreq,
    int spaceFreq,
    String profile,
    DemodulatorState d,
  ) {
    _initTables();

    d.profile = profile;
    d.numSlicers = 1;

    switch (d.profile) {
      case 'A':
      case 'E': // For compatibility during transition
        d.profile = 'A';
        _initProfileA(samplesPerSec, baud, markFreq, spaceFreq, d);
        break;

      case 'B':
      case 'D': // Backward compatibility
        d.profile = 'B';
        _initProfileB(samplesPerSec, baud, markFreq, spaceFreq, d);
        break;

      default:
        throw ArgumentError('Invalid AFSK demodulator profile = $profile');
    }

    // Calculate PLL timing constants
    if (baud == 521) {
      // EAS special case
      d.pllStepPerSample =
          (DemodulatorState.ticksPerPllCycle * 520.83 / samplesPerSec).round();
    } else {
      d.pllStepPerSample =
          (DemodulatorState.ticksPerPllCycle * baud / samplesPerSec).round();
    }

    // Generate prefilter if enabled
    if (d.usePrefilter != 0) {
      d.preFilterTaps =
          (d.preFilterLenSym * samplesPerSec / baud).toInt() | 1; // odd

      if (d.preFilterTaps > Dsp.maxFilterSize) {
        print(
          'Warning: Calculated pre filter size of ${d.preFilterTaps} is too large.',
        );
        d.preFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }

      double f1 = math.min(markFreq, spaceFreq) - d.prefilterBaud * baud;
      double f2 = math.max(markFreq, spaceFreq) + d.prefilterBaud * baud;
      f1 = f1 / samplesPerSec;
      f2 = f2 / samplesPerSec;

      Dsp.genBandpass(f1, f2, d.preFilter, d.preFilterTaps, d.preWindow);
    }

    // Generate lowpass filter
    if (d.afsk.useRrc != 0) {
      assert(d.afsk.rrcWidthSym >= 1 && d.afsk.rrcWidthSym <= 16);
      assert(d.afsk.rrcRolloff >= 0.0 && d.afsk.rrcRolloff <= 1.0);

      d.lpFilterTaps =
          (d.afsk.rrcWidthSym * samplesPerSec / baud).toInt() | 1; // odd

      if (d.lpFilterTaps > Dsp.maxFilterSize) {
        print(
          'Calculated RRC low pass filter size of ${d.lpFilterTaps} is too large.',
        );
        d.lpFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }

      assert(d.lpFilterTaps > 8 && d.lpFilterTaps <= Dsp.maxFilterSize);
      Dsp.genRrcLowpass(
        d.lpFilter,
        d.lpFilterTaps,
        d.afsk.rrcRolloff,
        samplesPerSec / baud,
      );
    } else {
      d.lpFilterTaps = (d.lpFilterWidthSym * samplesPerSec / baud).round();

      if (d.lpFilterTaps > Dsp.maxFilterSize) {
        print(
          'Calculated FIR low pass filter size of ${d.lpFilterTaps} is too large.',
        );
        d.lpFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }

      assert(d.lpFilterTaps > 8 && d.lpFilterTaps <= Dsp.maxFilterSize);

      final double fc = baud * d.lpfBaud / samplesPerSec;
      Dsp.genLowpass(fc, d.lpFilter, d.lpFilterTaps, d.lpWindow);
    }
  }

  /// Initialize Profile A demodulator (dual tone comparison).
  void _initProfileA(
    int samplesPerSec,
    int baud,
    int markFreq,
    int spaceFreq,
    DemodulatorState d,
  ) {
    d.usePrefilter = 1;

    if (baud > 600) {
      d.prefilterBaud = 0.155;
      d.preFilterLenSym = 383 * 1200.0 / 44100.0; // about 8 symbols
      d.preWindow = BpWindowType.truncated;
    } else {
      d.prefilterBaud = 0.87;
      d.preFilterLenSym = 1.857;
      d.preWindow = BpWindowType.cosine;
    }

    // Local oscillators for Mark and Space tones
    d.afsk.mOscPhase = 0;
    d.afsk.mOscDelta =
        (math.pow(2.0, 32) * markFreq / samplesPerSec).round() & 0xFFFFFFFF;

    d.afsk.sOscPhase = 0;
    d.afsk.sOscDelta =
        (math.pow(2.0, 32) * spaceFreq / samplesPerSec).round() & 0xFFFFFFFF;

    d.afsk.useRrc = 1;

    if (d.afsk.useRrc != 0) {
      d.afsk.rrcWidthSym = 2.80;
      d.afsk.rrcRolloff = 0.20;
    } else {
      d.lpfBaud = 0.14;
      d.lpFilterWidthSym = 1.388;
      d.lpWindow = BpWindowType.truncated;
    }

    d.agcFastAttack = 0.70;
    d.agcSlowDecay = 0.000090;

    d.pllLockedInertia = 0.74;
    d.pllSearchingInertia = 0.50;

    d.quickAttack = d.agcFastAttack;
    d.sluggishDecay = d.agcSlowDecay;
  }

  /// Initialize Profile B demodulator (FM discriminator).
  void _initProfileB(
    int samplesPerSec,
    int baud,
    int markFreq,
    int spaceFreq,
    DemodulatorState d,
  ) {
    d.usePrefilter = 1;

    if (baud > 600) {
      d.prefilterBaud = 0.19;
      d.preFilterLenSym = 8.163;
      d.preWindow = BpWindowType.truncated;
    } else {
      d.prefilterBaud = 0.87;
      d.preFilterLenSym = 1.857;
      d.preWindow = BpWindowType.cosine;
    }

    // Local oscillator for Center frequency
    d.afsk.cOscPhase = 0;
    d.afsk.cOscDelta =
        (math.pow(2.0, 32) * 0.5 * (markFreq + spaceFreq) / samplesPerSec)
            .round() &
        0xFFFFFFFF;

    d.afsk.useRrc = 1;

    if (d.afsk.useRrc != 0) {
      d.afsk.rrcWidthSym = 2.00;
      d.afsk.rrcRolloff = 0.40;
    } else {
      d.lpfBaud = 0.5;
      d.lpFilterWidthSym = 1.714286;
      d.lpWindow = BpWindowType.truncated;
    }

    // For scaling phase shift into normalized -1 to +1 range
    d.afsk.normalizeRpsam =
        1.0 /
        (0.5 * (markFreq - spaceFreq).abs() * 2 * math.pi / samplesPerSec);

    d.agcFastAttack = 0.70;
    d.agcSlowDecay = 0.000090;

    d.pllLockedInertia = 0.74;
    d.pllSearchingInertia = 0.50;

    d.quickAttack = d.agcFastAttack;
    d.sluggishDecay = d.agcSlowDecay;

    // Disable received signal display for profile B
    d.alevelMarkPeak = -1;
    d.alevelSpacePeak = -1;
  }

  /// Process one audio sample through the AFSK demodulator.
  void processSample(int chan, int subchan, int sam, DemodulatorState d) {
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan < AudioConfig.maxSlicers);

    // Scale to normalized float
    final double fsam = sam / 16384.0;

    switch (d.profile) {
      case 'A':
      case 'E':
        _processSampleProfileA(chan, subchan, fsam, d);
        break;

      case 'B':
      case 'D':
        _processSampleProfileB(chan, subchan, fsam, d);
        break;
    }
  }

  /// Process sample using Profile A (dual tone amplitude comparison).
  void _processSampleProfileA(
    int chan,
    int subchan,
    double fsam,
    DemodulatorState d,
  ) {
    // Apply prefilter if enabled
    if (d.usePrefilter != 0) {
      _pushSample(fsam, d.rawCb, d.preFilterTaps);
      fsam = _convolve(d.rawCb, d.preFilter, d.preFilterTaps);
    }

    // Mix with Mark local oscillator
    _pushSample(
      fsam * _fcos256(d.afsk.mOscPhase),
      d.afsk.mIRaw,
      d.lpFilterTaps,
    );
    _pushSample(
      fsam * _fsin256(d.afsk.mOscPhase),
      d.afsk.mQRaw,
      d.lpFilterTaps,
    );
    d.afsk.mOscPhase = (d.afsk.mOscPhase + d.afsk.mOscDelta) & 0xFFFFFFFF;

    // Mix with Space local oscillator
    _pushSample(
      fsam * _fcos256(d.afsk.sOscPhase),
      d.afsk.sIRaw,
      d.lpFilterTaps,
    );
    _pushSample(
      fsam * _fsin256(d.afsk.sOscPhase),
      d.afsk.sQRaw,
      d.lpFilterTaps,
    );
    d.afsk.sOscPhase = (d.afsk.sOscPhase + d.afsk.sOscDelta) & 0xFFFFFFFF;

    // Apply lowpass filters and calculate amplitudes
    final double mI = _convolve(d.afsk.mIRaw, d.lpFilter, d.lpFilterTaps);
    final double mQ = _convolve(d.afsk.mQRaw, d.lpFilter, d.lpFilterTaps);
    final double mAmp = _fastHypot(mI, mQ);

    final double sI = _convolve(d.afsk.sIRaw, d.lpFilter, d.lpFilterTaps);
    final double sQ = _convolve(d.afsk.sQRaw, d.lpFilter, d.lpFilterTaps);
    final double sAmp = _fastHypot(sI, sQ);

    // Capture mark and space peak amplitudes for display
    if (mAmp >= d.alevelMarkPeak) {
      d.alevelMarkPeak =
          mAmp * d.quickAttack + d.alevelMarkPeak * (1.0 - d.quickAttack);
    } else {
      d.alevelMarkPeak =
          mAmp * d.sluggishDecay + d.alevelMarkPeak * (1.0 - d.sluggishDecay);
    }

    if (sAmp >= d.alevelSpacePeak) {
      d.alevelSpacePeak =
          sAmp * d.quickAttack + d.alevelSpacePeak * (1.0 - d.quickAttack);
    } else {
      d.alevelSpacePeak =
          sAmp * d.sluggishDecay + d.alevelSpacePeak * (1.0 - d.sluggishDecay);
    }

    if (d.numSlicers <= 1) {
      // Single slicer with AGC
      final mr = _agc(
        mAmp,
        d.agcFastAttack,
        d.agcSlowDecay,
        d.mPeak,
        d.mValley,
      );
      final double mNorm = mr.$1;
      d.mPeak = mr.$2;
      d.mValley = mr.$3;
      final sr = _agc(
        sAmp,
        d.agcFastAttack,
        d.agcSlowDecay,
        d.sPeak,
        d.sValley,
      );
      final double sNorm = sr.$1;
      d.sPeak = sr.$2;
      d.sValley = sr.$3;

      final double demodOut = mNorm - sNorm;

      _nudgePll(chan, subchan, 0, demodOut, d, 1.0);
    } else {
      // Multiple slicers
      final mr = _agc(
        mAmp,
        d.agcFastAttack,
        d.agcSlowDecay,
        d.mPeak,
        d.mValley,
      );
      d.mPeak = mr.$2;
      d.mValley = mr.$3;
      final sr = _agc(
        sAmp,
        d.agcFastAttack,
        d.agcSlowDecay,
        d.sPeak,
        d.sValley,
      );
      d.sPeak = sr.$2;
      d.sValley = sr.$3;

      for (int slice = 0; slice < d.numSlicers; slice++) {
        final double demodOut = mAmp - sAmp * _spaceGain[slice];
        double amp =
            0.5 *
            (d.mPeak - d.mValley + (d.sPeak - d.sValley) * _spaceGain[slice]);
        if (amp < 0.0000001) amp = 1; // avoid divide by zero

        _nudgePll(chan, subchan, slice, demodOut, d, amp);
      }
    }
  }

  /// Process sample using Profile B (FM discriminator).
  void _processSampleProfileB(
    int chan,
    int subchan,
    double fsam,
    DemodulatorState d,
  ) {
    // Apply prefilter if enabled
    if (d.usePrefilter != 0) {
      _pushSample(fsam, d.rawCb, d.preFilterTaps);
      fsam = _convolve(d.rawCb, d.preFilter, d.preFilterTaps);
    }

    // Mix with Center frequency local oscillator
    _pushSample(
      fsam * _fcos256(d.afsk.cOscPhase),
      d.afsk.cIRaw,
      d.lpFilterTaps,
    );
    _pushSample(
      fsam * _fsin256(d.afsk.cOscPhase),
      d.afsk.cQRaw,
      d.lpFilterTaps,
    );
    d.afsk.cOscPhase = (d.afsk.cOscPhase + d.afsk.cOscDelta) & 0xFFFFFFFF;

    final double cI = _convolve(d.afsk.cIRaw, d.lpFilter, d.lpFilterTaps);
    final double cQ = _convolve(d.afsk.cQRaw, d.lpFilter, d.lpFilterTaps);

    final double phase = math.atan2(cQ, cI);
    double rate = phase - d.afsk.prevPhase;
    if (rate > math.pi) {
      rate -= 2 * math.pi;
    } else if (rate < -math.pi) {
      rate += 2 * math.pi;
    }
    d.afsk.prevPhase = phase;

    // Scale rate into -1 to +1 for expected tones
    final double normRate = rate * d.afsk.normalizeRpsam;

    if (d.numSlicers <= 1) {
      final double demodOut = normRate;
      _nudgePll(chan, subchan, 0, demodOut, d, 1.0);
    } else {
      // Multiple slicers with frequency offsets
      for (int slice = 0; slice < d.numSlicers; slice++) {
        final double offset = -0.5 + slice * (1.0 / (d.numSlicers - 1));
        final double demodOut = normRate + offset;
        _nudgePll(chan, subchan, slice, demodOut, d, 1.0);
      }
    }
  }

  /// Digital Phase Locked Loop for symbol timing recovery.
  void _nudgePll(
    int chan,
    int subchan,
    int slice,
    double demodOut,
    DemodulatorState d,
    double amplitude,
  ) {
    final SlicerState s = d.slicer[slice];

    s.prevDClockPll = s.dataClockPll;

    // Perform add as unsigned to avoid signed overflow
    s.dataClockPll = _toInt32(
      (s.dataClockPll & 0xFFFFFFFF) + (d.pllStepPerSample & 0xFFFFFFFF),
    );

    // Check for overflow (zero crossing) - this is where we sample
    if (s.dataClockPll < 0 && s.prevDClockPll > 0) {
      // Sample the data
      int quality = (demodOut.abs() * 100.0 / amplitude).toInt();
      if (quality > 100) quality = 100;

      final int bitValue = demodOut > 0 ? 1 : 0;

      // Pass bit to HDLC decoder
      _hdlcRec.recBit(chan, subchan, slice, bitValue, false, quality);

      // DCD detection
      _pllDcdEachSymbol(d, chan, subchan, slice);
    }

    // Transitions nudge the DPLL phase toward the incoming signal
    final int demodData = demodOut > 0 ? 1 : 0;
    if (demodData != s.prevDemodData) {
      _pllDcdSignalTransition(d, slice, s.dataClockPll);

      // Adjust PLL phase
      if (s.dataDetect != 0) {
        s.dataClockPll = (s.dataClockPll * d.pllLockedInertia).toInt();
      } else {
        s.dataClockPll = (s.dataClockPll * d.pllSearchingInertia).toInt();
      }
    }

    // Remember demodulator output for next time
    s.prevDemodData = demodData;
  }

  /// Check if transition occurred at good or bad time.
  void _pllDcdSignalTransition(DemodulatorState d, int slice, int dpllPhase) {
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      d.slicer[slice].goodFlag = 1;
    } else {
      d.slicer[slice].badFlag = 1;
    }
  }

  /// Update DCD state after each symbol.
  void _pllDcdEachSymbol(DemodulatorState d, int chan, int subchan, int slice) {
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
