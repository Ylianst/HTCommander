/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Contract implemented by each panel embedded as a tab in the combined
/// hardware Radio Settings dialog. Panels own their own state and DataBroker
/// subscriptions; the host dialog drives a single shared Save action across
/// every tab.
///
/// The same panel widgets are also used stand-alone by their original
/// dialogs, so the panels themselves never close a dialog: closing is left to
/// whichever container hosts them.
mixin RadioSettingsPanel {
  /// Whether the panel's current input is valid enough to be written to the
  /// radio. This blocks the shared Save button only for genuinely invalid
  /// input (e.g. a malformed callsign); panels with nothing to validate or
  /// nothing to save return true.
  bool get canSave;

  /// Writes the panel's edits to the radio. Implementations must guard against
  /// missing/unloaded data and must not close the host dialog.
  void save();
}
