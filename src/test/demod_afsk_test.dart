// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/demod_afsk.dart';
import 'package:htcommander/hamlib/ihdlc_receiver.dart';

class _Receiver implements IHdlcReceiver {
  final List<List<int>> events = [];

  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
  ) {
    events.add([chan, subchan, slice, raw, isScrambled ? 1 : 0, notUsedRemove]);
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    events.add([-1, chan, subchan, slice, dcdOn ? 1 : 0]);
  }
}

List<Float32List> _histories(DemodulatorState state) => [
  state.rawCb,
  state.afsk.mIRaw,
  state.afsk.mQRaw,
  state.afsk.sIRaw,
  state.afsk.sQRaw,
  state.afsk.cIRaw,
  state.afsk.cQRaw,
];

void main() {
  for (final rate in [32000, 48000]) {
    for (final profile in ['A', 'B']) {
      test(
        '$profile at $rate Hz preserves wrapped history on reinitialization',
        () {
          final continuousSink = _Receiver();
          final restartedSink = _Receiver();
          final continuous = DemodAfsk(continuousSink);
          final restarted = DemodAfsk(restartedSink);
          final continuousState = DemodulatorState();
          final restartedState = DemodulatorState();
          continuous.init(rate, 1200, 1200, 2200, profile, continuousState);
          restarted.init(rate, 1200, 1200, 2200, profile, restartedState);

          var index = 0;
          var phase = 0.0;
          for (final count in [
            1,
            continuousState.preFilterTaps - 1,
            continuousState.lpFilterTaps + 3,
            rate ~/ 4,
          ]) {
            for (var i = 0; i < count; i++, index++) {
              phase +=
                  2 *
                  math.pi *
                  ((index * 1200 ~/ rate).isEven ? 1200 : 2200) /
                  rate;
              final sample = index % 97 == 0
                  ? -32768
                  : (math.sin(phase) * 24000).round();
              continuous.processSample(0, 0, sample, continuousState);
              restarted.processSample(0, 0, sample, restartedState);
            }

            final afsk = restartedState.afsk;
            final phases = (afsk.mOscPhase, afsk.sOscPhase, afsk.cOscPhase);
            restarted.init(rate, 1200, 1200, 2200, profile, restartedState);
            // Initialization resets oscillators, but must preserve filter history.
            afsk.mOscPhase = phases.$1;
            afsk.sOscPhase = phases.$2;
            afsk.cOscPhase = phases.$3;
          }

          expect(restartedSink.events, isNotEmpty);
          expect(restartedSink.events, continuousSink.events);
          expect(restartedState.mPeak, continuousState.mPeak);
          expect(restartedState.sPeak, continuousState.sPeak);
          expect(restartedState.afsk.prevPhase, continuousState.afsk.prevPhase);
          expect(
            restartedState.slicer[0].dataClockPll,
            continuousState.slicer[0].dataClockPll,
          );

          continuous.init(rate, 1200, 1200, 2200, profile, continuousState);
          expect(_histories(restartedState), _histories(continuousState));
        },
      );
    }
  }
}
