/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math';
import 'dart:convert';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_conversation.dart';
import '../aprs/aprs_observation.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/packet_data_type.dart';
import '../aprsis/tnc2_codec.dart';
import '../radio/ax25_packet.dart';
import '../radio/tnc_data_fragment.dart';
import '../radio/utils.dart';
import '../services/aprs_observation_store.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';

class AprsObservationHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  final AprsObservationStore _store;
  final DateTime Function() _clock;
  final String _session = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0xFFFFFFFF)}';
  final List<AprsObservation> _records = [];
  final Map<String, AprsObservation> _recent = {};
  Future<void> _work = Future.value();
  int _sequence = 0;
  bool _disposed = false;
  bool _archiveLoaded = false;

  AprsObservationHandler({AprsObservationStore? store, DateTime Function()? clock})
      : _store = store ?? AprsObservationStore(), _clock = clock ?? DateTime.now;

  Future<void> get ready async {
    while (true) {
      final work = _work;
      await work;
      if (identical(work, _work)) return;
    }
  }

  void init() {
    if (HostBridge.isHosted) return;
    _broker.subscribe(deviceId: DataBroker.allDevices, name: 'DataFrame', callback: _onDataFrame);
    _broker.subscribe(deviceId: 1, name: 'AprsFrame', callback: _onAprsFrame);
    _broker.subscribe(deviceId: 1, name: 'RequestAprsObservations', callback: _onRequest);
    _enqueue(() async {
      final restored = await _store.load();
      if (_disposed) return;
      _archiveLoaded = true;
      final all = [...restored, ..._records];
      _records..clear()..addAll(all.skip(max(0, all.length - AprsObservation.capacity)));
      _publish();
    });
  }

  void _enqueue(Future<void> Function() action) {
    _work = _work.then((_) async {
      try {
        await action();
      } catch (error) {
        _broker.logError('[APRS observations] $error');
        if (!_disposed) {
          _broker.dispatch(deviceId: 1, name: 'AprsObservationError',
            data: {'detail': error.toString()}, store: true);
        }
      }
    });
  }

  void _onRequest(int deviceId, String name, Object? data) => _publish();

  void _publish() {
    if (!_disposed) {
      _broker.dispatch(deviceId: 1, name: 'AprsObservations',
        data: _records.map((o) => o.toJson()).toList(), store: true);
    }
  }

  void _onDataFrame(int deviceId, String name, Object? data) {
    if (_disposed || data is! TncDataFragment || !data.incoming || data.historical ||
        data.frameType == FragmentFrameType.xara) {
      return;
    }
    AX25Packet? packet;
    AprsPacket? aprs;
    try {
      packet = AX25Packet.decode(data);
      if (packet != null && packet.type == FrameType.uFrameUi && packet.pid == AX25Defs.pidNone) {
        aprs = AprsPacket.parse(packet);
      }
    } on RangeError catch (error) {
      _broker.logError('[APRS observations] Malformed frame: $error');
    }
    if ((aprs == null || aprs.dataType == PacketDataType.unknown) &&
        data.channelName != 'APRS' && data.usage != 'APRSSat') {
      return;
    }
    final path = packet == null ? <AprsObservedHop>[] :
      packet.addresses.skip(2).map((a) => AprsObservedHop(aprsPeerKey(a.callSignWithId), a.crBit1)).toList();
    final kind = data.encoding == FragmentEncodingType.loopback ? AprsReceiveKind.loopback :
      aprs == null || aprs.dataType == PacketDataType.unknown || aprs.dataType == PacketDataType.invalidOrTestData
        ? AprsReceiveKind.invalid :
      aprs.thirdPartyHeader != null ? AprsReceiveKind.thirdParty :
      aprs.hasInternetPath ? AprsReceiveKind.internet :
      path.any((h) => h.used) ? AprsReceiveKind.digipeatedRf : AprsReceiveKind.directRf;
    _capture(deviceId: data.radioDeviceId ?? deviceId, fragment: data, packet: packet,
      aprs: aprs, kind: kind, path: path, live: true);
  }

  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (_disposed || data is! AprsFrameEventArgs || !data.aprsPacket.fromAprsIs ||
        !data.ax25Packet.incoming) {
      return;
    }
    _capture(deviceId: null, fragment: null, packet: data.ax25Packet, aprs: data.aprsPacket,
      kind: AprsReceiveKind.internet,
      path: data.ax25Packet.addresses.skip(2)
        .map((a) => AprsObservedHop(aprsPeerKey(a.callSignWithId), a.crBit1)).toList(),
      live: !data.historical);
  }

  void _capture({required int? deviceId, required TncDataFragment? fragment,
      required AX25Packet? packet, required AprsPacket? aprs, required AprsReceiveKind kind,
      required List<AprsObservedHop> path, required bool live}) {
    final now = _clock().toUtc();
    final tnc2 = fragment == null ? Tnc2Codec.encode(packet!) : null;
    if (fragment == null && tnc2 == null) {
      _broker.logError('[APRS observations] Invalid internet frame');
      return;
    }
    final hex = RadioUtils.bytesToHex(fragment?.data ?? utf8.encode(tnc2!));
    final decoder = fragment?.encoding.name ?? 'aprsIs';
    final key = '${fragment?.radioMac ?? deviceId}/${fragment?.channelId ?? -1}/${fragment?.regionId ?? -1}/$hex';
    _recent.removeWhere((_, o) => now.isBefore(o.observed) ||
      now.difference(o.observed) >= const Duration(seconds: 3));
    final previous = live ? _recent[key] : null;
    final record = AprsObservation(
      id: '$_session-${_sequence++}', observed: now,
      received: fragment?.time ?? packet!.time, radioDeviceId: deviceId,
      radioMac: fragment?.radioMac, channel: fragment?.channelId ?? -1, region: fragment?.regionId ?? -1,
      channelName: fragment?.channelName ?? 'APRS-IS', decoder: decoder,
      frameType: fragment?.frameType.name ?? 'tnc2', corrections: fragment?.corrections ?? -1,
      dataHex: hex, information: packet?.dataStr ?? '', source: aprs == null ? null : aprsPeerKey(aprs.sourceCallsignWithId),
      frameSource: packet != null && packet.addresses.length >= 2 ? aprsPeerKey(packet.addresses[1].callSignWithId) : null,
      destination: packet != null && packet.addresses.isNotEmpty ? aprsPeerKey(packet.addresses[0].callSignWithId) : null,
      addressee: aprs?.dataType == PacketDataType.message ? aprsPeerKey(aprs!.messageData.addressee) : null,
      path: path, kind: kind, live: live, duplicateOf: previous?.id,
      duplicate: previous == null ? AprsDecodeDuplicate.none :
        previous.decoder == decoder ? AprsDecodeDuplicate.sameDecoder : AprsDecodeDuplicate.otherDecoder,
    );
    if (live && previous == null) {
      _recent[key] = record;
      if (_recent.length > AprsObservation.capacity) _recent.remove(_recent.keys.first);
    }
    _records.add(record);
    if (_records.length > AprsObservation.capacity) _records.removeAt(0);
    _publish();
    // Live consumers must not wait for a disk write, and restored records never
    // travel through this event or the packet/ACK/gating receive pipeline.
    if (live) _broker.dispatch(deviceId: 1, name: 'AprsObservation', data: record, store: false);
    _enqueue(() async {
      await _store.save(record);
      if (_disposed) return;
      final index = _records.indexWhere((o) => o.id == record.id);
      if (index >= 0) _records[index] = record.withStatus(live: live, persisted: true);
      if (_archiveLoaded && _records.every((o) => o.persisted)) {
        _broker.dispatch(deviceId: 1, name: 'AprsObservationError', data: null, store: true);
      }
      _publish();
    });
  }

  void dispose() {
    _disposed = true;
    _recent.clear();
    _broker.dispose();
  }
}
