/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Unit tests for the radio firmware-update building blocks:
  - GAIA VM control message builders and VMU packet parsing
  - BSDIFF40 binary patch application (bspatch)
  - the hand-rolled proto3 encode/decode used by the cloud update check
*/

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/firmware_vm_protocol.dart';
import 'package:htcommander/services/firmware_service.dart';
import 'package:htcommander/utils/bspatch.dart';

/// Encode a bsdiff "offtout" 64-bit sign-magnitude integer (8 bytes).
Uint8List _offtout(int value) {
  final out = Uint8List(8);
  int x = value < 0 ? -value : value;
  for (int i = 0; i < 8; i++) {
    out[i] = x & 0xFF;
    x >>= 8;
  }
  if (value < 0) out[7] |= 0x80;
  return out;
}

/// Build a minimal valid BSDIFF40 patch from raw control/diff/extra blocks.
Uint8List _buildBsdiff40(
  List<int> control,
  List<int> diff,
  List<int> extra,
  int newSize,
) {
  final cCtrl = BZip2Encoder().encodeBytes(control);
  final cDiff = BZip2Encoder().encodeBytes(diff);
  final cExtra = BZip2Encoder().encodeBytes(extra);

  final header = BytesBuilder();
  header.add('BSDIFF40'.codeUnits);
  header.add(_offtout(cCtrl.length));
  header.add(_offtout(cDiff.length));
  header.add(_offtout(newSize));

  return Uint8List.fromList([...header.toBytes(), ...cCtrl, ...cDiff, ...cExtra]);
}

