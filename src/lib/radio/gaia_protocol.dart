/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';
import 'utils.dart';

/// Radio command groups
enum RadioCommandGroup {
  basic(2),
  extended(10);

  final int value;
  const RadioCommandGroup(this.value);
}

/// Radio basic commands
enum RadioBasicCommand {
  unknown(0),
  getDevId(1),
  setRegTimes(2),
  getRegTimes(3),
  getDevInfo(4),
  readStatus(5),
  registerNotification(6),
  cancelNotification(7),
  getNotification(8),
  eventNotification(9),
  readSettings(10),
  writeSettings(11),
  storeSettings(12),
  readRfCh(13),
  writeRfCh(14),
  getInScan(15),
  setInScan(16),
  setRemoteDeviceAddr(17),
  getTrustedDevice(18),
  delTrustedDevice(19),
  getHtStatus(20),
  setHtOnOff(21),
  getVolume(22),
  setVolume(23),
  radioGetStatus(24),
  radioSetMode(25),
  radioSeekUp(26),
  radioSeekDown(27),
  radioSetFreq(28),
  readAdvancedSettings(29),
  writeAdvancedSettings(30),
  htSendData(31),
  setPosition(32),
  readBssSettings(33),
  writeBssSettings(34),
  freqModeSetPar(35),
  freqModeGetStatus(36),
  readRda1846sAgc(37),
  writeRda1846sAgc(38),
  readFreqRange(39),
  writeDeEmphCoeffs(40),
  stopRinging(41),
  setTxTimeLimit(42),
  setIsDigitalSignal(43),
  setHl(44),
  setDid(45),
  setIba(46),
  getIba(47),
  setTrustedDeviceName(48),
  setVoc(49),
  getVoc(50),
  setPhoneStatus(51),
  readRfStatus(52),
  playTone(53),
  getDid(54),
  getPf(55),
  setPf(56),
  rxData(57),
  writeRegionCh(58),
  writeRegionName(59),
  setRegion(60),
  setPpId(61),
  getPpId(62),
  readAdvancedSettings2(63),
  writeAdvancedSettings2(64),
  unlock(65),
  doProgFunc(66),
  setMsg(67),
  getMsg(68),
  bleConnParam(69),
  setTime(70),
  setAprsPath(71),
  getAprsPath(72),
  readRegionName(73),
  setDevId(74),
  getPfActions(75),
  getPosition(76);

  final int value;
  const RadioBasicCommand(this.value);

  static RadioBasicCommand fromValue(int value) {
    return RadioBasicCommand.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RadioBasicCommand.unknown,
    );
  }
}

/// Radio extended commands (command group [RadioCommandGroup.extended]).
///
/// These are used by the GAIA VM firmware-update protocol. Commands are sent to
/// the radio ([vmConnect]/[vmControl]/[vmDisconnect]); the radio replies to VM
/// control messages asynchronously via [btEventNotification] events.
enum RadioExtendedCommand {
  unknown(0),
  getBtSignal(769),
  vmConnect(1600),
  vmDisconnect(1601),
  vmControl(1602),
  devRegistration(1825),
  registerBtNotification(16385),
  cancelBtNotification(16386),
  btEventNotification(16387);

  final int value;
  const RadioExtendedCommand(this.value);

  static RadioExtendedCommand fromValue(int value) {
    return RadioExtendedCommand.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RadioExtendedCommand.unknown,
    );
  }
}

/// Radio notifications
enum RadioNotification {
  unknown(0),
  htStatusChanged(1),
  dataRxd(2),
  newInquiryData(3),
  restoreFactorySettings(4),
  htChChanged(5),
  htSettingsChanged(6),
  ringingStopped(7),
  radioStatusChanged(8),
  userAction(9),
  systemEvent(10),
  bssSettingsChanged(11),
  dataTxd(12),
  positionChange(13);

  final int value;
  const RadioNotification(this.value);
}

/// Radio power status types
enum RadioPowerStatus {
  unknown(0),
  batteryLevel(1),
  batteryVoltage(2),
  rcBatteryLevel(3),
  batteryLevelAsPercentage(4);

  final int value;
  const RadioPowerStatus(this.value);
}

/// Programmable-function action types (how a button event is interpreted).
///
/// Mirrors benlink's `PFActionType`. Used to decode the GET_PF button table.
/// The edge actions ([lowToHigh]/[highToLow]) are the likely candidates for a
/// live press/release when triggering a function remotely via DO_PROG_FUNC.
enum PFActionType {
  invalid(0),
  short(1),
  long(2),
  veryLong(3),
  double(4),
  repeat(5),
  lowToHigh(6),
  highToLow(7),
  shortSingle(8),
  longRelease(9),
  veryLongRelease(10),
  veryVeryLong(11),
  veryVeryLongRelease(12),
  triple(13);

  final int value;
  const PFActionType(this.value);

  static PFActionType fromValue(int value) => PFActionType.values.firstWhere(
    (e) => e.value == value,
    orElse: () => PFActionType.invalid,
  );
}

