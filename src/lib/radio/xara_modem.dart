/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Runs the pure-Dart XARA FM modem (VARA FM compatible) in a background isolate.
The isolate owns an FmStation behind an XaraDriver, advances it on a 10 ms wall
clock, and exchanges 32 kHz PCM16 audio, commands and events with the host.
*/

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../hamlib/xara/arq_host.dart';
import '../hamlib/xara/ax25.dart' as ax25;
import '../hamlib/xara/complex.dart';
import '../hamlib/xara/compression.dart';
import '../hamlib/xara/fm_constellation.dart';
import '../hamlib/xara/fm_level.dart';
import '../hamlib/xara/fm_rx.dart' show FmFrameRx;
import '../hamlib/xara/fm_rx_frontend.dart' show fs6;
import '../hamlib/xara/fm_session.dart' show FmConfig;
import '../hamlib/xara/fm_station.dart';
import '../hamlib/xara/kiss_command.dart';
import '../hamlib/xara/station.dart';
import '../hamlib/xara/xara_driver.dart';

/// Configuration for one XARA modem instance.
class XaraModemConfig {
  /// Default silence sent before each burst so the radio can key up and the far
  /// squelch can open before the XARA lead-in starts. Slower radios may need more.
  static const int defaultTxKeyUpMs = 100;

  /// Default delay from PCM handed to the radio until the far station hears it,
  /// on top of [defaultTxKeyUpMs] (which the modem adds itself). Over-estimating
  /// is harmless while under-estimating drops ARQ replies as late, so this is
  /// set to cover Bluetooth HT paths of up to about 1 s.
  static const int defaultTxLatencyMs = 800;

  final String callsign;

  /// Extra callsigns (e.g. `CALL-SSID`) this station also answers connects for.
  final List<String> aliases;
  final bool wide;
  final bool registered;
  final int txLatencyMs;
  final int txKeyUpMs;
  final double driveDb;
  final int sampleRate;
  final bool analysis;

  const XaraModemConfig({
    required this.callsign,
    this.aliases = const <String>[],
    this.wide = false,
    this.registered = false,
    this.txLatencyMs = defaultTxLatencyMs,
    this.txKeyUpMs = defaultTxKeyUpMs,
    this.driveDb = defaultDriveDb,
    this.sampleRate = 32000,
    this.analysis = false,
  });

  Map<String, Object?> toMap() => <String, Object?>{
        'callsign': callsign,
        'aliases': aliases,
        'wide': wide,
        'registered': registered,
        'txLatencyMs': txLatencyMs,
        'txKeyUpMs': txKeyUpMs,
        'driveDb': driveDb,
        'sampleRate': sampleRate,
        'analysis': analysis,
      };

  static XaraModemConfig fromMap(Map<Object?, Object?> m) => XaraModemConfig(
        callsign: (m['callsign'] as String?) ?? '',
        aliases: ((m['aliases'] as List?) ?? const <Object?>[]).cast<String>(),
        wide: (m['wide'] as bool?) ?? false,
        registered: (m['registered'] as bool?) ?? false,
        txLatencyMs: (m['txLatencyMs'] as int?) ?? defaultTxLatencyMs,
        txKeyUpMs: (m['txKeyUpMs'] as int?) ?? defaultTxKeyUpMs,
        driveDb: (m['driveDb'] as num?)?.toDouble() ?? defaultDriveDb,
        sampleRate: (m['sampleRate'] as int?) ?? 32000,
        analysis: (m['analysis'] as bool?) ?? false,
      );
}

/// Host-side handle. Events are delivered as plain maps (see [xaraReportToMap]).
class XaraModem {
  final XaraModemConfig config;
  final void Function(Uint8List pcm) onTransmit;
  final void Function(Map<String, Object?> event) onEvent;

  SendPort? _port;
  ReceivePort? _receive;
  Isolate? _isolate;
  final List<Map<String, Object?>> _backlog = <Map<String, Object?>>[];
  bool _disposed = false;

  XaraModem({required this.config, required this.onTransmit, required this.onEvent}) {
    unawaited(_start());
  }

