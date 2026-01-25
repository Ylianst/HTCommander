# VoiceHandler Usage Guide

The `VoiceHandler` is a Data Broker handler that provides speech-to-text conversion for radio audio streams using Whisper.

## Overview

Previously, speech-to-text was handled directly in `RadioAudio.cs`. Now it's been extracted into a separate handler that:
- Listens to `AudioDataAvailable` events from the Data Broker
- Converts PCM audio data to text using WhisperEngine
- Dispatches `TextReady` and `ProcessingVoice` events

## Enabling the VoiceHandler

To enable speech-to-text for a specific radio:

```csharp
// Dispatch a VoiceHandlerEnable command with device ID, language, and model
broker.Dispatch(0, "VoiceHandlerEnable", new
{
    DeviceId = 100,  // The radio device ID to listen to
    Language = "auto",  // Language code or "auto" for automatic detection
    Model = @"C:\Path\To\ggml-tiny.bin"  // Path to Whisper model file
}, store: false);
```

## Disabling the VoiceHandler

To disable speech-to-text:

```csharp
broker.Dispatch(0, "VoiceHandlerDisable", null, store: false);
```

## Events Dispatched

The VoiceHandler dispatches the following events for the target device:

### TextReady
Dispatched when text has been transcribed from audio.

```csharp
broker.Subscribe(deviceId, "TextReady", (devId, name, data) =>
{
    // data contains: { Text, Channel, Time, Completed }
    var text = data.Text;
    var channel = data.Channel;
    var time = data.Time;
    var completed = data.Completed;
});
```

### ProcessingVoice
Dispatched when the speech processing state changes.

```csharp
broker.Subscribe(deviceId, "ProcessingVoice", (devId, name, data) =>
{
    // data contains: { Listening, Processing }
    var listening = data.Listening;  // Whether engine is active
    var processing = data.Processing;  // Whether actively processing audio
});
```

## Architecture

```
┌──────────────────┐
│   RadioAudio     │
│  (Device 100)    │
└────────┬─────────┘
         │ Dispatches AudioDataAvailable
         ▼
┌──────────────────┐
│   Data Broker    │
└────────┬─────────┘
         │ Subscribes to AudioDataAvailable
         ▼
┌──────────────────┐
│  VoiceHandler    │
│                  │
│ ┌──────────────┐ │
│ │WhisperEngine │ │
│ └──────────────┘ │
└────────┬─────────┘
         │ Dispatches TextReady & ProcessingVoice
         ▼
┌──────────────────┐
│   Data Broker    │
└────────┬─────────┘
         │ Subscribers receive events
         ▼
┌──────────────────┐
│  UI Components   │
│ (VoiceTab, etc.) │
└──────────────────┘
```

## Benefits of This Architecture

1. **Separation of Concerns**: Audio streaming and speech recognition are decoupled
2. **Flexibility**: Can enable/disable speech-to-text without affecting audio streaming
3. **Multi-Radio Support**: Can listen to different radios by changing the device ID
4. **Easy Testing**: Can test speech-to-text independently of radio hardware
5. **Resource Management**: Speech engine only runs when needed

## Migration Notes

If you have existing code that used `RadioAudio.StartAudioToText()`:

**Old Code:**
```csharp
radioAudio.voiceLanguage = "auto";
radioAudio.voiceModel = @"C:\Path\To\model.bin";
radioAudio.speechToText = true;
// or
radioAudio.StartAudioToText("auto", @"C:\Path\To\model.bin");
```

**New Code:**
```csharp
broker.Dispatch(0, "VoiceHandlerEnable", new
{
    DeviceId = radioDeviceId,
    Language = "auto",
    Model = @"C:\Path\To\model.bin"
}, store: false);
```

The events dispatched remain the same, so existing subscribers to `TextReady` and `ProcessingVoice` will continue to work without modification.
