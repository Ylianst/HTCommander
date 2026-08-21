/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/radio_models.dart';
import '../radio/radio_transport.dart';
import '../winlink/winlink_mail.dart';
import 'bluetooth_service.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';

/// Bridges the app's radio state to the native Android Auto car UI.
///
/// The Android Auto surface is drawn by a native `CarAppService` (Kotlin) that
/// cannot see the Dart isolate directly, so this class mirrors a small,
/// car-safe slice of state over the `com.htcommander/android_auto`
/// [MethodChannel]:
///   - the preferred radio's current region, VFO A / VFO B channels, scan and
///     dual-watch state, plus the region and channel lists used by the pickers,
///   - a merged list of recent messages addressed to our station (APRS and
///     other on-air chat via the comms history, plus Winlink Inbox mail).
///
/// State flows Dart -> native via `updateState`. The car requests changes back
/// via `setChannel` (VFO A/B), `setRegion`, `setScan` and `setDualWatch`. Only
/// active on Android; a no-op elsewhere.
class AndroidAutoBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.htcommander/android_auto',
  );

  /// Broker device id the decoded-text history is published under (device 1,
  /// see [CommsHandler]).
  static const int _commsDeviceId = 1;

  /// Maximum number of messages mirrored to the car screen.
  static const int _maxMessages = 25;

  final DataBrokerClient _broker = DataBrokerClient();
  final BluetoothService _bluetoothService = BluetoothService();

  bool _active = false;
  int _preferredRadioId = -1;
  bool _scanningRadios = false;
  String _connectingRadioId = '';
  String _radioConnectionErrorId = '';
  List<DiscoveredDevice> _availableRadios = const [];

  /// Whether a car (Android Auto) session is currently projecting. Incoming
  /// messages are only read aloud while this is true.
  bool _carConnected = false;

  /// Last region index pushed to the car, used to suppress the continuous
  /// (RSSI-carrying) `HtStatus` updates that don't change the region.
  int _lastPushedRegion = -1000;

  /// Lazily created text-to-speech engine used to read incoming messages aloud
  /// through the car speaker. Null until the first message is spoken.
  FlutterTts? _tts;

  /// On-air chat messages addressed to us, derived from the comms history.
  List<Map<String, Object?>> _textMessages = const [];

  /// Winlink Inbox mail addressed to us.
  List<Map<String, Object?>> _mailMessages = const [];

  /// Initializes the bridge. Safe to call on every platform; only wires up the
  /// native channel and broker subscriptions on Android.
  void init() {
    if (kIsWeb || !Platform.isAndroid) return;
    _active = true;

    _channel.setMethodCallHandler(_onNativeCall);

    _preferredRadioId =
        DataBroker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;

    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onPreferredRadioChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Channels',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Settings',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Info',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'RegionNames',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'HtStatus',
      callback: _onHtStatusChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'FriendlyName',
      callback: _onRadioStateChanged,
    );

    // On-air chat messages (APRS + other) directed to us, from the unified
    // comms history. The full snapshot is re-dispatched after every new entry.
    _broker.subscribe(
      deviceId: _commsDeviceId,
      name: 'DecodedTextHistory',
      callback: _onDecodedTextHistory,
    );
    // Real-time single entry, used only to read a new message aloud.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TextReady',
      callback: _onTextReady,
    );

    // Winlink Inbox mail addressed to us.
    _broker.subscribe(
      deviceId: 0,
      name: 'MailsChanged',
      callback: _onMailsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MailStoreReady',
      callback: _onMailsChanged,
    );
    _broker.subscribe(deviceId: 0, name: 'MailList', callback: _onMailList);

    // The broker does not replay stored values to new subscribers, so seed the
    // message list from what is already stored, then ask for the mail list.
    final history = _broker.getValueDynamic(
      _commsDeviceId,
      'DecodedTextHistory',
    );
    if (history is List) _rebuildTextMessages(history);
    _requestMailList();

    _pushState();
  }

  void dispose() {
    if (!_active) return;
    _broker.dispose();
    _channel.setMethodCallHandler(null);
    _tts?.stop();
    _active = false;
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'getState':
        return _buildState();
      case 'carConnected':
        _carConnected = call.arguments as bool? ?? false;
        if (_carConnected && _preferredRadioId <= 0) {
          await _refreshAvailableRadios();
        } else if (!_carConnected) {
          _tts?.stop();
        }
        return null;
      case 'refreshRadios':
        await _refreshAvailableRadios();
        return null;
      case 'connectRadio':
        final args = call.arguments;
        if (args is Map) {
          final radioId = args['id'] as String? ?? '';
          await _connectRadio(radioId);
        }
        return null;
      case 'setChannel':
        final args = call.arguments;
        if (args is Map && _preferredRadioId > 0) {
          final channelId = (args['channelId'] as num?)?.toInt();
          final vfo = args['vfo'] as String? ?? 'A';
          if (channelId != null) {
            _broker.dispatch(
              deviceId: _preferredRadioId,
              name: vfo == 'B' ? 'ChannelChangeVfoB' : 'ChannelChangeVfoA',
              data: channelId,
              store: false,
            );
          }
        }
        return null;
      case 'setRegion':
        final index = (call.arguments as num?)?.toInt();
        if (index != null && _preferredRadioId > 0) {
          _broker.dispatch(
            deviceId: _preferredRadioId,
            name: 'Region',
            data: index,
            store: false,
          );
        }
        return null;
      case 'setScan':
        final scanOn = call.arguments as bool?;
        if (scanOn != null && _preferredRadioId > 0) {
          _broker.dispatch(
            deviceId: _preferredRadioId,
            name: 'Scan',
            data: scanOn,
            store: false,
          );
        }
        return null;
      case 'setDualWatch':
        final dualOn = call.arguments as bool?;
        if (dualOn != null && _preferredRadioId > 0) {
          _broker.dispatch(
            deviceId: _preferredRadioId,
            name: 'DualWatch',
            data: dualOn,
            store: false,
          );
        }
        return null;
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  void _onPreferredRadioChanged(int deviceId, String name, Object? data) {
    final wasConnected = _preferredRadioId > 0;
    if (data is int) _preferredRadioId = data;
    _lastPushedRegion = -1000;
    _pushState();
    if (wasConnected && _preferredRadioId <= 0 && _carConnected) {
      unawaited(_refreshAvailableRadios());
    }
  }

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    _pushState();
  }

  Future<void> _refreshAvailableRadios() async {
    if (_scanningRadios || _connectingRadioId.isNotEmpty) return;
    _scanningRadios = true;
    _radioConnectionErrorId = '';
    _pushState();
    try {
      final bluetoothAvailable = await BluetoothService.checkBluetooth();
      if (!bluetoothAvailable) {
        _availableRadios = const [];
        return;
      }
      final radios = await _bluetoothService.findCompatibleDevices(
        timeout: const Duration(seconds: 5),
      );
      _availableRadios = radios
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (error) {
      debugPrint('AndroidAutoBridge: radio scan failed: $error');
      _availableRadios = const [];
    } finally {
      _scanningRadios = false;
      _pushState();
    }
  }

  Future<void> _connectRadio(String radioId) async {
    if (radioId.isEmpty || _connectingRadioId.isNotEmpty) return;
    DiscoveredDevice? selected;
    for (final radio in _availableRadios) {
      if (radio.id.toUpperCase() == radioId.toUpperCase()) {
        selected = radio;
        break;
      }
    }
    if (selected == null) return;

    _connectingRadioId = selected.id;
    _radioConnectionErrorId = '';
    _pushState();
    try {
      final deviceId = await _bluetoothService.connectToRadio(
        selected.id,
        _friendlyName(selected),
      );
      if (deviceId == null) {
        _radioConnectionErrorId = selected.id;
        return;
      }
      _preferredRadioId = deviceId;
      _broker.dispatch(
        deviceId: 1,
        name: 'SelectedRadioDeviceId',
        data: deviceId,
      );
    } catch (error) {
      debugPrint('AndroidAutoBridge: radio connection failed: $error');
      _radioConnectionErrorId = selected.id;
    } finally {
      _connectingRadioId = '';
      _pushState();
    }
  }

  String _friendlyName(DiscoveredDevice radio) {
    final customNames = DataBroker.getValue<Map<String, dynamic>>(
      0,
      'DeviceFriendlyName',
    );
    if (customNames == null) return radio.name;
    final upperId = radio.id.toUpperCase();
    final compactId = upperId.replaceAll(':', '').replaceAll('-', '');
    return customNames[compactId] as String? ??
        customNames[upperId] as String? ??
        radio.name;
  }

  /// `HtStatus` updates arrive continuously (RSSI etc.). Only push when the
  /// current region actually changes so the car screen doesn't churn.
  void _onHtStatusChanged(int deviceId, String name, Object? data) {
    if (_preferredRadioId > 0 && deviceId != _preferredRadioId) return;
    final region = _currRegion();
    if (region == _lastPushedRegion) return;
    _lastPushedRegion = region;
    _pushState();
  }

  // ---------------------------------------------------------------------------
  // Messages (on-air chat + Winlink mail) addressed to us
  // ---------------------------------------------------------------------------

  void _onDecodedTextHistory(int deviceId, String name, Object? data) {
    if (data is! List) return;
    _rebuildTextMessages(data);
    _pushState();
  }

  /// Rebuilds [_textMessages] from a full decoded-text history snapshot, keeping
  /// only received text messages directed to our station.
  void _rebuildTextMessages(List<dynamic> history) {
    final out = <Map<String, Object?>>[];
    for (final item in history) {
      if (item is! Map) continue;
      final isReceived = item['isReceived'] as bool? ?? true;
      if (!isReceived) continue;
      final text = (item['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      if (!_isDirectedToUs(item['destination'] as String?)) continue;
      final encoding = item['encoding'] as String? ?? '';
      final time = item['time'];
      out.add({
        'kind': encoding == 'APRS' ? 'APRS' : 'Comm',
        'from': (item['source'] as String?)?.trim() ?? '',
        'text': text,
        'time': time is int ? time : DateTime.now().millisecondsSinceEpoch,
      });
    }
    _textMessages = out;
  }

  /// Reads a newly arrived directed message aloud (car only). The list itself
  /// is built from [_onDecodedTextHistory]; this only handles the announcement.
  void _onTextReady(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final completed = data['completed'];
    if (completed is bool && !completed) return;
    final isReceived = data['isReceived'] as bool? ?? true;
    if (!isReceived) return;
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return;
    if (!_isDirectedToUs(data['destination'] as String?)) return;
    if (_carConnected) {
      _speakMessage((data['source'] as String?)?.trim() ?? '', text);
    }
  }

  void _onMailsChanged(int deviceId, String name, Object? data) {
    _requestMailList();
  }

  void _requestMailList() {
    if (!_active) return;
    _broker.dispatch(deviceId: 0, name: 'MailGetAll', data: null, store: false);
  }

  void _onMailList(int deviceId, String name, Object? data) {
    if (data is! List) return;
    final out = <Map<String, Object?>>[];
    for (final item in data) {
      if (item is! WinLinkMail) continue;
      if (item.mailbox != 'Inbox') continue;
      final subject = item.subject?.trim() ?? '';
      out.add({
        'kind': 'Mail',
        'from': item.from?.trim() ?? '',
        'text': subject.isNotEmpty ? subject : '(no subject)',
        'time': item.dateTime.millisecondsSinceEpoch,
      });
    }
    _mailMessages = out;
    _pushState();
  }

  /// Returns true when [destination] is addressed to our station. Mirrors the
  /// "for us" filter used by [CommsHandler] for incoming-message notifications.
  bool _isDirectedToUs(String? destination) {
    final dest = destination?.trim() ?? '';
    if (dest.isEmpty) return false;
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    if (callsign.isEmpty) return false;
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final full = stationId == 0 ? callsign : '$callsign-$stationId';
    final destLower = dest.toLowerCase();
    final destBase = destLower.split('-').first;
    final callBase = callsign.toLowerCase().split('-').first;
    return destLower == full.toLowerCase() ||
        destLower == callsign.toLowerCase() ||
        destBase == callBase;
  }

  /// Reads an incoming message aloud through the car speaker. Announces the
  /// sender (when known) followed by the message text; queues rather than
  /// interrupts so back-to-back messages are all read.
  Future<void> _speakMessage(String from, String text) async {
    if (text.isEmpty) return;
    final spoken = from.isNotEmpty
        ? 'Message from $from. $text'
        : 'Message. $text';
    try {
      final tts = await _ensureTts();
      await tts.speak(spoken);
    } catch (e) {
      debugPrint('AndroidAutoBridge: TTS speak failed: $e');
    }
  }

  Future<FlutterTts> _ensureTts() async {
    final existing = _tts;
    if (existing != null) return existing;
    final tts = FlutterTts();
    await tts.setQueueMode(1); // 1 = QUEUE_ADD: don't drop earlier messages.
    _tts = tts;
    return tts;
  }

  // ---------------------------------------------------------------------------
  // Preferred-radio state reads
  // ---------------------------------------------------------------------------

  List<RadioChannelInfo> _channelsForPreferred() {
    if (_preferredRadioId <= 0) return const [];
    return _broker.getJsonListValue<RadioChannelInfo>(
          _preferredRadioId,
          'Channels',
          (json) => RadioChannelInfo.fromJson(json),
        ) ??
        const [];
  }

  RadioSettings? _settings() {
    if (_preferredRadioId <= 0) return null;
    return _broker.getJsonValue<RadioSettings>(
      _preferredRadioId,
      'Settings',
      (json) => RadioSettings.fromJson(json),
    );
  }

  int _regionCount() {
    if (_preferredRadioId <= 0) return 0;
    final info = _broker.getValueDynamic(_preferredRadioId, 'Info');
    if (info is RadioDevInfo) return info.regionCount;
    if (info is Map) return (info['regionCount'] as int?) ?? 0;
    return 0;
  }

  int _currRegion() {
    if (_preferredRadioId <= 0) return 0;
    final status = _broker.getValueDynamic(_preferredRadioId, 'HtStatus');
    if (status is RadioHtStatus) return status.currRegion;
    if (status is Map) return (status['currRegion'] as int?) ?? 0;
    return 0;
  }

  List<String?> _regionNames() {
    if (_preferredRadioId <= 0) return const [];
    final names = _broker.getValueDynamic(_preferredRadioId, 'RegionNames');
    if (names is List) {
      return names.map((e) => e is String ? e : null).toList();
    }
    return const [];
  }

  List<Map<String, Object?>> _regions() {
    final names = _regionNames();
    final count = _regionCount();
    final total = count > 0 ? count : names.length;
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < total; i++) {
      final n = i < names.length ? names[i] : null;
      out.add({
        'index': i,
        'name': (n != null && n.isNotEmpty) ? n : 'Region ${i + 1}',
      });
    }
    return out;
  }

  String _channelName(int id) {
    if (id < 0) return '';
    for (final c in _channelsForPreferred()) {
      if (c.channelId == id) {
        return c.name.isNotEmpty ? c.name : 'Channel ${id + 1}';
      }
    }
    return 'Channel ${id + 1}';
  }

  String _regionName() {
    final idx = _currRegion();
    final names = _regionNames();
    if (idx >= 0 && idx < names.length) {
      final n = names[idx];
      if (n != null && n.isNotEmpty) return n;
    }
    return 'Region ${idx + 1}';
  }

  String _radioName() {
    if (_preferredRadioId <= 0) return '';
    // The per-device `FriendlyName` is the live source of truth (updated when
    // the user renames the radio); fall back to the ConnectedRadios list.
    final name =
        _broker.getValue<String>(_preferredRadioId, 'FriendlyName', '') ?? '';
    if (name.isNotEmpty) return name;
    final radios = _broker.getJsonListValue<ConnectedRadioInfo>(
      1,
      'ConnectedRadios',
      (json) => ConnectedRadioInfo.fromJson(json),
    );
    for (final r in radios ?? const <ConnectedRadioInfo>[]) {
      if (r.deviceId == _preferredRadioId) return r.friendlyName;
    }
    return '';
  }

  Map<String, Object?> _buildState() {
    final settings = _settings();
    final vfoA = settings?.channelA ?? -1;
    final vfoB = settings?.channelB ?? -1;
    final merged = <Map<String, Object?>>[..._textMessages, ..._mailMessages]
      ..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
    return {
      'connected': _preferredRadioId > 0,
      'scanningRadios': _scanningRadios,
      'connectingRadioId': _connectingRadioId,
      'radioConnectionErrorId': _radioConnectionErrorId,
      'availableRadios': [
        for (final radio in _availableRadios)
          {'id': radio.id, 'name': _friendlyName(radio)},
      ],
      'radioName': _radioName(),
      'regionName': _regionName(),
      'regionIndex': _currRegion(),
      'regions': _regions(),
      'vfoA': {'channelId': vfoA, 'name': _channelName(vfoA)},
      'vfoB': {'channelId': vfoB, 'name': _channelName(vfoB)},
      'channels': [
        for (final c in _channelsForPreferred())
          {'id': c.channelId, 'name': c.name},
      ],
      'scan': settings?.scan ?? false,
      'dualWatch': (settings?.doubleChannel ?? 0) != 0,
      'messages': merged.take(_maxMessages).toList(),
    };
  }

  void _pushState() {
    if (!_active) return;
    _channel.invokeMethod('updateState', _buildState());
  }
}