  Future<void> _start() async {
    final ReceivePort rp = ReceivePort();
    _receive = rp;
    rp.listen(_onMessage);
    final isolate = await Isolate.spawn(
      _xaraIsolateEntry,
      <Object?>[rp.sendPort, config.toMap()],
      debugName: 'xara-modem',
    );
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
    } else {
      _isolate = isolate;
    }
  }

  void _onMessage(Object? message) {
    if (_disposed) return;
    if (message is SendPort) {
      _port = message;
      for (final Map<String, Object?> m in _backlog) {
        message.send(m);
      }
      _backlog.clear();
      return;
    }
    if (message is! Map) return;
    if (message['evt'] == 'tx') {
      final Object? pcm = message['pcm'];
      if (pcm is TransferableTypedData) onTransmit(pcm.materialize().asUint8List());
      return;
    }
    onEvent(message.cast<String, Object?>());
  }

  void _send(Map<String, Object?> m) {
    if (_disposed) return;
    final SendPort? p = _port;
    if (p == null) {
      _backlog.add(m);
    } else {
      p.send(m);
    }
  }

  /// Feeds received 16-bit little-endian mono PCM at the configured sample rate.
  void pushRx(Uint8List data, int offset, int length) {
    _send(<String, Object?>{
      'cmd': 'rx',
      'pcm': TransferableTypedData.fromList(<Uint8List>[Uint8List.sublistView(data, offset, offset + length)]),
    });
  }

  void connect(String remote, List<String> vias) =>
      _send(<String, Object?>{'cmd': 'connect', 'remote': remote, 'vias': vias});

  void send(Uint8List data) => _send(<String, Object?>{'cmd': 'send', 'data': data});

  void disconnect() => _send(<String, Object?>{'cmd': 'disconnect'});

  void abort() => _send(<String, Object?>{'cmd': 'abort'});

  /// Sends an AX.25 frame as an unconnected VARA FM (record 16) broadcast.
  void kiss(Uint8List frame) => _send(<String, Object?>{'cmd': 'kiss', 'data': frame});

  void cq(String call) => _send(<String, Object?>{'cmd': 'cq', 'call': call});

  void setListen(bool on) => _send(<String, Object?>{'cmd': 'listen', 'on': on});

  /// Tells the modem whether the radio is receiving (streaming RX audio). While
  /// on, XARA holds back the start of any transmission.
  void setRadioReceiving(bool on) => _send(<String, Object?>{'cmd': 'carrier', 'on': on});

  /// Turns per-frame constellation capture ('analysis' events) on or off.
  void setAnalysis(bool on) => _send(<String, Object?>{'cmd': 'analysis', 'on': on});

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
    _backlog.clear();
    _receive?.close();
    _receive = null;
  }
}

/// Converts a station report into a sendable map, or null for reports the host ignores.
Map<String, Object?>? xaraReportToMap(Report r) {
  switch (r) {
    case ReportPtt(:final bool on):
      return <String, Object?>{'evt': 'ptt', 'on': on};
    case ReportBusy(:final bool on):
      return <String, Object?>{'evt': 'busy', 'on': on};
    case ReportBitrate(:final int level, :final int bps, :final bool tx):
      return <String, Object?>{'evt': 'bitrate', 'level': level, 'bps': bps, 'tx': tx};
    case ReportTrace(:final String text):
      return <String, Object?>{'evt': 'log', 'text': text};
    case ReportLine(:final String text):
      return <String, Object?>{'evt': 'line', 'text': text};
    case ReportKiss(:final KissCommand cmd, :final Uint8List data):
      return <String, Object?>{'evt': 'kiss', 'cmd': cmd.byte, 'data': data};
    case ReportUnencryptedLink():
      return null;
    case ReportHost(:final HostEvent event):
      return switch (event) {
        HostData(:final Uint8List data) => <String, Object?>{'evt': 'data', 'data': data},
        HostConnected(:final String caller, :final String answerer, :final List<String> vias, :final LinkBw bw) =>
          <String, Object?>{
            'evt': 'connected',
            'caller': caller,
            'answerer': answerer,
            'vias': vias,
            'wide': bw == const LinkBwFm(FmBandwidth.wide),
          },
        HostSn(:final double db) => <String, Object?>{'evt': 'snr', 'db': db},
        HostBuffer(:final int n) => <String, Object?>{'evt': 'buffer', 'bytes': n},
        HostRegistered(:final bool on) => <String, Object?>{'evt': 'registered', 'on': on},
        HostLog(:final String text) => <String, Object?>{'evt': 'log', 'text': text},
        _ when event == hostDisconnected => <String, Object?>{'evt': 'disconnected'},
        _ when event == hostTimedOut => <String, Object?>{'evt': 'timedOut'},
        _ when event == hostUnableToConnect => <String, Object?>{'evt': 'unableToConnect'},
        _ when event == hostPending => <String, Object?>{'evt': 'pending'},
        _ when event == hostCancelPending => <String, Object?>{'evt': 'cancelPending'},
        _ => null,
      };
  }
}

