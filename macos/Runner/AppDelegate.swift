import Cocoa
import FlutterMacOS
import desktop_multi_window
import window_manager
import IOBluetooth

// MARK: - Bluetooth Classic Handler

/// Handler for Bluetooth Classic operations on macOS
/// Uses IOBluetooth framework for RFCOMM (Serial Port Profile) connections
class BluetoothClassicHandler: NSObject, FlutterPlugin, IOBluetoothRFCOMMChannelDelegate {
    
    private var methodChannel: FlutterMethodChannel?
    private var dataChannel: FlutterEventChannel?
    private var dataSink: FlutterEventSink?
    
    // Active RFCOMM connections: deviceAddress -> RFCOMMConnection
    private var connections: [String: RFCOMMConnection] = [:]
    
    // Known compatible radio device name patterns
    private static let targetDeviceNames = [
        "UV-PRO", "UV-50PRO", "GA-5WB", "VR-N75", "VR-N76", "VR-N7500", "VR-N7600", "DB50-B",
        "WP-C1", "HT-CH1", "QUANSHENG", "VR-N", "SA-888S", "HG-UV98", "UV-98",
        "HAM-AIO", "VR-6600PRO", "TH-UV88", "3B01B", "E1WPR", "PNI-HP98WP"
    ]
    
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
                "isConnected": device.isConnected()
            ])
        }
        
        return devices
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
            
            // Check if this device matches any known radio name pattern
            let isCompatible = Self.targetDeviceNames.contains { pattern in
                name.localizedCaseInsensitiveContains(pattern)
            }
            
            if isCompatible {
                seenAddresses.insert(normalizedAddress)
                compatibleDevices.append([
                    "name": name,
                    "address": normalizedAddress,
                    "isPaired": true,
                    "isConnected": device.isConnected()
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
        
        NSLog("BluetoothClassic: connect called for \(normalizedAddress)")
        
        // Check if already connected
        if let existingConnection = connections[normalizedAddress] {
            if existingConnection.isConnected {
                NSLog("BluetoothClassic: Already connected to \(normalizedAddress)")
                result(true)
                return
            } else {
                // Clean up stale connection
                NSLog("BluetoothClassic: Cleaning up stale connection for \(normalizedAddress)")
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
        
        NSLog("BluetoothClassic: Device found: \(device.name ?? "unknown"), isConnected: \(device.isConnected())")
        
        // If device shows as connected but we don't have a connection, close it
        if device.isConnected() {
            NSLog("BluetoothClassic: Device reports connected, closing existing connection first...")
            device.closeConnection()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Perform SDP query to get fresh services
        NSLog("BluetoothClassic: Performing SDP query...")
        let sdpResult = device.performSDPQuery(nil)
        if sdpResult != kIOReturnSuccess {
            NSLog("BluetoothClassic: SDP query failed with error: \(sdpResult), will try default channel")
        } else {
            NSLog("BluetoothClassic: SDP query completed")
        }
        
        // Serial Port Profile UUID: 00001101-0000-1000-8000-00805F9B34FB (for DATA)
        // Generic Audio UUID: 00001203-0000-1000-8000-00805F9B34FB (for AUDIO - we DON'T want this)
        let sppUUID = IOBluetoothSDPUUID(uuid16: 0x1101)
        let audioUUID = IOBluetoothSDPUUID(uuid16: 0x1203)
        
        // Track found channels with their counts (channels used by multiple services are more likely to be SPP)
        var channelCounts: [BluetoothRFCOMMChannelID: Int] = [:]
        var sppChannelID: BluetoothRFCOMMChannelID = 0
        var audioChannelID: BluetoothRFCOMMChannelID = 0
        
        // First try: Use getServiceRecordForUUID to directly find SPP service
        NSLog("BluetoothClassic: Looking for RFCOMM services on device")
        if let sppRecord = device.getServiceRecord(for: sppUUID) {
            var ch: BluetoothRFCOMMChannelID = 0
            if sppRecord.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                sppChannelID = ch
                NSLog("BluetoothClassic: Found SPP service directly! Channel: \(ch)")
            }
        }
        
        // Also check for audio service so we know which channel to avoid
        if let audioRecord = device.getServiceRecord(for: audioUUID) {
            var ch: BluetoothRFCOMMChannelID = 0
            if audioRecord.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                audioChannelID = ch
                NSLog("BluetoothClassic: Found Audio service directly! Channel: \(ch) (will avoid)")
            }
        }
        
        // Second try: Enumerate all services and look for UUIDs
        if let serviceRecords = device.services as? [IOBluetoothSDPServiceRecord] {
            NSLog("BluetoothClassic: Found \(serviceRecords.count) service records")
            for record in serviceRecords {
                var isSPP = false
                var isAudio = false
                
                // Use getAttributeDataElement to properly access service class UUIDs (attribute 0x0001)
                if let serviceClassElement = record.getAttributeDataElement(0x0001),
                   let uuidArray = serviceClassElement.getArrayValue() as? [IOBluetoothSDPDataElement] {
                    for uuidElement in uuidArray {
                        if let uuid = uuidElement.getUUIDValue() {
                            // Log the UUID for debugging (IOBluetoothSDPUUID is an NSData subclass)
                            let uuidHex = (uuid as Data).map { String(format: "%02X", $0) }.joined()
                            NSLog("BluetoothClassic: Service class UUID: \(uuidHex)")
                            
                            if uuid.isEqual(to: sppUUID) {
                                NSLog("BluetoothClassic: -> This is SPP (Serial Port Profile)!")
                                isSPP = true
                            }
                            if uuid.isEqual(to: audioUUID) {
                                NSLog("BluetoothClassic: -> This is Generic Audio!")
                                isAudio = true
                            }
                        }
                    }
                }
                
                // Get the RFCOMM channel for this service
                var ch: BluetoothRFCOMMChannelID = 0
                if record.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                    channelCounts[ch, default: 0] += 1
                    NSLog("BluetoothClassic: Service has RFCOMM channel: \(ch) (count: \(channelCounts[ch]!))")
                    
                    if isSPP && sppChannelID == 0 {
                        sppChannelID = ch
                        NSLog("BluetoothClassic: Identified as SPP data channel: \(ch)")
                    } else if isAudio && audioChannelID == 0 {
                        audioChannelID = ch
                        NSLog("BluetoothClassic: Identified as audio channel: \(ch)")
                    }
                }
            }
        } else {
            NSLog("BluetoothClassic: No service records found")
        }
        
        // Build list of channels to try in priority order
        // The C# reference just uses the SPP service directly, so we should try SPP first
        var channelsToTry: [BluetoothRFCOMMChannelID] = []
        
        // 1. Add SPP channel first (even if same as audio - the C# code doesn't avoid it)
        if sppChannelID != 0 {
            channelsToTry.append(sppChannelID)
            NSLog("BluetoothClassic: Will try SPP channel: \(sppChannelID)")
        }
        
        // 2. Add other known working channels for HT radios
        for ch: BluetoothRFCOMMChannelID in [4, 2, 3, 1] {
            if !channelsToTry.contains(ch) {
                channelsToTry.append(ch)
            }
        }
        
        // 3. Add any other channels from SDP
        for ch in channelCounts.keys.sorted() {
            if !channelsToTry.contains(ch) {
                channelsToTry.append(ch)
            }
        }
        
        NSLog("BluetoothClassic: Channels to try in order: \(channelsToTry)")
        
        // Try each channel until one works
        var rfcommChannel: IOBluetoothRFCOMMChannel?
        var openResult: IOReturn = kIOReturnError
        var successChannelID: BluetoothRFCOMMChannelID = 0
        
        for channelToTry in channelsToTry {
            NSLog("BluetoothClassic: Trying RFCOMM channel \(channelToTry)")
            
            rfcommChannel = nil
            openResult = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: channelToTry, delegate: self)
            
            if openResult == kIOReturnSuccess && rfcommChannel != nil {
                successChannelID = channelToTry
                NSLog("BluetoothClassic: Channel \(channelToTry) opened successfully")
                break
            }
            
            NSLog("BluetoothClassic: Channel \(channelToTry) failed: \(openResult)")
            device.closeConnection()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        if openResult != kIOReturnSuccess || rfcommChannel == nil {
            NSLog("BluetoothClassic: Failed to open any RFCOMM channel")
            result(FlutterError(code: "CONNECTION_FAILED", message: "Failed to open RFCOMM channel", details: nil))
            return
        }
        
        let channel = rfcommChannel!
        
        // Explicitly set the delegate on the channel
        channel.setDelegate(self)
        NSLog("BluetoothClassic: RFCOMM channel \(successChannelID) opened, delegate set, MTU: \(channel.getMTU())")
        
        // Store the connection
        let connection = RFCOMMConnection(device: device, channel: channel, address: normalizedAddress)
        connection.connectResult = result
        connections[normalizedAddress] = connection
        
        // Set up a connection timeout (10 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if let conn = self.connections[normalizedAddress], !conn.isConnected {
                NSLog("BluetoothClassic: Connection timeout for \(normalizedAddress)")
                conn.channel.close()
                self.connections.removeValue(forKey: normalizedAddress)
                conn.connectResult?(FlutterError(
                    code: "CONNECTION_TIMEOUT",
                    message: "Connection timed out after 10 seconds",
                    details: nil
                ))
            }
        }
        
        // Result will be sent when connection completes (in delegate callback)
    }
    
    private func disconnect(address: String) {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        
        if let connection = connections.removeValue(forKey: normalizedAddress) {
            connection.channel.close()
        }
    }
    
    private func send(address: String, data: Data) -> Bool {
        let normalizedAddress = address.uppercased().replacingOccurrences(of: ":", with: "-")
        NSLog("BluetoothClassic: send called for \(normalizedAddress), \(data.count) bytes")
        
        guard let connection = connections[normalizedAddress] else {
            NSLog("BluetoothClassic: send - no connection found for \(normalizedAddress)")
            return false
        }
        
        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> IOReturn in
            guard let baseAddress = ptr.baseAddress else { return kIOReturnError }
            return connection.channel.writeAsync(baseAddress, length: UInt16(data.count), refcon: nil)
        }
        
        NSLog("BluetoothClassic: send result: \(result)")
        return result == kIOReturnSuccess
    }
    
    // MARK: - IOBluetoothRFCOMMChannelDelegate
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        NSLog("BluetoothClassic: rfcommChannelOpenComplete called, error: \(error)")
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-") else {
            NSLog("BluetoothClassic: rfcommChannelOpenComplete - failed to get device info")
            return
        }
        
        NSLog("BluetoothClassic: rfcommChannelOpenComplete for \(address)")
        
        if let connection = connections[address] {
            if error == kIOReturnSuccess {
                connection.isConnected = true
                connection.connectResult?(true)
                connection.connectResult = nil
                
                // Notify Flutter of successful connection
                NSLog("BluetoothClassic: Sending connected event to Flutter")
                dataSink?([
                    "event": "connected",
                    "address": address.replacingOccurrences(of: "-", with: ":")
                ])
            } else {
                connections.removeValue(forKey: address)
                connection.connectResult?(FlutterError(
                    code: "CONNECTION_FAILED",
                    message: "RFCOMM connection failed: \(error)",
                    details: nil
                ))
            }
        }
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-") else {
            return
        }
        
        connections.removeValue(forKey: address)
        
        // Notify Flutter of disconnection
        dataSink?([
            "event": "disconnected",
            "address": address.replacingOccurrences(of: "-", with: ":")
        ])
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        NSLog("BluetoothClassic: rfcommChannelData called, length: \(dataLength)")
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-"),
              let ptr = dataPointer else {
            NSLog("BluetoothClassic: rfcommChannelData - failed to get device info")
            return
        }
        
        let data = Data(bytes: ptr, count: dataLength)
        NSLog("BluetoothClassic: Received \(dataLength) bytes from \(address): \(data.map { String(format: "%02X", $0) }.joined())")
        
        // Send data to Flutter
        if dataSink != nil {
            NSLog("BluetoothClassic: Sending data event to Flutter")
            dataSink?([
                "event": "data",
                "address": address.replacingOccurrences(of: "-", with: ":"),
                "data": FlutterStandardTypedData(bytes: data)
            ])
        } else {
            NSLog("BluetoothClassic: dataSink is nil, cannot send data to Flutter")
        }
    }
    
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        NSLog("BluetoothClassic: rfcommChannelWriteComplete called, error: \(error)")
    }
    
    func rfcommChannelQueueSpaceAvailable(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        NSLog("BluetoothClassic: rfcommChannelQueueSpaceAvailable called")
    }
}

