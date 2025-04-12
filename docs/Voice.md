# Voice

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-voice.png?raw=true)

Handi-Talky Commander has built-in speech recognition capabilities with integration of Open AI's Whisper. Radio audio will be run into a neural-network language model to convert into text and the results are quite impressive. A powerful CPU with AVX support is required.

From within Handi-Talky Commander you can select and download one of the Whisper models. The larger the model, the better the results but also the more CPU power is required.

- Tiny, 77.7 MB
- Tiny.en, 77.7 MB, English Only
- Base, 148 MB
- Base.en, 148 MB, English Only (Recommended)
- Small, 488 MB
- Small.en, 488 MB, English Only
- Medium, 1.53 GB
- Medium.en, 1.53 GB, English Only

The English-only models are best if your intend to only listen to English conversations, otherwise, the normal models support a large range of languages. You can help the model out by selecting the language you will be listening to in the Settings panel, this will give a hint to the model to focus on the selected language.

Once enabled, the voice recognition will run when the radio no longer receives a signal or every 20 to 30 seconds.

In addition, there is support for text-to-speech (TTS) using the Microsoft Speech API. So, you can type a message and it will be read on the radio.