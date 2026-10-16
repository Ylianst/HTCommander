/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_dialogs.dart - Connect a MeshCore companion radio over Bluetooth,
// and add MeshCore users and groups. Every action is a Data Broker request to
// the host-side MeshCoreManager (device 204), so these dialogs also work from
// detached windows.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../meshcore/meshcore_manager.dart';
import '../meshcore/meshcore_protocol.dart';
import '../services/data_broker_client.dart';

/// Short, readable form of a public key: first and last eight hex digits.
String meshCoreFingerprint(String keyHex) => keyHex.length <= 16
    ? keyHex
    : '${keyHex.substring(0, 8)}…${keyHex.substring(keyHex.length - 8)}';

/// Sends a request to the MeshCore manager and waits for its `MeshCoreResult`
/// with the matching [op].
Future<Map<dynamic, dynamic>> _request(
  String op,
  String name,
  Map<String, dynamic> data,
) {
  final broker = DataBrokerClient();
  final done = Completer<Map<dynamic, dynamic>>();
  broker.subscribe(
    deviceId: meshCoreDeviceId,
    name: 'MeshCoreResult',
    callback: (_, _, result) {
      if (result is Map && result['op'] == op && !done.isCompleted) {
        done.complete(result);
      }
    },
  );
  broker.dispatch(
    deviceId: meshCoreDeviceId,
    name: name,
    data: data,
    store: false,
  );
  return done.future
      .timeout(
        const Duration(seconds: 30),
        onTimeout: () => {'ok': false, 'error': 'Timed out'},
      )
      .whenComplete(broker.dispose);
}

// ---------------------------------------------------------------------------
// Connection dialog
// ---------------------------------------------------------------------------

Future<void> showMeshCoreConnectionDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _MeshCoreConnectionDialog(),
    );

class _MeshCoreConnectionDialog extends StatefulWidget {
  const _MeshCoreConnectionDialog();

  @override
  State<_MeshCoreConnectionDialog> createState() =>
      _MeshCoreConnectionDialogState();
}

