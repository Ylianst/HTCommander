/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Home Assistant bridge (desktop only).

Owns an MQTT connection to a broker (typically the Mosquitto add-on that Home
Assistant users already run) and exposes every connected radio to Home Assistant
as its own device using MQTT Discovery. Inspired by the NodeJS proof-of-concept
in `reference/HtStation/src/utils/MqttReporter.js`, folded into HTCommander's
DataBroker event bus and multi-radio model.

For each connected radio it:
  * publishes retained discovery configs so Home Assistant auto-creates the
    entities (battery, firmware, GPS, volume, squelch, scan, dual-watch, VFO A/B,
    region, and incoming APRS messages),
  * republishes radio state (from DataBroker events) to the matching MQTT state
    topics, and
  * turns inbound Home Assistant command topics back into the same DataBroker
    commands the app's own UI dispatches.

The bridge is only wired up on desktop (Windows / Linux / macOS); on the web the
[MqttClientFacade] resolves to an inert stub and this handler is never started.
*/

import 'dart:convert';

import '../aprs/aprs_events.dart';
import '../aprs/packet_data_type.dart';
import '../radio/ax25_packet.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/mqtt/mqtt_client_facade.dart';

/// Per-radio bridge state: identity and Home Assistant topic roots.
class _HaRadio {
  _HaRadio({
    required this.deviceId,
    required this.mac,
    required this.id,
    required this.friendlyName,
  });

  final int deviceId;
  final String mac;

  /// Sanitized unique id used for topics / object ids, e.g. `htcommander_aabbcc`.
  final String id;

  String friendlyName;

  /// Whether discovery configs have been published for this radio.
  bool discovered = false;

  /// Model string, refined once device info arrives.
  String model = 'Benshi Radio';

  /// Base state-topic root, e.g. `htcommander/aabbcc`.
  String get baseTopic => 'htcommander/$id';

  /// Availability topic Home Assistant watches to grey out entities.
  String get availabilityTopic => '$baseTopic/status';
}

/// Bridges connected radios to Home Assistant over MQTT.
class HomeAssistantHandler {
  HomeAssistantHandler() : _broker = DataBrokerClient();

  final DataBrokerClient _broker;

  bool _enabled = false;
  String _url = '';
  String _username = '';
  String _password = '';
  bool _disposed = false;

  MqttClientFacade? _mqtt;

  /// Connected radios by device id.
  final Map<int, _HaRadio> _radios = <int, _HaRadio>{};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initializes the handler: loads settings, subscribes to changes and radio
  /// state, and connects if enabled.
  void init() {
    _enabled =
        (_broker.getValue<int>(0, 'homeAssistantEnabled', 0) ?? 0) == 1;
    _url = _broker.getValue<String>(0, 'homeAssistantMqttUrl', '') ?? '';
    _username =
        _broker.getValue<String>(0, 'homeAssistantUsername', '') ?? '';
    _password =
        _broker.getValue<String>(0, 'homeAssistantPassword', '') ?? '';

    _broker.subscribeMultiple(
      deviceId: 0,
      names: <String>[
        'homeAssistantEnabled',
        'homeAssistantMqttUrl',
        'homeAssistantUsername',
        'homeAssistantPassword',
      ],
      callback: _onSettingChanged,
    );

    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    // Per-radio state events drive the Home Assistant entities.
    _broker.subscribeMultiple(
      deviceId: DataBroker.allDevices,
      names: <String>[
        'State',
        'HtStatus',
        'Settings',
        'Volume',
        'BatteryAsPercentage',
        'Position',
        'GpsEnabled',
        'Info',
        'Channels',
        'RegionNames',
      ],
      callback: _onRadioEvent,
    );

    // Incoming APRS frames (device 1) become APRS message sensors.
    _broker.subscribe(
      deviceId: 1,
      name: 'AprsFrame',
      callback: _onAprsFrame,
    );

    _refreshConnectedRadios();

    if (_enabled && _url.trim().isNotEmpty) {
      _connect();
    }
  }

