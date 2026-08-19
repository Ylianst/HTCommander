# btsnoop Decoder

`decode_btsnoop.py` decodes an Android **btsnoop HCI log** of a Benshi radio
firmware update into a CSV of decoded GAIA commands.

The tool peels back every protocol layer:

```
btsnoop record -> HCI H4 -> ACL (reassembly) -> L2CAP -> RFCOMM (UIH) ->
GAIA frame (FF 01 CS LEN ...) -> decoded command
```

Both the "basic" command group (2) and the "extended" firmware-update VM
protocol (group 10, `VM_CONTROL` / `BT_EVENT_NOTIFICATION`) are decoded. The
decoder uses only the Python standard library — no dependencies to install.

## Requirements

- Python 3.10 or newer (uses `int | None` style type hints)

## Usage

```sh
python decode_btsnoop.py INPUT.log [-o OUTPUT.csv] [--max-hex N]
```

Arguments:

- `INPUT.log` — path to the btsnoop `.log` file to decode (required).
- `-o`, `--output OUTPUT.csv` — output CSV path. Defaults to the input path with
  its `.log` extension replaced by `.csv`.
- `--max-hex N` — maximum number of payload bytes to render as hex in the
  `payload_hex` column (default `64`). Longer payloads are truncated with a
  `...(+NB)` suffix.

A per-command summary is printed to stderr when decoding finishes.

### Example

Decode the included capture, writing `btsnoop_hci_firmware_upgrade.csv`
next to the input:

```sh
python decode_btsnoop.py btsnoop_hci_firmware_upgrade.log
```

Decode to a custom output path and show more payload bytes:

```sh
python decode_btsnoop.py btsnoop_hci_firmware_upgrade.log -o decoded.csv --max-hex 128
```

## Output columns

The CSV contains one row per decoded GAIA command with these columns:

| Column | Description |
| --- | --- |
| `index` | Row number in timestamp order. |
| `timestamp_utc` | Packet time in UTC (`YYYY-MM-DD HH:MM:SS.ffffff`). |
| `delta_ms` | Milliseconds since the previous row. |
| `direction` | `APP->RADIO` or `RADIO->APP`. |
| `group` | Command group (`basic`, `extended`, or numeric). |
| `command` | Decoded command name. |
| `cmd_value` | Numeric command value (response bit masked off). |
| `kind` | `request`, `response`, or `notification`. |
| `status` | Status byte meaning for replies (e.g. `success`). |
| `decoded` | Human-readable decode of the command body. |
| `payload_len` | Length of the command payload in bytes. |
| `payload_hex` | Payload bytes as hex (truncated per `--max-hex`). |

## Sample capture

`btsnoop_hci_firmware_upgrade.log` contains the firmware update from
firmware **9.0.0 to 9.0.3** for the **UV-Pro radio**. The already-decoded output
of this capture is provided alongside it as
`btsnoop_hci_firmware_upgrade.csv`.

## Protocol reference

The canonical protocol definitions in this repository are:

- `src/lib/radio/gaia_protocol.dart`
- `src/lib/radio/firmware_vm_protocol.dart`
- `docs/blogs/radio-command-protocol.md`
