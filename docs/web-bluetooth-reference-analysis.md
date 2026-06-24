# Web Bluetooth Reference Analysis

This document explains why `reference/HTCommanderWeb/index.html` works against the radio on Web Bluetooth, and what must match in Flutter web for the same radio-control path to succeed.

## 1. What The Reference Page Does Correctly

The reference page uses a very specific and consistent BLE contract:

1. Device chooser is constrained to the target model family.
   - `navigator.bluetooth.requestDevice({ filters: [{ name: 'UV-PRO' }], optionalServices: [RADIO_SERVICE_UUID] })`

2. It binds to a fixed service/characteristic tuple.
   - Service: `00001100-d102-11e1-9b23-00025b00a5a5`
   - Write characteristic: `00001101-d102-11e1-9b23-00025b00a5a5`
   - Indicate/notify characteristic: `00001102-d102-11e1-9b23-00025b00a5a5`

3. It enables notifications on the indicate characteristic before command flow.
   - `startNotifications()` and `characteristicvaluechanged` handler are both set.

4. It sends commands in direct radio format (not GAIA-wrapped transport frames).
   - `SendCommand(group, cmd, data)` writes bytes shaped like:
     - `[0, group, 0, cmd, ...payload]`
   - For null payload commands it still sends one trailing byte (`0`), because JS `Uint8Array([..., null])` becomes `0`.

5. It parses incoming notification bytes as radio command responses directly.
   - Interprets `receivedData` as:
     - `group = (b0 << 8) + b1`
     - `cmd = ((b2 & 0x7F) << 8) + b3`
     - `status = b4`
     - payload follows

6. Initial handshake command set is minimal and known-good.
   - `GET_DEV_INFO(3)`
   - `READ_SETTINGS(0)`
   - `GET_HT_STATUS(0)`

## 2. Why Earlier Flutter Web Attempts Failed

The Flutter web path had behavior that could diverge from this known-good contract:

1. Command envelope mismatch risk.
   - Flutter primarily sent GAIA-framed packets (`FF 01 ...`) while the reference path succeeds with direct radio command bytes.

2. Characteristic ambiguity.
   - Flutter had web heuristics to prefer/mirror writes across alternate writable characteristics; the reference path uses `1101` as the single command write endpoint.

3. Broader chooser/scan behavior.
   - The reference chooser is tightly filtered (`UV-PRO` + required service) while the Flutter path could admit broader devices and then rely on runtime probing.

4. More aggressive adaptive protocol probing.
   - Multiple compact variants and retries can obscure root cause and keep the app in a connected-but-not-operational state if command shape is wrong.

## 3. Flutter Web Parity Rules

For this radio profile on web, parity with the reference page means:

1. Filter web scan/chooser by `UV-PRO` with service `00001100...` in optional services.
2. Prefer and keep TX on `00001101...` and RX notifications on `00001102...`.
3. Send direct command bytes for basic commands:
   - `[0, 2, 0, cmd, payload...]`
   - include trailing `0` byte for commands without payload.
4. Accept direct response notifications as already-decoded command frames.
5. Use the same minimal init command batch as reference.

## 4. Implemented Alignment In This Repository

The Flutter web stack was adjusted to follow the reference behavior:

1. Web scan now includes a `UV-PRO` keyword filter and keeps required optional services.
2. `UV-PRO` support was explicitly included in radio-compatible name patterns.
3. BLE transport now recognizes the reference profile binding and avoids web-only TX mirroring for that profile.
4. Radio web TX now defaults to direct command framing for basic commands, with a trailing `0` when no payload is provided.
5. Radio web RX now handles direct response packets (`group/cmd/status/payload`) before GAIA decode.
6. Web init command batch now mirrors the reference sequence.

## 5. Expected Outcome

With these parity rules, Flutter web should behave like the known-good reference page for radios exposing the same BLE profile and firmware behavior. If a specific firmware still rejects commands, the next likely causes are:

1. device-side auth/lock state,
2. firmware variant using a different command subset,
3. browser BLE stack differences for the selected adapter.
