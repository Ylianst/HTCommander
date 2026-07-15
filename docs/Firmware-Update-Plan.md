# Firmware Update — Implementation Plan

Adding over-the-air radio firmware update support to HTCommander (the Flutter
application), porting the capability proven in the `benlink-firmware-update`
reference library.

## Goal & scope

Deliver a complete, automatic firmware-update experience:

1. **Check** — query the Benshi cloud (gRPC) for an available update.
2. **Download + assemble** — download a shared base image plus a `BSDIFF40`
   patch and reconstruct the flashable image on-device.
3. **Flash** — stream the assembled image to the radio over the GAIA VM protocol
   on the existing RFCOMM command channel, handle the mid-process reboot, and
   commit.

**Platforms:** Bluetooth Classic only — **Windows, Android, macOS**. The feature
is hidden/disabled on BLE-only platforms (iOS, Web, Linux), where the VM protocol
is unverified.

**Delivery:** single comprehensive implementation, end to end.

## Reference implementation (source of truth)

Byte layouts, sequencing, and error codes are ported from
`reference/benlink-firmware-update/src/benlink/`:

| File | Provides |
| --- | --- |
| `firmware.py` | Layer 1 (gRPC check) + Layer 2 (download + bsdiff assemble) |
| `firmware_updater.py` | Layer 3 state machine (`transfer()` + `confirm()`) |
| `protocol/command/vm.py` | `VmControlType` / `VmuPacketType` enums + message bodies |
| `protocol/command/bt_notification.py` | `BtEventType` (`VMU_PACKET`=18) wrapper |
| `protocol/command/message.py` | Extended commands + group IDs |

## Protocol facts

- **Send** over the EXTENDED command group (10): `VM_CONNECT` (1600),
  `VM_CONTROL` (1602), `VM_DISCONNECT` (1601).
- **Receive** the radio's VMU replies as an EXTENDED `BT_EVENT_NOTIFICATION`
  (16387) → `bt_event_type = VMU_PACKET` (18) → `VmuPacket(type, len, msg)`.
- `VM_CONTROL` body layout: `vm_control_type` (8) · `n_bytes_payload` (16) · `msg`.
- `md5_tail` = **last 4 bytes** of the assembled image's MD5, sent in
  `UPDATE_SYNC_REQ`.
- Chunking is **device-driven**: the radio asks for `n` bytes (≤ 250, usually
  145) via `UPDATE_DATA_BYTES_REQ`; `n_bytes_skip` supports resume.
- Two phases separated by a **radio reboot**:

  **Phase 1 — transfer**
  `VM_CONNECT → UPDATE_SYNC_REQ/CFM → UPDATE_START_REQ/CFM(OK) →
  UPDATE_DATA_START_REQ → loop[UPDATE_DATA_BYTES_REQ → UPDATE_DATA(chunk,
  is_final)] → UPDATE_IS_VALIDATION_DONE_REQ → UPDATE_TRANSFER_COMPLETE_IND →
  UPDATE_TRANSFER_COMPLETE_RES(action=0x00)` → radio reboots into the trial
  image, BT drops.

  **Phase 2 — confirm** (fresh connection)
  `VM_CONNECT → UPDATE_SYNC_REQ/CFM(update_state=IN_PROGRESS=3) →
  UPDATE_START_REQ/CFM(GOTO_NEXT_STATE=9) → UPDATE_IN_PROGRESS_RES(0x00) →
  UPDATE_COMPLETE_IND → VM_DISCONNECT`.

- Abort: `UPDATE_ABORT_REQ → UPDATE_ABORT_CFM`. Errors via `UPDATE_ERROR`:
  `BATTERY_LOW` (33), `SYNC_IS_DIFFERENT` (129).

The update is **fail-safe by design**: the image is staged and only committed in
Phase 2, so an interrupted flash leaves the old firmware intact.

### ⚠️ Critical correction — the commit finalize is a two-stage sequence (2026-07)

This correction supersedes the `is_complete=True` behaviour ported from the
upstream `benlink` reference. Two things were wrong in *every* implementation
ported from `benlink` (including our own `firmware_updater.dart` /
`firmware_vm_protocol.dart`), which is why the radio uploaded the image but then
**either did not reboot, or rebooted back into the old firmware**. The corrected
semantics were recovered off-the-wire from the vendor app's own debug strings
(`UpdateVMFragment`) — not guesswork — and confirmed with a successful
end-to-end OTA commit on the VR-N76 / GA-5WB over Bluetooth.

