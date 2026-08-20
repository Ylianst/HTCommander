/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../aprs/aprs_events.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../models/radio_models.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';

/// Bridges the app's radio state to the native Android Auto car UI.
///
/// The Android Auto surface is drawn by a native `CarAppService` (Kotlin) that
/// cannot see the Dart isolate directly, so this class mirrors a small,
/// car-safe slice of state over the `com.htcommander/android_auto`
/// [MethodChannel]:
///   - the channel list and currently selected channel of the preferred radio,
///   - recent APRS messages addressed to our station.
///
/// State flows Dart -> native via `updateState`; channel-change requests flow
/// native -> Dart via `setChannel`. Only active on Android; a no-op elsewhere.
class AndroidAutoBridge {
  static const MethodChannel _channel =
      MethodChannel('com.htcommander/android_auto');

  /// Broker device id APRS events are published under (see [AprsHandler]).
  static const int _aprsDeviceId = 1;

  /// Maximum number of APRS messages mirrored to the car screen.
  static const int _maxMessages = 25;

  final DataBrokerClient _broker = DataBrokerClient();

  bool _active = false;
  int _preferredRadioId = -1;

  /// Whether a car (Android Auto) session is currently projecting. Incoming
  /// messages are only read aloud while this is true.
  bool _carConnected = false;

  /// Lazily created text-to-speech engine used to read incoming messages aloud
  /// through the car speaker. Null until the first message is spoken.
  FlutterTts? _tts;

  final List<Map<String, Object?>> _messages = [];

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
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsFrame',
      callback: _onAprsFrame,
    );

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
        if (!_carConnected) _tts?.stop();
        return null;
      case 'setChannel':
        final channelId = call.arguments as int?;
        if (channelId != null && _preferredRadioId > 0) {
          _broker.dispatch(
            deviceId: _preferredRadioId,
            name: 'ChannelChangeVfoA',
            data: channelId,
            store: false,
          );
        }
        return null;
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  void _onPreferredRadioChanged(int deviceId, String name, Object? data) {
    if (data is int) _preferredRadioId = data;
    _pushState();
  }

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    _pushState();
  }

  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (data is! AprsFrameEventArgs) return;
    final entry = _incomingMessageForUs(data);
    if (entry == null) return;
    _messages.insert(0, entry);
    while (_messages.length > _maxMessages) {
      _messages.removeLast();
    }
    _pushState();
    if (_carConnected) {
      _speakMessage(
        entry['from'] as String? ?? '',
        entry['text'] as String? ?? '',
      );
    }
  }

  /// Reads an incoming APRS message aloud through the car speaker. Announces the
  /// sender (when known) followed by the message text; queues rather than
  /// interrupts so back-to-back messages are all read.
  Future<void> _speakMessage(String from, String text) async {
    if (text.isEmpty) return;
    final spoken =
        from.isNotEmpty ? 'Message from $from. $text' : 'Message. $text';
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

  /// Returns a `{from, text, time}` map when [args] is an APRS text message
  /// addressed to our station, otherwise null. Mirrors the filter used by
  /// [AprsHandler] to raise incoming-message notifications.
  Map<String, Object?>? _incomingMessageForUs(AprsFrameEventArgs args) {
    final aprs = args.aprsPacket;
    if (aprs.dataType != PacketDataType.message) return null;
    final msg = aprs.messageData;
    if (msg.msgType == MessageType.mtAck) return null;
    if (msg.msgType == MessageType.mtRej) return null;
    if (msg.msgText.isEmpty) return null;

    final addressee = msg.addressee;
    if (addressee.isEmpty) return null;

    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final localWithId = _localCallsignWithId();
    final isForUs =
        (localWithId != null &&
            addressee.toLowerCase() == localWithId.toLowerCase()) ||
        (callsign.isNotEmpty &&
            addressee.toLowerCase() == callsign.toLowerCase());
    if (!isForUs) return null;

    final ax = args.ax25Packet;
    String from = '';
    if (ax.addresses.length >= 2) {
      final addr = ax.addresses[1];
      from = addr.ssid > 0 ? '${addr.address}-${addr.ssid}' : addr.address;
    }
    return {
      'from': from,
      'text': msg.msgText,
      'time': DateTime.now().millisecondsSinceEpoch,
    };
  }

  String? _localCallsignWithId() {
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    if (callsign.isEmpty) return null;
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    return stationId > 0 ? '$callsign-$stationId' : callsign;
  }

  List<RadioChannelInfo> _channelsForPreferred() {
    if (_preferredRadioId <= 0) return const [];
    return _broker.getJsonListValue<RadioChannelInfo>(
          _preferredRadioId,
          'Channels',
          (json) => RadioChannelInfo.fromJson(json),
        ) ??
        const [];
  }

  int _currentChannelId() {
    if (_preferredRadioId <= 0) return -1;
    final settings = _broker.getJsonValue<RadioSettings>(
      _preferredRadioId,
      'Settings',
      (json) => RadioSettings.fromJson(json),
    );
    return settings?.channelA ?? -1;
  }

  String _radioName() {
    if (_preferredRadioId <= 0) return '';
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
    final channels = _channelsForPreferred();
    return {
      'connected': _preferredRadioId > 0,
      'radioName': _radioName(),
      'currentChannelId': _currentChannelId(),
      'channels': [
        for (final c in channels) {'id': c.channelId, 'name': c.name},
      ],
      'messages': List<Map<String, Object?>>.from(_messages),
    };
  }

  void _pushState() {
    if (!_active) return;
    _channel.invokeMethod('updateState', _buildState());
  }
}
