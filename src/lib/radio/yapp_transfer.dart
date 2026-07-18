/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'ax25_session.dart';

/// Direction of an in-progress YAPP transfer.
enum YappDirection { none, send, receive }

/// Snapshot of an in-progress YAPP file transfer, delivered to
/// [YappTransfer.onProgress] so the UI can render a progress bar.
class YappProgress {
  final String filename;
  final int fileSize;
  final int bytesTransferred;
  final YappDirection direction;

  const YappProgress({
    required this.filename,
    required this.fileSize,
    required this.bytesTransferred,
    required this.direction,
  });

  /// Fraction complete in the range 0.0-1.0 (0 when the size is unknown).
  double get fraction =>
      fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 0.0;
}

/// YAPP (Yet Another Protocol for Packet) file-transfer engine for a connected
/// AX.25 session, ported and extended from the C# `YappTransfer`.
///
/// The C# reference implemented receiving only; this Dart port implements both
/// **sending** and **receiving**, including YappC (checksummed) transfers. It
/// drives a single [AX25Session] and expects each YAPP packet to arrive as one
/// discrete `onDataReceived` callback (one AX.25 I-frame). Keeping [blockSize]
/// well below the session's `packetLength` guarantees each packet fits in a
/// single I-frame so message boundaries are preserved.
///
/// Received file bytes are buffered in memory and handed to [onReceiveComplete]
/// when the transfer finishes, letting the UI prompt for a save location.
class YappTransfer {
  YappTransfer(this.session);

  final AX25Session session;

  // ---- YAPP control characters (from the protocol specification) -----------
  static const int _ack = 0x06;
  static const int _enq = 0x05;
  static const int _soh = 0x01; // Start of Header (HD packet)
  static const int _stx = 0x02; // Start of Text  (DT data packet)
  static const int _etx = 0x03; // End of Text     (EF end-of-file)
  static const int _eot = 0x04; // End of Transmission (ET)
  static const int _nak = 0x15; // Negative Acknowledge (NR / RE)
  static const int _can = 0x18; // Cancel (CN)

  // ---- Second-byte packet subtypes used with _ack / _enq -------------------
  static const int _rr = 0x01; // Receive Ready (also SI second byte)
  static const int _rf = 0x02; // Receive File (standard mode accept)
  static const int _af = 0x03; // Ack EOF
  static const int _at = 0x04; // Ack EOT
  static const int _ca = 0x05; // Cancel Ack
  static const int _si = 0x01; // Send Init second byte

  // ---- Configuration -------------------------------------------------------

  /// Whether to request/accept YappC (per-block additive checksum) transfers.
  bool useChecksum = true;

  /// Maximum number of timeout retries before a transfer is cancelled.
  int maxRetries = 3;

  /// Inactivity timeout in milliseconds.
  int timeoutMs = 60000;

  /// Payload size of each data block. Must stay below the session
  /// `packetLength` so each YAPP packet maps to a single I-frame.
  int blockSize = 128;

  // ---- Callbacks -----------------------------------------------------------

  /// Fired repeatedly during a transfer with the current progress.
  void Function(YappProgress progress)? onProgress;

  /// Fired when an incoming file has been fully received. The [data] holds the
  /// complete file bytes so the caller can prompt for a save location.
  void Function(String filename, Uint8List data)? onReceiveComplete;

  /// Fired when an outgoing file has been fully sent and acknowledged.
  void Function(String filename)? onSendComplete;

  /// Fired when a transfer fails or is cancelled.
  void Function(String message)? onError;

  // ---- State ---------------------------------------------------------------

  _YappState _state = _YappState.idle;
  YappDirection _direction = YappDirection.none;
  Timer? _timeoutTimer;
  int _retryCount = 0;
  bool _disposed = false;

  // Common transfer info.
  String _filename = '';
  int _fileSize = 0;
  int _bytesTransferred = 0;

  // Receive buffer.
  final BytesBuilder _recvBuffer = BytesBuilder(copy: false);
  bool _recvUseChecksum = false;

  // Send buffer.
  Uint8List _sendData = Uint8List(0);
  int _sendOffset = 0;
  bool _sendUseChecksum = false;

