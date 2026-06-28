// Static web server facade.
//
// On desktop / mobile platforms (those exposing `dart:io`) this resolves to the
// real [WebServer] backed by an `HttpServer`. On the web — which cannot open
// listening sockets — it resolves to an inert stub so `dart:io` is never
// referenced.
//
// The web server feature is only wired up on desktop (Windows / Linux / macOS);
// the stub keeps the web/iOS/Android builds compiling.
export 'web_server_stub.dart'
    if (dart.library.io) 'web_server_io.dart';
