#!/usr/bin/env python3
"""Decode an Android btsnoop HCI log of a Benshi radio firmware update into CSV.

The log captures the full Bluetooth traffic between an application and the
radio. On Android the radio speaks over Bluetooth Classic RFCOMM (SPP), and the
HTCommander/Benshi "GAIA" command protocol rides on top of that serial stream.
This tool peels back every layer and emits one CSV row per decoded command:

    btsnoop record -> HCI H4 -> ACL (reassembly) -> L2CAP -> RFCOMM (UIH) ->
    GAIA frame (FF 01 CS LEN ...) -> decoded command

Both the "basic" command group (2) and the "extended" firmware-update VM
protocol (group 10, VM_CONTROL / BT_EVENT_NOTIFICATION) are decoded.

Usage:
    python decode_btsnoop.py INPUT.log [-o OUTPUT.csv] [--max-hex N]

If no output path is given, the CSV is written next to the input with a .csv
extension. The decoder uses only the Python standard library.

Protocol reference (canonical source of truth in this repo):
    src/lib/radio/gaia_protocol.dart
    src/lib/radio/firmware_vm_protocol.dart
    docs/blogs/radio-command-protocol.md
"""

from __future__ import annotations

import argparse
import bisect
import csv
import datetime
import struct
import sys
from collections import defaultdict
from dataclasses import dataclass, field

# --------------------------------------------------------------------------- #
# Protocol constants (mirrors the Dart enums in src/lib/radio/)
# --------------------------------------------------------------------------- #

# btsnoop timestamps are microseconds since midnight 0000-01-01 (proleptic
# Gregorian). Subtract the offset to year 1970 to get a Unix timestamp.
BTSNOOP_EPOCH_DELTA_US = 62_167_219_200_000_000

# HCI H4 packet-type indicator (first byte of each record for datalink 1002).
H4_CMD = 0x01
H4_ACL = 0x02
H4_SCO = 0x03
H4_EVT = 0x04

L2CAP_CID_SIGNALING = 0x0001

# GAIA command groups.
GROUP_BASIC = 2
GROUP_EXTENDED = 10

GROUP_NAMES = {GROUP_BASIC: "basic", GROUP_EXTENDED: "extended"}

# RadioBasicCommand (group 2) — value -> name.
BASIC_COMMANDS = {
    0: "UNKNOWN", 1: "GET_DEV_ID", 2: "SET_REG_TIMES", 3: "GET_REG_TIMES",
    4: "GET_DEV_INFO", 5: "READ_STATUS", 6: "REGISTER_NOTIFICATION",
    7: "CANCEL_NOTIFICATION", 8: "GET_NOTIFICATION", 9: "EVENT_NOTIFICATION",
    10: "READ_SETTINGS", 11: "WRITE_SETTINGS", 12: "STORE_SETTINGS",
    13: "READ_RF_CH", 14: "WRITE_RF_CH", 15: "GET_IN_SCAN", 16: "SET_IN_SCAN",
    17: "SET_REMOTE_DEVICE_ADDR", 18: "GET_TRUSTED_DEVICE",
    19: "DEL_TRUSTED_DEVICE", 20: "GET_HT_STATUS", 21: "SET_HT_ON_OFF",
    22: "GET_VOLUME", 23: "SET_VOLUME", 24: "RADIO_GET_STATUS",
    25: "RADIO_SET_MODE", 26: "RADIO_SEEK_UP", 27: "RADIO_SEEK_DOWN",
    28: "RADIO_SET_FREQ", 29: "READ_ADVANCED_SETTINGS",
    30: "WRITE_ADVANCED_SETTINGS", 31: "HT_SEND_DATA", 32: "SET_POSITION",
    33: "READ_BSS_SETTINGS", 34: "WRITE_BSS_SETTINGS", 35: "FREQ_MODE_SET_PAR",
    36: "FREQ_MODE_GET_STATUS", 37: "READ_RDA1846S_AGC",
    38: "WRITE_RDA1846S_AGC", 39: "READ_FREQ_RANGE", 40: "WRITE_DE_EMPH_COEFFS",
    41: "STOP_RINGING", 42: "SET_TX_TIME_LIMIT", 43: "SET_IS_DIGITAL_SIGNAL",
    44: "SET_HL", 45: "SET_DID", 46: "SET_IBA", 47: "GET_IBA",
    48: "SET_TRUSTED_DEVICE_NAME", 49: "SET_VOC", 50: "GET_VOC",
    51: "SET_PHONE_STATUS", 52: "READ_RF_STATUS", 53: "PLAY_TONE",
    54: "GET_DID", 55: "GET_PF", 56: "SET_PF", 57: "RX_DATA",
    58: "WRITE_REGION_CH", 59: "WRITE_REGION_NAME", 60: "SET_REGION",
    61: "SET_PP_ID", 62: "GET_PP_ID", 63: "READ_ADVANCED_SETTINGS2",
    64: "WRITE_ADVANCED_SETTINGS2", 65: "UNLOCK", 66: "DO_PROG_FUNC",
    67: "SET_MSG", 68: "GET_MSG", 69: "BLE_CONN_PARAM", 70: "SET_TIME",
    71: "SET_APRS_PATH", 72: "GET_APRS_PATH", 73: "READ_REGION_NAME",
    74: "SET_DEV_ID", 75: "GET_PF_ACTIONS", 76: "GET_POSITION",
    77: "SET_SATELLITE_INFO",
}

