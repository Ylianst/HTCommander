# DataBroker Architecture

## Overview

The DataBroker is the central pub/sub messaging system for HTCommander. It enables decoupled communication between modules (radio services, APRS handler, BBS handler, etc.) and the UI layer. Components dispatch data to the broker, and UI widgets subscribe to receive updates.

```
┌─────────────────────────────────────────────────────────────────┐
│                        DataBroker                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              In-Memory Data Store                        │   │
│  │   (deviceId, name) → value                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Subscription Registry                       │   │
│  │   (deviceId, name, callback) per client                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Persistent Storage (deviceId=0)            │   │
│  │   SharedPreferences (cross-platform)                    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         ▲                                    │
         │ dispatch()                         │ callback
         │                                    ▼
┌────────┴───────┐                   ┌────────────────┐
│   Producers    │                   │   Subscribers  │
├────────────────┤                   ├────────────────┤
│ Radio Service  │                   │ CommsTab       │
│ APRS Handler   │                   │ AprsTab        │
│ BBS Handler    │                   │ RadioPanel     │
│ Comms Handler  │                   │ ChatWidget     │
│ Settings       │                   │ SettingsDialog │
└────────────────┘                   └────────────────┘
```

## Core Concepts

### Device IDs

Each piece of data is scoped to a **device ID**:

| Device ID | Purpose | Persistence |
|-----------|---------|-------------|
| `0` | Global settings and app-wide state | **Persisted** to local storage |
| `1` | Logging/system events | Not stored |
| `2+` | Connected radio devices | In-memory only |
| `-1` | Wildcard (subscribe to all devices) | N/A |

### Data Keys

Data is identified by a tuple of `(deviceId, name)`:

- `(0, "lastSelectedTab")` - Persisted setting
- `(0, "recentConnections")` - Persisted list
- `(1, "LogInfo")` - Transient log message
- `(2, "frequency")` - Radio device state
- `(2, "rssi")` - Radio signal strength

### Wildcard Subscriptions

Subscribers can use wildcards:
- `AllDevices` (`-1`): Receive updates from any device
- `AllNames` (`*`): Receive updates for any name on a device

## Components

### DataBroker (Static Singleton)

The main broker class provides static methods for all operations:

```dart
// Initialize at app startup
DataBroker.initialize('HTCommander');

// Dispatch data
DataBroker.dispatch(deviceId: 2, name: 'frequency', data: 446.00625);

// Get stored value
final freq = DataBroker.getValue<double>(deviceId: 2, name: 'frequency');

// Check existence
if (DataBroker.hasValue(deviceId: 0, name: 'lastTab')) { ... }
```

### DataBrokerClient (Per-Component Instance)

Each widget/service creates a client to manage its subscriptions:

```dart
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _broker = DataBrokerClient();
  
  @override
  void initState() {
    super.initState();
    _broker.subscribe(
      deviceId: 2, 
      name: 'frequency',
      callback: _onFrequencyChanged,
    );
  }
  
  void _onFrequencyChanged(int deviceId, String name, Object? data) {
    setState(() {
      _frequency = data as double?;
    });
  }
  
  @override
  void dispose() {
    _broker.dispose(); // Unsubscribes all automatically
    super.dispose();
  }
}
```

## API Reference

### DataBroker Static Methods

#### `initialize(String appName)`
Initializes the broker with persistent storage. Must be called once at app startup.

#### `dispatch({required int deviceId, required String name, required Object? data, bool store = true})`
Dispatches data to all matching subscribers.
- `store: true` (default): Stores the value for later retrieval
- `store: false`: Broadcast-only, value is not stored

#### `getValue<T>(int deviceId, String name, [T? defaultValue])`
Retrieves a stored value, with optional default.

#### `hasValue(int deviceId, String name)`
Returns `true` if a value exists for the key.

#### `removeValue(int deviceId, String name)`
Removes a value from storage.

#### `getDeviceValues(int deviceId)`
Returns all stored values for a device as a `Map<String, Object?>`.

#### `clearDevice(int deviceId)`
Removes all values for a device from storage.

#### `deleteDevice(int deviceId)`
Removes all values and notifies subscribers with `null` values.

#### `reset()`
Clears all data and subscriptions. Use with caution.

### DataBrokerClient Methods

#### `subscribe({required int deviceId, required String name, required DataCallback callback})`
Subscribes to data changes for a specific device/name combination.

