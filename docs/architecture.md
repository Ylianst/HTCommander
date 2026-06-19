# Architecture Overview

## Application Structure

HTCommander is a Flutter desktop application with a tabbed interface. The main window contains a radio panel on the left and a vertical tab bar on the right side.

```
┌─────────────────────────────────────────────────────────┐
│  Menu Bar                                               │
├──────────┬───────────────────────────────────────┬──────┤
│          │                                       │[Voice│
│  Radio   │                                       │[APRS]│
│  Panel   │                                       │[Map] │
│          │         Tab Content                   │[Mail]│
│  ┌────┐  │                                       │[Term]│
│  │    │  │                                       │[Cntct│
│  │ 📻 │  │                                       │[BBS] │
│  │    │  │                                       │[Trnt]│
│  └────┘  │                                       │[Pkts]│
│          │                                       │[Debug│
│ [Connect]│                                       │      │
│ Channels │                                       │      │
└──────────┴───────────────────────────────────────┴──────┘
```

## Key Components

### Main Entry Point (`main.dart`)

- Initializes window manager for desktop
- Sets minimum window size (550x600)
- Creates the main `HTCommanderApp` widget
- Handles multi-window support via `SubWindowApp`

### Window Service (`services/window_service.dart`)

Singleton service managing detached windows:
- `createWindow(tabName, tabContent)` - Opens tab in new window
- `closeAllWindows()` - Closes all child windows
- Tracks active windows by ID

### Radio Panel (`widgets/radio_panel.dart`)

Displays the radio hardware representation:
- Radio image with overlay controls
- VFO A/B frequency display
- RSSI signal strength indicator
- Channel list with context menu
- Connection state management

## State Management

Currently uses local `StatefulWidget` state. Each tab manages its own state independently.

### Connection Flow

```
Disconnected → Connecting → Connected
     ↑              │            │
     └──────────────┴────────────┘
              (on error/disconnect)
```

## Multi-Window Architecture

Tabs can be "detached" into separate windows:

```dart
// In main.dart menu
PopupMenuItem(
  value: 'detach_voice',
  child: Text('Detach Voice Tab'),
)

// Handler creates new window
WindowService().createWindow('Voice', const VoiceTab());
```

Child windows:
- Run as separate Flutter instances
- Receive tab name via window arguments
- Have minimum size enforced (550x600)
- Can be closed independently

## Data Flow (Planned)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   UV-Pro    │────▶│   Service    │────▶│    UI       │
│   Radio     │     │   Layer      │     │  (Widgets)  │
└─────────────┘     └──────────────┘     └─────────────┘
       │                  │
       │            ┌─────┴─────┐
   BT Classic       ▼           ▼
   or BLE     ┌─────────┐ ┌─────────┐
              │  APRS   │ │  BBS    │
              │ Service │ │ Service │
              └─────────┘ └─────────┘
```

## Platform Support

| Platform | Status | Bluetooth | UI Mode | Notes |
|----------|--------|-----------|---------|-------|
| macOS | Primary | Classic | Desktop | Full data + audio support |
| Windows | Planned | Classic | Desktop | Full data + audio support |
| Linux | Planned | Classic | Desktop | Full data + audio support |
| iOS | Planned | Classic | Mobile | Full data + audio, simplified UI |
| Android | Planned | Classic | Mobile | Full data + audio, simplified UI |
| Web | Limited | BLE | Responsive | Data commands only, no audio |

## Desktop vs Mobile UI

The application adapts its UI based on platform:

### Desktop UI (macOS, Windows, Linux)
- Menu bar with application options
- Tabs can be detached into separate windows
- Radio panel always visible on left side (when wide enough)
- Vertical tab bar on right side
- Keyboard shortcuts available

### Compact Mode (Narrow windows & Mobile)
When the application window is narrow (below a threshold width), the UI switches to "compact mode":
- Radio panel is hidden from the left side
- Radio becomes a tab in the tab bar
- Same UI works for both narrow desktop windows and mobile devices
- Allows seamless transition between wide and narrow layouts

This responsive design means the same codebase works across all form factors without separate mobile/desktop implementations.

### Mobile UI (iOS, Android)
- Runs in compact mode by default (radio as tab)
- No menu bar - all options accessible from tabs
- Tabs cannot be detached (single window only)
- Touch-optimized controls
- Options typically in overflow menus or tab-specific toolbars

### Desktop Mode on Mobile (Android with external display)
Some Android devices (Google Pixel 8+, Samsung DeX, etc.) support connecting to external displays with mouse and keyboard. When detected, HTCommander can switch to a desktop-like UI:
- Larger window with desktop layout
- Mouse and keyboard input support
- Potentially enable tab detachment if windowing is supported
- Menu bar or toolbar with full options
- Radio panel visible alongside tab content (exits compact mode)

The app should detect external display connection and offer to switch UI modes.

```
Wide Layout (Desktop):             Compact/Narrow Layout:
┌────────┬─────────────┬─────┐    ┌─────────────────┬─────┐
│ Menu   │             │     │    │ Menu            │     │
├────────┤             │Tabs │    ├─────────────────┤     │
│ Radio  │  Content    │     │    │                 │     │
│ Panel  │             │     │    │    Content      │Tabs │
│        │             │     │    │                 │(+📻)│
│        │             │     │    │                 │     │
└────────┴─────────────┴─────┘    └─────────────────┴─────┘
```

## Bluetooth Connectivity

The target radio (UV-Pro) supports two Bluetooth modes:

### Bluetooth Classic (Desktop + Mobile)
- **Data**: Full command/response protocol
- **Audio**: Streaming audio for voice communication
- Used on macOS, Windows, Linux, iOS, Android

### Bluetooth Low Energy (Web)
- **Data**: Command/response protocol only
- **Audio**: Not supported over BLE
- Uses Web Bluetooth API in browser
- Limited to data operations (channel config, APRS, messaging)

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Desktop    │  │    Mobile    │  │     Web      │
│   App        │  │     App      │  │   Browser    │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       │ BT Classic      │ BT Classic      │ BLE
       │ (Data + Audio)  │ (Data + Audio)  │ (Data only)
       │                 │                 │
       └────────┬────────┴────────┬────────┘
                │                 │
         ┌──────▼──────┐   ┌──────▼──────┐
         │   UV-Pro    │   │   UV-Pro    │
         │   Radio     │   │   Radio     │
         └─────────────┘   └─────────────┘
```

## File Organization Conventions

```
lib/
├── main.dart           # Entry point only
├── dialogs/            # Modal dialog boxes
│   └── *_dialog.dart
├── services/           # Business logic, no UI
│   └── *_service.dart
├── widgets/            # Reusable UI components
│   └── *_tab.dart      # Tab content widgets
│   └── *_widget.dart   # Other widgets
└── models/             # Data classes (planned)
    └── *.dart
```

## Porting from C# Reference

The `reference/HTCommander/` folder contains the original C# source:

| C# Location | Flutter Equivalent |
|-------------|-------------------|
| `src/TabControls/*TabUserControl.cs` | `lib/widgets/*_tab.dart` |
| `src/Dialogs/*.cs` | `lib/dialogs/*_dialog.dart` |
| `src/RadioControls/RadioPanelControl.cs` | `lib/widgets/radio_panel.dart` |
| `src/Resources/*.png` | `assets/images/` |

### Porting Checklist

1. Read C# `.cs` and `.Designer.cs` files
2. Identify UI layout and controls
3. Map to Flutter equivalents
4. Implement state management
5. Port event handlers to callbacks
6. Test across platforms
