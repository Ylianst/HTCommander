# Handi-Talkie Commander (Flutter Edition)

<p align="center"><img width="100" height="100" src="assets/images/AppIcon.png"></p>

Handi-Talkie Commander is an Amateur Radio (HAM Radio) control tool for Bluetooth-capable handheld radios. This repository is the **Flutter port** of the original C# WinForms application, aiming to run on as many platforms as possible (Windows, Linux, macOS, Android, and more) while keeping the same look and feel as the original.

> The original C# application by [Ylian Saint-Hilaire](https://github.com/Ylianst) lives at **[github.com/Ylianst/HTCommander](https://github.com/Ylianst/HTCommander)** and is kept under `reference/HTCommander` strictly as a development reference.

> ⚠️ **Work in progress.** This Flutter version is under active development. Features are being ported incrementally and may be incomplete or unstable.

> 📻 An Amateur Radio license is required to transmit using this software. You can get [information on a license here](https://www.arrl.org/getting-licensed).

## Radio Support

The following radios are targeted for support (matching the original application):

- BTech UV-Pro
- BTech UV-50Pro
- Radioddity GA-5WB
- Radioddity DB50-B Mini
- Radtel RT-660
- Vero VR-N75 / VR-N76
- Vero VR-N7500 / VR-N7600

These radios are controlled over **Bluetooth LE**. A computer with Bluetooth LE support (or an inexpensive Bluetooth LE USB dongle) is required.

## Features

The Flutter edition ports the feature set of the original HTCommander. The following capabilities are implemented or in progress:

- **Radio control** — Connect over Bluetooth, read radio status, and control the VFO/channels.
- **Comms / Voice** — Bluetooth audio to listen and transmit using your computer's speakers, microphone, or headset.
- **Speech-to-Text & Text-to-Speech** — On-device transcription (via `sherpa_onnx`) and TTS playback.
- **APRS** — Receive and send APRS messages, set routes, and view message details, including authenticated messages.
- **APRS Map** — OpenStreetMap-based map showing APRS stations at a glance.
- **Winlink Mail** — Send and receive email over the [Winlink network](https://winlink.org/), including attachments.
- **Terminal** — Communicate in packet modes with other stations, users, or BBSes.
- **BBS** — Built-in bulletin board support.
- **SSTV** — Send and receive images, with auto-detection on receive and drag & drop on send.
- **Torrent file exchange** — Many-to-many file exchange over 1200 Baud FM-AFSK.
- **Packet Capture** — Capture and decode packets with the built-in capture view.
- **GPS Support** — Use the radio's built-in GPS when supported by the firmware.
- **Address Book / Contacts** — Store APRS contacts and terminal profiles for quick access.
- **AGWPE Protocol** — Route other applications' traffic over the radio.
- **Web UI** — A bundled static web server (ported from the original `web/` folder) on desktop builds.

## Supported Platforms

| Platform | Status |
| --- | --- |
| Windows | Primary target |
| Linux   | Supported |
| macOS   | Supported |
| Android | Supported (speech-to-text disabled to reduce APK size) |
| iOS     | Experimental |
| Web     | Experimental |

## Building

This is a standard Flutter project. You will need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.12.2`).

```bash
# Fetch dependencies
flutter pub get

# Run in debug mode on the connected/desktop device
flutter run

# Build a release for a specific platform
flutter build windows
flutter build linux
flutter build macos
flutter build apk        # Android
```

> On Android, the large `sherpa_onnx` native libraries are replaced with empty stubs (see `dependency_overrides` in `pubspec.yaml`), so speech-to-text is disabled there to keep the APK small.

## Architecture

The Flutter version of HTCommander uses a **DataBroker** message-bus architecture: a central component through which all other components communicate. For more details, see the [DataBroker documentation](docs/databroker.md).

Additional documentation is available in the [`docs/`](docs/) folder:

- [Architecture Overview](docs/architecture.md)
- [DataBroker](docs/databroker.md)
- [Radio / Bluetooth](docs/radio-bluetooth.md)
- [Terminal](docs/terminal.md)
- [Dialogs](docs/dialogs.md)
- [Widgets](docs/widgets.md)

## Project Structure

```
lib/
├── main.dart      # App entry point, main window, tab navigation
├── aprs/          # APRS protocol and messaging
├── dialogs/       # Dialog boxes
├── gps/           # GPS handling
├── hamlib/        # Hamlib-style radio control helpers
├── handlers/      # Event/protocol handlers
├── models/        # Data models
├── radio/         # Radio connection and control (Bluetooth)
├── sbc/           # SBC audio codec
├── services/      # Business logic services (windows, etc.)
├── sstv/          # SSTV encode/decode
├── torrent/       # Torrent file transfer
├── utils/         # Shared utilities
├── widgets/       # UI components and tab views
└── winlink/       # Winlink mail support
```

## Credits

This project is a Flutter port of [HTCommander](https://github.com/Ylianst/HTCommander) by **Ylian Saint-Hilaire**.

The original tool is based on the decoding work done by Kyle Husmann (KC3SLD) and the [BenLink](https://github.com/khusmann/benlink) project, which decoded the Bluetooth commands for these radios, and on [APRS-Parser](https://github.com/k0qed/aprs-parser) by Lee (K0QED).

Map data provided by [openstreetmap.org](https://openstreetmap.org/), the project that creates and distributes free geographic data for the world.

## License

Licensed under the [Apache License 2.0](LICENSE).