# Data Broker System

The Data Broker is a centralized messaging and state management system for HTCommander. It allows components to communicate with each other without direct dependencies, following a publish-subscribe pattern.

## Overview

The system consists of two main classes:

- **`DataBroker`** - A static global broker that manages data storage, subscriptions, and message dispatching
- **`DataBrokerClient`** - A per-component client that simplifies subscription management with automatic cleanup on disposal

## Key Concepts

### Device IDs
Each piece of data is associated with a device ID (integer). This allows you to:
- Store data specific to individual radios/devices (device 1, 2, 3, etc.)
- Store application-wide settings using device 0 (with registry persistence)
- Subscribe to events from all devices using `DataBroker.AllDevices` (-1)

### Names
Data is also keyed by a string name (e.g., "Volume", "Frequency", "RadioStatus"). You can:
- Subscribe to a specific name
- Subscribe to multiple names at once
- Subscribe to all names using `DataBroker.AllNames` ("*")

### Storage vs Broadcast
When dispatching data, you can choose to:
- **Store and broadcast** (`store: true`, default) - Data is saved in the broker and all subscribers are notified
- **Broadcast only** (`store: false`) - Subscribers are notified but data is not stored (useful for transient events)

### Registry Persistence
Values dispatched to **device 0** that are `int` or `string` types are automatically saved to the Windows registry and restored on application restart. Registry keys are prefixed with "Broker_" to avoid conflicts.

## Initialization

Initialize the broker early in your application (typically in `Program.cs` or `MainForm` constructor):

```csharp
// Basic initialization
DataBroker.Initialize("HTCommander");

// With UI context for automatic thread marshalling
DataBroker.Initialize("HTCommander", this); // 'this' is the main form
```

The UI context is optional but recommended. When set, callbacks are automatically invoked on the UI thread using `Control.BeginInvoke`, preventing cross-thread exceptions when updating UI elements.

## DataBroker Static Methods

### Constants

```csharp
public const int AllDevices = -1;   // Subscribe to all device IDs
public const string AllNames = "*"; // Subscribe to all names
```

### Dispatch

Send data to the broker and notify subscribers:

```csharp
// Store and broadcast (default)
DataBroker.Dispatch(int deviceId, string name, object data);

// Broadcast only (don't store)
DataBroker.Dispatch(int deviceId, string name, object data, bool store = false);
```

**Examples:**
```csharp
// Store volume for device 1
DataBroker.Dispatch(1, "Volume", 75);

// Store callsign in device 0 (will persist to registry)
DataBroker.Dispatch(0, "Callsign", "W1ABC");

// Broadcast PTT event without storing
DataBroker.Dispatch(2, "PTTPressed", true, store: false);
```

### GetValue

Retrieve a stored value with optional default:

```csharp
// Generic version (recommended)
T GetValue<T>(int deviceId, string name, T defaultValue = default);

// Object version
object GetValue(int deviceId, string name, object defaultValue = null);
```

**Examples:**
```csharp
// Get volume with default of 50
int volume = DataBroker.GetValue<int>(1, "Volume", 50);

// Get callsign with default empty string
string callsign = DataBroker.GetValue<string>(0, "Callsign", "");

// Check if exists first
if (DataBroker.HasValue(1, "Volume"))
{
    int vol = DataBroker.GetValue<int>(1, "Volume");
}
```

### HasValue

Check if a value exists in the broker:

```csharp
bool exists = DataBroker.HasValue(int deviceId, string name);
```

### RemoveValue

Remove a stored value:

```csharp
bool removed = DataBroker.RemoveValue(int deviceId, string name);
```

Note: For device 0, this also removes the value from the registry.

### GetDeviceValues

Get all stored values for a specific device:

```csharp
Dictionary<string, object> values = DataBroker.GetDeviceValues(int deviceId);
```

### ClearDevice

Clear all stored data for a specific device:

```csharp
DataBroker.ClearDevice(int deviceId);
```

### SetUIContext

Update the UI context for thread marshalling:

```csharp
DataBroker.SetUIContext(Control uiContext);
```

### Reset

Clear all stored data and subscriptions (use with caution):

```csharp
DataBroker.Reset();
```

## DataBrokerClient

The `DataBrokerClient` class provides a convenient way for components to interact with the broker. When disposed, all subscriptions are automatically removed.

### Creating a Client

