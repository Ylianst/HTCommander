# System Patterns - HTCommander

## Architecture Overview

HTCommander follows a **broker-based architecture** where a central Data Broker manages all communication between components. This decouples the various modules and provides a clean, event-driven design.

```
┌─────────────────────────────────────────────────────────────────┐
│                         MainForm                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ RadioPanel   │  │ Tab Controls │  │ Dialogs      │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│                    ┌──────▼──────┐                              │
│                    │ DataBroker  │                              │
│                    │  (Static)   │                              │
│                    └──────┬──────┘                              │
│                           │                                     │
│         ┌─────────────────┼─────────────────┐                   │
│         │                 │                 │                   │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌──────▼───────┐          │
│  │ Radio (HW)   │  │ Data Handlers│  │ Services     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Core Design Patterns

### 1. Data Broker Pattern (Publish-Subscribe)
The central communication mechanism using `DataBroker` and `DataBrokerClient`:

```csharp
// Publisher
DataBroker.Dispatch(deviceId, "EventName", data);

// Subscriber
broker.Subscribe(deviceId, "EventName", (devId, name, data) => {
    // Handle event
});
```

**Key Concepts:**
- **Device IDs**: Integer identifiers (0 = app settings, 100+ = radios)
- **Names**: String event/property names
- **Storage**: Optional persistence (device 0 uses Windows Registry)

### 2. Component Initialization Pattern
All tab controls follow a consistent initialization pattern:

```csharp
public partial class SomeTabUserControl : UserControl
{
    private DataBrokerClient broker;
    
    public void Initialize(MainForm parent)
    {
        broker = new DataBrokerClient();
        broker.Subscribe(deviceId, "EventName", OnEventHandler);
    }
    
    protected override void Dispose(bool disposing)
    {
        if (disposing) { broker?.Dispose(); }
        base.Dispose(disposing);
    }
}
```

### 3. Data Handler Pattern
For global services that process broker events:

```csharp
public class MyHandler : IDisposable
{
    private readonly DataBrokerClient _broker;
    
    public MyHandler()
    {
        _broker = new DataBrokerClient();
        _broker.Subscribe(DataBroker.AllDevices, "SomeEvent", OnEvent);
    }
    
    public void Dispose() { _broker?.Dispose(); }
}

// Registration
DataBroker.AddDataHandler("HandlerName", new MyHandler());
```

## Project Structure

```
src/
├── MainForm.cs                 # Main application window
├── Program.cs                  # Entry point
├── DataBroker.cs              # Central messaging (likely in Utils/)
│
├── Radio/                      # Radio hardware interaction
│   ├── Radio.cs               # Main radio class
│   ├── RadioBluetoothWin.cs   # Windows Bluetooth implementation
│   └── ...                    # Radio-related types
│
├── Controls/                   # Reusable UI controls
│   ├── ChatControl.cs
│   ├── AmplitudeHistoryBar.cs
│   └── ...
│
├── Dialogs/                    # Dialog windows
│   ├── SettingsForm.cs
│   ├── RadioConnectionForm.cs
│   └── ...
│
├── TabControls/                # Main tab page controls
│   ├── AprsTabUserControl.cs
│   ├── MapTabUserControl.cs
│   ├── VoiceTabUserControl.cs
│   ├── MailTabUserControl.cs
│   ├── TerminalTabUserControl.cs
│   ├── ContactsTabUserControl.cs
│   ├── BbsTabUserControl.cs
│   ├── TorrentTabUserControl.cs
│   └── PacketCaptureTabUserControl.cs
│
├── AprsParser/                 # APRS protocol parsing
│   ├── AprsPacket.cs
│   ├── Callsign.cs
│   └── ...
│
├── HamLib/                     # Amateur radio library
│   ├── AfskEncoder.cs         # Audio FSK encoding
│   ├── AfskDecoder.cs         # Audio FSK decoding
│   ├── Ax25Pad.cs            # AX.25 protocol
│   └── ...
│
├── WinLink/                    # WinLink email protocol
├── Sbc/                        # Single Board Computer support?
├── Utils/                      # Utility classes
├── Web/                        # Web server functionality
├── Adventurer/                 # Text adventure game
└── Docs/                       # Documentation
```

## Key Classes and Responsibilities

### MainForm
- Application entry point and main window
- Manages radio connections/disconnections
- Initializes all tab controls
- Handles menu actions
- Publishes `ConnectedRadios` list updates

### Radio
- Represents a connected Bluetooth radio
- Has a unique `DeviceId` (starting at 100)
- Manages connection state
- Registered as a DataHandler: `Radio_{deviceId}`

### DataBroker (Static)
- Central event bus
- Key/value storage with optional persistence
- Thread-safe with UI context support
- Manages data handlers

### DataBrokerClient
- Per-component broker interface
- Automatic subscription cleanup on dispose
- Convenience methods for logging

## Common Data Flow Patterns

### Radio Connection Flow
```
1. User clicks Connect → connectToolStripMenuItem_Click()
2. RadioBluetoothWin.FindCompatibleDevices() scans for radios
3. ConnectToRadio(mac, name) creates Radio instance
4. Radio registered: DataBroker.AddDataHandler("Radio_{id}", radio)
5. broker.Dispatch(1, "ConnectedRadios", radioList) notifies UI
6. RadioPanelControl subscribes and updates display
```

### Settings Persistence
```
1. User changes setting
2. DataBroker.Dispatch(0, "SettingName", value, store: true)
3. DataBroker stores in registry (Broker_{SettingName})
4. On restart, Initialize() loads from registry
```

### Cross-Component Communication
```
1. Component A dispatches: broker.Dispatch(deviceId, "EventName", data)
2. DataBroker notifies all matching subscribers
3. Component B receives via callback (on UI thread if context set)
```

## Threading Model
- UI operations on main thread (via `Control.BeginInvoke`)
- Bluetooth operations async (`Task.Run`, `async/await`)
- DataBroker callbacks marshalled to UI thread automatically
- Pipe server runs on background thread

## Naming Conventions
- **Device 0**: Application-wide settings (persisted to registry)
- **Device 1**: UI events and requests
- **Device 100+**: Connected radios
- **Event Names**: PascalCase (e.g., `RadioConnect`, `Volume`, `Settings`)
