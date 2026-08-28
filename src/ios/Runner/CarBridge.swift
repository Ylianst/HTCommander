/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import AVFoundation
import Flutter
import Foundation
import MediaPlayer

/// In-process bridge between the Flutter engine and the CarPlay UI.
///
/// The CarPlay surface ([CarPlaySceneDelegate] and its templates) runs in a
/// separate `UIScene` from the app's main window scene, so it cannot talk to
/// the Dart isolate directly. This singleton holds the latest car-safe state
/// pushed from Dart over the `com.htcommander/carplay` [FlutterMethodChannel]
/// and lets the CarPlay templates both read that state and request changes.
///
/// This is the iOS counterpart of the Kotlin `AndroidAutoBridge`; it consumes
/// the exact same `updateState` payload and emits the same control calls
/// (`setChannel`, `setRegion`, `setScan`, `setDualWatch`, `setRadioPower`,
/// `disconnectRadio`, `refreshRadios`, `connectRadio`) so a single Dart
/// `CarBridge` drives both platforms.
final class CarBridge: NSObject {
    static let shared = CarBridge()

    private static let channelName = "com.htcommander/carplay"

    private var methodChannel: FlutterMethodChannel?
    private var carConnected = false
    private var remoteCommandsRegistered = false

    // MARK: - Mirrored state

    struct CarChannel {
        let id: Int
        let name: String
        let frequency: String
    }

    struct CarRadio {
        let id: String
        let name: String
    }

    struct CarRegion {
        let index: Int
        let name: String
    }

    struct CarVfo {
        let channelId: Int
        let name: String
        let frequency: String

        var title: String {
            if !name.isEmpty { return name }
            if !frequency.isEmpty { return frequency }
            return "—"
        }

        var subtitle: String {
            if !name.isEmpty { return frequency }
            if channelId >= 0 { return "Channel \(channelId + 1)" }
            return ""
        }
    }

    private(set) var connected = false
    private(set) var powerOn = true
    private(set) var scanningRadios = false
    private(set) var connectingRadioId = ""
    private(set) var radioConnectionErrorId = ""
    private(set) var availableRadios: [CarRadio] = []
    private(set) var radioName = ""
    private(set) var regionName = ""
    private(set) var regionIndex = -1
    private(set) var regions: [CarRegion] = []
    private(set) var vfoA = CarVfo(channelId: -1, name: "", frequency: "")
    private(set) var vfoB = CarVfo(channelId: -1, name: "", frequency: "")
    private(set) var scan = false
    private(set) var dualWatch = false
    private(set) var channels: [CarChannel] = []

    // MARK: - Listeners

    private var nextListenerToken = 0
    private var listeners: [Int: () -> Void] = [:]

    /// Registers a state-change listener and returns a token used to remove it.
    /// The listener is invoked (on the main thread) whenever new state arrives.
    @discardableResult
    func addListener(_ listener: @escaping () -> Void) -> Int {
        let token = nextListenerToken
        nextListenerToken += 1
        listeners[token] = listener
        return token
    }

    func removeListener(_ token: Int) {
        listeners.removeValue(forKey: token)
    }

    // MARK: - Channel wiring

