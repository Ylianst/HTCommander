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
// app_database_stub.dart - Web build of [AppDatabase]. The web target has no
// dart:io / SQLite, so the database is always absent: [instance] is null and
// every store falls back to its in-memory behaviour. This keeps sqflite and
// dart:ffi out of the web bundle entirely (see the conditional export in
// app_database.dart).
//

/// No-op stand-in for the SQLite database on web. [instance] is always null, so
/// the DAO getters are never actually invoked; they exist only to satisfy the
/// call sites (`AppDatabase.instance?.comms`).
class AppDatabase {
  AppDatabase._();

  /// Always null on web.
  static AppDatabase? get instance => null;

  /// No database on web.
  dynamic get comms => null;

  /// No database on web.
  dynamic get packets => null;

  /// No database on web.
  dynamic get aprsis => null;

  /// No-op on web.
  static Future<void> open() async {}

  /// No-op on web.
  static Future<void> close() async {}
}
