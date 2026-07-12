/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

import '../services/firmware_service.dart';
import 'firmware_vm_protocol.dart';
import 'gaia_protocol.dart';
import 'radio.dart';

/// Thrown on any firmware-update protocol error or timeout.
class FirmwareUpdateException implements Exception {
  final String message;
  const FirmwareUpdateException(this.message);
  @override
  String toString() => 'FirmwareUpdateException: $message';
}

/// GAIA VM firmware-delivery state machine (Layer 3).
///
/// Dart port of the `benlink` reference `firmware_updater.py`. The update is
/// split into two phases separated by a radio reboot:
///
/// **Phase 1 — [transfer]:** `VM_CONNECT → UPDATE_SYNC_REQ → UPDATE_START_REQ →
/// UPDATE_DATA_START_REQ → [device-driven chunk loop] →
/// UPDATE_IS_VALIDATION_DONE_REQ → UPDATE_TRANSFER_COMPLETE_RES`. The radio then
/// reboots and the Bluetooth connection drops.
///
/// **Phase 2 — [confirm]** (after reconnect): `VM_CONNECT → UPDATE_SYNC_REQ →
/// UPDATE_START_REQ (GOTO_NEXT_STATE) → UPDATE_IN_PROGRESS_RES →
/// UPDATE_COMPLETE_IND → VM_DISCONNECT`.
class FirmwareUpdater {
  final Radio radio;
  final FirmwareBundle bundle;
  final FirmwareProgress? progress;

  FirmwareUpdater(this.radio, this.bundle, {this.progress});

  // Timeouts (mirroring the reference implementation).
  static const Duration _vmReplyTimeout = Duration(seconds: 15);
  static const Duration _vmuTimeout = Duration(seconds: 30);
  static const Duration _chunkTimeout = Duration(seconds: 60);
  static const Duration _validationTimeout = Duration(seconds: 120);
  static const Duration _completeTimeout = Duration(seconds: 120);

  /// Phase 1: transfer the firmware image to the radio.
  ///
  /// Returns once the radio has acknowledged the complete transfer
  /// (`UPDATE_TRANSFER_COMPLETE_RES` sent). Shortly afterwards the radio reboots
  /// and the Bluetooth connection drops. The caller should then disconnect,
  /// wait for the radio to reboot, reconnect, and call [confirm].
  Future<void> transfer() async {
    final fw = bundle.data;
    final total = fw.length;
    final inbox = _VmEventInbox(radio.vmEvents);

    try {
      // Phase 1a: handshake.
      await _vmConnect(inbox);
      await _sync(inbox);

      final cfmCode = await _start(inbox);
      if (cfmCode == UpdateStartCfmCode.gotoNextState) {
        throw const FirmwareUpdateException(
          'UPDATE_START_CFM returned GOTO_NEXT_STATE before transfer. The radio '
          'may already be partway through an update. Power-cycle the radio and '
          'retry, or call confirm() if a previous transfer completed.',
        );
      }

      // Phase 1b: data transfer (device-driven chunking).
      radio.sendVmCommand(RadioExtendedCommand.vmControl, VmControl.dataStartReq());

      int offset = 0;
      while (offset < total) {
        final req = await _waitVmu(
          inbox,
          VmuPacketType.updateDataBytesReq,
          _chunkTimeout,
        );
        final n = req.bytesRequested;
        offset += req.bytesSkip; // non-zero only on resume

        final end = (offset + n) > total ? total : (offset + n);
        if (offset >= total || end <= offset) {
          throw FirmwareUpdateException(
            'Device requested $n bytes at offset $offset but firmware is only '
            '$total bytes',
          );
        }
        final chunk = Uint8List.sublistView(fw, offset, end);
        final isLast = end >= total;

        radio.sendVmCommand(
          RadioExtendedCommand.vmControl,
          VmControl.data(chunk, isFinalFragment: isLast),
        );
        offset = end;
        progress?.call('flash', offset, total);
      }

      // Phase 1c: validation & transfer-complete.
      radio.sendVmCommand(
        RadioExtendedCommand.vmControl,
        VmControl.isValidationDoneReq(),
      );
      await _waitVmu(
        inbox,
        VmuPacketType.updateTransferCompleteInd,
        _validationTimeout,
      );

      // Tell the radio the transfer is complete — it will now reboot.
      radio.sendVmCommand(
        RadioExtendedCommand.vmControl,
        VmControl.transferCompleteRes(isComplete: true),
      );
    } catch (_) {
      _abort();
      rethrow;
    } finally {
      inbox.dispose();
    }
  }

