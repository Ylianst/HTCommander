# Build It Yourself: Compiling HTCommander on Every Platform

*A start-to-finish guide to setting up a Flutter development environment and
building HTCommander from source on Windows, macOS, Linux, Android, iOS, and the
web. It covers installing Flutter, cloning the repo, the exact system packages
each desktop platform needs (including the GStreamer libraries Linux trips over
first), and the one command that produces a release build on each target.*

---

## Why build from source?

Most people should just grab a prebuilt package from the
[releases page](https://github.com/Ylianst/HTCommander/releases/latest) — there
are installers for Windows, macOS, Linux (x64 and ARM64), and Android, plus a
hosted [web version](https://ylianst.github.io/HTCommanderWeb/). But if you want
to hack on the app, test a fix, run on a platform we don't ship binaries for, or
just see how it all fits together, building from source is straightforward once
the toolchain is in place.

HTCommander is a single [Flutter](https://flutter.dev) codebase that targets
Windows, macOS, Linux, iOS, Android, and the web. The Dart/Flutter side is
identical everywhere; the only per-platform work is installing Flutter itself and
the native SDKs and system libraries each target needs. This post walks through
all of it.

---

## Step 1 — Install Flutter (all platforms)

HTCommander tracks a recent **Flutter stable** channel (it needs the Dart
`3.12+` SDK, per [`pubspec.yaml`](../../src/pubspec.yaml)). The cleanest way to
install and stay current is Flutter's own tooling.

**The universal path** — follow the official installer for your OS:
<https://docs.flutter.dev/get-started/install>

After installing, confirm the toolchain is healthy from a terminal:

```bash
flutter --version
flutter doctor
```

`flutter doctor` is your friend on every platform — it checks for the platform
SDKs, licenses, and tools described below and prints exactly what's missing. Work
through its checklist until the targets you care about show a green check.

> Tip: on Linux and macOS, installing Flutter via a version manager or the git
> clone method keeps `flutter upgrade` working. On Windows, the `.zip` install or
> `winget install --id=Google.Flutter` both work well.

Once Flutter is installed, enable the desktop/web targets you plan to build
(these are no-ops if already on):

```bash
flutter config --enable-windows-desktop
flutter config --enable-macos-desktop
flutter config --enable-linux-desktop
flutter config --enable-web
```

---

## Step 2 — Get the source

```bash
git clone https://github.com/Ylianst/HTCommander.git
cd HTCommander/src
flutter pub get
```

**Important:** the Flutter project lives in the **`src/`** subdirectory of the
repository, not the repo root. All `flutter` commands below are run from
`HTCommander/src`. `flutter pub get` downloads the Dart package dependencies; the
first native build will fetch the platform-specific pieces.

---

## Step 3 — Build for your platform

Pick your target. Each section lists the one-time platform setup, then the build
command. All builds are run from the `src/` directory.

### Windows

**Setup:**

- **Visual Studio 2022** (not VS Code) with the **"Desktop development with C++"**
  workload. This provides MSVC, the Windows SDK, and CMake — everything the
  Flutter Windows toolchain links against.

**Build:**

```powershell
flutter build windows --release
```

The result lands in `build/windows/x64/runner/Release/`. To iterate live, use
`flutter run -d windows`.

### macOS

**Setup:**

- **Xcode** (from the App Store) plus its command-line tools:
  ```bash
  sudo xcodebuild -runFirstLaunch
  ```
- **CocoaPods** for plugin dependencies:
  ```bash
  sudo gem install cocoapods
  ```

**Build:**

```bash
flutter build macos --release
```

The app bundle appears in `build/macos/Build/Products/Release/`. Use
`flutter run -d macos` for live development.

### Linux

Linux needs the most system packages because HTCommander's desktop build links
against several native libraries directly. In addition to the standard Flutter
Linux toolchain, HTCommander's own Linux runner plugins use **BlueZ** (native
Bluetooth Classic / RFCOMM to the radio), **GLib/GIO**, and the **PulseAudio
simple API** (native PCM playback), and the bundled `audioplayers` plugin uses
**GStreamer**. Missing any of these is what produces errors like:

```
CMake Error at .../FindPkgConfig.cmake:619 (message):
  The following required packages were not found:
   - gstreamer-app-1.0
```

That error just means the GStreamer development files aren't installed — it's a
missing dependency, not a bug.

**Setup (Debian / Ubuntu — including the Framework laptop):**

```bash
sudo apt update
sudo apt install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev \
  libglib2.0-dev \
  libbluetooth-dev \
  libpulse-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
```

What each group is for:

| Package(s) | Needed by |
|---|---|
| `clang`, `cmake`, `ninja-build`, `pkg-config` | The Flutter Linux build toolchain |
| `libgtk-3-dev`, `liblzma-dev` | Flutter's GTK shell |
| `libglib2.0-dev` | GLib/GIO (`gio-2.0`) used by the native plugins |
| `libbluetooth-dev` | BlueZ — native Bluetooth Classic/RFCOMM link to the radio |
| `libpulse-dev` | PulseAudio simple API — native PCM audio playback |
| `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev` | The `audioplayers` plugin (`gstreamer-app-1.0`) |
| `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good` | GStreamer runtime codecs for audio playback |

**Setup (Fedora / RHEL):**

```bash
sudo dnf install -y \
  clang cmake ninja-build pkgconf-pkg-config \
  gtk3-devel xz-devel \
  glib2-devel \
  bluez-libs-devel \
  pulseaudio-libs-devel \
  gstreamer1-devel gstreamer1-plugins-base-devel
```

**Setup (Arch):**

```bash
sudo pacman -S --needed \
  clang cmake ninja pkgconf \
  gtk3 xz \
  glib2 \
  bluez-libs \
  libpulse \
  gstreamer gst-plugins-base
```

**Verify** the tricky one is now visible to `pkg-config` before building:

```bash
pkg-config --modversion gstreamer-app-1.0
```

If that prints a version number, you're good.

**Build:**

```bash
flutter build linux --release
```

The bundle lands in `build/linux/x64/release/bundle/` (or `arm64` on ARM
machines). On an ARM64 host — like a Raspberry Pi or an ARM laptop — the exact
same command and package list apply; Flutter selects the ARM64 toolchain
automatically. Use `flutter run -d linux` for live development.

### Android

**Setup:**

- **Android Studio** (easiest — it bundles the SDK, platform tools, and an
  emulator), or the standalone Android command-line tools.
- Accept the SDK licenses:
  ```bash
  flutter doctor --android-licenses
  ```
- A device with USB debugging enabled, or a running emulator.

**Build:**

```bash
# APK for sideloading / direct install:
flutter build apk --release

# Or an App Bundle for the Play Store:
flutter build appbundle --release
```

The APK is written to `build/app/outputs/flutter-apk/`. Install straight to a
connected device with `flutter install`, or iterate with `flutter run -d <device>`.

### iOS

**Setup (macOS only):**

- **Xcode** and command-line tools (see the macOS section).
- **CocoaPods**: `sudo gem install cocoapods`.
- For running on a physical device, an Apple Developer account and a configured
  signing team in Xcode (open `ios/Runner.xcworkspace`).

**Build:**

```bash
# Simulator / development run:
flutter run -d <ios-device-or-simulator>

# Release build (add --no-codesign to skip signing for CI/inspection):
flutter build ios --release
```

### Web

**Setup:** nothing beyond Flutter itself. Note that HTCommander's web build relies
on **Web Bluetooth**, which today means **Chrome or Edge** — Safari and Firefox
don't expose the Bluetooth APIs the app needs.

**Build:**

```bash
flutter build web --release
```

When served by the desktop app instead, the web UI connects back over a
WebSocket to share the host's radio (no Web Bluetooth needed). Build that variant
with `tools/build_web_app.ps1`, which passes `--dart-define=HTC_HOSTED=true`.

The static site is emitted to `build/web/`. Serve it with any static host, or run
`flutter run -d chrome` during development.

---

## Troubleshooting

- **`Package gstreamer-app-1.0 was not found` (or `bluez`, `libpulse-simple`,
  `gio-2.0`) on Linux.** A `-dev` package is missing — install the full Linux set
  from the table above. The name after "not found" maps directly to one of those
  packages.
- **`flutter doctor` shows a red X.** Fix the item it names before building; it's
  almost always a missing SDK, an unaccepted license, or a tool not on your
  `PATH`.
- **Old artifacts causing weird build errors.** Run `flutter clean` in `src/`,
  then `flutter pub get`, then rebuild. This regenerates the ephemeral CMake/Gradle
  files.
- **Wrong directory.** Every command here runs from `HTCommander/src`, not the
  repository root. If Flutter says it can't find `pubspec.yaml`, you're one level
  too high.
- **Plugin/pod mismatches on macOS/iOS.** From `src/ios` or `src/macos`, run
  `pod repo update` then `pod install`, or just `flutter clean` and rebuild.

---

## Summary

| Platform | Host OS to build on | Extra setup beyond Flutter | Build command |
|---|---|---|---|
| Windows | Windows | Visual Studio 2022 + C++ workload | `flutter build windows --release` |
| macOS | macOS | Xcode + CocoaPods | `flutter build macos --release` |
| Linux (x64/ARM64) | Linux | GTK, BlueZ, PulseAudio, GStreamer dev libs | `flutter build linux --release` |
| Android | any | Android Studio / SDK + licenses | `flutter build apk --release` |
| iOS | macOS | Xcode + CocoaPods + signing | `flutter build ios --release` |
| Web | any | Chrome/Edge for testing | `flutter build web --release` |

Once Flutter is installed and `flutter doctor` is happy for your target, building
HTCommander is a single command. The Dart code is the same everywhere — the only
platform-specific effort is the native toolchain and, on Linux, the handful of
system libraries the radio link, audio playback, and Bluetooth stack depend on.

Happy hacking — and if you get it running on a platform we don't ship binaries
for, we'd love a report.