const List<String> _modulationNames = <String>['', 'BPSK', '4-DPSK', '8PSK', '16QAM', '32QAM', '64QAM', '128QAM', '256QAM'];
const int _maxPlotSymbols = 2000;

/// Builds an 'analysis' event (constellation + quality) for one received frame.
Map<String, Object?> xaraAnalysisToMap(FmFrameRx f, FmLevel level) {
  final List<Cx> ref = fmConstellation(f.bps);
  final List<Cx> syms = f.symbols ?? const <Cx>[];
  double err = 0.0, pow = 0.0;
  for (final Cx z in syms) {
    double best = double.infinity;
    for (final Cx p in ref) {
      final double d = (z - p).normSqr;
      if (d < best) best = d;
    }
    err += best;
  }
  for (final Cx p in ref) {
    pow += p.normSqr;
  }
  final double evm = syms.isEmpty || ref.isEmpty
      ? 0.0
      : 100.0 * math.sqrt((err / syms.length) / (pow / ref.length));
  final int stride = (syms.length + _maxPlotSymbols - 1) ~/ _maxPlotSymbols;
  final List<double> rxI = <double>[], rxQ = <double>[];
  for (int i = 0; i < syms.length; i += stride) {
    rxI.add(syms[i].re);
    rxQ.add(syms[i].im);
  }
  final String mod = f.bps < _modulationNames.length ? _modulationNames[f.bps] : '${f.bps} bps';
  return <String, Object?>{
    'evt': 'analysis',
    'protocol': 'XARA',
    'mode': f.record.index,
    'modeDesc': '$mod, ${level.nc} carriers, ${level.bw.name}, ${level.netBps.round()} bps',
    'crcOk': f.ok,
    'evm': evm,
    'snr': f.snrDb,
    'coherence': f.coherence,
    'iterations': f.iterations,
    'payloadLen': f.bytes.length,
    'durationMs': (f.tEnd - f.t) * 1000.0 / fs6,
    'rxI': rxI,
    'rxQ': rxQ,
    'refI': <double>[for (final Cx p in ref) p.re],
    'refQ': <double>[for (final Cx p in ref) p.im],
  };
}

