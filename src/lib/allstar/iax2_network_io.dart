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
// iax2_network_io.dart - dart:io implementation of Iax2Network. Binds one UDP
// socket on an ephemeral local port; IAX2 replies come back to that same port.
// Host names are resolved once and cached. Not exercised by unit tests (real
// sockets); the call logic is tested against a fake network.
//

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'iax2_network.dart';

class DartIoIax2Network implements Iax2Network {
  RawDatagramSocket? _sock;
  StreamSubscription<RawSocketEvent>? _sub;
  final Map<String, InternetAddress> _resolved = <String, InternetAddress>{};

  final StreamController<Iax2Datagram> _in =
      StreamController<Iax2Datagram>.broadcast();

  @override
  Stream<Iax2Datagram> get datagramsIn => _in.stream;

  @override
  Future<void> open() async {
    final RawDatagramSocket sock =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _sock = sock;
    _sub = sock.listen(_onEvent);
  }

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final RawDatagramSocket? sock = _sock;
    if (sock == null) return;
    final Datagram? dg = sock.receive();
    if (dg == null) return;
    _in.add(Iax2Datagram(
        dg.address.address, dg.port, Uint8List.fromList(dg.data)));
  }

  @override
  void send(String host, int port, Uint8List data) {
    final RawDatagramSocket? sock = _sock;
    if (sock == null) return;
    final InternetAddress? addr = _resolved[host];
    if (addr != null) {
      sock.send(data, addr, port);
      return;
    }
    // Fast path for literal IPs; otherwise resolve and cache asynchronously.
    final InternetAddress? literal = InternetAddress.tryParse(host);
    if (literal != null) {
      _resolved[host] = literal;
      sock.send(data, literal, port);
      return;
    }
    _resolveAndSend(host, port, data);
  }

  Future<void> _resolveAndSend(String host, int port, Uint8List data) async {
    try {
      final List<InternetAddress> addrs =
          await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      if (addrs.isEmpty) return;
      final InternetAddress addr = addrs.first;
      _resolved[host] = addr;
      _sock?.send(data, addr, port);
    } catch (_) {
      // Resolution failure: drop the datagram; the call layer will time out.
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _sock?.close();
    _sock = null;
    if (!_in.isClosed) await _in.close();
  }
}
