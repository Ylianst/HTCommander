/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `EditIdentSettingsForm`. Lets the user configure the radio's
PTT-release ident: a callsign / station ID string plus toggles to send the
callsign and/or position each time the PTT is released on the transmitting
channel. Values are read from and written to the radio's BSS settings via the
DataBroker (per-device `BssSettings` value and `SetBssSettings` event).
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the PTT Release (ident) Settings dialog. [initialDeviceId] selects
/// which radio is shown first; when omitted the first connected radio is used.
Future<void> showEditIdentSettingsDialog(
  BuildContext context, {
  int? initialDeviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _EditIdentSettingsDialog(initialDeviceId: initialDeviceId),
  );
}

class _EditIdentSettingsDialog extends StatefulWidget {
  final int? initialDeviceId;
  const _EditIdentSettingsDialog({this.initialDeviceId});

  @override
  State<_EditIdentSettingsDialog> createState() =>
      _EditIdentSettingsDialogState();
}

class _EditIdentSettingsDialogState extends State<_EditIdentSettingsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _callsignController = TextEditingController();

  /// The radio device id this dialog edits (the currently selected radio), or
  /// -1 when none was provided.
  int _deviceId = -1;

  /// The current BSS settings for the selected radio, or null when unavailable.
  RadioBssSettings? _bssSettings;

  bool _sendCallsign = false;
  bool _sendPosition = false;

  @override
  void initState() {
    super.initState();

    // Operate on the currently selected radio passed in by the caller.
    _deviceId = widget.initialDeviceId ?? -1;
    if (_deviceId <= 0) return;

    // Seed current values from the broker, then subscribe for live updates.
    _applyBssSettings(
      _broker.getJsonValue<RadioBssSettings>(
        _deviceId,
        'BssSettings',
        (json) => RadioBssSettings.fromJson(json),
      ),
    );

    _broker.subscribe(
      deviceId: _deviceId,
      name: 'BssSettings',
      callback: _onBssSettingsChanged,
    );
  }

  @override
  void dispose() {
    if (_deviceId > 0) _broker.unsubscribe(_deviceId, 'BssSettings');
    _callsignController.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onBssSettingsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (deviceId != _deviceId) return;
    setState(() {
      _applyBssSettings(
        data is Map<String, dynamic> ? RadioBssSettings.fromJson(data) : null,
      );
    });
  }

  /// Copies [bss] into the editable form fields.
  void _applyBssSettings(RadioBssSettings? bss) {
    _bssSettings = bss;
    if (bss == null) {
      _callsignController.text = '';
      _sendCallsign = false;
      _sendPosition = false;
      return;
    }
    _callsignController.text = bss.pttReleaseIdInfo;
    _sendCallsign = bss.pttReleaseSendIdInfo;
    _sendPosition = bss.pttReleaseSendLocation;
  }

  bool get _canSave => _deviceId > 0 && _bssSettings != null;

  void _onOk() {
    final current = _bssSettings;
    if (_deviceId <= 0 || current == null) return;

    // Update only the PTT-release ident fields, preserving all other BSS
    // settings (matching the C# copy-then-modify behavior).
    current.pttReleaseIdInfo = _callsignController.text;
    current.pttReleaseSendIdInfo = _sendCallsign;
    current.pttReleaseSendLocation = _sendPosition;

    // Dispatch the updated settings object to the radio. The Radio listens for
    // the 'SetBssSettings' event and writes it to the device.
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SetBssSettings',
      data: current,
      store: false,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'PTT Release Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              // Description
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'If enabled, sends your callsign and/or location '
                        'information each time you release the PTT on the '
                        'channel you are transmitting on.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // Editable fields
              _buildForm(),
              const SizedBox(height: 16),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSave ? _onOk : null,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final enabled = _canSave;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _callsignController,
          enabled: enabled,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            // Allow letters, numbers, dash (-), slash (/) and space.
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9/\- ]')),
          ],
          decoration: InputDecoration(
            labelText: 'Callsign - Station ID',
            hintText: 'Enter Callsign - Station ID',
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _sendCallsign,
          onChanged: enabled
              ? (v) => setState(() => _sendCallsign = v ?? false)
              : null,
          title: const Text('Send Callsign'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          value: _sendPosition,
          onChanged: enabled
              ? (v) => setState(() => _sendPosition = v ?? false)
              : null,
          title: const Text('Send Position'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}
