// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/modem_rx_worker.dart';
import 'package:htcommander/radio/modem_tx_encoder.dart';

void main() {
  test('truncated FX.25 retains the timed plain-HDLC fallback', () async {
    const rate = 32000;
    final encoder = ModemTxEncoder();
    addTearDown(encoder.dispose);
    final frame = Uint8List.fromList(
      List.generate(83, (i) => (i * 13 + 7) & 255),
    );
    final encoded = await encoder.encodePacket(
      modulation: PacketModulation.afsk1200,
      fecEnabled: true,
      txdelay: 30,
      txtail: 10,
      sampleRate: rate,
      frames: [frame],
    );
    final received = Completer<ModemRxEvent>();
    final errors = <Object>[];
    final receiver = ModemRxWorker(
      mode: ModemRxMode.afsk1200,
      sampleRate: rate,
      onEvent: received.complete,
      onError: (error, _) => errors.add(error),
    );
    addTearDown(receiver.dispose);
    // Keep the embedded valid HDLC frame, but omit the end of the RS block.
    receiver.process(encoded.pcm!, 0, (rate * 2 * 1.6).round(), context: 101);
    await receiver.idle;
    expect(received.isCompleted, isFalse);
    final event = await received.future.timeout(const Duration(seconds: 3));
    expect(errors, isEmpty);
    expect(event.frame, frame);
    expect(event.fx25, isFalse);
    expect(event.context, 101);
  });

  for (final modulation in PacketModulation.values) {
    for (final rate in [32000, 48000]) {
      for (final fec in [false, true]) {
        test(
          '$modulation $rate Hz FEC=$fec receives ordered frames without an end marker',
          () async {
            final encoder = ModemTxEncoder();
            addTearDown(encoder.dispose);
            final frames = [
              Uint8List.fromList(List.generate(83, (i) => (i * 13 + 7) & 255)),
              Uint8List.fromList(List.generate(34, (i) => (i * 17 + 3) & 255)),
            ];
            final encoded = await encoder.encodePacket(
              modulation: modulation,
              fecEnabled: fec,
              txdelay: 30,
              txtail: 10,
              sampleRate: rate,
              frames: frames,
            );
            expect(
              encoded.logs.any((line) => line.contains('encode error')),
              isFalse,
            );
            final events = <ModemRxEvent>[];
            final errors = <Object>[];
            final receiver = ModemRxWorker(
              mode: modulation == PacketModulation.afsk1200
                  ? ModemRxMode.afsk1200
                  : ModemRxMode.psk2400,
              sampleRate: rate,
              onEvent: events.add,
              onError: (error, _) => errors.add(error),
            );
            addTearDown(receiver.dispose);
            final pcm = encoded.pcm!;
            for (int offset = 0; offset < pcm.length; offset += 1024) {
              receiver.process(
                pcm,
                offset,
                math.min(1024, pcm.length - offset),
                context: 'captured channel',
              );
              if (offset % (1024 * 16) == 0) await receiver.idle;
            }
            await receiver.idle;
            expect(errors, isEmpty);
            expect(events, hasLength(frames.length));
            for (int i = 0; i < frames.length; i++) {
              expect(events[i].frame, frames[i]);
            }
            expect(
              events.every((event) => event.context == 'captured channel'),
              isTrue,
            );
            expect(events.every((event) => event.fx25 == fec), isTrue);
            expect(events.every((event) => event.corrections == 0), isTrue);
          },
        );
      }
    }
  }
}