# RadioExtendedCommand (group 10) — value -> name.
EXTENDED_COMMANDS = {
    0: "UNKNOWN", 769: "GET_BT_SIGNAL", 1600: "VM_CONNECT",
    1601: "VM_DISCONNECT", 1602: "VM_CONTROL", 1825: "DEV_REGISTRATION",
    16385: "REGISTER_BT_NOTIFICATION", 16386: "CANCEL_BT_NOTIFICATION",
    16387: "BT_EVENT_NOTIFICATION",
}

# Basic-reply status byte (payload[0]) meanings.
STATUS_NAMES = {
    0: "success", 1: "notSupported", 2: "notAuthenticated",
    3: "insufficientResources", 4: "authenticating", 5: "invalidParameter",
    6: "incorrectState", 7: "inProgress",
}

# RadioNotification — used to decode EVENT_NOTIFICATION payloads.
NOTIFICATION_NAMES = {
    0: "unknown", 1: "htStatusChanged", 2: "dataRxd", 3: "newInquiryData",
    4: "restoreFactorySettings", 5: "htChChanged", 6: "htSettingsChanged",
    7: "ringingStopped", 8: "radioStatusChanged", 9: "userAction",
    10: "systemEvent", 11: "bssSettingsChanged", 12: "dataTxd",
    13: "positionChange", 14: "freqModeStatusChanged",
}

# VM_CONTROL message types (app -> radio inside a VM_CONTROL command).
VM_CONTROL_TYPES = {
    1: "UPDATE_START_REQ", 4: "UPDATE_DATA", 7: "UPDATE_ABORT_REQ",
    12: "UPDATE_TRANSFER_COMPLETE_RES", 14: "UPDATE_IN_PROGRESS_RES",
    16: "UPDATE_COMMIT_CFM", 19: "UPDATE_SYNC_REQ", 21: "UPDATE_START_DATA_REQ",
    22: "UPDATE_IS_VALIDATION_DONE_REQ", 30: "UPDATE_ERASE_SQIF_CFM",
    31: "UPDATE_ABORT_WITH_CODE1_REQ", 32: "UPDATE_ABORT_WITH_CODE2_REQ",
}

# VMU packet types (radio -> app inside a BT_EVENT_NOTIFICATION).
VMU_PACKET_TYPES = {
    2: "UPDATE_START_CFM", 3: "UPDATE_DATA_BYTES_REQ", 8: "UPDATE_ABORT_CFM",
    11: "UPDATE_TRANSFER_COMPLETE_IND", 15: "UPDATE_COMMIT_RES",
    17: "UPDATE_ERROR", 18: "UPDATE_COMPLETE_IND", 20: "UPDATE_SYNC_CFM",
    23: "UPDATE_IS_VALIDATION_DONE_CFM", 29: "UPDATE_COMMIT_ERASE_SQIF_RES",
}

BT_EVENT_TYPE_VMU_PACKET = 18

UPDATE_START_CFM_CODES = {0: "OK", 9: "GOTO_NEXT_STATE"}
UPDATE_ERROR_CODES = {0: "unknown", 33: "batteryLow", 129: "syncIsDifferent"}

# RFCOMM control-field frame types (with the P/F bit masked off).
RFCOMM_SABM = 0x2F
RFCOMM_UA = 0x63
RFCOMM_DM = 0x0F
RFCOMM_DISC = 0x43
RFCOMM_UIH = 0xEF
RFCOMM_FRAME_TYPES = {RFCOMM_SABM, RFCOMM_UA, RFCOMM_DM, RFCOMM_DISC, RFCOMM_UIH}