// MARK: - FlutterStreamHandler

extension BluetoothClassicHandler: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        NSLog("BluetoothClassic: onListen called - EventChannel connected")
        dataSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NSLog("BluetoothClassic: onCancel called - EventChannel disconnected")
        dataSink = nil
        return nil
    }
}

// MARK: - RFCOMMConnection

private class RFCOMMConnection {
    let device: IOBluetoothDevice
    let channel: IOBluetoothRFCOMMChannel
    let address: String
    var isConnected: Bool = false
    var connectResult: FlutterResult?
    
    init(device: IOBluetoothDevice, channel: IOBluetoothRFCOMMChannel, address: String) {
        self.device = device
        self.channel = channel
        self.address = address
    }
}

// MARK: - App Delegate

@main
class AppDelegate: FlutterAppDelegate {
  private var bluetoothHandlerRegistered = false
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register window_manager for sub-windows created by desktop_multi_window
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
    }
    
    // Register Bluetooth Classic handler
    registerBluetoothHandler()
  }
  
  override func applicationDidBecomeActive(_ notification: Notification) {
    // Register Bluetooth Classic handler when app becomes active (fallback)
    registerBluetoothHandler()
  }
  
  private func registerBluetoothHandler() {
    if bluetoothHandlerRegistered {
      return
    }
    
    if let mainWindow = NSApp.mainWindow,
       let flutterViewController = mainWindow.contentViewController as? FlutterViewController {
      let registrar = flutterViewController.registrar(forPlugin: "BluetoothClassicHandler")
      BluetoothClassicHandler.register(with: registrar)
      bluetoothHandlerRegistered = true
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