1. **The `UPDATE_TRANSFER_COMPLETE_RES` action byte is inverted from its
   `is_complete` naming.** The single body byte means:
   - **`0x00` = proceed / commit-to-trial-reboot** — this is what actually makes
     the radio reboot into the new image.
   - **`0x01` = abort.**

   `benlink`'s `is_complete=True` serializes to `0x01`, which is **abort** — so
   the radio silently discarded the staged image and never rebooted. The app
   must send **`0x00`** here to trigger the trial reboot. (Our
   `VmControl.transferCompleteRes(isComplete: true)` currently emits `0x01` and
   has the same bug — see *Fixes required*.)

2. **Phase 2 is a mandatory second stage, not optional.** After the trial
   reboot the app must reconnect and run the confirm sequence to make the update
   **permanent**:
   `VM_CONNECT → UPDATE_SYNC_REQ → UPDATE_START_REQ → UPDATE_IN_PROGRESS_RES
   (action byte `0x00`) → UPDATE_COMPLETE_IND`.
   The post-reboot `UPDATE_SYNC_CFM` reports **`update_state = 3` (IN_PROGRESS)**
   — the resume point that *only appears once the Phase 1 `0x00` has actually
   applied the trial*. Seeing `update_state = 3` on reconnect is therefore the
   positive confirmation that Phase 1's commit byte worked. Without it, the
   radio has booted the old firmware and the update did not take.

#### Fixes required in our code (implement later)

- `src/lib/radio/firmware_vm_protocol.dart` — `VmControl.transferCompleteRes`
  must send `0x00` to commit (`0x01` = abort). Today it maps
  `isComplete: true → 0x01`, which aborts. Invert the byte (and rename the
  parameter to avoid the same trap, e.g. `commit`/`proceed`).
- `src/lib/radio/firmware_updater.dart` — `transfer()` calls
  `transferCompleteRes(isComplete: true)`; after the byte fix it must send the
  commit (`0x00`) value. Optionally assert the Phase 2 `UPDATE_SYNC_CFM`
  reports `update_state == 3` before sending `UPDATE_IN_PROGRESS_RES`.
- `UPDATE_IN_PROGRESS_RES` already sends a `0x00` body byte, which is correct;
  no change needed there beyond confirming it against a live commit.

## Layer 1 — Check (gRPC)

- Host `rpc.benshikj.com:800` (TLS on port **800**), method
  `/benshikj.DeviceManagement/CheckFirmwareUpdate`.
- Request (proto3) `CheckFirmwareUpdateRequest`: field 1 = `productId` (int32,
  read from the radio via `GET_DEV_INFO` / `RadioDevInfo.productId`), field 2 =
  `firmwareVersion` (int32; send `0` for the latest), field 3 = `beta` (bool),
  field 4 = `userId` (int64), field 5 = `inviteCode` (int32). Proto3 omits
  zero/false fields, so a minimal request is just `productId`.
- Response `CheckFirmwareUpdateResult`: field 1 = `firmware` (patch), field 2 =
  `base`, each a nested `FirmwareInfo { version(1), url(2), md5(3),
  releaseNotes(4), releaseDate(5) }`. Extract the two HTTPS URLs (patch + base)
  and the version.
- Dart: add the `grpc` package and use a raw-bytes
  `ClientMethod<List<int>, List<int>>`, hand-rolling the proto3 varint/string
  encode + decode (mirrors `firmware.py`).

## Layer 2 — Download + assemble

- Download the patch (`patch_base_to_vr_n76.bin`) and base zip
  (`upgrade_base_v{N}.bin.zip`) via `http` (already a dependency).
- Unzip the base `.bin` with `archive`'s `ZipDecoder`.
- The patch is `BSDIFF40`: a 32-byte header (`"BSDIFF40"` + three little-endian
  int64 lengths) followed by three bzip2 streams. Decompress with `archive`'s
  `BZip2Decoder` and run the bspatch reconstruction loop.
- Compute MD5 with `crypto`; expose `md5_tail`.
- Progress reported via a `ValueNotifier<FirmwareStatus>` (mirrors
  `sherpa_model_manager.dart`).

## Dependencies

- **New:** `grpc` (Layer 1 only).
- **Already present:** `crypto` (md5), `archive` (zip **and** bzip2), `http`,
  `file_picker`.

## Existing HTCommander pieces to reuse

- `src/lib/radio/gaia_protocol.dart` — `RadioCommandGroup{basic(2), extended(10)}`,
  `GaiaProtocol.encode/decode/buildCommand/parseResponse` (reply bit `0x8000`).
  Classic frame: `[0xFF,0x01,csum,len,grp_hi,grp_lo,cmd_hi,cmd_lo,data]`.
