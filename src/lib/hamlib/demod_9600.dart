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
// demod_9600.dart - Demodulator for 9600 baud baseband signal
//
// Ported from C# HamLib/Demod9600.cs
//

import 'dart:typed_data';

import 'demod_afsk.dart';
import 'dsp.dart';
import 'ihdlc_receiver.dart';

/// Baseband demodulator-specific state (for 9600 baud).
class BasebandState {
  double rrcWidthSym = 0; // Width of RRC filter in symbols
  double rrcRolloff = 0; // Rolloff factor for RRC (0-1)
  int rrcFilterTaps = 0; // Number of filter taps for RRC
  final Float32List audioIn = Float32List(
    Dsp.maxFilterSize,
  ); // Audio samples input
  final Float32List lpFilter = Float32List(
    Dsp.maxFilterSize,
  ); // Low pass filter coefficients
  final Float32List lpPolyphase1 = Float32List(
    Dsp.maxFilterSize,
  ); // Polyphase filter 1
  final Float32List lpPolyphase2 = Float32List(
    Dsp.maxFilterSize,
  ); // Polyphase filter 2
  final Float32List lpPolyphase3 = Float32List(
    Dsp.maxFilterSize,
  ); // Polyphase filter 3
  final Float32List lpPolyphase4 = Float32List(
    Dsp.maxFilterSize,
  ); // Polyphase filter 4
  double lp1IirParam = 0; // Low pass IIR parameter 1
  double lp1Out = 0; // Low pass IIR output 1
  double lp2IirParam = 0; // Low pass IIR parameter 2
  double lp2Out = 0; // Low pass IIR output 2
  double agc1FastAttack = 0; // AGC fast attack rate
  double agc1SlowDecay = 0; // AGC slow decay rate
  double agc1Peak = 0; // AGC peak value
  double agc1Valley = 0; // AGC valley value
  double agc2FastAttack = 0; // AGC 2 fast attack
  double agc2SlowDecay = 0; // AGC 2 slow decay
  double agc2Peak = 0; // AGC 2 peak
  double agc2Valley = 0; // AGC 2 valley
  double agc3FastAttack = 0; // AGC 3 fast attack
  double agc3SlowDecay = 0; // AGC 3 slow decay
  double agc3Peak = 0; // AGC 3 peak
  double agc3Valley = 0; // AGC 3 valley
}

/// Baseband (9600 baud) specific state added to DemodulatorState.
class Demod9600State {
  final BasebandState bb = BasebandState();
  double lpFilterLenBits = 0;
  int lpFilterSize = 0;
  BpWindowType lpWindow = BpWindowType.truncated;
  double lpfBaud = 0;
  double agcFastAttack = 0;
  double agcSlowDecay = 0;
  double pllLockedInertia = 0;
  double pllSearchingInertia = 0;
  int pllStepPerSample = 0;
}

/// Demodulator for 9600 baud baseband signal.
///
/// This is used for AX.25 (with scrambling) and IL2P (without).
class Demod9600 {
  // DCD thresholds
  static const int _dcdThreshOn = 32; // Hysteresis for detecting lock
  static const int _dcdThreshOff = 8; // Threshold for losing lock
  static const int _dcdGoodWidth = 1024; // Maximum width for good transition

  // PLL cycle constant
  static const double _ticksPerPllCycle = 256.0 * 256.0 * 256.0 * 256.0;

  // Maximum number of subchannels
  static const int _maxSubchans = 9;

  // Slice points for multiple slicers
  static final Float32List _slicePoint = Float32List(_maxSubchans);

