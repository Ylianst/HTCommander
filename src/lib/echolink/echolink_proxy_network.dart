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
// echolink_proxy_network.dart - EchoLinkNetwork over an EchoLink proxy.
//
// Tunnels the audio (5198), control (5199) and directory (5200) traffic through
// a single TCP connection to an EchoLink proxy server, so EchoLink works from
// networks that block inbound UDP (e.g. mobile carriers behind CGNAT). The
// protocol codec lives in echolink_proxy.dart; this file only wires it to a
// dart:io socket. Not exercised by unit tests (real socket); the codec is.
//

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'echolink_network.dart';
import 'echolink_proxy.dart';
import 'echolink_qso.dart' show echoLinkAudioPort, echoLinkControlPort;

/// State of the single tunnel TCP connection to the proxy.
enum _ProxyState { disconnected, waitingForDigest, connected }

/// Tracks one in-flight directory-server request tunnelled through the proxy.
class _DirOp {
  final Uint8List request;
  final int? maxBytes;
  final BytesBuilder collected = BytesBuilder();
  final Completer<Uint8List> completer = Completer<Uint8List>();
  bool tcpOpened = false;
  _DirOp(this.request, this.maxBytes);
}

class EchoLinkProxyNetwork implements EchoLinkNetwork {
  final String proxyHost;
  final int proxyPort;
  final String callsign;
  final String password;

  /// Timeout for the proxy connect + credentials handshake.
  final Duration connectTimeout;

  /// Timeout for a single directory exchange tunnelled through the proxy.
  final Duration directoryTimeout;

  Socket? _sock;
  StreamSubscription<Uint8List>? _sub;
  _ProxyState _state = _ProxyState.disconnected;
  final List<int> _rx = <int>[];
  Completer<void>? _openCompleter;
  _DirOp? _dirOp;
  Object? _fatalError;

  final StreamController<EchoLinkDatagram> _audioIn =
      StreamController<EchoLinkDatagram>.broadcast();
  final StreamController<EchoLinkDatagram> _controlIn =
      StreamController<EchoLinkDatagram>.broadcast();

  EchoLinkProxyNetwork({
    required this.proxyHost,
    required this.callsign,
    this.proxyPort = echoLinkProxyDefaultPort,
    this.password = echoLinkProxyPublicPassword,
    this.connectTimeout = const Duration(seconds: 15),
    this.directoryTimeout = const Duration(seconds: 15),
  });

  @override
  Stream<EchoLinkDatagram> get audioIn => _audioIn.stream;

  @override
  Stream<EchoLinkDatagram> get controlIn => _controlIn.stream;

  @override
  Future<void> open() async {
    if (_state != _ProxyState.disconnected) return;
    final Socket sock = await Socket.connect(proxyHost, proxyPort,
        timeout: connectTimeout);
    _sock = sock;
    _state = _ProxyState.waitingForDigest;
    final Completer<void> opened = Completer<void>();
    _openCompleter = opened;
    _sub = sock.listen(
      _onData,
      onError: (Object e) => _onSocketDown(e),
      onDone: () => _onSocketDown(const SocketException('Proxy closed')),
      cancelOnError: true,
    );
    // Writes via sock.add() are buffered; a failing write (e.g. the socket was
    // destroyed while a UDP-tunnel packet was still queued) reports its error
    // through the done future, NOT synchronously at the add() call. Without a
    // handler here that becomes an uncaught async "Bad file descriptor" error.
    unawaited(sock.done.catchError((Object e) => _onSocketDown(e)));
    // The proxy is silent on success (no explicit ACK); it only speaks up with a
    // SYSTEM error on a bad password/ACL. Complete once the nonce arrives and we
    // have sent our credentials, but fail if the handshake never gets that far.
    await opened.future.timeout(connectTimeout, onTimeout: () {
      _onSocketDown(TimeoutException('Proxy handshake timed out'));
      throw _fatalError ?? TimeoutException('Proxy handshake timed out');
    });
  }

  @override
  void sendAudio(String host, Uint8List data) {
    _sendMessage(encodeEchoLinkProxyMessage(EchoLinkProxyMsgType.udpData,
        ip: host, data: data));
  }

  @override
  void sendControl(String host, Uint8List data) {
    _sendMessage(encodeEchoLinkProxyMessage(EchoLinkProxyMsgType.udpControl,
        ip: host, data: data));
  }

  @override
  Future<Uint8List> directoryExchange(List<String> servers, Uint8List request,
      {int? maxBytes}) async {
    if (_state != _ProxyState.connected) {
      throw StateError('EchoLink proxy not connected');
    }
    Object? lastError = _fatalError;
    for (final String server in servers) {
      _DirOp? op;
      try {
        final String ip = await _resolveIpv4(server);
        op = _DirOp(request, maxBytes);
        _dirOp = op;
        _sendMessage(encodeEchoLinkProxyMessage(EchoLinkProxyMsgType.tcpOpen,
            ip: ip));
        final Uint8List resp =
            await op.completer.future.timeout(directoryTimeout);
        return resp;
      } catch (e) {
        lastError = e;
      } finally {
        if (identical(_dirOp, op)) {
          // Ask the proxy to tear down the tunnelled TCP connection.
          if (op != null && op.tcpOpened) {
            _sendMessage(
                encodeEchoLinkProxyMessage(EchoLinkProxyMsgType.tcpClose));
          }
          _dirOp = null;
        }
      }
    }
    throw StateError('Directory exchange via proxy failed: $lastError');
  }

