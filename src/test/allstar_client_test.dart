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
// allstar_client_test.dart - AllStarClient orchestration over a fake IAX2
// transport: open -> online, connectTo -> call handshake -> in-call, received
// audio delivery, and clean teardown.
//

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/allstar_client.dart';
import 'package:htcommander/allstar/allstar_node.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';
import 'package:htcommander/allstar/iax2_network.dart';

/// In-memory IAX2 transport that captures sent datagrams and lets a test inject
/// received datagrams as if from the node.
class FakeIax2Network implements Iax2Network {
  final StreamController<Iax2Datagram> _in =
      StreamController<Iax2Datagram>.broadcast();
  final List<Uint8List> sent = <Uint8List>[];
  bool opened = false;

  @override
  Future<void> open({int bindPort = 0}) async {
    opened = true;
  }

  @override
  Stream<Iax2Datagram> get datagramsIn => _in.stream;

  @override
  void send(String host, int port, Uint8List data) => sent.add(data);

  @override
  Future<void> close() async {
    opened = false;
    if (!_in.isClosed) await _in.close();
  }

  void deliver(Uint8List data) =>
      _in.add(Iax2Datagram('node.example', iax2DefaultPort, data));

  /// The source call number the client assigned (from its first sent frame).
  int get clientCallNumber => Iax2FullFrame.parse(sent.first)!.sourceCallNumber;
}

Uint8List _serverFull(int subclass, int dstCall,
    {int srcCall = 777,
    int oSeqno = 0,
    int iSeqno = 0,
    int frameType = Iax2FrameType.iax,
    Iax2IeSet? ies}) {
  return Iax2FullFrame(
    sourceCallNumber: srcCall,
    destCallNumber: dstCall,
    timestamp: 10,
    oSeqno: oSeqno,
    iSeqno: iSeqno,
    frameType: frameType,
    subclass: subclass,
  ).toBytes(ies: ies);
}

void main() {
  const AllStarNode node = AllStarNode(
    name: 'Test Node',
    host: 'node.example',
    iaxUser: '12345',
    iaxSecret: 's3cret',
    nodeNumber: '2000',
  );

  late FakeIax2Network net;
  late AllStarClient client;
  late List<AllStarClientState> states;

  setUp(() {
    net = FakeIax2Network();
    states = <AllStarClientState>[];
    client = AllStarClient(network: net)..onStateChanged = states.add;
  });

  tearDown(() async => client.close());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('open moves to the online state', () async {
    await client.open();
    expect(net.opened, isTrue);
    expect(client.state, AllStarClientState.online);
  });

  test('connectTo sends a NEW and reaches in-call after the handshake', () async {
    await client.open();
    client.connectTo(node);
    expect(client.state, AllStarClientState.connecting);
    expect(net.sent, isNotEmpty);

    final int cn = net.clientCallNumber;
    final Iax2FullFrame newFrame = Iax2FullFrame.parse(net.sent.first)!;
    expect(newFrame.subclass, Iax2Subclass.newCall);
    expect(newFrame.parseIes().getString(Iax2Ie.calledNumber), '2000');

    // AUTHREQ -> client answers AUTHREP with MD5.
    final Iax2IeSet auth = Iax2IeSet()
      ..addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5)
      ..addString(Iax2Ie.challenge, 'zzz');
    net.deliver(_serverFull(Iax2Subclass.authReq, cn, oSeqno: 0, iSeqno: 1, ies: auth));
    await pump();
    expect(
        net.sent.any((Uint8List d) {
          final Iax2FullFrame? f = Iax2FullFrame.parse(d);
          return f != null &&
              f.frameType == Iax2FrameType.iax &&
              f.subclass == Iax2Subclass.authRep &&
              f.parseIes().getString(Iax2Ie.md5Result) ==
                  iax2Md5Response('zzz', 's3cret');
        }),
        isTrue);

    // ACCEPT + ANSWER -> in-call.
    final Iax2IeSet accept = Iax2IeSet()..addUint32(Iax2Ie.format, Iax2Format.gsm);
    net.deliver(_serverFull(Iax2Subclass.accept, cn, oSeqno: 1, iSeqno: 2, ies: accept));
    net.deliver(_serverFull(Iax2Control.answer, cn,
        oSeqno: 2, iSeqno: 2, frameType: Iax2FrameType.control));
    await pump();
    expect(client.state, AllStarClientState.inCall);
    expect(client.connectedNode?.nodeNumber, '2000');
  });

  test('remote hangup returns the client to online', () async {
    await client.open();
    client.connectTo(node);
    final int cn = net.clientCallNumber;
    final Iax2IeSet auth = Iax2IeSet()
      ..addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5)
      ..addString(Iax2Ie.challenge, 'q');
    net.deliver(_serverFull(Iax2Subclass.authReq, cn, oSeqno: 0, iSeqno: 1, ies: auth));
    final Iax2IeSet accept = Iax2IeSet()..addUint32(Iax2Ie.format, Iax2Format.gsm);
    net.deliver(_serverFull(Iax2Subclass.accept, cn, oSeqno: 1, iSeqno: 2, ies: accept));
    net.deliver(_serverFull(Iax2Control.answer, cn,
        oSeqno: 2, iSeqno: 2, frameType: Iax2FrameType.control));
    await pump();
    expect(client.state, AllStarClientState.inCall);

    net.deliver(_serverFull(Iax2Subclass.hangup, cn, oSeqno: 3, iSeqno: 3));
    await pump();
    expect(client.state, AllStarClientState.online);
    expect(client.connectedNode, isNull);
  });

  test('disconnect stays online', () async {
    await client.open();
    client.connectTo(node);
    client.disconnect();
    expect(client.state, AllStarClientState.online);
  });
}
