import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// Wraps [FlutterTts] to convert text into 32 kHz / mono / signed 16-bit
/// little-endian PCM suitable for transmission through the radio audio path
/// (same format as the Morse/DTMF/SSTV PCM producers).
///
/// Text-to-speech is rendered to an audio file by the platform engine
/// (`synthesizeToFile`), then decoded (WAV or CAF), down-mixed to mono and
/// resampled to 32 kHz before being returned as raw PCM bytes.
class TtsService {
  TtsService._();

  /// Shared instance.
  static final TtsService instance = TtsService._();

  /// Target PCM format expected by the radio audio path.
  static const int targetSampleRate = 32000;

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    // Make synthesizeToFile() resolve only once the file has been written.
    await _tts.awaitSynthCompletion(true);
    _initialized = true;
  }

  /// Returns the list of available voices. Each entry is a map containing at
  /// least `name` and `locale`, and on Apple platforms also `identifier`,
  /// `quality` and `gender`.
  Future<List<Map<String, String>>> getVoices() async {
    await _ensureInit();
    final result = <Map<String, String>>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            result.add(
              v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? '')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('TtsService.getVoices failed: $e');
    }
    return result;
  }

  /// Encodes a voice map (as returned by [getVoices]) into a stable string that
  /// can be persisted and later passed to [synthesizeToPcm].
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

  /// Synthesizes [text] and returns 32 kHz / mono / signed 16-bit LE PCM, or
  /// null if synthesis or decoding failed (e.g. on a platform without
  /// `synthesizeToFile` support).
  ///
  /// [voiceJson] is a string produced by [encodeVoice]. [rate] and [pitch] are
  /// passed straight to the engine (rate 0.0-1.0, pitch 0.5-2.0).
  Future<Uint8List?> synthesizeToPcm(
    String text, {
    String? voiceJson,
    double? rate,
    double? pitch,
  }) async {
    if (text.trim().isEmpty) return null;
    await _ensureInit();

    try {
      if (rate != null) await _tts.setSpeechRate(rate);
      if (pitch != null) await _tts.setPitch(pitch);
      if (voiceJson != null && voiceJson.isNotEmpty) {
        await _applyVoice(voiceJson);
      }
    } catch (e) {
      debugPrint('TtsService: failed to apply voice settings: $e');
    }

    final Directory docDir = await getApplicationDocumentsDirectory();
    final String fileName =
        'htc_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    // On Apple platforms the plugin ignores the path and writes to the
    // documents directory using the file name; on Android passing isFullPath
    // true writes to the given path. Resolve both to docDir/fileName.
    final String filePath = '${docDir.path}/$fileName';
    final File file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    try {
      await _tts.synthesizeToFile(
        text,
        Platform.isAndroid ? filePath : fileName,
        true,
      );
    } catch (e) {
      debugPrint('TtsService.synthesizeToFile failed: $e');
      return null;
    }

    if (!await file.exists()) {
      debugPrint('TtsService: synthesized file not found at $filePath');
      return null;
    }

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }

    final _DecodedAudio? decoded = _decodeAudio(bytes);
    if (decoded == null || decoded.samples.isEmpty) {
      debugPrint('TtsService: failed to decode synthesized audio');
      return null;
    }

    return _toPcm16Mono(decoded.samples, decoded.sampleRate);
  }

  Future<void> _applyVoice(String voiceJson) async {
    final Object? decoded = jsonDecode(voiceJson);
    if (decoded is! Map) return;
    final voice = <String, String>{};
    final id = decoded['identifier']?.toString();
    final name = decoded['name']?.toString();
    final locale = decoded['locale']?.toString();
    if (id != null && id.isNotEmpty) voice['identifier'] = id;
    if (name != null && name.isNotEmpty) voice['name'] = name;
    if (locale != null && locale.isNotEmpty) voice['locale'] = locale;
    if (voice.isNotEmpty) await _tts.setVoice(voice);
  }

  // ---------------------------------------------------------------------------
  // Audio file decoding (WAV / CAF) -> mono float samples
  // ---------------------------------------------------------------------------

  _DecodedAudio? _decodeAudio(Uint8List bytes) {
    if (bytes.length < 12) return null;
    // 'RIFF' .... 'WAVE'
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return _decodeWav(bytes);
    }
    // 'caff'
    if (bytes[0] == 0x63 &&
        bytes[1] == 0x61 &&
        bytes[2] == 0x66 &&
        bytes[3] == 0x66) {
      return _decodeCaf(bytes);
    }
    return null;
  }

  _DecodedAudio? _decodeWav(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    // 'WAVE'
    if (!(bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45)) {
      return null;
    }
    int pos = 12;
    int format = 1;
    int channels = 1;
    int sampleRate = 22050;
    int bits = 16;
    int dataOffset = -1;
    int dataLen = 0;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = bd.getUint16(body, Endian.little);
        channels = bd.getUint16(body + 2, Endian.little);
        sampleRate = bd.getUint32(body + 4, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
        // WAVE_FORMAT_EXTENSIBLE: the real format tag is in the sub-format GUID.
        if (format == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
          format = bd.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        dataOffset = body;
        dataLen = size;
        break;
      }
      // Chunks are word-aligned.
      pos = body + size + (size & 1);
    }
    if (dataOffset < 0) return null;
    if (dataOffset + dataLen > bytes.length)
      dataLen = bytes.length - dataOffset;
    final samples = _pcmToFloatMono(
      bd,
      dataOffset,
      dataLen,
      format,
      bits,
      channels,
      Endian.little,
      eightBitUnsigned: true,
    );
    return _DecodedAudio(samples, sampleRate);
  }

  _DecodedAudio? _decodeCaf(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    // 'caff' (4) + version (2) + flags (2)
    int pos = 8;
    double sampleRate = 22050;
    int formatFlags = 0;
    int channels = 1;
    int bits = 16;
    String formatId = 'lpcm';
    int dataOffset = -1;
    int dataLen = 0;
    while (pos + 12 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getInt64(pos + 4, Endian.big);
      final body = pos + 12;
      if (id == 'desc' && body + 32 <= bytes.length) {
        sampleRate = bd.getFloat64(body, Endian.big);
        formatId = String.fromCharCodes(bytes.sublist(body + 8, body + 12));
        formatFlags = bd.getUint32(body + 12, Endian.big);
        channels = bd.getUint32(body + 24, Endian.big);
        bits = bd.getUint32(body + 28, Endian.big);
      } else if (id == 'data') {
        // First 4 bytes of the data chunk are the edit count.
        dataOffset = body + 4;
        dataLen = size < 0 ? bytes.length - dataOffset : size - 4;
        break;
      }
      if (size < 0) break;
      pos = body + size;
    }
    if (dataOffset < 0 || formatId != 'lpcm') return null;
    final bool isFloat = (formatFlags & 0x1) != 0;
    final bool isLittleEndian = (formatFlags & 0x2) != 0;
    final Endian endian = isLittleEndian ? Endian.little : Endian.big;
    if (dataOffset + dataLen > bytes.length)
      dataLen = bytes.length - dataOffset;
    final samples = _pcmToFloatMono(
      bd,
      dataOffset,
      dataLen,
      isFloat ? 3 : 1,
      bits,
      channels,
      endian,
      eightBitUnsigned: false,
    );
    return _DecodedAudio(samples, sampleRate.round());
  }

  /// Converts interleaved PCM into mono float samples in the range [-1, 1].
  /// [format] is 1 for integer PCM and 3 for IEEE float.
  Float32List _pcmToFloatMono(
    ByteData bd,
    int offset,
    int len,
    int format,
    int bits,
    int channels,
    Endian endian, {
    required bool eightBitUnsigned,
  }) {
    final int bytesPerSample = bits ~/ 8;
    if (bytesPerSample == 0 || channels <= 0) return Float32List(0);
    final int frameSize = bytesPerSample * channels;
    final int frames = len ~/ frameSize;
    final out = Float32List(frames);
    for (int f = 0; f < frames; f++) {
      double sum = 0;
      for (int c = 0; c < channels; c++) {
        final int p = offset + f * frameSize + c * bytesPerSample;
        double v = 0;
        if (format == 3) {
          v = bits == 64 ? bd.getFloat64(p, endian) : bd.getFloat32(p, endian);
        } else {
          switch (bits) {
            case 8:
              v = eightBitUnsigned
                  ? (bd.getUint8(p) - 128) / 128.0
                  : bd.getInt8(p) / 128.0;
              break;
            case 16:
              v = bd.getInt16(p, endian) / 32768.0;
              break;
            case 24:
              int b0, b1, b2;
              if (endian == Endian.little) {
                b0 = bd.getUint8(p);
                b1 = bd.getUint8(p + 1);
                b2 = bd.getUint8(p + 2);
              } else {
                b2 = bd.getUint8(p);
                b1 = bd.getUint8(p + 1);
                b0 = bd.getUint8(p + 2);
              }
              int val = b0 | (b1 << 8) | (b2 << 16);
              if ((val & 0x800000) != 0) val -= 0x1000000;
              v = val / 8388608.0;
              break;
            case 32:
              v = bd.getInt32(p, endian) / 2147483648.0;
              break;
          }
        }
        sum += v;
      }
      out[f] = sum / channels;
    }
    return out;
  }

  /// Resamples mono float samples to [targetSampleRate] and packs them into
  /// signed 16-bit little-endian PCM bytes.
  Uint8List _toPcm16Mono(Float32List samples, int srcRate) {
    if (samples.isEmpty || srcRate <= 0) return Uint8List(0);
    Float32List resampled;
    if (srcRate == targetSampleRate) {
      resampled = samples;
    } else {
      final int outLen = (samples.length * targetSampleRate / srcRate).floor();
      resampled = Float32List(outLen);
      final double ratio = srcRate / targetSampleRate;
      for (int i = 0; i < outLen; i++) {
        final double srcPos = i * ratio;
        final int i0 = srcPos.floor();
        final int i1 = (i0 + 1 < samples.length) ? i0 + 1 : i0;
        final double frac = srcPos - i0;
        resampled[i] = samples[i0] * (1 - frac) + samples[i1] * frac;
      }
    }
    final out = Uint8List(resampled.length * 2);
    final bd = ByteData.sublistView(out);
    for (int i = 0; i < resampled.length; i++) {
      double s = resampled[i];
      if (s > 1) s = 1;
      if (s < -1) s = -1;
      bd.setInt16(i * 2, (s * 32767).round(), Endian.little);
    }
    return out;
  }
}

class _DecodedAudio {
  _DecodedAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;
}