void main() {
  group('VmControl builders', () {
    test('syncReq wraps the 4-byte md5 tail', () {
      final tail = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final msg = VmControl.syncReq(tail);
      // [type(19), len_hi, len_lo, tail...]
      expect(msg[0], VmControlType.updateSyncReq.value);
      expect(msg[1], 0); // length high byte
      expect(msg[2], 4); // length low byte
      expect(msg.sublist(3), tail);
    });

    test('data sets final-fragment flag and payload length', () {
      final chunk = Uint8List.fromList([1, 2, 3]);
      final msg = VmControl.data(chunk, isFinalFragment: true);
      expect(msg[0], VmControlType.updateData.value);
      expect(msg[1], 0);
      expect(msg[2], 4); // 1 flag byte + 3 data bytes
      expect(msg[3], 1); // is_final_fragment = true
      expect(msg.sublist(4), chunk);
    });

    test('transferCompleteRes carries a bool byte', () {
      final msg = VmControl.transferCompleteRes(isComplete: true);
      expect(msg[0], VmControlType.updateTransferCompleteRes.value);
      expect(msg[2], 1);
      expect(msg[3], 1);
    });

    test('empty-body messages have zero payload length', () {
      for (final msg in [
        VmControl.startReq(),
        VmControl.dataStartReq(),
        VmControl.isValidationDoneReq(),
        VmControl.abortReq(),
      ]) {
        expect(msg.length, 3);
        expect(msg[1], 0);
        expect(msg[2], 0);
      }
    });
  });

  group('VmuPacket parsing', () {
    test('parses UPDATE_START_CFM cfm_code', () {
      // [bt_event_type=18, vmu_type=2, len_hi, len_lo, cfm_code, unk, unk]
      final payload = Uint8List.fromList([
        BtEventType.vmuPacket,
        VmuPacketType.updateStartCfm.value,
        0,
        3,
        UpdateStartCfmCode.gotoNextState.value,
        0,
        0,
      ]);
      final vmu = VmuPacket.fromBtEventPayload(payload)!;
      expect(vmu.type, VmuPacketType.updateStartCfm);
      expect(vmu.startCfmCode, UpdateStartCfmCode.gotoNextState);
    });

    test('parses UPDATE_DATA_BYTES_REQ requested/skip', () {
      final body = Uint8List(8);
      body[0] = 0x00;
      body[1] = 0x00;
      body[2] = 0x00;
      body[3] = 145; // n_bytes_requested = 145
      body[7] = 0; // n_bytes_skip = 0
      final payload = Uint8List.fromList([
        BtEventType.vmuPacket,
        VmuPacketType.updateDataBytesReq.value,
        0,
        8,
        ...body,
      ]);
      final vmu = VmuPacket.fromBtEventPayload(payload)!;
      expect(vmu.type, VmuPacketType.updateDataBytesReq);
      expect(vmu.bytesRequested, 145);
      expect(vmu.bytesSkip, 0);
    });

    test('parses UPDATE_ERROR code', () {
      final payload = Uint8List.fromList([
        BtEventType.vmuPacket,
        VmuPacketType.updateError.value,
        0,
        2,
        0x00,
        33, // BATTERY_LOW
      ]);
      final vmu = VmuPacket.fromBtEventPayload(payload)!;
      expect(vmu.type, VmuPacketType.updateError);
      expect(vmu.error, UpdateError.batteryLow);
    });

    test('rejects non-VMU BT events', () {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      expect(VmuPacket.fromBtEventPayload(payload), isNull);
    });
  });

  group('BsPatch', () {
    test('detects BSDIFF40 magic', () {
      expect(BsPatch.isBsdiff40(Uint8List.fromList('BSDIFF40'.codeUnits)), isTrue);
      expect(BsPatch.isBsdiff40(Uint8List.fromList('NOPE0000'.codeUnits)), isFalse);
    });

    test('applies a patch with add + copy blocks', () {
      final base = Uint8List.fromList([10, 20, 30, 40]);
      // add 2 bytes (diff + base), then copy 2 bytes from extra, seek 0.
      final control = <int>[
        ..._offtout(2), // addLen
        ..._offtout(2), // copyLen
        ..._offtout(0), // seek
      ];
      final diff = [1, 2]; // out[0]=1+10=11, out[1]=2+20=22
      final extra = [99, 98];
      final patch = _buildBsdiff40(control, diff, extra, 4);

      final result = BsPatch.apply(base, patch);
      expect(result, Uint8List.fromList([11, 22, 99, 98]));
    });

    test('applies a copy-only patch', () {
      final base = Uint8List.fromList([0, 0, 0]);
      final target = [200, 100, 50, 25];
      final control = <int>[
        ..._offtout(0), // addLen
        ..._offtout(target.length), // copyLen
        ..._offtout(0), // seek
      ];
      final patch = _buildBsdiff40(control, [0], target, target.length);

      final result = BsPatch.apply(base, patch);
      expect(result, Uint8List.fromList(target));
    });

    test('throws on bad magic', () {
      expect(
        () => BsPatch.apply(Uint8List(4), Uint8List.fromList('XXXX'.codeUnits)),
        throwsFormatException,
      );
    });
  });

  group('Proto3 encode/decode', () {
    test('encodes CheckFirmwareUpdateRequest with productId only', () {
      final bytes = FirmwareService.debugEncodeCheckRequest(259);
      // field 1 (varint) productId = 259 -> tag 0x08, varint 259 = 0x83 0x02.
      expect(bytes, Uint8List.fromList([0x08, 0x83, 0x02]));
    });

    test('omits firmwareVersion when zero', () {
      final bytes = FirmwareService.debugEncodeCheckRequest(
        1,
        firmwareVersion: 0,
      );
      expect(bytes, Uint8List.fromList([0x08, 0x01]));
    });

    test('encodes firmwareVersion and beta when set', () {
      final bytes = FirmwareService.debugEncodeCheckRequest(
        1,
        firmwareVersion: 5,
        beta: true,
      );
      // productId=1, firmwareVersion=5 (tag 0x10), beta=true (tag 0x18).
      expect(bytes, Uint8List.fromList([0x08, 0x01, 0x10, 0x05, 0x18, 0x01]));
    });

    test('decodes CheckFirmwareUpdateResult with nested FirmwareInfo', () {
      const patchUrl =
          'https://pubdatas.oss-cn-shenzhen.aliyuncs.com/firmware/v147/patch_base_to_vr_n76.bin';
      const baseUrl =
          'https://pubdatas.oss-cn-shenzhen.aliyuncs.com/upgrade_base_v1.bin.zip';

      final firmwareMsg = Uint8List.fromList([
        0x08, 0x93, 0x01, // field 1 (varint) version = 147
        ...FirmwareService.debugEncodeStringField(2, patchUrl), // url
        ...FirmwareService.debugEncodeStringField(3, 'abc123'), // md5
      ]);
      final baseMsg = Uint8List.fromList([
        0x08, 0x01, // version = 1
        ...FirmwareService.debugEncodeStringField(2, baseUrl), // url
      ]);
      final response = Uint8List.fromList([
        ...FirmwareService.debugEncodeMessageField(1, firmwareMsg), // firmware
        ...FirmwareService.debugEncodeMessageField(2, baseMsg), // base
      ]);

      final info = FirmwareService.debugDecodeResult(response);
      expect(info, isNotNull);
      expect(info!.version, 147);
      expect(info.semanticVersion, '0.9.3');
      expect(info.displayVersion, 'v0.9.3');
      expect(info.patchUrl, patchUrl);
      expect(info.baseUrl, baseUrl);
      expect(info.firmware.md5, 'abc123');
    });

    test('returns null when firmware or base is missing', () {
      final firmwareMsg = Uint8List.fromList([0x08, 0x01]);
      final response = Uint8List.fromList([
        ...FirmwareService.debugEncodeMessageField(1, firmwareMsg),
      ]);
      expect(FirmwareService.debugDecodeResult(response), isNull);
    });
  });

  group('Download MD5 verification', () {
    // MD5 of the ASCII bytes "abc".
    final abcBytes = Uint8List.fromList('abc'.codeUnits);
    const abcMd5 = '900150983cd24fb0d6963f7d28e17f72';

    test('passes when the digest matches (case-insensitive)', () {
      expect(
        () => FirmwareService.debugVerifyMd5(abcBytes, abcMd5.toUpperCase()),
        returnsNormally,
      );
    });

    test('throws when the digest does not match', () {
      expect(
        () => FirmwareService.debugVerifyMd5(
          abcBytes,
          '00000000000000000000000000000000',
        ),
        throwsFormatException,
      );
    });

    test('is a no-op when no digest is supplied', () {
      expect(
        () => FirmwareService.debugVerifyMd5(abcBytes, ''),
        returnsNormally,
      );
    });
  });
}
