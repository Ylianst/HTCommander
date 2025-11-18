/*
Copyright 2025 Ylian Saint-Hilaire

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
// AudioConfig.cs - Audio configuration structures
//

namespace HamLib
{
    /// <summary>
    /// Modem types
    /// </summary>
    public enum ModemType
    {
        Afsk,
        Baseband,
        Scramble,
        Qpsk,
        Psk8,
        Off,
        Qam16,
        Qam64,
        Ais,
        Eas
    }

    /// <summary>
    /// Layer 2 protocol types
    /// </summary>
    public enum Layer2Type
    {
        Ax25 = 0,
        Fx25,
        Il2p
    }

    /// <summary>
    /// V.26 alternatives
    /// </summary>
    public enum V26Alternative
    {
        Unspecified = 0,
        A,
        B
    }

    /// <summary>
    /// Channel medium type
    /// </summary>
    public enum Medium
    {
        None = 0,
        Radio,
        Igate,
        NetTnc
    }

    /// <summary>
    /// Audio channel parameters
    /// </summary>
    public class AudioChannelConfig
    {
        public ModemType ModemType { get; set; } = ModemType.Afsk;
        public Layer2Type Layer2Xmit { get; set; } = Layer2Type.Ax25;
        public int MarkFreq { get; set; } = 1200;
        public int SpaceFreq { get; set; } = 2200;
        public int Baud { get; set; } = 1200;
        public V26Alternative V26Alt { get; set; } = V26Alternative.B;
        public int Fx25Strength { get; set; } = 1;
        public int Il2pMaxFec { get; set; } = 0;
        public bool Il2pInvertPolarity { get; set; } = false;
        public int Decimate { get; set; } = 1;
        public int Upsample { get; set; } = 1;
        public int NumFreq { get; set; } = 1;
        public int Offset { get; set; } = 0;
        public int NumSlicers { get; set; } = 1;
        public int NumSubchan { get; set; } = 1;
        
        // Transmit timing parameters
        public int Dwait { get; set; } = 0;
        public int Slottime { get; set; } = 10;
        public int Persist { get; set; } = 63;
        public int Txdelay { get; set; } = 30;
        public int Txtail { get; set; } = 10;
        public int Fulldup { get; set; } = 0;
    }

    /// <summary>
    /// Audio device parameters
    /// </summary>
    public class AudioDeviceConfig
    {
        public bool Defined { get; set; } = false;
        public string DeviceIn { get; set; } = "";
        public string DeviceOut { get; set; } = "";
        public int NumChannels { get; set; } = 1;
        public int SamplesPerSec { get; set; } = 44100;
        public int BitsPerSample { get; set; } = 16;
    }

    /// <summary>
    /// Main audio configuration structure
    /// </summary>
    public class AudioConfig
    {
        public const int MaxAudioDevices = 3;
        public const int MaxRadioChannels = 6;
        public const int MaxTotalChannels = 16;
        public const int MaxSubchannels = 9;
        public const int MaxSlicers = 9;

        public AudioDeviceConfig[] Devices { get; set; }
        public AudioChannelConfig[] Channels { get; set; }
        public Medium[] ChannelMedium { get; set; }
        public string[] MyCall { get; set; }

        public AudioConfig()
        {
            Devices = new AudioDeviceConfig[MaxAudioDevices];
            for (int i = 0; i < MaxAudioDevices; i++)
            {
                Devices[i] = new AudioDeviceConfig();
            }

            Channels = new AudioChannelConfig[MaxRadioChannels];
            for (int i = 0; i < MaxRadioChannels; i++)
            {
                Channels[i] = new AudioChannelConfig();
            }

            ChannelMedium = new Medium[MaxTotalChannels];
            MyCall = new string[MaxTotalChannels];
            
            for (int i = 0; i < MaxTotalChannels; i++)
            {
                ChannelMedium[i] = Medium.None;
                MyCall[i] = "";
            }
        }

        /// <summary>
        /// Get audio device index for a given channel
        /// </summary>
        public static int ChannelToDevice(int channel)
        {
            return channel >> 1;
        }

        /// <summary>
        /// Get first channel for a given device
        /// </summary>
        public static int DeviceFirstChannel(int device)
        {
            return device * 2;
        }
    }
}
