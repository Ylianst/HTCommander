# C# (Windows) Bluetooth Connection Reference

This document captures how the original Windows HTCommander C# app connects to the
radio over Bluetooth Classic, so it can be used as a reference when porting the
behavior to the Flutter/macOS app. It is based on the reference sources:

- `reference/HTCommander/src/radio/RadioBluetoothWin.cs` — **control** channel
- `reference/HTCommander/src/radio/RadioAudio.cs` — **audio** channel

## TL;DR

The radio exposes **two independent RFCOMM services** over a single paired
Bluetooth Classic device. The app opens **two separate sockets**, one per service:

| Channel | SDP service                | UUID                                     | Carries                          |
| ------- | -------------------------- | ---------------------------------------- | -------------------------------- |
| Control | Serial Port Profile (SPP)  | `00001101-0000-1000-8000-00805f9b34fb`   | GAIA-framed commands & status    |
| Audio   | Generic Audio              | `00001203-0000-1000-8000-00805f9b34fb`   | SBC audio frames (rx/tx)         |

Both connect to the **same** Bluetooth device (same MAC), but each is resolved
from its **own SDP service record**, which is what gives each one a **distinct
RFCOMM channel number**. The two sockets are fully independent: closing the audio
socket does not affect the control socket, and vice versa.

WinRT does the channel-number resolution for you: `RfcommDeviceService.ConnectionServiceName`
is derived from each service record's own `ProtocolDescriptorList`, so the SPP
record and the Generic Audio record naturally resolve to different RFCOMM channels.

## Control channel — `RadioBluetoothWin.cs`

API stack: `Windows.Devices.Bluetooth` + `Windows.Devices.Bluetooth.Rfcomm` +
`Windows.Networking.Sockets`.

### Connect sequence (`StartAsync`)

1. Convert MAC string to `ulong`:
   `Convert.ToUInt64(mac.Replace(":","").Replace("-",""), 16)`.
2. `BluetoothDevice.FromBluetoothAddressAsync(btAddress)`.
3. Look up the SPP service specifically:
   `btDevice.GetRfcommServicesForIdAsync(RfcommServiceId.SerialPort)`.
   - If none found, fall back to `GetRfcommServicesAsync()` and use `Services[0]`.
4. Open the socket:
   ```csharp
   bluetoothSocket = new StreamSocket();
   await bluetoothSocket.ConnectAsync(
       rfcommService.ConnectionHostName,
       rfcommService.ConnectionServiceName,
       SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);
   ```
5. Wrap streams:
   `inputStream = socket.InputStream.AsStreamForRead()`,
   `outputStream = socket.OutputStream.AsStreamForWrite()`.
6. Fire `OnConnected`, then enter the read loop.
7. Connect is wrapped in a **retry loop (5 attempts)**.

### Wire protocol — GAIA framing

Commands are wrapped in a GAIA frame before sending:

```
0xFF 0x01 0x00 <payloadLen> <payload...> [checksum?]
```

- `GaiaEncode(cmd)` prepends `FF 01 00 len`.
- `GaiaDecode` validates `data[0]==0xFF && data[1]==0x01`, reads `payloadLen`
  at byte 3, computes `totalLen = payloadLen + 8 + hasChecksum`
  (`hasChecksum = data[2] & 1`).

### Read loop

- Reads into a 4096-byte accumulator and decodes complete GAIA frames.
- `bytesRead == 0` ⇒ remote closed ⇒ `Disconnect()` +
  `parent.Disconnect("Connection closed by remote host.", Disconnected)`.

## Audio channel — `RadioAudio.cs`

Separate class, separate socket, separate read loop. Uses the **same** WinRT
RFCOMM + StreamSocket stack as the control channel.

### Connect sequence (`StartAsync`)

1. `BluetoothDevice.FromBluetoothAddressAsync(btAddress)` (same MAC as control).
2. `btDevice.GetRfcommServicesAsync()` — enumerate **all** RFCOMM services.
3. Find the **Generic Audio** service by UUID:
   `00001203-0000-1000-8000-00805f9b34fb`.
   - Fallback if not found: use `Services[0]` (note: on a correctly behaving
     radio the Generic Audio record exists and is used).
4. Open a **second, independent** socket:
   ```csharp
   bluetoothSocket = new StreamSocket();
   await bluetoothSocket.ConnectAsync(
       rfcommService.ConnectionHostName,
       rfcommService.ConnectionServiceName,
       SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);
   ```
5. Wrap streams and start the audio read loop.

### No "start audio" command

The app sends **nothing** to begin receiving audio. The radio **streams audio on
its own** whenever there is audio on the FM channel. Therefore *not* receiving
audio frames most of the time is normal and expected.

