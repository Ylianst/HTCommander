import Cocoa
import FlutterMacOS
import desktop_multi_window
import window_manager
import IOBluetooth
import Speech
import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - Bluetooth Classic Handler

/// Handler for Bluetooth Classic operations on macOS
/// Uses IOBluetooth framework for RFCOMM (Serial Port Profile) connections
class BluetoothClassicHandler: NSObject, FlutterPlugin, IOBluetoothRFCOMMChannelDelegate {
    
    private var methodChannel: FlutterMethodChannel?
    private var dataChannel: FlutterEventChannel?
    private var dataSink: FlutterEventSink?

    // Separate event channel/sink for the audio (Generic Audio) RFCOMM channel
    private var audioChannel: FlutterEventChannel?
    fileprivate var audioSink: FlutterEventSink?
    private let audioStreamHandler = AudioEventStreamHandler()
    
    // Active RFCOMM connections for the SPP data channel: deviceAddress -> RFCOMMConnection
    private var connections: [String: RFCOMMConnection] = [:]

    // The control (SPP / data) RFCOMM channel on these radios is either channel
    // 4 or channel 1, so connection attempts alternate between them.
    private let controlChannelCandidates: [BluetoothRFCOMMChannelID] = [4, 1]
    // Connection retry tuning: each attempt waits this long for the open to
    // complete before being torn down and retried, up to the attempt cap. This
    // mirrors the C# client's connection retry, which is far more reliable than
    // a single long attempt.
    private let controlConnectTimeout: TimeInterval = 5.0
    private let maxControlConnectAttempts = 5

    // Active RFCOMM connections for the Generic Audio channel: deviceAddress -> RFCOMMConnection
    private var audioConnections: [String: RFCOMMConnection] = [:]

    // Timestamp of the most recent audio-channel open/close per device address.
    // Opening OR closing the audio RFCOMM channel can trigger a spurious
    // rfcommChannelClosed on the still-alive DATA channel; this lets the data
    // close handler verify (rather than immediately report) a disconnect for a
    // short window around any audio-channel change.
    private var lastAudioActivity: [String: Date] = [:]

    // Whether audio frames should currently be forwarded to Dart for each device.
    // On macOS, CLOSING the audio RFCOMM channel also tears down the control/data
    // RFCOMM channel (both channels to the device share link state). To let the
    // user enable/disable audio repeatedly WITHOUT dropping the control channel,
    // we keep the audio channel OPEN once connected and simply gate delivery with
    // this flag: disabling audio sets it false (channel stays open, frames are
    // dropped natively); enabling sets it true again. The channel is only really
    // closed on a full radio disconnect.
    private var audioForwardingEnabled: [String: Bool] = [:]
    
    // Vendor "BS AOC" service that carries the SBC audio stream on these radios.
    // Custom 128-bit UUID 39144315-32FA-40DB-85ED-FBFEBA2D86E6. Audio does NOT
    // come on the advertised Generic Audio service (0x1203); see
    // docs/radio-bluetooth.md.
    fileprivate static let audioVendorUUID = IOBluetoothSDPUUID(data: Data([
        0x39, 0x14, 0x43, 0x15, 0x32, 0xFA, 0x40, 0xDB,
        0x85, 0xED, 0xFB, 0xFE, 0xBA, 0x2D, 0x86, 0xE6
    ]))

    // Canonical lowercase 128-bit string form of `audioVendorUUID`, shared with
    // the Dart side and the other platforms as the radio's unique identifier.
    fileprivate static let radioServiceUuidString = "39144315-32fa-40db-85ed-fbfeba2d86e6"

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BluetoothClassicHandler()
        
        // Method channel for commands
        let channel = FlutterMethodChannel(
            name: "com.htcommander/bluetooth_classic",
            binaryMessenger: registrar.messenger
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Event channel for data reception
        let eventChannel = FlutterEventChannel(
            name: "com.htcommander/bluetooth_classic_data",
            binaryMessenger: registrar.messenger
        )
        eventChannel.setStreamHandler(instance)
        instance.dataChannel = eventChannel

        // Event channel for audio (Generic Audio RFCOMM) reception
        let audioEventChannel = FlutterEventChannel(
            name: "com.htcommander/bluetooth_classic_audio",
            binaryMessenger: registrar.messenger
        )
        instance.audioStreamHandler.owner = instance
        audioEventChannel.setStreamHandler(instance.audioStreamHandler)
        instance.audioChannel = audioEventChannel
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(isBluetoothAvailable())
            
        case "getPairedDevices":
            result(getPairedDevices())
            
        case "findCompatibleDevices":
            result(findCompatibleDevices())
            
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address", details: nil))
                return
            }
            connect(address: address, result: result)
            
