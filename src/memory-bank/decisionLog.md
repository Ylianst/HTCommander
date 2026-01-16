# Decision Log - HTCommander

This document tracks significant technical and architectural decisions made during development.

---

## Decision Template
```
### [Decision Title]
- **Date**: YYYY-MM-DD
- **Status**: Proposed | Accepted | Deprecated | Superseded
- **Context**: What prompted this decision?
- **Decision**: What was decided?
- **Alternatives Considered**: What other options were evaluated?
- **Consequences**: What are the implications of this decision?
```

---

## Architectural Decisions

### ADR-001: Data Broker Architecture
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: The application needs to manage data flow between multiple components including radios, UI controls, file system, microphone, speakers, and more. Direct component-to-component communication would create tight coupling and complex dependencies.
- **Decision**: Implement a centralized Data Broker system using publish-subscribe pattern. All components communicate through the broker rather than directly with each other.
- **Alternatives Considered**:
  - Direct event handlers between components
  - Observable pattern with individual subjects
  - Message queue system
- **Consequences**:
  - Pros: Loose coupling, easy to add new components, centralized state management, thread-safe communication
  - Cons: Indirect communication can be harder to trace, potential for message overhead

### ADR-002: Device ID Scheme
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need a way to identify different data sources/targets in the broker system.
- **Decision**: Use integer device IDs with conventions:
  - Device 0: Application-wide settings (persisted to Windows Registry)
  - Device 1: UI events and requests
  - Device 100+: Connected radios (auto-assigned starting at 100)
- **Alternatives Considered**:
  - String-based identifiers
  - GUID identifiers
  - Enum-based device types
- **Consequences**:
  - Pros: Simple, efficient, allows for clear categorization
  - Cons: Magic numbers require documentation, limited semantic meaning

### ADR-003: Windows Forms UI Framework
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need a UI framework for a Windows desktop application with complex controls.
- **Decision**: Use .NET Windows Forms (WinForms).
- **Alternatives Considered**:
  - WPF (Windows Presentation Foundation)
  - MAUI (.NET Multi-platform App UI)
  - Avalonia (cross-platform)
- **Consequences**:
  - Pros: Mature framework, fast development, good designer support, familiar to many developers
  - Cons: Windows-only, older UI paradigm, less modern styling options

### ADR-004: Registry Persistence for Settings
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Application settings need to persist between sessions.
- **Decision**: Use Windows Registry for device 0 settings, automatically managed by DataBroker.
- **Alternatives Considered**:
  - JSON/XML configuration files
  - SQLite database
  - Application settings (app.config)
- **Consequences**:
  - Pros: Automatic persistence, no file management needed, Windows-native
  - Cons: Windows-only, can be opaque to users, potential for registry bloat

### ADR-005: Multi-Radio Support
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Users may want to connect and control multiple radios simultaneously.
- **Decision**: Support multiple concurrent radio connections, each with unique device ID.
- **Alternatives Considered**:
  - Single radio only
  - Radio pooling with switching
- **Consequences**:
  - Pros: Flexibility, supports diverse use cases
  - Cons: More complex UI, state management challenges

---

## Technology Decisions

### TDR-001: Whisper.net for Speech Recognition
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need speech-to-text capability for voice transcription.
- **Decision**: Use Whisper.net (OpenAI Whisper port to .NET).
- **Consequences**: Local processing, no cloud dependency, good accuracy

### TDR-002: NAudio for Audio Processing
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need audio input/output and signal processing.
- **Decision**: Use NAudio library.
- **Consequences**: Well-maintained, comprehensive audio API, Windows-focused

### TDR-003: GMap.NET for Mapping
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need map display for station locations and APRS.
- **Decision**: Use GMap.NET.WinForms.
- **Consequences**: Multiple map providers, WinForms integration, offline caching

### TDR-004: InTheHand Bluetooth
- **Date**: Prior to 2026-01-15 (existing decision)
- **Status**: Accepted
- **Context**: Need Bluetooth connectivity for radio communication.
- **Decision**: Use InTheHand.Net.Bluetooth library.
- **Consequences**: .NET-native Bluetooth API, Windows 10+ support

---

## Future Decisions (To Be Made)
- None pending

---

## Deprecated Decisions
- None yet
