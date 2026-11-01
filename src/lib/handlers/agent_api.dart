/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Agent automation protocol, carried over the web server's WebSocket next to the
hosted web UI's messages (see docs/blogs/ai-agent-radio-testing.md).

Every message is a text frame `agent:{json}`. It is off unless the operator
enables `AgentApiEnabled`, and each connection must authenticate with the
`AgentApiToken` secret before anything else is accepted.

Requests carry an `id` that the reply echoes:

  agent:{"id":1,"op":"hello","token":"..."}
  agent:{"id":1,"ok":true,"station":"N0CALL-1",...}

Observation: `hello`, `ping`, `subscribe`, `unsubscribe`, `packets`, `logs`,
`get`. Subscribed events are pushed as
`agent:{"event":name,"device":id,"time":iso,"data":...}`.

Control: `command` runs one allowlisted, typed command (radio lock, BBS, XARA,
the host terminal, packet clearing, a few modem settings) and `stop` releases everything agents
hold. Commands that can transmit need the station's `AllowTransmit` setting and
are refused on radios locked by anything other than an agent. Each radio an
agent controls has a transmit-time limit per minute; going over it releases the
radio. Everything an agent holds is released when its socket closes, when the
operator presses Stop (which also turns the API off), or when the API is turned
off. While any agent is connected the host publishes `AgentControl` (device 1)
so the UI can show that it is under agent control.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/station_info.dart';
import '../radio/packet_decoder.dart';
import '../radio/radio.dart' show SetLockData, SetUnlockData;
import '../radio/tnc_data_fragment.dart';
import '../radio/utils.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import '../services/web/web_server.dart';
import 'bbs_handler.dart';
import 'packet_store.dart';

/// Automation channel for test agents.
class AgentApi {
  AgentApi(this._broker);

  final DataBrokerClient _broker;
  final Map<int, _AgentSession> _sessions = <int, _AgentSession>{};
  final Map<int, _TxMeter> _txMeters = <int, _TxMeter>{};
  Timer? _txTimer;
  bool _initialized = false;
  Object? _lastTerminalNotice;

  /// Message prefix that routes a WebSocket text frame to this API.
  static const String prefix = 'agent:';

  /// Device-0 setting that turns the API on (1) or off (0).
  static const String enabledSetting = 'AgentApiEnabled';

  /// Device-0 secret that clients must present in `hello`.
  static const String tokenSetting = 'AgentApiToken';

  /// Failed `hello` attempts after which a connection is ignored.
  static const int maxAuthFailures = 5;

  /// Device-0 setting: seconds an agent-controlled radio may transmit within
  /// any 60 s window before the agent's hold on it is released.
  static const String txLimitSetting = 'AgentApiTxSecondsPerMinute';
  static const int defaultTxSecondsPerMinute = 45;

  /// How long a radio refuses transmitting commands after hitting the limit.
  static const Duration txCooldown = Duration(seconds: 60);

  /// Device-1 value the UI watches to show agent control (stored).
  static const String controlValue = 'AgentControl';

  /// Device-1 event the UI sends to stop all agents and turn the API off.
  static const String stopEvent = 'AgentStop';

  /// Commands an agent may run with `command`.
  static const Set<String> commands = <String>{
    'radio.lock',
    'radio.unlock',
    'bbs.start',
    'bbs.stop',
    'xara.connect',
    'xara.send',
    'xara.disconnect',
    'xara.abort',
    'terminal.connect',
    'terminal.wait',
    'terminal.send',
    'terminal.disconnect',
    'terminal.abort',
    'packets.clear',
    'setting.set',
  };

  /// Commands that can key a transmitter.
  static const Set<String> transmitting = <String>{
    'radio.lock',
    'bbs.start',
    'xara.connect',
    'xara.send',
    'terminal.connect',
    'terminal.wait',
    'terminal.send',
  };

  /// Lock usages an agent may take.
  static const Set<String> lockUsages = <String>{'Agent', 'Terminal'};

  /// Modem overrides an agent may request when locking a radio.
  static const Set<String> lockModems = <String>{
    'Hardware',
    'AFSK1200',
    'PSK2400',
    'DART',
    'XARA',
  };

  /// Device-0 settings an agent may change with `setting.set`.
  static const Set<String> settableSettings = <String>{
    'SoftwareModemMode',
    'SoftwareModemFec',
    'DartTxMode',
    'XaraWide',
    'XaraTxLatencyMs',
    'XaraTxKeyUpMs',
  };

  /// Events an agent may subscribe to, with the broker device they come from
  /// (-1 = any radio device).
  static const Map<String, int> events = <String, int>{
    'PacketStored': 1,
    'LogInfo': 1,
    'LogError': 1,
    'XaraEvent': -1,
    'XaraLinkState': -1,
    'BbsControlMessage': 0,
    'BbsTraffic': 0,
    'BbsError': 0,
    'LockState': -1,
    'State': -1,
    'HtStatus': -1,
    'TerminalState': 1,
    'TerminalText': 1,
    'TerminalNotice': 1,
  };

  /// Per-radio values an agent may read with `get`.
  static const Set<String> readableRadioValues = <String>{
    'State',
    'LockState',
    'HtStatus',
    'XaraLinkState',
    'FriendlyName',
    'Channels',
    'RegionNames',
    'AudioState',
  };