        case "disconnect":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address", details: nil))
                return
            }
            disconnect(address: address)
            result(true)
            
        case "send":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String,
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address or data", details: nil))
                return
            }
            let success = send(address: address, data: data.data)
            result(success)

        case "connectAudio":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address", details: nil))
                return
            }
            connectAudio(address: address, result: result)

        case "disconnectAudio":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address", details: nil))
                return
            }
            disconnectAudio(address: address)
            result(true)

        case "sendAudio":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String,
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address or data", details: nil))
                return
            }
            let success = sendAudio(address: address, data: data.data)
            result(success)
            
        case "getDeviceNames":
            result(getDeviceNames())
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Bluetooth Operations
    
    private func isBluetoothAvailable() -> Bool {
        // Check if Bluetooth is available and powered on
        guard let controller = IOBluetoothHostController.default() else {
            return false
        }
        return controller.powerState == kBluetoothHCIPowerStateON
    }
    
    private func getPairedDevices() -> [[String: Any]] {
        var devices: [[String: Any]] = []
        var seenAddresses: Set<String> = []
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return devices
        }
        
        for device in pairedDevices {
            guard let name = device.name, let address = device.addressString else {
                continue
            }
            
            let normalizedAddress = address.uppercased().replacingOccurrences(of: "-", with: ":")
            
            // Skip duplicates (same MAC can appear for multiple profiles)
            if seenAddresses.contains(normalizedAddress) {
                continue
            }
            seenAddresses.insert(normalizedAddress)
            
            devices.append([
                "name": name,
                "address": normalizedAddress,
                "isPaired": true,
                "isConnected": device.isConnected(),
                "serviceUuids": radioServiceUuids(for: device)
            ])
        }
        
        return devices
    }
    
    /// Returns the radio's unique service UUID(s) if the device exposes the
    /// vendor "BS AOC" SDP service, otherwise an empty array. Devices are
    /// identified by this stable UUID rather than by their (rebrandable) name.
    private func radioServiceUuids(for device: IOBluetoothDevice) -> [String] {
        if device.getServiceRecord(for: Self.audioVendorUUID) != nil {
            return [Self.radioServiceUuidString]
        }
        return []
    }
    
    private func findCompatibleDevices() -> [[String: Any]] {
        var compatibleDevices: [[String: Any]] = []
        var seenAddresses: Set<String> = []
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return compatibleDevices
        }
        
        for device in pairedDevices {
            guard let name = device.name, let address = device.addressString else {
                continue
            }
            
            let normalizedAddress = address.uppercased().replacingOccurrences(of: "-", with: ":")
            
            // Skip duplicates (same MAC can appear for multiple profiles like control + audio)
            if seenAddresses.contains(normalizedAddress) {
                continue
            }
            
            // Identify the radio by its unique vendor SDP service UUID rather
            // than by name, which can change across rebrands / OS stacks.
            let radioUuids = radioServiceUuids(for: device)
            
            if !radioUuids.isEmpty {
                seenAddresses.insert(normalizedAddress)
                compatibleDevices.append([
                    "name": name,
                    "address": normalizedAddress,
                    "isPaired": true,
                    "isConnected": device.isConnected(),
                    "serviceUuids": radioUuids
                ])
            }
        }
        
        return compatibleDevices
    }
    
    private func getDeviceNames() -> [String] {
        var names: [String] = []
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return names
        }
        
        for device in pairedDevices {
            if let name = device.name, !names.contains(name) {
                names.append(name)
            }
        }
        
        names.sort()
        return names
    }
    
    private func connect(address: String, result: @escaping FlutterResult) {
        // Normalize address format
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        
        
        // Check if already connected
        if let existingConnection = connections[normalizedAddress] {
            if existingConnection.isConnected {
                result(true)
                return
            } else {
                // Clean up stale connection
                existingConnection.channel.close()
                connections.removeValue(forKey: normalizedAddress)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        
        // Find the device by address
        guard let device = IOBluetoothDevice(addressString: normalizedAddress) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found: \(address)", details: nil))
            return
        }
        
        
        // If device shows as connected but we don't have a connection, close it
        if device.isConnected() {
            device.closeConnection()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // The control (SPP / data) channel on these radios is either RFCOMM
        // channel 4 or channel 1, so connect to it directly without an SDP
        // channel scan, alternating between the two channels on each attempt.
        // Each attempt is given a short timeout and retried, which is far more
        // reliable than a single long attempt.
        attemptControlConnect(device: device, address: normalizedAddress, attempt: 1, result: result)
    }

    /// Open the control RFCOMM channel for a single attempt, alternating between
    /// channel 4 and channel 1. If the open does not complete within
    /// `controlConnectTimeout`, or fails, the attempt is torn down and retried
    /// up to `maxControlConnectAttempts` times.
    private func attemptControlConnect(device: IOBluetoothDevice, address: String, attempt: Int, result: @escaping FlutterResult) {
        let controlChannelID = controlChannelCandidates[(attempt - 1) % controlChannelCandidates.count]

        var rfcommChannel: IOBluetoothRFCOMMChannel?
        let openResult = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: controlChannelID, delegate: self)

        if openResult != kIOReturnSuccess || rfcommChannel == nil {
            device.closeConnection()
            retryOrFailControlConnect(device: device, address: address, attempt: attempt, result: result)
            return
        }

        let channel = rfcommChannel!
        channel.setDelegate(self)

        let connection = RFCOMMConnection(device: device, channel: channel, address: address)
        connection.connectResult = result
        connection.connectAttempt = attempt
        connections[address] = connection

        // Per-attempt timeout: if the open has not completed, tear it down and
        // retry (or fail after the final attempt). The attempt check ensures a
        // stale timeout cannot tear down a newer attempt's connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + controlConnectTimeout) { [weak self] in
            guard let self = self else { return }
            guard let conn = self.connections[address],
                  !conn.isConnected,
                  conn.connectAttempt == attempt else { return }
            conn.channel.setDelegate(nil)
            conn.channel.close()
            self.connections.removeValue(forKey: address)
            self.retryOrFailControlConnect(device: device, address: address, attempt: attempt, result: result)
        }
    }

    /// Schedule another control-connect attempt, or report failure once the
    /// maximum number of attempts has been reached.
    private func retryOrFailControlConnect(device: IOBluetoothDevice, address: String, attempt: Int, result: @escaping FlutterResult) {
        if attempt >= maxControlConnectAttempts {
            result(FlutterError(
                code: "CONNECTION_FAILED",
                message: "Failed to connect after \(maxControlConnectAttempts) attempts",
                details: nil
            ))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.attemptControlConnect(device: device, address: address, attempt: attempt + 1, result: result)
        }
    }
    
    private func disconnect(address: String) {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")

        // Full radio disconnect: tear down BOTH the data and audio RFCOMM
        // channels. The audio channel is kept open across audio enable/disable
        // cycles, so it may still be open here. Detach the delegate from each
        // channel BEFORE closing it: the close is asynchronous and the radio may
        // keep delivering audio frames during the drain, which would otherwise
        // arrive after we've removed the connection and spam
        // "rfcommChannelData - no matching connection".
        audioForwardingEnabled.removeValue(forKey: normalizedAddress)
        lastAudioActivity.removeValue(forKey: normalizedAddress)

        let audioConnection = audioConnections.removeValue(forKey: normalizedAddress)
        let dataConnection = connections.removeValue(forKey: normalizedAddress)

        // Close the audio channel first. Closing it also tears down the data
        // channel at the OS level (both channels to the device share link
        // state). Skip the explicit close only if it is the SAME object as the
        // data channel (some radios resolve audio to the data channel); in that
        // case the data close below handles it.
        if let audioChannel = audioConnection?.channel {
            audioChannel.setDelegate(nil)
            if dataConnection?.channel !== audioChannel {
                audioChannel.close()
            }
        }

        if let dataChannel = dataConnection?.channel {
            dataChannel.setDelegate(nil)
            dataChannel.close()
        }
    }

    // MARK: - Audio (BS AOC vendor RFCOMM) Operations

    /// Resolve the RFCOMM channel number advertised by a service UUID on a device.
    /// Returns 0 if the device does not advertise that service (or it has no
    /// RFCOMM channel). Uses the cached SDP records — call performSDPQuery first
    /// if the records may be stale.
    private func rfcommChannel(on device: IOBluetoothDevice, for uuid: IOBluetoothSDPUUID?) -> BluetoothRFCOMMChannelID {
        guard let uuid = uuid, let record = device.getServiceRecord(for: uuid) else { return 0 }
        var ch: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&ch) == kIOReturnSuccess ? ch : 0
    }

    /// Connect to the audio RFCOMM channel of a device. Audio is carried by the
    /// vendor "BS AOC" service (128-bit UUID 39144315-32FA-40DB-85ED-FBFEBA2D86E6),
    /// resolved by UUID since channel numbers are unstable. This is a second,
    /// independent RFCOMM channel alongside the SPP/control channel.
    private func connectAudio(address: String, result: @escaping FlutterResult) {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")


        // Check if already connected to the audio channel
        if let existingConnection = audioConnections[normalizedAddress] {
            if existingConnection.isConnected {
                // The audio channel is kept open across enable/disable cycles to
                // avoid tearing down the control channel (see audioForwardingEnabled).
                // Re-enabling simply resumes forwarding on the already-open channel.
                audioForwardingEnabled[normalizedAddress] = true
                lastAudioActivity[normalizedAddress] = Date()
                result(true)
                return
            } else {
                audioConnections.removeValue(forKey: normalizedAddress)
                closeAudioChannelSafely(existingConnection.channel, address: normalizedAddress)
            }
        }

        // Reuse the IOBluetoothDevice from the existing data connection if we
        // have one. Creating a brand-new IOBluetoothDevice(addressString:) and
        // running an SDP query can make IOBluetooth renegotiate the baseband/ACL
        // link, which tears down the already-open data RFCOMM channel (the radio
        // then shows as disconnected). Opening the audio channel on the SAME
        // device object adds a second RFCOMM channel without disturbing the data
        // channel.
        let device: IOBluetoothDevice
        if let dataDevice = connections[normalizedAddress]?.device {
            device = dataDevice
        } else if let freshDevice = IOBluetoothDevice(addressString: normalizedAddress) {
            device = freshDevice
        } else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found: \(address)", details: nil))
            return
        }

        // Audio is carried by the vendor "BS AOC" RFCOMM service, identified by
        // the custom 128-bit UUID 39144315-32FA-40DB-85ED-FBFEBA2D86E6 — NOT by
        // the advertised Generic Audio service (0x1203). On these radios 0x1203
        // resolves to a control endpoint (it answers GAIA traffic) and carries
        // no audio; the SBC audio stream only appears on the BS AOC channel.
        // See docs/radio-bluetooth.md for the hardware-verified details.
        //
        // RFCOMM channel numbers are unstable across SDP queries, so always
        // resolve the channel from the service record by UUID, never a hardcoded
        // number.
        let audioUUID = BluetoothClassicHandler.audioVendorUUID
        // Generic Audio (0x1203) is kept only as a fallback for radio models that
        // do not advertise the BS AOC vendor service.
        let fallbackAudioUUID = IOBluetoothSDPUUID(uuid16: 0x1203)
        var audioChannelID: BluetoothRFCOMMChannelID = 0

        // Try the cached service records first; only fall back to an SDP query if
        // the audio service record is not already known. Running an SDP query
        // while the data channel is open can drop that channel, so we avoid it
        // whenever possible.
        audioChannelID = rfcommChannel(on: device, for: audioUUID)

        if audioChannelID == 0 {
            _ = device.performSDPQuery(nil)
            audioChannelID = rfcommChannel(on: device, for: audioUUID)
        }

        // Fall back to the Generic Audio (0x1203) service for non-BS-AOC radios.
        if audioChannelID == 0 {
            audioChannelID = rfcommChannel(on: device, for: fallbackAudioUUID)
        }

        if audioChannelID == 0 {
            result(FlutterError(code: "AUDIO_NOT_FOUND", message: "No audio RFCOMM channel found", details: nil))
            return
        }

        // Open the audio RFCOMM channel
        var rfcommChannel: IOBluetoothRFCOMMChannel?
        let openResult = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: audioChannelID, delegate: self)

        if openResult != kIOReturnSuccess || rfcommChannel == nil {
            result(FlutterError(code: "AUDIO_CONNECTION_FAILED", message: "Failed to open audio RFCOMM channel", details: nil))
            return
        }

        let channel = rfcommChannel!
        channel.setDelegate(self)

        let connection = RFCOMMConnection(device: device, channel: channel, address: normalizedAddress)
        connection.connectResult = result
        audioConnections[normalizedAddress] = connection

        // On some radios the rfcommChannelOpenComplete delegate callback never
        // fires for the audio channel (the second RFCOMM channel to the device)
        // and isOpen() keeps returning false even though the channel is actually
        // open. A negotiated MTU (> 0) is only available once the channel has
        // opened, so treat that as the authoritative "connected" signal. If the
        // MTU is already valid here, declare success immediately; otherwise poll.
        if channel.getMTU() > 0 {
            markAudioConnected(address: normalizedAddress)
        } else {
            pollAudioOpen(address: normalizedAddress, attempt: 0)
        }

        // Result is sent when the channel open completes (immediately above,
        // via the delegate callback, or via the poll fallback).
    }

    /// Marks a tracked audio connection as connected and notifies Dart once.
    private func markAudioConnected(address: String) {
        guard let conn = audioConnections[address], !conn.isConnected else { return }
        conn.isConnected = true
        conn.didNotifyConnected = true
        lastAudioActivity[address] = Date()
        audioForwardingEnabled[address] = true
        conn.connectResult?(true)
        conn.connectResult = nil
        audioSink?([
            "event": "connected",
            "address": address.replacingOccurrences(of: "-", with: ":")
        ])
    }

    /// Polls the audio RFCOMM channel for completion as a fallback for the
    /// unreliable rfcommChannelOpenComplete delegate callback.
    private func pollAudioOpen(address: String, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            guard let conn = self.audioConnections[address] else { return }

            // The delegate already completed the connection.
            if conn.isConnected { return }

            // A negotiated MTU (or isOpen()) indicates the channel is open:
            // treat it as a successful connection.
            if conn.channel.getMTU() > 0 || conn.channel.isOpen() {
                self.markAudioConnected(address: address)
                return
            }

            // Give up after ~10 seconds (20 * 0.5s).
            if attempt >= 20 {
                // Remove before closing so the resulting rfcommChannelClosed callback
                // does not emit a (spurious) disconnect for this failed attempt.
                self.audioConnections.removeValue(forKey: address)
                self.closeAudioChannelSafely(conn.channel, address: address)
                conn.connectResult?(FlutterError(
                    code: "AUDIO_CONNECTION_TIMEOUT",
                    message: "Audio connection timed out after 10 seconds",
                    details: nil
                ))
                conn.connectResult = nil
                return
            }

            self.pollAudioOpen(address: address, attempt: attempt + 1)
        }
    }

    /// "Disable audio" from the user's perspective. IMPORTANT: this does NOT
    /// close the audio RFCOMM channel. On macOS, closing the audio channel also
    /// tears down the control/data RFCOMM channel (both channels to the device
    /// share link state), which would disconnect the radio. Instead we keep the
    /// audio channel OPEN and simply stop forwarding audio frames to Dart. The
    /// channel is only closed on a full radio disconnect (disconnect(address:)).
    private func disconnectAudio(address: String) {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        lastAudioActivity[normalizedAddress] = Date()
        audioForwardingEnabled[normalizedAddress] = false
    }

    /// Closes an audio RFCOMM channel without disturbing the data channel.
    /// On some radios the Generic Audio service resolves to the same RFCOMM
    /// channel ID as the SPP data service, in which case IOBluetooth hands back
    /// the SAME IOBluetoothRFCOMMChannel object for both. Closing it would tear
    /// down the data channel (and disconnect the radio). Guard against that by
    /// only closing when the channel is not the one used by the data connection.
    private func closeAudioChannelSafely(_ channel: IOBluetoothRFCOMMChannel, address: String) {
        if let dataConn = connections[address], dataConn.channel === channel {
            return
        }
        channel.close()
    }

    private func sendAudio(address: String, data: Data) -> Bool {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        guard let connection = audioConnections[normalizedAddress] else {
            return false
        }

        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> IOReturn in
            guard let baseAddress = ptr.baseAddress else { return kIOReturnError }
            return connection.channel.writeAsync(baseAddress, length: UInt16(data.count), refcon: nil)
        }
        return result == kIOReturnSuccess
    }
    
    private func send(address: String, data: Data) -> Bool {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        
        guard let connection = connections[normalizedAddress] else {
            return false
        }
        
        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> IOReturn in
            guard let baseAddress = ptr.baseAddress else { return kIOReturnError }
            return connection.channel.writeAsync(baseAddress, length: UInt16(data.count), refcon: nil)
        }
        
        return result == kIOReturnSuccess
    }
    
    // MARK: - IOBluetoothRFCOMMChannelDelegate

    /// Determine whether a delegate callback belongs to the data or audio channel.
    /// Returns the role ("data"/"audio"), the owning connection, and the event sink.
    private func routeFor(channel: IOBluetoothRFCOMMChannel) -> (role: String, connection: RFCOMMConnection, sink: FlutterEventSink?)? {
        for (_, conn) in connections where conn.channel === channel {
            return ("data", conn, dataSink)
        }
        for (_, conn) in audioConnections where conn.channel === channel {
            return ("audio", conn, audioSink)
        }
        return nil
    }
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-") else {
            return
        }

        guard let route = routeFor(channel: channel) else {
            return
        }


        let connection = route.connection
        if error == kIOReturnSuccess {
            connection.isConnected = true
            connection.didNotifyConnected = true
            connection.connectResult?(true)
            connection.connectResult = nil

            route.sink?([
                "event": "connected",
                "address": address.replacingOccurrences(of: "-", with: ":")
            ])
        } else {
            if route.role == "audio" {
                audioConnections.removeValue(forKey: address)
                connection.connectResult?(FlutterError(
                    code: "AUDIO_CONNECTION_FAILED",
                    message: "RFCOMM connection failed: \(error)",
                    details: nil
                ))
                connection.connectResult = nil
            } else {
                // Control channel: an explicit open failure should retry rather
                // than fail immediately (the per-attempt timeout handles the
                // no-callback case). retryOrFailControlConnect reports the final
                // failure once all attempts are exhausted.
                connections.removeValue(forKey: address)
                let pendingResult = connection.connectResult
                connection.connectResult = nil
                if let pendingResult = pendingResult {
                    retryOrFailControlConnect(
                        device: connection.device,
                        address: address,
                        attempt: connection.connectAttempt,
                        result: pendingResult
                    )
                }
            }
        }
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-") else {
            return
        }

        guard let route = routeFor(channel: channel) else {
            // The channel is no longer tracked (it was closed as part of a
            // locally-initiated operation that already cleaned up, e.g. an audio
            // connection timeout or an intentional disconnect). There is nothing
            // to report and, crucially, we must NOT fall back to emitting a
            // disconnect on the data channel.
            return
        }

        let connection = route.connection

        // On macOS, opening OR closing the second (audio) RFCOMM channel to a
        // device can trigger a spurious rfcommChannelClosed callback on the
        // already-open DATA channel even though the OS-level link stays alive and
        // data keeps flowing. If an audio channel is present for this device, or
        // one was opened/closed very recently, defer the decision: keep the
        // connection and check shortly afterward whether fresh data has arrived.
        // The radio streams status frames roughly once per second, so continued
        // data means the close was spurious and must NOT be reported as a radio
        // disconnect.
        let audioRecentlyActive: Bool = {
            if audioConnections[address] != nil { return true }
            if let last = lastAudioActivity[address], Date().timeIntervalSince(last) < 5.0 { return true }
            return false
        }()
        if route.role == "data", audioRecentlyActive {
            let closeTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                guard let conn = self.connections[address] else { return }
                if conn.lastDataReceived > closeTime {
                    return
                }
                self.connections.removeValue(forKey: address)
                if conn.didNotifyConnected {
                    self.dataSink?([
                        "event": "disconnected",
                        "address": address.replacingOccurrences(of: "-", with: ":")
                    ])
                }
            }
            return
        }

        if route.role == "audio" {
            audioConnections.removeValue(forKey: address)
        } else {
            connections.removeValue(forKey: address)
        }

        // Only report a disconnect if this channel had previously reported a
        // successful connection. This prevents a failed/timed-out connection
        // attempt from emitting a spurious "disconnected" event.
        if connection.didNotifyConnected {
            route.sink?([
                "event": "disconnected",
                "address": address.replacingOccurrences(of: "-", with: ":")
            ])
        }
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-"),
              let ptr = dataPointer else {
            return
        }

        guard let route = routeFor(channel: channel) else {
            return
        }

        let data = Data(bytes: ptr, count: dataLength)

        route.connection.lastDataReceived = Date()

        if route.role == "audio" {
            lastAudioActivity[address] = Date()
            // Audio is kept connected across enable/disable cycles; while
            // disabled we drop incoming frames instead of closing the channel
            // (closing it would also kill the control channel on macOS).
            if audioForwardingEnabled[address] != true {
                return
            }
        }

        if let sink = route.sink {
            sink([
                "event": "data",
                "address": address.replacingOccurrences(of: "-", with: ":"),
                "data": FlutterStandardTypedData(bytes: data)
            ])
        }
    }
    
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
    }
    
    func rfcommChannelQueueSpaceAvailable(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
    }
}

