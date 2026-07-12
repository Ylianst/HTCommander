/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'gaia_protocol.dart';
import 'utils.dart';

/// GAIA VM firmware-update protocol messages.
///
/// This is a Dart port of the message layouts in the `benlink` reference
/// implementation (`protocol/command/vm.py` and `bt_notification.py`). It
/// defines the control messages the app sends inside a `VM_CONTROL` extended
/// command, and parses the VMU replies the radio sends back inside
/// `BT_EVENT_NOTIFICATION` extended events.
///
/// All multi-byte integers are big-endian, matching the GAIA framing used by
/// the rest of the radio protocol.

/// Control message types sent from the app to the radio inside a `VM_CONTROL`
/// command.
enum VmControlType {
  updateStartReq(1),
  updateData(4),
  updateAbortReq(7),
  updateTransferCompleteRes(12),
  updateInProgressRes(14),
  updateCommitCfm(16),
  updateSyncReq(19),
  updateStartDataReq(21),
  updateIsValidationDoneReq(22),
  updateEraseSqifCfm(30),
  updateAbortWithCode1Req(31),
  updateAbortWithCode2Req(32);

  final int value;
  const VmControlType(this.value);
}

/// Reply/notification message types sent from the radio to the app inside a
/// `BT_EVENT_NOTIFICATION` VMU packet.
enum VmuPacketType {
  updateStartCfm(2),
  updateDataBytesReq(3),
  updateAbortCfm(8),
  updateTransferCompleteInd(11),
  updateCommitRes(15),
  updateError(17),
  updateCompleteInd(18),
  updateSyncCfm(20),
  updateIsValidationDoneCfm(23),
  updateCommitEraseSqifRes(29),
  unknown(-1);

  final int value;
  const VmuPacketType(this.value);

  static VmuPacketType fromValue(int value) {
    return VmuPacketType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => VmuPacketType.unknown,
    );
  }
}

/// `bt_event_type` values inside a `BT_EVENT_NOTIFICATION`. Only [vmuPacket] is
/// used by the firmware-update flow.
class BtEventType {
  static const int vmuPacket = 18;
}

/// `cfm_code` returned in `UPDATE_START_CFM`.
enum UpdateStartCfmCode {
  ok(0),
  gotoNextState(9),
  unknown(-1);

  final int value;
  const UpdateStartCfmCode(this.value);

  static UpdateStartCfmCode fromValue(int value) {
    return UpdateStartCfmCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UpdateStartCfmCode.unknown,
    );
  }
}

/// Error codes reported in `UPDATE_ERROR`.
enum UpdateError {
  unknown(0),
  batteryLow(33),
  syncIsDifferent(129);

  final int value;
  const UpdateError(this.value);

  static UpdateError fromValue(int value) {
    return UpdateError.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UpdateError.unknown,
    );
  }
}

/// Builders for the payload of a `VM_CONTROL` extended command.
///
/// The `VM_CONTROL` command payload has the form:
/// `[vm_control_type(1), n_bytes_payload(2 big-endian), inner...]`.
class VmControl {
  /// Build a `VM_CONTROL` payload for [type] carrying [inner] as its body.
  static Uint8List _build(VmControlType type, Uint8List inner) {
    final out = Uint8List(3 + inner.length);
    out[0] = type.value & 0xFF;
    RadioUtils.setShort(out, 1, inner.length);
    out.setRange(3, 3 + inner.length, inner);
    return out;
  }

  /// UPDATE_SYNC_REQ — carries the last 4 bytes of the firmware MD5.
  static Uint8List syncReq(Uint8List md5Tail) {
    assert(md5Tail.length == 4);
    return _build(VmControlType.updateSyncReq, Uint8List.fromList(md5Tail));
  }

  /// UPDATE_START_REQ — no body.
  static Uint8List startReq() =>
      _build(VmControlType.updateStartReq, Uint8List(0));

  /// UPDATE_START_DATA_REQ — no body.
  static Uint8List dataStartReq() =>
      _build(VmControlType.updateStartDataReq, Uint8List(0));

  /// UPDATE_DATA — one firmware chunk.
  static Uint8List data(Uint8List chunk, {required bool isFinalFragment}) {
    final inner = Uint8List(1 + chunk.length);
    inner[0] = isFinalFragment ? 1 : 0;
    inner.setRange(1, 1 + chunk.length, chunk);
    return _build(VmControlType.updateData, inner);
  }

