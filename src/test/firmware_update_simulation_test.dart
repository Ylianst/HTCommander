/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

End-to-end simulation of a Benshi UV-Pro firmware update.

`SimulatedUvProRadio` re-implements the radio's side of the GAIA VM firmware
protocol so that the real [FirmwareUpdater] state machine can be driven exactly
as it would drive a physical radio. The response sequence mirrors the captured
btsnoop log in `src/tools/btsnoop_decoder/btsnoop_hci_firmware_upgrade.log`
(the firmware update from 9.0.0 to 9.0.3 on a real UV-Pro):

  Phase 1 (transfer):
    VM_CONNECT              -> reply(success)
    UPDATE_SYNC_REQ         -> reply(success), UPDATE_SYNC_CFM(update_state=0)
    UPDATE_START_REQ        -> reply(success), UPDATE_START_CFM(code=OK)
    UPDATE_START_DATA_REQ   -> reply(success), UPDATE_DATA_BYTES_REQ(n)
    UPDATE_DATA (xN)        -> reply(success), UPDATE_DATA_BYTES_REQ(n) ...
    UPDATE_IS_VALIDATION..  -> reply(success), UPDATE_TRANSFER_COMPLETE_IND
    UPDATE_TRANSFER_COMP..  -> reply(success)  [radio reboots]

  Phase 2 (confirm, on the post-reboot connection):
    VM_CONNECT              -> reply(success)
    UPDATE_SYNC_REQ         -> reply(success), UPDATE_SYNC_CFM(update_state=3)
    UPDATE_START_REQ        -> reply(success), UPDATE_START_CFM(code=OK)
    UPDATE_IN_PROGRESS_RES  -> reply(success), UPDATE_COMPLETE_IND
    VM_DISCONNECT           -> reply(success)
*/

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/firmware_updater.dart';
import 'package:htcommander/radio/firmware_vm_protocol.dart';
import 'package:htcommander/radio/gaia_protocol.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/firmware_service.dart';

/// A software model of a real UV-Pro radio's firmware-update endpoint.
///
/// It consumes the `VM_CONNECT` / `VM_CONTROL` / `VM_DISCONNECT` commands the
/// [FirmwareUpdater] sends and answers with the same VMU packets the physical
/// radio produced in the captured session, so a full update can be exercised
/// with no hardware.
class SimulatedUvProRadio implements FirmwareRadio {
  SimulatedUvProRadio({
    required this.firmwareSize,
    this.chunkSize = 4096,
    this.phase2StartCfmCode = UpdateStartCfmCode.ok,
    this.injectErrorAfterBytes,
    this.rebooted = false,
  });

  /// Total size of the firmware image the radio expects to receive.
  final int firmwareSize;

  /// Number of bytes the radio asks for in each `UPDATE_DATA_BYTES_REQ`.
  final int chunkSize;

  /// `cfm_code` the radio returns in the Phase 2 (post-reboot)
  /// `UPDATE_START_CFM`. The real UV-Pro returns [UpdateStartCfmCode.ok].
  final UpdateStartCfmCode phase2StartCfmCode;

  /// When set, the radio answers with `UPDATE_ERROR` once it has received at
  /// least this many firmware bytes (used to exercise the abort path).
  final int? injectErrorAfterBytes;

  final StreamController<RadioVmEvent> _controller =
      StreamController<RadioVmEvent>.broadcast();

  /// Every firmware byte the radio received, in order.
  final List<int> receivedFirmware = [];

  /// Human-readable log of the app->radio commands, for assertions.
  final List<String> commandLog = [];

  bool rebooted;

  bool updateCompleted = false;
  bool sawFinalChunk = false;
  bool abortRequested = false;
  Uint8List? lastMd5Tail;

  int get received => receivedFirmware.length;

  @override
  Stream<RadioVmEvent> get vmEvents => _controller.stream;

  @override
  void sendVmCommand(RadioExtendedCommand cmd, [Uint8List? body]) {
    switch (cmd) {
      case RadioExtendedCommand.vmConnect:
        commandLog.add('VM_CONNECT');
        _emitReply(cmd);
        break;
      case RadioExtendedCommand.vmDisconnect:
        commandLog.add('VM_DISCONNECT');
        _emitReply(cmd);
        break;
      case RadioExtendedCommand.vmControl:
        _handleVmControl(body ?? Uint8List(0));
        break;
      default:
        break;
    }
  }

