// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Run with: dart run test\packet_modem_benchmark.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/demod_afsk.dart';
import 'package:htcommander/hamlib/demod_psk.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/ihdlc_receiver.dart';
import 'package:htcommander/hamlib/native_packet_modem.dart';

class _Sink implements IHdlcReceiver {
  int checksum = 0;
  @override
  void recBit(int c, int s, int k, int raw, bool scrambled, int q) {
    checksum = (checksum + raw + q) & 0x7fffffff;
  }

  @override
  void dcdChange(int c, int s, int k, bool on) {}
}

double _measure(void Function() run) {
  // Warm up both JIT code and native code before timing a median of five runs.
  for (int i = 0; i < 3; i++) {
    run();
  }
  final times = <int>[];
  for (int i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    run();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[2] / 1000;
}

void main() {
  if (!nativePacketModemEnabled) {
    throw StateError('This benchmark requires the native packet modem');
  }
  const rate = 32000;
  final random = math.Random(47);
  for (final mode in [ModemType.afsk, ModemType.qpsk]) {
    final config = AudioConfig();
    config.devices[0].defined = true;
    config.devices[0].samplesPerSec = rate;
    config.devices[0].bitsPerSample = 16;
    config.devices[0].numChannels = 1;
    config.channelMedium[0] = Medium.radio;
    final channel = config.channels[0];
    channel.modemType = mode;
    channel.baud = mode == ModemType.afsk ? 1200 : 2400;
    channel.v26Alt = V26Alternative.b;
    final bits = Uint8List.fromList(
      List.generate(channel.baud * 5, (_) => random.nextInt(2)),
    );
    final pcm = encodeNativePacketTones(channel, rate, 50, bits);
    final samples = ByteData.sublistView(pcm);
    final nativeSink = _Sink(), dartSink = _Sink();
    final DemodulatorState state;
    final void Function(int) dartSample;
    if (mode == ModemType.afsk) {
      state = DemodulatorState();
      final demod = DemodAfsk(dartSink);
      demod.init(rate, 1200, 1200, 2200, 'A', state);
      dartSample = (sample) => demod.processSample(0, 0, sample, state);
    } else {
      final pskState = PskDemodulatorState();
      state = pskState;
      final demod = DemodPsk(dartSink);
      demod.init(mode, V26Alternative.b, rate, 2400, 'B', pskState);
      dartSample = (sample) => demod.processSample(0, 0, sample, pskState);
    }
    final native = NativePacketDemodulator(state, nativeSink);
    try {
      final dartRx = _measure(() {
        for (int i = 0; i < pcm.length; i += 2) {
          dartSample(samples.getInt16(i, Endian.little));
        }
      });
      final nativeRx = _measure(() {
        for (int i = 0; i < pcm.length; i += 640) {
          native.process(pcm, i, math.min(640, pcm.length - i));
        }
      });
      if (dartSink.checksum != nativeSink.checksum) {
        throw StateError('Receive checksum mismatch');
      }
      int dartSamples = 0, nativeSamples = 0;
      final dartTx = _measure(() {
        final buffer = AudioBuffer(1);
        final tone = GenTone(buffer)..init(config, 50);
        for (final bit in bits) {
          tone.putBit(0, bit);
        }
        dartSamples = buffer.getAndClear(0).length;
      });
      final nativeTx = _measure(() {
        nativeSamples =
            encodeNativePacketTones(channel, rate, 50, bits).length ~/ 2;
      });
      if (dartSamples != nativeSamples) throw StateError('TX length mismatch');
      print(
        '${mode.name} 5 s audio, median milliseconds: '
        'RX Dart=${dartRx.toStringAsFixed(2)} native=${nativeRx.toStringAsFixed(2)} '
        '(${(dartRx / nativeRx).toStringAsFixed(2)}x); '
        'TX Dart=${dartTx.toStringAsFixed(2)} native=${nativeTx.toStringAsFixed(2)} '
        '(${(dartTx / nativeTx).toStringAsFixed(2)}x)',
      );
    } finally {
      native.dispose();
    }
  }
}