  /// Reinterpret a value as a signed 32-bit integer.
  static int _toInt32(int v) {
    v &= 0xFFFFFFFF;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Initialize the 9600 baud demodulator.
  static void init(
    int originalSampleRate,
    int upsample,
    int baud,
    DemodulatorState d,
    Demod9600State state9600,
  ) {
    if (upsample < 1) upsample = 1;
    if (upsample > 4) upsample = 4;

    d.numSlicers = 1;

    // Configure filter parameters
    state9600.lpFilterLenBits = 1.0;

    // Calculate filter size - just round to nearest integer
    state9600.lpFilterSize =
        ((state9600.lpFilterLenBits * originalSampleRate / baud) + 0.5).toInt();

    state9600.lpWindow = BpWindowType.cosine;
    state9600.lpfBaud = 1.00;

    // AGC parameters
    state9600.agcFastAttack = 0.080;
    state9600.agcSlowDecay = 0.00012;

    // PLL parameters
    state9600.pllLockedInertia = 0.89;
    state9600.pllSearchingInertia = 0.67;

    // PLL needs to use the upsampled rate
    state9600.pllStepPerSample =
        (_ticksPerPllCycle * baud / (originalSampleRate * upsample)).round();

    // Initial filter (before scattering) is based on upsampled rate
    final double fc =
        baud * state9600.lpfBaud / (originalSampleRate * upsample);

    // Generate the low pass filter
    Dsp.genLowpass(
      fc,
      state9600.bb.lpFilter,
      state9600.lpFilterSize * upsample,
      state9600.lpWindow,
    );

    // Create polyphase filters to reduce CPU load
    // Scatter the original filter across multiple shorter filters
    // Each input sample cycles around them to produce the upsampled rate
    int k = 0;
    for (int i = 0; i < state9600.lpFilterSize; i++) {
      state9600.bb.lpPolyphase1[i] = state9600.bb.lpFilter[k++];
      if (upsample >= 2) {
        state9600.bb.lpPolyphase2[i] = state9600.bb.lpFilter[k++];
        if (upsample >= 3) {
          state9600.bb.lpPolyphase3[i] = state9600.bb.lpFilter[k++];
          if (upsample >= 4) {
            state9600.bb.lpPolyphase4[i] = state9600.bb.lpFilter[k++];
          }
        }
      }
    }

    // Initialize slice points for multiple slicers
    for (int j = 0; j < _maxSubchans; j++) {
      _slicePoint[j] = 0.02 * (j - 0.5 * (_maxSubchans - 1));
    }
  }

  /// Process a single audio sample.
  static void processSample(
    int chan,
    int sam,
    int upsample,
    DemodulatorState d,
    Demod9600State state9600,
    IHdlcReceiver hdlcReceiver,
  ) {
    // Scale to nice number for convenience
    // Input range +-16k becomes +-1 here
    double fsam = sam / 16384.0;

    // Low pass filter - push sample into buffer
    _pushSample(fsam, state9600.bb.audioIn, state9600.lpFilterSize);

    // Apply polyphase filters and process
    fsam = _convolve(
      state9600.bb.audioIn,
      state9600.bb.lpPolyphase1,
      state9600.lpFilterSize,
    );
    _processFilteredSample(chan, fsam, d, state9600, hdlcReceiver);

    if (upsample >= 2) {
      fsam = _convolve(
        state9600.bb.audioIn,
        state9600.bb.lpPolyphase2,
        state9600.lpFilterSize,
      );
      _processFilteredSample(chan, fsam, d, state9600, hdlcReceiver);

      if (upsample >= 3) {
        fsam = _convolve(
          state9600.bb.audioIn,
          state9600.bb.lpPolyphase3,
          state9600.lpFilterSize,
        );
        _processFilteredSample(chan, fsam, d, state9600, hdlcReceiver);

        if (upsample >= 4) {
          fsam = _convolve(
            state9600.bb.audioIn,
            state9600.bb.lpPolyphase4,
            state9600.lpFilterSize,
          );
          _processFilteredSample(chan, fsam, d, state9600, hdlcReceiver);
        }
      }
    }
  }

  /// Add sample to buffer and shift the rest down.
  static void _pushSample(double val, Float32List buff, int size) {
    // Shift all elements down by one
    buff.setRange(1, size, buff.sublist(0, size - 1));
    buff[0] = val;
  }

  /// FIR filter kernel - convolve data with filter.
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

  /// Automatic gain control.
  ///
  /// Result should settle down to 1 unit peak to peak (i.e. -0.5 to +0.5).
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

    if (peak > valley) {
      return ((input - 0.5 * (peak + valley)) / (peak - valley), peak, valley);
    }
    return (0.0, peak, valley);
  }

  /// Process a filtered sample.
  static void _processFilteredSample(
    int chan,
    double fsam,
    DemodulatorState d,
    Demod9600State state9600,
    IHdlcReceiver hdlcReceiver,
  ) {
    const int subchan = 0; // Fixed subchannel for 9600 baud

    // Capture post-filtering amplitude for display
    // Similar to AGC without normalization - for audio level display
    if (fsam >= d.alevelMarkPeak) {
      d.alevelMarkPeak =
          fsam * d.quickAttack + d.alevelMarkPeak * (1.0 - d.quickAttack);
    } else {
      d.alevelMarkPeak =
          fsam * d.sluggishDecay + d.alevelMarkPeak * (1.0 - d.sluggishDecay);
    }

    if (fsam <= d.alevelSpacePeak) {
      d.alevelSpacePeak =
          fsam * d.quickAttack + d.alevelSpacePeak * (1.0 - d.quickAttack);
    } else {
      d.alevelSpacePeak =
          fsam * d.sluggishDecay + d.alevelSpacePeak * (1.0 - d.sluggishDecay);
    }

    // Normalize the signal with automatic gain control (AGC)
    // This removes DC bias and scales to roughly -1.0 to +1.0 range
    final r = _agc(
      fsam,
      state9600.agcFastAttack,
      state9600.agcSlowDecay,
      d.mPeak,
      d.mValley,
    );
    final double demodOut = r.$1;
    d.mPeak = r.$2;
    d.mValley = r.$3;

    if (d.numSlicers <= 1) {
      // Normal case: one demodulator to one HDLC decoder
      _nudgePll(chan, subchan, 0, demodOut, d, state9600, hdlcReceiver);
    } else {
      // Multiple slicers each feeding its own HDLC decoder
      for (int slice = 0; slice < d.numSlicers; slice++) {
        _nudgePll(
          chan,
          subchan,
          slice,
          demodOut - _slicePoint[slice],
          d,
          state9600,
          hdlcReceiver,
        );
      }
    }
  }

