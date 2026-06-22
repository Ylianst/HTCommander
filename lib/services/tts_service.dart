// Text-to-speech facade.
//
// On platforms with `dart:io` (desktop / mobile) this resolves to the real
// `TtsService` backed by `flutter_tts`. On the web — which has no audio
// channel — it resolves to an inert stub so `flutter_tts` is never referenced
// and text-to-speech is simply unavailable.
export 'tts_service_stub.dart' if (dart.library.io) 'tts_service_io.dart';
