# bttest — IOBluetooth RFCOMM diagnostic tool

A small macOS command-line tool to debug the radio's Bluetooth Classic RFCOMM
channels directly, without the Flutter app. Use it to figure out the radio's
real SDP layout and how the SPP (control) and Generic Audio channels behave —
especially the issue where control frames appear on the audio channel and where
closing the audio channel disturbs the control channel.

## Requirements

- macOS, with the radio already **paired** in System Settings > Bluetooth.
- Swift toolchain (comes with Xcode / Command Line Tools).
- If you get no data at all, grant your terminal app Bluetooth access under
  System Settings > Privacy & Security > Bluetooth, then retry.

## Build & run

```sh
cd tools/bttest
swift run bttest <MAC> <mode> [options]
```

`<MAC>` accepts either `38:D2:00:00:FA:F9` or `38-D2-00-00-FA-F9`.

## Modes

| Mode      | What it does                                                              |
|-----------|---------------------------------------------------------------------------|
| `scan`    | Lists every SDP service record with its name, RFCOMM channel, and class UUIDs, then exits. Start here. |
| `control` | Opens only the SPP/control channel (0x1101) and dumps incoming frames.    |
| `audio`   | Opens only the Generic Audio channel (0x1203) and dumps incoming frames.  |
| `both`    | Opens control, waits 3s, then opens audio. Dumps traffic labeled per channel so you can see which frames land where. |

## Options

| Option            | Meaning                                                                 |
|-------------------|-------------------------------------------------------------------------|
| `--control-ch N`  | Force the control RFCOMM channel ID (default: resolved from SPP 0x1101). |
| `--audio-ch N`    | Force the audio RFCOMM channel ID (default: resolved from 0x1203).       |
| `--close-audio S` | In `both` mode, close the audio channel after `S` seconds and keep running, to test whether the control channel survives. |

## Suggested debugging session

1. **See the real channel layout:**
   ```sh
   swift run bttest 38:D2:00:00:FA:F9 scan
   ```
   Confirm whether SPP (0x1101) and Generic Audio (0x1203) report *different*
   RFCOMM channel numbers. If they report the *same* channel, the radio
   multiplexes both over one channel and a second RFCOMM connection is wrong.

2. **Control only** — verify normal control traffic and channel number:
   ```sh
   swift run bttest 38:D2:00:00:FA:F9 control
   ```

3. **Both** — watch whether control frames leak onto the AUDIO label and whether
   the CONTROL channel closes when the audio channel opens:
   ```sh
   swift run bttest 38:D2:00:00:FA:F9 both
   ```

4. **Close audio mid-session** — confirm whether closing audio kills control:
   ```sh
   swift run bttest 38:D2:00:00:FA:F9 both --close-audio 10
   ```

Press Ctrl+C to quit. Every line is timestamped and labeled with the channel
(`CONTROL(chN)` / `AUDIO(chN)`) so frames can be attributed unambiguously.