  /// Phase 2: confirm the completed update after the radio reboots.
  ///
  /// Call on a radio that has been reconnected post-reboot. The radio expects
  /// `UPDATE_START_CFM` to return `GOTO_NEXT_STATE`, indicating it is ready to
  /// finalise the update.
  static Future<void> confirm(Radio radio, FirmwareBundle bundle) async {
    final updater = FirmwareUpdater(radio, bundle);
    final inbox = _VmEventInbox(radio.vmEvents);

    try {
      await updater._vmConnect(inbox);
      await updater._sync(inbox);

      final cfmCode = await updater._start(inbox);
      if (cfmCode != UpdateStartCfmCode.gotoNextState) {
        throw FirmwareUpdateException(
          'Expected GOTO_NEXT_STATE in post-reboot UPDATE_START_CFM, got '
          '${cfmCode.name}. The radio may not have rebooted yet.',
        );
      }

      // Signal that the update is in progress (finalising).
      radio.sendVmCommand(
        RadioExtendedCommand.vmControl,
        VmControl.inProgressRes(),
      );

      // Wait for the radio to confirm the update is fully applied.
      await updater._waitVmu(
        inbox,
        VmuPacketType.updateCompleteInd,
        _completeTimeout,
      );

      radio.sendVmCommand(RadioExtendedCommand.vmDisconnect);
    } finally {
      inbox.dispose();
    }
  }

  // ── Protocol steps ────────────────────────────────────────────────────────

  Future<void> _vmConnect(_VmEventInbox inbox) async {
    final future = inbox.take(
      (e) => e.reply == RadioExtendedCommand.vmConnect,
      _vmReplyTimeout,
      'VM_CONNECT reply',
    );
    radio.sendVmCommand(RadioExtendedCommand.vmConnect);
    final event = await future;
    if (event.replyStatus != 0) {
      throw FirmwareUpdateException(
        'VM_CONNECT rejected (status ${event.replyStatus})',
      );
    }
  }

  Future<void> _sync(_VmEventInbox inbox) async {
    final future = _waitVmuFuture(inbox, VmuPacketType.updateSyncCfm, _vmuTimeout);
    radio.sendVmCommand(
      RadioExtendedCommand.vmControl,
      VmControl.syncReq(bundle.md5Tail),
    );
    await future;
  }

  Future<UpdateStartCfmCode> _start(_VmEventInbox inbox) async {
    final future = _waitVmuFuture(inbox, VmuPacketType.updateStartCfm, _vmuTimeout);
    radio.sendVmCommand(RadioExtendedCommand.vmControl, VmControl.startReq());
    final vmu = await future;
    return vmu.startCfmCode;
  }

  void _abort() {
    try {
      radio.sendVmCommand(RadioExtendedCommand.vmControl, VmControl.abortReq());
    } catch (_) {
      // best-effort
    }
  }

  /// Wait for a VMU packet of [type], sending nothing. Fails if an
  /// `UPDATE_ERROR` arrives first.
  Future<VmuPacket> _waitVmu(
    _VmEventInbox inbox,
    VmuPacketType type,
    Duration timeout,
  ) {
    return _waitVmuFuture(inbox, type, timeout);
  }

  Future<VmuPacket> _waitVmuFuture(
    _VmEventInbox inbox,
    VmuPacketType type,
    Duration timeout,
  ) async {
    final event = await inbox.take(
      (e) =>
          e.vmu != null &&
          (e.vmu!.type == type || e.vmu!.type == VmuPacketType.updateError),
      timeout,
      'VMU ${type.name}',
    );
    final vmu = event.vmu!;
    if (vmu.type == VmuPacketType.updateError && type != VmuPacketType.updateError) {
      throw FirmwareUpdateException(
        'Radio reported UPDATE_ERROR: ${vmu.error.name}',
      );
    }
    return vmu;
  }
}

/// Buffers [RadioVmEvent]s from the radio so that none are lost between the
/// discrete request/response steps of the update state machine.
class _VmEventInbox {
  final List<RadioVmEvent> _buffer = [];
  final List<_Waiter> _waiters = [];
  late final StreamSubscription<RadioVmEvent> _sub;

  _VmEventInbox(Stream<RadioVmEvent> stream) {
    _sub = stream.listen(_onEvent);
  }

  void _onEvent(RadioVmEvent event) {
    for (var i = 0; i < _waiters.length; i++) {
      if (_waiters[i].matches(event)) {
        final waiter = _waiters.removeAt(i);
        waiter.completer.complete(event);
        return;
      }
    }
    _buffer.add(event);
  }

  /// Returns the next event satisfying [match], either from the buffer or by
  /// waiting up to [timeout].
  Future<RadioVmEvent> take(
    bool Function(RadioVmEvent) match,
    Duration timeout,
    String description,
  ) {
    for (var i = 0; i < _buffer.length; i++) {
      if (match(_buffer[i])) {
        return Future.value(_buffer.removeAt(i));
      }
    }
    final completer = Completer<RadioVmEvent>();
    final waiter = _Waiter(match, completer);
    _waiters.add(waiter);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw FirmwareUpdateException(
          'Timed out (${timeout.inSeconds}s) waiting for $description',
        );
      },
    );
  }

  void dispose() {
    _sub.cancel();
    for (final waiter in _waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const FirmwareUpdateException('Update cancelled'),
        );
      }
    }
    _waiters.clear();
    _buffer.clear();
  }
}

class _Waiter {
  final bool Function(RadioVmEvent) matches;
  final Completer<RadioVmEvent> completer;
  _Waiter(this.matches, this.completer);
}