// MARK: - FlutterStreamHandler

extension BluetoothClassicHandler: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        dataSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        dataSink = nil
        return nil
    }
}

// MARK: - Audio Event Stream Handler

/// Separate stream handler for the audio (Generic Audio RFCOMM) event channel.
/// Forwards the event sink to its owning BluetoothClassicHandler.
private class AudioEventStreamHandler: NSObject, FlutterStreamHandler {
    weak var owner: BluetoothClassicHandler?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        owner?.audioSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        owner?.audioSink = nil
        return nil
    }
}

// MARK: - RFCOMMConnection

private class RFCOMMConnection {
    let device: IOBluetoothDevice
    let channel: IOBluetoothRFCOMMChannel
    let address: String
    var isConnected: Bool = false
    /// True once a "connected" event has been emitted for this channel. Used to
    /// ensure a matching "disconnected" event is only emitted for channels that
    /// actually completed their connection (avoids spurious disconnects from
    /// failed/timed-out connection attempts).
    var didNotifyConnected: Bool = false
    var connectResult: FlutterResult?
    /// The control-channel connect attempt number that created this connection.
    /// Used so a stale per-attempt timeout cannot tear down a newer attempt.
    var connectAttempt: Int = 0
    /// Timestamp of the most recent inbound data on this channel. Used to detect
    /// whether a data-channel "close" callback was spurious (data keeps flowing).
    var lastDataReceived: Date = Date()
    