  void _handleVmControl(Uint8List payload) {
    // VM_CONTROL payload: [type(1), n_bytes(2 BE), inner...].
    final type = VmControlType.values.firstWhere(
      (t) => t.value == (payload.isNotEmpty ? payload[0] : -1),
      orElse: () => VmControlType.updateAbortReq,
    );
    final n = RadioUtils.getShort(payload, 1);
    final inner = Uint8List.fromList(payload.sublist(3, 3 + n));

    // Every VM_CONTROL is acknowledged with a status byte before the VMU reply.
    _emitReply(RadioExtendedCommand.vmControl);

    switch (type) {
      case VmControlType.updateSyncReq:
        commandLog.add('UPDATE_SYNC_REQ');
        lastMd5Tail = inner;
        _emitVmu(VmuPacketType.updateSyncCfm, [
          rebooted ? 3 : 0, // update_state
          ...inner, // md5 tail echoed back
          0x03, // trailing byte seen in the capture
        ]);
        break;
      case VmControlType.updateStartReq:
        commandLog.add('UPDATE_START_REQ');
        final code = rebooted ? phase2StartCfmCode : UpdateStartCfmCode.ok;
        _emitVmu(VmuPacketType.updateStartCfm, [code.value, 0x06, 0x66]);
        break;
      case VmControlType.updateStartDataReq:
        commandLog.add('UPDATE_START_DATA_REQ');
        _requestNextChunk();
        break;
      case VmControlType.updateData:
        final isFinal = inner.isNotEmpty && inner[0] == 1;
        receivedFirmware.addAll(inner.sublist(1));
        if (isFinal) sawFinalChunk = true;
        if (injectErrorAfterBytes != null &&
            received >= injectErrorAfterBytes!) {
          _emitVmu(VmuPacketType.updateError, [0x00, UpdateError.batteryLow.value]);
          break;
        }
        if (received < firmwareSize) _requestNextChunk();
        break;
      case VmControlType.updateIsValidationDoneReq:
        commandLog.add('UPDATE_IS_VALIDATION_DONE_REQ');
        _emitVmu(VmuPacketType.updateTransferCompleteInd, const []);
        break;
      case VmControlType.updateTransferCompleteRes:
        commandLog.add('UPDATE_TRANSFER_COMPLETE_RES');
        rebooted = true; // the radio reboots into the trial image
        break;
      case VmControlType.updateInProgressRes:
        commandLog.add('UPDATE_IN_PROGRESS_RES');
        updateCompleted = true;
        _emitVmu(VmuPacketType.updateCompleteInd, const []);
        break;
      case VmControlType.updateAbortReq:
        commandLog.add('UPDATE_ABORT_REQ');
        abortRequested = true;
        _emitVmu(VmuPacketType.updateAbortCfm, const []);
        break;
      default:
        break;
    }
  }

  void _requestNextChunk() {
    final remaining = firmwareSize - received;
    if (remaining <= 0) return;
    final n = remaining < chunkSize ? remaining : chunkSize;
    final body = Uint8List(8);
    RadioUtils.setInt(body, 0, n); // n_bytes_requested
    RadioUtils.setInt(body, 4, 0); // n_bytes_skip
    _emitVmu(VmuPacketType.updateDataBytesReq, body);
  }

  void _emitReply(RadioExtendedCommand cmd) {
    _controller.add(RadioVmEvent.replyTo(cmd, 0));
  }

  /// Builds a full `BT_EVENT_NOTIFICATION` VMU payload and pushes it through the
  /// same parser the radio uses, so the event surfaced to the updater is
  /// byte-for-byte what a physical radio would produce.
  void _emitVmu(VmuPacketType type, List<int> body) {
    final payload = Uint8List(4 + body.length);
    payload[0] = BtEventType.vmuPacket;
    payload[1] = type.value & 0xFF;
    RadioUtils.setShort(payload, 2, body.length);
    payload.setRange(4, 4 + body.length, body);
    final vmu = VmuPacket.fromBtEventPayload(payload)!;
    _controller.add(RadioVmEvent.vmuPacket(vmu));
  }

  void dispose() => _controller.close();
}

