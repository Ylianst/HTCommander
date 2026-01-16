# Product Context - HTCommander

## Overview
HTCommander (Handi-Talky Commander) is a Windows desktop application for amateur radio (HAM Radio) enthusiasts. It provides comprehensive control and communication features for Bluetooth-enabled handheld radios.

## Problem Statement
Amateur radio operators need a unified software solution to:
- Control and program Bluetooth-connected handheld radios
- Communicate using various digital modes (APRS, WinLink, BBS)
- Transfer files over radio links
- Manage contacts and messages
- Visualize audio signals and radio activity

## Target Users
- Amateur radio (HAM) operators
- Users of Bluetooth-enabled handheld radios (HTs)
- Those requiring digital mode communications (APRS, WinLink)

## Key Features
1. **Radio Control**
   - Bluetooth connectivity to compatible radios
   - Channel programming and management
   - Multi-radio support (connect multiple radios simultaneously)
   - Dual-watch, scan, GPS, and region settings

2. **Voice Features**
   - Speech-to-text (using Whisper.net)
   - Text-to-speech (using System.Speech)
   - Audio clip management
   - Spectrogram visualization

3. **Digital Communications**
   - APRS (Automatic Packet Reporting System)
   - WinLink email over radio
   - BBS (Bulletin Board System)
   - Terminal mode

4. **Data Transfer**
   - Torrent-style file transfer over radio
   - YAPP file transfer protocol

5. **Mapping & Location**
   - GPS integration
   - Map display (GMap.NET)
   - Station location tracking

6. **Additional Features**
   - Channel import from CSV files
   - Packet capture and analysis
   - Contact management
   - Auto-update functionality
   - Text adventure game (Adventurer)

## Technology Stack
- **Framework**: .NET 8.0 Windows Forms
- **Platform**: Windows 10+ (10.0.19041.0 minimum)
- **Language**: C#
- **Key Libraries**:
  - NAudio (audio processing)
  - Whisper.net (speech recognition)
  - GMap.NET.WinForms (mapping)
  - InTheHand.Net.Bluetooth (Bluetooth connectivity)
  - System.Data.SQLite (local storage)
  - Spectrogram (audio visualization)

## Architecture
The application uses a centralized **Data Broker** pattern for component communication:
- Publish-subscribe messaging system
- Device-based data organization (device IDs)
- Automatic UI thread marshalling
- Registry persistence for application settings (device 0)
- Thread-safe operations

## Repository
- GitHub: https://github.com/Ylianst/HTCommander.git
- License: Apache License 2.0

## Building the Project
To build the project from the command line:

```bash
# Navigate to the src directory
cd c:\Code\HTCommander\src

# Build the project (specify the .csproj file since there are multiple projects)
dotnet build HTCommander.csproj

# Or for a release build
dotnet build HTCommander.csproj -c Release

# Build without restoring packages (faster if packages already restored)
dotnet build HTCommander.csproj --no-restore
```

**Note**: The project must be built specifying `HTCommander.csproj` explicitly because the `src` folder contains multiple project/solution files.
