/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/fm_rx.dart';
import 'package:htcommander/hamlib/xara/fm_tx.dart';
import 'package:htcommander/hamlib/xara/receiver_common.dart';
import 'package:htcommander/hamlib/xara/resample.dart';
import 'package:htcommander/radio/audio_engine.dart';
import 'package:htcommander/sbc/sbc_decoder.dart';
import 'package:htcommander/sbc/sbc_encoder.dart';
import 'package:htcommander/sbc/sbc_enums.dart';
import 'package:htcommander/sbc/sbc_frame.dart';

Uint8List _payload(Uint8List packet) {
  expect(packet.first, 0x7e);
  expect(packet.last, 0x7e);
  expect(packet[1], 0);
  final List<int> bytes = <int>[];
  for (int i = 2; i < packet.length - 1; i++) {
    bytes.add(packet[i] == 0x7d ? packet[++i] ^ 0x20 : packet[i]);
  }
  return Uint8List.fromList(bytes);
}

class _Tx {
  _Tx({this.prepared = false, this.unsupported = false});

  final bool prepared;
  final bool unsupported;
  final List<Uint8List> packets = <Uint8List>[];
  final List<int> writeSizes = <int>[];
  final List<PreparedAudioJob> jobs = <PreparedAudioJob>[];
  int endWrites = 0;
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  final Completer<void> done = Completer<void>();
  late final AudioEngine engine = AudioEngine(
    (Map<String, Object?> event) {
      events.add(event);
      if (event['evt'] == 'txState' && event['transmitting'] == false) {
        done.complete();
      }
    },
    btSend: (Uint8List write) async {
      if (write[1] != 0) {
        endWrites++;
        return;
      }
      _captureWrite(write);
    },
    btSendPrepared: prepared
        ? (job) async {
            jobs.add(job);
            if (unsupported) throw const PreparedAudioUnsupportedException();
            int offset = 0;
            for (final length in job.lengths) {
              _captureWrite(
                Uint8List.sublistView(job.data, offset, offset + length),
              );
              offset += length;
            }
            expect(offset, job.data.length);
            return PreparedAudioResult(
              cancelled: false,
              samplesSent: job.samples.reduce((a, b) => a + b),
            );
          }
        : null,
    btCancelPrepared: prepared ? (_) async {} : null,
  );

  void _captureWrite(Uint8List write) {
    // A write may coalesce several 0x7e-framed packets; split them back out.
    int count = 0;
    int start = 0;
    for (int i = 1; i < write.length; i++) {
      if (write[i] == 0x7e) {
        packets.add(Uint8List.sublistView(write, start, i + 1));
        count++;
        start = i + 1;
        i++;
      }
    }
    expect(start, write.length);
    writeSizes.add(count);
  }

  Future<void> send(
    Uint8List pcm, {
    bool data = true,
    bool bulk = false,
  }) async {
    engine.transmitVoice(
      pcm,
      0,
      pcm.length,
      false,
      isDataFrame: data,
      isBulkData: bulk,
    );
    await done.future.timeout(const Duration(seconds: 5));
  }

  List<int> decode(SbcBitAllocationMethod allocation) {
    final SbcDecoder decoder = SbcDecoder();
    final List<int> samples = <int>[];
    for (final Uint8List packet in packets) {
      final Uint8List bytes = _payload(packet);
      expect(bytes.length, lessThanOrEqualTo(300));
      int offset = 0;
      while (offset < bytes.length) {
        final Uint8List rest = Uint8List.sublistView(bytes, offset);
        final frame = decoder.probe(rest);
        expect(frame, isNotNull);
        expect(frame!.bitpool, 18);
        expect(frame.frequency, SbcFrequency.freq32K);
        expect(frame.mode, SbcMode.mono);
        expect(frame.allocationMethod, allocation);
        expect(frame.getFrameSize(), 44);
        final result = decoder.decode(
          Uint8List.sublistView(rest, 0, frame.getFrameSize()),
        );
        expect(result.success, isTrue);
        samples.addAll(result.pcmLeft);
        offset += frame.getFrameSize();
      }
      expect(offset, bytes.length);
    }
    return samples;
  }
}