```csharp
private DataBrokerClient broker;

public void Initialize()
{
    broker = new DataBrokerClient();
    // ... set up subscriptions
}
```

### Subscribing to Events

```csharp
// Subscribe to a specific device and name
broker.Subscribe(int deviceId, string name, Action<int, string, object> callback);

// Subscribe to a specific device and multiple names
broker.Subscribe(int deviceId, string[] names, Action<int, string, object> callback);

// Subscribe to all names for a device
broker.SubscribeAll(int deviceId, Action<int, string, object> callback);

// Subscribe to everything
broker.SubscribeAll(Action<int, string, object> callback);
```

**Examples:**
```csharp
// Subscribe to RadioStatus from all devices
broker.Subscribe(DataBroker.AllDevices, "RadioStatus", OnRadioStatusChanged);

// Subscribe to multiple properties for device 1
broker.Subscribe(1, new[] { "Volume", "Frequency", "Squelch" }, OnPropertyChanged);

// Subscribe to all events from device 2
broker.SubscribeAll(2, OnDevice2Event);

// Callback signature
private void OnRadioStatusChanged(int deviceId, string name, object data)
{
    // deviceId: the device that sent the event
    // name: the property name (e.g., "RadioStatus")
    // data: the value (cast to appropriate type)
    bool isOnline = (bool)data;
}
```

### Unsubscribing

```csharp
// Unsubscribe from a specific subscription
broker.Unsubscribe(int deviceId, string name);

// Unsubscribe from all subscriptions
broker.UnsubscribeAll();
```

### Dispatching and Getting Values

The client provides convenience methods that call through to the static broker:

```csharp
// Dispatch data
broker.Dispatch(int deviceId, string name, object data, bool store = true);

// Get values
T value = broker.GetValue<T>(int deviceId, string name, T defaultValue = default);
object value = broker.GetValue(int deviceId, string name, object defaultValue = null);
bool exists = broker.HasValue(int deviceId, string name);
```

### Disposal

Always dispose the client when your component is destroyed:

```csharp
public class MyUserControl : UserControl
{
    private DataBrokerClient broker;

    public void Initialize()
    {
        broker = new DataBrokerClient();
        broker.Subscribe(1, "Volume", OnVolumeChanged);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            broker?.Dispose(); // Auto-unsubscribes all
        }
        base.Dispose(disposing);
    }
}
```

## Complete Example

Here's a complete example showing how to use the data broker in a user control:

```csharp
public class VolumeControl : UserControl
{
    private DataBrokerClient broker;
    private TrackBar volumeSlider;

    public void Initialize(int deviceId)
    {
        broker = new DataBrokerClient();
        
        // Subscribe to volume changes
        broker.Subscribe(deviceId, "Volume", OnVolumeChanged);
        
        // Load current value
        int currentVolume = broker.GetValue<int>(deviceId, "Volume", 50);
        volumeSlider.Value = currentVolume;
    }

    private void OnVolumeChanged(int deviceId, string name, object data)
    {
        // Update UI (already on UI thread if UIContext was set)
        if (data is int volume)
        {
            volumeSlider.Value = volume;
        }
    }

    private void volumeSlider_ValueChanged(object sender, EventArgs e)
    {
        // Dispatch the new volume
        broker.Dispatch(1, "Volume", volumeSlider.Value);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            broker?.Dispose();
        }
        base.Dispose(disposing);
    }
}
```

## Thread Safety

The Data Broker is fully thread-safe:
- All internal data structures are protected by locks
- Callbacks are invoked outside the lock to prevent deadlocks
- If a UI context is set, callbacks are marshalled to the UI thread using `BeginInvoke`
- Exceptions in callbacks are caught and swallowed to prevent broker failure

## Data Handlers

Data handlers are global objects that can be registered with the broker to process data. They are useful for creating reusable components that react to broker events, such as logging to files, sending data to external services, or performing background processing.

### Adding a Data Handler

```csharp
// Add a data handler with a unique name
DataBroker.AddDataHandler(string name, object handler);
```

**Example:**
```csharp
// Create and register a log file handler
var logHandler = new LogFileHandler("debug.log");
DataBroker.AddDataHandler("DebugLogFile", logHandler);
```

### Getting a Data Handler

```csharp
// Get by name (returns object)
object handler = DataBroker.GetDataHandler(string name);

// Get with type casting (recommended)
T handler = DataBroker.GetDataHandler<T>(string name);
```

