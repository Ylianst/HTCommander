// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/audio_buffer.dart';
import 'package:htcommander/hamlib/audio_config.dart';
import 'package:htcommander/hamlib/demod_afsk.dart';
import 'package:htcommander/hamlib/demod_psk.dart';
import 'package:htcommander/hamlib/gen_tone.dart';
import 'package:htcommander/hamlib/ihdlc_receiver.dart';
import 'package:htcommander/hamlib/native_packet_modem.dart';

class _Receiver implements IHdlcReceiver {
  final List<int> events = [];
  void Function()? onBit;

  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool scrambled,
    int q,
  ) {
    expect(chan, 0);
    expect(subchan, 0);
    expect(scrambled, false);
    events.add(raw | (q << 1) | (slice << 8));
    onBit?.call();
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool on) {
    events.add(4096 | (slice << 8) | (on ? 1 : 0));
  }
}

AudioConfig _config(ModemType mode, int rate, {bool altB = true, int? baud}) {
  final config = AudioConfig();
  config.devices[0].defined = true;
  config.devices[0].samplesPerSec = rate;
  config.devices[0].bitsPerSample = 16;
  config.devices[0].numChannels = 1;
  config.channelMedium[0] = Medium.radio;
  final channel = config.channels[0];
  channel.modemType = mode;
  channel.baud =
      baud ??
      (mode == ModemType.afsk
          ? 1200
          : mode == ModemType.qpsk
          ? 2400
          : 4800);
  channel.markFreq = 1200;
  channel.spaceFreq = 2200;
  channel.v26Alt = altB ? V26Alternative.b : V26Alternative.a;
  return config;
}

Uint8List _bits(int count) {
  final random = math.Random(47);
  return Uint8List.fromList(List.generate(count, (_) => random.nextInt(2)));
}

Uint8List _dartTones(AudioConfig config, Uint8List bits, int amplitude) {
  final buffer = AudioBuffer(1);
  final tone = GenTone(buffer)..init(config, amplitude);
  for (final bit in bits) {
    tone.putBit(0, bit);
  }
  final samples = buffer.getAndClear(0);
  final pcm = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(pcm);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return pcm;
}

void _compareRx(
  DemodulatorState state,
  _Receiver expected,
  void Function(int) dartSample,
  Uint8List pcm,
) {
  final actual = _Receiver();
  final native = NativePacketDemodulator(state, actual);
  try {
    // Include clipping, low-level input and silence in addition to modem audio.
    final input = Uint8List(pcm.length + 4096)..setAll(1024, pcm);
    final data = ByteData.sublistView(input);
    final random = math.Random(92);
    for (int i = 0; i < 512; i++) {
      data.setInt16(i * 2, i.isEven ? -32768 : 32767, Endian.little);
    }
    for (int i = pcm.length + 1024; i < input.length - 1024; i += 2) {
      data.setInt16(i, random.nextInt(127) - 63, Endian.little);
    }
    for (int i = 0; i < input.length; i += 2) {
      dartSample(data.getInt16(i, Endian.little));
    }
    var offset = 0, index = 0;
    final chunks = [2, 6, 2048, 14, 4098, 130];
    while (offset < input.length) {
      final length = math.min(
        chunks[index++ % chunks.length],
        input.length - offset,
      );
      // Exercise byte offsets, typed-data views and ignored odd trailing bytes.
      final padded = Uint8List(length + 9)
        ..setRange(3, length + 3, input, offset);
      native.process(Uint8List.sublistView(padded, 1), 2, length + 1);
      offset += length;
    }
    expect(actual.events, isNotEmpty);
    expect(actual.events, expected.events);
  } finally {
    native.dispose();
    native.dispose();
  }
  expect(() => native.process(pcm, 0, pcm.length), throwsStateError);
}

