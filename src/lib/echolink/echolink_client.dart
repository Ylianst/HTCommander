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
// echolink_client.dart - EchoLink internet radio for Data Broker device 200.
//
// Orchestrates the directory (login + station list), a single peer QSO (RTCP
// handshake, keep-alive/timeout, GSM voice), and publishes status onto the
// Data Broker at device 200. Networking and timers are injected so the logic is
// unit-testable without real sockets.
//

import 'dart:async';
import 'dart:typed_data';

import '../services/data_broker.dart';
import 'echolink_audio.dart';
import 'echolink_data_packet.dart';
import 'echolink_directory.dart';
import 'echolink_network.dart';
import 'echolink_qso.dart';
import 'echolink_station.dart';
import 'rtcp_packet.dart';

/// Data Broker device id for the internet-only EchoLink radio.
const int echoLinkDeviceId = 200;

/// High-level state of the EchoLink client.
enum EchoLinkClientState { offline, online, connecting, inQso }

/// Cancels a scheduled timer.
typedef CancelTimer = void Function();

/// Timer source, injectable for testing.
abstract class Scheduler {
  CancelTimer periodic(Duration d, void Function() cb);
  CancelTimer oneShot(Duration d, void Function() cb);
}

/// Default [Scheduler] backed by dart:async [Timer].
class RealScheduler implements Scheduler {
  @override
  CancelTimer periodic(Duration d, void Function() cb) {
    final Timer t = Timer.periodic(d, (_) => cb());
    return t.cancel;
  }

  @override
  CancelTimer oneShot(Duration d, void Function() cb) {
    final Timer t = Timer(d, cb);
    return t.cancel;
  }
}

class EchoLinkClient {
  final String localCallsign;
  final String localPassword;
  final String localName;
  final String localInfo;
  final List<String> directoryServers;

  final EchoLinkNetwork network;
  final Scheduler scheduler;

  /// Fired with 640 samples (8 kHz) of decoded received audio.
  void Function(Int16List pcm8k)? onAudio;

  /// Fired with received chat messages.
  void Function(EchoLinkChat chat)? onChat;

  /// Fired with received station-info messages.
  void Function(String info)? onInfo;

  /// Fired when the client state changes.
  void Function(EchoLinkClientState state)? onStateChanged;

  /// Fired with the latest station list after [refreshStations].
  void Function(DirectoryListing listing)? onStations;

  EchoLinkClientState _state = EchoLinkClientState.offline;
  EchoLinkQso? _qso;
  StationData? _remoteStation;
  String? _remoteHost;
  CancelTimer? _keepAlive;
  CancelTimer? _timeout;
  bool _opened = false;
  bool _online = false;

  final List<int> _txBuffer = <int>[];

  StreamSubscription<EchoLinkDatagram>? _audioSub;
  StreamSubscription<EchoLinkDatagram>? _controlSub;

  EchoLinkClient({
    required this.localCallsign,
    this.localPassword = '',
    this.localName = '',
    this.localInfo = '',
    List<String>? directoryServers,
    required this.network,
    Scheduler? scheduler,
  })  : directoryServers = directoryServers ?? defaultDirectoryServers,
        scheduler = scheduler ?? RealScheduler();

  EchoLinkClientState get state => _state;
  StationData? get connectedStation => _remoteStation;

  void _setState(EchoLinkClientState s) {
    final bool changed = _state != s;
    _state = s;
    DataBroker.dispatch(
        deviceId: echoLinkDeviceId, name: 'State', data: _stateLabel(s));
    DataBroker.dispatch(
        deviceId: echoLinkDeviceId, name: 'ClientState', data: s.name);
    if (changed) onStateChanged?.call(s);
  }

  static String _stateLabel(EchoLinkClientState s) {
    switch (s) {
      case EchoLinkClientState.offline:
        return 'Disconnected';
      case EchoLinkClientState.online:
        return 'Online';
      case EchoLinkClientState.connecting:
        return 'Connecting';
      case EchoLinkClientState.inQso:
        return 'Connected';
    }
  }

  /// Opens the UDP sockets, wires packet routing and registers device 200.
  Future<void> open() async {
    if (_opened) return;
    await network.open();
    _audioSub = network.audioIn.listen(_onAudioDatagram);
    _controlSub = network.controlIn.listen(_onControlDatagram);
    _opened = true;

    DataBroker.dispatch(
        deviceId: echoLinkDeviceId, name: 'FriendlyName', data: 'EchoLink');
    _setState(EchoLinkClientState.offline);
  }

  /// Registers presence with the directory server (status ONLINE).
  Future<void> goOnline({DirectoryStatus status = DirectoryStatus.online}) async {
    final Uint8List cmd = buildLoginCommand(
      callsign: localCallsign,
      password: localPassword,
      description: localInfo,
      status: status,
      timeHHmm: _localHHmm(),
    );
    await network.directoryExchange(directoryServers, cmd);
    if (status == DirectoryStatus.offline) {
      _online = false;
      if (_qso == null) _setState(EchoLinkClientState.offline);
      return;
    }
    _online = true;
    if (_state == EchoLinkClientState.offline) {
      _setState(EchoLinkClientState.online);
    }
  }

