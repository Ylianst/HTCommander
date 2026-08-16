/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Combined "Radio Settings" dialog for a connected hardware (Bluetooth) radio.
It gathers configuration that used to live in several separate dialogs into a
single tabbed dialog styled like the application Settings dialog. Each tab
embeds a reusable panel that owns its own state; a single shared Save button at
the bottom writes every tab back to the radio.

This dialog is specific to the hardware radio. Other radio types (EchoLink,
AllStarLink, ...) may get their own "Radio Settings" dialog in the future.
*/

import 'package:flutter/material.dart';

import 'buttons_settings_panel.dart';
import 'edit_beacon_settings_dialog.dart';
import 'edit_ident_settings_dialog.dart';
import 'radio_bitfield_settings_panels.dart';
import 'radio_settings_panel.dart';
import 'trusted_devices_panel.dart';

/// Shows the combined hardware Radio Settings dialog for the connected radio
/// [deviceId]. [radioName] is shown in the header when provided.
Future<void> showHardwareRadioSettingsDialog(
  BuildContext context, {
  required int deviceId,
  String? radioName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => HardwareRadioSettingsDialog(
      deviceId: deviceId,
      radioName: radioName,
    ),
  );
}

class HardwareRadioSettingsDialog extends StatefulWidget {
  final int deviceId;
  final String? radioName;

  const HardwareRadioSettingsDialog({
    super.key,
    required this.deviceId,
    this.radioName,
  });

  @override
  State<HardwareRadioSettingsDialog> createState() =>
      _HardwareRadioSettingsDialogState();
}

class _HardwareRadioSettingsDialogState
    extends State<HardwareRadioSettingsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final RadioBitfieldSettingsController _bitfieldController;

  final GlobalKey<IdentSettingsPanelState> _pttKey =
      GlobalKey<IdentSettingsPanelState>();
  final GlobalKey<BeaconSettingsPanelState> _beaconKey =
      GlobalKey<BeaconSettingsPanelState>();
  final GlobalKey<ButtonsSettingsPanelState> _buttonsKey =
      GlobalKey<ButtonsSettingsPanelState>();
  final GlobalKey<TrustedDevicesPanelState> _trustedKey =
      GlobalKey<TrustedDevicesPanelState>();

  static const List<String> _tabTitles = [
    'PTT Release',
    'Beacon',
    'Buttons',
    'Paired Devices',
    'Audio',
    'Power',
    'Transmit',
    'Display',
    'Advanced',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabTitles.length, vsync: this);
    _bitfieldController = RadioBitfieldSettingsController(widget.deviceId);
  }

  @override
  void dispose() {
    _bitfieldController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// The savable panels in tab order (Paired Devices edits live, so it is not
  /// part of the batched Save).
  List<RadioSettingsPanel?> get _savablePanels => [
        _pttKey.currentState,
        _beaconKey.currentState,
        _buttonsKey.currentState,
        _trustedKey.currentState,
      ];

  void _onSave() {
    final panels = _savablePanels;

    // Block the save if any tab has invalid input; jump to the offending tab so
    // the user can see and fix the inline validation error.
    for (int i = 0; i < panels.length; i++) {
      final panel = panels[i];
      if (panel != null && !panel.canSave) {
        _tabController.animateTo(i);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fix the ${_tabTitles[i]} tab before saving.')),
        );
        return;
      }
    }

    for (final panel in panels) {
      panel?.save();
    }
    // The Audio/Power/Transmit/Display/Advanced tabs all edit one shared
    // settings buffer, so write it back to the radio exactly once.
    _bitfieldController.write();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.radioName;
    return Dialog(
      backgroundColor: scheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Radio Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              if (name != null && name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Tab bar
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                tabs: _tabTitles.map((t) => Tab(text: t)).toList(),
              ),
              const SizedBox(height: 8),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _padded(IdentSettingsPanel(
                      key: _pttKey,
                      initialDeviceId: widget.deviceId,
                    )),
                    _padded(BeaconSettingsPanel(key: _beaconKey)),
                    _padded(ButtonsSettingsPanel(
                      key: _buttonsKey,
                      initialDeviceId: widget.deviceId,
                    )),
                    _padded(TrustedDevicesPanel(
                      key: _trustedKey,
                      deviceId: widget.deviceId,
                    )),
                    _padded(RadioBitfieldPanel(
                      controller: _bitfieldController,
                      tab: RadioBitfieldTab.audio,
                    )),
                    _padded(RadioBitfieldPanel(
                      controller: _bitfieldController,
                      tab: RadioBitfieldTab.power,
                    )),
                    _padded(RadioBitfieldPanel(
                      controller: _bitfieldController,
                      tab: RadioBitfieldTab.transmit,
                    )),
                    _padded(RadioBitfieldPanel(
                      controller: _bitfieldController,
                      tab: RadioBitfieldTab.display,
                    )),
                    _padded(RadioBitfieldPanel(
                      controller: _bitfieldController,
                      tab: RadioBitfieldTab.advanced,
                    )),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _padded(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: child,
    );
  }
}
