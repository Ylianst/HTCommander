import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/station_info.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../services/data_broker_client.dart';

/// Shows the add / edit station dialog. When [existing] is provided the dialog
/// edits that station (callsign and type are locked, matching the C#
/// `AddStationForm.DeserializeFromObject`). Returns the resulting [StationInfo]
/// or `null` if cancelled.
Future<StationInfo?> showStationDialog(
  BuildContext context, {
  StationInfo? existing,
}) {
  return showDialog<StationInfo>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StationDialog(existing: existing),
  );
}

/// A selectable station type (mirrors the 4 options in the C# combo box).
class _TypeOption {
  final StationType type;
  final String label;
  const _TypeOption(this.type, this.label);
}

const List<_TypeOption> _typeOptions = [
  _TypeOption(StationType.generic, 'Voice / Generic Station'),
  _TypeOption(StationType.aprs, 'APRS Station'),
  _TypeOption(StationType.terminal, 'Terminal Station'),
  _TypeOption(StationType.winlink, 'Winlink Gateway'),
];

class _ProtocolOption {
  final TerminalProtocol protocol;
  final String label;
  const _ProtocolOption(this.protocol, this.label);
}

const List<_ProtocolOption> _protocolOptions = [
  _ProtocolOption(TerminalProtocol.rawX25, 'Raw AX.25'),
  _ProtocolOption(TerminalProtocol.aprs, 'APRS'),
  _ProtocolOption(TerminalProtocol.rawX25Compress, 'Raw AX.25 (Compressed)'),
  _ProtocolOption(TerminalProtocol.x25Session, 'AX.25 Session'),
];

/// A selectable modem for Terminal / Winlink sessions.
class _ModemOption {
  final String value;
  final String label;
  const _ModemOption(this.value, this.label);
}

const List<_ModemOption> _modemOptions = [
  _ModemOption('Hardware', 'Hardware AFSK 1200 (radio modem)'),
  _ModemOption('AFSK1200', 'Software AFSK 1200'),
  _ModemOption('PSK2400', 'Software PSK 2400'),
  _ModemOption('DART', 'Software DART'),
];

class _StationDialog extends StatefulWidget {
  final StationInfo? existing;
  const _StationDialog({this.existing});

  @override
  State<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<_StationDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  late final TextEditingController _callsignController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ax25DestController;
  late final TextEditingController _authPasswordController;
  late final TextEditingController _channelController;

  StationType _stationType = StationType.generic;
  TerminalProtocol _terminalProtocol = TerminalProtocol.x25Session;
  String _aprsRoute = '';
  bool _useAuth = false;
  String _modem = 'Hardware';

  List<String> _channelNames = [];
  List<String> _aprsRouteNames = [];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;

    _callsignController = TextEditingController(text: s?.callsign ?? '');
    _nameController = TextEditingController(text: s?.name ?? '');
    _descriptionController = TextEditingController(text: s?.description ?? '');
    _ax25DestController = TextEditingController(text: s?.ax25Destination ?? '');
    _authPasswordController = TextEditingController(
      text: s?.authPassword ?? '',
    );
    _channelController = TextEditingController(text: s?.channel ?? '');

    if (s != null) {
      _stationType = s.stationType;
      _terminalProtocol = s.terminalProtocol;
      _aprsRoute = s.aprsRoute;
      _modem = _modemOptions.any((o) => o.value == s.modem)
          ? s.modem
          : 'Hardware';
      _useAuth =
          s.stationType == StationType.aprs &&
          (s.authPassword?.isNotEmpty ?? false);
    }

    _loadChannelNames();
    _loadAprsRoutes();