/// Programmable-function effect types (what a button does when triggered).
///
/// Mirrors benlink's `PFEffectType`. These are the effects a physical button
/// can be mapped to (via SET_PF) or that may be triggered remotely (via
/// DO_PROG_FUNC). [mainPtt] keys the main-VFO transmitter.
enum PFEffectType {
  disable(0),
  alarm(1),
  alarmAndMute(2),
  toggleOffline(3),
  toggleRadioTx(4),
  toggleTxPower(5),
  toggleFm(6),
  prevChannel(7),
  nextChannel(8),
  tCall(9),
  prevRegion(10),
  nextRegion(11),
  toggleChScan(12),
  mainPtt(13),
  subPtt(14),
  toggleMonitor(15),
  btPairing(16),
  toggleDoubleCh(17),
  toggleAbCh(18),
  sendLocation(19),
  oneClickLink(20),
  volDown(21),
  volUp(22),
  toggleMute(23);

  final int value;
  const PFEffectType(this.value);

  static PFEffectType fromValue(int value) => PFEffectType.values.firstWhere(
    (e) => e.value == value,
    orElse: () => PFEffectType.disable,
  );
}

/// GAIA protocol encoder/decoder for radio communication
class GaiaProtocol {
  /// Decode a GAIA frame from raw data
  /// Returns the number of bytes consumed, or 0 if incomplete, -1 on error
  /// The decoded command is returned via the out parameter.
  /// Accepts any [List<int>] so callers can decode directly from their receive
  /// buffer at an offset without copying it into a new [Uint8List].
  static ({int consumed, Uint8List? command}) decode(
    List<int> data,
    int index,
    int len,
  ) {
    if (len < 8) return (consumed: 0, command: null);
    if (data[index] != 0xFF || data[index + 1] != 0x01) {
      return (consumed: -1, command: null);
    }

    final payloadLen = data[index + 3];
    final hasChecksum = data[index + 2] & 1;
    final totalLen = payloadLen + 8 + hasChecksum;
    if (totalLen > len) return (consumed: 0, command: null);

    final cmd = Uint8List(4 + payloadLen);
    cmd.setRange(0, cmd.length, data, index + 4);
    return (consumed: totalLen, command: cmd);
  }

  /// Encode a command into a GAIA frame
  static Uint8List encode(Uint8List cmd) {
    final bytes = Uint8List(cmd.length + 4);
    bytes[0] = 0xFF;
    bytes[1] = 0x01;
    bytes[2] = 0x00; // No checksum
    bytes[3] = cmd.length - 4;
    bytes.setRange(4, 4 + cmd.length, cmd);
    return bytes;
  }

  /// Build a command packet
  static Uint8List buildCommand(
    RadioCommandGroup group,
    RadioBasicCommand cmd, [
    Uint8List? data,
  ]) {
    return buildRawCommand(group.value, cmd.value, data);
  }

  /// Build a command packet from raw group and command values.
  ///
  /// Produces `[group_hi, group_lo, cmd_hi, cmd_lo, data...]` (big-endian).
  /// Used for extended commands (e.g. the VM firmware-update protocol) whose
  /// command values fall outside [RadioBasicCommand].
  static Uint8List buildRawCommand(
    int groupValue,
    int cmdValue, [
    Uint8List? data,
  ]) {
    final dataLen = data?.length ?? 0;
    final cmdData = Uint8List(4 + dataLen);

    // Big-endian group
    cmdData[0] = (groupValue >> 8) & 0xFF;
    cmdData[1] = groupValue & 0xFF;

    // Big-endian command
    cmdData[2] = (cmdValue >> 8) & 0xFF;
    cmdData[3] = cmdValue & 0xFF;

    // Data
    if (data != null) {
      cmdData.setRange(4, 4 + data.length, data);
    }

    return cmdData;
  }

  /// Build a command packet with a single byte parameter
  static Uint8List buildCommandByte(
    RadioCommandGroup group,
    RadioBasicCommand cmd,
    int value,
  ) {
    return buildCommand(group, cmd, Uint8List.fromList([value]));
  }

  /// Build a command packet with an int parameter
  static Uint8List buildCommandInt(
    RadioCommandGroup group,
    RadioBasicCommand cmd,
    int value,
  ) {
    final data = Uint8List(4);
    RadioUtils.setInt(data, 0, value);
    return buildCommand(group, cmd, data);
  }

  /// Parse a response to get group and command
  static ({RadioCommandGroup group, RadioBasicCommand command, bool isResponse})
  parseResponse(Uint8List data) {
    if (data.length < 4) {
      return (
        group: RadioCommandGroup.basic,
        command: RadioBasicCommand.unknown,
        isResponse: false,
      );
    }

    final groupValue = RadioUtils.getShort(data, 0);
    final cmdValue = RadioUtils.getShort(data, 2);

    final isResponse = (cmdValue & 0x8000) != 0;
    final actualCmd = cmdValue & 0x7FFF;

    final group = groupValue == RadioCommandGroup.extended.value
        ? RadioCommandGroup.extended
        : RadioCommandGroup.basic;

    return (
      group: group,
      command: RadioBasicCommand.fromValue(actualCmd),
      isResponse: isResponse,
    );
  }

  /// Get the expected response code for a command
  static int getExpectedResponse(
    RadioCommandGroup group,
    RadioBasicCommand cmd,
  ) {
    switch (cmd) {
      case RadioBasicCommand.registerNotification:
      case RadioBasicCommand.writeSettings:
      case RadioBasicCommand.setRegion:
        return -1;
      default:
        final rcmd = cmd.value | 0x8000;
        return (group.value << 16) + rcmd;
    }
  }
}