/// A deterministic firmware image of [size] bytes.
Uint8List _fakeFirmware(int size) {
  final data = Uint8List(size);
  for (var i = 0; i < size; i++) {
    data[i] = (i * 31 + 7) & 0xFF;
  }
  return data;
}

void main() {
  group('Firmware update simulation (UV-Pro)', () {
    test('Phase 1 transfers the whole image and reboots the radio', () async {
      final bundle = FirmwareBundle(_fakeFirmware(9000));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        chunkSize: 512,
      );
      addTearDown(radio.dispose);

      final updater = FirmwareUpdater(radio, bundle);
      await updater.transfer();

      // The radio received exactly the firmware image, in order.
      expect(
        Uint8List.fromList(radio.receivedFirmware),
        equals(bundle.data),
        reason: 'the radio must receive the full image byte-for-byte',
      );
      expect(radio.sawFinalChunk, isTrue,
          reason: 'the last chunk must carry the is_final flag');
      expect(radio.rebooted, isTrue,
          reason: 'transfer must end with UPDATE_TRANSFER_COMPLETE_RES');
      // The sync must carry the last 4 bytes of the image MD5.
      expect(radio.lastMd5Tail, equals(bundle.md5Tail));
    });

    test('Phase 2 confirm finalises the update after reboot', () async {
      final bundle = FirmwareBundle(_fakeFirmware(2048));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        rebooted: true, // simulate a radio that already applied the trial image
      );
      addTearDown(radio.dispose);

      await FirmwareUpdater.confirm(radio, bundle);

      expect(radio.updateCompleted, isTrue);
      expect(radio.commandLog, contains('UPDATE_IN_PROGRESS_RES'));
      expect(radio.commandLog, contains('VM_DISCONNECT'));
    });

    test('full update: transfer then confirm on the same radio', () async {
      final bundle = FirmwareBundle(_fakeFirmware(20000));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        chunkSize: 1024,
      );
      addTearDown(radio.dispose);

      final flashProgress = <int>[];
      final updater = FirmwareUpdater(
        radio,
        bundle,
        progress: (stage, done, total) {
          if (stage == 'flash') flashProgress.add(done);
        },
      );

      await updater.transfer();
      await FirmwareUpdater.confirm(radio, bundle);

      expect(Uint8List.fromList(radio.receivedFirmware), equals(bundle.data));
      expect(radio.updateCompleted, isTrue);
      // Progress must be monotonic and reach the full image size.
      expect(flashProgress, isNotEmpty);
      expect(flashProgress.last, equals(bundle.size));
      for (var i = 1; i < flashProgress.length; i++) {
        expect(flashProgress[i], greaterThan(flashProgress[i - 1]));
      }
    });

    test('device-driven chunking works for odd/small request sizes', () async {
      final bundle = FirmwareBundle(_fakeFirmware(1234));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        chunkSize: 7, // deliberately awkward chunk size
      );
      addTearDown(radio.dispose);

      await FirmwareUpdater(radio, bundle).transfer();

      expect(Uint8List.fromList(radio.receivedFirmware), equals(bundle.data));
      expect(radio.sawFinalChunk, isTrue);
    });

    test('an UPDATE_ERROR mid-transfer aborts the update', () async {
      final bundle = FirmwareBundle(_fakeFirmware(8000));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        chunkSize: 512,
        injectErrorAfterBytes: 1000,
      );
      addTearDown(radio.dispose);

      await expectLater(
        FirmwareUpdater(radio, bundle).transfer(),
        throwsA(isA<FirmwareUpdateException>()),
      );
      expect(radio.abortRequested, isTrue,
          reason: 'the updater must send UPDATE_ABORT_REQ on error');
      expect(radio.rebooted, isFalse);
    });

    test('confirm accepts the GOTO_NEXT_STATE start code too', () async {
      final bundle = FirmwareBundle(_fakeFirmware(1024));
      final radio = SimulatedUvProRadio(
        firmwareSize: bundle.size,
        rebooted: true,
        phase2StartCfmCode: UpdateStartCfmCode.gotoNextState,
      );
      addTearDown(radio.dispose);

      await FirmwareUpdater.confirm(radio, bundle);
      expect(radio.updateCompleted, isTrue);
    });
  });
}