  @override
  Future<void> close() async {
    _state = _ProxyState.disconnected;
    await _sub?.cancel();
    _sub = null;
    _sock?.destroy();
    _sock = null;
    _failPending(const SocketException('Proxy closed'));
    if (!_audioIn.isClosed) await _audioIn.close();
    if (!_controlIn.isClosed) await _controlIn.close();
  }

  // ---- internals ----------------------------------------------------------

  void _sendMessage(Uint8List bytes) {
    final Socket? sock = _sock;
    if (sock == null || _state != _ProxyState.connected) return;
    try {
      sock.add(bytes);
    } catch (_) {
      // A failed write means the tunnel is gone; teardown happens via onError.
    }
  }

  void _onData(Uint8List chunk) {
    _rx.addAll(chunk);

    if (_state == _ProxyState.waitingForDigest) {
      if (_rx.length < echoLinkProxyNonceSize) return;
      final Uint8List nonce =
          Uint8List.fromList(_rx.sublist(0, echoLinkProxyNonceSize));
      _rx.removeRange(0, echoLinkProxyNonceSize);
      final Uint8List authResp =
          echoLinkProxyAuthResponse(callsign, password, nonce);
      _state = _ProxyState.connected;
      try {
        _sock?.add(authResp);
      } catch (e) {
        _onSocketDown(e);
        return;
      }
      _openCompleter?.complete();
      _openCompleter = null;
    }

    if (_rx.isEmpty) return;
    final EchoLinkProxyParseResult res =
        parseEchoLinkProxyMessages(Uint8List.fromList(_rx));
    if (res.consumed > 0) _rx.removeRange(0, res.consumed);
    for (final EchoLinkProxyMessage msg in res.messages) {
      _handleMessage(msg);
    }
  }

  void _handleMessage(EchoLinkProxyMessage msg) {
    switch (msg.type) {
      case EchoLinkProxyMsgType.udpData:
        if (!_audioIn.isClosed) {
          _audioIn.add(EchoLinkDatagram(msg.ip, echoLinkAudioPort, msg.data));
        }
        break;
      case EchoLinkProxyMsgType.udpControl:
        if (!_controlIn.isClosed) {
          _controlIn
              .add(EchoLinkDatagram(msg.ip, echoLinkControlPort, msg.data));
        }
        break;
      case EchoLinkProxyMsgType.tcpStatus:
        _onTcpStatus(msg.data);
        break;
      case EchoLinkProxyMsgType.tcpData:
        _onTcpData(msg.data);
        break;
      case EchoLinkProxyMsgType.tcpClose:
        _onTcpClose();
        break;
      case EchoLinkProxyMsgType.system:
        _onSystem(msg.data);
        break;
      case EchoLinkProxyMsgType.tcpOpen:
        break; // Client-only message; ignore if echoed back.
    }
  }

  void _onTcpStatus(Uint8List data) {
    final _DirOp? op = _dirOp;
    if (op == null) return;
    final bool ok = data.length >= 4 &&
        data[0] == 0 &&
        data[1] == 0 &&
        data[2] == 0 &&
        data[3] == 0;
    if (!ok) {
      if (!op.completer.isCompleted) {
        op.completer.completeError(
            StateError('Proxy could not reach the directory server'));
      }
      return;
    }
    op.tcpOpened = true;
    _sendMessage(encodeEchoLinkProxyMessage(EchoLinkProxyMsgType.tcpData,
        data: op.request));
  }

  void _onTcpData(Uint8List data) {
    final _DirOp? op = _dirOp;
    if (op == null) return;
    op.collected.add(data);
    final int? max = op.maxBytes;
    if (max != null && op.collected.length >= max && !op.completer.isCompleted) {
      op.completer.complete(op.collected.toBytes());
    }
  }

  void _onTcpClose() {
    final _DirOp? op = _dirOp;
    if (op == null) return;
    if (!op.completer.isCompleted) {
      op.completer.complete(op.collected.toBytes());
    }
  }

  void _onSystem(Uint8List data) {
    final int code = data.isNotEmpty ? data[0] : 0;
    final String reason = code == echoLinkProxySystemBadPassword
        ? 'Proxy rejected the password'
        : code == echoLinkProxySystemAccessDenied
            ? 'Proxy denied access to this callsign'
            : 'Proxy reported an error ($code)';
    _onSocketDown(StateError(reason));
  }

  void _onSocketDown(Object error) {
    _fatalError ??= error;
    _state = _ProxyState.disconnected;
    _sock?.destroy();
    _sock = null;
    final Completer<void>? oc = _openCompleter;
    _openCompleter = null;
    if (oc != null && !oc.isCompleted) oc.completeError(error);
    _failPending(error);
  }

  void _failPending(Object error) {
    final _DirOp? op = _dirOp;
    _dirOp = null;
    if (op != null && !op.completer.isCompleted) {
      op.completer.completeError(error);
    }
  }

  Future<String> _resolveIpv4(String host) async {
    final List<InternetAddress> addrs =
        await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (addrs.isEmpty) {
      throw StateError('Could not resolve directory server $host');
    }
    return addrs.first.address;
  }
}
