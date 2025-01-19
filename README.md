# Handi-Talky Commander

This is a Amateur Radio (HAM Radio) tool for the UV-Pro, GA-5WB, VR-N76, VR-N7500 radios that works on Windows 11 with Bluetooth LE support. It allows for easy control over the radio over Bluetooth and doing APRS messaging. This is an early preview version with the goal for it to support BBS's, WinLink and more.

![image](https://github.com/user-attachments/assets/ad3e0c3e-f5f5-4b07-9217-2306f07c362f)

Note that a Amateur radio license is required to transmit using this software. You can get [information on a license here](https://www.arrl.org/getting-licensed).

### Radio Support

The following radios should work with this application:

- BTech UV-Pro
- RadioOddity GA-5WB (untested)
- Vero VR-N76 (untested)
- Vero VR-N7500 (untested)

### Features

This first version is focused on getting APRS working well along with control over the radio's channels. The APRS messaging will show messages more as you would expect them from a messaging application. You can right click on a APRS message to get more details and filter APRS messaging to not display telemetry messages. Stations with location data will be shown on the open street map tab. There is also another tab with all packets received making this tool work like a packet capture tool.

### Installation

There are no installer, just [download the zip file](https://github.com/Ylianst/HTCommander/raw/refs/heads/main/releases/HTCommander-0.1.zip), extract and run. Except for Open Street Map data, this tool does not access the internet.

### Credits

This tool is based on the decoding work done by [Kyle Husmann](https://github.com/khusmann) and his BenLink project which decoded the Bluetooth commands for these radios. Also [APRS-Parser](https://github.com/k0qed/aprs-parser) by Lee, K0QED.
