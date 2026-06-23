/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web speech-to-text factory. Speech-to-text is intentionally unavailable on the
web build: the sherpa-onnx recognizer depends on dart:ffi/native libraries that
do not exist in the browser. This stub keeps those dependencies out of the web
compilation entirely (it is selected by the conditional import in
speech_to_text_engine.dart whenever dart.library.io is absent).
*/

import 'speech_to_text_engine.dart';

/// Web has no PCM-buffer recognizer, so speech-to-text is disabled.
SpeechToTextEngine createPlatformSpeechToTextEngine() =>
    UnsupportedSpeechToTextEngine();