  /// Fetches and publishes the current station list.
  Future<DirectoryListing> refreshStations() async {
    final Uint8List resp =
        await network.directoryExchange(directoryServers, buildListRequest());
    final DirectoryListing listing = parseStationList(resp);
    DataBroker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'StationList',
      data: listing.all.map(_stationMap).toList(),
    );
    onStations?.call(listing);
    return listing;
  }

  /// Opens a QSO to [station] (which must have a resolved [StationData.ip]).
  void connectTo(StationData station) {
    if (_qso != null) return;
    _remoteStation = station;
    _remoteHost = station.ip;

    final EchoLinkQso qso = EchoLinkQso(
      localCallsign: localCallsign,
      localName: localName,
      localInfo: localInfo,
      sendControl: (Uint8List p) => network.sendControl(_remoteHost!, p),
      sendAudio: (Uint8List p) => network.sendAudio(_remoteHost!, p),
    )
      ..onStateChanged = _onQsoState
      ..onKeepAlive = _resetTimeout
      ..onAudio = (Int16List pcm) {
        onAudio?.call(pcm);
      }
      ..onChat = (EchoLinkChat c) {
        onChat?.call(c);
      }
      ..onInfo = (String s) {
        onInfo?.call(s);
      }
      ..onRemoteStation = _onRemoteStation;
    _qso = qso;

    _txBuffer.clear();
    _setState(EchoLinkClientState.connecting);
    qso.connect();

    _keepAlive = scheduler.periodic(
        const Duration(milliseconds: EchoLinkQso.keepAliveMs),
        () => _qso?.onKeepAliveTick());
    _resetTimeout();
  }

  /// Tears down the active QSO.
  void disconnect() {
    _qso?.disconnect();
    _endConnection();
  }

  /// Sends chat text over the active QSO.
  void sendChat(String msg) => _qso?.sendChat(msg);

  /// Sends station-info text over the active QSO.
  void sendInfo([String? info]) => _qso?.sendInfo(info);

  /// Queues 8 kHz mono PCM for transmission, emitting 640-sample voice packets.
  void sendAudio(Int16List pcm8k) {
    final EchoLinkQso? qso = _qso;
    if (qso == null || _state != EchoLinkClientState.inQso) return;
    _txBuffer.addAll(pcm8k);
    const int block = EchoLinkAudioEncoder.samplesPerPacket; // 640
    int off = 0;
    while (_txBuffer.length - off >= block) {
      qso.sendAudioFrame(Int16List.fromList(_txBuffer.sublist(off, off + block)));
      off += block;
    }
    if (off > 0) _txBuffer.removeRange(0, off);
  }

  /// Closes sockets and releases resources.
  Future<void> close() async {
    disconnect();
    await _audioSub?.cancel();
    await _controlSub?.cancel();
    await network.close();
    _opened = false;
    _online = false;
  }

  // ---- internals ----------------------------------------------------------

  void _onAudioDatagram(EchoLinkDatagram dg) {
    if (_qso == null || dg.host != _remoteHost) return;
    _qso!.handleAudioPacket(dg.data);
  }

  void _onControlDatagram(EchoLinkDatagram dg) {
    if (_qso == null || dg.host != _remoteHost) return;
    _qso!.handleControlPacket(dg.data);
  }

  void _onQsoState(QsoState s) {
    switch (s) {
      case QsoState.connected:
        _setState(EchoLinkClientState.inQso);
        DataBroker.dispatch(
          deviceId: echoLinkDeviceId,
          name: 'ConnectedStation',
          data: _remoteStation == null ? null : _stationMap(_remoteStation!),
        );
        break;
      case QsoState.disconnected:
        _endConnection();
        break;
      case QsoState.connecting:
      case QsoState.byeReceived:
        break;
    }
  }

  void _onRemoteStation(SdesStation st) {
    final StationData? cur = _remoteStation;
    _remoteStation = StationData(
      callsign: st.callsign,
      description: st.name,
      ip: cur?.ip ?? _remoteHost ?? '',
      id: cur?.id ?? 0,
      status: cur?.status ?? StationStatus.online,
    );
  }

  void _endConnection() {
    _keepAlive?.call();
    _timeout?.call();
    _keepAlive = null;
    _timeout = null;
    _qso = null;
    _remoteHost = null;
    _remoteStation = null;
    _txBuffer.clear();
    DataBroker.dispatch(
        deviceId: echoLinkDeviceId, name: 'ConnectedStation', data: null);
    _setState(_online ? EchoLinkClientState.online : EchoLinkClientState.offline);
  }

  void _resetTimeout() {
    _timeout?.call();
    _timeout = scheduler.oneShot(
      const Duration(milliseconds: EchoLinkQso.connectionTimeoutMs),
      () {
        _qso?.onConnectionTimeout();
        _endConnection();
      },
    );
  }

  Map<String, Object?> _stationMap(StationData s) => <String, Object?>{
        'Callsign': s.callsign,
        'Description': s.description,
        'Status': s.status.name,
        'Time': s.time,
        'Id': s.id,
        'Ip': s.ip,
      };

  String _localHHmm() {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}';
  }
}