- `src/lib/radio/radio.dart` — `_sendCommand(group, cmd, data)`; RX pipeline
  `_onDataReceived → GaiaProtocol.decode → _handleCommand`; `_dispatch(name,
  data)` via `DataBroker`; connect lifecycle in `_onTransportConnected` /
  `_sendInitialCommands`.
- `src/lib/services/bluetooth_service.dart` — `connectToRadio`,
  `_watchTransportDisconnect`, `_handleUnexpectedDisconnect` (no auto-reconnect;
  UI re-calls `connectToRadio`).
- `src/lib/radio/radio_transport.dart` + `bluetooth_classic_transport.dart` —
  transport interface (`send` / `dataStream` / `stateStream`).
- `src/lib/radio/utils.dart` — `getByte/getShort/getInt/setShort/setInt`,
  hex helpers.
- Dialogs: `dialog_utils.dart` (`HTDialog`, `DialogStyles`), the
  `showXxxDialog` + `_XxxDialog` StatefulWidget pattern; `radio_info_dialog.dart`
  shows the current firmware version (entry-point candidate); progress pattern in
  `sherpa_model_manager.dart` + `LinearProgressIndicator`.

## Files to create

- `src/lib/radio/firmware_vm_protocol.dart` — port of `vm.py` (enums, message
  builders, VMU parser).
- `src/lib/utils/bspatch.dart` — pure-Dart `BSDIFF40` patcher using
  `BZip2Decoder`.
- `src/lib/services/firmware_service.dart` — Layer 1 gRPC check + Layer 2
  download/assemble, with `ValueNotifier` progress.
- `src/lib/radio/firmware_updater.dart` — Layer 3 state machine
  (`transfer()` + `confirm()`), reconnect orchestration.
- `src/lib/dialogs/firmware_update_dialog.dart` — UI (progress, warnings,
  battery pre-check).

## Files to modify

- `src/pubspec.yaml` — add `grpc`.
- `src/lib/radio/gaia_protocol.dart` — extended-command constants
  (`VM_CONNECT`=1600, `VM_DISCONNECT`=1601, `VM_CONTROL`=1602,
  `REGISTER_BT_NOTIFICATION`=16385, `BT_EVENT_NOTIFICATION`=16387); ensure
  `buildCommand` supports the extended group.
- `src/lib/radio/radio.dart` — send VM extended commands; parse incoming
  extended `BT_EVENT_NOTIFICATION` (16387) → VMU packet → expose a
  stream/callback for the updater; gate to Classic transport.
- `src/lib/services/bluetooth_service.dart` — reconnect-same-MAC helper for
  Phase 2.
- `src/lib/dialogs/radio_info_dialog.dart` (or the settings menu / `main.dart`) —
  add the "Firmware Update…" entry with a platform gate.

## Reboot / reconnect orchestration

After `UPDATE_TRANSFER_COMPLETE_RES` the radio reboots and BT drops. The dialog
keeps running, calls `BluetoothService.connectToRadio` for the same device MAC,
polls until connected (~15–30 s, with timeout), then runs
`FirmwareUpdater.confirm` on the fresh connection.

## Safety (hard-to-reverse operation)

- Pre-flight: require a Classic transport, check battery level, verify the model
  matches, and show a strong warning ("do not power off / keep in range").
- Handle `UPDATE_ERROR` (`BATTERY_LOW`, `SYNC_IS_DIFFERENT`); auto-send
  `UPDATE_ABORT_REQ` on any exception.
- Rely on the staged-then-commit design so a failed flash keeps the old firmware.

## Verification

1. **Unit:** bspatch a known base + patch → assembled MD5 matches (offline).
2. **Unit:** proto encode/decode — build a `CheckFirmwareUpdate` request; parse a
   sample `CheckFirmwareUpdateResult` → patch/base URLs + version.
3. **Unit:** `VM_CONTROL` / VMU packet build + parse roundtrip against the
   `vm.py` byte layouts.
4. **Manual dry-run:** gRPC check with `productId` (and `firmwareVersion=0`)
   returns URLs; download + assemble a real bundle; verify size/MD5.
5. **Manual live flash** on a spare radio: progress → reboot → confirm → new
   version shows in radio info.
6. `flutter analyze` clean; existing test suite passes.

## Open considerations

- **Notification registration** — benlink's updater never sends
  `REGISTER_BT_NOTIFICATION`; `VM_CONNECT` alone may enable VMU events. Implement
  without it first; add only if device testing shows no VMU packets arrive.
- **VM over BLE** — assumed RFCOMM-only and unverified over BLE GATT; gated out.
- **Local firmware override** — optionally allow a user-selected local
  `.firmware` file to bypass Layers 1–2 (useful for testing / offline updates).
