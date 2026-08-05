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
// allstar_node_handler_stub.dart - Web no-op for AllStarNodeHandler. Hosting an
// AllStarLink node needs dart:io UDP sockets, which are unavailable on the web,
// so this stub keeps `main()` compiling for web builds.
//

import 'dart:async';

/// No-op stand-in used on platforms without dart:io sockets.
class AllStarNodeHandler {
  bool get isHosting => false;
  int get hostedRadioDeviceId => -1;

  void init() {}

  Future<void> start(int radioDeviceId) async {}

  Future<void> stop() async {}
}
