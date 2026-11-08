// HTTP BBS server facade.
//
// On platforms exposing `dart:io` this resolves to the real [BbsWebServer]
// backed by an `HttpServer`. On the web — which cannot open listening sockets —
// it resolves to an inert stub so `dart:io` is never referenced.
export 'bbs_web_server_stub.dart'
    if (dart.library.io) 'bbs_web_server_io.dart';