    init(device: IOBluetoothDevice, channel: IOBluetoothRFCOMMChannel, address: String) {
        self.device = device
        self.channel = channel
        self.address = address
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
            binaryMessenger: registrar.messenger
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(
            name: "com.htcommander/speech_to_text_events",
            binaryMessenger: registrar.messenger
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
        // server recognition, which requires the network.client entitlement.
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

// MARK: - System Audio Handler

/// Handler for the host computer's default output device volume and mute,
/// using CoreAudio. Mirrors the "computer master volume" controls of the C#
/// RadioAudioForm (masterVolumeTrackBar / masterMuteButton), which on Windows
/// used NAudio's MMDevice.AudioEndpointVolume.
///
/// Channel contract (see lib/services/system_audio.dart):
///   method  com.htcommander/system_audio
///     getMasterVolume() -> Double? (0.0-1.0, null if unavailable)
///     setMasterVolume({volume: Double})
///     getMute() -> Bool? (null if unavailable)
///     setMute({mute: Bool})
class SystemAudioHandler: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SystemAudioHandler()
        let channel = FlutterMethodChannel(
            name: "com.htcommander/system_audio",
            binaryMessenger: registrar.messenger
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getMasterVolume":
            result(getMasterVolume())
        case "setMasterVolume":
            let args = call.arguments as? [String: Any]
            let v = (args?["volume"] as? Double) ?? 0
            setMasterVolume(Float32(v))
            result(nil)
        case "getMute":
            result(getMute())
        case "setMute":
            let args = call.arguments as? [String: Any]
            let m = (args?["mute"] as? Bool) ?? false
            setMute(m)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// The current default output device, or nil if none is available.
    private func defaultOutputDevice() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        if status != noErr || deviceID == kAudioObjectUnknown { return nil }
        return deviceID
    }

    private func getMasterVolume() -> Double? {
        guard let dev = defaultOutputDevice() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &volume)
        if status != noErr { return nil }
        return Double(max(0, min(1, volume)))
    }

    private func setMasterVolume(_ volume: Float32) {
        guard let dev = defaultOutputDevice() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
              settable.boolValue else { return }
        var v = max(0, min(1, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &v)
    }

    private func getMute() -> Bool? {
        guard let dev = defaultOutputDevice() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &muted)
        if status != noErr { return nil }
        return muted != 0
    }

    private func setMute(_ mute: Bool) {
        guard let dev = defaultOutputDevice() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
              settable.boolValue else { return }
        var val: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &val)
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
            binaryMessenger: registrar.messenger
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

    /// Speaks [text] through the computer's speakers so the user can audition
    /// the selected voice / rate / pitch without transmitting.
    private func preview(args: [String: Any]) {
        let text = (args["text"] as? String) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(makeUtterance(args: args))
    }

    private func getVoices() -> [[String: String]] {
        return AVSpeechSynthesisVoice.speechVoices().map { voice in
            let quality: String
            if #available(macOS 13.0, *), voice.quality == .premium {
                quality = "premium"
            } else if voice.quality == .enhanced {
                quality = "enhanced"
            } else {
                quality = "default"
            }
            var gender = "unspecified"
            if #available(macOS 12.0, *) {
                switch voice.gender {
                case .male: gender = "male"
                case .female: gender = "female"
                default: gender = "unspecified"
                }
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

// MARK: - PCM Player Handler

/// Streaming 16-bit PCM playback plugin for macOS, backed by CoreAudio's
/// `AudioQueue`. `flutter_pcm_sound` (used on iOS/Android) always plays on the
/// operating-system default output device, so this native player is used on
/// macOS instead to let the user route radio audio to a specific output device
/// selected in the Audio tab. It mirrors the Windows/Linux native players and
/// exposes the same channel surface consumed by lib/radio/pcm_player.dart:
///
///   method  com.htcommander/pcm_player
///     setLogLevel / start                        -> null   (no-ops)
///     setup({sampleRate, channels, deviceId})    -> Bool   (opens the device)
///     listDevices()                              -> [[id, label]] output devices
///     setFeedThreshold({threshold})              -> null
///     feed({buffer})                             -> Bool   (queues PCM bytes)
///     release()                                  -> null
///   event   com.htcommander/pcm_player_feed
///     emits the number of PCM frames still buffered after each buffer drains
///
/// A fresh `AudioQueueBuffer` is allocated per `feed` chunk and freed in the
/// output callback (mirroring the Windows waveOut-per-chunk model), which keeps
/// the buffering logic simple and correct for the radio's variable-size chunks.
class PcmPlayerHandler: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var queue: AudioQueueRef?
    private var sampleRate: Int = 32000
    private var channels: Int = 1
    private var bufferedFrames: Int64 = 0
    private var feedThreshold: Int = 0

    // Serializes access to queue/bufferedFrames between the platform thread and
    // the AudioQueue callback thread.
    private let lock = NSLock()

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PcmPlayerHandler()
        let mc = FlutterMethodChannel(
            name: "com.htcommander/pcm_player",
            binaryMessenger: registrar.messenger)
        instance.methodChannel = mc
        registrar.addMethodCallDelegate(instance, channel: mc)

        let ec = FlutterEventChannel(
            name: "com.htcommander/pcm_player_feed",
            binaryMessenger: registrar.messenger)
        instance.eventChannel = ec
        ec.setStreamHandler(instance)
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

    // MARK: Method dispatch

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "setLogLevel", "start":
            // Playback starts as soon as the queue is created in setup; nothing
            // to do here.
            result(nil)
        case "setup":
            let rate = (args?["sampleRate"] as? Int) ?? 32000
            let chans = (args?["channels"] as? Int) ?? 1
            let deviceId = (args?["deviceId"] as? String) ?? ""
            result(setup(rate: rate, channels: chans, deviceId: deviceId))
        case "listDevices":
            result(listDevices())
        case "setFeedThreshold":
            feedThreshold = (args?["threshold"] as? Int) ?? 0
            result(nil)
        case "feed":
            if let data = (args?["buffer"] as? FlutterStandardTypedData)?.data {
                result(feed(data))
            } else {
                result(false)
            }
        case "release":
            release()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Playback

    // C-convention output callback: recovers the handler from inUserData and
    // hands the drained buffer back for accounting/recycling. Must not capture.
    private let outputCallback: AudioQueueOutputCallback = { inUserData, inAQ, inBuffer in
        guard let inUserData = inUserData else { return }
        let handler = Unmanaged<PcmPlayerHandler>.fromOpaque(inUserData).takeUnretainedValue()
        handler.onBufferDone(aq: inAQ, buffer: inBuffer)
    }

    private func setup(rate: Int, channels chans: Int, deviceId: String) -> Bool {
        release()
        lock.lock(); defer { lock.unlock() }

        sampleRate = rate > 0 ? rate : 32000
        channels = chans > 0 ? chans : 1

        var format = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 2),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0)

        var newQueue: AudioQueueRef?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioQueueNewOutput(
            &format, outputCallback, selfPtr, nil, nil, 0, &newQueue)
        guard status == noErr, let q = newQueue else {
            queue = nil
            return false
        }

        // Route to the requested output device (its CoreAudio UID). An empty id
        // leaves the queue on the OS default device. The property value is a
        // CFStringRef, so we pass a pointer to the string's opaque reference.
        if !deviceId.isEmpty {
            let cfUid = deviceId as CFString
            var uidRef = Unmanaged.passUnretained(cfUid).toOpaque()
            _ = withUnsafePointer(to: &uidRef) { ptr in
                AudioQueueSetProperty(
                    q, kAudioQueueProperty_CurrentDevice, ptr,
                    UInt32(MemoryLayout<UnsafeMutableRawPointer>.size))
            }
        }

        queue = q
        bufferedFrames = 0
        AudioQueueStart(q, nil)
        return true
    }