void main() {
  for (final rate in [8000, 32000, 44100, 48000]) {
    for (final mode in [ModemType.afsk, ModemType.qpsk, ModemType.psk8]) {
      for (final amplitude in [0, 50, 100]) {
        test('$mode $rate Hz amplitude $amplitude TX is bit-exact', () {
          final config = _config(mode, rate);
          final bits = _bits(
            1027,
          ); // Partial final PSK symbol must not emit PCM.
          final expected = _dartTones(config, bits, amplitude);
          final actual = encodeNativePacketTones(
            config.channels[0],
            rate,
            amplitude,
            bits,
            leadingSamples: 7,
            trailingSamples: 3,
          );
          expect(actual.length, expected.length + 20);
          expect(actual.sublist(0, 14), everyElement(0));
          expect(actual.sublist(14, actual.length - 6), expected);
          expect(actual.sublist(actual.length - 6), everyElement(0));
        }, skip: !nativePacketModemEnabled);
      }
    }
  }

  for (final rate in [32000, 48000]) {
    for (final profile in ['A', 'B']) {
      for (final slicers in [1, 3, 9]) {
        test('AFSK $profile $rate Hz $slicers slicers event parity', () {
          final sink = _Receiver();
          final demod = DemodAfsk(sink);
          final state = DemodulatorState();
          demod.init(rate, 1200, 1200, 2200, profile, state);
          state.numSlicers = slicers;
          final pcm = _dartTones(_config(ModemType.afsk, rate), _bits(601), 50);
          _compareRx(
            state,
            sink,
            (s) => demod.processSample(0, 0, s, state),
            pcm,
          );
        }, skip: !nativePacketModemEnabled);
      }
    }
    for (final scenario in [
      (mode: ModemType.qpsk, profiles: ['P', 'Q', 'R', 'S'], altB: false),
      (mode: ModemType.qpsk, profiles: ['P', 'Q', 'R', 'S'], altB: true),
      (mode: ModemType.psk8, profiles: ['T', 'U', 'V', 'W'], altB: false),
    ]) {
      for (final profile in scenario.profiles) {
        test(
          '${scenario.mode} $profile $rate Hz altB=${scenario.altB} event parity',
          () {
            final config = _config(scenario.mode, rate, altB: scenario.altB);
            final sink = _Receiver();
            final demod = DemodPsk(sink);
            final state = PskDemodulatorState();
            demod.init(
              scenario.mode,
              config.channels[0].v26Alt,
              rate,
              config.channels[0].baud,
              profile,
              state,
            );
            final pcm = _dartTones(config, _bits(1201), 50);
            _compareRx(
              state,
              sink,
              (s) => demod.processSample(0, 0, s, state),
              pcm,
            );
          },
          skip: !nativePacketModemEnabled,
        );
      }
    }
  }

  test('AFSK 300 baud and classic QPSK waveforms match Dart', () {
    for (final config in [
      _config(ModemType.afsk, 32000, baud: 300),
      _config(ModemType.qpsk, 48000, altB: false),
    ]) {
      final bits = _bits(701);
      expect(
        encodeNativePacketTones(
          config.channels[0],
          config.devices[0].samplesPerSec,
          50,
          bits,
        ),
        _dartTones(config, bits, 50),
      );
    }
  }, skip: !nativePacketModemEnabled);

  test('four-output prefilter preserves short and wrapping histories', () {
    final pcm = _dartTones(_config(ModemType.afsk, 32000), _bits(101), 50);
    for (final taps in [1, 2, 3, 4, 7, 8]) {
      final sink = _Receiver();
      final state = DemodulatorState();
      final demod = DemodAfsk(sink);
      demod.init(32000, 1200, 1200, 2200, 'A', state);
      state.preFilterTaps = taps;
      for (int i = 0; i < taps; i++) {
        state.preFilter[i] = (i.isEven ? 1 : -1) / (i + 1);
      }
      _compareRx(state, sink, (s) => demod.processSample(0, 0, s, state), pcm);
    }
  }, skip: !nativePacketModemEnabled);

  test(
    'native PCM results own independent storage, including zero samples',
    () {
      final config = _config(ModemType.qpsk, 32000);
      final bits = _bits(101);
      final first = encodeNativePacketTones(
        config.channels[0],
        32000,
        50,
        bits,
      );
      final expected = Uint8List.fromList(first);
      final second = encodeNativePacketTones(
        config.channels[0],
        32000,
        50,
        bits,
      );
      second.fillRange(0, second.length, 0);
      expect(first, expected);
      expect(first, isNot(everyElement(0)));
      final partial = encodeNativePacketTones(
        config.channels[0],
        32000,
        50,
        Uint8List.fromList([1]),
      );
      expect(partial, isEmpty);
      final silence = encodeNativePacketTones(
        config.channels[0],
        32000,
        50,
        Uint8List(0),
        leadingSamples: 5,
        trailingSamples: 3,
      );
      expect(silence, List.filled(16, 0));
    },
    skip: !nativePacketModemEnabled,
  );

  test('batched mixer FIR preserves short, even and wrapping histories', () {
    for (final mode in [ModemType.afsk, ModemType.qpsk]) {
      final pcm = _dartTones(_config(mode, 32000), _bits(101), 50);
      for (final taps in [1, 2, 4, 7]) {
        final sink = _Receiver();
        final DemodulatorState state;
        final void Function(int) sample;
        final Float32List coefficients;
        if (mode == ModemType.afsk) {
          state = DemodulatorState();
          final demod = DemodAfsk(sink);
          demod.init(32000, 1200, 1200, 2200, 'A', state);
          state.lpFilterTaps = taps;
          coefficients = state.lpFilter;
          sample = (s) => demod.processSample(0, 0, s, state);
        } else {
          final psk = PskDemodulatorState();
          state = psk;
          final demod = DemodPsk(sink);
          demod.init(mode, V26Alternative.b, 32000, 2400, 'R', psk);
          psk.psk.lpFilterTaps = taps;
          coefficients = psk.psk.lpFilter;
          sample = (s) => demod.processSample(0, 0, s, psk);
        }
        for (int i = 0; i < taps; i++) {
          coefficients[i] = (i.isEven ? 1 : -1) / (i + 1);
        }
        _compareRx(state, sink, sample, pcm);
      }
    }
  }, skip: !nativePacketModemEnabled);

  test(
    'pinned PCM supports heap, native and read-only views without mutation',
    () {
      final config = _config(ModemType.afsk, 32000);
      final bits = _bits(201);
      final heap = _dartTones(config, bits, 50);
      final external = encodeNativePacketTones(
        config.channels[0],
        32000,
        50,
        bits,
      );
      for (final pcm in [
        heap,
        external,
        Uint8List.sublistView(external, 1),
        heap.asUnmodifiableView(),
      ]) {
        final original = Uint8List.fromList(pcm);
        final actual = _Receiver(), expected = _Receiver();
        final state = DemodulatorState();
        final demod = DemodAfsk(expected);
        demod.init(32000, 1200, 1200, 2200, 'A', state);
        final native = NativePacketDemodulator(state, actual);
        try {
          final data = ByteData.sublistView(pcm);
          for (int i = 2; i + 1 < pcm.length; i += 2) {
            demod.processSample(0, 0, data.getInt16(i, Endian.little), state);
          }
          native.process(pcm, 2, pcm.length - 2);
          expect(actual.events, isNotEmpty);
          expect(actual.events, expected.events);
          expect(pcm, original);
        } finally {
          native.dispose();
        }
      }
    },
    skip: !nativePacketModemEnabled,
  );

  test('PSK half-phase ties retain a one bit in either Gray direction', () {
    for (final sign in [1.0, -1.0]) {
      final actual = _Receiver(), expected = _Receiver();
      final demod = DemodPsk(expected);
      final state = PskDemodulatorState();
      demod.init(ModemType.qpsk, V26Alternative.a, 32000, 2400, 'R', state);
      state.pllStepPerSample = 0x40000000;
      state.psk.usePrefilter = 0;
      state.psk.lpFilterTaps = 1;
      state.psk.lpFilter[0] = 1;
      state.psk.delayLineTaps = 4;
      state.psk.bOffs = 3;
      state.psk.cOffs = 0;
      state.psk.sOffs = 0;
      state.psk.loStep = 0;
      state.psk.sinTable256[0] = sign;
      state.psk.sinTable256[64] = sign;
      final native = NativePacketDemodulator(state, actual);
      try {
        final pcm = Uint8List(64);
        final data = ByteData.sublistView(pcm);
        for (int i = 0; i < 32; i++) {
          data.setInt16(i * 2, 16384, Endian.little);
          demod.processSample(0, 0, 16384, state);
        }
        native.process(pcm, 0, pcm.length);
        expect(actual.events.take(2), [sign > 0 ? 200 : 201, 1]);
        expect(actual.events, expected.events);
      } finally {
        native.dispose();
      }
    }
  }, skip: !nativePacketModemEnabled);

  test('carrier acquisition and loss preserve ordered bit/DCD delivery', () {
    for (final mode in [ModemType.afsk, ModemType.qpsk]) {
      final actual = _Receiver(), expected = _Receiver();
      final DemodulatorState state;
      final void Function(int) sample;
      if (mode == ModemType.afsk) {
        state = DemodulatorState();
        final demod = DemodAfsk(expected);
        demod.init(32000, 1200, 1200, 2200, 'A', state);
        sample = (s) => demod.processSample(0, 0, s, state);
      } else {
        final psk = PskDemodulatorState();
        state = psk;
        final demod = DemodPsk(expected);
        demod.init(mode, V26Alternative.b, 32000, 2400, 'R', psk);
        sample = (s) => demod.processSample(0, 0, s, psk);
      }
      final tones = _dartTones(_config(mode, 32000), _bits(1800), 50);
      final burstBytes = tones.length + 32000;
      final pcm = Uint8List(burstBytes * 2)
        ..setAll(0, tones)
        ..setAll(burstBytes, tones);
      final native = NativePacketDemodulator(state, actual);
      try {
        final samples = ByteData.sublistView(pcm);
        for (int i = 0; i < pcm.length; i += 2) {
          sample(samples.getInt16(i, Endian.little));
        }
        native.process(pcm, 0, pcm.length);
        expect(actual.events, expected.events);
        expect(actual.events.where((e) => (e & 4096) != 0), [
          4097,
          4096,
          4097,
          4096,
        ]);
      } finally {
        native.dispose();
      }
    }
  }, skip: !nativePacketModemEnabled);

  test('callback disposal stops event delivery and reentrancy is rejected', () {
    final sink = _Receiver();
    final state = DemodulatorState();
    DemodAfsk(sink).init(32000, 1200, 1200, 2200, 'A', state);
    final native = NativePacketDemodulator(state, sink);
    final pcm = _dartTones(_config(ModemType.afsk, 32000), _bits(101), 50);
    sink.onBit = () {
      expect(() => native.process(pcm, 0, 2), throwsStateError);
      native.dispose();
    };
    native.process(pcm, 0, pcm.length);
    expect(sink.events.length, 1);
  }, skip: !nativePacketModemEnabled);

  test('invalid input is rejected without consuming the RX stream', () {
    final sink = _Receiver();
    final state = DemodulatorState();
    DemodAfsk(sink).init(32000, 1200, 1200, 2200, 'A', state);
    final native = NativePacketDemodulator(state, sink);
    try {
      expect(() => native.process(Uint8List(4), 1, 4), throwsRangeError);
      expect(() => native.process(Uint8List(4), 2, -1), throwsRangeError);
      native.process(Uint8List(0), 0, 0);
      expect(sink.events, isEmpty);
    } finally {
      native.dispose();
    }
    expect(
      () => encodeNativePacketTones(
        _config(ModemType.afsk, 32000).channels[0],
        32000,
        50,
        Uint8List.fromList([0, 2, 1]),
      ),
      throwsStateError,
    );
  }, skip: !nativePacketModemEnabled);
}