Uint8List _pcm(List<double> samples) {
  final ByteData bytes = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    bytes.setInt16(
      i * 2,
      (samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('prepared native transmissions', () {
    for (final transferred in [false, true]) {
      test(
        'preserves PCM ownership and monitored bytes, transferred=$transferred',
        () async {
          final expected = _pcm(
            List.generate(64000, (i) => 0.3 * math.sin(i * 0.3)),
          );
          final source = Uint8List(expected.length + 7)
            ..setRange(3, 3 + expected.length, expected);
          final played = BytesBuilder(copy: false);
          final reported = BytesBuilder(copy: false);
          final playbackDone = Completer<void>();
          final transmitDone = Completer<void>();
          PreparedAudioJob? submitted;
          final engine = AudioEngine(
            (event) {
              if (event['evt'] == 'play') {
                expect(event['received'], isFalse);
                played.add(
                  (event['pcm']! as TransferableTypedData)
                      .materialize()
                      .asUint8List(),
                );
                if (played.length == expected.length) playbackDone.complete();
              } else if (event['evt'] == 'audioData') {
                reported.add(
                  (event['pcm']! as TransferableTypedData)
                      .materialize()
                      .asUint8List(),
                );
              } else if (event['evt'] == 'txState' &&
                  event['transmitting'] == false) {
                transmitDone.complete();
              }
            },
            btSendPrepared: (job) async {
              submitted = job;
              return PreparedAudioResult(
                cancelled: false,
                samplesSent: job.samples.reduce((a, b) => a + b),
              );
            },
            btCancelPrepared: (_) async {},
          );
          addTearDown(() => engine.handleCommand({'cmd': 'shutdown'}));
          if (transferred) {
            await engine.handleCommand({
              'cmd': 'tx',
              'pcm': TransferableTypedData.fromList([
                Uint8List.sublistView(source, 3, 3 + expected.length),
              ]),
              'playLocally': true,
              'isBulkData': true,
            });
          } else {
            engine.transmitVoice(
              source,
              3,
              expected.length,
              true,
              isBulkData: true,
            );
          }
          source.fillRange(0, source.length, 0);
          await Future.wait([
            transmitDone.future,
            playbackDone.future,
          ]).timeout(const Duration(seconds: 5));
          expect(played.takeBytes(), expected);
          expect(reported.takeBytes(), expected);
          final reference = _Tx(prepared: true);
          addTearDown(
            () => reference.engine.handleCommand({'cmd': 'shutdown'}),
          );
          await reference.send(expected, data: false, bulk: true);
          expect(submitted!.data, reference.jobs.single.data);
        },
      );
    }

    for (final data in [false, true]) {
      test(
        'prepares identical ${data ? "modem" : "SSTV"} bytes in one job',
        () async {
          final pcm = _pcm(
            List<double>.generate(
              182 * 128 + 21,
              (i) => 0.3 * math.sin(i * 0.3),
            ),
          );
          final streaming = _Tx();
          final native = _Tx(prepared: true);
          await streaming.send(pcm, data: data, bulk: !data);
          await native.send(pcm, data: data, bulk: !data);
          expect(native.packets, streaming.packets);
          expect(native.endWrites, 0, reason: 'native owns the end marker');
          final job = native.jobs.single;
          expect(job.leadMs, data ? 10000 : 6000);
          expect(job.samples, [3072, 3072, 3072, 3072, 3072, 3072, 3072, 1792]);
          expect(
            native
                .decode(
                  data
                      ? SbcBitAllocationMethod.snr
                      : SbcBitAllocationMethod.loudness,
                )
                .length,
            182 * 128,
          );
          expect(
            native.events
                .where((e) => e['evt'] == 'audioData')
                .fold(0, (int sum, e) => sum + (e['length'] as int)),
            182 * 256,
          );
        },
      );
    }

    test('voice still uses streaming writes', () async {
      final tx = _Tx(prepared: true);
      await tx.send(Uint8List(30 * 256), data: false);
      expect(tx.jobs, isEmpty);
      expect(tx.writeSizes, [4, 1]);
      expect(tx.endWrites, 1);
    });

    test(
      'unsupported shared endpoints preserve legacy transmission explicitly',
      () async {
        final tx = _Tx(prepared: true, unsupported: true);
        await tx.send(Uint8List(30 * 256));
        expect(tx.decode(SbcBitAllocationMethod.snr).length, 30 * 128);
        expect(tx.endWrites, 1);
        expect(
          tx.events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
          contains(contains('without UI-stall protection')),
        );
      },
    );

    test(
      'long SSTV is submitted whole without Dart real-time pacing',
      () async {
        final tx = _Tx(prepared: true);
        await tx.send(Uint8List(8 * 32000 * 2), data: false, bulk: true);
        final job = tx.jobs.single;
        expect(job.samples.reduce((a, b) => a + b), 8 * 32000);
        expect(tx.endWrites, 0);
      },
    );

    test(
      'cancellation targets the active job without a competing stop write',
      () async {
        final submitted = Completer<PreparedAudioJob>();
        final result = Completer<PreparedAudioResult>();
        final done = Completer<void>();
        final events = <Map<String, Object?>>[];
        final cancelledIds = <int>[];
        int streamingWrites = 0;
        final engine = AudioEngine(
          (event) {
            events.add(event);
            if (event['evt'] == 'txState' && event['transmitting'] == false) {
              done.complete();
            }
          },
          btSend: (_) async {
            streamingWrites++;
          },
          btSendPrepared: (job) {
            submitted.complete(job);
            return result.future;
          },
          btCancelPrepared: (id) async {
            cancelledIds.add(id);
          },
        );
        final pcm = Uint8List(30 * 256);
        engine.transmitVoice(pcm, 0, pcm.length, false, isBulkData: true);
        final job = await submitted.future;
        engine.transmitVoice(pcm, 0, pcm.length, false, isBulkData: true);
        engine.cancelVoiceTransmit();
        expect(cancelledIds, [job.jobId]);
        expect(streamingWrites, 0);
        result.complete(
          const PreparedAudioResult(cancelled: true, samplesSent: 3072),
        );
        await done.future.timeout(const Duration(seconds: 2));
        expect(streamingWrites, 0);
        expect(
          events.where((e) => e['evt'] == 'audioData').single['length'],
          6144,
        );
      },
    );

    test(
      'preparation can be cancelled before any bytes are submitted',
      () async {
        final tx = _Tx(prepared: true);
        final pcm = Uint8List(20 * 32000 * 2);
        tx.engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
        tx.engine.cancelVoiceTransmit();
        await tx.done.future.timeout(const Duration(seconds: 2));
        expect(tx.jobs, isEmpty);
        expect(tx.endWrites, 0);
      },
    );

    test('a busy channel is rechecked after preparation', () async {
      final tx = _Tx(prepared: true);
      await tx.engine.handleCommand({'cmd': 'radioState', 'receiving': true});
      final pcm = Uint8List(30 * 256);
      tx.engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tx.jobs, isEmpty);
      await tx.engine.handleCommand({'cmd': 'radioState', 'receiving': false});
      await tx.done.future.timeout(const Duration(seconds: 2));
      expect(tx.jobs, hasLength(1));
    });

    test('expired modem audio never keys the radio', () async {
      final tx = _Tx(prepared: true);
      final pcm = Uint8List(30 * 256);
      tx.engine.transmitVoice(
        pcm,
        0,
        pcm.length,
        false,
        isDataFrame: true,
        deadlineMs: 1,
      );
      await tx.done.future.timeout(const Duration(seconds: 2));
      expect(tx.jobs, isEmpty);
      expect(tx.endWrites, 0);
      expect(
        tx.events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
        contains(contains('expired before submission')),
      );
    });

    test(
      'native failure is reported without replay or duplicate stop',
      () async {
        final done = Completer<void>();
        final events = <Map<String, Object?>>[];
        int writes = 0;
        final engine = AudioEngine(
          (event) {
            events.add(event);
            if (event['evt'] == 'txState' && event['transmitting'] == false) {
              done.complete();
            }
          },
          btSend: (_) async {
            writes++;
          },
          btSendPrepared: (_) async {
            throw StateError('native write failed');
          },
          btCancelPrepared: (_) async {},
        );
        final pcm = Uint8List(30 * 256);
        engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
        await done.future.timeout(const Duration(seconds: 2));
        expect(writes, 0);
        expect(
          events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
          contains(contains('native write failed')),
        );
      },
    );
  });

  test(
    'cancelling data audio drops queued PCM and ends the current run',
    () async {
      final firstWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      final stopped = Completer<void>();
      var payloadWrites = 0;
      var endWrites = 0;
      final engine = AudioEngine(
        (event) {
          if (event['evt'] == 'txState' && event['transmitting'] == false) {
            stopped.complete();
          }
        },
        btSend: (write) async {
          if (write[1] == 0) {
            payloadWrites++;
            if (!firstWrite.isCompleted) firstWrite.complete();
            await releaseWrite.future;
          } else {
            endWrites++;
          }
        },
      );
      final pcm = Uint8List(20 * 32000 * 2);
      engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
      engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
      await firstWrite.future;
      engine.cancelVoiceTransmit();
      expect(endWrites, greaterThan(0));
      releaseWrite.complete();
      await stopped.future.timeout(const Duration(seconds: 1));
      expect(payloadWrites, 1, reason: 'cancelled PCM continued transmitting');
    },
  );

  for (final bool data in <bool>[false, true]) {
    test(
      'stock bitrate and bounded complete packets for ${data ? "data" : "voice"}',
      () async {
        final _Tx tx = _Tx();
        await tx.send(
          _pcm(
            List<double>.generate(17 * 128, (int i) => 0.3 * math.sin(i * 0.3)),
          ),
          data: data,
        );
        expect(tx.packets.map((Uint8List p) => _payload(p).length), <int>[
          264,
          264,
          220,
        ]);
        expect(
          tx
              .decode(
                data
                    ? SbcBitAllocationMethod.snr
                    : SbcBitAllocationMethod.loudness,
              )
              .length,
          17 * 128,
        );
      },
    );
  }

  test('partial SBC input is carried across streamed PCM chunks', () async {
    final _Tx tx = _Tx();
    final Uint8List first = Uint8List(6 * 256 + 42);
    tx.engine.transmitVoice(first, 0, first.length, false, isDataFrame: true);
    final Uint8List second = Uint8List(214);
    tx.engine.transmitVoice(second, 0, second.length, false, isDataFrame: true);
    await tx.done.future.timeout(const Duration(seconds: 5));
    expect(tx.decode(SbcBitAllocationMethod.snr).length, 7 * 128);
  });

  test(
    'precomputed modem audio retains the ten-second buffering lead',
    () async {
      final _Tx tx = _Tx();
      await tx.send(Uint8List(3 * 32000 * 2));
      expect(tx.decode(SbcBitAllocationMethod.snr).length, 3 * 32000);
      expect(
        tx.events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
        contains(
          startsWith('TX audio: bitpool=18, lead=10000ms, audio=3000ms,'),
        ),
      );
    },
  );

  test('SSTV bulk data uses the deep cancellable lead', () async {
    final _Tx tx = _Tx();
    await tx.send(Uint8List(3 * 32000 * 2), data: false, bulk: true);
    expect(tx.decode(SbcBitAllocationMethod.loudness).length, 3 * 32000);
    expect(
      tx.events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
      contains(startsWith('TX audio: bitpool=18, lead=6000ms, audio=3000ms,')),
    );
    expect(
      tx.events.where((e) => e['evt'] == 'txState' && e['isDataFrame'] == true),
      isEmpty,
    );
  });

  test('SBC packets are coalesced into fewer Bluetooth writes', () async {
    final _Tx tx = _Tx();
    // 30 packets of 6 frames each, plus a 2-frame tail packet.
    await tx.send(Uint8List(182 * 256));
    expect(tx.writeSizes, <int>[4, 4, 4, 4, 4, 4, 4, 3]);
    expect(tx.decode(SbcBitAllocationMethod.snr).length, 182 * 128);
    final int reported = tx.events
        .where((e) => e['evt'] == 'audioData')
        .fold(0, (int sum, e) => sum + (e['length'] as int));
    expect(reported, 182 * 256);
  });

  test('failed writes abort queued audio and report the failure', () async {
    final Completer<void> release = Completer<void>();
    final Completer<void> done = Completer<void>();
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    int audioWrites = 0;
    int endWrites = 0;
    final AudioEngine engine = AudioEngine(
      (event) {
        events.add(event);
        if (event['evt'] == 'txState' && event['transmitting'] == false) {
          done.complete();
        }
      },
      btSend: (packet) async {
        if (packet[1] != 0) {
          endWrites++;
          return;
        }
        audioWrites++;
        await release.future;
        throw StateError('write rejected');
      },
    );
    final Uint8List pcm = Uint8List(256 * 12);
    engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
    engine.transmitVoice(pcm, 0, pcm.length, false, isDataFrame: true);
    release.complete();
    await done.future.timeout(const Duration(seconds: 5));
    expect(audioWrites, 1);
    expect(endWrites, 1);
    expect(
      events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
      contains(contains('Voice transmit error: Bad state: write rejected')),
    );
  });

  group('received audio continuity', () {
    // Received-audio packets (cmd 0x03), 24 ms each, built by the transmit
    // encoder so the receive decoder sees real SBC payloads.
    Future<List<Uint8List>> rxPackets(int count) async {
      final _Tx tx = _Tx();
      await tx.send(Uint8List(count * 6 * 256), data: false);
      return tx.packets.map((Uint8List p) {
        final Uint8List rx = Uint8List.fromList(p);
        rx[1] = 0x03;
        return rx;
      }).toList();
    }

    test(
      'RX speaker events are tagged without suppressing data consumers',
      () async {
        final events = <Map<String, Object?>>[];
        final engine = AudioEngine(events.add);
        addTearDown(
          () => engine.handleCommand(<String, Object?>{'cmd': 'shutdown'}),
        );
        final packets = await rxPackets(3);
        for (final packet in packets) {
          await engine.handleCommand(<String, Object?>{
            'cmd': 'rx',
            'bytes': packet,
          });
        }
        final playback = events.where((event) => event['evt'] == 'play');
        expect(playback, hasLength(3));
        expect(playback.every((event) => event['received'] == true), isTrue);
        expect(
          events.where((event) => event['evt'] == 'audioData'),
          hasLength(3),
        );
      },
    );

    Future<List<String>> run(
      List<Uint8List> packets,
      Set<int> dropped, {
      int packetMs = 24,
      int deliveryDelayMs = 0,
    }) async {
      int now = 0;
      final List<String> logs = <String>[];
      final AudioEngine engine = AudioEngine((Map<String, Object?> e) {
        if (e['evt'] == 'log') logs.add(e['msg']! as String);
      }, clockMs: () => now);
      await engine.handleCommand(<String, Object?>{
        'cmd': 'setMute',
        'value': true,
      });
      for (int i = 0; i < packets.length; i++) {
        now = i * packetMs + (i >= 30 ? deliveryDelayMs : 0);
        if (dropped.contains(i)) continue;
        await engine.handleCommand(<String, Object?>{
          'cmd': 'rx',
          'bytes': packets[i],
        });
      }
      await engine.handleCommand(<String, Object?>{
        'cmd': 'rx',
        'bytes': Uint8List.fromList(<int>[0x7e, 0x01, 0x00, 0x7e]),
      });
      return logs;
    }

    test('a continuous run is not reported', () async {
      final List<String> logs = await run(await rxPackets(60), <int>{});
      expect(
        logs.where((String m) => m.startsWith('RX audio shortfall')),
        isEmpty,
      );
    });

    test(
      'complete but delayed delivery is not attributed to Bluetooth',
      () async {
        final logs = await run(
          await rxPackets(60),
          <int>{},
          deliveryDelayMs: 500,
        );
        expect(logs, contains(contains('RX audio shortfall: 476ms')));
        expect(logs, contains(contains('Packets=60')));
        expect(logs, contains(contains('SBC frames=360, samples=46080')));
        expect(logs, contains(contains('decodeErrors=0, rejectedBytes=0')));
        expect(
          logs,
          contains(contains('Arrival timing alone does not establish')),
        );
      },
    );

    test('decoder loss is distinguished from omitted packets', () async {
      final packets = await rxPackets(60);
      for (int i = 30; i < 50; i++) {
        packets[i][2] = 0; // Replace the first SBC sync byte.
      }
      final logs = await run(packets, <int>{});
      expect(logs, contains(contains('RX audio shortfall: 456ms')));
      expect(logs, contains(contains('Packets=60')));
      expect(logs, contains(contains('decodeErrors=20, rejectedBytes=5280')));
      expect(
        logs.where((m) => m.startsWith('SBC decode rejected')),
        hasLength(20),
      );
    });

    test('duration statistics use the SBC header sample rate', () async {
      final frame = SbcFrame()
        ..frequency = SbcFrequency.freq16K
        ..blocks = 16
        ..subbands = 8
        ..mode = SbcMode.mono
        ..bitpool = 18;
      final sbc = SbcEncoder().encode(Int16List(128), null, frame);
      expect(sbc, isNotNull);
      final packet = <int>[0x7e, 0x03];
      for (final byte in sbc!) {
        if (byte == 0x7e || byte == 0x7d) {
          packet.addAll(<int>[0x7d, byte ^ 0x20]);
        } else {
          packet.add(byte);
        }
      }
      packet.add(0x7e);
      final logs = await run(
        List<Uint8List>.filled(70, Uint8List.fromList(packet)),
        <int>{},
        packetMs: 8,
      );
      expect(logs, isEmpty);
    });

    test('starting TX ends a receive run without an end marker', () async {
      final packet = (await rxPackets(1)).single;
      final tx = _Tx();
      await tx.engine.handleCommand(<String, Object?>{
        'cmd': 'rx',
        'bytes': packet,
      });
      tx.events.clear();
      await tx.send(Uint8List(6 * 256));
      expect(
        tx.events
            .where((e) => e['evt'] == 'audioStart')
            .map((e) => e['transmit']),
        <bool>[true],
      );
      expect(
        tx.events
            .where((e) => e['evt'] == 'audioEnd')
            .map((e) => e['transmit']),
        <bool>[false, true],
      );
    });

    test('invalid received SBC payload is reported explicitly', () async {
      final logs = <String>[];
      final engine = AudioEngine((event) {
        if (event['evt'] == 'log') logs.add(event['msg']! as String);
      });
      await engine.handleCommand(<String, Object?>{
        'cmd': 'rx',
        'bytes': Uint8List.fromList(<int>[0x7e, 0x03, 0x00, 0x7e]),
      });
      expect(logs, contains(contains('SBC decode rejected')));
    });

    test(
      'received audio resumes after a late transmit echo without an end marker',
      () async {
        final packets = await rxPackets(2);
        final echo = Uint8List.fromList(packets.first)..[1] = 0x09;
        final events = <Map<String, Object?>>[];
        final engine = AudioEngine(events.add);
        await engine.handleCommand(<String, Object?>{
          'cmd': 'rx',
          'bytes': echo,
        });
        events.clear();
        await engine.handleCommand(<String, Object?>{
          'cmd': 'rx',
          'bytes': packets.last,
        });
        expect(
          events.where((e) => e['evt'] == 'audioEnd').map((e) => e['transmit']),
          <bool>[true],
        );
        expect(
          events.where(
            (e) => e['evt'] == 'audioData' && e['transmit'] == false,
          ),
          isNotEmpty,
        );
      },
    );

    test(
      'received audio stays suppressed while local transmission is pending',
      () async {
        final packet = (await rxPackets(1)).single;
        final release = Completer<void>();
        final done = Completer<void>();
        final events = <Map<String, Object?>>[];
        final engine = AudioEngine(
          (event) {
            events.add(event);
            if (event['evt'] == 'txState' && event['transmitting'] == false) {
              done.complete();
            }
          },
          btSend: (packet) async {
            if (packet[1] == 0) await release.future;
          },
        );
        final pcm = Uint8List(6 * 256);
        engine.transmitVoice(pcm, 0, pcm.length, false);
        try {
          events.clear();
          await engine.handleCommand(<String, Object?>{
            'cmd': 'rx',
            'bytes': packet,
          });
          expect(
            events.where(
              (e) => e['evt'] == 'audioData' && e['transmit'] == false,
            ),
            isEmpty,
          );
          expect(events.where((e) => e['evt'] == 'audioEnd'), isEmpty);
        } finally {
          release.complete();
          await done.future.timeout(const Duration(seconds: 5));
        }
      },
    );

    for (final bool transmitting in <bool>[false, true]) {
      test('opposite-direction audio does not strand the end marker '
          'during ${transmitting ? "TX" : "RX"}', () async {
        final packets = await rxPackets(2);
        final echo = Uint8List.fromList(packets.first)..[1] = 0x09;
        final events = <Map<String, Object?>>[];
        final engine = AudioEngine(events.add);
        await engine.handleCommand(<String, Object?>{
          'cmd': 'rx',
          'bytes': transmitting ? echo : packets.first,
        });
        events.clear();
        await engine.handleCommand(<String, Object?>{
          'cmd': 'rx',
          'bytes': Uint8List.fromList(<int>[
            ...(transmitting ? packets.first : echo),
            0x7e,
            0x01,
            0x00,
            0x7e,
            ...packets.last,
          ]),
        });
        expect(
          events.where((e) => e['evt'] == 'audioEnd').map((e) => e['transmit']),
          transmitting ? <bool>[true, false] : <bool>[false],
        );
        expect(
          events.where(
            (e) => e['evt'] == 'audioData' && e['transmit'] == false,
          ),
          isNotEmpty,
        );
      });
    }

    test('packets dropped upstream are reported with the stall', () async {
      // 20 consecutive packets (480 ms) never arrive, as during a link stall.
      final List<String> logs = await run(
        await rxPackets(60),
        Set<int>.of(List<int>.generate(20, (int i) => 30 + i)),
      );
      expect(
        logs,
        contains(
          'RX audio shortfall: 456ms over 1416ms of packet arrivals '
          '(decoded 960ms); longest gap 504ms at 696ms into the run. '
          'Packets=40, payloadBytes=10560, SBC frames=240, samples=30720, '
          'decodeErrors=0, rejectedBytes=0, formats=32000Hz/mono/bitpool=18. '
          'Arrival timing alone does not establish radio/Bluetooth packet loss.',
        ),
      );
    });
  });

  test('failed stop writes still release transmit state', () async {
    final Completer<void> done = Completer<void>();
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    final AudioEngine engine = AudioEngine(
      (event) {
        events.add(event);
        if (event['evt'] == 'txState' && event['transmitting'] == false) {
          done.complete();
        }
      },
      btSend: (packet) async {
        if (packet[1] != 0) throw StateError('stop rejected');
      },
    );
    final Uint8List pcm = Uint8List(256);
    engine.transmitVoice(pcm, 0, pcm.length, false);
    await done.future.timeout(const Duration(seconds: 5));
    expect(
      events.where((e) => e['evt'] == 'log').map((e) => e['msg']),
      contains(contains('Voice transmit stop error: Bad state: stop rejected')),
    );
  });

  for (final FmBandwidth bandwidth in FmBandwidth.values) {
    test(
      'XARA ${bandwidth.name} frame survives the stock SBC transmit path',
      () async {
        final FmRecord record = FmRecord.fromIndex(1)!;
        final Uint8List frame = buildData(
          record,
          bandwidth.level(record).frameBytes,
          Uint8List.fromList('Bluetooth continuity test'.codeUnits),
          false,
          3,
          false,
          const Trailer(leadReport: 0),
        );
        final Modulator modulator = Modulator(bandwidth);
        final math.Random rng = math.Random(42);
        final List<double> audio = <double>[
          ...List<double>.filled(12000, 0),
          ...modulator.transmission(
            record,
            3,
            <Uint8List>[frame],
            20,
            const TxOptions(driveDb: -5),
            rng.nextInt,
          ),
          ...List<double>.filled(12000, 0),
        ];
        final Resampler down = Resampler(48000, 32000);
        final _Tx tx = _Tx();
        final Uint8List pcm = _pcm(<double>[
          ...down.process(audio),
          ...down.flush(),
        ]);
        await tx.send(pcm);
        final List<double> compressed = tx
            .decode(SbcBitAllocationMethod.snr)
            .map((int n) => n / 32768.0)
            .toList();
        final Resampler up = Resampler(32000, 48000);
        final List<double> received = <double>[
          ...up.process(compressed),
          ...up.flush(),
        ];
        final FmReceiver receiver = FmReceiver(bandwidth, 3, <FmRecord>[
          record,
        ], 1);
        final List<Uint8List> frames = <Uint8List>[];
        for (int i = 0; i < received.length; i += 480) {
          for (final FmEvent event in receiver.feed(
            received.sublist(i, math.min(i + 480, received.length)),
          )) {
            if (event is FrameEv<FmCtrlEvent, FmRecord, FmFrameRx> &&
                event.frame.ok) {
              frames.add(event.frame.bytes);
            }
          }
        }
        expect(frames, <Uint8List>[frame]);
      },
    );
  }
}