DIR_APP_TO_RADIO = "APP->RADIO"
DIR_RADIO_TO_APP = "RADIO->APP"


# --------------------------------------------------------------------------- #
# Small byte helpers (big-endian, matching RadioUtils in the Dart code)
# --------------------------------------------------------------------------- #

def be16(data: bytes, off: int) -> int:
    if off + 2 > len(data):
        return 0
    return (data[off] << 8) | data[off + 1]


def be32(data: bytes, off: int) -> int:
    if off + 4 > len(data):
        return 0
    return (data[off] << 24) | (data[off + 1] << 16) | (data[off + 2] << 8) | data[off + 3]


def hexstr(data: bytes, limit: int | None = None) -> str:
    if limit is not None and len(data) > limit:
        return data[:limit].hex(" ") + f" ...(+{len(data) - limit}B)"
    return data.hex(" ")


# --------------------------------------------------------------------------- #
# btsnoop file reader
# --------------------------------------------------------------------------- #

@dataclass
class HciRecord:
    ts_us: int          # microseconds since Unix epoch
    sent: bool          # True = host->controller (APP->RADIO)
    data: bytes         # H4 payload (starts with the packet-type byte)


def read_btsnoop(path: str):
    """Yield HciRecord for every packet in a btsnoop file."""
    with open(path, "rb") as fh:
        header = fh.read(16)
        if header[:8] != b"btsnoop\x00":
            raise ValueError("Not a btsnoop file (bad magic)")
        version, datalink = struct.unpack(">II", header[8:16])
        if version != 1:
            raise ValueError(f"Unsupported btsnoop version {version}")
        # datalink 1002 = HCI UART (H4); 1001 = HCI (no type byte).
        while True:
            rec_hdr = fh.read(24)
            if len(rec_hdr) < 24:
                break
            (orig_len, incl_len, flags, _drops, ts) = struct.unpack(
                ">IIIIq", rec_hdr
            )
            data = fh.read(incl_len)
            if len(data) < incl_len:
                break  # truncated file
            ts_us = ts - BTSNOOP_EPOCH_DELTA_US
            sent = (flags & 0x01) == 0  # bit0: 0 = sent (host->controller)
            yield HciRecord(ts_us=ts_us, sent=sent, data=data)


# --------------------------------------------------------------------------- #
# ACL -> L2CAP reassembly
# --------------------------------------------------------------------------- #

class AclReassembler:
    """Reassembles ACL fragments into complete L2CAP PDUs, per connection."""

    def __init__(self):
        # key -> (buffer bytearray, expected_total_len, ts_us)
        self._pending: dict[tuple[int, bool], list] = {}

    def feed(self, rec: HciRecord):
        """Feed an ACL record; yield (ts_us, sent, l2cap_pdu) for each PDU."""
        data = rec.data
        if len(data) < 5 or data[0] != H4_ACL:
            return
        handle_flags = data[1] | (data[2] << 8)
        handle = handle_flags & 0x0FFF
        pb = (handle_flags >> 12) & 0x03
        acl_len = data[3] | (data[4] << 8)
        payload = data[5:5 + acl_len]

        key = (handle, rec.sent)
        if pb in (0b10, 0b00):  # start fragment (BR/EDR non-flushable, or BLE)
            if len(payload) < 4:
                return
            l2cap_len = payload[0] | (payload[1] << 8)
            total = l2cap_len + 4  # + L2CAP header (len + cid)
            buf = bytearray(payload)
            if len(buf) >= total:
                yield (rec.ts_us, rec.sent, bytes(buf[:total]))
                self._pending.pop(key, None)
            else:
                self._pending[key] = [buf, total, rec.ts_us]
        elif pb == 0b01:  # continuation
            entry = self._pending.get(key)
            if entry is None:
                return  # continuation without a start; ignore
            entry[0].extend(payload)
            if len(entry[0]) >= entry[1]:
                total = entry[1]
                yield (entry[2], rec.sent, bytes(entry[0][:total]))
                self._pending.pop(key, None)


# --------------------------------------------------------------------------- #
# RFCOMM
# --------------------------------------------------------------------------- #

def parse_l2cap(pdu: bytes) -> tuple[int, bytes]:
    """Return (cid, payload) from an L2CAP B-frame."""
    if len(pdu) < 4:
        return (0, b"")
    length = pdu[0] | (pdu[1] << 8)
    cid = pdu[2] | (pdu[3] << 8)
    payload = pdu[4:4 + length]
    return (cid, payload)