    _callsignController.addListener(_onTextChanged);
    _ax25DestController.addListener(_onTextChanged);
    _authPasswordController.addListener(_onTextChanged);
    _channelController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _broker.dispose();
    _callsignController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _ax25DestController.dispose();
    _authPasswordController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// Collects channel names from all connected radios, excluding "APRS".
  void _loadChannelNames() {
    final names = <String>{};
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final deviceId = item['DeviceId'];
        if (deviceId is! int || deviceId <= 0) continue;
        final channels = _broker.getJsonListValue<RadioChannelInfo>(
          deviceId,
          'Channels',
          (json) => RadioChannelInfo.fromJson(json),
        );
        if (channels == null) continue;
        for (final channel in channels) {
          if (channel.name.isEmpty) continue;
          if (channel.name.toUpperCase() == 'APRS') continue;
          names.add(channel.name);
        }
      }
    }
    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _channelNames = sorted;
  }

  /// Reads APRS route names from the persisted `AprsRoutes` setting (Flutter
  /// pipe-separated name/path pairs).
  void _loadAprsRoutes() {
    final names = <String>[];
    final routesStr = _broker.getValue<String>(0, 'AprsRoutes', '') ?? '';
    if (routesStr.isNotEmpty) {
      final parts = routesStr.split('|');
      for (var i = 0; i + 1 < parts.length; i += 2) {
        if (parts[i].isNotEmpty) names.add(parts[i]);
      }
    }
    _aprsRouteNames = names;
    if (_aprsRoute.isEmpty && names.isNotEmpty) _aprsRoute = names.first;
  }

  // ---- validation -----------------------------------------------------------

  bool get _callsignValid {
    final text = _callsignController.text.trim();
    if (text.isEmpty) return false;
    return AX25Address.parse(text) != null;
  }

  bool get _ax25DestValid {
    final text = _ax25DestController.text.trim();
    if (text.isEmpty) return true; // optional
    return AX25Address.parse(text) != null && text.contains('-');
  }

  bool get _isValid {
    if (!_callsignValid) return false;
    if (!_ax25DestValid) return false;
    if (_stationType == StationType.aprs &&
        _useAuth &&
        _authPasswordController.text.isEmpty) {
      return false;
    }
    if (_stationType == StationType.terminal &&
        _terminalProtocol == TerminalProtocol.aprs &&
        _channelController.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  String get _title {
    final base = switch (_stationType) {
      StationType.generic => 'Voice Station',
      StationType.aprs => 'APRS Station',
      StationType.terminal => 'Terminal Station',
      StationType.winlink => 'Winlink Gateway',
      _ => 'Station',
    };
    if (_isEditing) return '$base - ${widget.existing!.callsign}';
    return base;
  }

  StationInfo _buildResult() {
    if (_stationType == StationType.winlink) {
      return StationInfo(
        callsign: _callsignController.text.trim(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        stationType: StationType.winlink,
        terminalProtocol: TerminalProtocol.x25Session,
        channel: _channelController.text.trim(),
        modem: _modem,
      );
    }
    return StationInfo(
      callsign: _callsignController.text.trim(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      stationType: _stationType,
      aprsRoute: _aprsRoute,
      terminalProtocol: _terminalProtocol,
      channel: _channelController.text.trim(),
      ax25Destination: _ax25DestController.text.trim(),
      authPassword: (_stationType == StationType.aprs && _useAuth)
          ? _authPasswordController.text
          : null,
      modem: _modem,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCallsignField(),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: _inputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: _inputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              if (!_isEditing) _buildTypeDropdown(),
              ..._buildTypeSpecificFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_buildResult())
              : null,
          child: const Text('OK'),
        ),
      ],
    );
  }

  /// Filled, borderless input decoration matching the settings dialog style.
  InputDecoration _inputDecoration({
    String? labelText,
    String? hintText,
    String? errorText,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      labelText: labelText,
      hintText: hintText,
      errorText: errorText,
      isDense: true,
      contentPadding: labelText != null
          ? const EdgeInsets.fromLTRB(12, 20, 12, 12)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );
  }

  Widget _buildCallsignField() {
    return TextField(
      controller: _callsignController,
      enabled: !_isEditing,
      textCapitalization: TextCapitalization.characters,
      decoration: _inputDecoration(
        labelText: 'Callsign',
        errorText: _callsignController.text.isNotEmpty && !_callsignValid
            ? 'Invalid callsign'
            : null,
      ),
      onChanged: (value) {
        final upper = value.toUpperCase();
        if (upper != value) {
          _callsignController.value = _callsignController.value.copyWith(
            text: upper,
            selection: TextSelection.collapsed(offset: upper.length),
          );
        }
      },
    );
  }

  Widget _buildTypeDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<StationType>(
        initialValue: _typeOptions.any((o) => o.type == _stationType)
            ? _stationType
            : StationType.generic,
        decoration: _inputDecoration(labelText: 'Station Type'),
        items: [
          for (final option in _typeOptions)
            DropdownMenuItem(value: option.type, child: Text(option.label)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _stationType = value);
        },
      ),
    );
  }

  List<Widget> _buildTypeSpecificFields() {
    switch (_stationType) {
      case StationType.aprs:
        return _buildAprsFields();
      case StationType.terminal:
        return _buildTerminalFields();
      case StationType.winlink:
        return _buildWinlinkFields();
      default:
        return const [];
    }
  }

  List<Widget> _buildAprsFields() {
    return [
      if (_aprsRouteNames.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          initialValue: _aprsRouteNames.contains(_aprsRoute)
              ? _aprsRoute
              : _aprsRouteNames.first,
          decoration: _inputDecoration(labelText: 'APRS Route'),
          items: [
            for (final name in _aprsRouteNames)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _aprsRoute = value);
          },
        ),
        const SizedBox(height: 12),
      ],
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: const Text('Use message authentication'),
        value: _useAuth,
        onChanged: (value) => setState(() => _useAuth = value ?? false),
      ),
      if (_useAuth)
        TextField(
          controller: _authPasswordController,
          obscureText: true,
          decoration: _inputDecoration(
            labelText: 'Auth Password',
            errorText: _useAuth && _authPasswordController.text.isEmpty
                ? 'Password required'
                : null,
          ),
        ),
    ];
  }

  List<Widget> _buildTerminalFields() {
    return [
      DropdownButtonFormField<TerminalProtocol>(
        initialValue: _terminalProtocol,
        decoration: _inputDecoration(labelText: 'Terminal Protocol'),
        items: [
          for (final option in _protocolOptions)
            DropdownMenuItem(value: option.protocol, child: Text(option.label)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _terminalProtocol = value);
        },
      ),
      const SizedBox(height: 12),
      _buildChannelField(),
      if (_terminalProtocol == TerminalProtocol.aprs) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _ax25DestController,
          textCapitalization: TextCapitalization.characters,
          decoration: _inputDecoration(
            labelText: 'AX.25 Destination (e.g. CALL-1)',
            errorText: _ax25DestController.text.isNotEmpty && !_ax25DestValid
                ? 'Invalid AX.25 address'
                : null,
          ),
          onChanged: (value) {
            final upper = value.toUpperCase();
            if (upper != value) {
              _ax25DestController.value = _ax25DestController.value.copyWith(
                text: upper,
                selection: TextSelection.collapsed(offset: upper.length),
              );
            }
          },
        ),
      ],
      if (_audioChannelSupported) ...[
        const SizedBox(height: 12),
        _buildModemDropdown(),
      ],
    ];
  }

  List<Widget> _buildWinlinkFields() {
    return [
      _buildChannelField(),
      if (_audioChannelSupported) ...[
        const SizedBox(height: 12),
        _buildModemDropdown(),
      ],
    ];
  }

  /// True when this platform supports the software modem audio channel.
  /// The audio channel is unavailable on web and iOS.
  bool get _audioChannelSupported => !kIsWeb && !Platform.isIOS;

  Widget _buildModemDropdown() {
    final current =
        _modemOptions.any((o) => o.value == _modem) ? _modem : 'Hardware';
    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: _inputDecoration(labelText: 'Modem'),
      items: [
        for (final option in _modemOptions)
          DropdownMenuItem(value: option.value, child: Text(option.label)),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _modem = value);
      },
    );
  }

  Widget _buildChannelField() {
    // Use a dropdown when channel names are available, otherwise free text.
    if (_channelNames.isEmpty) {
      return TextField(
        controller: _channelController,
        decoration: _inputDecoration(labelText: 'Channel'),
      );
    }

    final current = _channelController.text.trim();
    final items = <String>[..._channelNames];
    if (current.isNotEmpty && !items.contains(current)) {
      items.insert(0, current);
    }

    return DropdownButtonFormField<String>(
      initialValue: items.contains(current) && current.isNotEmpty
          ? current
          : items.first,
      decoration: _inputDecoration(labelText: 'Channel'),
      items: [
        for (final name in items)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() => _channelController.text = value);
        }
      },
    );
  }
}