class _MeshCoreConnectionDialogState extends State<_MeshCoreConnectionDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _pinController = TextEditingController();

  Map<dynamic, dynamic> _state = const {};
  Map<dynamic, dynamic>? _info;
  Map<dynamic, dynamic> _scan = const {};
  String? _selectedId;
  String? _selectedName;
  bool _autoConnect = true;
  String? _notice;

  String get _status => _state['state']?.toString() ?? MeshCoreState.disconnected;

  bool get _isBusy =>
      _status == MeshCoreState.pairing ||
      _status == MeshCoreState.connecting ||
      _status == MeshCoreState.syncing;

  bool get _isConnected => _status == MeshCoreState.connected;

  @override
  void initState() {
    super.initState();
    _state = _mapValue('MeshCoreState') ?? const {};
    _info = _mapValue('MeshCoreInfo');
    _scan = _mapValue('MeshCoreScanResults') ?? const {};
    _autoConnect =
        (_broker.getValue<int>(0, 'MeshCoreAutoConnect', 1) ?? 1) != 0;
    final last = _broker.getValueDynamic(0, 'MeshCoreLastDevice', null);
    if (last is Map) {
      _selectedId = last['id']?.toString();
      _selectedName = last['name']?.toString();
    }

    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreState',
      callback: (_, _, data) {
        if (mounted && data is Map) setState(() => _state = data);
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreInfo',
      callback: (_, _, data) {
        if (mounted) setState(() => _info = data is Map ? data : null);
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreScanResults',
      callback: (_, _, data) {
        if (mounted && data is Map) setState(() => _scan = data);
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreResult',
      callback: _onResult,
    );

    if (!_isConnected && !_isBusy) _startScan();
  }

  Map<dynamic, dynamic>? _mapValue(String name) {
    final v = _broker.getValueDynamic(meshCoreDeviceId, name, null);
    return v is Map ? v : null;
  }

  @override
  void dispose() {
    _broker.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onResult(int _, String _, Object? data) {
    if (!mounted || data is! Map) return;
    final l10n = AppLocalizations.of(context);
    final op = data['op'];
    final ok = data['ok'] == true;
    setState(() {
      if (op == 'advert') {
        _notice = ok
            ? l10n.meshAdvertSent
            : l10n.meshActionFailed('${data['error']}');
      } else if (op == 'forgetPairing') {
        _notice = ok
            ? l10n.meshPairingForgotten
            : l10n.meshActionFailed('${data['error']}');
      }
    });
  }

  void _send(String name, [Map<String, dynamic>? data]) {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: name,
      data: data ?? const <String, dynamic>{},
      store: false,
    );
  }

  void _startScan() {
    setState(() => _notice = null);
    _send('MeshCoreScan');
  }

  void _connect() {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _notice = null);
    _broker.dispatch(
      deviceId: 0,
      name: 'MeshCoreAutoConnect',
      data: _autoConnect ? 1 : 0,
    );
    _send('MeshCoreConnect', {
      'id': id,
      'name': _selectedName ?? id,
      'pin': _pinController.text.trim(),
    });
  }

  String _statusText(AppLocalizations l10n) => switch (_status) {
    MeshCoreState.pairing => l10n.meshStatusPairing,
    MeshCoreState.connecting => l10n.meshStatusConnecting,
    MeshCoreState.syncing => l10n.meshStatusSyncing,
    MeshCoreState.connected => l10n.meshStatusConnected,
    MeshCoreState.error => l10n.meshStatusError,
    _ => l10n.meshStatusDisconnected,
  };

  Color _statusColor(ColorScheme scheme) => switch (_status) {
    MeshCoreState.connected => Colors.green,
    MeshCoreState.error => scheme.error,
    MeshCoreState.disconnected => scheme.outline,
    _ => Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final error = _state['error']?.toString();
    final deviceName = _state['deviceName']?.toString() ?? '';

    return AlertDialog(
      title: Text(l10n.meshConnectionTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: _statusColor(scheme)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      deviceName.isEmpty
                          ? _statusText(l10n)
                          : '${_statusText(l10n)} · $deviceName',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_isBusy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              if (error != null && error.isNotEmpty && !_isConnected) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: scheme.error)),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(_notice!),
              ],
              const SizedBox(height: 16),
              if (_isConnected) _buildInfo(l10n) else _buildPicker(l10n),
            ],
          ),
        ),
      ),
      actions: [
        if (_isConnected) ...[
          TextButton(
            onPressed: () => _send('MeshCoreSendAdvert'),
            child: Text(l10n.meshSendAdvert),
          ),
          TextButton(
            onPressed: () => _send('MeshCoreRefresh'),
            child: Text(l10n.meshRefresh),
          ),
        ],
        if (_isConnected || _isBusy)
          TextButton(
            onPressed: () => _send('MeshCoreDisconnect'),
            child: Text(l10n.commonDisconnect),
          )
        else
          FilledButton(
            onPressed: _selectedId == null ? null : _connect,
            child: Text(l10n.commonConnect),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildInfo(AppLocalizations l10n) {
    final info = _info ?? const {};
    final key = info['publicKey']?.toString() ?? '';
    final mv = (info['batteryMv'] as num?)?.toInt();
    final freq = (info['freqMhz'] as num?)?.toDouble();
    final bw = (info['bwKhz'] as num?)?.toDouble();
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: value),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(l10n.meshName, Text(info['name']?.toString() ?? '')),
        row(
          l10n.meshPublicKey,
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  meshCoreFingerprint(key),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: l10n.meshCopyPublicKey,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: key.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: key)),
              ),
            ],
          ),
        ),
        row(
          l10n.meshFirmware,
          Text(
            [
              info['model'],
              info['version'],
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          ),
        ),
        if (freq != null)
          row(
            l10n.meshRadio,
            Text(
              '${freq.toStringAsFixed(3)} MHz · BW ${bw?.toStringAsFixed(1)} kHz'
              ' · SF${info['sf']} · CR${info['cr']}',
            ),
          ),
        if (mv != null && mv > 0)
          row(l10n.meshBattery, Text('${(mv / 1000).toStringAsFixed(2)} V')),
      ],
    );
  }

  Widget _buildPicker(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final scanning = _scan['scanning'] == true;
    final scanError = _scan['error']?.toString();
    final devices = <Map<dynamic, dynamic>>[
      for (final d in (_scan['devices'] as List? ?? const []))
        if (d is Map) d,
    ];
    // Offer the last used device even when it is not advertising right now.
    if (_selectedId != null && !devices.any((d) => d['id'] == _selectedId)) {
      devices.insert(0, {'id': _selectedId, 'name': _selectedName, 'rssi': null});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                scanning ? l10n.meshScanning : l10n.meshDevice,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (scanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: _isBusy ? null : _startScan,
                icon: const Icon(Icons.bluetooth_searching, size: 18),
                label: Text(l10n.meshScan),
              ),
          ],
        ),
        if (scanError != null && scanError.isNotEmpty)
          Text(scanError, style: TextStyle(color: scheme.error)),
        if (devices.isEmpty && !scanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.meshNoDevices),
          ),
        for (final d in devices)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: d['id'] == _selectedId,
            leading: Icon(
              d['id'] == _selectedId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(d['name']?.toString() ?? d['id'].toString()),
            subtitle: Text(
              d['rssi'] == null ? '${d['id']}' : '${d['id']} · ${d['rssi']} dBm',
            ),
            onTap: _isBusy
                ? null
                : () => setState(() {
                    _selectedId = d['id']?.toString();
                    _selectedName = d['name']?.toString();
                  }),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _pinController,
          enabled: !_isBusy,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: l10n.meshPin,
            helperText: l10n.meshPinHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _autoConnect,
          onChanged: (v) => setState(() => _autoConnect = v ?? true),
          title: Text(l10n.meshAutoConnect),
        ),
        if (_selectedId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isBusy
                  ? null
                  : () => _send('MeshCoreForgetPairing', {'id': _selectedId}),
              child: Text(l10n.meshForgetPairing),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add user
// ---------------------------------------------------------------------------

/// Adds a MeshCore user to the companion radio. Returns the conversation peer
/// (12-hex-digit key prefix) on success.
Future<String?> showMeshCoreAddUserDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddUserDialog(),
    );

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  String? _nameError;
  String? _keyError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final key = normalizePublicKeyHex(_key.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? l10n.meshInvalidName : null;
      _keyError = key == null ? l10n.meshInvalidPublicKey : null;
      _error = null;
    });
    if (_nameError != null || key == null) return;
    setState(() => _busy = true);
    final result = await _request('addContact', 'MeshCoreAddContact', {
      'key': key,
      'name': _name.text.trim(),
    });
    if (!mounted) return;
    if (result['ok'] == true) {
      Navigator.of(context).pop(result['peer']?.toString());
    } else {
      setState(() {
        _busy = false;
        _error = l10n.meshActionFailed('${result['error']}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.meshAddUserTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              inputFormatters: [LengthLimitingTextInputFormatter(31)],
              decoration: InputDecoration(
                labelText: l10n.meshName,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              enabled: !_busy,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: l10n.meshPublicKey,
                hintText: l10n.meshPublicKeyHint,
                errorText: _keyError,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add group
// ---------------------------------------------------------------------------

/// Adds a MeshCore group channel to a free slot on the companion radio.
/// Returns the conversation peer (channel key) on success.
Future<String?> showMeshCoreAddGroupDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddGroupDialog(),
    );

class _AddGroupDialog extends StatefulWidget {
  const _AddGroupDialog();

  @override
  State<_AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<_AddGroupDialog> {
  MeshCoreChannelKind _kind = MeshCoreChannelKind.hashtag;
  final _name = TextEditingController();
  final _secret = TextEditingController();
  String? _nameError;
  String? _secretError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _setKind(MeshCoreChannelKind kind) {
    setState(() {
      _kind = kind;
      _nameError = null;
      _secretError = null;
      if (kind == MeshCoreChannelKind.public && _name.text.trim().isEmpty) {
        _name.text = 'Public';
      }
      if (kind == MeshCoreChannelKind.private && _secret.text.isEmpty) {
        _secret.text = bytesToHex(randomChannelSecret());
      }
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    var name = _name.text.trim();
    if (_kind == MeshCoreChannelKind.hashtag && name.isNotEmpty) {
      name = name.startsWith('#') ? name : '#$name';
    }
    String? secret;
    switch (_kind) {
      case MeshCoreChannelKind.public:
        secret = MeshCoreConst.publicChannelSecretHex;
      case MeshCoreChannelKind.hashtag:
        secret = name.length > 1 ? bytesToHex(hashtagChannelSecret(name)) : null;
      case MeshCoreChannelKind.private:
        secret = normalizeChannelSecretHex(_secret.text);
    }
    setState(() {
      _nameError = name.isEmpty || name == '#' ? l10n.meshInvalidName : null;
      _secretError = _kind == MeshCoreChannelKind.private && secret == null
          ? l10n.meshInvalidSecret
          : null;
      _error = null;
    });
    if (_nameError != null || _secretError != null || secret == null) return;
    setState(() => _busy = true);
    final result = await _request('addChannel', 'MeshCoreAddChannel', {
      'name': name,
      'secret': secret,
    });
    if (!mounted) return;
    if (result['ok'] == true) {
      Navigator.of(context).pop(result['peer']?.toString());
    } else {
      setState(() {
        _busy = false;
        _error = l10n.meshActionFailed('${result['error']}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final help = switch (_kind) {
      MeshCoreChannelKind.public => l10n.meshGroupPublicHelp,
      MeshCoreChannelKind.hashtag => l10n.meshGroupHashtagHelp,
      MeshCoreChannelKind.private => l10n.meshGroupPrivateHelp,
    };
    return AlertDialog(
      title: Text(l10n.meshAddGroupTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.meshGroupType),
            const SizedBox(height: 8),
            SegmentedButton<MeshCoreChannelKind>(
              segments: [
                ButtonSegment(
                  value: MeshCoreChannelKind.public,
                  label: Text(l10n.meshGroupPublic),
                ),
                ButtonSegment(
                  value: MeshCoreChannelKind.hashtag,
                  label: Text(l10n.meshGroupHashtag),
                ),
                ButtonSegment(
                  value: MeshCoreChannelKind.private,
                  label: Text(l10n.meshGroupPrivate),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (s) => _setKind(s.first),
            ),
            const SizedBox(height: 8),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              inputFormatters: [LengthLimitingTextInputFormatter(31)],
              decoration: InputDecoration(
                labelText: l10n.meshName,
                hintText: _kind == MeshCoreChannelKind.hashtag ? '#name' : null,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_kind == MeshCoreChannelKind.private) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _secret,
                      enabled: !_busy,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: l10n.meshSecret,
                        hintText: l10n.meshSecretHint,
                        errorText: _secretError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _secret.text = bytesToHex(
                                randomChannelSecret(),
                              ),
                            ),
                      child: Text(l10n.meshGenerate),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}
