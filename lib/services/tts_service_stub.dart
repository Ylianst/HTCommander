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

  /// A human-readable label for a voice map.
  static String voiceLabel(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    if (name.isEmpty) return locale.isEmpty ? 'Unknown' : locale;
    return locale.isEmpty ? name : '$name ($locale)';
  }

  /// Text-to-speech is not supported on the web, so this always returns null.
  Future<Uint8List?> synthesizeToPcm(
    String text, {
    String? voiceJson,
    double? rate,
    double? pitch,
  }) async => null;
}
