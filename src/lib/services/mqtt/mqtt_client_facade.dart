/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

MQTT client facade.

On desktop / mobile platforms (those exposing `dart:io`) this resolves to the
real [MqttClientFacade] backed by `package:mqtt_client`'s `MqttServerClient`. On
the web — which cannot open the plain TCP sockets MQTT needs — it resolves to an
inert stub so `dart:io` is never referenced.

The Home Assistant bridge that uses this is only wired up on desktop
(Windows / Linux / macOS); the stub keeps the web/iOS/Android builds compiling.
*/

export 'mqtt_client_stub.dart'
    if (dart.library.io) 'mqtt_client_io.dart';