  /// Device-1 values an agent may read with `get`.
  static const Set<String> readableAppValues = <String>{
    'ConnectedRadios',
    'SelectedRadioDeviceId',
    'TerminalState',
  };

  /// Whether [name] is a device-0 setting that must never leave the host.
  static bool isSecretSetting(String name) => HostBridge.isSecretSetting(name);

  bool get enabled => (_broker.getValue<int>(0, enabledSetting, 0) ?? 0) == 1;

  /// Generates a new random access token (192 bits, URL-safe).
  static String generateToken() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(24, (_) => rng.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    for (final entry in events.entries) {
      _broker.subscribe(
        deviceId: DataBroker.allDevices,
        name: entry.key,
        callback: _onEvent,
      );
    }
    // Turning the API off stops every agent and drops its session.
    _broker.subscribe(
      deviceId: 0,
      name: enabledSetting,
      callback: (_, _, _) {
        if (!enabled) _stopAll('agent API turned off', drop: true);
      },
    );
    // A terminal link that ended (or that the operator took over) is no
    // longer the agent's to release.
    _broker.subscribe(
      deviceId: 1,
      name: 'TerminalState',
      callback: (_, _, _) {
        if (_terminalRadio != null) return;
        var changed = false;
        for (final s in _sessions.values) {
          if (s.terminal != null) {
            s.terminal = null;
            changed = true;
          }
        }
        if (changed) _publishControl();
      },
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'TerminalNotice',
      callback: (_, _, d) => _lastTerminalNotice = d,
    );
    // The operator's Stop button: stop every agent and turn the API off.
    _broker.subscribe(
      deviceId: 1,
      name: stopEvent,
      callback: (_, _, _) {
        _stopAll('stopped by the operator', drop: true);
        _broker.dispatch(deviceId: 0, name: enabledSetting, data: 0);
      },
    );
    _publishControl();
  }

  /// Handles an `agent:` text frame from [client]. Returns false when [message]
  /// is not an agent message.
  bool handle(WebSocketClient client, String message) {
    if (!message.startsWith(prefix)) return false;
    Map<String, Object?> req;
    try {
      final decoded = jsonDecode(message.substring(prefix.length));
      if (decoded is! Map) throw const FormatException('not an object');
      req = decoded.cast<String, Object?>();
    } catch (_) {
      _reply(client, null, error: 'invalid JSON request');
      return true;
    }
    final Object? id = req['id'];
    if (!enabled) {
      _reply(client, id, error: 'agent API disabled');
      return true;
    }
    final session = _sessions.putIfAbsent(
      client.id,
      () => _AgentSession(client),
    );
    if (session.failures >= maxAuthFailures) return true;
    final String op = (req['op'] ?? '').toString();
    if (op == 'hello') {
      _hello(session, id, req);
      return true;
    }
    if (!session.authenticated) {
      _reply(client, id, error: 'not authenticated: send hello first');
      return true;
    }
    switch (op) {
      case 'ping':
        _reply(client, id, data: {'hostTime': _now()});
      case 'subscribe':
        _subscribe(session, id, req, add: true);
      case 'unsubscribe':
        _subscribe(session, id, req, add: false);
      case 'packets':
        _packets(session, id, req);
      case 'logs':
        _logs(session, id, req);
      case 'get':
        _get(session, id, req);
      case 'command':
        _command(session, id, req);
      case 'stop':
        final released = _stopAll(
          'stop requested by agent client ${client.id}',
          notify: false,
        );
        _reply(client, id, data: {'released': released});
      default:
        _reply(client, id, error: 'unknown op "$op"');
    }
    return true;
  }

  /// Forgets [client]'s session when its socket closes, releasing everything it
  /// holds (fail-safe: a dropped agent never leaves a radio keyed or locked).
  void remove(WebSocketClient client) {
    final s = _sessions.remove(client.id);
    if (s == null) return;
    final released = _release(s);
    if (released.isNotEmpty) {
      _broker.logInfo(
        '[AgentApi] Agent client ${client.id} disconnected; released $released',
      );
    }
    _publishControl();
  }

  /// Releases everything agents hold and stops the transmit meter.
  void dispose() {
    for (final s in _sessions.values) {
      _release(s);
    }
    _sessions.clear();
    _txTimer?.cancel();
    _txTimer = null;
    _publishControl();
  }

  /// Number of authenticated agent connections (for diagnostics and tests).
  int get authenticatedCount =>
      _sessions.values.where((s) => s.authenticated).length;

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------

