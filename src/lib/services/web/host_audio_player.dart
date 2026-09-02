/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Facade for [HostAudioPlayer]. On the web build it resolves to a Web Audio
implementation that plays the desktop host's streamed PCM in the browser; on
every other platform it resolves to an inert stub (those platforms play audio
natively and never need this).
*/

export 'host_audio_player_web.dart'
    if (dart.library.io) 'host_audio_player_stub.dart';
