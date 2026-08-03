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
// allstar_node.dart - A saved AllStarLink node the user can call (DVSwitch /
// iaxrpt style). Holds the IAX2 connection parameters and is round-tripped to
// JSON for persistence on Data Broker device 0.
//

import 'iax2_constants.dart';

/// DataBroker key (device 0, persisted) holding the saved node list.
const String allStarNodesKey = 'AllStarNodes';

/// DataBroker key (device 0, persisted) holding the last node connected to, for
/// auto-reconnect on the next launch.
const String lastAllStarNodeKey = 'LastAllStarNode';

/// DataBroker key (device 0, persisted) recording whether AllStarLink was online
/// (connected as a radio) when the app last closed.
const String allStarWasOnlineKey = 'AllStarWasOnline';

class AllStarNode {
  /// Friendly display name shown in the UI (e.g. "My Repeater").
  final String name;

  /// Node host name or IP address to place the IAX2 call to.
  final String host;

  /// UDP port of the node (default 4569).
  final int port;

  /// IAX2 username configured for this client in the node's iax.conf.
  final String iaxUser;

  /// Shared IAX2 secret (password) for MD5 authentication.
  final String iaxSecret;

  /// AllStarLink node number to connect to (the IAX2 "called number").
  final String nodeNumber;

  const AllStarNode({
    required this.name,
    required this.host,
    this.port = iax2DefaultPort,
    required this.iaxUser,
    required this.iaxSecret,
    required this.nodeNumber,
  });

  /// Text shown as the node's subtitle: node number plus host.
  String get description {
    final String n = nodeNumber.isNotEmpty ? nodeNumber : '?';
    return '$n @ $host';
  }

  AllStarNode copyWith({
    String? name,
    String? host,
    int? port,
    String? iaxUser,
    String? iaxSecret,
    String? nodeNumber,
  }) {
    return AllStarNode(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      iaxUser: iaxUser ?? this.iaxUser,
      iaxSecret: iaxSecret ?? this.iaxSecret,
      nodeNumber: nodeNumber ?? this.nodeNumber,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'Name': name,
        'Host': host,
        'Port': port,
        'User': iaxUser,
        'Secret': iaxSecret,
        'NodeNumber': nodeNumber,
      };

  static AllStarNode fromMap(Map<dynamic, dynamic> m) {
    int parsePort(Object? v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? iax2DefaultPort;
      return iax2DefaultPort;
    }

    String str(Object? a, Object? b) =>
        (a ?? b ?? '').toString();

    return AllStarNode(
      name: str(m['Name'], m['name']),
      host: str(m['Host'], m['host']),
      port: parsePort(m['Port'] ?? m['port']),
      iaxUser: str(m['User'], m['user']),
      iaxSecret: str(m['Secret'], m['secret']),
      nodeNumber: str(m['NodeNumber'], m['nodeNumber']),
    );
  }

  /// A stable key used to identify this node (name + host + node number).
  String get key => '$name|$host|$nodeNumber';
}