  /// Update the PLL state for each audio sample.
  ///
  /// A PLL is used to sample near the centers of the data bits.
  static void _nudgePll(
    int chan,
    int subchan,
    int slice,
    double demodOutF,
    DemodulatorState d,
    Demod9600State state9600,
    IHdlcReceiver hdlcReceiver,
  ) {
    final SlicerState s = d.slicer[slice];

    s.prevDClockPll = s.dataClockPll;

    // Perform the add as unsigned to avoid signed overflow
    s.dataClockPll = _toInt32(
      (s.dataClockPll & 0xFFFFFFFF) + (state9600.pllStepPerSample & 0xFFFFFFFF),
    );

    // Check for overflow (was large positive, now large negative)
    if (s.prevDClockPll > 1000000000 && s.dataClockPll < -1000000000) {
      // Sample the data bit
      final int rawBit = demodOutF > 0 ? 1 : 0;

      // Descramble the bit for 9600 baud (G3RUH scrambling)
      final desc = descramble(rawBit, s.lfsr);
      final int descrambledBit = desc.$1;
      s.lfsr = desc.$2;

      // Pass the descrambled bit to HDLC receiver
      hdlcReceiver.recBit(chan, subchan, slice, descrambledBit, false, 0);

      s.pllSymbolCount++;

      // Update DCD state
      _pllDcdEachSymbol2(d, chan, subchan, slice);
    }

    // Check for zero crossing
    if ((s.prevDemodOutF < 0 && demodOutF > 0) ||
        (s.prevDemodOutF > 0 && demodOutF < 0)) {
      // Signal transition detected
      _pllDcdSignalTransition2(d, slice, s.dataClockPll);

      // Calculate target phase using linear interpolation
      final double target =
          state9600.pllStepPerSample *
          demodOutF /
          (demodOutF - s.prevDemodOutF);

      final int before = s.dataClockPll;

      // Nudge PLL toward the target
      if (s.dataDetect != 0) {
        // Locked on - use locked inertia
        s.dataClockPll =
            (s.dataClockPll * state9600.pllLockedInertia +
                    target * (1.0 - state9600.pllLockedInertia))
                .toInt();
      } else {
        // Searching - use searching inertia
        s.dataClockPll =
            (s.dataClockPll * state9600.pllSearchingInertia +
                    target * (1.0 - state9600.pllSearchingInertia))
                .toInt();
      }

      s.pllNudgeTotal += s.dataClockPll - before;
    }

    // Remember demodulator output for next comparison
    s.prevDemodOutF = demodOutF;
  }

  /// Update DCD state when a signal transition is detected.
  static void _pllDcdSignalTransition2(
    DemodulatorState d,
    int slice,
    int dpllPhase,
  ) {
    final SlicerState s = d.slicer[slice];

    // Check if transition occurred at expected time (good) or not (bad)
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      s.goodFlag = 1;
    } else {
      s.badFlag = 1;
    }
  }

  /// Update DCD state for each symbol.
  static void _pllDcdEachSymbol2(
    DemodulatorState d,
    int chan,
    int subchan,
    int slice,
  ) {
    final SlicerState s = d.slicer[slice];

    // Shift history and add current flags
    s.goodHist = ((s.goodHist << 1) | s.goodFlag) & 0xFF;
    s.goodFlag = 0;

    s.badHist = ((s.badHist << 1) | s.badFlag) & 0xFF;
    s.badFlag = 0;

    // Compare good vs bad transitions (need at least 2 for flag pattern)
    final int goodCount = _popCount(s.goodHist);
    final int badCount = _popCount(s.badHist);
    s.score =
        ((s.score << 1) | ((goodCount - badCount >= 2) ? 1 : 0)) & 0xFFFFFFFF;

    // Check overall score
    final int scoreCount = _popCount(s.score);

    if (scoreCount >= _dcdThreshOn) {
      if (s.dataDetect == 0) {
        s.dataDetect = 1;
        // Would call dcd_change here in full implementation
      }
    } else if (scoreCount <= _dcdThreshOff) {
      if (s.dataDetect != 0) {
        s.dataDetect = 0;
        // Would call dcd_change here in full implementation
      }
    }
  }

  /// Count number of set bits (population count).
  static int _popCount(int value) {
    value &= 0xFFFFFFFF;
    int count = 0;
    while (value != 0) {
      count++;
      value &= value - 1;
    }
    return count;
  }

  /// Descramble a bit for G3RUH/K9NG scrambling.
  ///
  /// The data stream must be unscrambled at the receiving end.
  /// Returns a record of `(output, state)`.
  static (int, int) descramble(int input, int state) {
    final int output = (input ^ (state >> 16) ^ (state >> 11)) & 1;
    state = ((state << 1) | (input & 1)) & 0xFFFFFFFF;
    return (output, state);
  }
}