  Future<void> _hello(
    _AgentSession session,
    Object? id,
    Map<String, Object?> req,
  ) async {
    final expected = _broker.getValue<String>(0, tokenSetting, '') ?? '';
    final given = req['token'];
    if (expected.isEmpty || given is! String || !_sameToken(given, expected)) {
      session.failures++;
      _broker.logError(
        '[AgentApi] Rejected agent client ${session.client.id} '
        '(bad token, attempt ${session.failures})',
      );
      _reply(session.client, id, error: 'bad token');
      return;
    }
    session.authenticated = true;
    session.failures = 0;
    _broker.logInfo(
      '[AgentApi] Agent client ${session.client.id} authenticated',
    );
    _publishControl();
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // Not available (e.g. tests); the version is informational.
    }
    final call = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final ssid = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    _reply(
      session.client,
      id,
      data: {
        'protocol': 2,
        'app': version,
        'station': ssid > 0 && call.isNotEmpty ? '$call-$ssid' : call,
        'hostTime': _now(),
        'radios': _radios(),
        'events': events.keys.toList(),
        'commands': commands.toList(),
        'settable': settableSettings.toList(),
        'allowTransmit': _allowTransmit,
        'txSecondsPerMinute': _txLimit,
        'readOnly': false,
      },
    );
  }

  void _subscribe(
    _AgentSession session,
    Object? id,
    Map<String, Object?> req, {
    required bool add,
  }) {
    final raw = req['events'];
    final names = raw is List ? raw.map((e) => e.toString()).toList() : null;
    if (names == null) {
      _reply(session.client, id, error: 'events must be a list');
      return;
    }
    final wanted = names.contains('*') ? events.keys.toList() : names;
    final unknown = wanted.where((n) => !events.containsKey(n)).toList();
    if (unknown.isNotEmpty) {
      _reply(
        session.client,
        id,
        error: 'unknown events $unknown; allowed: ${events.keys.join(', ')}',
      );
      return;
    }
    if (add) {
      session.events.addAll(wanted);
    } else {
      session.events.removeAll(wanted);
    }
    _reply(session.client, id, data: {'events': session.events.toList()});
  }

  void _packets(_AgentSession session, Object? id, Map<String, Object?> req) {
    final store = DataBroker.getDataHandler<PacketStore>('PacketStore');
    var packets = store?.getPackets() ?? const <TncDataFragment>[];
    final since = _parseTime(req['since']);
    if (since != null) {
      packets = packets.where((p) => p.time.isAfter(since)).toList();
    }
    final limit = _limit(req['limit'], 200, 2000);
    if (packets.length > limit) {
      packets = packets.sublist(packets.length - limit);
    }
    final details = req['details'] == true;
    _reply(
      session.client,
      id,
      data: {
        'packets': [for (final p in packets) packetJson(p, details: details)],
      },
    );
  }

  void _logs(_AgentSession session, Object? id, Map<String, Object?> req) {
    final stored = _broker.getValueDynamic(1, 'DebugLogEntries', null);
    final since = _parseTime(req['since']);
    final errorsOnly = req['level'] == 'error';
    final out = <Map<String, Object?>>[];
    if (stored is List) {
      for (final e in stored) {
        if (e is! Map) continue;
        final time = DateTime.tryParse(e['time']?.toString() ?? '');
        if (since != null && (time == null || !time.isAfter(since))) continue;
        final isError = e['isError'] == true;
        if (errorsOnly && !isError) continue;
        out.add({
          'time': time?.toUtc().toIso8601String(),
          'level': isError ? 'error' : 'info',
          'message': e['message']?.toString() ?? '',
        });
      }
    }
    final limit = _limit(req['limit'], 500, 5000);
    _reply(
      session.client,
      id,
      data: {
        'logs': out.length > limit ? out.sublist(out.length - limit) : out,
      },
    );
  }

  void _get(_AgentSession session, Object? id, Map<String, Object?> req) {
    final device = (req['device'] as num?)?.toInt();
    final name = req['name'];
    if (device == null || name is! String) {
      _reply(session.client, id, error: 'get needs device and name');
      return;
    }
    final allowed = switch (device) {
      0 => !isSecretSetting(name),
      1 => readableAppValues.contains(name),
      _ => device > 1 && readableRadioValues.contains(name),
    };
    if (!allowed) {
      _reply(session.client, id, error: 'value $device/$name is not readable');
      return;
    }
    _reply(
      session.client,
      id,
      data: {
        'device': device,
        'name': name,
        'value': jsonable(_broker.getValueDynamic(device, name, null)),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  void _onEvent(int deviceId, String name, Object? data) {
    if (name == 'HtStatus' && data is Map) {
      _meterTx(deviceId, data['isInTx'] == true);
    }
    if (name == 'LockState') _forgetReleasedLock(deviceId, data);
    if (_sessions.isEmpty || !enabled) return;
    final from = events[name];
    if (from == null || (from >= 0 && deviceId != from)) return;
    String? frame;
    for (final s in _sessions.values) {
      if (!s.authenticated || !s.events.contains(name)) continue;
      frame ??=
          prefix +
          jsonEncode({
            'event': name,
            'device': deviceId,
            'time': _now(),
            'data': jsonable(data, details: true),
          });
      s.client.sendText(frame);
    }
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  int get _allowTransmit => _broker.getValue<int>(0, 'AllowTransmit', 0) ?? 0;

  int get _txLimit =>
      (_broker.getValue<int>(0, txLimitSetting, defaultTxSecondsPerMinute) ??
              defaultTxSecondsPerMinute)
          .clamp(1, 60);

  void _command(_AgentSession session, Object? id, Map<String, Object?> req) {
    final name = (req['command'] ?? '').toString();
    final rawArgs = req['args'];
    final args = rawArgs is Map
        ? rawArgs.cast<String, Object?>()
        : <String, Object?>{};
    try {
      if (!commands.contains(name)) {
        throw _AgentError(
          'unknown command "$name"; allowed: ${commands.join(', ')}',
        );
      }
      if (transmitting.contains(name)) {
        if (_allowTransmit != 1) {
          throw _AgentError(
            'transmitting is not allowed on this station (AllowTransmit is off)',
          );
        }
        final radio = name == 'terminal.send'
            ? _agentTerminal(session)
            : _radio(args);
        final blocked = _txMeters[radio]?.blockedUntil;
        if (blocked != null && DateTime.now().isBefore(blocked)) {
          final left = blocked.difference(DateTime.now()).inSeconds + 1;
          throw _AgentError(
            'radio $radio hit the agent transmit limit; retry in $left s',
          );
        }
      }
      final result = switch (name) {
        'radio.lock' => _lock(session, args),
        'radio.unlock' => _unlock(args),
        'bbs.start' => _bbsStart(session, args),
        'bbs.stop' => _bbsStop(args),
        'xara.connect' => _xaraConnect(session, args),
        'xara.send' => _xaraSend(session, args),
        'xara.disconnect' => _xaraSimple(session, args, 'XaraDisconnect'),
        'xara.abort' => _xaraSimple(session, args, 'XaraAbort'),
        'terminal.connect' => _terminalConnect(session, args),
        'terminal.wait' => _terminalWait(session, args),
        'terminal.send' => _terminalSend(session, args),
        'terminal.disconnect' => _terminalSimple(session, 'TerminalDisconnect'),
        'terminal.abort' => _terminalSimple(session, 'TerminalAbort'),
        'packets.clear' => _packetsClear(),
        'setting.set' => _settingSet(args),
        _ => throw _AgentError('unhandled command "$name"'),
      };
      _broker.logInfo(
        '[AgentApi] Client ${session.client.id} ran $name ${jsonEncode(jsonable(args))}',
      );
      _publishControl();
      _ensureTxTimer();
      _reply(session.client, id, data: {'command': name, ...result});
    } on _AgentError catch (e) {
      _reply(session.client, id, error: e.message);
    }
  }

  /// The connected radio named by `args.radio`.
  int _radio(Map<String, Object?> args) {
    final r = args['radio'];
    if (r is! num) throw _AgentError('radio (device id) is required');
    final id = r.toInt();
    if (!_radios().any((x) => x['id'] == id)) {
      throw _AgentError('radio $id is not connected');
    }
    return id;
  }

  Map<Object?, Object?>? _lockState(int radio) {
    final v = _broker.getValueDynamic(radio, 'LockState', null);
    return v is Map && (v['isLocked'] ?? v['IsLocked']) == true ? v : null;
  }

  /// The usage under which an agent locked [radio], if any agent did.
  String? _agentLock(int radio) {
    for (final s in _sessions.values) {
      final u = s.locks[radio];
      if (u != null) return u;
    }
    return null;
  }

  bool _agentBbs(int radio) =>
      _sessions.values.any((s) => s.bbs.contains(radio));

  Map<String, Object?> _lock(_AgentSession session, Map<String, Object?> args) {
    final radio = _radio(args);
    final held = _lockState(radio);
    if (held != null) {
      throw _AgentError(
        'radio $radio is already locked for "${held['usage'] ?? held['Usage']}"',
      );
    }
    final usage = (args['usage'] ?? 'Agent').toString();
    if (!lockUsages.contains(usage)) {
      throw _AgentError('usage must be one of ${lockUsages.join(', ')}');
    }
    var channelId = -1;
    String? channelName;
    final ch = args['channel'];
    if (ch is num) {
      channelId = ch.toInt();
    } else if (ch is String && ch.isNotEmpty) {
      channelName = ch;
    }
    final region = _region(radio, args['region']);
    final modem = args['modem'];
    if (modem != null && (modem is! String || !lockModems.contains(modem))) {
      throw _AgentError('modem must be one of ${lockModems.join(', ')}');
    }
    final wide = args['xaraWide'];
    _broker.dispatch(
      deviceId: radio,
      name: 'SetLock',
      data: SetLockData(
        usage: usage,
        regionId: region,
        channelId: channelId,
        channelName: channelName,
        modem: modem as String?,
        xaraWide: wide is bool ? wide : null,
      ),
      store: false,
    );
    session.locks[radio] = usage;
    return {'radio': radio, 'usage': usage};
  }

  Map<String, Object?> _unlock(Map<String, Object?> args) {
    final radio = _radio(args);
    final usage = _agentLock(radio);
    if (usage == null) {
      throw _AgentError('radio $radio is not locked by an agent');
    }
    _releaseRadio(radio, bbs: false);
    return {'radio': radio};
  }

  /// Region index from a number or region name; -1 keeps the current region.
  int _region(int radio, Object? region) {
    if (region == null) return -1;
    if (region is num) return region.toInt();
    if (region is String) {
      if (region.isEmpty) return -1;
      final names = _broker.getValueDynamic(radio, 'RegionNames', null);
      final i = names is List ? names.indexOf(region) : -1;
      if (i < 0) throw _AgentError('unknown region "$region"');
      return i;
    }
    throw _AgentError('region must be a number or a name');
  }

  Map<String, Object?> _bbsStart(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _radio(args);
    final held = _lockState(radio);
    if (held != null) {
      throw _AgentError(
        'radio $radio is already locked for "${held['usage'] ?? held['Usage']}"',
      );
    }
    final ht = _broker.getValueDynamic(radio, 'HtStatus', null);
    final current = (ht is Map ? ht['currRegion'] as int? : null) ?? 0;
    final region = args['region'] == null
        ? current
        : _region(radio, args['region']);
    if (region != current) {
      throw _AgentError(
        'the BBS runs in the radio\'s current region ($current); '
        'switch region first',
      );
    }
    final channel = _bbsChannel(radio, args['channel']);
    _broker.dispatch(
      deviceId: 1,
      name: 'CreateBbs',
      data: CreateBbsData(
        radioDeviceId: radio,
        channelId: channel,
        regionId: region,
      ),
      store: false,
    );
    session.bbs.add(radio);
    return {'radio': radio, 'channel': channel, 'region': region};
  }

  /// BBS channel id from a number, a channel name in the current region, or
  /// (when omitted) the radio's current channel A.
  int _bbsChannel(int radio, Object? channel) {
    if (channel is num) return channel.toInt();
    if (channel is String && channel.isNotEmpty) {
      final list = _broker.getValueDynamic(radio, 'Channels', null);
      if (list is List) {
        for (var i = 0; i < list.length; i++) {
          final c = list[i];
          if (c is Map && c['name'] == channel) {
            return (c['channelId'] as int?) ?? i;
          }
        }
      }
      throw _AgentError('no channel "$channel" in the current region');
    }
    final settings = _broker.getValueDynamic(radio, 'Settings', null);
    return (settings is Map ? settings['channelA'] as int? : null) ?? 0;
  }

  Map<String, Object?> _bbsStop(Map<String, Object?> args) {
    final radio = _radio(args);
    if (!_agentBbs(radio)) {
      throw _AgentError('the BBS on radio $radio was not started by an agent');
    }
    _broker.dispatch(
      deviceId: 1,
      name: 'RemoveBbs',
      data: RemoveBbsData(radioDeviceId: radio),
      store: false,
    );
    for (final s in _sessions.values) {
      s.bbs.remove(radio);
    }
    return {'radio': radio};
  }

  /// XARA commands act only on radios an agent controls (its lock or BBS), so
  /// an agent cannot drive a link the operator or another feature started.
  void _requireAgentRadio(int radio) {
    if (_agentLock(radio) == null && !_agentBbs(radio)) {
      throw _AgentError(
        'radio $radio is not controlled by an agent; use radio.lock or '
        'bbs.start first',
      );
    }
  }

  Map<String, Object?> _xaraConnect(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _radio(args);
    _requireAgentRadio(radio);
    final remote = args['remote'];
    if (remote is! String || remote.trim().isEmpty) {
      throw _AgentError('remote callsign is required');
    }
    final rawVias = args['vias'];
    final vias = rawVias is List
        ? rawVias.map((v) => v.toString().trim().toUpperCase()).toList()
        : const <String>[];
    if (vias.length > 2) throw _AgentError('XARA allows at most 2 vias');
    final call = remote.trim().toUpperCase();
    _broker.dispatch(
      deviceId: radio,
      name: 'XaraConnect',
      data: <String, Object?>{'Remote': call, 'Vias': vias},
      store: false,
    );
    session.xara.add(radio);
    return {'radio': radio, 'remote': call, 'vias': vias};
  }

  Map<String, Object?> _xaraSend(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _radio(args);
    _requireAgentRadio(radio);
    final Uint8List bytes;
    if (args['text'] is String) {
      bytes = Uint8List.fromList(utf8.encode(args['text']! as String));
    } else if (args['hex'] is String) {
      final b = RadioUtils.hexStringToByteArray(args['hex']! as String);
      if (b == null) throw _AgentError('hex is not valid hexadecimal');
      bytes = b;
    } else {
      throw _AgentError('text or hex is required');
    }
    if (bytes.isEmpty || bytes.length > 65536) {
      throw _AgentError('send 1 to 65536 bytes');
    }
    _broker.dispatch(
      deviceId: radio,
      name: 'XaraSend',
      data: bytes,
      store: false,
    );
    session.xara.add(radio);
    return {'radio': radio, 'bytes': bytes.length};
  }

  Map<String, Object?> _xaraSimple(
    _AgentSession session,
    Map<String, Object?> args,
    String event,
  ) {
    final radio = _radio(args);
    _requireAgentRadio(radio);
    _broker.dispatch(deviceId: radio, name: event, data: null, store: false);
    return {'radio': radio};
  }

  // ---------------------------------------------------------------------------
  // Terminal (the host's headless TerminalHandler)
  // ---------------------------------------------------------------------------

  Map<Object?, Object?> get _terminalState {
    final v = _broker.getValueDynamic(1, 'TerminalState', null);
    return v is Map ? v : const <Object?, Object?>{};
  }

  /// The radio the host terminal is using, or null when it is idle.
  int? get _terminalRadio {
    final s = _terminalState;
    if ((s['status'] ?? 'idle') == 'idle') return null;
    final r = s['radioId'];
    return r is num && r > 0 ? r.toInt() : -1;
  }

  /// The radio of the terminal link [session] started.
  int _agentTerminal(_AgentSession session) {
    final radio = session.terminal;
    if (radio == null || _terminalRadio == null) {
      throw _AgentError(
        'the terminal is not in use by this agent; terminal.connect first',
      );
    }
    return radio;
  }

  /// The terminal must be idle and [radio] free before an agent uses it.
  void _requireTerminalFree(int radio) {
    final s = _terminalState;
    if ((s['status'] ?? 'idle') != 'idle') {
      throw _AgentError(
        'the terminal is busy (${s['status']} with ${s['remote'] ?? s['station']?.toString() ?? 'another station'})',
      );
    }
    final held = _lockState(radio);
    if (held != null) {
      throw _AgentError(
        'radio $radio is already locked for "${held['usage'] ?? held['Usage']}"',
      );
    }
  }

  /// Terminal contacts in the address book (device-0 `Stations`).
  List<StationInfo> _terminalContacts() {
    final list = _broker.getValueDynamic(0, 'Stations', null);
    final out = <StationInfo>[];
    if (list is! List) return out;
    for (final e in list) {
      StationInfo? s;
      if (e is StationInfo) {
        s = e;
      } else if (e is Map) {
        try {
          s = StationInfo.fromJson(e.cast<String, dynamic>());
        } catch (_) {}
      }
      if (s != null && s.stationType == StationType.terminal) out.add(s);
    }
    return out;
  }

  Map<String, Object?> _terminalConnect(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _radio(args);
    _requireTerminalFree(radio);
    final StationInfo station;
    final contact = args['contact'];
    final raw = args['station'];
    if (contact is String && contact.trim().isNotEmpty) {
      final call = contact.trim().toUpperCase();
      final contacts = _terminalContacts();
      final match = contacts.where((s) => s.callsign.toUpperCase() == call);
      if (match.isEmpty) {
        throw _AgentError(
          'no terminal contact "$call"; known: '
          '${contacts.map((s) => s.callsign).join(', ')}',
        );
      }
      station = match.first;
    } else if (raw is Map) {
      try {
        station = StationInfo.fromJson(raw.cast<String, dynamic>());
      } catch (e) {
        throw _AgentError('station is not a valid station: $e');
      }
      station.stationType = StationType.terminal;
      if (station.callsign.trim().isEmpty) {
        throw _AgentError('station callsign is required');
      }
    } else {
      throw _AgentError(
        'contact (terminal contact callsign) or station (json) is required',
      );
    }
    session.terminal = radio;
    _lastTerminalNotice = null;
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalConnect',
      data: <String, Object?>{'RadioId': radio, 'Station': station.toJson()},
      store: false,
    );
    _requireTerminalStarted(session, radio);
    return {
      'radio': radio,
      'remote': station.callsign,
      'protocol': station.terminalProtocol.name,
      'state': jsonable(_terminalState),
    };
  }

  /// Fails the command when the terminal refused to start (it stayed idle),
  /// reporting the handler's notice (e.g. a missing channel or region).
  void _requireTerminalStarted(_AgentSession session, int radio) {
    if (_terminalRadio != null) {
      session.terminal = radio;
      return;
    }
    session.terminal = null;
    final n = _lastTerminalNotice;
    throw _AgentError(
      'the terminal did not start'
      '${n == null ? '' : ': ${jsonEncode(jsonable(n))}'}',
    );
  }

  Map<String, Object?> _terminalWait(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _radio(args);
    _requireTerminalFree(radio);
    session.terminal = radio;
    _lastTerminalNotice = null;
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalWait',
      data: <String, Object?>{'RadioId': radio},
      store: false,
    );
    _requireTerminalStarted(session, radio);
    return {'radio': radio, 'state': jsonable(_terminalState)};
  }

  Map<String, Object?> _terminalSend(
    _AgentSession session,
    Map<String, Object?> args,
  ) {
    final radio = _agentTerminal(session);
    final text = args['text'];
    if (text is! String || text.isEmpty || text.length > 65536) {
      throw _AgentError('text (1 to 65536 characters) is required');
    }
    if (_terminalState['canSend'] != true) {
      throw _AgentError(
        'the terminal cannot send yet (${_terminalState['status']})',
      );
    }
    _broker.dispatch(
      deviceId: 1,
      name: 'TerminalSend',
      data: <String, Object?>{'Text': text},
      store: false,
    );
    return {'radio': radio, 'chars': text.length};
  }

  Map<String, Object?> _terminalSimple(_AgentSession session, String event) {
    final radio = _agentTerminal(session);
    _broker.dispatch(deviceId: 1, name: event, data: null, store: false);
    return {'radio': radio, 'state': jsonable(_terminalState)};
  }

  Map<String, Object?> _packetsClear() {
    _broker.dispatch(
      deviceId: 1,
      name: 'ClearPackets',
      data: null,
      store: false,
    );
    return const {};
  }

  Map<String, Object?> _settingSet(Map<String, Object?> args) {
    final name = args['name'];
    if (name is! String || !settableSettings.contains(name)) {
      throw _AgentError(
        'setting must be one of ${settableSettings.join(', ')}',
      );
    }
    final value = args['value'];
    if (value == null) throw _AgentError('value is required');
    final command = HostBridge.modemSettingCommands[name];
    if (command != null) {
      _broker.dispatch(deviceId: 0, name: command, data: value, store: false);
    } else {
      _broker.dispatch(deviceId: 0, name: name, data: value);
    }
    return {'name': name, 'value': value};
  }

  // ---------------------------------------------------------------------------
  // Release, stop and the transmit limit
  // ---------------------------------------------------------------------------

  /// Releases everything [s] holds; returns what was released.
  List<String> _release(_AgentSession s) {
    final radios = <int>{
      ...s.xara,
      ...s.bbs,
      ...s.locks.keys,
      if (s.terminal != null) s.terminal!,
    };
    final done = <String>[];
    for (final r in radios) {
      done.addAll(_releaseRadio(r, only: s));
    }
    return done;
  }

  /// Ends agent activity on [radio]: aborts XARA, stops an agent BBS (unless
  /// [bbs] is false) and removes agent locks. Limited to session [only] when
  /// given, otherwise applies to every session.
  List<String> _releaseRadio(
    int radio, {
    _AgentSession? only,
    bool bbs = true,
  }) {
    final done = <String>[];
    final sessions = only != null ? [only] : _sessions.values.toList();
    var abort = false;
    for (final s in sessions) {
      if (s.terminal == radio) {
        s.terminal = null;
        if (_terminalRadio != null) {
          _broker.dispatch(
            deviceId: 1,
            name: 'TerminalAbort',
            data: null,
            store: false,
          );
          done.add('stopped terminal on radio $radio');
        }
      }
      if (s.xara.remove(radio)) abort = true;
      final usage = s.locks.remove(radio);
      if (usage != null) {
        abort = true;
        _broker.dispatch(
          deviceId: radio,
          name: 'XaraAbort',
          data: null,
          store: false,
        );
        _broker.dispatch(
          deviceId: radio,
          name: 'SetUnlock',
          data: SetUnlockData(usage: usage),
          store: false,
        );
        done.add('unlocked radio $radio');
      }
      if (bbs && s.bbs.remove(radio)) {
        _broker.dispatch(
          deviceId: 1,
          name: 'RemoveBbs',
          data: RemoveBbsData(radioDeviceId: radio),
          store: false,
        );
        done.add('stopped BBS on radio $radio');
      }
    }
    if (abort && !done.contains('unlocked radio $radio')) {
      _broker.dispatch(
        deviceId: radio,
        name: 'XaraAbort',
        data: null,
        store: false,
      );
      done.add('aborted XARA on radio $radio');
    }
    return done;
  }

  /// Stops every agent. When [notify], each authenticated agent first gets an
  /// `AgentStopped` event; when [drop], sessions are discarded so agents must
  /// authenticate again.
  List<String> _stopAll(
    String reason, {
    bool notify = true,
    bool drop = false,
  }) {
    final done = <String>[];
    for (final s in _sessions.values) {
      if (notify && s.authenticated) {
        s.client.sendText(
          prefix +
              jsonEncode({
                'event': 'AgentStopped',
                'time': _now(),
                'data': {'reason': reason},
              }),
        );
      }
      done.addAll(_release(s));
    }
    if (drop) _sessions.clear();
    _broker.logInfo('[AgentApi] Agents stopped ($reason); released $done');
    _publishControl();
    return done;
  }

  /// Drops agent locks that something else released (e.g. the operator).
  void _forgetReleasedLock(int radio, Object? lock) {
    final locked =
        lock is Map && (lock['isLocked'] ?? lock['IsLocked']) == true;
    if (locked) return;
    var changed = false;
    for (final s in _sessions.values) {
      if (s.locks.remove(radio) != null) changed = true;
    }
    if (changed) _publishControl();
  }

  /// Radios any agent currently holds.
  Set<int> get _agentRadios => <int>{
    for (final s in _sessions.values) ...s.xara,
    for (final s in _sessions.values) ...s.bbs,
    for (final s in _sessions.values) ...s.locks.keys,
    for (final s in _sessions.values)
      if (s.terminal != null) s.terminal!,
  };

  void _meterTx(int radio, bool inTx) {
    final m = _txMeters.putIfAbsent(radio, _TxMeter.new);
    final now = DateTime.now();
    if (inTx && m.since == null) {
      m.since = now;
    } else if (!inTx && m.since != null) {
      m.spans.add((m.since!, now));
      m.since = null;
    }
    _checkTx(radio, now);
  }

  void _ensureTxTimer() {
    if (_agentRadios.isEmpty) {
      _txTimer?.cancel();
      _txTimer = null;
      return;
    }
    _txTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      for (final r in _agentRadios.toList()) {
        _checkTx(r, now);
      }
      if (_agentRadios.isEmpty) {
        _txTimer?.cancel();
        _txTimer = null;
      }
    });
  }

  /// Seconds [radio] transmitted in the last minute, counting an ongoing burst.
  double transmitSeconds(int radio, [DateTime? at]) =>
      _txMeters[radio]?.seconds(at ?? DateTime.now()) ?? 0;

  void _checkTx(int radio, DateTime now) {
    if (!_agentRadios.contains(radio)) return;
    final m = _txMeters[radio];
    if (m == null) return;
    final used = m.seconds(now);
    final limit = _txLimit;
    if (used <= limit) return;
    m.blockedUntil = now.add(txCooldown);
    final done = _releaseRadio(radio);
    final message =
        'radio $radio transmitted ${used.toStringAsFixed(1)} s in the last '
        'minute (limit $limit s); released $done';
    _broker.logError('[AgentApi] Transmit limit: $message');
    for (final s in _sessions.values.where((s) => s.authenticated)) {
      s.client.sendText(
        prefix +
            jsonEncode({
              'event': 'AgentLimit',
              'device': radio,
              'time': _now(),
              'data': {
                'radio': radio,
                'seconds': double.parse(used.toStringAsFixed(1)),
                'limit': limit,
                'cooldownSeconds': txCooldown.inSeconds,
              },
            }),
      );
    }
    _publishControl();
  }

  /// Publishes `AgentControl` (device 1) for the UI's agent-control indicator.
  void _publishControl() {
    final clients = _sessions.values.where((s) => s.authenticated).length;
    final radios = _agentRadios.toList()..sort();
    _broker.dispatch(
      deviceId: 1,
      name: controlValue,
      data: <String, Object?>{
        'active': clients > 0,
        'clients': clients,
        'radios': radios,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  /// A captured packet as the agent sees it: the same summary, modem label,
  /// over-the-air bytes and (optionally) decode sections as the packet tab.
  static Map<String, Object?> packetJson(
    TncDataFragment f, {
    bool details = false,
  }) {
    return {
      'time': f.time.toUtc().toIso8601String(),
      'incoming': f.incoming,
      'radio': f.radioDeviceId,
      'radioMac': f.radioMac,
      'channel': f.channelName,
      'channelId': f.channelId,
      'regionId': f.regionId,
      'usage': f.usage,
      'frameType': f.frameType.name,
      'encoding': PacketDecoder.encodingLabel(f),
      'summary': PacketDecoder.fragmentToShortString(f),
      'hex': RadioUtils.bytesToHex(PacketDecoder.frameBytes(f)),
      if (details)
        'decode': [
          for (final s in PacketDecoder.decode(f))
            {
              'title': s.title,
              'lines': {for (final l in s.lines) l.key: l.value},
            },
        ],
    };
  }

  /// Converts a broker value to plain JSON: known payload types become maps,
  /// bytes become hex, and anything else falls back to `toJson()` or text.
  static Object? jsonable(Object? v, {bool details = false}) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is TncDataFragment) return packetJson(v, details: details);
    if (v is Uint8List) return RadioUtils.bytesToHex(v);
    if (v is BbsTrafficData) {
      return {
        'deviceId': v.deviceId,
        'callsign': v.callsign,
        'outgoing': v.outgoing,
        'message': v.message,
      };
    }
    if (v is BbsControlMessageData) {
      return {'deviceId': v.deviceId, 'message': v.message};
    }
    if (v is BbsErrorEventData) {
      return {'deviceId': v.deviceId, 'error': v.error};
    }
    if (v is Map) {
      return {
        for (final e in v.entries)
          e.key.toString(): jsonable(e.value, details: details),
      };
    }
    if (v is Iterable) {
      return [for (final e in v) jsonable(e, details: details)];
    }
    try {
      return jsonable((v as dynamic).toJson(), details: details);
    } catch (_) {
      return v.toString();
    }
  }

  List<Map<String, Object?>> _radios() {
    final raw = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    final out = <Map<String, Object?>>[];
    if (raw is! List) return out;
    for (final r in raw) {
      if (r is! Map) continue;
      final id = (r['DeviceId'] ?? r['deviceId']) as int?;
      if (id == null) continue;
      out.add({
        'id': id,
        'name':
            _broker.getValue<String>(id, 'FriendlyName', '') ??
            (r['FriendlyName'] ?? '').toString(),
        'state': jsonable(_broker.getValueDynamic(id, 'State', null)),
      });
    }
    return out;
  }

  void _reply(
    WebSocketClient client,
    Object? id, {
    Map<String, Object?>? data,
    String? error,
  }) {
    final body = <String, Object?>{
      'id': ?id,
      'ok': error == null,
      'error': ?error,
      ...?data,
    };
    client.sendText(prefix + jsonEncode(body));
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static DateTime? _parseTime(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static int _limit(Object? v, int fallback, int max) {
    final n = (v as num?)?.toInt() ?? fallback;
    return n.clamp(1, max);
  }

  /// Constant-time comparison so response timing does not leak the token.
  static bool _sameToken(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < max(x.length, y.length); i++) {
      diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
    }
    return diff == 0;
  }
}

class _AgentSession {
  _AgentSession(this.client);

  final WebSocketClient client;
  bool authenticated = false;
  int failures = 0;
  final Set<String> events = <String>{};

  /// Radios this agent locked, with the lock usage.
  final Map<int, String> locks = <int, String>{};

  /// Radios on which this agent started a BBS.
  final Set<int> bbs = <int>{};

  /// Radios on which this agent drove XARA.
  final Set<int> xara = <int>{};

  /// Radio of the host terminal link this agent started, if any.
  int? terminal;
}

/// Transmit time of one radio, from its `isInTx` status.
class _TxMeter {
  DateTime? since;
  final List<(DateTime, DateTime)> spans = <(DateTime, DateTime)>[];
  DateTime? blockedUntil;

  double seconds(DateTime now) {
    final from = now.subtract(const Duration(minutes: 1));
    spans.removeWhere((s) => !s.$2.isAfter(from));
    var us = 0;
    for (final (a, b) in spans) {
      us += b.difference(a.isBefore(from) ? from : a).inMicroseconds;
    }
    final s = since;
    if (s != null) {
      us += now.difference(s.isBefore(from) ? from : s).inMicroseconds;
    }
    return us / 1e6;
  }
}

class _AgentError implements Exception {
  _AgentError(this.message);
  final String message;
}