    private func feed(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let q = queue, !data.isEmpty else { return false }

        let byteSize = UInt32(data.count)
        var bufferRef: AudioQueueBufferRef?
        guard AudioQueueAllocateBuffer(q, byteSize, &bufferRef) == noErr,
              let buffer = bufferRef else {
            return false
        }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(buffer.pointee.mAudioData, base, data.count)
            }
        }
        buffer.pointee.mAudioDataByteSize = byteSize
        if AudioQueueEnqueueBuffer(q, buffer, 0, nil) != noErr {
            AudioQueueFreeBuffer(q, buffer)
            return false
        }

        let frameBytes = max(channels * 2, 2)
        bufferedFrames += Int64(data.count / frameBytes)
        return true
    }

    private func onBufferDone(aq: AudioQueueRef, buffer: AudioQueueBufferRef) {
        lock.lock()
        let frameBytes = max(channels * 2, 2)
        let frames = Int64(Int(buffer.pointee.mAudioDataByteSize) / frameBytes)
        bufferedFrames -= frames
        if bufferedFrames < 0 { bufferedFrames = 0 }
        let remaining = bufferedFrames
        AudioQueueFreeBuffer(aq, buffer)
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(Int(remaining))
        }
    }

    private func release() {
        lock.lock()
        let q = queue
        queue = nil
        bufferedFrames = 0
        lock.unlock()

        if let q = q {
            AudioQueueStop(q, true)   // synchronous: stops pending callbacks
            AudioQueueDispose(q, true) // frees all remaining allocated buffers
        }
    }

    // MARK: Device enumeration

    /// Enumerates output-capable audio devices as {id: UID, label: name} maps.
    private func listDevices() -> [[String: String]] {
        var devices: [[String: String]] = []

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return devices
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return devices
        }

        for dev in deviceIDs {
            // Skip devices that have no output streams (input-only devices).
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(dev, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                continue
            }
            guard let uid = deviceStringProperty(dev, kAudioDevicePropertyDeviceUID) else {
                continue
            }
            let name = deviceStringProperty(dev, kAudioObjectPropertyName) ?? uid
            devices.append(["id": uid, "label": name])
        }
        return devices
    }

    /// Reads a CFString device property (UID, name, ...) as a Swift String.
    private func deviceStringProperty(_ dev: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfStr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfStr) { ptr -> OSStatus in
            AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr)
        }
        if status != noErr { return nil }
        return cfStr as String?
    }
}

