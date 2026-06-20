//
// bttest — IOBluetooth RFCOMM diagnostic tool for HT radios on macOS
//
// Connects to a radio over Bluetooth Classic RFCOMM and lets you observe the
// raw behavior of the SPP (control) and Generic Audio channels independently,
// without the Flutter app in the way. Use it to answer questions like:
//   - What RFCOMM services/channels does the radio actually advertise?
//   - Is Generic Audio (0x1203) on a different channel than SPP (0x1101)?
//   - When both channels are open, does control data leak onto the audio
//     channel (i.e. is the per-channel demux working)?
//   - Does opening/closing the audio channel disturb the control channel?
//
// Usage:
//   swift run bttest <MAC> <mode> [options]
//
//   <MAC>   Radio address, e.g. 38:D2:00:00:FA:F9 or 38-D2-00-00-FA-F9
//   <mode>  scan      List all SDP services + RFCOMM channels, then exit.
//           control   Open only the SPP/control channel and dump traffic.
//           audio     Open only the Generic Audio channel and dump traffic.
//           both      Open control, wait, then open audio. Dump labeled
//                     traffic from both so you can see which frames land where.
//           probe     Open each RFCOMM channel in a range (default 0..8) one
//                     at a time, listen briefly, and report which channels
//                     open and receive any data.
//
//   Options:
//     --control-ch N   Force the control channel ID (default: SPP 0x1101).
//     --audio-ch N     Force the audio channel ID (default: GenericAudio 0x1203).
//     --close-audio S  In 'both' mode, close the audio channel after S seconds
//                      (then keep running) to test whether control survives.
//
// Notes:
//   * This uses classic IOBluetooth RFCOMM (not CoreBluetooth). The radio must
//     already be paired in System Settings > Bluetooth.
//   * If you see no data at all, grant the terminal Bluetooth permission under
//     System Settings > Privacy & Security > Bluetooth, then retry.
//   * Press Ctrl+C to quit.
//

import Foundation
import IOBluetooth

// MARK: - Helpers

func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}

func ts() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

func log(_ s: String) {
    print("[\(ts())] \(s)")
}

// Recursively collect every UUID found anywhere in an SDP data element tree.
func collectUUIDs(_ el: IOBluetoothSDPDataElement, into out: inout [String]) {
    if let u = el.getUUIDValue() {
        // IOBluetoothSDPUUID is a subclass of NSData.
        let h = hex(Data(referencing: u as NSData))
        if !out.contains(h) { out.append(h) }
        return
    }
    if let arr = el.getArrayValue() as? [IOBluetoothSDPDataElement] {
        for child in arr { collectUUIDs(child, into: &out) }
    }
}

// MARK: - Tester

