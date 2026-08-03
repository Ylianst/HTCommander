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
// iax2_network.dart - Networking abstraction for the IAX2 client. IAX2
// multiplexes all signaling and media over a single UDP association, so the
// transport is one socket. The client depends only on this interface so its
// call logic can be unit-tested with a fake.
//

import 'dart:async';
import 'dart:typed_data';

/// A datagram received on the IAX2 UDP socket.
class Iax2Datagram {
  final String host;
  final int port;
  final Uint8List data;
  const Iax2Datagram(this.host, this.port, this.data);
}

/// Single-socket UDP transport for IAX2.
abstract class Iax2Network {
  /// Binds the UDP socket. Must be called before sending/receiving.
  Future<void> open();

  /// Datagrams received on the socket.
  Stream<Iax2Datagram> get datagramsIn;

  /// Sends [data] to [host]:[port].
  void send(String host, int port, Uint8List data);

  /// Closes the socket and releases resources.
  Future<void> close();
}
