import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
import 'contact_logo_picker_dialog.dart';
import 'image_crop_dialog.dart';
import '../models/station_info.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../services/data_broker_client.dart';
import '../services/callsign_lookup_service.dart';
import '../widgets/contact_avatar.dart';

/// Shows the add / edit station dialog. When [existing] is provided the dialog
/// edits that station (callsign and type are locked, matching the C#
/// `AddStationForm.DeserializeFromObject`).
///
/// When [fixedType] is provided (and [existing] is null) the dialog creates a
/// new station of that type: the type is locked, but the callsign remains
/// editable so the user can enter a valid callsign. [initialCallsign] prefills
/// that editable callsign field. Returns the resulting
/// [StationInfo] or `null` if cancelled.
Future<StationInfo?> showStationDialog(
  BuildContext context, {
  StationInfo? existing,
  StationType? fixedType,
  String? initialCallsign,
}) {
  return showDialog<StationInfo>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StationDialog(
      existing: existing,
      fixedType: fixedType,
      initialCallsign: initialCallsign,
    ),
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
  _TypeOption(StationType.sms, 'SMS / Phone'),
  _TypeOption(StationType.email, 'Email'),
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
  final StationType? fixedType;
  final String? initialCallsign;
  const _StationDialog({this.existing, this.fixedType, this.initialCallsign});

  @override
  State<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<_StationDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  // Focus for the callsign field: when focus leaves it, we auto-fill the name
  // and description from the offline callsign database (new radio contacts).
  final FocusNode _callsignFocusNode = FocusNode();
  // The last callsign auto-filled from the database, so leaving the field again
  // without changes does not repeat the lookup.
  String _autoFilledCallsign = '';

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

  // Avatar customization: a chosen built-in logo name and/or a base64 64x64 PNG.
  String? _avatarIcon;
  String? _avatarImage;

  List<String> _channelNames = [];
  List<String> _aprsRouteNames = [];

  bool get _isEditing => widget.existing != null;

  /// The station type is locked when editing an existing station or when a
  /// [fixedType] was requested for a new station.
  bool get _isTypeLocked => _isEditing || widget.fixedType != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s == null && widget.fixedType != null) {
      _stationType = widget.fixedType!;
    }

    _callsignController = TextEditingController(
      text: s?.callsign ?? widget.initialCallsign ?? '',
    );
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
      _avatarIcon = s.avatarIcon;
      _avatarImage = s.avatarImage;
    }

    _loadChannelNames();
    _loadAprsRoutes();

    _callsignController.addListener(_onTextChanged);
    _ax25DestController.addListener(_onTextChanged);
    _authPasswordController.addListener(_onTextChanged);
    _channelController.addListener(_onTextChanged);
    _callsignFocusNode.addListener(_onCallsignFocusChanged);

    // When opened prefilled with a callsign (e.g. from the callsign lookup
    // dialog), auto-fill the name and description from the offline database.
    if (s == null && (widget.initialCallsign ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _autoFillFromCallsign(),
      );
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    _callsignFocusNode.dispose();
    _callsignController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _ax25DestController.dispose();
    _authPasswordController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// When the callsign field loses focus (the user moves to the next field),
  /// look the callsign up in the offline database and, when a record is found,
  /// auto-fill the still-empty Name and Description (station location) fields.
  void _onCallsignFocusChanged() {
    if (_callsignFocusNode.hasFocus) return;
    _autoFillFromCallsign();
  }

  Future<void> _autoFillFromCallsign() async {
    // Only radio callsign contacts are looked up (not SMS/email), and only for
    // new contacts (editing locks the callsign).
    if (_isEditing || _isSimpleContact) return;
    final callsign = _callsignController.text.trim().toUpperCase();
    if (callsign.isEmpty || !_callsignValid) return;
    // Skip if we already auto-filled for this exact callsign.
    if (callsign == _autoFilledCallsign) return;

    final result = await CallsignLookupService.instance.lookup(callsign);
    if (!mounted || result == null) return;

    final record = result.record;
    var changed = false;
    if (_nameController.text.trim().isEmpty && record.name.isNotEmpty) {
      _nameController.text = record.name;
      changed = true;
    }
    if (_descriptionController.text.trim().isEmpty &&
        record.location.isNotEmpty) {
      _descriptionController.text = record.location;
      changed = true;
    }
    if (changed) {
      _autoFilledCallsign = callsign;
      setState(() {});
    }
  }

  /// Builds the right-click / long-press context menu for the Name and
  /// Description fields, appending a "Lookup" item that fills the field from the
  /// offline callsign database. The item is only offered for radio callsign
  /// contacts with a valid callsign entered.
  Widget _fieldContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
    TextEditingController controller, {
    required bool isName,
  }) {
    final buttonItems = editableTextState.contextMenuButtonItems;
    if (!_isSimpleContact && _callsignValid) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: AppLocalizations.of(context).cslButtonLookup,
          onPressed: () {
            ContextMenuController.removeAny();
            _lookupField(controller, isName: isName);
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  /// Looks the entered callsign up in the offline database and replaces the
  /// target field with the record's name (or location for the description).
  Future<void> _lookupField(
    TextEditingController controller, {
    required bool isName,
  }) async {
    final callsign = _callsignController.text.trim().toUpperCase();
    if (callsign.isEmpty || !_callsignValid) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    final result = await CallsignLookupService.instance.lookup(callsign);
    if (!mounted) return;

    final value = result == null
        ? ''
        : (isName ? result.record.name : result.record.location);
    if (value.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.cslNotFound(callsign))),
      );
      return;
    }
    controller.text = value;
    setState(() {});
  }

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

  /// True for the simple contact types (SMS / phone and email) that only carry
  /// an identifier (phone number or email address) and a name.
  bool get _isSimpleContact =>
      _stationType == StationType.sms || _stationType == StationType.email;

  bool get _callsignValid {
    final text = _callsignController.text.trim();
    if (text.isEmpty) return false;
    return AX25Address.parse(text) != null;
  }

  /// Rough email format check: something@something.something.
  bool get _emailValid {
    final text = _callsignController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  }

  /// The identifier field (callsign / phone / email) is valid for the type.
  bool get _idValid {
    switch (_stationType) {
      case StationType.sms:
        return _callsignController.text.trim().isNotEmpty;
      case StationType.email:
        return _emailValid;
      default:
        return _callsignValid;
    }
  }

  bool get _ax25DestValid {
    final text = _ax25DestController.text.trim();
    if (text.isEmpty) return true; // optional
    return AX25Address.parse(text) != null && text.contains('-');
  }

  bool get _isValid {
    if (!_idValid) return false;
    if (_isSimpleContact) return true;
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
    final l10n = AppLocalizations.of(context);
    final base = switch (_stationType) {
      StationType.generic => l10n.stationTitleVoice,
      StationType.aprs => l10n.stationTitleAprs,
      StationType.terminal => l10n.stationTitleTerminal,
      StationType.winlink => l10n.stationTitleWinlink,
      StationType.sms => l10n.stationTitleSms,
      StationType.email => l10n.stationTitleEmail,
      _ => l10n.stationTitleGeneric,
    };
    return base;
  }

  /// Localized label for a station [type] in the type dropdown.
  String _typeLabel(StationType type, AppLocalizations l10n) {
    switch (type) {
      case StationType.generic:
        return l10n.stationTypeOptionVoice;
      case StationType.aprs:
        return l10n.stationTitleAprs;
      case StationType.terminal:
        return l10n.stationTitleTerminal;
      case StationType.winlink:
        return l10n.stationTitleWinlink;
      case StationType.sms:
        return l10n.stationTitleSms;
      case StationType.email:
        return l10n.stationTitleEmail;
      default:
        return l10n.stationTitleGeneric;
    }
  }

  /// Round contact avatar shown at the dialog's top-right. Tapping it opens the
  /// avatar customization menu.
  Widget _buildAvatarButton() {
    return Tooltip(
      message: AppLocalizations.of(context).contactAvatarCustomize,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTapDown: (details) => _showAvatarMenu(details.globalPosition),
        child: ContactAvatar(
          callsign: _callsignController.text.trim(),
          avatarIcon: _avatarIcon,
          avatarImage: _avatarImage,
          radius: 22,
        ),
      ),
    );
  }

  Future<void> _showAvatarMenu(Offset globalPosition) async {
    final l10n = AppLocalizations.of(context);
    // A snapshot of any clipboard image, read up front so a "Paste" item can be
    // offered only when one is available.
    Uint8List? clipboardImage;
    try {
      clipboardImage = await Pasteboard.image;
    } catch (_) {
      clipboardImage = null;
    }
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final hasCustom = _avatarIcon != null || _avatarImage != null;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'logo',
          child: Text(l10n.contactAvatarChooseLogo),
        ),
        PopupMenuItem<String>(
          value: 'image',
          child: Text(l10n.contactAvatarChooseImage),
        ),
        if (clipboardImage != null)
          PopupMenuItem<String>(
            value: 'paste',
            child: Text(l10n.contactAvatarPaste),
          ),
        if (hasCustom)
          PopupMenuItem<String>(
            value: 'reset',
            child: Text(l10n.contactAvatarReset),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case 'logo':
        await _chooseLogo();
        break;
      case 'image':
        await _chooseImage();
        break;
      case 'paste':
        if (clipboardImage != null) await _cropAndSetImage(clipboardImage);
        break;
      case 'reset':
        setState(() {
          _avatarIcon = null;
          _avatarImage = null;
        });
        break;
    }
  }

  Future<void> _chooseLogo() async {
    final name = await showContactLogoPicker(context);
    if (name == null || !mounted) return;
    setState(() {
      _avatarIcon = name;
      _avatarImage = null; // a logo replaces any custom image
    });
  }

  Future<void> _chooseImage() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      return;
    }
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    var bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null || !mounted) return;
    await _cropAndSetImage(bytes);
  }

  /// Runs [bytes] through the crop dialog and stores the resulting avatar image.
  Future<void> _cropAndSetImage(Uint8List bytes) async {
    final b64 = await showImageCropDialog(context, bytes);
    if (b64 == null || !mounted) return;
    setState(() {
      _avatarImage = b64;
      _avatarIcon = null; // a custom image replaces any chosen logo
    });
  }

  StationInfo _buildResult() {
    if (_isSimpleContact) {
      // The identifier (phone number or email) is stored in the callsign field,
      // which the contacts list surfaces as the generic "ID" column.
      return StationInfo(
        callsign: _callsignController.text.trim(),
        name: _nameController.text.trim(),
        stationType: _stationType,
        avatarIcon: _avatarIcon,
        avatarImage: _avatarImage,
      );
    }
    if (_stationType == StationType.winlink) {
      return StationInfo(
        callsign: _callsignController.text.trim(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        stationType: StationType.winlink,
        terminalProtocol: TerminalProtocol.x25Session,
        channel: _channelController.text.trim(),
        modem: _modem,
        avatarIcon: _avatarIcon,
        avatarImage: _avatarImage,
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
      avatarIcon: _avatarIcon,
      avatarImage: _avatarImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typeFields = _buildTypeSpecificFields();
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(_title)),
          const SizedBox(width: 12),
          _buildAvatarButton(),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isTypeLocked) ...[
                _buildTypeDropdown(),
              ],
              _buildCallsignField(),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                contextMenuBuilder: (context, editableTextState) =>
                    _fieldContextMenuBuilder(
                      context,
                      editableTextState,
                      _nameController,
                      isName: true,
                    ),
                decoration: _inputDecoration(labelText: l10n.contactsColName),
              ),
              if (!_isSimpleContact) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  contextMenuBuilder: (context, editableTextState) =>
                      _fieldContextMenuBuilder(
                        context,
                        editableTextState,
                        _descriptionController,
                        isName: false,
                      ),
                  decoration:
                      _inputDecoration(labelText: l10n.contactsColDescription),
                ),
              ],
              if (typeFields.isNotEmpty) const SizedBox(height: 12),
              ...typeFields,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_buildResult())
              : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonOk),
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
    return DialogStyles.inputDecoration(
      context,
      labelText: labelText,
      hintText: hintText,
      errorText: errorText,
      focusColor: Colors.blue,
    );
  }

  Widget _buildCallsignField() {
    final l10n = AppLocalizations.of(context);
    // The identifier field adapts to the station type: a callsign for radio
    // contacts, a phone number for SMS, or an email address for email.
    final String label;
    String? errorText;
    switch (_stationType) {
      case StationType.sms:
        label = l10n.stationPhoneNumber;
        break;
      case StationType.email:
        label = l10n.stationEmail;
        errorText = _callsignController.text.isNotEmpty && !_emailValid
            ? l10n.stationInvalidEmail
            : null;
        break;
      default:
        label = l10n.contactsColCallsign;
        errorText = _callsignController.text.isNotEmpty && !_callsignValid
            ? l10n.terminalInvalidCallsign
            : null;
    }
    return TextField(
      controller: _callsignController,
      enabled: !_isEditing,
      focusNode: _callsignFocusNode,
      keyboardType: _stationType == StationType.sms
          ? TextInputType.phone
          : (_stationType == StationType.email
              ? TextInputType.emailAddress
              : TextInputType.text),
      textCapitalization: _isSimpleContact
          ? TextCapitalization.none
          : TextCapitalization.characters,
      decoration: _inputDecoration(labelText: label, errorText: errorText),
      onChanged: (value) {
        // Only callsigns are force-uppercased; phone/email keep their casing.
        if (!_isSimpleContact) {
          final upper = value.toUpperCase();
          if (upper != value) {
            _callsignController.value = _callsignController.value.copyWith(
              text: upper,
              selection: TextSelection.collapsed(offset: upper.length),
            );
          }
        }
      },
    );
  }

  Widget _buildTypeDropdown() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<StationType>(
        initialValue: _typeOptions.any((o) => o.type == _stationType)
            ? _stationType
            : StationType.generic,
        decoration: _inputDecoration(labelText: l10n.stationTypeLabel),
        items: [
          for (final option in _typeOptions)
            DropdownMenuItem(
                value: option.type,
                child: Text(_typeLabel(option.type, l10n))),
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
    final l10n = AppLocalizations.of(context);
    return [
      if (_aprsRouteNames.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          initialValue: _aprsRouteNames.contains(_aprsRoute)
              ? _aprsRoute
              : _aprsRouteNames.first,
          decoration: _inputDecoration(labelText: l10n.stationAprsRoute),
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
        title: Text(l10n.stationUseAuth),
        value: _useAuth,
        onChanged: (value) => setState(() => _useAuth = value ?? false),
      ),
      if (_useAuth)
        TextField(
          controller: _authPasswordController,
          obscureText: true,
          decoration: _inputDecoration(
            labelText: l10n.stationAuthPassword,
            errorText: _useAuth && _authPasswordController.text.isEmpty
                ? l10n.stationPasswordRequired
                : null,
          ),
        ),
    ];
  }

  List<Widget> _buildTerminalFields() {
    final l10n = AppLocalizations.of(context);
    return [
      DropdownButtonFormField<TerminalProtocol>(
        initialValue: _terminalProtocol,
        decoration: _inputDecoration(labelText: l10n.stationTerminalProtocol),
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
            labelText: l10n.stationAx25Destination,
            errorText: _ax25DestController.text.isNotEmpty && !_ax25DestValid
                ? l10n.stationAx25Invalid
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
    final l10n = AppLocalizations.of(context);
    final current =
        _modemOptions.any((o) => o.value == _modem) ? _modem : 'Hardware';
    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: _inputDecoration(labelText: l10n.stationModem),
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
    final l10n = AppLocalizations.of(context);
    // Use a dropdown when channel names are available, otherwise free text.
    if (_channelNames.isEmpty) {
      return TextField(
        controller: _channelController,
        decoration: _inputDecoration(labelText: l10n.packetsColChannel),
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
      decoration: _inputDecoration(labelText: l10n.packetsColChannel),
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
