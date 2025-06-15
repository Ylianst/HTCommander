# Handi-Talky Commander

This is a Amateur Radio (HAM Radio) tool for the UV-Pro, GA-5WB, VR-N76, VR-N7500 radios that works on Windows x64 with Bluetooth support. It allows for easy control over the radio with range of feature including channel programming, speech-to-text, text-to-speech, WinLink, APRS, terminal, torrent file transfer, BBS and more.

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/th-commander-3.png?raw=true)
An Amateur radio license is required to transmit using this software. You can get [information on a license here](https://www.arrl.org/getting-licensed).

****Download: [Windows x64 MSI Installer](https://github.com/Ylianst/HTCommander/raw/refs/heads/main/releases/HTCommander-0.28.msi)****

### Radio Support

The following radios should work with this application:

- BTech UV-Pro
- RadioOddity GA-5WB (untested)
- Vero VR-N76 (untested)
- Vero VR-N7500 (untested)

### Features

Handi-Talky Commander is starting to have a lot of features.

- [Bluetooth Audio](https://github.com/Ylianst/HTCommander/blob/main/docs/Bluetooth.md). Uses audio connectivity to listen and transmit with your computer speakers, microphone or headset.
- [Speech-to-Text](https://github.com/Ylianst/HTCommander/blob/main/docs/Voice.md). Open AI Whisper integration will convert audio to text, a Windows Speech API will convert text to speech.
- [Channel Programming](https://github.com/Ylianst/HTCommander/blob/main/docs/Channels.md). Configure, import, export and drag & drop channels to create the perfect configuration for your usages.
- [APRS support](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS.md). You can receive and sent APRS messages, set APRS routes, send [SMS message](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-SMS.md) to normal phones, request [weather reports](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-Weather.md), get details on each APRS message.
- [APRS map](https://github.com/Ylianst/HTCommander/blob/main/docs/Map.md). With Open Street Map support, you can see all the APRS stations at a glance.
- [Winlink mail support](https://github.com/Ylianst/HTCommander/blob/main/docs/Mail.md). Send and receive email on the [Winlink network](https://winlink.org/), this includes support to attachments.
- [Torrent file exchange](https://github.com/Ylianst/HTCommander/blob/main/docs/Torrent.md). Many-to-many file exchange with a torrent file transfer system over 1200 Baud FM-AFSK.
- [Address book](https://github.com/Ylianst/HTCommander/blob/main/docs/AddressBook.md). Store your APRS contacts and Terminal profiles in the address book to quick access.
- [Terminal support](https://github.com/Ylianst/HTCommander/blob/main/docs/Terminal.md). Use the terminal to communicate in packet modes with other stations, users or BBS'es.
- [BBS support](https://github.com/Ylianst/HTCommander/blob/main/docs/BBS.md). Built-in support for a BBS. Right now it's basic with WInLink and a text adventure game. Route emails and challenge your friends to get a high score over packet radio.
- [Packet Capture](https://github.com/Ylianst/HTCommander/blob/main/docs/Capture.md). Use this application to capture and decode packets with the built-in packet capture feature.

### Installation

Download the [MSI Installer](https://github.com/Ylianst/HTCommander/raw/refs/heads/main/releases/HTCommander-0.28.msi). Except for Open Street Map data, and checking for updates on GitHub, this tool does not sent data on the Internet. Pair your radio to your computer and run the application. If your computer does not have Bluetooth, you can get a inexpensive Bluetooth USB dongle. Make sure Bluetooth LE is supported. Pairing can be a bit tricky, you have to pair TWO Bluetooth devices in quick succession, [Bluetooth pairing instructions here](https://github.com/Ylianst/HTCommander/blob/main/docs/Paring.md).

### Demonstration

Quick introduction to HT Commander
[![HTCommander - Introduction](https://img.youtube.com/vi/JJ6E7fRQD7o/mqdefault.jpg)](https://www.youtube.com/watch?v=JJ6E7fRQD7o)

### Credits

This tool is based on the decoding work done by Kyle Husmann, KC3SLD and this [BenLink](https://github.com/khusmann/benlink) project which decoded the Bluetooth commands for these radios. Also [APRS-Parser](https://github.com/k0qed/aprs-parser) by Lee, K0QED.