#### `subscribeMultiple({required int deviceId, required List<String> names, required DataCallback callback})`
Subscribes to multiple names on the same device.

#### `subscribeAll({int? deviceId, required DataCallback callback})`
Subscribes to all names (optionally filtered by device).

#### `unsubscribe(int deviceId, String name)`
Removes a specific subscription.

#### `unsubscribeAll()`
Removes all subscriptions for this client.

#### `dispatch(...)`
Convenience method that delegates to `DataBroker.dispatch()`.

#### `getValue<T>(...)`
Convenience method that delegates to `DataBroker.getValue()`.

#### `logInfo(String message)`
Dispatches an info log message to device 1.

#### `logError(String message)`
Dispatches an error log message to device 1.

#### `dispose()`
Unsubscribes from all subscriptions. Must be called in widget's `dispose()`.

## Data Handlers

Data handlers are global service objects registered with the broker:

```dart
// Register a handler
DataBroker.addDataHandler('aprs', aprsHandler);

// Retrieve later
final aprs = DataBroker.getDataHandler<AprsHandler>('aprs');

// Remove (calls dispose if IDisposable)
DataBroker.removeDataHandler('aprs');
```

Events are dispatched when handlers are added/removed:
- `(0, "DataHandlerAdded", handlerName)`
- `(0, "DataHandlerRemoved", handlerName)`

## Persistence (Device ID 0)

Data dispatched to device ID 0 is automatically persisted to local storage:

### Supported Types

| Type | Storage Method |
|------|----------------|
| `int` | Direct storage |
| `String` | Direct storage |
| `bool` | Direct storage |
| `double` | JSON serialization |
| `List<T>` | JSON serialization |
| `Map<String, T>` | JSON serialization |
| Custom objects | JSON serialization (requires `fromJson`/`toJson`) |

### Lazy Loading

Values are loaded from storage on first access:
1. Check in-memory store
2. If not found and `deviceId == 0`, load from SharedPreferences
3. Cache in memory for subsequent access

### Empty Collection Protection

To prevent accidental data loss, empty collections are not persisted if non-empty data already exists in storage.

## Thread Safety

The DataBroker uses synchronization to ensure thread-safe operations:
- All data store operations are atomic
- Callbacks are invoked outside the lock to prevent deadlocks
- Subscription modifications are synchronized

## Usage Patterns

### Settings Pattern

```dart
// Save setting
_broker.dispatch(deviceId: 0, name: 'darkMode', data: true);

// Load setting with default
final darkMode = _broker.getValue<bool>(0, 'darkMode', false);
```

### Event Pattern (No Storage)

```dart
// Dispatch transient event
_broker.dispatch(deviceId: 1, name: 'packetReceived', data: packet, store: false);

// Subscribe to events
_broker.subscribe(deviceId: 1, name: 'packetReceived', callback: _onPacket);
```

### Device State Pattern

```dart
// Radio service updates state
DataBroker.dispatch(deviceId: radioId, name: 'connected', data: true);
DataBroker.dispatch(deviceId: radioId, name: 'frequency', data: 446.00625);
DataBroker.dispatch(deviceId: radioId, name: 'rssi', data: -65);

// UI subscribes to all radio state
_broker.subscribeAll(deviceId: radioId, callback: _onRadioStateChanged);
```

### Cleanup Pattern

```dart
// When device disconnects
DataBroker.deleteDevice(radioId);  // Notifies subscribers with null, then clears
```

## Common Data Keys

### Device 0 (Persistent Settings)

#### License Settings
| Name | Type | Description |
|------|------|-------------|
| `CallSign` | `String` | User's amateur radio call sign |
| `StationId` | `int` | Station ID (0-15, 0 = None) |
| `AllowTransmit` | `int` | Allow transmitting (0/1) |

#### APRS Settings
| Name | Type | Description |
|------|------|-------------|
| `AprsRoutes` | `String` | Pipe-separated routes: "Name\|Path\|Name\|Path..." |

#### Voice Settings
| Name | Type | Description |
|------|------|-------------|
| `VoiceLanguage` | `String` | Whisper language code (e.g., "auto", "en") |
| `VoiceModel` | `String` | Whisper model ID (e.g., "base.en") |
| `Voice` | `String` | Text-to-speech voice name |

