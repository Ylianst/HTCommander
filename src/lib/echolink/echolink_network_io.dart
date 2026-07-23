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
// echolink_network_io.dart - dart:io implementation of EchoLinkNetwork.
//
// Binds the two EchoLink UDP ports (5198 audio / 5199 control) and performs the
// short-lived TCP directory exchange (port 5200). Not exercised by unit tests
// (real sockets); the client's logic is tested against a fake network.
//

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'echolink_directory.dart';
import 'echolink_qso.dart';
import 'echolink_network.dart';

class DartIoEchoLinkNetwork implements EchoLinkNetwork {
  RawDatagramSocket? _audioSock;
  RawDatagramSocket? _controlSock;
  StreamSubscription<RawSocketEvent>? _audioSub;
  StreamSubscription<RawSocketEvent>? _controlSub;

  final StreamController<EchoLinkDatagram> _audioIn =
      StreamController<EchoLinkDatagram>.broadcast();
  final StreamController<EchoLinkDatagram> _controlIn =
      StreamController<EchoLinkDatagram>.broadcast();

  /// Timeout for the directory TCP exchange.
  final Duration directoryTimeout;

  DartIoEchoLinkNetwork({
    this.directoryTimeout = const Duration(seconds: 15),
  });

  @override
  Stream<EchoLinkDatagram> get audioIn => _audioIn.stream;

  @override
  Stream<EchoLinkDatagram> get controlIn => _controlIn.stream;

  @override
  Future<void> open() async {
    final RawDatagramSocket audioSock =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, echoLinkAudioPort);
    final RawDatagramSocket controlSock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, echoLinkControlPort);
    _audioSock = audioSock;
    _controlSock = controlSock;

    _audioSub =
        audioSock.listen((RawSocketEvent e) => _onRead(audioSock, _audioIn, e));
    _controlSub = controlSock
        .listen((RawSocketEvent e) => _onRead(controlSock, _controlIn, e));
  }

  void _onRead(RawDatagramSocket sock, StreamController<EchoLinkDatagram> out,
      RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final Datagram? dg = sock.receive();
    if (dg == null) return;
    out.add(EchoLinkDatagram(
        dg.address.address, dg.port, Uint8List.fromList(dg.data)));
  }

  @override
  void sendAudio(String host, Uint8List data) {
    _sendTo(_audioSock, host, echoLinkAudioPort, data);
  }

  @override
  void sendControl(String host, Uint8List data) {
    _sendTo(_controlSock, host, echoLinkControlPort, data);
  }

  void _sendTo(RawDatagramSocket? sock, String host, int port, Uint8List data) {
    if (sock == null) return;
    sock.send(data, InternetAddress(host), port);
  }

  @override
  Future<Uint8List> directoryExchange(
      List<String> servers, Uint8List request,
      {int? maxBytes}) async {
    Object? lastError;
    for (final String server in servers) {
      Socket? socket;
      try {
        socket = await Socket.connect(server, directoryServerPort,
            timeout: directoryTimeout);
        socket.add(request);
        await socket.flush();

        final BytesBuilder buf = BytesBuilder();
        await for (final List<int> chunk
            in socket.timeout(directoryTimeout)) {
          buf.add(chunk);
          if (maxBytes != null && buf.length >= maxBytes) break;
        }
        return buf.toBytes();
      } catch (e) {
        lastError = e;
      } finally {
        socket?.destroy();
      }
    }
    throw StateError('Directory exchange failed: $lastError');
  }

  @override
  Future<void> close() async {
    await _audioSub?.cancel();
    await _controlSub?.cancel();
    _audioSub = null;
    _controlSub = null;
    _audioSock?.close();
    _controlSock?.close();
    _audioSock = null;
    _controlSock = null;
    await _audioIn.close();
    await _controlIn.close();
  }
}
