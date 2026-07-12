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
  UPDATE_TRANSFER_COMPLETE_RES(true)` → radio reboots, BT drops.

  **Phase 2 — confirm** (fresh connection)
  `VM_CONNECT → UPDATE_SYNC_REQ/CFM → UPDATE_START_REQ/CFM(GOTO_NEXT_STATE=9) →
  UPDATE_IN_PROGRESS_RES → UPDATE_COMPLETE_IND → VM_DISCONNECT`.

- Abort: `UPDATE_ABORT_REQ → UPDATE_ABORT_CFM`. Errors via `UPDATE_ERROR`:
  `BATTERY_LOW` (33), `SYNC_IS_DIFFERENT` (129).

The update is **fail-safe by design**: the image is staged and only committed in
Phase 2, so an interrupted flash leaves the old firmware intact.

## Layer 1 — Check (gRPC)

- Host `rpc.benshikj.com:800` (TLS on port **800**), method
  `/benshikj.APP/CheckUpdate`.
- Request (proto3): field 1 = `did` (serial), field 2 = `fwVersion`,
  field 3 = `model` (`VR_N7600`).
- Response: field 1 `bool haveUpdate`; extract the two HTTPS URLs (patch + base).
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
2. **Unit:** proto encode/decode — build a `CheckUpdate` request; parse a sample
   response → URLs + `haveUpdate`.
3. **Unit:** `VM_CONTROL` / VMU packet build + parse roundtrip against the
   `vm.py` byte layouts.
4. **Manual dry-run:** gRPC check with `fw_version="V0.0.0"` returns URLs;
   download + assemble a real bundle; verify size/MD5.
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
