/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// allstar_audio.dart - IAX2 media payload codec for AllStarLink.
//
// Wraps the GSM 06.10 and G.711 mu-law codecs to encode/decode the raw payload
// carried in IAX2 voice frames (no RTP header, unlike EchoLink). The negotiated
// media format selects the codec. Both operate at 8 kHz, 16-bit, mono.
//

import 'dart:typed_data';

import '../gsm/gsm_codec.dart';
import 'iax2_constants.dart';
import 'ulaw_codec.dart';

/// Samples in one GSM frame / one 20 ms voice packet at 8 kHz.
const int allStarGsmFrameSamples = 160;

/// Bytes in one encoded GSM 06.10 frame.
const int allStarGsmFrameBytes = 33;

/// Encodes 8 kHz mono PCM into IAX2 voice payloads for a single call. One
/// instance holds continuous codec state; create a new one per call.
class AllStarAudioEncoder {
  final GsmEncoder _gsm = GsmEncoder();
  final UlawCodec _ulaw = UlawCodec();

  /// Negotiated media format ([Iax2Format]). Defaults to GSM.
  int format;

  AllStarAudioEncoder({this.format = Iax2Format.gsm});

  void reset() => _gsm.reset();

  /// Number of PCM samples consumed per encoded frame for the current format.
  int get frameSamples =>
      format == Iax2Format.gsm ? allStarGsmFrameSamples : allStarGsmFrameSamples;

  /// Encodes exactly [frameSamples] samples into a voice-frame payload.
  Uint8List encodeFrame(Int16List pcm, {int pcmOff = 0}) {
    final Int16List frame = (pcmOff == 0 && pcm.length == frameSamples)
        ? pcm
        : Int16List.sublistView(pcm, pcmOff, pcmOff + frameSamples);
    switch (format) {
      case Iax2Format.ulaw:
        return _ulaw.encode(frame);
      case Iax2Format.gsm:
      default:
        return _gsm.encodeFrame(frame);
    }
  }
}

/// Decodes IAX2 voice payloads back into 8 kHz mono PCM for a single call.
class AllStarAudioDecoder {
  final GsmDecoder _gsm = GsmDecoder();
  final UlawCodec _ulaw = UlawCodec();

  /// Negotiated media format ([Iax2Format]). Defaults to GSM.
  int format;

  AllStarAudioDecoder({this.format = Iax2Format.gsm});

  void reset() => _gsm.reset();

  /// Decodes a voice-frame [payload]. For GSM the payload must be a whole number
  /// of 33-byte frames; for mu-law one byte per sample. Returns null if the
  /// payload is malformed for the current format.
  Int16List? decode(Uint8List payload) {
    switch (format) {
      case Iax2Format.ulaw:
        if (payload.isEmpty) return null;
        return _ulaw.decode(payload);
      case Iax2Format.gsm:
      default:
        if (payload.isEmpty || payload.length % allStarGsmFrameBytes != 0) {
          return null;
        }
        try {
          return _gsm.decode(payload);
        } on FormatException {
          return null;
        }
    }
  }
}
