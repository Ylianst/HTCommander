/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Native (dart:io platforms) speech-to-text factory. Pulls in the sherpa-onnx
backed engine, which depends on dart:ffi/native libraries and therefore must
NEVER be imported on web. The web build resolves to
[speech_to_text_engine_stub.dart] instead (see the conditional import in
speech_to_text_engine.dart).
*/

import 'dart:io' show Platform;

import 'android_speech_to_text_engine.dart';
import 'speech_to_text_engine.dart';
import 'sherpa_speech_to_text_engine.dart';

/// Desktop platforms use the offline sherpa-onnx recognizer. Android has no
/// bundled sherpa native libraries (they are stubbed out of the APK); instead
/// it feeds PCM into the OS on-device recognizer via
/// [AndroidSpeechToTextEngine], which requires no model download.
SpeechToTextEngine createPlatformSpeechToTextEngine() =>
    Platform.isAndroid
        ? AndroidSpeechToTextEngine()
        : SherpaSpeechToTextEngine();
