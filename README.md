# Handi-Talky Commander

This is a Amateur Radio (HAM Radio) multiplatform tool for the UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600 radios that works on Windows, macOS, Linux, iOS, Android and web as long as you have Bluetooth support. It allows for easy control over the radio with range of feature including channel programming, APRS, WinLink, terminal, torrent file transfer, BBS and more. On some platforms you also have audio support along with speech-to-text and text-to-speech.

![image](https://github.com/Ylianst/HTCommanderEx/blob/main/docs/images/htcommander.png?raw=true)
An Amateur radio license is required to transmit using this software. You can get [information on a license here](https://www.arrl.org/getting-licensed).

### Radio Support

The following radios should work with this application:

- BTech UV-Pro
- BTech UV-50Pro (untested)
- Radioddity GA-5WB (untested)
- Radioddity DB50-B Mini
- Radtel RT-660 (Contact Developers)
- Vero VR-N75
- Vero VR-N76 (untested)
- Vero VR-N7500 (untested)
- Vero VR-N7600

### Features

Handi-Talky Commander has a lot of features. There are the features available on all platforms.

- [Channel Programming](https://github.com/Ylianst/HTCommander/blob/main/docs/Channels.md). Configure, import, export and drag & drop channels to create the perfect configuration for your usages.
- [APRS support](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS.md). You can receive and sent APRS messages, set APRS routes, send [SMS message](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-SMS.md) to normal phones, request [weather reports](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-Weather.md), send [authenticated messages](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-Auth.md), get details on each APRS message.
- [BSS support](https://github.com/Ylianst/HTCommander/blob/main/docs/BSS-Protocol.md). Support for the propriatary short message binary protocol from Baofeng / BTech.
- [APRS map](https://github.com/Ylianst/HTCommander/blob/main/docs/Map.md). With Open Street Map support, you can see all the APRS stations at a glance.
- [Winlink mail support](https://github.com/Ylianst/HTCommander/blob/main/docs/Mail.md). Send and receive email on the [Winlink network](https://winlink.org/), this includes support to attachments.
- [Address book](https://github.com/Ylianst/HTCommander/blob/main/docs/AddressBook.md). Store your APRS, Winlink and Terminal contacts in the address book to quick access.
- [Terminal support](https://github.com/Ylianst/HTCommander/blob/main/docs/Terminal.md). Communicate in packet mode with other stations, users or BBS'es.
- [BBS support](https://github.com/Ylianst/HTCommander/blob/main/docs/BBS.md). Built-in very basic BBS and acts as a Winlink gateway.
- [Packet Capture](https://github.com/Ylianst/HTCommander/blob/main/docs/Capture.md). Use this application to capture and decode packets with the built-in packet capture feature.
- [GPS Support](https://github.com/Ylianst/HTCommander/blob/main/docs/GPS.md). Support for the radio's built in GPS if you have radio firmware that supports it.
- [Torrent file exchange](https://github.com/Ylianst/HTCommander/blob/main/docs/Torrent.md). Many-to-many file exchange with a torrent file transfer system over 1200 Baud FM-AFSK.

The following features are available on Windows, Linux, macOS, Android.

- [Bluetooth Audio](https://github.com/Ylianst/HTCommander/blob/main/docs/Bluetooth.md). Uses audio connectivity to listen and transmit with your computer speakers, microphone or headset.
- [SSTV](https://github.com/Ylianst/HTCommander/blob/main/docs/SSTV.md) send and receive images. Reception is auto-detected, drag & drop to sent.

The following are for desktop platforms only: Windows, Linux, macOS.

- [Speech-to-Text](https://github.com/Ylianst/HTCommander/blob/main/docs/Voice.md). Converts speech-to-text and text-to-speech.
- [AGWPE Protocol](https://github.com/Ylianst/HTCommander/blob/main/docs/Agwpe.md). Supports routing other application's traffic over the radio using the AGWPE protocol.

### Web Version

[HTCommander Web](https://ylianst.github.io/HTCommanderWeb/) will run on Chrome and Edge browsers. No audio support, but you can program channels, chat, send/receive APRS, Winlink and more.

### Installation

I am working on this as I release HTCommander on various platforms.

### Demonstration Video

This is a demonstration of the older Windows-only version of HTCommander.

[![HTCommander - Introduction](https://img.youtube.com/vi/JJ6E7fRQD7o/mqdefault.jpg)](https://www.youtube.com/watch?v=JJ6E7fRQD7o)

### Credits

This tool is based on the decoding work done by Kyle Husmann, KC3SLD and this [BenLink](https://github.com/khusmann/benlink) project which decoded the Bluetooth commands for these radios. Also [APRS-Parser](https://github.com/k0qed/aprs-parser) by Lee, K0QED.

Map data provided by [openstreetmap.org](https://openstreetmap.org), the project that creates and distributes free geographic data for the world.