def rfcomm_info(frame: bytes):
    """Parse a single RFCOMM frame; return (dlci, info_bytes) or None.

    Only UIH data frames carry information; other frame types return
    (dlci, b"").  Returns None when the bytes do not look like RFCOMM.
    """
    if len(frame) < 4:  # addr + control + len + fcs minimum
        return None
    addr = frame[0]
    if (addr & 0x01) == 0:  # address EA bit must terminate the octet
        return None
    dlci = (addr >> 2) & 0x3F
    control = frame[1]
    ftype = control & ~0x10  # mask off the P/F bit
    if ftype not in RFCOMM_FRAME_TYPES:
        return None

    pos = 2
    if pos >= len(frame):
        return None
    len_byte = frame[pos]
    if len_byte & 0x01:  # EA=1 -> single length octet
        info_len = len_byte >> 1
        pos += 1
    else:                # EA=0 -> two length octets
        if pos + 1 >= len(frame):
            return None
        info_len = (len_byte >> 1) | (frame[pos + 1] << 7)
        pos += 2

    if ftype != RFCOMM_UIH:
        return (dlci, b"")

    # Credit-based flow control: a P/F bit on a UIH frame means a 1-byte
    # credit field precedes the information field.
    if control & 0x10:
        pos += 1

    info = frame[pos:pos + info_len]
    if len(info) < info_len:
        return None  # frame shorter than its own length field claims
    return (dlci, bytes(info))


class RfcommChannelTracker:
    """Identifies which L2CAP CIDs carry RFCOMM (PSM 3) via signaling."""

    def __init__(self):
        self.rfcomm_cids: set[int] = set()
        self._pending_scid: dict[int, int] = {}  # signaling id -> requester scid

    def observe_signaling(self, payload: bytes):
        pos = 0
        while pos + 4 <= len(payload):
            code = payload[pos]
            ident = payload[pos + 1]
            clen = payload[pos + 2] | (payload[pos + 3] << 8)
            body = payload[pos + 4:pos + 4 + clen]
            pos += 4 + clen
            if code == 0x02 and len(body) >= 4:  # Connection Request
                psm = body[0] | (body[1] << 8)
                scid = body[2] | (body[3] << 8)
                if psm == 0x0003:  # RFCOMM
                    self._pending_scid[ident] = scid
                    self.rfcomm_cids.add(scid)
            elif code == 0x03 and len(body) >= 8:  # Connection Response
                dcid = body[0] | (body[1] << 8)
                scid = body[2] | (body[3] << 8)
                result = body[4] | (body[5] << 8)
                if ident in self._pending_scid:
                    if result == 0x0000 and dcid:
                        self.rfcomm_cids.add(dcid)
                        self.rfcomm_cids.add(scid)

    def is_rfcomm(self, cid: int) -> bool:
        if cid in self.rfcomm_cids:
            return True
        # Fallback heuristic: any dynamic CID when signaling was not captured.
        return not self.rfcomm_cids and cid >= 0x0040


# --------------------------------------------------------------------------- #
# GAIA stream reassembly + frame extraction
# --------------------------------------------------------------------------- #

class GaiaStream:
    """Accumulates one direction's RFCOMM data and extracts GAIA frames."""

    def __init__(self):
        self._buf = bytearray()
        self._marker_idx: list[int] = []   # buffer offset of each fed chunk
        self._marker_ts: list[int] = []    # timestamp for that chunk

    def feed(self, data: bytes, ts_us: int):
        if not data:
            return
        self._marker_idx.append(len(self._buf))
        self._marker_ts.append(ts_us)
        self._buf.extend(data)

    def _ts_at(self, index: int) -> int:
        j = bisect.bisect_right(self._marker_idx, index) - 1
        if j < 0:
            j = 0
        return self._marker_ts[j]

    def frames(self):
        """Yield (ts_us, cmd_bytes) for each complete GAIA frame."""
        buf = self._buf
        n = len(buf)
        i = 0
        while i + 8 <= n:
            if buf[i] != 0xFF or buf[i + 1] != 0x01:
                i += 1
                continue
            has_csum = buf[i + 2] & 0x01
            payload_len = buf[i + 3]
            total = payload_len + 8 + has_csum
            if i + total > n:
                break  # incomplete (end of a truncated capture)
            cmd = bytes(buf[i + 4:i + 8 + payload_len])
            yield (self._ts_at(i), cmd)
            i += total


