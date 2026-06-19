# HTCommander Documentation

HTCommander (Handi-Talkie Commander) is a Flutter desktop application for controlling amateur radio handhelds via Bluetooth. This is a port of the original C# Windows application to cross-platform Flutter.

## Documentation Index

- [Architecture Overview](architecture.md) - High-level app structure
- [Creating Dialogs](dialogs.md) - How to create dialog boxes
- [Widget Guide](widgets.md) - Tab widgets and UI components

## Project Structure

```
lib/
├── main.dart              # App entry point, main window, tab navigation
├── dialogs/               # Dialog boxes
│   ├── dialogs.dart       # Barrel export file
│   ├── dialog_utils.dart  # Common dialog utilities and base classes
│   └── about_dialog.dart  # About dialog
├── services/              # Business logic services
│   └── window_service.dart # Multi-window management
└── widgets/               # UI components
    ├── radio_panel.dart   # Radio display with VFO controls
    ├── voice_tab.dart     # Voice communication tab
    ├── aprs_tab.dart      # APRS messaging tab
    ├── map_tab.dart       # Map display tab
    ├── mail_tab.dart      # Email tab
    ├── terminal_tab.dart  # Terminal/console tab
    ├── contacts_tab.dart  # Contact list tab
    ├── bbs_tab.dart       # BBS messaging tab
    ├── torrent_tab.dart   # File transfer tab
    ├── packets_tab.dart   # Packet capture tab
    ├── chat_widget.dart   # Chat message display
    └── debug_tab.dart     # Debug/logging tab
```

## Building

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## Dependencies

- `desktop_multi_window` - Multi-window support for detaching tabs
- `window_manager` - Window title and size control
- `url_launcher` - Opening external links

## Reference

The `reference/` folder contains the original C# HTCommander source code for reference during porting.