final class BTTester: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let address: String
    let mode: String
    let forcedControlCh: BluetoothRFCOMMChannelID?
    let forcedAudioCh: BluetoothRFCOMMChannelID?
    let closeAudioAfter: Double?
    let handshake: Bool
    let probeStart: Int
    let probeEnd: Int
    let probeDwell: Double

    var device: IOBluetoothDevice?
    // Track labels by channel object identity so we can attribute callbacks.
    var labels: [ObjectIdentifier: String] = [:]
    var openChannels: [IOBluetoothRFCOMMChannel] = []
    var handshakeSent = false
    // Probe-mode bookkeeping: bytes/frames received per channel number.
    var rxBytes: [Int: Int] = [:]
    var rxFrames: [Int: Int] = [:]
    var openedOK: [Int: Bool] = [:]

    init(address: String,
         mode: String,
         forcedControlCh: BluetoothRFCOMMChannelID?,
         forcedAudioCh: BluetoothRFCOMMChannelID?,
         closeAudioAfter: Double?,
         handshake: Bool,
         probeStart: Int = 0,
         probeEnd: Int = 8,
         probeDwell: Double = 4.0) {
        self.address = address
        self.mode = mode
        self.forcedControlCh = forcedControlCh
        self.forcedAudioCh = forcedAudioCh
        self.closeAudioAfter = closeAudioAfter
        self.handshake = handshake
        self.probeStart = probeStart
        self.probeEnd = probeEnd
        self.probeDwell = probeDwell
    }

    func start() {
        let normalized = address.uppercased().replacingOccurrences(of: ":", with: "-")
        guard let dev = IOBluetoothDevice(addressString: normalized) else {
            log("ERROR: could not create IOBluetoothDevice for \(address)")
            exit(1)
        }
        device = dev
        log("Device: name=\(dev.name ?? "unknown") connected=\(dev.isConnected()) address=\(dev.addressString ?? "?")")

        log("Performing SDP query (waiting 2s for results)...")
        let r = dev.performSDPQuery(nil)
        log("performSDPQuery returned \(r)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.listServicesAndConnect()
        }
    }

    func listServicesAndConnect() {
        guard let dev = device else { return }
        log("=== SDP service records ===")
        if let records = dev.services as? [IOBluetoothSDPServiceRecord] {
            for rec in records {
                var ch: BluetoothRFCOMMChannelID = 0
                let hasCh = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess
                let name = rec.getServiceName() ?? "(no name)"
                // Walk the whole record's attribute tree and collect every UUID
                // we find (service class UUIDs like 1101/1203 plus protocol
                // UUIDs like L2CAP 0100 / RFCOMM 0003). getAttributeDataElement
                // on a single attribute proved unreliable, so recurse instead.
                var uuids: [String] = []
                if let attrs = rec.attributes as? [NSNumber: IOBluetoothSDPDataElement] {
                    for key in attrs.keys.sorted(by: { $0.intValue < $1.intValue }) {
                        if let el = attrs[key] { collectUUIDs(el, into: &uuids) }
                    }
                }
                log("  Service: \"\(name)\" | RFCOMM ch=\(hasCh ? String(ch) : "none") | UUIDs=[\(uuids.joined(separator: ", "))]")
            }
        } else {
            log("  (no service records returned)")
        }
        log("===========================")

        switch mode {
        case "scan":
            log("Scan complete. Exiting.")
            exit(0)
        case "control":
            openControl()
        case "audio":
            openAudio()
        case "both":
            openControl()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.openAudio()
                if let s = self?.closeAudioAfter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + s) {
                        self?.closeAudio()
                        // After closing audio, keep running briefly to observe
                        // whether the CONTROL channel also gets a (spurious)
                        // close, then exit cleanly so buffered output flushes.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self?.probeControlAfterClose()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            log("post-close observation window elapsed; exiting.")
                            exit(0)
                        }
                    }
                }
            }
        case "probe":
            log("Probing RFCOMM channels \(probeStart)..\(probeEnd), \(probeDwell)s each, handshake=\(handshake).")
            probeChannel(probeStart)
        default:
            log("ERROR: unknown mode '\(mode)' (use scan|control|audio|both)")
            exit(1)
        }
    }

    func channelID(forUUID16 uuid16: UInt16) -> BluetoothRFCOMMChannelID? {
        guard let dev = device,
              let rec = dev.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: uuid16)) else { return nil }
        var ch: BluetoothRFCOMMChannelID = 0
        return rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess ? ch : nil
    }

    func openControl() {
        guard let dev = device else { return }
        let chID = forcedControlCh ?? channelID(forUUID16: 0x1101) ?? 1
        log("Opening CONTROL channel \(chID) (SPP 0x1101)...")
        var channel: IOBluetoothRFCOMMChannel?
        let r = dev.openRFCOMMChannelAsync(&channel, withChannelID: chID, delegate: self)
        if r == kIOReturnSuccess, let c = channel {
            c.setDelegate(self)
            labels[ObjectIdentifier(c)] = "CONTROL(ch\(chID))"
            openChannels.append(c)
            log("  CONTROL open requested ok, immediate MTU=\(c.getMTU()) isOpen=\(c.isOpen())")
            // Fallback: if openComplete doesn't fire (unreliable on 2nd channel),
            // send the handshake once the MTU shows the channel is up.
            if handshake {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, !self.handshakeSent, c.getMTU() > 0 else { return }
                    self.sendHandshake(on: c)
                }
            }
        } else {
            log("  CONTROL open FAILED: \(r)")
        }
    }

    func openAudio() {
        guard let dev = device else { return }
        guard let chID = forcedAudioCh ?? channelID(forUUID16: 0x1203) else {
            log("No Generic Audio (0x1203) service found; pass --audio-ch N to force.")
            return
        }
        log("Opening AUDIO channel \(chID) (GenericAudio 0x1203)...")
        var channel: IOBluetoothRFCOMMChannel?
        let r = dev.openRFCOMMChannelAsync(&channel, withChannelID: chID, delegate: self)
        if r == kIOReturnSuccess, let c = channel {
            c.setDelegate(self)
            labels[ObjectIdentifier(c)] = "AUDIO(ch\(chID))"
            openChannels.append(c)
            log("  AUDIO open requested ok, immediate MTU=\(c.getMTU()) isOpen=\(c.isOpen())")
        } else {
            log("  AUDIO open FAILED: \(r)")
        }
    }

    func closeAudio() {
        for c in openChannels where (labels[ObjectIdentifier(c)] ?? "").hasPrefix("AUDIO") {
            log("Closing AUDIO channel (ch\(c.getID()))...")
            c.close()
        }
    }

    // After closing audio, probe whether the CONTROL channel is still usable:
    // report its MTU/isOpen and attempt a control write. If the write succeeds
    // (and/or a response arrives) the control channel survived; if it returns
    // -536870195 the channel is dead and we must avoid closing audio at all.
    func probeControlAfterClose() {
        var found = false
        for c in openChannels where (labels[ObjectIdentifier(c)] ?? "").hasPrefix("CONTROL") {
            found = true
            log("Post-close CONTROL state: MTU=\(c.getMTU()) isOpen=\(c.isOpen())")
            send(c, gaiaFrame(group: 2, cmd: 20), label: "POST-CLOSE GET_HT_STATUS")
        }
        if !found { log("Post-close: CONTROL channel no longer in openChannels.") }
    }

    // Sequentially open one channel, listen for `probeDwell` seconds, record any
    // traffic, then close it and move to the next. Opening one at a time avoids
    // the radio's apparent inability to hold two RFCOMM channels at once.
    func probeChannel(_ ch: Int) {
        guard ch <= probeEnd else {
            printProbeSummary()
            exit(0)
        }
        guard let dev = device else { return }
        let chID = BluetoothRFCOMMChannelID(ch)
        rxBytes[ch] = 0
        rxFrames[ch] = 0
        log("--- Probing channel \(ch) ---")
        var channel: IOBluetoothRFCOMMChannel?
        let r = dev.openRFCOMMChannelAsync(&channel, withChannelID: chID, delegate: self)
        if r == kIOReturnSuccess, let c = channel {
            c.setDelegate(self)
            labels[ObjectIdentifier(c)] = "PROBE(ch\(ch))"
            openChannels.append(c)
            log("  ch\(ch) open requested ok, immediate MTU=\(c.getMTU()) isOpen=\(c.isOpen())")
            // Optionally poke the channel with the control handshake to see if it
            // elicits a response (control) or starts audio streaming.
            if handshake {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, c.getMTU() > 0 else { return }
                    self.handshakeSent = false
                    self.sendHandshake(on: c)
                }
            }
        } else {
            log("  ch\(ch) open FAILED: \(r)")
            openedOK[ch] = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + probeDwell) { [weak self] in
            guard let self = self else { return }
            if let c = channel {
                self.openedOK[ch] = c.isOpen() || c.getMTU() > 0
                log("  ch\(ch) done: opened=\(self.openedOK[ch] ?? false) frames=\(self.rxFrames[ch] ?? 0) bytes=\(self.rxBytes[ch] ?? 0)")
                c.close()
                self.openChannels.removeAll { $0 === c }
            }
            self.probeChannel(ch + 1)
        }
    }

    func printProbeSummary() {
        log("=== PROBE SUMMARY ===")
        for ch in probeStart...probeEnd {
            let opened = openedOK[ch] ?? false
            let frames = rxFrames[ch] ?? 0
            let bytes = rxBytes[ch] ?? 0
            log(String(format: "  ch%d  opened=%@  frames=%d  bytes=%d",
                       ch, opened ? "yes" : "no ", frames, bytes))
        }
        log("=====================")
    }

    // Build a GAIA-framed radio command: FF 01 00 <payloadLen> <group(2 BE)><cmd(2 BE)><data>
    // where payloadLen = data.count (the bytes after the 4-byte group+cmd header).
    func gaiaFrame(group: UInt16, cmd: UInt16, data: [UInt8] = []) -> [UInt8] {
        var payload: [UInt8] = [
            UInt8(group >> 8), UInt8(group & 0xFF),
            UInt8(cmd >> 8), UInt8(cmd & 0xFF),
        ]
        payload.append(contentsOf: data)
        let payloadLen = UInt8(payload.count - 4)
        var frame: [UInt8] = [0xFF, 0x01, 0x00, payloadLen]
        frame.append(contentsOf: payload)
        return frame
    }

    func send(_ channel: IOBluetoothRFCOMMChannel, _ frame: [UInt8], label: String) {
        var bytes = frame
        let count = UInt16(bytes.count)
        let r = bytes.withUnsafeMutableBytes { ptr -> IOReturn in
            channel.writeSync(ptr.baseAddress, length: count)
        }
        log("  TX \(label) [\(frame.count)] \(hex(Data(frame)))  -> r=\(r)")
    }

    // Replicate the Windows control-channel connect handshake. The radio appears
    // to require this before it will stream audio on the Generic Audio channel.
    func sendHandshake(on channel: IOBluetoothRFCOMMChannel) {
        guard !handshakeSent else { return }
        handshakeSent = true
        log("Sending control handshake (GET_DEV_INFO, READ_SETTINGS, READ_BSS_SETTINGS, GET_HT_STATUS, REGISTER_NOTIFICATION)...")
        // BASIC group = 2
        send(channel, gaiaFrame(group: 2, cmd: 4, data: [3]), label: "GET_DEV_INFO")        // GET_DEV_INFO(3)
        send(channel, gaiaFrame(group: 2, cmd: 10), label: "READ_SETTINGS")                 // READ_SETTINGS
        send(channel, gaiaFrame(group: 2, cmd: 33), label: "READ_BSS_SETTINGS")             // READ_BSS_SETTINGS
        send(channel, gaiaFrame(group: 2, cmd: 20), label: "GET_HT_STATUS")                 // GET_HT_STATUS
        send(channel, gaiaFrame(group: 2, cmd: 6, data: [1]), label: "REGISTER_NOTIFICATION") // HT_STATUS_CHANGED=1
    }

    func label(for channel: IOBluetoothRFCOMMChannel?) -> String {
        guard let channel = channel else { return "?" }
        return labels[ObjectIdentifier(channel)] ?? "ch\(channel.getID())"
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        log("openComplete  \(label(for: rfcommChannel))  error=\(error) MTU=\(rfcommChannel.getMTU()) isOpen=\(rfcommChannel.isOpen())")
        if handshake, error == kIOReturnSuccess,
           (labels[ObjectIdentifier(rfcommChannel)] ?? "").hasPrefix("CONTROL") {
            sendHandshake(on: rfcommChannel)
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        log("DATA  \(label(for: rfcommChannel))  [\(dataLength)]  \(hex(data))")
        // Tally per-channel traffic for probe-mode summaries.
        let lbl = labels[ObjectIdentifier(rfcommChannel)] ?? ""
        if lbl.hasPrefix("PROBE"), let ch = Int(lbl.dropFirst("PROBE(ch".count).dropLast()) {
            rxBytes[ch, default: 0] += dataLength
            rxFrames[ch, default: 0] += 1
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("CLOSED  \(label(for: rfcommChannel))")
    }

    func rfcommChannelControlSignalsChanged(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("controlSignalsChanged  \(label(for: rfcommChannel))")
    }
}

// MARK: - Entry point

func usage() -> Never {
    print("""
    bttest — IOBluetooth RFCOMM diagnostic tool

    Usage:
      swift run bttest <MAC> <mode> [--control-ch N] [--audio-ch N] [--close-audio S] [--no-handshake] [--probe-range A B] [--dwell S]

      <MAC>   e.g. 38:D2:00:00:FA:F9
      <mode>  scan | control | audio | both | probe

      In control/both modes, bttest sends the Windows connect handshake on the
      control channel (GET_DEV_INFO, READ_SETTINGS, READ_BSS_SETTINGS,
      GET_HT_STATUS, REGISTER_NOTIFICATION). Use --no-handshake to disable,
      or --handshake to force it on.

      probe opens each RFCOMM channel in a range (default 0..8) one at a time,
      listens --dwell seconds (default 4), and reports which channels opened
      and received data. Add --handshake to poke each channel with the control
      handshake.

    Examples:
      swift run bttest 38:D2:00:00:FA:F9 scan
      swift run bttest 38:D2:00:00:FA:F9 control
      swift run bttest 38:D2:00:00:FA:F9 both --close-audio 10
      swift run bttest 38:D2:00:00:FA:F9 probe
      swift run bttest 38:D2:00:00:FA:F9 probe --probe-range 0 8 --dwell 5
    """)
    exit(2)
}

let rawArgs = Array(CommandLine.arguments.dropFirst())
guard rawArgs.count >= 2 else { usage() }

let macArg = rawArgs[0]
let modeArg = rawArgs[1]

var forcedControl: BluetoothRFCOMMChannelID?
var forcedAudio: BluetoothRFCOMMChannelID?
var closeAudioAfter: Double?
var probeStart = 0
var probeEnd = 8
var probeDwell = 4.0
// Handshake defaults on for modes that open the control channel.
var handshake: Bool = (modeArg == "control" || modeArg == "both")

var i = 2
while i < rawArgs.count {
    switch rawArgs[i] {
    case "--control-ch":
        i += 1
        if i < rawArgs.count, let v = UInt8(rawArgs[i]) { forcedControl = v }
    case "--audio-ch":
        i += 1
        if i < rawArgs.count, let v = UInt8(rawArgs[i]) { forcedAudio = v }
    case "--close-audio":
        i += 1
        if i < rawArgs.count, let v = Double(rawArgs[i]) { closeAudioAfter = v }
    case "--probe-range":
        if i + 2 < rawArgs.count, let a = Int(rawArgs[i + 1]), let b = Int(rawArgs[i + 2]) {
            probeStart = a; probeEnd = b; i += 2
        }
    case "--dwell":
        i += 1
        if i < rawArgs.count, let v = Double(rawArgs[i]) { probeDwell = v }
    case "--handshake":
        handshake = true
    case "--no-handshake":
        handshake = false
    default:
        print("Unknown option: \(rawArgs[i])")
        usage()
    }
    i += 1
}

let tester = BTTester(
    address: macArg,
    mode: modeArg,
    forcedControlCh: forcedControl,
    forcedAudioCh: forcedAudio,
    closeAudioAfter: closeAudioAfter,
    handshake: handshake,
    probeStart: probeStart,
    probeEnd: probeEnd,
    probeDwell: probeDwell
)

log("bttest starting (mode=\(modeArg), mac=\(macArg)). Press Ctrl+C to quit.")
tester.start()
CFRunLoopRun()
