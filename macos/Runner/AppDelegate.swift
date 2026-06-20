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
        
        // Check if already connected
        if connections[normalizedAddress] != nil {
            result(true)
            return
        }
        
        // Find the device by address
        guard let device = IOBluetoothDevice(addressString: normalizedAddress) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found: \(address)", details: nil))
            return
        }
        
        // Get RFCOMM channel (Serial Port Profile)
        var channelID: BluetoothRFCOMMChannelID = 0
        
        // Try to find Serial Port Profile service
        if let serviceRecords = device.services as? [IOBluetoothSDPServiceRecord] {
            for record in serviceRecords {
                var ch: BluetoothRFCOMMChannelID = 0
                if record.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                    // Use first available RFCOMM channel
                    if channelID == 0 {
                        channelID = ch
                    }
                }
            }
        }
        
        // If no service records found, try channel 1 (common default for SPP)
        if channelID == 0 {
            channelID = 1
        }
        
        // Open RFCOMM channel
        var rfcommChannel: IOBluetoothRFCOMMChannel?
        let openResult = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: channelID, delegate: self)
        
        if openResult != kIOReturnSuccess {
            result(FlutterError(code: "CONNECTION_FAILED", message: "Failed to open RFCOMM channel: \(openResult)", details: nil))
            return
        }
        
        guard let channel = rfcommChannel else {
            result(FlutterError(code: "CONNECTION_FAILED", message: "RFCOMM channel is nil", details: nil))
            return
        }
        
        // Store the connection
        let connection = RFCOMMConnection(device: device, channel: channel, address: normalizedAddress)
        connection.connectResult = result
        connections[normalizedAddress] = connection
        
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
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-") else {
            return
        }
        
        if let connection = connections[address] {
            if error == kIOReturnSuccess {
                connection.isConnected = true
                connection.connectResult?(true)
                connection.connectResult = nil
                
                // Notify Flutter of successful connection
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
        guard let channel = rfcommChannel,
              let device = channel.getDevice(),
              let address = device.addressString?.uppercased().replacingOccurrences(of: ":", with: "-"),
              let ptr = dataPointer else {
            return
        }
        
        let data = Data(bytes: ptr, count: dataLength)
        
        // Send data to Flutter
        dataSink?([
            "event": "data",
            "address": address.replacingOccurrences(of: "-", with: ":"),
            "data": FlutterStandardTypedData(bytes: data)
        ])
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
