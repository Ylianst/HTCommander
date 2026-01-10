# Handi-Talky Commander

This is a Amateur Radio (HAM Radio) tool for some Bluetooth radios. It allows for easy control over the radio with range of feature including channel programming, speech-to-text, text-to-speech, WinLink, APRS, terminal, torrent file transfer, BBS and more.

## Overall Design

This application is a C# WinForm application. Because there are a lot of data flows to and from the radios, user controls, microphone, speakers, file system and more, the application is designed around a main data broker class that gets and dispatches data to and from various components. Each component implements a common interface to send and receive data from the broker.