  /// UPDATE_IS_VALIDATION_DONE_REQ — no body.
  static Uint8List isValidationDoneReq() =>
      _build(VmControlType.updateIsValidationDoneReq, Uint8List(0));

  /// UPDATE_TRANSFER_COMPLETE_RES — one bool byte.
  static Uint8List transferCompleteRes({required bool isComplete}) => _build(
    VmControlType.updateTransferCompleteRes,
    Uint8List.fromList([isComplete ? 1 : 0]),
  );

  /// UPDATE_IN_PROGRESS_RES — one padding byte (0).
  static Uint8List inProgressRes() => _build(
    VmControlType.updateInProgressRes,
    Uint8List.fromList([0]),
  );

  /// UPDATE_ABORT_REQ — no body.
  static Uint8List abortReq() =>
      _build(VmControlType.updateAbortReq, Uint8List(0));
}

/// A parsed VMU packet (the radio's reply, carried inside a
/// `BT_EVENT_NOTIFICATION`).
class VmuPacket {
  final VmuPacketType type;

  /// Raw body bytes (after the 3-byte `type` + `n_bytes_payload` header).
  final Uint8List body;

  const VmuPacket(this.type, this.body);

  /// Parse a `BT_EVENT_NOTIFICATION` payload (the bytes after the
  /// `[group, cmd]` header, i.e. starting at `bt_event_type`).
  ///
  /// Returns `null` if the event is not a VMU packet or is malformed.
  static VmuPacket? fromBtEventPayload(Uint8List payload) {
    // payload = [bt_event_type(1), vmu_packet_type(1), n_bytes_payload(2), body...]
    if (payload.length < 4) return null;
    if (payload[0] != BtEventType.vmuPacket) return null;

    final type = VmuPacketType.fromValue(payload[1]);
    final n = RadioUtils.getShort(payload, 2);
    final start = 4;
    final end = start + n;
    if (end > payload.length) {
      // Length field disagrees with the buffer; fall back to whatever remains.
      return VmuPacket(type, Uint8List.fromList(payload.sublist(start)));
    }
    return VmuPacket(type, Uint8List.fromList(payload.sublist(start, end)));
  }

  /// UPDATE_START_CFM: `cfm_code(1), unknown(2)`.
  UpdateStartCfmCode get startCfmCode {
    if (body.isEmpty) return UpdateStartCfmCode.unknown;
    return UpdateStartCfmCode.fromValue(body[0]);
  }

  /// UPDATE_DATA_BYTES_REQ: `n_bytes_requested(4), n_bytes_skip(4)`.
  int get bytesRequested => RadioUtils.getInt(body, 0);
  int get bytesSkip => RadioUtils.getInt(body, 4);

  /// UPDATE_SYNC_CFM: `update_state(1), md5sum_tail(4), unknown(1)`.
  int get syncUpdateState => body.isNotEmpty ? body[0] : 0;

  /// UPDATE_ERROR: `update_error(2)`.
  UpdateError get error => UpdateError.fromValue(RadioUtils.getShort(body, 0));

  @override
  String toString() =>
      'VmuPacket(${type.name}, ${RadioUtils.bytesToHex(body)})';
}

/// An event surfaced by [Radio.vmEvents] during a firmware update: either a VMU
/// packet from the radio, or an acknowledgement (`is_reply`) to a VM extended
/// command the app sent.
class RadioVmEvent {
  /// Non-null for `BT_EVENT_NOTIFICATION` VMU packets from the radio.
  final VmuPacket? vmu;

  /// Non-null for replies to VM extended commands
  /// (`VM_CONNECT` / `VM_CONTROL` / `VM_DISCONNECT`).
  final RadioExtendedCommand? reply;

  /// Reply status byte (0 = success); meaningful only when [reply] is set.
  final int replyStatus;

  const RadioVmEvent.vmuPacket(VmuPacket packet)
    : vmu = packet,
      reply = null,
      replyStatus = 0;

  const RadioVmEvent.replyTo(RadioExtendedCommand command, this.replyStatus)
    : reply = command,
      vmu = null;

  @override
  String toString() => vmu != null
      ? 'RadioVmEvent(vmu: $vmu)'
      : 'RadioVmEvent(reply: ${reply?.name}, status: $replyStatus)';
}

