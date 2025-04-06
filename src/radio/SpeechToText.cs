using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace HTCommander.radio
{
    public interface SpeechToText
    {
        event RadioAudio.OnVoiceTextReady onFinalResultReady;
        event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

        void StartVoiceSegment();

        void ResetVoiceSegment();

        void ProcessAudioChunk(byte[] data, int index, int length, string channel);

        void Dispose();
    }
}
