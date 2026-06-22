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
