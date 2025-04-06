# Speech to Text

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-voice-to-text.png?raw=true)

Handi-Talky Commander has built-in speech recognition capabilities with integration of DeepSpeech. Radio audio will be run into the DeepSpeech neural-network to convert into text in near real-time. However, there are limitations to this, it's currently not great but fun to try. Don't try this on a slow computer with limited RAM, but will keep you CPU working.

To enable this feature, you need to download the following two files and add them in the same folder as the HTCommander executable. These two files are very large and total about a gigabyte in size.

- [DeepSpeech v0.9.3 Model](https://github.com/mozilla/DeepSpeech/releases/download/v0.9.3/deepspeech-0.9.3-models.pbmm)
- [DeepSpeech v0.9.3 Scorer](https://github.com/mozilla/DeepSpeech/releases/download/v0.9.3/deepspeech-0.9.3-models.scorer)

If you installed HTCommander using the installer, you can find the executable in the following location: `C:\Program Files\Open Source\Handi-Talky Commander`, so, copy the two large files here. Then, start HT Commander again, you will see a new "Voice" option in the "View" menu. You need to enable audio to play thru your computer and then, enable the voice feature to start seeing text. 

The feature does not work well, but it's a nice party trick for new. In my view, The two main problems are that:

- It does not handle rapid voice very at all. If someone says something quickly as most HAM radio people do, it does not seem to be able to keep up. I don't think it's a question of my computer being slow, it still seems to process all the audio frames, it just seems to do a lot better when saying things slowly. NOAA weather is the one test case I have that is always transmitting, so, it's clearly WAY to fast for the model.
- The AI model is not trained on HAM radio speak. For example, it does not understand "Alpha", "Bravo", etc. At least, not all of them. This is a HUGE bummer. It does numbers "One", "Two".

So, basically, you get junk a lot of the time. I did make the Speech-to-Text a bit more modular so, I could implement different solutions in the future. OpenAI Wisper is probably another one I can look at, I would have to find one with a large community. I am only looking at offline ones, I am not sure anyone would use an online one, even if it was any good.

I think ultimately, the solution is going to be to fine tune a speech model specifically for this usage.