  /// Whether a transfer is currently active (not idle and not merely listening).
  bool get isBusy =>
      _direction != YappDirection.none && _state != _YappState.recvInit;

  /// Whether the engine is idle (no transfer and not listening).
  bool get isIdle => _state == _YappState.idle;

  YappDirection get direction => _direction;

  // ---------------------------------------------------------------------------
  // Receive mode
  // ---------------------------------------------------------------------------

  /// Arms the engine to accept incoming file transfers. Safe to call when the
  /// session first connects; it does nothing if a transfer is already active.
  void enableAutoReceive() {
    if (_disposed) return;
    if (_state != _YappState.idle) return;
    _direction = YappDirection.receive;
    _setState(_YappState.recvInit);
  }

  // ---------------------------------------------------------------------------
  // Send mode
  // ---------------------------------------------------------------------------

  /// Starts sending [bytes] as a file named [filename]. Returns `false` if a
  /// transfer is already in progress.
  bool sendFile(String filename, Uint8List bytes) {
    if (_disposed) return false;
    if (isBusy) {
      _fail('A transfer is already in progress');
      return false;
    }

    _filename = _baseName(filename);
    _sendData = bytes;
    _sendOffset = 0;
    _fileSize = bytes.length;
    _bytesTransferred = 0;
    _sendUseChecksum = useChecksum;
    _direction = YappDirection.send;
    _retryCount = 0;

    // Send Init (SI) and wait for the receiver's Receive Ready (RR).
    _send(Uint8List.fromList([_enq, _si]));
    _setState(_YappState.sendWaitRR);
    _emitProgress();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Incoming data routing
  // ---------------------------------------------------------------------------

  /// Feeds raw session data to the YAPP engine. Returns `true` if the data was
  /// consumed as YAPP protocol traffic (and should therefore NOT be shown as
  /// terminal text), `false` otherwise.
  bool processIncomingData(Uint8List data) {
    if (_disposed || data.isEmpty) return false;

    // While idle, only a Send Init (SI) request starts a transfer.
    if (_state == _YappState.idle) {
      if (_isTransferRequest(data)) {
        enableAutoReceive();
        _handlePacket(data);
        return true;
      }
      return false;
    }

    // While merely listening (armed but no active transfer), consume only YAPP
    // control traffic so ordinary terminal text still flows through.
    if (_state == _YappState.recvInit && !_isYappData(data)) {
      return false;
    }

    // Any data during an active transfer is YAPP protocol traffic.
    _handlePacket(data);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Packet dispatch
  // ---------------------------------------------------------------------------

  void _handlePacket(Uint8List data) {
    _restartTimeout();
    final type = data[0];
    switch (_state) {
      case _YappState.idle:
        break;
      case _YappState.recvInit:
      case _YappState.recvHeader:
        _handleReceiveHeaderState(data, type);
        break;
      case _YappState.recvData:
        _handleReceiveDataState(data, type);
        break;
      case _YappState.sendWaitRR:
        _handleSendWaitRR(data, type);
        break;
      case _YappState.sendWaitHdrAck:
        _handleSendWaitHeaderAck(data, type);
        break;
      case _YappState.sendData:
        _handleSendData(data, type);
        break;
      case _YappState.sendWaitEofAck:
        _handleSendWaitEofAck(data, type);
        break;
      case _YappState.sendWaitEotAck:
        _handleSendWaitEotAck(data, type);
        break;
      case _YappState.cancelWait:
        _handleCancelWait(data, type);
        break;
    }
  }

  // ---- Receive-side state handlers -----------------------------------------

  void _handleReceiveHeaderState(Uint8List data, int type) {
    if (type == _enq && data.length >= 2 && data[1] == _si) {
      // Send Init: accept with Receive Ready (RR) and wait for the header.
      _send(Uint8List.fromList([_ack, _rr]));
      _setState(_YappState.recvHeader);
    } else if (type == _soh) {
      _processHeaderPacket(data);
    } else if (type == _eot) {
      _send(Uint8List.fromList([_ack, _at])); // Ack EOT
      _completeReceiveSession();
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleReceiveDataState(Uint8List data, int type) {
    if (type == _stx) {
      _processDataPacket(data);
    } else if (type == _etx) {
      _processEndOfFile();
    } else if (type == _eot) {
      _send(Uint8List.fromList([_ack, _at]));
      _completeReceiveSession();
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _processHeaderPacket(Uint8List data) {
    if (data.length < 2) {
      _sendNotReady('Invalid header packet');
      return;
    }
    final length = data[1];
    if (data.length < 2 + length) {
      _sendNotReady('Incomplete header packet');
      return;
    }
    final headerData = data.sublist(2, 2 + length);
    final parts = _parseNullSeparated(headerData);
    if (parts.length < 2) {
      _sendNotReady('Invalid header format');
      return;
    }

    _filename = _baseName(parts[0]);
    final parsedSize = int.tryParse(parts[1]);
    if (parsedSize == null) {
      _sendNotReady('Invalid file size');
      return;
    }
    _fileSize = parsedSize;
    _bytesTransferred = 0;
    _recvBuffer.clear();

    // Accept the header: YappC (RT) when checksums are enabled, otherwise the
    // standard Receive File (RF) response.
    if (useChecksum) {
      _recvUseChecksum = true;
      _send(Uint8List.fromList([_ack, _ack])); // RT (Receive TPK)
    } else {
      _recvUseChecksum = false;
      _send(Uint8List.fromList([_ack, _rf])); // RF (Receive File)
    }
    _setState(_YappState.recvData);
    _emitProgress();
  }

  void _processDataPacket(Uint8List data) {
    if (data.length < 2) {
      cancel('Invalid data packet');
      return;
    }
    final lengthByte = data[1];
    final dataLength = lengthByte == 0 ? 256 : lengthByte;

    Uint8List payload;
    if (_recvUseChecksum) {
      if (data.length < dataLength + 3) {
        cancel('Invalid YappC data packet length');
        return;
      }
      payload = data.sublist(2, 2 + dataLength);
      final checksum = data[2 + dataLength];
      var calc = 0;
      for (final b in payload) {
        calc = (calc + b) & 0xFF;
      }
      if (calc != checksum) {
        cancel('Checksum error - data corruption detected');
        return;
      }
    } else {
      if (data.length < dataLength + 2) {
        cancel('Invalid YAPP data packet length');
        return;
      }
      payload = data.sublist(2, 2 + dataLength);
    }

    _recvBuffer.add(payload);
    _bytesTransferred += payload.length;
    _emitProgress();

    // Acknowledge the block so the sender releases the next one.
    _send(Uint8List.fromList([_ack, _rr]));
  }

  void _processEndOfFile() {
    _send(Uint8List.fromList([_ack, _af])); // Ack EOF
    final bytes = _recvBuffer.toBytes();
    final name = _filename;
    onReceiveComplete?.call(name, bytes);
    // Ready for a possible next file in the same session.
    _recvBuffer.clear();
    _setState(_YappState.recvHeader);
  }

  void _completeReceiveSession() {
    _direction = YappDirection.receive;
    _cleanup();
    // Return to listening for the next incoming transfer.
    _setState(_YappState.recvInit);
  }

  // ---- Send-side state handlers --------------------------------------------

  void _handleSendWaitRR(Uint8List data, int type) {
    if (type == _ack && data.length >= 2 && data[1] == _rr) {
      _sendHeader();
    } else if (type == _nak) {
      _fail('Receiver not ready');
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleSendWaitHeaderAck(Uint8List data, int type) {
    if (type == _ack && data.length >= 2 && data[1] == _ack) {
      // RT (Receive TPK): receiver wants YappC (checksummed) transfer.
      _sendUseChecksum = true;
      _setState(_YappState.sendData);
      _sendNextBlock();
    } else if (type == _ack && data.length >= 2 && data[1] == _rf) {
      // RF (Receive File): standard transfer, no checksums.
      _sendUseChecksum = false;
      _setState(_YappState.sendData);
      _sendNextBlock();
    } else if (type == _nak) {
      _fail('Receiver rejected the file');
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleSendData(Uint8List data, int type) {
    if (type == _ack) {
      // Any ACK (Receive Ready) releases the next block.
      _sendNextBlock();
    } else if (type == _nak) {
      _fail('Transfer error reported by receiver');
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleSendWaitEofAck(Uint8List data, int type) {
    if (type == _ack && data.length >= 2 && data[1] == _af) {
      // EOF acknowledged: end the transmission.
      _send(Uint8List.fromList([_eot]));
      _setState(_YappState.sendWaitEotAck);
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleSendWaitEotAck(Uint8List data, int type) {
    if (type == _ack && data.length >= 2 && data[1] == _at) {
      final name = _filename;
      _direction = YappDirection.none;
      _cleanup();
      _setState(_YappState.idle);
      onSendComplete?.call(name);
    } else if (type == _can) {
      _processRemoteCancel(data);
    }
  }

  void _handleCancelWait(Uint8List data, int type) {
    if (type == _ack && data.length >= 2 && data[1] == _ca) {
      _cleanup();
      _setState(_YappState.idle);
      _direction = YappDirection.none;
    } else if (type == _can) {
      _send(Uint8List.fromList([_ack, _ca])); // Cancel Ack
    }
  }

  void _sendHeader() {
    // Header payload: filename NUL filesize-ascii NUL
    final builder = BytesBuilder();
    builder.add(utf8.encode(_filename));
    builder.addByte(0x00);
    builder.add(ascii.encode(_fileSize.toString()));
    builder.addByte(0x00);
    final payload = builder.toBytes();

    final packet = Uint8List(2 + payload.length);
    packet[0] = _soh;
    packet[1] = payload.length & 0xFF;
    packet.setRange(2, 2 + payload.length, payload);
    _send(packet);
    _setState(_YappState.sendWaitHdrAck);
  }

  void _sendNextBlock() {
    if (_sendOffset >= _sendData.length) {
      // All data sent: signal End of File.
      _send(Uint8List.fromList([_etx]));
      _setState(_YappState.sendWaitEofAck);
      return;
    }

    final remaining = _sendData.length - _sendOffset;
    final blockLen = remaining < blockSize ? remaining : blockSize;
    final block = _sendData.sublist(_sendOffset, _sendOffset + blockLen);
    _sendOffset += blockLen;

    final packet = BytesBuilder();
    packet.addByte(_stx);
    packet.addByte(blockLen == 256 ? 0 : blockLen);
    packet.add(block);
    if (_sendUseChecksum) {
      var checksum = 0;
      for (final b in block) {
        checksum = (checksum + b) & 0xFF;
      }
      packet.addByte(checksum);
    }
    _send(packet.toBytes());

    _bytesTransferred = _sendOffset;
    _emitProgress();
  }

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  /// Cancels the current transfer, notifying the remote station.
  void cancel([String reason = 'Transfer cancelled by user']) {
    if (_state == _YappState.idle || _state == _YappState.recvInit) {
      // Nothing active; just reset any listening state.
      _cleanup();
      if (_direction == YappDirection.receive) {
        _setState(_YappState.recvInit);
      } else {
        _setState(_YappState.idle);
        _direction = YappDirection.none;
      }
      return;
    }
    _sendCancel(reason);
    _setState(_YappState.cancelWait);
    onError?.call(reason);
    _cleanup();
  }

  void _processRemoteCancel(Uint8List data) {
    var reason = 'Transfer cancelled by remote';
    if (data.length > 2) {
      final length = data[1];
      if (length > 0 && data.length >= 2 + length) {
        reason = utf8.decode(data.sublist(2, 2 + length), allowMalformed: true);
      }
    }
    _send(Uint8List.fromList([_ack, _ca])); // Cancel Ack
    _fail('Remote cancelled: $reason');
  }

  void _sendCancel(String reason) {
    final reasonBytes = utf8.encode(reason);
    final packet = Uint8List(2 + reasonBytes.length);
    packet[0] = _can;
    packet[1] = reasonBytes.length & 0xFF;
    packet.setRange(2, 2 + reasonBytes.length, reasonBytes);
    _send(packet);
  }

  void _sendNotReady(String reason) {
    final reasonBytes = utf8.encode(reason);
    final packet = Uint8List(2 + reasonBytes.length);
    packet[0] = _nak;
    packet[1] = reasonBytes.length & 0xFF;
    packet.setRange(2, 2 + reasonBytes.length, reasonBytes);
    _send(packet);
    _fail(reason);
  }

  // ---------------------------------------------------------------------------
  // Timeout handling
  // ---------------------------------------------------------------------------

  void _restartTimeout() {
    _timeoutTimer?.cancel();
    if (_state == _YappState.idle || _state == _YappState.recvInit) return;
    _timeoutTimer = Timer(Duration(milliseconds: timeoutMs), _onTimeout);
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _onTimeout() {
    if (_retryCount < maxRetries) {
      _retryCount++;
      _restartTimeout();
    } else {
      cancel('Timeout - transfer aborted');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _fail(String message) {
    final wasReceiving = _direction == YappDirection.receive;
    _cleanup();
    onError?.call(message);
    if (wasReceiving) {
      _setState(_YappState.recvInit);
    } else {
      _setState(_YappState.idle);
      _direction = YappDirection.none;
    }
  }

  void _emitProgress() {
    onProgress?.call(
      YappProgress(
        filename: _filename,
        fileSize: _fileSize,
        bytesTransferred: _bytesTransferred,
        direction: _direction,
      ),
    );
  }

  void _setState(_YappState newState) {
    if (_state == newState) return;
    _state = newState;
    if (newState == _YappState.idle || newState == _YappState.recvInit) {
      _stopTimeout();
    } else {
      _restartTimeout();
    }
  }

  void _cleanup() {
    _stopTimeout();
    _retryCount = 0;
    _sendData = Uint8List(0);
    _sendOffset = 0;
    _recvBuffer.clear();
  }

  void _send(Uint8List packet) {
    session.send(packet);
  }

  bool _isTransferRequest(Uint8List data) =>
      data.length >= 2 && data[0] == _enq && data[1] == _si;

  bool _isYappData(Uint8List data) {
    if (data.isEmpty) return false;
    final b = data[0];
    return b == _enq ||
        b == _soh ||
        b == _stx ||
        b == _etx ||
        b == _eot ||
        b == _ack ||
        b == _nak ||
        b == _can;
  }

  List<String> _parseNullSeparated(Uint8List data) {
    final result = <String>[];
    final current = <int>[];
    for (final b in data) {
      if (b == 0x00) {
        if (current.isNotEmpty) {
          result.add(utf8.decode(current, allowMalformed: true));
          current.clear();
        }
      } else {
        current.add(b);
      }
    }
    if (current.isNotEmpty) {
      result.add(utf8.decode(current, allowMalformed: true));
    }
    return result;
  }

  String _baseName(String path) {
    var name = path.replaceAll('\\', '/');
    final slash = name.lastIndexOf('/');
    if (slash >= 0) name = name.substring(slash + 1);
    return name.isEmpty ? 'file.bin' : name;
  }

  /// Resets the engine to idle. Called when the session disconnects.
  void reset() {
    _cleanup();
    _state = _YappState.idle;
    _direction = YappDirection.none;
  }

  /// Releases resources. The engine must not be used after disposal.
  void dispose() {
    _disposed = true;
    _stopTimeout();
    onProgress = null;
    onReceiveComplete = null;
    onSendComplete = null;
    onError = null;
  }
}

enum _YappState {
  idle,
  // Receive states.
  recvInit, // Armed and listening for an incoming transfer.
  recvHeader, // Awaiting a file header.
  recvData, // Receiving data blocks.
  // Send states.
  sendWaitRR, // Sent SI, awaiting Receive Ready.
  sendWaitHdrAck, // Sent header, awaiting RF/RT (or NR).
  sendData, // Sending data blocks, awaiting per-block ACK.
  sendWaitEofAck, // Sent EOF, awaiting Ack EOF.
  sendWaitEotAck, // Sent EOT, awaiting Ack EOT.
  // Cancellation.
  cancelWait, // Sent Cancel, awaiting Cancel Ack.
}
