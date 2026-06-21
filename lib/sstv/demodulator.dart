/*
SSTV Demodulator
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'complex.dart';
import 'complex_convolution.dart';
import 'delay.dart';
import 'filter.dart';
import 'frequency_modulation.dart';
import 'kaiser.dart';
import 'phasor.dart';
import 'schmitt_trigger.dart';
import 'simple_moving_average.dart';
import 'sstv_round.dart';

enum SyncPulseWidth { fiveMilliSeconds, nineMilliSeconds, twentyMilliSeconds }

class Demodulator {
  final SimpleMovingAverage _syncPulseFilter;
  final ComplexConvolution _baseBandLowPass;
  final FrequencyModulation _frequencyModulation;
  final SchmittTrigger _syncPulseTrigger;
  final Phasor _baseBandOscillator;
  final Delay _syncPulseValueDelay;
  final double _syncPulseFrequencyValue;
  final double _syncPulseFrequencyTolerance;
  final int _syncPulse5msMinSamples;
  final int _syncPulse5msMaxSamples;
  final int _syncPulse9msMaxSamples;
  final int _syncPulse20msMaxSamples;
  final int _syncPulseFilterDelay;
  int _syncPulseCounter = 0;
  Complex _baseBand;

  SyncPulseWidth syncPulseWidthValue = SyncPulseWidth.fiveMilliSeconds;
  int syncPulseOffset = 0;
  double frequencyOffset = 0;

  static const double syncPulseFrequency = 1200;
  static const double blackFrequency = 1500;
  static const double whiteFrequency = 2300;

  factory Demodulator(int sampleRate) {
    const double scanLineBandwidth = whiteFrequency - blackFrequency;
    const double syncPulse5msSeconds = 0.005;
    const double syncPulse9msSeconds = 0.009;
    const double syncPulse20msSeconds = 0.020;
    const double syncPulse5msMinSeconds = syncPulse5msSeconds / 2;
    const double syncPulse5msMaxSeconds =
        (syncPulse5msSeconds + syncPulse9msSeconds) / 2;
    const double syncPulse9msMaxSeconds =
        (syncPulse9msSeconds + syncPulse20msSeconds) / 2;
    const double syncPulse20msMaxSeconds =
        syncPulse20msSeconds + syncPulse5msSeconds;
    const double syncPulseFilterSeconds = syncPulse5msSeconds / 2;
    final int syncPulseFilterSamples =
        sstvRound(syncPulseFilterSeconds * sampleRate) | 1;

    const double lowestFrequency = 1000;
    const double highestFrequency = 2800;
    const double cutoffFrequency = (highestFrequency - lowestFrequency) / 2;
    const double baseBandLowPassSeconds = 0.002;
    final int baseBandLowPassSamples =
        sstvRound(baseBandLowPassSeconds * sampleRate) | 1;
    final baseBandLowPass = ComplexConvolution(baseBandLowPassSamples);
    final kaiser = Kaiser();
    for (int i = 0; i < baseBandLowPass.length; ++i) {
      baseBandLowPass.taps[i] =
          kaiser.window(2.0, i, baseBandLowPass.length) *
          Filter.lowPass(
            cutoffFrequency,
            sampleRate,
            i,
            baseBandLowPass.length,
          );
    }
    const double centerFrequency = (lowestFrequency + highestFrequency) / 2;

    double normalizeFrequency(double frequency) =>
        (frequency - centerFrequency) * 2 / scanLineBandwidth;

    const double syncPorchFrequency = 1500;
    const double syncHighFrequency =
        (syncPulseFrequency + syncPorchFrequency) / 2;
    const double syncLowFrequency =
        (syncPulseFrequency + syncHighFrequency) / 2;

    return Demodulator._(
      SimpleMovingAverage(syncPulseFilterSamples),
      baseBandLowPass,
      FrequencyModulation(scanLineBandwidth, sampleRate.toDouble()),
      SchmittTrigger(
        normalizeFrequency(syncLowFrequency),
        normalizeFrequency(syncHighFrequency),
      ),
      Phasor(-centerFrequency, sampleRate.toDouble()),
      Delay(syncPulseFilterSamples),
      normalizeFrequency(syncPulseFrequency),
      50 * 2 / scanLineBandwidth,
      sstvRound(syncPulse5msMinSeconds * sampleRate),
      sstvRound(syncPulse5msMaxSeconds * sampleRate),
      sstvRound(syncPulse9msMaxSeconds * sampleRate),
      sstvRound(syncPulse20msMaxSeconds * sampleRate),
      (syncPulseFilterSamples - 1) ~/ 2,
    );
  }

  Demodulator._(
    this._syncPulseFilter,
    this._baseBandLowPass,
    this._frequencyModulation,
    this._syncPulseTrigger,
    this._baseBandOscillator,
    this._syncPulseValueDelay,
    this._syncPulseFrequencyValue,
    this._syncPulseFrequencyTolerance,
    this._syncPulse5msMinSamples,
    this._syncPulse5msMaxSamples,
    this._syncPulse9msMaxSamples,
    this._syncPulse20msMaxSamples,
    this._syncPulseFilterDelay,
  ) : _baseBand = Complex();

  bool process(Float64List buffer, int channelSelect) {
    bool syncPulseDetected = false;
    final channels = channelSelect > 0 ? 2 : 1;
    for (int i = 0; i < buffer.length ~/ channels; ++i) {
      switch (channelSelect) {
        case 1:
          _baseBand.setR(buffer[2 * i]);
          break;
        case 2:
          _baseBand.setR(buffer[2 * i + 1]);
          break;
        case 3:
          _baseBand.setR(buffer[2 * i] + buffer[2 * i + 1]);
          break;
        case 4:
          _baseBand.setRI(buffer[2 * i], buffer[2 * i + 1]);
          break;
        default:
          _baseBand.setR(buffer[i]);
          break;
      }
      _baseBand = _baseBandLowPass.push(
        _baseBand.mulC(_baseBandOscillator.rotate()),
      );
      final frequencyValue = _frequencyModulation.demod(_baseBand);
      final syncPulseValue = _syncPulseFilter.avg(frequencyValue);
      final syncPulseDelayedValue = _syncPulseValueDelay.push(syncPulseValue);
      buffer[i] = frequencyValue;
      if (!_syncPulseTrigger.latch(syncPulseValue)) {
        ++_syncPulseCounter;
      } else if (_syncPulseCounter < _syncPulse5msMinSamples ||
          _syncPulseCounter > _syncPulse20msMaxSamples ||
          (syncPulseDelayedValue - _syncPulseFrequencyValue).abs() >
              _syncPulseFrequencyTolerance) {
        _syncPulseCounter = 0;
      } else {
        if (_syncPulseCounter < _syncPulse5msMaxSamples) {
          syncPulseWidthValue = SyncPulseWidth.fiveMilliSeconds;
        } else if (_syncPulseCounter < _syncPulse9msMaxSamples) {
          syncPulseWidthValue = SyncPulseWidth.nineMilliSeconds;
        } else {
          syncPulseWidthValue = SyncPulseWidth.twentyMilliSeconds;
        }
        syncPulseOffset = i - _syncPulseFilterDelay;
        frequencyOffset = syncPulseDelayedValue - _syncPulseFrequencyValue;
        syncPulseDetected = true;
        _syncPulseCounter = 0;
      }
    }
    return syncPulseDetected;
  }
}
