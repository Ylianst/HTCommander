import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../file_transfer/file_transfer_engine.dart';
import '../file_transfer/pacsat.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

class FileTransferHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  late final FileTransferEngine _engine;
  Directory? _directory;
  Timer? _timer;
  bool _dirty = false;
  bool _saving = false;
  Completer<void>? _saveDone;
  bool _lastSaveSucceeded = true;
  bool _disposed = false;
  final Map<String, String> _reportedErrors = {};
  final Map<String, DateTime> _duplicates = {};
  final Map<String, bool> _submissionResults = {};

  Future<void> init() async {
    if (kIsWeb) return;
    _engine = FileTransferEngine(
      send: _send,
      available: _available,
      cancelPackets: _cancelPackets,
      changed: _changed,
      receivedFile: _saveReceived,
    );
    try {
      final base = await getApplicationSupportDirectory();
      _directory = await Directory(
        '${base.path}${Platform.pathSeparator}file-transfers',
      ).create(recursive: true);
      final manifest = File(
        '${_directory!.path}${Platform.pathSeparator}transfers.json',
      );
      if (await manifest.exists()) {
        if (await manifest.length() > 32000000) {
          throw const FormatException('Transfer archive exceeds 32 MB');
        }
        final stored = jsonDecode(await manifest.readAsString()) as List;
        if (stored.length > 100) {
          throw const FormatException('Too many stored transfers');
        }
        for (final row in stored) {
          _engine.transfers.add(
            FileTransfer.restore(Map<String, dynamic>.from(row as Map)),
          );
        }
      }
    } on FileSystemException catch (e) {
      _directory = null;
      _error('File transfer storage: ${e.message}');
    } on FormatException catch (e) {
      _directory = null;
      _error('File transfer storage: ${e.message}');
    } on TypeError catch (e) {
      _directory = null;
      _error('Invalid file transfer archive: $e');
    }
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'DataFrame',
      callback: _onFrame,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'FileTransmitResult',
      callback: (_, _, data) {
        if (data is Map && data['tag'] is String && data['accepted'] is bool) {
          _submissionResults[data['tag'] as String] = data['accepted'] as bool;
        }
      },
    );
    _broker.subscribe(deviceId: 1, name: 'FileTransferSend', callback: _onSend);
    _broker.subscribe(
      deviceId: 1,
      name: 'FileTransferAction',
      callback: _onAction,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'ClearVoiceText',
      callback: (_, _, _) {
        _engine.transfers.removeWhere((t) => t.terminal);
        _changed();
      },
    );
    _changed();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      for (final t in _engine.transfers) {
        final radio = _connected(t.link.deviceId, t.link.radioMac);
        if (radio?['DeviceId'] is! int) continue;
        final status = _broker.getValueDynamic(radio!['DeviceId'] as int, 'HtStatus');
        if (status is Map && (status['isInTx'] == true ||
            status['isInRx'] == true || (status['rssi'] as int? ?? 0) != 0)) {
          _engine.busy(t.link, DateTime.now());
        }
      }
      _engine.tick(DateTime.now());
      if (_dirty && !_saving) unawaited(_persist());
    });
  }

  String get _local => normalizeFileCallsign(
    '${_broker.getValue<String>(0, 'CallSign', '') ?? ''}'
    '-${_broker.getValue<int>(0, 'StationId', 0) ?? 0}',
  );

  Map? _connected(int id, [String? mac]) {
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (radios is! List) return null;
    for (final value in radios) {
      if (value is Map &&
          (mac != null
              ? value['MacAddress'] == mac
              : value['DeviceId'] == id)) {
        return value;
      }
    }
    return null;
  }

  Map? _channel(int id, int channelId) {
    final channels = _broker.getValueDynamic(id, 'Channels');
    if (channels is! List) return null;
    for (final channel in channels) {
      if (channel is Map && channel['channelId'] == channelId) return channel;
    }
    return null;
  }

  FileTransferLink _link(int id, {TncDataFragment? frame}) {
    final connected = _connected(id);
    final settings = _broker.getValueDynamic(id, 'Settings');
    final status = _broker.getValueDynamic(id, 'HtStatus');
    if (connected == null ||
        settings is! Map ||
        status is! Map ||
        connected['MacAddress'] is! String) {
      throw StateError(
        'Select a connected physical radio with loaded channels',
      );
    }
    final mode =
        (_broker.getValue<String>(0, 'SoftwareModemMode', 'None') ?? 'None')
            .toUpperCase();
    final software = frame != null
        ? frame.encoding == FragmentEncodingType.softwareAfsk1200
        : mode == 'AFSK1200' &&
              (_broker.getValue<bool>(id, 'AudioState', false) ?? false);
    final selected = software
        ? settings['channelA']
        : settings['doubleChannel'] != 0 && status['doubleChannel'] == 1
        ? settings['channelB']
        : settings['channelA'];
    final channelId = frame != null && frame.channelId >= 0
        ? frame.channelId
        : selected;
    if (channelId is! int) throw StateError('Radio channel is unknown');
    final channel = _channel(id, channelId);
    if (channel == null ||
        channel['rxFreq'] is! int ||
        channel['txFreq'] is! int ||
        (frame == null && channel['name'] == 'APRS')) {
      throw StateError(
        'Choose a dedicated packet channel, not the APRS channel',
      );
    }
    final region = frame != null && frame.regionId >= 0
        ? frame.regionId
        : status['currRegion'];
    if (region is! int) throw StateError('Radio region is unknown');
    return FileTransferLink(
      deviceId: id,
      radioMac: connected['MacAddress'] as String,
      regionId: region,
      channelId: channelId,
      channel: channel['name'] as String? ?? '',
      encoding: software ? 'softwareAfsk1200' : 'hardwareAfsk1200',
      rxFrequency: channel['rxFreq'] as int,
      txFrequency: channel['txFreq'] as int,
    );
  }

  bool _available(FileTransferLink link) {
    final connected = _connected(link.deviceId, link.radioMac);
    if (connected == null ||
        connected['DeviceId'] is! int ||
        (_broker.getValue<int>(0, 'AllowTransmit', 1) ?? 1) == 0) {
      return false;
    }
    final id = connected['DeviceId'] as int;
    final settings = _broker.getValueDynamic(id, 'Settings');
    final status = _broker.getValueDynamic(id, 'HtStatus');
    final lock = _broker.getValueDynamic(id, 'LockState');
    final channel = _channel(id, link.channelId);
    if (settings is! Map ||
        status is! Map ||
        channel == null ||
        (lock is Map && (lock['isLocked'] ?? lock['IsLocked']) == true) ||
        channel['txDisable'] == true ||
        channel['name'] == 'APRS' ||
        channel['rxFreq'] != link.rxFrequency ||
        channel['txFreq'] != link.txFrequency ||
        status['currRegion'] != link.regionId ||
        (settings['channelA'] != link.channelId &&
            settings['channelB'] != link.channelId)) {
      return false;
    }
    if (link.encoding == 'softwareAfsk1200' &&
        (settings['channelA'] != link.channelId ||
            !(_broker.getValue<bool>(id, 'AudioState', false) ?? false))) {
      return false;
    }
    try {
      _local;
    } on FormatException {
      return false;
    }
    return true;
  }

  bool _send(FileTransfer t, int pid, String destination, Uint8List bytes) {
    if (!_available(t.link)) return false;
    if ((t.outgoing ? t.source : t.file.destination) != _local &&
        !(t.file.destination == 'ALL' && !t.outgoing)) {
      return false;
    }
    final radio = _connected(t.link.deviceId, t.link.radioMac)!;
    final id = radio['DeviceId'] as int;
    final tag = 'file-transfer:${t.id}';
    final packet =
        AX25Packet.uiBytes([
            AX25Address.parse(destination)!,
            AX25Address.parse(_local)!,
          ], bytes)
          ..pid = pid
          ..command = true
          ..tag = tag
          ..channelName = t.link.channel
          ..deadline = DateTime.now().add(const Duration(seconds: 30));
    _submissionResults.remove(tag);
    _broker.dispatch(
      deviceId: id,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: packet,
        channelId: t.link.channelId,
        regionId: t.link.regionId,
        encoding: FragmentEncodingType.values.byName(t.link.encoding),
      ),
      store: false,
    );
    return _submissionResults.remove(tag) == true;
  }

  void _cancelPackets(FileTransfer t) {
    final radio = _connected(t.link.deviceId, t.link.radioMac);
    _broker.dispatch(
      deviceId: radio?['DeviceId'] as int? ?? t.link.deviceId,
      name: 'CancelFileTransmit',
      data: 'file-transfer:${t.id}',
      store: false,
    );
  }

  void _onFrame(int id, String name, Object? data) {
    if (_disposed ||
        data is! TncDataFragment ||
        !data.incoming ||
        data.historical ||
        data.encoding == FragmentEncodingType.loopback ||
        data.frameType == FragmentFrameType.xara ||
        !const {
          FragmentEncodingType.hardwareAfsk1200,
          FragmentEncodingType.softwareAfsk1200,
        }.contains(data.encoding)) {
      return;
    }
    final packet = AX25Packet.decode(data);
    if (packet == null ||
        packet.type != FrameType.uFrameUi ||
        packet.addresses.length < 2 ||
        (packet.pid != 0xbb && packet.pid != 0xbd) ||
        packet.data == null) {
      return;
    }
    try {
      final link = _link(id, frame: data);
      final now = DateTime.now();
      final key = '${link.key}:${base64Encode(data.data)}';
      _duplicates.removeWhere((_, v) => now.difference(v).inMilliseconds > 200);
      if (_duplicates.containsKey(key)) return;
      _duplicates[key] = now;
      final source = normalizeFileCallsign(packet.addresses[1].callSignWithId);
      final destination = normalizeFileCallsign(
        packet.addresses[0].callSignWithId,
      );
      if (source == _local) return;
      if (destination == 'QST-1') {
        _engine.receivePiece(
          link,
          source,
          _local,
          PacsatPiece.decode(packet.data!, directory: packet.pid == 0xbd),
          now,
        );
      } else if (packet.pid == 0xbb && destination == _local) {
        _engine.receiveRequest(
          link,
          source,
          PacsatRequest.decode(packet.data!),
          now,
        );
      }
    } on FormatException catch (e) {
      _broker.logError('[File transfer] Dropped packet: ${e.message}');
    } on StateError catch (e) {
      _broker.logError('[File transfer] Dropped packet: ${e.message}');
    }
  }

  void _onSend(int id, String name, Object? data) async {
    String? requestId;
    try {
      if (data is! Map ||
          data['deviceId'] is! int ||
          data['name'] is! String ||
          data['destination'] is! String ||
          data['data'] is! String) {
        throw const FormatException('Invalid file transfer command');
      }
      requestId = data['requestId'] as String?;
      if (_directory == null) {
        throw StateError('File transfer storage is unavailable');
      }
      final link = _link(data['deviceId'] as int);
      if (!_available(link)) {
        throw StateError('Radio is locked or transmission is disabled');
      }
      final destination = normalizeFileCallsign(data['destination'] as String);
      if (destination == 'ALL' || destination == 'QST-1') {
        throw const FormatException('Choose a single destination station, not a broadcast alias');
      }
      if (destination == _local) {
        throw const FormatException('Choose a different station');
      }
      final content = base64Decode(data['data'] as String);
      final now = DateTime.now();
      final random = Random.secure();
      var fileId = random.nextInt(0x100000000);
      while (_engine.transfers.any(
        (t) => t.outgoing && t.file.fileId == fileId,
      )) {
        fileId = random.nextInt(0x100000000);
      }
      final bytes = PacsatFile.create(
        fileId: fileId,
        name: data['name'] as String,
        source: _local,
        destination: destination,
        content: content,
        time: now,
      );
      final file = PacsatFile.fromBytes(bytes);
      final transfer = FileTransfer(
        id: 'tx_${now.microsecondsSinceEpoch}_$fileId',
        link: link,
        source: _local,
        outgoing: true,
        file: file,
        created: now,
        state: FileTransferState.queued,
        buffer: PacsatBuffer(bytes.length)..add(0, bytes),
      )..durable = false;
      _engine.addOutgoing(transfer);
      if (!await flush()) {
        _engine.fail(transfer, 'Could not persist the outgoing file');
        throw StateError('Could not persist the outgoing file');
      }
      if (_disposed) return;
      transfer.durable = true;
      _broker.dispatch(
        deviceId: 1,
        name: 'FileTransferCommandResult',
        data: {'requestId': requestId, 'accepted': true},
        store: false,
      );
    } on FormatException catch (e) {
      _commandError(requestId, e.message);
    } on StateError catch (e) {
      _commandError(requestId, e.message);
    }
  }

  void _onAction(int id, String name, Object? data) async {
    FileTransfer? transfer;
    FileTransferState? actionState;
    try {
      if (data is! Map || data['id'] is! String || data['action'] is! String) {
        throw const FormatException('Invalid file transfer action');
      }
      if (_directory == null) {
        throw StateError('File transfer storage is unavailable');
      }
      transfer = _engine.transfers.where((t) => t.id == data['id']).firstOrNull;
      if (transfer == null) throw StateError('File transfer no longer exists');
      _engine.act(
        data['id'] as String,
        data['action'] as String,
        DateTime.now(),
      );
      transfer.durable = false;
      actionState = transfer.state;
      if (!await flush()) {
        _engine.fail(transfer, 'Could not persist the file transfer action');
      }
    } on FormatException catch (e) {
      _error(e.message);
    } on StateError catch (e) {
      _error(e.message);
    } finally {
      if (transfer != null && transfer.state == actionState) {
        transfer.durable = true;
      }
    }
  }

  void _commandError(String? requestId, String error) {
    _error(error);
    _broker.dispatch(
      deviceId: 1,
      name: 'FileTransferCommandResult',
      data: {'requestId': requestId, 'accepted': false, 'error': error},
      store: false,
    );
  }

  void _error(String error) {
    _broker.logError('[File transfer] $error');
    _broker.dispatch(
      deviceId: 1,
      name: 'FileTransferError',
      data: error,
      store: false,
    );
  }

  void _changed() {
    if (_disposed) return;
    for (final t in _engine.transfers) {
      if (t.error != null && _reportedErrors[t.id] != t.error) {
        _reportedErrors[t.id] = t.error!;
        _error(t.error!);
      }
    }
    while (_engine.transfers.length > 100) {
      final terminal = _engine.transfers.where((t) => t.terminal).firstOrNull;
      if (terminal == null) break;
      _engine.transfers.remove(terminal);
    }
    _broker.dispatch(
      deviceId: 1,
      name: 'FileTransfers',
      data: _engine.transfers.map((t) => t.toJson()).toList(),
      store: true,
      allowEmpty: true,
    );
    _dirty = true;
  }

  Future<bool> _persist() async {
    final dir = _directory;
    if (dir == null) return false;
    if (_saving) {
      await _saveDone!.future;
      return _dirty ? _persist() : _lastSaveSucceeded;
    }
    _saving = true;
    _saveDone = Completer<void>();
    _dirty = false;
    try {
      final data = jsonEncode(
        _engine.transfers.map((t) => t.toJson(storage: true)).toList(),
      );
      final temporary = File(
        '${dir.path}${Platform.pathSeparator}transfers.json.tmp',
      );
      await temporary.writeAsString(data, flush: true);
      await temporary.rename(
        '${dir.path}${Platform.pathSeparator}transfers.json',
      );
      _lastSaveSucceeded = true;
    } on FileSystemException catch (e) {
      _lastSaveSucceeded = false;
      _error('Could not save file transfers: ${e.message}');
    } finally {
      _saving = false;
      _saveDone!.complete();
    }
    return _lastSaveSucceeded;
  }

  Future<bool> flush() async {
    if (kIsWeb) return true;
    final saved = await _persist();
    return _dirty && saved ? flush() : saved;
  }

  void _saveReceived(FileTransfer t, Uint8List content) {
    unawaited(_writeReceived(t, content));
  }

  Future<void> _writeReceived(FileTransfer t, Uint8List content) async {
    try {
      final dir = _directory;
      if (dir == null) {
        throw const FileSystemException('File transfer storage is unavailable');
      }
      final safe = String.fromCharCodes(t.file.name.runes.take(64))
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .replaceAll(RegExp(r'[. ]+$'), '');
      final path =
          '${dir.path}${Platform.pathSeparator}${t.id}_${safe.isEmpty ? 'file' : safe}';
      final temporary = File('$path.tmp');
      await temporary.writeAsBytes(content, flush: true);
      if (_disposed || t.state != FileTransferState.verifying) {
        await temporary.delete();
        return;
      }
      await temporary.rename(path);
      if (_disposed || t.state != FileTransferState.verifying) {
        await File(path).delete();
        return;
      }
      t.durable = false;
      _engine.completeReceive(t, path, DateTime.now());
      if (!await flush()) {
        _engine.fail(t, 'Could not persist the received file');
      }
      t.durable = true;
    } on FileSystemException catch (e) {
      if (!_disposed) {
        _engine.fail(t, 'Could not save received file: ${e.message}');
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    if (!kIsWeb) {
      _engine.dispose();
      unawaited(_persist());
    }
    _disposed = true;
    _broker.dispose();
  }
}
