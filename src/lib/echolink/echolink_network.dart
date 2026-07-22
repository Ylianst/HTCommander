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
// echolink_network.dart - Networking abstraction for the EchoLink client.
//
// The client depends only on this interface so its orchestration logic can be
// unit-tested with a fake. A real dart:io implementation lives in
// echolink_network_io.dart.
//

import 'dart:async';
import 'dart:typed_data';

/// A datagram received on one of the EchoLink UDP ports.
class EchoLinkDatagram {
  final String host;
  final int port;
  final Uint8List data;
  const EchoLinkDatagram(this.host, this.port, this.data);
}

/// Transport used by the EchoLink client: two UDP ports (audio 5198 / control
/// 5199) and a short-lived TCP exchange with a directory server (5200).
abstract class EchoLinkNetwork {
  /// Binds the UDP sockets. Must be called before sending/receiving.
  Future<void> open();

  /// Datagrams received on the audio port (5198): voice and info/chat.
  Stream<EchoLinkDatagram> get audioIn;

  /// Datagrams received on the control port (5199): RTCP SDES/BYE.
  Stream<EchoLinkDatagram> get controlIn;

  /// Sends a datagram to [host] on the audio port.
  void sendAudio(String host, Uint8List data);

  /// Sends a datagram to [host] on the control port.
  void sendControl(String host, Uint8List data);

  /// Opens a TCP connection to the first reachable [servers] entry on the
  /// directory port, writes [request], reads the full response until the server
  /// closes, and returns it.
  Future<Uint8List> directoryExchange(List<String> servers, Uint8List request);

  /// Closes the UDP sockets and releases resources.
  Future<void> close();
}