**Example:**
```csharp
var logHandler = DataBroker.GetDataHandler<LogFileHandler>("DebugLogFile");
if (logHandler != null)
{
    logHandler.Write("DEBUG", "Custom message");
}
```

### Checking if a Handler Exists

```csharp
bool exists = DataBroker.HasDataHandler(string name);
```

### Removing a Data Handler

When a handler is removed, `Dispose()` is automatically called if the handler implements `IDisposable`:

```csharp
bool removed = DataBroker.RemoveDataHandler(string name);
```

### Removing All Handlers

```csharp
DataBroker.RemoveAllDataHandlers();
```

### Data Handler Events

The broker dispatches events when handlers are added or removed. Subscribe to these on device 0:

```csharp
broker.Subscribe(0, new[] { "DataHandlerAdded", "DataHandlerRemoved" }, OnHandlerChanged);

private void OnHandlerChanged(int deviceId, string name, object data)
{
    string handlerName = (string)data;
    if (name == "DataHandlerAdded")
    {
        Console.WriteLine($"Handler added: {handlerName}");
    }
    else if (name == "DataHandlerRemoved")
    {
        Console.WriteLine($"Handler removed: {handlerName}");
    }
}
```

### Creating a Custom Data Handler

A data handler is any class that processes broker events. Implement `IDisposable` for proper cleanup:

```csharp
public class MyDataHandler : IDisposable
{
    private readonly DataBrokerClient _broker;
    private bool _disposed = false;

    public MyDataHandler()
    {
        _broker = new DataBrokerClient();
        
        // Subscribe to events you want to process
        _broker.Subscribe(DataBroker.AllDevices, "SomeEvent", OnSomeEvent);
    }

    private void OnSomeEvent(int deviceId, string name, object data)
    {
        if (_disposed) return;
        // Process the event...
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _broker?.Dispose(); // Unsubscribes automatically
            _disposed = true;
        }
    }
}
```

### Built-in LogFileHandler

HTCommander includes a `LogFileHandler` class that writes `LogInfo` and `LogError` messages to a file:

```csharp
// Create and register the handler
var logHandler = new LogFileHandler("app.log", append: true);
DataBroker.AddDataHandler("AppLog", logHandler);

// Now all LogInfo/LogError calls are written to file
broker.LogInfo("Application started");
broker.LogError("Connection failed");

// When done, remove it (auto-closes the file)
DataBroker.RemoveDataHandler("AppLog");
```

**Log file format:**
```
[2025-01-10 11:35:00.123] [INFO] Log file opened: 2025-01-10 11:35:00
[2025-01-10 11:35:01.456] [INFO] Application started
[2025-01-10 11:35:02.789] [ERROR] Connection failed
[2025-01-10 11:36:00.000] [INFO] Log file closed: 2025-01-10 11:36:00
```

**LogFileHandler properties:**
- `FilePath` - The path to the log file
- `IsDisposed` - Whether the handler has been disposed

**LogFileHandler methods:**
- `Write(string level, string message)` - Write a custom log entry
- `Flush()` - Flush the file buffer

## Logging

The `DataBrokerClient` provides convenience methods for logging:

```csharp
// Log an informational message (dispatched to device 0, "LogInfo")
broker.LogInfo(string msg);

// Log an error message (dispatched to device 0, "LogError")
broker.LogError(string msg);
```

These messages are broadcast-only (`store: false`) and can be received by any subscriber or data handler listening for `LogInfo` and `LogError` on device 0.

## Best Practices

1. **Always dispose clients** - Use the `Dispose` pattern to ensure subscriptions are cleaned up
2. **Use meaningful names** - Choose descriptive names for your data keys (e.g., "RadioVolume" instead of "Vol")
3. **Use device 0 for app settings** - Application-wide settings stored in device 0 automatically persist to registry
4. **Use broadcast-only for transient events** - Set `store: false` for events that don't need to be stored (like button presses)
5. **Set UI context early** - Initialize with a UI context to avoid cross-thread exceptions
6. **Use typed GetValue<T>** - Prefer the generic version for type safety
7. **Provide defaults** - Always provide sensible default values when calling GetValue
8. **Implement IDisposable for handlers** - Data handlers should implement `IDisposable` for proper cleanup when removed
9. **Use unique handler names** - Each data handler must have a unique name; `AddDataHandler` returns false if the name already exists