Future<void> _xaraIsolateEntry(List<Object?> args) async {
  final SendPort host = args[0] as SendPort;
  final XaraModemConfig cfg = XaraModemConfig.fromMap(args[1] as Map<Object?, Object?>);
  final ReceivePort commands = ReceivePort();
  final int keyUp = math.max(0, cfg.txKeyUpMs) * stationRate ~/ 1000;

  final FmConfig fc = FmConfig(cfg.wide ? FmBandwidth.wide : FmBandwidth.narrow, cfg.callsign);
  for (final String a in cfg.aliases) {
    if (a.isNotEmpty && !fc.host.mycalls.contains(a)) fc.host.mycalls.add(a);
  }
  fc.host.registered = cfg.registered;
  fc.host.compression = Compression.text;
  fc.seed = DateTime.now().microsecondsSinceEpoch;
  // The driver leads every burst with [keyUp] of silence, so the frame content
  // reaches the air that much later than the station renders it. The station's
  // latency must include it, or its reply windows and transmit holds run early
  // and replies are dropped once the radio path adds a few hundred ms more.
  final FmStation station = FmStation(
    fc,
    StationOptions(driveDb: cfg.driveDb, txLatency: cfg.txLatencyMs * stationRate ~/ 1000 + keyUp),
  );
  final XaraDriver driver = XaraDriver(station, hostRate: cfg.sampleRate, keyUp: keyUp);
  station.setKissRx(true);
  station.captureSymbols = cfg.analysis;
  station.logFrames = true;
  final Stopwatch clock = Stopwatch()..start();
  int wall() => clock.elapsedMicroseconds * stationRate ~/ 1000000;
  String state = '';
  // True from a local 'connect' until that attempt resolves, so links can be
  // reported as dialed by us or answered (incoming).
  bool dialing = false;

  void flush() {
    while (true) {
      final Report? r = driver.pop();
      if (r == null) break;
      final Map<String, Object?>? m = xaraReportToMap(r);
      if (m == null) continue;
      switch (m['evt']) {
        case 'connected':
          m['incoming'] = !dialing;
          dialing = false;
        case 'disconnected' || 'timedOut' || 'unableToConnect':
          dialing = false;
      }
      host.send(m);
    }
    for (final StationFrame f in station.takeFrames()) {
      host.send(<String, Object?>{
        'evt': 'frame',
        'tx': f.tx,
        'record': f.record,
        'code': f.code,
        'ok': f.ok,
        'data': f.bytes,
        'meta': f.meta,
      });
    }
    for (final FmFrameRx f in station.takeCaptured()) {
      if (f.symbols != null) host.send(xaraAnalysisToMap(f, station.rxLevel(f.record)));
    }
    final StationLink l = station.link();
    final String s = '${l.state}|${l.level}|${l.peer}|${l.bw}';
    if (s != state) {
      state = s;
      host.send(<String, Object?>{'evt': 'state', 'state': l.state, 'level': l.level, 'peer': l.peer, 'bw': l.bw});
    }
  }

  void tick() {
    for (final Int16List b in driver.tick(wall())) {
      host.send(<String, Object?>{'evt': 'tx', 'pcm': TransferableTypedData.fromList(<TypedData>[b])});
    }
    flush();
  }

  final Timer timer = Timer.periodic(const Duration(milliseconds: 10), (_) => tick());
  host.send(commands.sendPort);

  await for (final Object? message in commands) {
    if (message is! Map) continue;
    switch (message['cmd']) {
      case 'rx':
        final Uint8List b = (message['pcm'] as TransferableTypedData).materialize().asUint8List();
        driver.pushRx(Int16List.view(b.buffer, b.offsetInBytes, b.lengthInBytes ~/ 2), wall());
      case 'connect':
        dialing = true;
        final bool ok = station.connect(
            cfg.callsign, message['remote'] as String, (message['vias'] as List).cast<String>());
        if (!ok) {
          dialing = false;
          host.send(<String, Object?>{'evt': 'unableToConnect'});
        }
      case 'send':
        station.send(message['data'] as Uint8List);
      case 'disconnect':
        station.disconnect();
      case 'abort':
        station.abort();
      case 'kiss':
        final Uint8List f = message['data'] as Uint8List;
        KissCommand cmd = KissCommand.ax25;
        try {
          ax25.encode(f, cmd);
        } on ax25.Ax25Error {
          cmd = KissCommand.generic;
        }
        if (!station.kiss(cmd, f)) host.send(<String, Object?>{'evt': 'log', 'text': 'KISS queue full'});
      case 'cq':
        station.cqFrame(message['call'] as String, null);
      case 'listen':
        station.setListen(message['on'] as bool);
      case 'carrier':
        station.txBlocked = message['on'] as bool;
      case 'analysis':
        station.captureSymbols = message['on'] as bool;
      case 'shutdown':
        timer.cancel();
        commands.close();
    }
    flush();
  }
  Isolate.exit();
}