// MARK: - App Delegate

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register all generated plugins (shared_preferences, window_manager, etc.)
    // for sub-windows created by desktop_multi_window. Without this, plugin
    // channels such as shared_preferences are unavailable in detached windows,
    // causing "Communicating on a dead channel" crashes.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)

      // Register the custom Bluetooth Classic handler for the sub-window too,
      // matching the main window setup in MainFlutterWindow.
      let registrar = controller.registrar(forPlugin: "BluetoothClassicHandler")
      BluetoothClassicHandler.register(with: registrar)

      // Register the speech-to-text handler for the sub-window too.
      let sttRegistrar = controller.registrar(forPlugin: "SpeechToTextHandler")
      SpeechToTextHandler.register(with: sttRegistrar)

      // Register the system audio (computer master volume) handler.
      let sysAudioRegistrar = controller.registrar(forPlugin: "SystemAudioHandler")
      SystemAudioHandler.register(with: sysAudioRegistrar)

      // Register the text-to-speech handler (Apple AVSpeechSynthesizer).
      let ttsRegistrar = controller.registrar(forPlugin: "TextToSpeechHandler")
      TextToSpeechHandler.register(with: ttsRegistrar)

      // Register the native PCM player (CoreAudio) for the sub-window too.
      let pcmRegistrar = controller.registrar(forPlugin: "PcmPlayerHandler")
      PcmPlayerHandler.register(with: pcmRegistrar)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
