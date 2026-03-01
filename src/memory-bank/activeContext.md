# Active Context - HTCommander

## Current Session
- **Date**: March 1, 2026
- **Task**: GPS serial handler implementation

## Recent Activity
- Replaced `Gps/GpsSerialReader.cs` (standalone GpsTool console tool, wrong namespace/dependencies) with a proper Data Broker handler
- Created `Gps/GpsData.cs` — data class holding all GPS fix fields
- Created `Gps/GpsSerialHandler.cs` — Data Broker handler that reads/subscribes to GPS serial settings from device 0 and broadcasts parsed GPS data on device 1
- Registered `GpsSerialHandler` in `MainForm.cs` alongside other handlers

## Project State
- **Status**: Active development
- **Latest Commit**: 4a97331215bf1b57858a52c15564b0025d672293
- **Framework**: .NET 8.0 Windows Forms

## Key Files Recently Examined
1. `HTCommander.csproj` - Project configuration
2. `Docs/Overview.md` - Project description
3. `Docs/DataBroker.md` - Core architecture documentation
4. `MainForm.cs` - Main application window

## Current Understanding

### Architecture
The application uses a **Data Broker** pattern as its core architecture:
- Central publish-subscribe messaging system
- Device-based data organization
- Automatic thread marshalling for UI updates
- Registry persistence for application settings

### Main Components
- **MainForm**: Application shell with menu and tab container
- **RadioPanelControl**: Displays connected radio info
- **Tab Controls**: APRS, Map, Voice, Mail, Terminal, Contacts, BBS, Torrent, Packet Capture
- **Radio Class**: Represents Bluetooth-connected radios
- **DataBroker/DataBrokerClient**: Central messaging infrastructure
- **GpsSerialHandler**: Reads GPS serial port (settings from device 0), parses NMEA, dispatches `GpsData` on device 1
- **AirplaneHandler**: Polls Dump1090 for aircraft, dispatches airplane list on device 2+

### Radio Management
- Radios are identified by DeviceId (starting at 100)
- Support for multiple simultaneous radio connections
- Bluetooth discovery via `RadioBluetoothWin.FindCompatibleDevices()`
- Radios registered as data handlers: `Radio_{deviceId}`

## Working Notes
- The project has comprehensive documentation in `Docs/` folder
- Uses Windows-specific features (WinForms, Bluetooth, Registry)
- Includes text adventure game (Adventurer) as an Easter egg
- Memory bank initialized with core documentation

## GPS Handler Design (Device 1)
- Settings read from device 0: `"GpsSerialPort"` (string), `"GpsBaudRate"` (int)
- Subscribes to settings changes → restarts serial port on change
- Port config: 8N1, no handshake, DtrEnable/RtsEnable true
- Parses NMEA sentences: `$GPRMC`/`$GNRMC` and `$GPGGA`/`$GNGGA` (with checksum validation)
- Broadcasts `GpsData` object on `(1, "GpsData")` after each parsed sentence
- `GpsData` fields: Latitude, Longitude, Altitude, Speed, Heading, FixQuality, Satellites, IsFixed, GpsTime

## Open Questions
- None currently

## Next Steps
- GPS data (device 1, "GpsData") is now available for map display, APRS beaconing, etc.
