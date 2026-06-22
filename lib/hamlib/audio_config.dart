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
// audio_config.dart - Audio configuration structures
//
// Ported from C# HamLib/AudioConfig.cs
//

/// Modem types.
enum ModemType {
  afsk,
  baseband,
  scramble,
  qpsk,
  psk8,
  off,
  qam16,
  qam64,
  ais,
  eas,
}

/// Layer 2 protocol types.
enum Layer2Type {
  ax25, // = 0
  fx25,
  il2p,
}

/// V.26 alternatives.
enum V26Alternative {
  unspecified, // = 0
  a,
  b,
}

/// Channel medium type.
enum Medium {
  none, // = 0
  radio,
  igate,
  netTnc,
}

/// Audio channel parameters.
class AudioChannelConfig {
  ModemType modemType = ModemType.afsk;
  Layer2Type layer2Xmit = Layer2Type.ax25;
  int markFreq = 1200;
  int spaceFreq = 2200;
  int baud = 1200;
  V26Alternative v26Alt = V26Alternative.b;
  int fx25Strength = 1;
  int il2pMaxFec = 0;
  bool il2pInvertPolarity = false;
  int decimate = 1;
  int upsample = 1;
  int numFreq = 1;
  int offset = 0;
  int numSlicers = 1;
  int numSubchan = 1;

  // Transmit timing parameters
  int dwait = 0;
  int slottime = 10;
  int persist = 63;
  int txdelay = 30;
  int txtail = 10;
  int fulldup = 0;
}

/// Audio device parameters.
class AudioDeviceConfig {
  bool defined = false;
  String deviceIn = '';
  String deviceOut = '';
  int numChannels = 1;
  int samplesPerSec = 44100;
  int bitsPerSample = 16;
}

/// Main audio configuration structure.
class AudioConfig {
  static const int maxAudioDevices = 3;
  static const int maxRadioChannels = 6;
  static const int maxTotalChannels = 16;
  static const int maxSubchannels = 9;
  static const int maxSlicers = 9;

  late List<AudioDeviceConfig> devices;
  late List<AudioChannelConfig> channels;
  late List<Medium> channelMedium;
  late List<String> myCall;

  AudioConfig() {
    devices = List<AudioDeviceConfig>.generate(
      maxAudioDevices,
      (_) => AudioDeviceConfig(),
    );
    channels = List<AudioChannelConfig>.generate(
      maxRadioChannels,
      (_) => AudioChannelConfig(),
    );
    channelMedium = List<Medium>.filled(maxTotalChannels, Medium.none);
    myCall = List<String>.filled(maxTotalChannels, '');
  }

  /// Get audio device index for a given channel.
  static int channelToDevice(int channel) {
    return channel >> 1;
  }

  /// Get first channel for a given device.
  static int deviceFirstChannel(int device) {
    return device * 2;
  }
}