  void _onSettingChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    switch (name) {
      case 'homeAssistantEnabled':
        final enabled = (data is int ? data : 0) == 1;
        if (enabled == _enabled) return;
        _enabled = enabled;
        break;
      case 'homeAssistantMqttUrl':
        final url = data is String ? data : '';
        if (url == _url) return;
        _url = url;
        break;
      case 'homeAssistantUsername':
        final user = data is String ? data : '';
        if (user == _username) return;
        _username = user;
        break;
      case 'homeAssistantPassword':
        final pass = data is String ? data : '';
        if (pass == _password) return;
        _password = pass;
        break;
      default:
        return;
    }
    // Any change reconnects with the new configuration.
    _disconnect();
    if (_enabled && _url.trim().isNotEmpty) {
      _connect();
    }
  }

  // ---------------------------------------------------------------------------
  // MQTT connection
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_mqtt != null) return;
    final mqtt = MqttClientFacade(
      url: _url.trim(),
      username: _username,
      password: _password,
    );
    mqtt.onMessage = _onMqttMessage;
    mqtt.onConnected = _onMqttConnected;
    _mqtt = mqtt;

    final result = await mqtt.connect();
    if (_disposed) {
      mqtt.dispose();
      return;
    }
    if (!result.ok) {
      _broker.logError(
        'Home Assistant: MQTT connection failed - ${result.error}',
      );
      // autoReconnect will keep retrying; discovery is (re)published on connect.
      return;
    }
    _broker.logInfo('Home Assistant: connected to MQTT broker.');
  }

  void _disconnect() {
    final mqtt = _mqtt;
    if (mqtt == null) return;
    _mqtt = null;
    // Mark every radio offline before dropping the connection.
    for (final radio in _radios.values) {
      if (radio.discovered) {
        mqtt.publish(radio.availabilityTopic, 'offline', retain: true);
      }
      radio.discovered = false;
    }
    mqtt.dispose();
  }

  /// Called when the broker connection is (re)established. Publishes discovery
  /// and current state for every connected radio and subscribes to commands.
  void _onMqttConnected() {
    if (_disposed) return;
    for (final radio in _radios.values) {
      _publishRadio(radio);
    }
  }

  // ---------------------------------------------------------------------------
  // Radio tracking
  // ---------------------------------------------------------------------------

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _refreshConnectedRadios();
  }

  void _refreshConnectedRadios() {
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    final seen = <int>{};
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final id = item['DeviceId'] ?? item['deviceId'];
        if (id is! int || id <= 0) continue;
        seen.add(id);
        final mac = (item['MacAddress'] ?? item['macAddress'] ?? '').toString();
        final friendly =
            (item['FriendlyName'] ?? 'Radio $id').toString().trim();
        final existing = _radios[id];
        if (existing == null) {
          _radios[id] = _HaRadio(
            deviceId: id,
            mac: mac,
            id: _sanitizeId(mac, id),
            friendlyName: friendly.isEmpty ? 'Radio $id' : friendly,
          );
          _publishRadio(_radios[id]!);
        } else {
          existing.friendlyName =
              friendly.isEmpty ? existing.friendlyName : friendly;
        }
      }
    }

    // Remove radios that are no longer connected.
    final removed = _radios.keys.where((id) => !seen.contains(id)).toList();
    for (final id in removed) {
      final radio = _radios.remove(id);
      if (radio != null && radio.discovered) {
        _mqtt?.publish(radio.availabilityTopic, 'offline', retain: true);
      }
    }
  }

  static String _sanitizeId(String mac, int deviceId) {
    final cleaned =
        mac.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleaned.isEmpty) return 'htcommander_dev$deviceId';
    return 'htcommander_$cleaned';
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _deviceBlock(_HaRadio radio) => {
        'identifiers': <String>[radio.id],
        'name': radio.friendlyName,
        'manufacturer': 'Benshi',
        'model': radio.model,
      };

  /// Discovery config topic: `homeassistant/<component>/<node>/<object>/config`.
  String _discoveryTopic(_HaRadio radio, String component, String object) =>
      'homeassistant/$component/${radio.id}/$object/config';

  void _publishConfig(
    _HaRadio radio,
    String component,
    String object,
    Map<String, dynamic> config,
  ) {
    final mqtt = _mqtt;
    if (mqtt == null) return;
    config['availability_topic'] = radio.availabilityTopic;
    config['payload_available'] = 'online';
    config['payload_not_available'] = 'offline';
    config['device'] = _deviceBlock(radio);
    mqtt.publish(
      _discoveryTopic(radio, component, object),
      jsonEncode(config),
      retain: true,
    );
  }

  /// Publishes all discovery configs and the current state snapshot for a radio.
  void _publishRadio(_HaRadio radio) {
    final mqtt = _mqtt;
    if (mqtt == null || !mqtt.isConnected) return;

    _publishBatteryConfig(radio);
    _publishFirmwareConfig(radio);
    _publishGpsSensorsConfig(radio);
    _publishVolumeConfig(radio);
    _publishSquelchConfig(radio);
    _publishScanConfig(radio);
    _publishDualWatchConfig(radio);
    _publishGpsSwitchConfig(radio);
    _publishRegionConfig(radio);
    _publishVfoConfig(radio);
    _publishAprsConfig(radio);

    radio.discovered = true;
    // Announce availability, then push the current cached state.
    mqtt.publish(radio.availabilityTopic, 'online', retain: true);
    _publishSnapshot(radio);

    // Subscribe to this radio's command topics.
    for (final suffix in const <String>[
      'volume/set',
      'squelch/set',
      'scan/set',
      'dual_watch/set',
      'gps/set',
      'vfo_a/set',
      'vfo_b/set',
      'region/set',
    ]) {
      mqtt.subscribe('${radio.baseTopic}/$suffix');
    }
  }

  void _publishBatteryConfig(_HaRadio radio) {
    _publishConfig(radio, 'sensor', 'battery', {
      'name': 'Battery',
      'state_topic': '${radio.baseTopic}/battery',
      'unique_id': '${radio.id}_battery',
      'unit_of_measurement': '%',
      'device_class': 'battery',
      'value_template': '{{ value_json.battery }}',
      'icon': 'mdi:battery',
    });
  }

  void _publishFirmwareConfig(_HaRadio radio) {
    _publishConfig(radio, 'sensor', 'firmware', {
      'name': 'Firmware Version',
      'state_topic': '${radio.baseTopic}/firmware',
      'unique_id': '${radio.id}_firmware',
      'value_template': '{{ value_json.firmware_version }}',
      'entity_category': 'diagnostic',
      'icon': 'mdi:chip',
    });
  }

  void _publishGpsSensorsConfig(_HaRadio radio) {
    final stateTopic = '${radio.baseTopic}/gps_position';
    _publishConfig(radio, 'sensor', 'gps_lat', {
      'name': 'GPS Latitude',
      'state_topic': stateTopic,
      'unique_id': '${radio.id}_gps_lat',
      'unit_of_measurement': '°',
      'value_template': '{{ value_json.latitude }}',
      'icon': 'mdi:latitude',
    });
    _publishConfig(radio, 'sensor', 'gps_lng', {
      'name': 'GPS Longitude',
      'state_topic': stateTopic,
      'unique_id': '${radio.id}_gps_lng',
      'unit_of_measurement': '°',
      'value_template': '{{ value_json.longitude }}',
      'icon': 'mdi:longitude',
    });
    _publishConfig(radio, 'sensor', 'gps_alt', {
      'name': 'GPS Altitude',
      'state_topic': stateTopic,
      'unique_id': '${radio.id}_gps_alt',
      'unit_of_measurement': 'm',
      'value_template': '{{ value_json.altitude }}',
      'icon': 'mdi:altimeter',
    });
    _publishConfig(radio, 'binary_sensor', 'gps_lock', {
      'name': 'GPS Lock',
      'state_topic': stateTopic,
      'unique_id': '${radio.id}_gps_lock',
      'device_class': 'connectivity',
      'payload_on': 'true',
      'payload_off': 'false',
      'value_template': '{{ value_json.locked }}',
      'icon': 'mdi:satellite-variant',
    });
  }

  void _publishVolumeConfig(_HaRadio radio) {
    _publishConfig(radio, 'number', 'volume', {
      'name': 'Volume',
      'state_topic': '${radio.baseTopic}/volume',
      'command_topic': '${radio.baseTopic}/volume/set',
      'unique_id': '${radio.id}_volume',
      'min': 0,
      'max': 15,
      'step': 1,
      'value_template': '{{ value_json.volume }}',
      'icon': 'mdi:volume-high',
    });
  }

  void _publishSquelchConfig(_HaRadio radio) {
    _publishConfig(radio, 'number', 'squelch', {
      'name': 'Squelch',
      'state_topic': '${radio.baseTopic}/squelch',
      'command_topic': '${radio.baseTopic}/squelch/set',
      'unique_id': '${radio.id}_squelch',
      'min': 0,
      'max': 15,
      'step': 1,
      'value_template': '{{ value_json.squelch }}',
      'icon': 'mdi:volume-off',
    });
  }

  void _publishScanConfig(_HaRadio radio) {
    _publishConfig(radio, 'switch', 'scan', {
      'name': 'Scan',
      'state_topic': '${radio.baseTopic}/scan',
      'command_topic': '${radio.baseTopic}/scan/set',
      'unique_id': '${radio.id}_scan',
      'payload_on': 'ON',
      'payload_off': 'OFF',
      'value_template': '{{ value_json.scan }}',
      'icon': 'mdi:radar',
    });
  }

  void _publishDualWatchConfig(_HaRadio radio) {
    _publishConfig(radio, 'switch', 'dual_watch', {
      'name': 'Dual Watch',
      'state_topic': '${radio.baseTopic}/dual_watch',
      'command_topic': '${radio.baseTopic}/dual_watch/set',
      'unique_id': '${radio.id}_dual_watch',
      'payload_on': 'ON',
      'payload_off': 'OFF',
      'value_template': '{{ value_json.dual_watch }}',
      'icon': 'mdi:swap-horizontal',
    });
  }

  void _publishGpsSwitchConfig(_HaRadio radio) {
    _publishConfig(radio, 'switch', 'gps', {
      'name': 'GPS',
      'state_topic': '${radio.baseTopic}/gps',
      'command_topic': '${radio.baseTopic}/gps/set',
      'unique_id': '${radio.id}_gps',
      'payload_on': 'ON',
      'payload_off': 'OFF',
      'value_template': '{{ value_json.gps }}',
      'icon': 'mdi:crosshairs-gps',
    });
  }

  void _publishRegionConfig(_HaRadio radio) {
    final options = _regionOptions(radio.deviceId);
    if (options.isEmpty) return;
    _publishConfig(radio, 'select', 'region', {
      'name': 'Region',
      'state_topic': '${radio.baseTopic}/region',
      'command_topic': '${radio.baseTopic}/region/set',
      'unique_id': '${radio.id}_region',
      'options': options,
      'value_template': '{{ value_json.region }}',
      'icon': 'mdi:map',
    });
  }

  void _publishVfoConfig(_HaRadio radio) {
    final options = _channelOptions(radio.deviceId);
    if (options.isEmpty) return;
    _publishConfig(radio, 'select', 'vfo_a', {
      'name': 'VFO A',
      'state_topic': '${radio.baseTopic}/vfo_a',
      'command_topic': '${radio.baseTopic}/vfo_a/set',
      'unique_id': '${radio.id}_vfo_a',
      'options': options,
      'value_template': '{{ value_json.vfo }}',
      'icon': 'mdi:radio-handheld',
    });
    _publishConfig(radio, 'select', 'vfo_b', {
      'name': 'VFO B',
      'state_topic': '${radio.baseTopic}/vfo_b',
      'command_topic': '${radio.baseTopic}/vfo_b/set',
      'unique_id': '${radio.id}_vfo_b',
      'options': options,
      'value_template': '{{ value_json.vfo }}',
      'icon': 'mdi:radio-handheld',
    });
  }

  void _publishAprsConfig(_HaRadio radio) {
    _publishConfig(radio, 'sensor', 'aprs_message', {
      'name': 'My APRS Message',
      'state_topic': '${radio.baseTopic}/aprs_message',
      'unique_id': '${radio.id}_aprs_message',
      'value_template': '{{ value_json.message }}',
      'icon': 'mdi:message-text',
    });
    _publishConfig(radio, 'sensor', 'aprs_message_trusted', {
      'name': 'My Trusted APRS Message',
      'state_topic': '${radio.baseTopic}/aprs_message_trusted',
      'unique_id': '${radio.id}_aprs_message_trusted',
      'value_template': '{{ value_json.message }}',
      'icon': 'mdi:message-lock',
    });
    _publishConfig(radio, 'sensor', 'aprs_message_other', {
      'name': 'APRS Message',
      'state_topic': '${radio.baseTopic}/aprs_message_other',
      'unique_id': '${radio.id}_aprs_message_other',
      'value_template': '{{ value_json.message }}',
      'icon': 'mdi:message-outline',
    });
  }

  // ---------------------------------------------------------------------------
  // State: radio -> Home Assistant
  // ---------------------------------------------------------------------------

  /// Publishes the currently-cached state for every entity of [radio].
  void _publishSnapshot(_HaRadio radio) {
    final id = radio.deviceId;
    final battery = _broker.getValue<int>(id, 'BatteryAsPercentage', null);
    if (battery != null) _publishBattery(radio, battery);

    final volume = _broker.getValue<int>(id, 'Volume', null);
    if (volume != null) _publishVolume(radio, volume);

    final info = _broker.getValueDynamic(id, 'Info', null);
    if (info is Map) _publishFirmware(radio, info);

    final settings = _broker.getValueDynamic(id, 'Settings', null);
    if (settings is Map) _publishSettings(radio, settings);

    final htStatus = _broker.getValueDynamic(id, 'HtStatus', null);
    if (htStatus is Map) _publishHtStatus(radio, htStatus);

    final gpsEnabled = _broker.getValue<bool>(id, 'GpsEnabled', null);
    if (gpsEnabled != null) _publishGpsEnabled(radio, gpsEnabled);

    final position = _broker.getValueDynamic(id, 'Position', null);
    if (position is Map) _publishPosition(radio, position);
  }

  void _onRadioEvent(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final radio = _radios[deviceId];
    if (radio == null) return;
    final mqtt = _mqtt;
    if (mqtt == null || !mqtt.isConnected) return;

    switch (name) {
      case 'State':
        final connected = data is String && data == 'Connected';
        if (radio.discovered) {
          mqtt.publish(
            radio.availabilityTopic,
            connected ? 'online' : 'offline',
            retain: true,
          );
        }
        break;
      case 'BatteryAsPercentage':
        if (data is int) _publishBattery(radio, data);
        break;
      case 'Volume':
        if (data is int) _publishVolume(radio, data);
        break;
      case 'Info':
        if (data is Map) {
          _publishFirmware(radio, data);
          // Region count may now be known; refresh the region select options.
          if (radio.discovered) _publishRegionConfig(radio);
        }
        break;
      case 'Settings':
        if (data is Map) _publishSettings(radio, data);
        break;
      case 'HtStatus':
        if (data is Map) _publishHtStatus(radio, data);
        break;
      case 'GpsEnabled':
        if (data is bool) _publishGpsEnabled(radio, data);
        break;
      case 'Position':
        if (data is Map) _publishPosition(radio, data);
        break;
      case 'Channels':
        if (radio.discovered) {
          _publishVfoConfig(radio);
          _publishVfoStateFromSettings(radio);
        }
        break;
      case 'RegionNames':
        if (radio.discovered) _publishRegionConfig(radio);
        break;
    }
  }

  void _publishBattery(_HaRadio radio, int percentage) {
    _mqtt?.publish(
      '${radio.baseTopic}/battery',
      jsonEncode({'battery': percentage}),
      retain: true,
    );
  }

  void _publishVolume(_HaRadio radio, int volume) {
    _mqtt?.publish(
      '${radio.baseTopic}/volume',
      jsonEncode({'volume': volume}),
      retain: true,
    );
  }

  void _publishFirmware(_HaRadio radio, Map<dynamic, dynamic> info) {
    final softVer = info['softVer'];
    if (softVer is! int) return;
    // softVer is packed as a 16-bit value; render it as major.minor.patch.
    final version =
        '${(softVer >> 8) & 0xFF}.${(softVer >> 4) & 0x0F}.${softVer & 0x0F}';
    _mqtt?.publish(
      '${radio.baseTopic}/firmware',
      jsonEncode({'firmware_version': version}),
      retain: true,
    );
  }

  void _publishSettings(_HaRadio radio, Map<dynamic, dynamic> settings) {
    final squelch = settings['squelchLevel'];
    if (squelch is int) {
      _mqtt?.publish(
        '${radio.baseTopic}/squelch',
        jsonEncode({'squelch': squelch}),
        retain: true,
      );
    }
    _publishVfoStateFromSettings(radio, settings: settings);
  }

  void _publishVfoStateFromSettings(
    _HaRadio radio, {
    Map<dynamic, dynamic>? settings,
  }) {
    final data = settings ?? _broker.getValueDynamic(radio.deviceId, 'Settings', null);
    if (data is! Map) return;
    final options = _channelOptions(radio.deviceId);
    final channelA = data['channelA'];
    final channelB = data['channelB'];
    if (channelA is int && channelA >= 0 && channelA < options.length) {
      _mqtt?.publish(
        '${radio.baseTopic}/vfo_a',
        jsonEncode({'vfo': options[channelA]}),
        retain: true,
      );
    }
    if (channelB is int && channelB >= 0 && channelB < options.length) {
      _mqtt?.publish(
        '${radio.baseTopic}/vfo_b',
        jsonEncode({'vfo': options[channelB]}),
        retain: true,
      );
    }
  }

  void _publishHtStatus(_HaRadio radio, Map<dynamic, dynamic> status) {
    final isScan = status['isScan'];
    if (isScan is bool) {
      _mqtt?.publish(
        '${radio.baseTopic}/scan',
        jsonEncode({'scan': isScan ? 'ON' : 'OFF'}),
        retain: true,
      );
    }
    final doubleChannel = status['doubleChannel'];
    if (doubleChannel is int) {
      _mqtt?.publish(
        '${radio.baseTopic}/dual_watch',
        jsonEncode({'dual_watch': doubleChannel != 0 ? 'ON' : 'OFF'}),
        retain: true,
      );
    }
    final currRegion = status['currRegion'];
    if (currRegion is int) {
      final options = _regionOptions(radio.deviceId);
      if (currRegion >= 0 && currRegion < options.length) {
        _mqtt?.publish(
          '${radio.baseTopic}/region',
          jsonEncode({'region': options[currRegion]}),
          retain: true,
        );
      }
    }
  }

  void _publishGpsEnabled(_HaRadio radio, bool enabled) {
    _mqtt?.publish(
      '${radio.baseTopic}/gps',
      jsonEncode({'gps': enabled ? 'ON' : 'OFF'}),
      retain: true,
    );
  }

  void _publishPosition(_HaRadio radio, Map<dynamic, dynamic> position) {
    _mqtt?.publish(
      '${radio.baseTopic}/gps_position',
      jsonEncode({
        'latitude': position['latitude'],
        'longitude': position['longitude'],
        'altitude': position['altitude'],
        'speed': position['speed'],
        'heading': position['heading'],
        'locked': position['locked'] == true ? 'true' : 'false',
      }),
      retain: true,
    );
  }

  // ---------------------------------------------------------------------------
  // APRS messages -> Home Assistant
  // ---------------------------------------------------------------------------

  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! AprsFrameEventArgs) return;
    final mqtt = _mqtt;
    if (mqtt == null || !mqtt.isConnected) return;

    final aprs = data.aprsPacket;
    if (aprs.dataType != PacketDataType.message) return;
    final text = aprs.messageData.msgText;
    if (text.isEmpty) return;

    // Resolve which radio this frame arrived on (by MAC).
    final mac = data.fragment?.radioMac ?? '';
    final radios = <_HaRadio>[];
    if (mac.isNotEmpty) {
      final match = _radios.values.where(
        (r) => r.mac.toLowerCase() == mac.toLowerCase(),
      );
      radios.addAll(match);
    }
    if (radios.isEmpty) radios.addAll(_radios.values);

    // Determine whether the message is addressed to us and authenticated.
    final callSign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final localWithId = stationId > 0 ? '$callSign-$stationId' : callSign;
    final addressee = aprs.messageData.addressee;
    final forUs = callSign.isNotEmpty &&
        (addressee.toLowerCase() == callSign.toLowerCase() ||
            addressee.toLowerCase() == localWithId.toLowerCase());
    final trusted = data.ax25Packet.authState == AuthState.success;

    final sender = data.ax25Packet.addresses.length > 1
        ? data.ax25Packet.addresses[1].callSignWithId
        : '';
    final payload = jsonEncode({
      'message': text,
      'sender': sender,
      'addressee': addressee,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final String topicSuffix;
    if (forUs && trusted) {
      topicSuffix = 'aprs_message_trusted';
    } else if (forUs) {
      topicSuffix = 'aprs_message';
    } else {
      topicSuffix = 'aprs_message_other';
    }

    for (final radio in radios) {
      if (!radio.discovered) continue;
      mqtt.publish('${radio.baseTopic}/$topicSuffix', payload, retain: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Commands: Home Assistant -> radio
  // ---------------------------------------------------------------------------

  void _onMqttMessage(String topic, String payload) {
    if (_disposed) return;
    for (final radio in _radios.values) {
      final prefix = '${radio.baseTopic}/';
      if (!topic.startsWith(prefix)) continue;
      final suffix = topic.substring(prefix.length);
      _handleCommand(radio, suffix, payload.trim());
      return;
    }
  }

  void _handleCommand(_HaRadio radio, String suffix, String payload) {
    final id = radio.deviceId;
    switch (suffix) {
      case 'volume/set':
        final value = int.tryParse(payload);
        if (value != null) {
          _broker.dispatch(
            deviceId: id,
            name: 'SetVolumeLevel',
            data: value.clamp(0, 15),
            store: false,
          );
        }
        break;
      case 'squelch/set':
        final value = int.tryParse(payload);
        if (value != null) {
          _broker.dispatch(
            deviceId: id,
            name: 'SetSquelchLevel',
            data: value.clamp(0, 15),
            store: false,
          );
        }
        break;
      case 'scan/set':
        _broker.dispatch(
          deviceId: id,
          name: 'Scan',
          data: payload.toUpperCase() == 'ON',
          store: false,
        );
        break;
      case 'dual_watch/set':
        _broker.dispatch(
          deviceId: id,
          name: 'DualWatch',
          data: payload.toUpperCase() == 'ON',
          store: false,
        );
        break;
      case 'gps/set':
        _broker.dispatch(
          deviceId: id,
          name: 'SetGPS',
          data: payload.toUpperCase() == 'ON',
          store: false,
        );
        break;
      case 'vfo_a/set':
        final channelId = _parseLeadingIndex(payload);
        if (channelId != null) {
          _broker.dispatch(
            deviceId: id,
            name: 'ChannelChangeVfoA',
            data: channelId,
            store: false,
          );
        }
        break;
      case 'vfo_b/set':
        final channelId = _parseLeadingIndex(payload);
        if (channelId != null) {
          _broker.dispatch(
            deviceId: id,
            name: 'ChannelChangeVfoB',
            data: channelId,
            store: false,
          );
        }
        break;
      case 'region/set':
        final region = _parseLeadingIndex(payload);
        if (region != null) {
          _broker.dispatch(
            deviceId: id,
            name: 'SetRegion',
            data: region,
            store: false,
          );
        }
        break;
    }
  }

  /// Parses the leading 1-based number out of an option label ("3: Calling" or
  /// "Region 3") and returns the 0-based index, or null if none.
  static int? _parseLeadingIndex(String option) {
    final match = RegExp(r'(\d+)').firstMatch(option);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value < 1) return null;
    return value - 1;
  }

  // ---------------------------------------------------------------------------
  // Option helpers
  // ---------------------------------------------------------------------------

  /// Builds VFO select options ("1: Calling") from the radio's channel list.
  List<String> _channelOptions(int deviceId) {
    final channels = _broker.getValueDynamic(deviceId, 'Channels', null);
    if (channels is! List || channels.isEmpty) return const <String>[];
    // Channels are addressed by channelId; build a dense list large enough.
    var maxId = -1;
    for (final ch in channels) {
      if (ch is Map) {
        final cid = ch['channelId'];
        if (cid is int && cid > maxId) maxId = cid;
      }
    }
    if (maxId < 0) return const <String>[];
    final options = List<String>.generate(
      maxId + 1,
      (i) => '${i + 1}: Channel ${i + 1}',
    );
    for (final ch in channels) {
      if (ch is! Map) continue;
      final cid = ch['channelId'];
      if (cid is! int || cid < 0 || cid > maxId) continue;
      final name = (ch['name'] ?? '').toString().trim();
      options[cid] = '${cid + 1}: ${name.isEmpty ? 'Channel ${cid + 1}' : name}';
    }
    return options;
  }

  /// Builds region select options ("Region 1") from the radio's region count.
  List<String> _regionOptions(int deviceId) {
    final regionNames = _broker.getValueDynamic(deviceId, 'RegionNames', null);
    int count = 0;
    if (regionNames is List) count = regionNames.length;
    if (count == 0) {
      final info = _broker.getValueDynamic(deviceId, 'Info', null);
      if (info is Map && info['regionCount'] is int) {
        count = info['regionCount'] as int;
      }
    }
    if (count <= 0) return const <String>[];
    return List<String>.generate(count, (i) => 'Region ${i + 1}');
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Stops the bridge and releases all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disconnect();
    _broker.dispose();
  }
}