# --------------------------------------------------------------------------- #
# GAIA command decoding
# --------------------------------------------------------------------------- #

@dataclass
class DecodedCommand:
    ts_us: int
    direction: str
    group: int
    command_value: int
    command_name: str
    kind: str            # request / response / notification
    status: str
    decoded: str
    payload: bytes = field(repr=False)


def _decode_vm_control(payload: bytes) -> str:
    """Decode a VM_CONTROL command body: [type(1), n(2 BE), inner...]."""
    if len(payload) < 3:
        return "VM_CONTROL (truncated)"
    vtype = payload[0]
    n = be16(payload, 1)
    inner = payload[3:3 + n]
    name = VM_CONTROL_TYPES.get(vtype, f"type_{vtype}")
    if vtype == 4:  # UPDATE_DATA
        is_final = inner[0] if inner else 0
        chunk = inner[1:]
        return (f"{name} isFinal={is_final} chunkLen={len(chunk)} "
                f"first={hexstr(chunk[:8])}")
    if vtype == 19:  # UPDATE_SYNC_REQ
        return f"{name} md5Tail={hexstr(inner[:4])}"
    if vtype == 12:  # UPDATE_TRANSFER_COMPLETE_RES
        action = inner[0] if inner else -1
        meaning = "commit/reboot" if action == 0 else ("abort" if action == 1 else "?")
        return f"{name} action={action} ({meaning})"
    if inner:
        return f"{name} body={hexstr(inner, 32)}"
    return name


def _decode_bt_event_notification(payload: bytes) -> str:
    """Decode a BT_EVENT_NOTIFICATION body (VMU packet from the radio)."""
    if len(payload) < 4:
        return "BT_EVENT (truncated)"
    bt_event_type = payload[0]
    if bt_event_type != BT_EVENT_TYPE_VMU_PACKET:
        return f"btEventType={bt_event_type} data={hexstr(payload[1:], 32)}"
    vmu_type = payload[1]
    n = be16(payload, 2)
    body = payload[4:4 + n]
    name = VMU_PACKET_TYPES.get(vmu_type, f"vmu_{vmu_type}")
    if vmu_type == 2:   # UPDATE_START_CFM
        code = body[0] if body else -1
        return f"{name} code={UPDATE_START_CFM_CODES.get(code, code)}"
    if vmu_type == 3:   # UPDATE_DATA_BYTES_REQ
        return (f"{name} bytesRequested={be32(body, 0)} "
                f"bytesSkip={be32(body, 4)}")
    if vmu_type == 20:  # UPDATE_SYNC_CFM
        state = body[0] if body else -1
        return f"{name} updateState={state} md5Tail={hexstr(body[1:5])}"
    if vmu_type == 17:  # UPDATE_ERROR
        err = be16(body, 0)
        return f"{name} error={UPDATE_ERROR_CODES.get(err, err)}"
    if body:
        return f"{name} body={hexstr(body, 32)}"
    return name


def decode_command(ts_us: int, sent: bool, cmd: bytes) -> DecodedCommand:
    """Decode an un-framed GAIA command: [group16, cmd16, payload...]."""
    direction = DIR_APP_TO_RADIO if sent else DIR_RADIO_TO_APP
    group = be16(cmd, 0)
    cmd_raw = be16(cmd, 2)
    is_response = (cmd_raw & 0x8000) != 0
    cmd_value = cmd_raw & 0x7FFF
    payload = cmd[4:]

    status = ""
    kind = "response" if is_response else "request"
    decoded = ""

    if group == GROUP_BASIC:
        name = BASIC_COMMANDS.get(cmd_value, f"BASIC_{cmd_value}")
        if is_response and payload:
            status = STATUS_NAMES.get(payload[0], f"status_{payload[0]}")
        if cmd_value == 9:  # EVENT_NOTIFICATION
            kind = "notification"
            nt = payload[0] if not is_response and payload else (
                payload[1] if len(payload) > 1 else -1)
            # EVENT_NOTIFICATION carries a notification-type byte.
            ntype = payload[0] if payload else -1
            decoded = f"notification={NOTIFICATION_NAMES.get(ntype, ntype)}"
        elif payload:
            decoded = f"payload={hexstr(payload, 48)}"
    elif group == GROUP_EXTENDED:
        name = EXTENDED_COMMANDS.get(cmd_value, f"EXT_{cmd_value}")
        if cmd_value == 1602:  # VM_CONTROL
            if is_response:
                status = STATUS_NAMES.get(payload[0], f"status_{payload[0]}") if payload else ""
                decoded = "VM_CONTROL reply"
            else:
                decoded = _decode_vm_control(payload)
        elif cmd_value == 16387:  # BT_EVENT_NOTIFICATION
            kind = "notification"
            decoded = _decode_bt_event_notification(payload)
        elif cmd_value in (1600, 1601):  # VM_CONNECT / VM_DISCONNECT
            if is_response and payload:
                status = STATUS_NAMES.get(payload[0], f"status_{payload[0]}")
            decoded = name
        elif payload:
            decoded = f"payload={hexstr(payload, 48)}"
    else:
        name = f"GROUP{group}_CMD{cmd_value}"
        if payload:
            decoded = f"payload={hexstr(payload, 48)}"

    return DecodedCommand(
        ts_us=ts_us, direction=direction, group=group,
        command_value=cmd_value, command_name=name, kind=kind,
        status=status, decoded=decoded, payload=payload,
    )


