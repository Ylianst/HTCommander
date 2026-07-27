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
// aprsis_manager_stub.dart - No-op APRS-IS manager for the web build.
//
// APRS-IS relies on dart:io TCP sockets, which do not exist in the browser.
// `main.dart` conditionally imports this stub on web so the APRS-IS glue is
// never compiled there.
//

/// Web stub: does nothing. Mirrors the real [AprsIsManager] surface used by
/// `main()`.
class AprsIsManager {
  AprsIsManager();

  void init() {}

  Future<void> dispose() async {}
}
