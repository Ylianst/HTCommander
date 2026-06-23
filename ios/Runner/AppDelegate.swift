import Flutter
import UIKit
import Speech
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register the speech-to-text handler (Apple SFSpeechRecognizer).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechToTextHandler") {
      SpeechToTextHandler.register(with: registrar)
    }

    // Register the text-to-speech handler (Apple AVSpeechSynthesizer).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TextToSpeechHandler") {
      TextToSpeechHandler.register(with: registrar)
    }
  }
}

// MARK: - Speech To Text Handler

/// Speech-to-text plugin backed by Apple's `SFSpeechRecognizer`. Unlike the
/// microphone-only speech_to_text Flutter package, this accepts raw PCM buffers
/// (16-bit signed little-endian mono) pushed from Dart via the data broker's
/// received-audio frames, so it can transcribe incoming radio voice. Partial
/// and final transcriptions are reported back over an event channel.
///
/// Channel contract (see lib/handlers/speech_to_text_engine.dart):
///   method  com.htcommander/speech_to_text
///     initialize({localeId}) -> Bool (available & authorized)
///     startSegment / appendAudio({data, sampleRate}) / completeSegment /
///     resetSegment / dispose
///   event   com.htcommander/speech_to_text_events
///     { event: "result", text: String, isFinal: Bool }
///     { event: "processing", active: Bool }
///     { event: "error", message: String }
class SpeechToTextHandler: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var authorized = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SpeechToTextHandler()

        let channel = FlutterMethodChannel(
            name: "com.htcommander/speech_to_text",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(
            name: "com.htcommander/speech_to_text_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
        instance.eventChannel = eventChannel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            let args = call.arguments as? [String: Any]
            let localeId = (args?["localeId"] as? String) ?? ""
            initialize(localeId: localeId, result: result)
        case "startSegment":
            startSegment()
            result(nil)
        case "appendAudio":
            let args = call.arguments as? [String: Any]
            if let typed = args?["data"] as? FlutterStandardTypedData {
                let sampleRate = (args?["sampleRate"] as? Int) ?? 32000
                appendAudio(typed.data, sampleRate: sampleRate)
            }
            result(nil)
        case "completeSegment":
            completeSegment()
            result(nil)
        case "resetSegment":
            resetSegment()
            result(nil)
        case "dispose":
            resetSegment()
            recognizer = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(localeId: String, result: @escaping FlutterResult) {
        let locale = localeId.isEmpty ? Locale.current : Locale(identifier: localeId)
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else {
                DispatchQueue.main.async { result(false) }
                return
            }
            self.authorized = (status == .authorized)
            let available = self.authorized && (self.recognizer != nil)
            DispatchQueue.main.async { result(available) }
        }
    }

    private func startSegment() {
        guard authorized, let recognizer = recognizer else { return }
        cancelTask()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer fully offline recognition when the system supports it (avoids
        // network round-trips and keeps audio private); otherwise fall back to
        // server recognition.
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.emitResult(text: text, isFinal: result.isFinal)
                if result.isFinal { self.finishTask() }
            }
            if let error = error {
                self.emitError(error.localizedDescription)
                self.finishTask()
            }
        }
    }

    private func appendAudio(_ data: Data, sampleRate: Int) {
        guard let request = request else { return }
        let sampleCount = data.count / 2
        if sampleCount == 0 { return }

        guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 1,
                interleaved: false),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)) else { return }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let channel = buffer.floatChannelData?[0] {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let samples = raw.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    channel[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
                }
            }
        }
        request.append(buffer)
        emitProcessing(true)
    }

    private func completeSegment() {
        request?.endAudio()
    }

    private func resetSegment() {
        cancelTask()
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
        request = nil
    }

    private func finishTask() {
        task = nil
        request = nil
        emitProcessing(false)
    }

    // MARK: Event emission (always delivered on the main thread)

    private func emitResult(text: String, isFinal: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "result", "text": text, "isFinal": isFinal])
        }
    }

    private func emitError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "error", "message": message])
        }
    }

    private func emitProcessing(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "processing", "active": active])
        }
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

// MARK: - Text To Speech Handler

