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
// allstar_wt_test.dart - AllStarLink portal (Web Transceiver) account auth:
// token exchange, node model serialization of the auth mode, and the
// account-mode IAX2 NEW frame (fixed public user + token as CallerID name).
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/allstar_node.dart';
import 'package:htcommander/allstar/allstar_portal_service.dart';
import 'package:htcommander/allstar/iax2_call.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AllStarNode auth mode', () {
    test('defaults to node auth and round-trips through a map', () {
      const AllStarNode n = AllStarNode(
        name: 'Repeater',
        host: 'node.example.com',
        port: 4569,
        iaxUser: 'user',
        iaxSecret: 'secret',
        nodeNumber: '2000',
      );
      expect(n.authMode, AllStarAuthMode.node);
      final AllStarNode back = AllStarNode.fromMap(n.toMap());
      expect(back.authMode, AllStarAuthMode.node);
      expect(back.effectiveHost, 'node.example.com');
      expect(back.effectivePort, 4569);
    });

    test('account mode resolves host from the node number via DNS', () {
      const AllStarNode n = AllStarNode(
        name: 'Hub',
        host: '',
        iaxUser: '',
        iaxSecret: '',
        nodeNumber: '50000',
        authMode: AllStarAuthMode.account,
      );
      final AllStarNode back = AllStarNode.fromMap(n.toMap());
      expect(back.authMode, AllStarAuthMode.account);
      expect(back.effectiveHost, '50000.nodes.allstarlink.org');
      expect(back.effectivePort, iax2DefaultPort);
    });

    test('legacy maps without AuthMode load as node auth', () {
      final AllStarNode back = AllStarNode.fromMap(<String, Object?>{
        'Name': 'Old',
        'Host': 'h',
        'Port': 4569,
        'User': 'u',
        'Secret': 's',
        'NodeNumber': '1',
      });
      expect(back.authMode, AllStarAuthMode.node);
    });
  });

  group('AllStarPortalService', () {
    test('returns the token on a successful auth response', () async {
      final MockClient client = MockClient((http.Request req) async {
        expect(req.method, 'POST');
        final Map<String, dynamic> body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['username'], 'W1AW');
        expect(body['password'], 'pw');
        return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'OK',
              'auth': 1,
              'token': 'abc123',
              'msg': '',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final AllStarPortalService service = AllStarPortalService(client: client);
      final AllStarWtAuthResult r =
          await service.fetchToken(username: 'W1AW', password: 'pw');
      expect(r.success, isTrue);
      expect(r.token, 'abc123');
    });

    test('reports failure on a login-failed response', () async {
      final MockClient client = MockClient((http.Request req) async {
        return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'ERR',
              'auth': 0,
              'token': '',
              'msg': 'login failed',
            }),
            401,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final AllStarPortalService service = AllStarPortalService(client: client);
      final AllStarWtAuthResult r =
          await service.fetchToken(username: 'W1AW', password: 'bad');
      expect(r.success, isFalse);
      expect(r.token, isEmpty);
      expect(r.message, 'login failed');
    });
  });

  group('Iax2Call account (Web Transceiver) NEW frame', () {
    test('uses the public user and carries the token as CallerID name', () {
      final List<Iax2FullFrame> sent = <Iax2FullFrame>[];
      final Iax2Call call = Iax2Call(
        username: 'allstar-public',
        secret: 'allstar',
        calledNumber: '50000',
        callingNumber: '50000',
        callingName: 'tok-xyz',
        onSend: (Uint8List d) {
          if (iax2IsFullFrame(d)) sent.add(Iax2FullFrame.parse(d)!);
        },
        onAudio: (_) {},
        onStateChanged: (_) {},
      );
      call.connect(srcCallNumber: 1);
      final Iax2FullFrame newFrame = sent.lastWhere((Iax2FullFrame f) =>
          f.frameType == Iax2FrameType.iax &&
          f.subclass == Iax2Subclass.newCall);
      final Iax2IeSet ies = newFrame.parseIes();
      expect(ies.getString(Iax2Ie.username), 'allstar-public');
      expect(ies.getString(Iax2Ie.callingNumber), '50000');
      expect(ies.getString(Iax2Ie.callingName), 'tok-xyz');
      call.disconnect();
    });
  });
}
