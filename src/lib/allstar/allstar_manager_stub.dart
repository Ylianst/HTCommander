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
// allstar_manager_stub.dart - No-op AllStarLink manager for the web build.
//
// AllStarLink relies on dart:io UDP sockets and native audio, neither of which
// exist in the browser. `main.dart` conditionally imports this stub on web so
// the AllStarLink glue is never compiled there.
//

/// Web stub: does nothing. Mirrors the real [AllStarManager] surface used by
/// `main()`.
class AllStarManager {
  AllStarManager();

  void init() {}

  Future<void> dispose() async {}
}
