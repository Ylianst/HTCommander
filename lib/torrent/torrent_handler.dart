/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.Torrent` class.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/torrent_file.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../utils/compression.dart';
import 'torrent_store.dart';

/// Background engine for the file-transfer "Torrent" feature.
///
/// Direct port of the C# `Torrent` class. Owns the local shared [files], the
/// peers' advertised file lists ([stations]) and this station's own [advertised]
/// file list. It speaks the AX.25 torrent protocol over any radio that is
/// locked to the `"Torrent"` usage:
///   * PID 162 — control frames (version / advertise / requests / discovery).
///   * PID 163 — data block frames.
///
/// UI commands are received on device 0 (`TorrentAddFile`, `TorrentRemoveFile`,
/// `TorrentSetFileMode`, `TorrentGetFiles`, `TorrentGetStations`) and state is
/// published back on device 0 (`TorrentFiles`, `TorrentStations`,
/// `TorrentFileUpdate`, `TorrentStationUpdate`).
class TorrentHandler {
  static const int _pidControl = 162;
  static const int _pidData = 163;
  static const int _maxRequestBlocks = 30;
  static const Duration _advertisementInterval = Duration(seconds: 30);

  final DataBrokerClient _broker = DataBrokerClient();

  /// Optional disk persistence (provided pre-initialized by the caller).
  final TorrentStore? _store;

  TorrentHandler({this._store});

  /// Files we are sharing or downloading.
  final List<TorrentFile> files = [];

  /// Other stations' advertised file lists (downloaded as station-files).
  final List<TorrentFile> stations = [];

  /// This station's advertised file list, or null when we share nothing.
  TorrentFile? advertised;

  bool firstDiscovery = true;

  /// Device ids of radios currently locked to the "Torrent" usage.
  final List<int> _lockedTorrentRadios = [];

  /// Last-known lock state map per radio device id.
  final Map<int, Map<String, dynamic>> _lockStates = {};

  Timer? _advertisementTimer;

  /// Initializes the handler: subscribes to broker events, restores persisted
  /// files and publishes the initial state.
  void init() {
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onDataFrameReceived,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockStateChanged,
    );

    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentAddFile',
      callback: _onAddFile,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentRemoveFile',
      callback: _onRemoveFile,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentSetFileMode',
      callback: _onSetFileMode,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentGetFiles',
      callback: _onGetFiles,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentGetStations',
      callback: _onGetStations,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentSaveFile',
      callback: _onSaveFile,
    );

    files.addAll(_loadPersistedFiles());

    _broker.logInfo('[Torrent] Torrent handler initialized');

    _publishFilesUpdate();
    _publishStationsUpdate();
    _updateAdvertised();
  }

  void dispose() {
    _stopAdvertising();
    _advertisementTimer?.cancel();
    _advertisementTimer = null;
    _broker.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI command handlers
  // ---------------------------------------------------------------------------

  void _onAddFile(int deviceId, String name, Object? data) {
    if (data is! TorrentFile) return;
    if (add(data)) {
      _broker.logInfo('[Torrent] Added file: ${data.fileName}');
    }
  }

  void _onRemoveFile(int deviceId, String name, Object? data) {
    final id = _extractId(data, 'Id');
    if (id == null) return;
    final file = _findById(files, id);
    if (file == null) return;
    files.remove(file);
    _deletePersistedFile(file);
    _updateAdvertised();
    _publishFilesUpdate();
    _broker.logInfo('[Torrent] Removed file: ${file.fileName}');
  }

  void _onSetFileMode(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final id = _extractId(data, 'FileId');
    if (id == null) return;
    final mode = _parseMode(data['Mode']);
    if (mode == null) return;
    final file = _findById(files, id);
    if (file == null || file.mode == mode) return;
    file.mode = mode;
    _persistFile(file);
    _broker.logInfo(
      '[Torrent] Changed mode for ${file.fileName} to ${mode.name}',
    );
    _publishFileUpdate(file);
  }

  void _onGetFiles(int deviceId, String name, Object? data) =>
      _publishFilesUpdate();

  void _onGetStations(int deviceId, String name, Object? data) =>
      _publishStationsUpdate();

  /// Writes the decoded bytes of a completed file to disk. The UI cannot
  /// reassemble files itself because the broker maps do not carry block data,
  /// so it asks the handler (which owns the blocks) to perform the write.
  ///
  /// [data] is a `Map` with `FileId` (id bytes / base64) and `Path` (target
  /// path). The result is published on `TorrentSaveFileResult` as a `Map` with
  /// `Path`, `Success` and an optional `Error`.
  void _onSaveFile(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final path = data['Path'];
    if (path is! String || path.isEmpty) return;
    final id = _extractId(data, 'FileId');

    void publishResult({required bool success, String? error}) {
      _broker.dispatch(
        deviceId: 0,
        name: 'TorrentSaveFileResult',
        data: {'Path': path, 'Success': success, 'Error': ?error},
        store: false,
      );
    }

    final file = id == null
        ? null
        : (_findById(files, id) ?? _findById(stations, id));
    if (file == null) {
      publishResult(success: false, error: 'File not found');
      return;
    }
    final bytes = file.getFileData();
    if (bytes == null) {
      publishResult(success: false, error: 'File data not available');
      return;
    }
    try {
      File(path).writeAsBytesSync(bytes);
      _broker.logInfo('[Torrent] Saved file ${file.fileName} to $path');
      publishResult(success: true);
    } catch (e) {
      _broker.logError('[Torrent] Failed to save ${file.fileName}: $e');
      publishResult(success: false, error: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // State publishing
  // ---------------------------------------------------------------------------

  void _publishFilesUpdate() {
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentFiles',
      data: files.map((f) => f.toBrokerMap()).toList(),
      store: false,
    );
  }

  void _publishStationsUpdate() {
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentStations',
      data: stations.map((s) => s.toBrokerMap()).toList(),
      store: false,
    );
  }

  void _publishFileUpdate(TorrentFile file) {
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentFileUpdate',
      data: file.toBrokerMap(),
      store: false,
    );
  }

  void _publishStationUpdate(TorrentFile station) {
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentStationUpdate',
      data: station.toBrokerMap(),
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Public list management
  // ---------------------------------------------------------------------------

  bool add(TorrentFile file) {
    if (files.contains(file)) return false;
    if (file.callsign.isEmpty) {
      file.callsign =
          _broker.getValue<String>(0, 'CallSign', 'NOCALL') ?? 'NOCALL';
    }
    if (file.stationId == 0) {
      file.stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    }
    files.add(file);
    _persistFile(file);
    _updateAdvertised();
    _publishFilesUpdate();
    return true;
  }

  bool remove(TorrentFile file) {
    if (!files.contains(file)) return false;
    files.remove(file);
    _deletePersistedFile(file);
    _updateAdvertised();
    _publishFilesUpdate();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Lock state / advertising
  // ---------------------------------------------------------------------------

  void _onLockStateChanged(int deviceId, String name, Object? data) {
    final wasActive = _lockedTorrentRadios.isNotEmpty;

    if (data is Map) {
      _lockStates[deviceId] = data.map((k, v) => MapEntry(k.toString(), v));
      final isLocked = (data['isLocked'] ?? data['IsLocked']) == true;
      final usage = (data['usage'] ?? data['Usage']) as String?;
      if (isLocked && usage == 'Torrent') {
        if (!_lockedTorrentRadios.contains(deviceId)) {
          _lockedTorrentRadios.add(deviceId);
          _broker.logInfo('[Torrent] Radio $deviceId locked to Torrent mode');
        }
      } else {
        if (_lockedTorrentRadios.remove(deviceId)) {
          _broker.logInfo(
            '[Torrent] Radio $deviceId unlocked from Torrent mode',
          );
        }
      }
    } else if (data == null) {
      _lockStates.remove(deviceId);
      if (_lockedTorrentRadios.remove(deviceId)) {
        _broker.logInfo('[Torrent] Radio $deviceId unlocked from Torrent mode');
      }
    }

    final isActive = _lockedTorrentRadios.isNotEmpty;
    if (isActive && !wasActive) {
      _startAdvertising();
      firstDiscovery = true;
      _broker.logInfo('[Torrent] Started advertising');
    } else if (!isActive && wasActive) {
      _stopAdvertising();
      _broker.logInfo('[Torrent] Stopped advertising');
    }
  }

  void _startAdvertising() {
    _advertisementTimer?.cancel();
    _advertisementTimer = Timer.periodic(_advertisementInterval, (_) {
      _sendRequestFrame(discovery: firstDiscovery);
      firstDiscovery = false;
    });
  }

  void _stopAdvertising() {
    _advertisementTimer?.cancel();
    _advertisementTimer = null;
  }

  /// Sends a single request frame immediately (e.g. from the UI).
  void sendRequest() {
    _sendRequestFrame(discovery: firstDiscovery);
    firstDiscovery = false;
  }

  // ---------------------------------------------------------------------------
  // Incoming frames
  // ---------------------------------------------------------------------------

  void _onDataFrameReceived(int deviceId, String name, Object? data) {
    if (data is! TncDataFragment) return;
    if (data.usage != 'Torrent') return;
    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    _broker.logInfo('[Torrent] Received torrent frame from radio $deviceId');
    processFrame(packet);
  }

  void processFrame(AX25Packet p) {
    if ((p.pid != _pidControl && p.pid != _pidData) ||
        p.addresses.length != 1) {
      return;
    }
    final payload = p.data;
    if (payload == null) return;

    if (p.pid == _pidControl) {
      _processControlFrame(p, payload);
    } else {
      _processDataBlock(p, payload);
    }
  }

  void _processControlFrame(AX25Packet p, Uint8List payload) {
    final reader = _BinReader(payload);
    String callsign = p.addresses[0].address;
    int stationId = p.addresses[0].ssid;
    Uint8List? shortId;

    while (reader.hasMore) {
      final recordType = reader.u8();
      switch (recordType) {
        case 1: // Version
          final version = reader.u8();
          if (version != 1) return;
          break;
        case 2: // Station Id + Callsign
          stationId = reader.u8();
          final len = reader.u8();
          callsign = utf8.decode(reader.bytes(len));
          break;
        case 3: // Advertised No Files
          final xFile = _findStationFile(callsign, stationId);
          if (xFile != null) stations.remove(xFile);
          break;
        case 4: // Advertised Files
          final sId = reader.bytes(12);
          final sblockCount = reader.u16le();
          var sFile = _findStationFile(callsign, stationId);
          if (sFile != null && !_bytesEqual(sFile.id, sId)) {
            stations.remove(sFile);
            sFile = null;
          }
          if (sFile == null) {
            sFile = TorrentFile()
              ..id = sId
              ..callsign = callsign
              ..stationId = stationId
              ..blocks = List<Uint8List?>.filled(
                sblockCount,
                null,
                growable: true,
              )
              ..completed = false
              ..stationFile = true
              ..receivedLastBlock = true
              ..mode = TorrentMode.request;
            stations.add(sFile);
            _publishStationsUpdate();
          }
          break;
        case 5: // Short Id
          shortId = reader.bytes(6);
          break;
        case 6: // Simple Request (block number, block count)
          final blockNumber = reader.u16le();
          final blockCount = reader.u8();
          if (shortId == null) break;
          final file = _findTorrentFileWithShortId(
            callsign,
            stationId,
            shortId,
          );
          if (file != null) {
            _respondToRequest(file, blockNumber, blockCount);
          }
          break;
        case 7: // Discovery
          _sendRequestFrame(discovery: false);
          break;
      }
    }
  }

  void _respondToRequest(TorrentFile file, int blockNumber, int blockCount) {
    final blocks = file.blocks;
    if (blocks == null) return;
    final shortId = file.shortId;
    final end = (blockNumber + blockCount < blocks.length)
        ? blockNumber + blockCount
        : blocks.length;
    for (var i = blockNumber; i < end; i++) {
      final block = blocks[i];
      if (block == null) continue;
      final frame = Uint8List(block.length + 8);
      frame.setRange(0, 6, shortId);
      if (i == blocks.length - 1) frame[5] = (frame[5] + 0x01) & 0xFF;
      frame[6] = (i >> 8) & 0xFF;
      frame[7] = i & 0xFF;
      frame.setRange(8, frame.length, block);
      final tag =
          '${file.callsign}-${file.stationId}-${_bytesToHex(shortId)}-$i';
      _sendTorrentPacket(
        frame,
        _pidData,
        tag: tag,
        deadline: DateTime.now().add(const Duration(seconds: 60)),
      );
    }
  }

  void _processDataBlock(AX25Packet p, Uint8List payload) {
    if (payload.length < 8) return;
    final callsign = p.addresses[0].address;
    final stationId = p.addresses[0].ssid;

    final blockShortId = Uint8List(6);
    blockShortId.setRange(0, 6, payload);
    final lastBlock = (payload[5] & 0x01) != 0;
    final isStationFile = (payload[5] & 0x02) != 0;
    blockShortId[5] = blockShortId[5] & 0xFE;
    final blockNumber = (payload[6] << 8) + payload[7];
    final block = Uint8List.fromList(payload.sublist(8));

    if (isStationFile) {
      _storeStationBlock(
        callsign,
        stationId,
        blockShortId,
        blockNumber,
        block,
        lastBlock,
      );
    } else {
      _storeFileBlock(
        callsign,
        stationId,
        blockShortId,
        blockNumber,
        block,
        lastBlock,
      );
    }
  }

  void _storeStationBlock(
    String callsign,
    int stationId,
    Uint8List blockShortId,
    int blockNumber,
    Uint8List block,
    bool lastBlock,
  ) {
    for (final file in stations) {
      if (file.callsign != callsign ||
          file.stationId != stationId ||
          !_bytesEqual(file.shortId, blockShortId) ||
          file.completed) {
        continue;
      }
      final blocks = file.blocks;
      if (blocks == null || blockNumber >= blocks.length) return;
      if (blocks[blockNumber] == null) {
        blocks[blockNumber] = block;
        file.receivedLastBlock = lastBlock;
        final r = file.isCompleted();
        if (r == 1) {
          file.completed = true;
          file.mode = TorrentMode.sharing;
          _updateStationAdvertised(file);
        } else if (r == 2) {
          file.mode = TorrentMode.error;
        }
        _publishStationUpdate(file);
      }
      return;
    }
  }

  void _storeFileBlock(
    String callsign,
    int stationId,
    Uint8List blockShortId,
    int blockNumber,
    Uint8List block,
    bool lastBlock,
  ) {
    TorrentFile? mfile;
    for (final file in files) {
      if (file.callsign == callsign &&
          file.stationId == stationId &&
          _bytesEqual(file.shortId, blockShortId)) {
        mfile = file;
      }
    }
    if (mfile == null || mfile.completed) return;

    var blocks = mfile.blocks;
    if (blocks == null) {
      blocks = List<Uint8List?>.filled(
        blockNumber + (lastBlock ? 1 : 40),
        null,
        growable: true,
      );
      mfile.blocks = blocks;
    }
    if (blocks.length <= blockNumber) {
      final newLen = blockNumber + (lastBlock ? 1 : 40);
      while (blocks.length < newLen) {
        blocks.add(null);
      }
    }
    if (blocks[blockNumber] == null) {
      blocks[blockNumber] = block;
      mfile.receivedLastBlock = lastBlock;
      final r = mfile.isCompleted();
      if (r == 1) {
        mfile.completed = true;
        mfile.mode = TorrentMode.sharing;
      } else if (r == 2) {
        mfile.mode = TorrentMode.error;
      }
      _persistFile(mfile);
      _publishFileUpdate(mfile);
    }
  }

  // ---------------------------------------------------------------------------
  // Outgoing requests
  // ---------------------------------------------------------------------------

  void _sendRequestFrame({bool discovery = false}) {
    if (_lockedTorrentRadios.isEmpty) return;

    final writer = _BinWriter();
    writer.u8(1); // Version
    writer.u8(1);

    final ad = advertised;
    if (ad == null) {
      writer.u8(3); // Advertised No Files
    } else {
      writer.u8(4); // Advertised Files
      writer.bytes(ad.id!);
      writer.u16le(ad.blocks?.length ?? 0);
    }

    if (discovery) {
      writer.u8(7); // Discovery
    }

    final requests = _getNextRequests();
    final myCallsign =
        _broker.getValue<String>(0, 'CallSign', 'NOCALL') ?? 'NOCALL';
    final myStationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    var currentStationId = myStationId & 0xFF;
    var currentCallsign = myCallsign;
    Uint8List? currentShortId;

    for (final r in requests) {
      if (currentStationId != r.stationId || currentCallsign != r.callsign) {
        writer.u8(2); // Station Id + Callsign
        writer.u8(r.stationId);
        final callsignBuf = utf8.encode(r.callsign);
        writer.u8(callsignBuf.length);
        writer.bytes(callsignBuf);
        currentStationId = r.stationId;
        currentCallsign = r.callsign;
      }
      if (currentShortId == null || !_bytesEqual(currentShortId, r.shortId)) {
        writer.u8(5); // Short Id
        writer.bytes(r.shortId);
        currentShortId = r.shortId;
      }
      writer.u8(6); // Simple Request
      writer.u16le(r.blockNumber);
      writer.u8(r.blockCount);
    }

    _sendTorrentPacket(
      writer.toBytes(),
      _pidControl,
      tag: 'TorrentRequest',
      deadline: DateTime.now().add(const Duration(seconds: 30)),
    );
  }

  List<_Request> _getNextRequests() {
    final requests = <_Request>[];
    final requestTorrents = <TorrentFile>[
      ...stations.where((f) => f.mode == TorrentMode.request),
      ...files.where((f) => f.mode == TorrentMode.request),
    ];

    for (final file in requestTorrents) {
      final blocks = file.blocks;
      if (blocks == null) continue;
      var requestBlockIndex = -1;
      var requestBlockCount = 0;
      var totalRequestCount = 0;

      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] == null) {
          if (requestBlockIndex == -1) requestBlockIndex = i;
          requestBlockCount++;
          totalRequestCount++;
          if (requestBlockCount > _maxRequestBlocks ||
              totalRequestCount > _maxRequestBlocks) {
            requests.add(
              _Request(
                file.callsign,
                file.stationId & 0xFF,
                file.shortId,
                requestBlockIndex,
                requestBlockCount,
              ),
            );
            requestBlockIndex = -1;
            requestBlockCount = 0;
            if (totalRequestCount > _maxRequestBlocks) return requests;
          }
        } else {
          if (requestBlockIndex != -1) {
            requests.add(
              _Request(
                file.callsign,
                file.stationId & 0xFF,
                file.shortId,
                requestBlockIndex,
                requestBlockCount,
              ),
            );
            requestBlockIndex = -1;
            requestBlockCount = 0;
            if (totalRequestCount > _maxRequestBlocks) return requests;
          }
        }
      }
      if (requestBlockIndex != -1) {
        requests.add(
          _Request(
            file.callsign,
            file.stationId & 0xFF,
            file.shortId,
            requestBlockIndex,
            requestBlockCount,
          ),
        );
      }
    }
    return requests;
  }

  void _sendTorrentPacket(
    Uint8List data,
    int pid, {
    String? tag,
    DateTime? deadline,
  }) {
    if (_lockedTorrentRadios.isEmpty) return;
    final callsign =
        _broker.getValue<String>(0, 'CallSign', 'NOCALL') ?? 'NOCALL';
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final address = AX25Address.getAddress(callsign, stationId);
    if (address == null) return;

    for (final radioId in _lockedTorrentRadios) {
      final lock = _lockStates[radioId];
      if (lock == null) continue;
      final isLocked = (lock['isLocked'] ?? lock['IsLocked']) == true;
      final usage = (lock['usage'] ?? lock['Usage']) as String?;
      if (!isLocked || usage != 'Torrent') continue;
      final channelId = (lock['channelId'] ?? lock['ChannelId']) as int? ?? -1;
      final regionId = (lock['regionId'] ?? lock['RegionId']) as int? ?? -1;

      final packet = AX25Packet(
        addresses: [address],
        data: data,
        type: FrameType.uFrameUi,
      );
      packet.pid = pid;
      packet.tag = tag;
      packet.deadline =
          deadline ?? DateTime.now().add(const Duration(seconds: 60));
      packet.incoming = false;
      packet.sent = false;

      _broker.dispatch(
        deviceId: radioId,
        name: 'TransmitDataFrame',
        data: TransmitDataFrameData(
          packet: packet,
          channelId: channelId,
          regionId: regionId,
        ),
        store: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Advertised list (our own + decoding peers')
  // ---------------------------------------------------------------------------

  void _updateStationAdvertised(TorrentFile stationFile) {
    if (!stationFile.completed) return;
    final tagged = stationFile.getRawBlocks();
    if (tagged == null) return;
    final bytes = Compression.decompressTagged(tagged);
    if (bytes.isEmpty) return;

    final reader = _BinReader(bytes);
    final updated = <TorrentFile>[];
    String? xcallsign;
    String? xfilename;
    String? xdescription;
    var xstationId = 0;

    while (reader.hasMore) {
      final recordType = reader.u8();
      switch (recordType) {
        case 1: // Version
          final version = reader.u8();
          if (version != 1) return;
          break;
        case 2: // Callsign
          final len = reader.u8();
          xcallsign = utf8.decode(reader.bytes(len));
          break;
        case 3: // Station Id
          xstationId = reader.u8();
          break;
        case 4: // Filename
          final len = reader.u8();
          xfilename = utf8.decode(reader.bytes(len));
          break;
        case 5: // Description
          final len = reader.u8();
          xdescription = utf8.decode(reader.bytes(len));
          break;
        case 6: // ID + Block Count
          final id = reader.bytes(12);
          final blockCount = reader.u16le();
          if (xcallsign != null && xfilename != null) {
            final tFile = TorrentFile()
              ..id = id
              ..callsign = xcallsign
              ..stationId = xstationId
              ..fileName = xfilename
              ..description = xdescription ?? ''
              ..blocks = List<Uint8List?>.filled(
                blockCount,
                null,
                growable: true,
              );
            updated.add(tFile);
            xfilename = null;
            xdescription = null;
          }
          break;
      }
    }

    var changed = false;
    for (final tFile in updated) {
      var found = false;
      for (final file in files) {
        if (_bytesEqual(file.shortId, tFile.shortId) &&
            file.callsign == tFile.callsign &&
            file.stationId == tFile.stationId) {
          found = true;
          if (file.id == null) {
            file.id = tFile.id;
            changed = true;
          }
          if (file.fileName != tFile.fileName) {
            file.fileName = tFile.fileName;
            changed = true;
          }
          if (file.description != tFile.description) {
            file.description = tFile.description;
            changed = true;
          }
          break;
        }
      }
      if (!found) {
        files.add(tFile);
        _persistFile(tFile);
        changed = true;
      }
    }

    if (changed) _publishFilesUpdate();
  }

  void _updateAdvertised() {
    final writer = _BinWriter();
    final callsign =
        _broker.getValue<String>(0, 'CallSign', 'NOCALL') ?? 'NOCALL';
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;

    writer.u8(1); // Version
    writer.u8(1);

    final callsignBuf = utf8.encode(callsign);
    writer.u8(2); // Callsign
    writer.u8(callsignBuf.length);
    writer.bytes(callsignBuf);

    if (stationId != 0) {
      writer.u8(3); // Station Id
      writer.u8(stationId);
    }

    var filecount = 0;
    for (final file in files) {
      if (file.callsign == callsign &&
          file.stationId == stationId &&
          file.id != null &&
          file.id!.length == 12) {
        final nameBuf = utf8.encode(file.fileName);
        writer.u8(4); // Filename
        writer.u8(nameBuf.length);
        writer.bytes(nameBuf);

        if (file.description.isNotEmpty) {
          final descBuf = utf8.encode(file.description);
          writer.u8(5); // Description
          writer.u8(descBuf.length);
          writer.bytes(descBuf);
        }

        writer.u8(6); // ID + Block Count
        writer.bytes(file.id!);
        writer.u16le(file.blocks?.length ?? 0);
        filecount++;
      }
    }

    if (filecount == 0) {
      advertised = null;
      return;
    }

    final raw = writer.toBytes();
    final best = Compression.chooseBest(raw);
    final tagged = Compression.tagAndPack(best.compression, best.data);

    advertised = TorrentFile.fromTaggedPayload(
      tagged: tagged,
      callsign: callsign,
      stationId: stationId,
      rawSize: raw.length,
      compression: best.compression,
      stationFile: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Persistence hooks
  // ---------------------------------------------------------------------------

  List<TorrentFile> _loadPersistedFiles() => _store?.loadedFiles ?? const [];

  void _persistFile(TorrentFile file) {
    _store?.save(file);
  }

  void _deletePersistedFile(TorrentFile file) {
    _store?.delete(file);
  }

  // ---------------------------------------------------------------------------
  // Lookups & helpers
  // ---------------------------------------------------------------------------

  TorrentFile? _findStationFile(String callsign, int stationId) {
    for (final file in stations) {
      if (file.callsign == callsign && file.stationId == stationId) return file;
    }
    return null;
  }

  TorrentFile? _findTorrentFileWithShortId(
    String callsign,
    int stationId,
    Uint8List shortId,
  ) {
    final ad = advertised;
    if (ad != null &&
        ad.callsign == callsign &&
        ad.stationId == stationId &&
        _bytesEqual(ad.shortId, shortId)) {
      return ad;
    }
    for (final file in files) {
      if (_bytesEqual(file.shortId, shortId) &&
          file.callsign == callsign &&
          file.stationId == stationId) {
        return file;
      }
    }
    for (final file in stations) {
      if (_bytesEqual(file.shortId, shortId) &&
          file.callsign == callsign &&
          file.stationId == stationId) {
        return file;
      }
    }
    return null;
  }

  TorrentFile? _findById(List<TorrentFile> list, Uint8List id) {
    for (final file in list) {
      if (file.id != null && _bytesEqual(file.id, id)) return file;
    }
    return null;
  }

  static Uint8List? _extractId(Object? data, String key) {
    if (data is TorrentFile) return data.id;
    if (data is Map) {
      final v = data[key];
      if (v is Uint8List) return v;
      if (v is List) return Uint8List.fromList(v.cast<int>());
      if (v is String) return Uint8List.fromList(base64Decode(v));
    }
    return null;
  }

  static TorrentMode? _parseMode(Object? value) {
    if (value is TorrentMode) return value;
    if (value is String) {
      switch (value) {
        case 'Pause':
          return TorrentMode.pause;
        case 'Request':
          return TorrentMode.request;
        case 'Sharing':
          return TorrentMode.sharing;
        case 'Error':
          return TorrentMode.error;
      }
    }
    return null;
  }

  static bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// A pending block request (port of the C# `Torrent.Request` struct).
class _Request {
  _Request(
    this.callsign,
    this.stationId,
    this.shortId,
    this.blockNumber,
    this.blockCount,
  );
  final String callsign;
  final int stationId;
  final Uint8List shortId;
  final int blockNumber;
  final int blockCount;
}

/// Minimal little-endian binary writer matching .NET `BinaryWriter` for the
/// fields used by the torrent protocol.
class _BinWriter {
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);

  void u16le(int v) {
    _b.addByte(v & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
  }

  void bytes(List<int> v) => _b.add(v);

  Uint8List toBytes() => _b.toBytes();
}

/// Minimal binary reader matching .NET `BinaryReader` (little-endian) for the
/// fields used by the torrent protocol.
class _BinReader {
  _BinReader(this._d);
  final Uint8List _d;
  int _p = 0;

  bool get hasMore => _p < _d.length;

  int u8() => _d[_p++];

  int u16le() {
    final v = _d[_p] | (_d[_p + 1] << 8);
    _p += 2;
    return v;
  }

  Uint8List bytes(int n) {
    final r = Uint8List.fromList(_d.sublist(_p, _p + n));
    _p += n;
    return r;
  }
}