    /// Binds the method channel to the active Flutter engine's messenger. Called
    /// once from `AppDelegate` when the implicit engine is initialized.
    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: CarBridge.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            switch call.method {
            case "updateState":
                if let map = call.arguments as? [String: Any] {
                    self.applyState(map)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        methodChannel = channel

        // Pull the current snapshot in case Dart pushed state before the CarPlay
        // scene (and therefore this channel) existed.
        channel.invokeMethod("carConnected", arguments: carConnected)
        channel.invokeMethod("getState", arguments: nil) { [weak self] result in
            if let map = result as? [String: Any] {
                self?.applyState(map)
            }
        }
    }

    // MARK: - Control (native -> Dart)

    func requestChannel(channelId: Int, vfo: String) {
        methodChannel?.invokeMethod("setChannel", arguments: ["channelId": channelId, "vfo": vfo])
    }

    func requestRegion(_ index: Int) {
        methodChannel?.invokeMethod("setRegion", arguments: index)
    }

    func requestScan(_ on: Bool) {
        methodChannel?.invokeMethod("setScan", arguments: on)
    }

    func requestDualWatch(_ on: Bool) {
        methodChannel?.invokeMethod("setDualWatch", arguments: on)
    }

    func requestRadioRefresh() {
        methodChannel?.invokeMethod("refreshRadios", arguments: nil)
    }

    func requestRadioConnection(id: String) {
        methodChannel?.invokeMethod("connectRadio", arguments: ["id": id])
    }

    func requestRadioPower(_ on: Bool) {
        methodChannel?.invokeMethod("setRadioPower", arguments: on)
    }

    func requestDisconnect() {
        methodChannel?.invokeMethod("disconnectRadio", arguments: nil)
    }

    /// Notifies Dart whether a CarPlay session is projecting, so it can decide
    /// whether to read incoming messages aloud.
    func setCarConnected(_ connected: Bool) {
        carConnected = connected
        methodChannel?.invokeMethod("carConnected", arguments: connected)
    }

    // MARK: - State (Dart -> native)

    private func applyState(_ map: [String: Any]) {
        connected = map["connected"] as? Bool ?? false
        powerOn = map["powerOn"] as? Bool ?? true
        scanningRadios = map["scanningRadios"] as? Bool ?? false
        connectingRadioId = map["connectingRadioId"] as? String ?? ""
        radioConnectionErrorId = map["radioConnectionErrorId"] as? String ?? ""
        availableRadios = (map["availableRadios"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return CarRadio(id: id, name: m["name"] as? String ?? "")
        }
        radioName = map["radioName"] as? String ?? ""
        regionName = map["regionName"] as? String ?? ""
        regionIndex = (map["regionIndex"] as? NSNumber)?.intValue ?? -1
        scan = map["scan"] as? Bool ?? false
        dualWatch = map["dualWatch"] as? Bool ?? false
        vfoA = parseVfo(map["vfoA"])
        vfoB = parseVfo(map["vfoB"])
        regions = (map["regions"] as? [[String: Any]] ?? []).compactMap { m in
            guard let index = (m["index"] as? NSNumber)?.intValue else { return nil }
            return CarRegion(index: index, name: m["name"] as? String ?? "")
        }
        channels = (map["channels"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = (m["id"] as? NSNumber)?.intValue else { return nil }
            return CarChannel(id: id, name: m["name"] as? String ?? "", frequency: m["frequency"] as? String ?? "")
        }
        updateNowPlayingInfo()
        notifyListeners()
    }

    private func parseVfo(_ value: Any?) -> CarVfo {
        guard let m = value as? [String: Any] else {
            return CarVfo(channelId: -1, name: "", frequency: "")
        }
        return CarVfo(
            channelId: (m["channelId"] as? NSNumber)?.intValue ?? -1,
            name: m["name"] as? String ?? "",
            frequency: m["frequency"] as? String ?? ""
        )
    }

    private func notifyListeners() {
        DispatchQueue.main.async { [weak self] in
            self?.listeners.values.forEach { $0() }
        }
    }

    // MARK: - Audio session & Now Playing

    /// Activates the playback audio session and registers the CarPlay transport
    /// commands. Called when the CarPlay scene connects.
    func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        registerRemoteCommands()
    }

    /// Maps the Now Playing transport play/pause to radio power so the driver
    /// can start and stop listening from the car's controls and steering wheel.
    private func registerRemoteCommands() {
        guard !remoteCommandsRegistered else { return }
        remoteCommandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.requestRadioPower(true)
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.requestRadioPower(false)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.requestRadioPower(!self.powerOn)
            return .success
        }
    }

    /// Publishes the current channel to the system Now Playing info so the
    /// CarPlay Now Playing screen (and lock screen) show what's being received.
    func updateNowPlayingInfo() {
        let vfo = vfoA
        let title = vfo.title == "\u{2014}" ? (radioName.isEmpty ? "HTCommander" : radioName) : vfo.title
        let subtitle = vfo.frequency.isEmpty ? radioName : vfo.frequency
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: (connected && powerOn) ? 1.0 : 0.0,
        ]
        if scan { info[MPMediaItemPropertyAlbumTitle] = "Scanning" }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