/// Text-to-speech plugin backed by Apple's `AVSpeechSynthesizer`. Synthesis is
/// rendered entirely in memory via `AVSpeechSynthesizer.write(_:)`, which hands
/// back raw `AVAudioPCMBuffer` chunks. The buffers are down-mixed to mono and
/// returned to Dart as 32-bit float samples plus the source sample rate; Dart
/// resamples them to the radio's 32 kHz / mono / signed-16-bit PCM format. No
/// temporary audio file is ever written, which avoids the file-flush timing and
/// format-detection failures of `flutter_tts`'s `synthesizeToFile`.
///
/// Channel contract (see lib/services/tts_service_io.dart):
///   method  com.htcommander/tts
///     getVoices() -> [[String: String]]  (name, locale, identifier, quality, gender)
///     synthesize({text, voiceIdentifier, locale, rate, pitch})
///         -> { samples: Float32List, sampleRate: Int }  (null if no audio)
class TextToSpeechHandler: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    // In-flight synthesizers are retained here so ARC does not deallocate them
    // while `write(_:)` is still streaming buffers on a background queue.
    private var activeSynthesizers: [AVSpeechSynthesizer] = []
    // Dedicated synthesizer used for local "preview" playback in Settings.
    private let previewSynthesizer = AVSpeechSynthesizer()

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TextToSpeechHandler()
        let channel = FlutterMethodChannel(
            name: "com.htcommander/tts",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getVoices":
            result(getVoices())
        case "synthesize":
            synthesize(args: call.arguments as? [String: Any] ?? [:], result: result)
        case "preview":
            preview(args: call.arguments as? [String: Any] ?? [:])
            result(nil)
        case "stopPreview":
            previewSynthesizer.stopSpeaking(at: .immediate)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Builds an utterance from the shared argument map (text, voiceIdentifier,
    /// locale, rate, pitch).
    private func makeUtterance(args: [String: Any]) -> AVSpeechUtterance {
        let text = (args["text"] as? String) ?? ""
        let utterance = AVSpeechUtterance(string: text)
        if let identifier = args["voiceIdentifier"] as? String, !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else if let locale = args["locale"] as? String, !locale.isEmpty,
                  let voice = AVSpeechSynthesisVoice(language: locale) {
            utterance.voice = voice
        }
        if let rate = args["rate"] as? Double {
            utterance.rate = min(
                max(Float(rate), AVSpeechUtteranceMinimumSpeechRate),
                AVSpeechUtteranceMaximumSpeechRate)
        }
        if let pitch = args["pitch"] as? Double {
            utterance.pitchMultiplier = min(max(Float(pitch), 0.5), 2.0)
        }
        return utterance
    }

    /// Speaks [text] through the device speaker so the user can audition the
    /// selected voice / rate / pitch without transmitting.
    private func preview(args: [String: Any]) {
        let text = (args["text"] as? String) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(makeUtterance(args: args))
    }

    private func getVoices() -> [[String: String]] {
        return AVSpeechSynthesisVoice.speechVoices().map { voice in
            let quality: String
            if #available(iOS 16.0, *), voice.quality == .premium {
                quality = "premium"
            } else if voice.quality == .enhanced {
                quality = "enhanced"
            } else {
                quality = "default"
            }
            var gender = "unspecified"
            switch voice.gender {
            case .male: gender = "male"
            case .female: gender = "female"
            default: gender = "unspecified"
            }
            return [
                "name": voice.name,
                "locale": voice.language,
                "identifier": voice.identifier,
                "quality": quality,
                "gender": gender,
            ]
        }
    }

    private func synthesize(args: [String: Any], result: @escaping FlutterResult) {
        let text = (args["text"] as? String) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(nil)
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        if let identifier = args["voiceIdentifier"] as? String, !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else if let locale = args["locale"] as? String, !locale.isEmpty,
                  let voice = AVSpeechSynthesisVoice(language: locale) {
            utterance.voice = voice
        }
        if let rate = args["rate"] as? Double {
            utterance.rate = min(
                max(Float(rate), AVSpeechUtteranceMinimumSpeechRate),
                AVSpeechUtteranceMaximumSpeechRate)
        }
        if let pitch = args["pitch"] as? Double {
            utterance.pitchMultiplier = min(max(Float(pitch), 0.5), 2.0)
        }

        let synthesizer = AVSpeechSynthesizer()
        activeSynthesizers.append(synthesizer)

        var monoSamples = [Float]()
        var sourceSampleRate: Double = 0
        var didReturn = false

        let deliver: (Bool) -> Void = { [weak self] success in
            if didReturn { return }
            didReturn = true
            if let self = self,
               let index = self.activeSynthesizers.firstIndex(where: { $0 === synthesizer }) {
                self.activeSynthesizers.remove(at: index)
            }
            let payload: Any?
            if success, !monoSamples.isEmpty, sourceSampleRate > 0 {
                let data = monoSamples.withUnsafeBufferPointer { Data(buffer: $0) }
                payload = [
                    "samples": FlutterStandardTypedData(float32: data),
                    "sampleRate": Int(sourceSampleRate),
                ]
            } else {
                payload = nil
            }
            DispatchQueue.main.async { result(payload) }
        }

        synthesizer.write(utterance) { (buffer: AVAudioBuffer) in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                deliver(false)
                return
            }
            let frames = Int(pcm.frameLength)
            // A trailing zero-length buffer signals the synthesizer is finished.
            if frames == 0 {
                deliver(true)
                return
            }
            sourceSampleRate = pcm.format.sampleRate
            let channels = Int(pcm.format.channelCount)
            if let floatChannels = pcm.floatChannelData {
                if channels <= 1 {
                    monoSamples.append(
                        contentsOf: UnsafeBufferPointer(start: floatChannels[0], count: frames))
                } else {
                    for i in 0..<frames {
                        var sum: Float = 0
                        for c in 0..<channels { sum += floatChannels[c][i] }
                        monoSamples.append(sum / Float(channels))
                    }
                }
            } else if let int16Channels = pcm.int16ChannelData {
                let channel = int16Channels[0]
                for i in 0..<frames {
                    monoSamples.append(Float(channel[i]) / 32768.0)
                }
            }
        }
    }
}
