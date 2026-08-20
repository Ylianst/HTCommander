# Testing HTCommander with Android Auto

HTCommander includes a templated Android Auto experience built with the
Android for Cars App Library. Use Google's Desktop Head Unit (DHU) to preview
and test it on a development computer. The DHU behaves like a vehicle display,
while an Android phone runs Android Auto and the HTCommander app.

## What the car interface provides

The Android Auto app appears in the IoT/device-control category and provides:

- A list of channels from the preferred connected radio.
- A `Current` indicator on the active channel.
- One-tap channel changes.
- A `Messages` screen containing recent APRS messages addressed to the station.

Android Auto renders these screens from standard car templates, so their exact
colors, spacing, and navigation chrome can vary by Android Auto version and
head unit. When HTCommander is not connected to a radio, the channel screen
displays `Open HTCommander and connect a radio`.

## Requirements

- Android Studio with the Android SDK installed.
- Flutter and the HTCommander source tree.
- An Android phone running Android 9 (API level 28) or newer.
- The latest Android Auto app on the phone. On Android 10 and newer, update it
  through Google Play before using the DHU for the first time.
- A USB cable that supports data.
- A radio supported by HTCommander if testing live channel data.

The standard Android Emulator is not a replacement for this setup. Projected
Android Auto testing uses a phone together with the DHU. An Android Automotive
OS emulator tests a different, vehicle-installed app environment.

## 1. Install the Desktop Head Unit

In Android Studio:

1. Open **Tools > SDK Manager**.
2. Select the **SDK Tools** tab.
3. Enable **Android Auto Desktop Head Unit Emulator**.
4. Select **Apply** to install it.

The package is installed under the Android SDK at:

```text
extras/google/auto/
```

On Windows, the executable is normally:

```text
%ANDROID_SDK_ROOT%\extras\google\auto\desktop-head-unit.exe
```

For the current HTCommander Windows development environment, this resolves to:

```text
C:\Users\Default.DESKTOP-9CGK2DI\AppData\Local\Android\Sdk\extras\google\auto\desktop-head-unit.exe
```

## 2. Prepare the phone

1. Enable Android developer options on the phone.
2. Enable **USB debugging** under the phone's developer options.
3. Connect the phone to the computer by USB.
4. Unlock the phone and accept its USB debugging authorization prompt.
5. Open Android Auto settings. If Android Auto has no launcher icon, find its
   settings under **Settings > Connected devices > Connection preferences >
   Android Auto**. The exact path varies by phone vendor.
6. Scroll to the Android Auto version information and tap **Version** several
   times until Android Auto developer mode is enabled.
7. Open the overflow menu, select **Developer settings**, and enable **Unknown
   sources**. This allows the locally installed debug build to appear in the
   Android Auto launcher.
8. Return to Android Auto settings, select **Previously connected cars**, and
   ensure **Add new cars to Android Auto** is enabled.

Verify that ADB can see the phone:

```powershell
adb devices -l
```

The device must be listed as `device`, not `unauthorized`. If it is
unauthorized, unlock the phone and accept the debugging prompt.

## 3. Build and install HTCommander

From the repository's `src` directory, run HTCommander on the connected phone:

```powershell
Set-Location C:\code\HTCommander\src
flutter devices
flutter run
```

If more than one target is available, pass the phone ID shown by
`flutter devices`:

```powershell
flutter run -d <device-id>
```

Keep HTCommander running on the phone. Grant Bluetooth, location, notification,
and microphone permissions when prompted, then connect to a supported radio if
live channels and APRS messages are needed in the car interface.

## 4. Start an Android Auto session

On the phone:

1. Open Android Auto settings.
2. Open the overflow menu.
3. Select **Start head unit server**.
4. Confirm that Android shows a notification indicating the head unit server is
   running.

On Windows, forward the DHU connection through ADB and launch the DHU:

```powershell
adb forward tcp:5277 tcp:5277
& "$env:ANDROID_SDK_ROOT\extras\google\auto\desktop-head-unit.exe"
```

If `ANDROID_SDK_ROOT` is not set, use the full executable path shown in section
1. On macOS or Linux, launch `./desktop-head-unit` from the same SDK directory.

On the first connection, watch the phone for Android Auto terms, permissions,
or confirmation dialogs. The DHU might close while these are accepted; launch
it again afterward.

## 5. Open and exercise HTCommander

1. Open the Android Auto app launcher in the DHU.
2. Select **HTCommander**. It may be grouped with device-control or IoT apps.
3. Confirm that the preferred radio name and its channels appear.
4. Select a channel and verify that HTCommander requests the channel change.
5. Select **Messages** and verify that recent APRS messages appear.

The phone app supplies radio and message state to the car service. Leave it
running and connected while testing. If there is no active radio connection,
the empty-state prompt is expected.

## Alternative USB accessory connection

DHU 2.x can connect directly over the Android Open Accessory protocol:

```powershell
& "$env:ANDROID_SDK_ROOT\extras\google\auto\desktop-head-unit.exe" --usb
```

ADB tunneling is generally easier on Windows. Accessory mode can require a
WinUSB driver and may disrupt the existing ADB connection.

## Useful DHU tests

Enter these commands in the terminal where the DHU is running:

| Command | Purpose |
|---|---|
| `day` | Switch to day mode. |
| `night` | Switch to night mode. |
| `restrict none` | Simulate an unrestricted/parked state. |
| `restrict all` | Simulate driving restrictions. |
| `screenshot filename.png` | Save a screenshot. |
| `quit` | Close the DHU. |

To test a rotary-controller head unit instead of a touchscreen, launch with:

```powershell
& "$env:ANDROID_SDK_ROOT\extras\google\auto\desktop-head-unit.exe" -i rotary
```

The Android SDK also includes sample DHU display configurations under
`extras/google/auto/config/`. Pass one with `-c` to test layouts such as wide or
portrait displays.

## Troubleshooting

### HTCommander does not appear in the launcher

- Confirm the debug build is installed on the phone.
- Enable **Unknown sources** in Android Auto developer settings.
- Stop and restart the Android Auto head unit server.
- Close and reopen the DHU.
- Confirm the package is present with:

  ```powershell
  adb shell pm list packages com.meshcentral.htcommander
  ```

### DHU cannot connect

- Keep the phone unlocked for the initial connection.
- Confirm `adb devices -l` lists it as `device`.
- Restart **Start head unit server** on the phone.
- Recreate the forwarding rule:

  ```powershell
  adb forward --remove tcp:5277
  adb forward tcp:5277 tcp:5277
  ```

- Ensure no other DHU process is already using port 5277.

### DHU opens to a blank screen

Close the DHU, stop and restart the head unit server on the phone, and launch
the DHU again. Check the phone for a permission dialog. First-time setup can
require more than one DHU launch.

### The channel list is empty

Open HTCommander on the phone and connect a supported radio. The car screen
uses the preferred radio's current channel list and does not create test channel
data by itself.

### Inspect Android logs

Filter Logcat for the HTCommander package while reproducing the problem:

```powershell
adb logcat --pid=$(adb shell pidof -s com.meshcentral.htcommander)
```

## References

- [Test using the Desktop Head Unit](https://developer.android.com/training/cars/testing/dhu)
- [Use the Android for Cars App Library](https://developer.android.com/training/cars/apps/library)
- [Test Android apps for cars](https://developer.android.com/training/cars/testing)