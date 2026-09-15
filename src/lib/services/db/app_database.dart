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
// app_database.dart - Single embedded SQLite database for high-churn event
// history (comms events, RF packets, APRS-IS history).
//
// Replaces the previous flat-file stores (voicetext.json full rewrites,
// packets.ptcap and aprsis_history.txt append/compact). SQLite in WAL mode
// turns every add into a tiny incremental write and makes retention an indexed
// DELETE, which matters on SD-card hosts (e.g. Raspberry Pi) and removes the
// whole-file-rewrite data-loss window.
//
// This is a conditional-export barrel: desktop and mobile get the real SQLite
// implementation (app_database_io.dart); the web build gets a no-op stub
// (app_database_stub.dart) so sqflite / dart:ffi are never bundled for web. On
// web [AppDatabase.instance] is null and every store keeps its in-memory
// behaviour, exactly as it did before. Detached desktop sub-windows are broker
// clients that mirror the host, so only the host/main process calls [open].
//

export 'app_database_stub.dart' if (dart.library.io) 'app_database_io.dart';
