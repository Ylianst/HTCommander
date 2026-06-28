// AGWPE TCP server facade.
//
// On desktop / mobile platforms (those exposing `dart:io`) this resolves to the
// real [AgwpeServer] backed by a `ServerSocket`. On the web — which cannot open
// listening sockets — it resolves to an inert stub so `dart:io` is never
// referenced and the AGWPE server is simply unavailable.
//
// The AGWPE feature is only wired up on desktop (Windows / Linux / macOS); the
// stub keeps the web build compiling.
export 'agwpe_server_stub.dart'
    if (dart.library.io) 'agwpe_server_io.dart';