### Wire protocol — 0x7E framing + SBC

Audio frames use byte-stuffed `0x7E` delimiters (different from the control
channel's GAIA framing):

- Frame markers: `0x7E ... 0x7E`.
- Escape byte `0x7D`: the following byte is XOR'd with `0x20`
  (`UnescapeBytesInPlace` / `EscapeBytes`). `0x7D` and `0x7E` in the payload are
  escaped.
- `ExtractData` scans the accumulator for a complete `0x7E…0x7E` frame, handles
  leading/duplicate `0x7E` and leading garbage.

After unescaping, `frame[0]` is the opcode:

| Opcode | Meaning             | Action                                            |
| ------ | ------------------- | ------------------------------------------------- |
| `0x00` | Received audio (odd)| Start rx run if needed; `DecodeSbcFrame(...false)` |
| `0x03` | Received audio      | Same as `0x00`                                    |
| `0x01` | Audio end           | End the current audio run                          |
| `0x02` | Audio ACK           | Ignored                                           |
| `0x09` | Transmit audio      | Start tx run if needed; `DecodeSbcFrame(...true)`  |

- Payload after `frame[0]` is an SBC frame: 32 kHz, 16 blocks, mono, Loudness
  allocation, 8 subbands, bitpool 18. Decoded to PCM (32 kHz/16-bit/mono).
- TX path encodes PCM → SBC and writes frames back over the same audio socket.

### Read loop

- Reads into a `MemoryStream` accumulator (64 KB safety cap), extracts frames,
  unescapes, switches on the opcode.
- `bytesRead == 0` ⇒ remote closed ⇒ stop.

## Lifecycle / independence

- **Control** is owned by `RadioBluetoothWin`; **audio** is owned by `RadioAudio`.
  They are constructed and torn down independently.
- Disconnecting audio (`RadioAudio.Stop()`) closes only the audio socket/streams;
  the control connection stays up.
- Disconnecting the radio tears down the control connection; audio is stopped
  separately.
- Each side disposes in order: **streams → socket → service**, then a short
  `Thread.Sleep(100)` to let the OS release the socket.

## Why this matters for the macOS port

On Windows the two channels never collide because WinRT resolves each RFCOMM
channel number from its **own** SDP service record (`ConnectionServiceName`):

- SPP (`0x1101`) record → control channel number
- Generic Audio (`0x1203`) record → a **different** audio channel number

The macOS port must mirror this: enumerate the device's SDP records, find the one
whose **service class UUID is `0x1203`**, and use **that record's** RFCOMM channel
number — rather than reusing the data channel or trusting a cached/default channel
ID. If `0x1203` resolves to the same RFCOMM channel as `0x1101`, the "audio"
socket is really a second handle to the control channel and control traffic will
leak onto it (the symptom observed on macOS).

> Diagnostic: `tools/bttest scan <MAC>` lists each SDP service with its RFCOMM
> channel number and class UUIDs, which confirms whether `0x1101` and `0x1203`
> are advertised on **different** channels.

## Confirmed SDP map (UV-PRO, from `bttest scan`)

Running `swift run bttest 38:D2:00:00:FA:F9 scan` against a real UV-PRO returns:

| Service name    | RFCOMM ch | Service-class UUID                          | Role                     |
| --------------- | --------- | ------------------------------------------- | ------------------------ |
| `(no name)`     | **4**     | `00001101`                                  | **SPP / control**        |
| `Voice Gateway` | **1**     | `00001203`                                  | **Generic Audio**        |
| `Voice Gateway` | 1         | `0000111F` + `0000111E`                     | HFP Audio Gateway        |
| `BS AOC`        | 2         | `39144315-32FA-40DB-85ED-FBFEBA2D86E6`      | vendor service           |
| `(no name)`     | none      | `00001200`                                  | PnP / Device ID          |
| `(no name)`     | none      | `00001000`                                  | SDP server               |

(`00000100` = L2CAP and `00000003` = RFCOMM are protocol UUIDs, not service classes.)

**Conclusions:**

- Control (`0x1101`) and audio (`0x1203`) are on **different RFCOMM channels**
  (4 and 1 respectively), so the two-socket model is correct on this radio.
- Generic Audio (`0x1203`) shares RFCOMM **channel 1** with the standard HFP
  "Voice Gateway" (`0x111F`); that's one endpoint advertised under two records.
- On macOS, open **control from the `0x1101` record (ch 4)** and **audio from the
  `0x1203` record (ch 1)**. Do **not** infer the channel from `getID()` or by
  reusing the data connection's device — a previous macOS bug opened control on
  channel 1 (the audio channel), which made `getHtStatus` control frames leak
  onto the audio route.