# --------------------------------------------------------------------------- #
# Main driver
# --------------------------------------------------------------------------- #

def decode_file(input_path: str, max_hex: int):
    reassembler = AclReassembler()
    tracker = RfcommChannelTracker()
    tx_stream = GaiaStream()  # APP -> RADIO
    rx_stream = GaiaStream()  # RADIO -> APP

    for rec in read_btsnoop(input_path):
        if len(rec.data) < 1 or rec.data[0] != H4_ACL:
            continue
        for ts_us, sent, pdu in reassembler.feed(rec):
            cid, payload = parse_l2cap(pdu)
            if cid == L2CAP_CID_SIGNALING:
                tracker.observe_signaling(payload)
                continue
            if not tracker.is_rfcomm(cid):
                continue
            parsed = rfcomm_info(payload)
            if parsed is None:
                continue
            dlci, info = parsed
            if dlci == 0 or not info:
                continue  # DLCI 0 is the RFCOMM control channel
            (tx_stream if sent else rx_stream).feed(info, ts_us)

    rows: list[DecodedCommand] = []
    for ts_us, cmd in tx_stream.frames():
        rows.append(decode_command(ts_us, True, cmd))
    for ts_us, cmd in rx_stream.frames():
        rows.append(decode_command(ts_us, False, cmd))
    rows.sort(key=lambda r: r.ts_us)
    return rows


def format_ts(ts_us: int) -> str:
    dt = datetime.datetime.fromtimestamp(ts_us / 1_000_000, tz=datetime.timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:%S.") + f"{ts_us % 1_000_000:06d}"


def write_csv(rows, output_path: str, max_hex: int):
    with open(output_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow([
            "index", "timestamp_utc", "delta_ms", "direction", "group",
            "command", "cmd_value", "kind", "status", "decoded",
            "payload_len", "payload_hex",
        ])
        prev_ts = None
        for i, r in enumerate(rows):
            delta = "" if prev_ts is None else f"{(r.ts_us - prev_ts) / 1000:.3f}"
            prev_ts = r.ts_us
            writer.writerow([
                i, format_ts(r.ts_us), delta, r.direction,
                GROUP_NAMES.get(r.group, str(r.group)), r.command_name,
                r.command_value, r.kind, r.status, r.decoded,
                len(r.payload), hexstr(r.payload, max_hex),
            ])


def print_summary(rows):
    counts: dict[tuple[str, str], int] = defaultdict(int)
    for r in rows:
        counts[(r.direction, r.command_name)] += 1
    print(f"Decoded {len(rows)} commands:", file=sys.stderr)
    for (direction, name), n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:6d}  {direction:11s} {name}", file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Decode an Android btsnoop HCI log of a Benshi radio "
                    "firmware update into a CSV of decoded commands.")
    parser.add_argument("input", help="Path to the btsnoop .log file")
    parser.add_argument("-o", "--output", help="Output CSV path "
                        "(default: alongside the input)")
    parser.add_argument("--max-hex", type=int, default=64,
                        help="Max payload bytes to render as hex (default 64)")
    args = parser.parse_args(argv)

    output = args.output
    if output is None:
        base = args.input
        if base.lower().endswith(".log"):
            base = base[:-4]
        output = base + ".csv"

    rows = decode_file(args.input, args.max_hex)
    write_csv(rows, output, args.max_hex)
    print_summary(rows)
    print(f"Wrote {len(rows)} rows to {output}", file=sys.stderr)


if __name__ == "__main__":
    main()