#### Winlink Settings
| Name | Type | Description |
|------|------|-------------|
| `WinlinkPassword` | `String` | Winlink account password |
| `WinlinkUseStationId` | `int` | Use station ID for Winlink (0/1) |

#### Server Settings
| Name | Type | Description |
|------|------|-------------|
| `webServerEnabled` | `int` | Web server enabled (0/1) |
| `webServerPort` | `int` | Web server port (default 8080) |
| `agwpeServerEnabled` | `int` | AGWPE server enabled (0/1) |
| `agwpeServerPort` | `int` | AGWPE server port (default 8000) |

#### GPS/Map Settings
| Name | Type | Description |
|------|------|-------------|
| `GpsSerialPort` | `String` | GPS serial port name or "None" |
| `GpsBaudRate` | `int` | GPS baud rate (default 4800) |
| `AirplaneServer` | `String` | dump1090 server URL for airplane tracking |

#### Application State
| Name | Type | Description |
|------|------|-------------|
| `SelectedTabIndex` | `int` | Last selected tab index |
| `CheckForUpdates` | `int` | Auto-check for updates (0/1) |

#### Map State
| Name | Type | Description |
|------|------|-------------|
| `MapLatitude` | `String` | Map center latitude (stored as string for precision) |
| `MapLongitude` | `String` | Map center longitude (stored as string for precision) |
| `MapZoom` | `int` | Map zoom level (3-18) |
| `MapOfflineMode` | `int` | Offline mode enabled (0/1) |
| `MapShowTracks` | `int` | Show tracks on map (0/1) |
| `MapLargeMarkers` | `int` | Use large markers (0/1) |
| `MapTimeFilter` | `int` | Marker time filter in minutes (0 = all) |
| `ShowAirplanesOnMap` | `int` | Show airplane markers (0/1) |

### Device 1 (System Events)

| Name | Type | Description |
|------|------|-------------|
| `LogInfo` | `String` | Info log message |
| `LogError` | `String` | Error log message |
| `ConnectedRadios` | `List<Map>` | List of connected radios with DeviceId, MacAddress, FriendlyName, State |
| `RadioConnect` | `null` | Request to open radio connection dialog |
| `RadioConnectRequest` | `Map` | Request to connect to specific radio (MacAddress, FriendlyName) |
| `RadioDisconnectRequest` | `Map` | Request to disconnect radio (DeviceId or MacAddress) |
| `SelectedRadioDeviceId` | `int` | Currently selected radio device ID for UI |

### Device 100+ (Radio Devices)

Each connected radio gets a device ID starting at 100. The following keys are used per-radio:

| Name | Type | Description |
|------|------|-------------|
| `State` | `String` | Connection state: Disconnected, Connecting, Connected, UnableToConnect, AccessDenied, etc. |
| `HtStatus` | `RadioHtStatus` | Live radio status (RSSI, TX/RX state, current channel, GPS lock, etc.) |
| `Settings` | `RadioSettings` | Radio configuration (channel_a, channel_b, scan, squelch, etc.) |
| `Channels` | `List<RadioChannelInfo>` | List of programmed channels with frequencies and names |
| `FriendlyName` | `String` | Bluetooth friendly name of the radio |
| `GpsEnabled` | `bool` | Whether GPS is enabled on the radio |
| `Position` | `RadioPosition` | GPS position (latitude, longitude, altitude, locked state) |
| `LockState` | `RadioLockState` | Lock state for exclusive operations (IsLocked, Usage) |
| `ChannelChangeVfoA` | `int` | Command to change VFO A to specified channel ID |
| `ChannelChangeVfoB` | `int` | Command to change VFO B to specified channel ID |

## Implementation Notes

### Flutter-Specific Considerations

1. **UI Thread**: Callbacks are always invoked on the main isolate since Flutter is single-threaded for UI.

2. **SharedPreferences**: Used for cross-platform persistence (iOS, Android, macOS, Windows, Linux, Web).

3. **JSON Serialization**: Complex types use `dart:convert` for serialization.

4. **Lifecycle**: Widgets must call `client.dispose()` in their `dispose()` method.

### Migration from C# Reference

| C# | Flutter |
|----|---------|
| `RegistryHelper` | `SharedPreferences` |
| `Control.BeginInvoke()` | Not needed (single UI thread) |
| `lock` / `Monitor` | Not needed for UI-only access |
| `IDisposable` | Manual `dispose()` pattern |
