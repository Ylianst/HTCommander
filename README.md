> [!NOTE]
> Official web site at: [https://ylianst.github.io/HTCommanderSite/](https://ylianst.github.io/HTCommanderSite/).

# Handi-Talky Commander

This is a Amateur Radio (HAM Radio) multiplatform tool for the EchoLink and UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600 radios that works on Windows, macOS, Linux, iOS, Android and web as long as you have Bluetooth support. It allows for easy control over the radio with range of feature including channel programming, APRS, WinLink, terminal, torrent file transfer, BBS and more. On some platforms you also have audio support along with speech-to-text and text-to-speech.

![image](https://github.com/Ylianst/HTCommanderEx/blob/main/docs/images/htcommander.png?raw=true)
An Amateur radio license is required to transmit using this software. You can get [information on a license here](https://www.arrl.org/getting-licensed).

### Radio Support

EchoLink and the following radios should work with this application:

- BTech UV-Pro, UV-50Pro
- Radioddity GA-5WB, DB50-B Mini
- Vero VR-N75, VR-N76, VR-N7500, VR-N7600
- Radtel RT-660

### Installation

- [Windows Installer (.msi)](https://github.com/Ylianst/HTCommander/releases/latest/download/HTCommander-x64.msi). Only runs on 64bit Windows 10 and 11.
- [macOS Installer (.dmg)](https://github.com/Ylianst/HTCommander/releases/latest/download/HTCommander.dmg). Universal binary.
- [Linux x64 (.tar.gz)](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-x64.tar.gz) | [.deb](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-x64.deb) | [.rpm](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-x64.rpm) | [.AppImage](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-x64.AppImage). Should work, please test and report.
- [Linux ARM64 (.tar.gz)](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-arm64.tar.gz) | [.deb](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-arm64.deb) | [.rpm](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-arm64.rpm) | [.AppImage](https://github.com/Ylianst/HTCommander/releases/latest/download/htcommander-linux-arm64.AppImage). Should work, please test and report.
- [Google Play](https://play.google.com/store/apps/details?id=com.meshcentral.htcommander) | [Android (.apk)](https://github.com/Ylianst/HTCommander/releases/latest/download/HTCommander.apk). Android 5.0 or higher.
- [Web Version](https://ylianst.github.io/HTCommanderWeb/). Browsers with Bluetooth support (Chrome & Edge).

### Features

Handi-Talky Commander has a lot of features. There are the features available on all platforms:

- [Channel Programming](https://ylianst.github.io/HTCommanderSite/features/channels.html). Configure, import, export and drag & drop channels to create the perfect configuration for your usages.
- [APRS support](https://ylianst.github.io/HTCommanderSite/features/aprs.html). You can receive and sent APRS messages, set APRS routes, send [SMS message](https://ylianst.github.io/HTCommanderSite/features/aprs.html#sms) to normal phones, request [weather reports](https://ylianst.github.io/HTCommanderSite/features/aprs.html#weather), send [authenticated messages](https://ylianst.github.io/HTCommanderSite/features/aprs.html#authentication), get details on each APRS message.
- [BSS support](https://ylianst.github.io/HTCommanderSite/features/bss.html). Support for the propriatary short message binary protocol from Baofeng / BTech.
- [APRS map](https://ylianst.github.io/HTCommanderSite/features/map.html). With Open Street Map support, you can see all the APRS stations at a glance.
- [Winlink mail support](https://ylianst.github.io/HTCommanderSite/features/winlink.html). Send and receive email on the [Winlink network](https://winlink.org/), this includes support to attachments.
- [Address book](https://ylianst.github.io/HTCommanderSite/features/address-book.html). Store your APRS, Winlink and Terminal contacts in the address book to quick access.
- [Terminal support](https://ylianst.github.io/HTCommanderSite/features/terminal.html). Communicate in packet mode with other stations, users or BBS'es.
- [BBS support](https://ylianst.github.io/HTCommanderSite/features/bbs.html). Built-in very basic BBS and acts as a Winlink gateway.
- [Packet Capture](https://ylianst.github.io/HTCommanderSite/features/capture.html). Use this application to capture and decode packets with the built-in packet capture feature.
- [GPS Support](https://ylianst.github.io/HTCommanderSite/features/gps.html). Support for the radio's built in GPS if you have radio firmware that supports it.
- [Torrent file exchange](https://ylianst.github.io/HTCommanderSite/features/torrent.html). Many-to-many file exchange with a torrent file transfer system over 1200 Baud FM-AFSK.

The following features are available on Windows, Linux, macOS, Android.

- [Bluetooth Audio](https://ylianst.github.io/HTCommanderSite/features/bluetooth-audio.html). Uses audio connectivity to listen and transmit with your computer speakers, microphone or headset.
- [SSTV](https://ylianst.github.io/HTCommanderSite/features/sstv.html) send and receive images. Reception is auto-detected, drag & drop to sent.

The following are for desktop platforms only: Windows, Linux, macOS.

- [Speech-to-Text](https://ylianst.github.io/HTCommanderSite/features/voice.html). Converts speech-to-text and text-to-speech.
- [AGWPE Protocol](https://ylianst.github.io/HTCommanderSite/features/agwpe.html). Supports routing other application's traffic over the radio using the AGWPE protocol.

### Technology Blog

Field notes and deep dives on the technology behind HTCommander — real-world findings, protocol reverse-engineering and DSP experiments. See the [HTCommander Technology Blog](https://github.com/Ylianst/HTCommander/blob/main/docs/blogs/README.md).

### Demonstration Video

This is a demonstration of the older Windows-only version of HTCommander.

[![HTCommander - Introduction](https://img.youtube.com/vi/JJ6E7fRQD7o/mqdefault.jpg)](https://www.youtube.com/watch?v=JJ6E7fRQD7o)

### Credits

This tool is based on the decoding work done by Kyle Husmann, KC3SLD and this [BenLink](https://github.com/khusmann/benlink) project which decoded the Bluetooth commands for these radios. Also [APRS-Parser](https://github.com/k0qed/aprs-parser) by Lee, K0QED.

Map data provided by [openstreetmap.org](https://openstreetmap.org), the project that creates and distributes free geographic data for the world.
