import 'dart:convert';
import 'dart:typed_data';

/// Web stub for [TtsService].
///
/// The web build has no audio channel, so text-to-speech is unavailable:
/// [getVoices] reports no voices and [synthesizeToPcm] always returns null.
/// The static [encodeVoice] / [voiceLabel] helpers stay pure so any shared
/// settings code keeps compiling, and [targetSampleRate] mirrors the real
/// implementation.
class TtsService {
  TtsService._();

  /// Shared instance.
  static final TtsService instance = TtsService._();

  /// Target PCM format expected by the radio audio path.
  static const int targetSampleRate = 32000;

  /// No text-to-speech voices are available on the web.
  Future<List<Map<String, String>>> getVoices() async =>
      const <Map<String, String>>[];

  /// Encodes a voice map into a stable string. Kept identical to the native
  /// implementation so persisted values remain compatible.
  static String encodeVoice(Map<String, String> voice) {
    return jsonEncode(<String, String>{
      if ((voice['name'] ?? '').isNotEmpty) 'name': voice['name']!,
      if ((voice['locale'] ?? '').isNotEmpty) 'locale': voice['locale']!,
      if ((voice['identifier'] ?? '').isNotEmpty)
        'identifier': voice['identifier']!,
    });
  }

  /// A human-readable label for a voice map, including its quality tier
  /// (Enhanced / Premium) when reported. Kept identical to the native build.
  static String voiceLabel(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    final base = name.isEmpty
        ? (locale.isEmpty ? 'Unknown' : locale)
        : (locale.isEmpty ? name : '$name ($locale)');
    switch (voice['quality']) {
      case 'premium':
        return '$base — Premium';
      case 'enhanced':
        return '$base — Enhanced';
      default:
        return base;
    }
  }

  /// On-device preview playback is not available on the web.
  bool get isPreviewSupported => false;

  /// Text-to-speech synthesis is never available in the web build.
  Future<bool> isAvailable() async => false;

  /// Guidance shown when [isAvailable] is false.
  String get setupInstructions =>
      'Text-to-speech is not available in the web version of the app.';

  /// No-op preview on the web (no audio channel).
  Future<void> preview(
    String text, {
    String? voiceJson,
    double? rate,
    double? pitch,
  }) async {}

  /// No-op preview stop on the web.
  Future<void> stopPreview() async {}

  /// Text-to-speech is not supported on the web, so this always returns null.
  Future<Uint8List?> synthesizeToPcm(
    String text, {
    String? voiceJson,
    double? rate,
    double? pitch,
  }) async => null;
}
