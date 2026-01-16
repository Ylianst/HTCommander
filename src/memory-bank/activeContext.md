# Active Context - HTCommander

## Current Session
- **Date**: January 15, 2026
- **Task**: Memory bank initialization

## Recent Activity
- Initialized memory bank structure
- Analyzed project architecture and documented core patterns
- Created productContext.md with project overview
- Created systemPatterns.md with architecture documentation

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

## Open Questions
- None currently

## Next Steps
- Memory bank is initialized and ready for use
- Future sessions can reference these files for project context
