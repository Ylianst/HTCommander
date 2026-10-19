import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'tab_visibility.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'chat_widget.dart';
import 'callsign_license_line.dart';
import 'contact_avatar.dart';
import '../dialogs/aprs_configuration_dialog.dart';
import '../dialogs/aprs_details_dialog.dart';
import '../dialogs/aprs_sms_dialog.dart';
import '../dialogs/aprs_weather_dialog.dart';
import '../dialogs/dialog_utils.dart';
import '../dialogs/aprs_location_dialog.dart';
import '../dialogs/edit_beacon_settings_dialog.dart';
import '../dialogs/software_beacon_dialog.dart';
import '../handlers/software_beacon_config.dart';
import '../dialogs/digipeater_dialog.dart';
import '../dialogs/add_station_dialog.dart';
import '../dialogs/callsign_lookup_dialog.dart';
import '../dialogs/meshcore_dialogs.dart';
import '../l10n/app_localizations.dart';
import '../meshcore/meshcore_manager.dart' show meshCoreDeviceId, MeshCoreState;
import '../meshcore/meshcore_message.dart';
import '../meshcore/meshcore_protocol.dart'
    show
        MeshCoreConst,
        hopsFromPathLen,
        maxChannelTextBytes,
        meshCorePeerForKey,
        utf8Length;
import '../services/window_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../aprs/aprs_conversation.dart';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_symbols.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../models/radio_models.dart';
import '../models/station_info.dart';
import '../radio/radio_models.dart' as radio;
import '../radio/ax25_packet.dart';
import '../utils/channel_share.dart';

/// A configured APRS route (a display name plus a comma-separated path).
class _AprsRouteDef {
  final String name;
  final String path; // e.g. "APN000,WIDE1-1,WIDE2-2"
  const _AprsRouteDef(this.name, this.path);

  /// Route array in the form [name, dest, digi1, digi2, ...].
  List<String> toRouteArray() {
    final parts = path.split(',').where((p) => p.isNotEmpty).toList();
    return [name, ...parts];
  }
}

/// A single APRS chat entry. Holds the mutable display state that the C#
/// `ChatMessage` carried (image index, auth state, visibility) so we can update
/// delivery icons when ACK/REJ packets arrive.
class _AprsEntry {
  final AprsPacket aprsPacket;
  final AX25Packet packet;
  String routingString;
  final String senderCallsign;
  final String messageText;
  final DateTime time;
  final bool sender;
  final String? messageId;
  final PacketDataType messageType;
  int imageIndex; // -1 none, 0 ack, 1 rej, 3 position
  final AuthState authState;
  double? latitude;
  double? longitude;
  bool visible;
  // Peer callsign for Messenger-mode conversation grouping: the addressee for
  // sent messages, or the sender for messages addressed to us. Null for
  // packets that don't belong to one of our direct conversations.
  final String? peerCallsign;

  _AprsEntry({
    required this.aprsPacket,
    required this.packet,
    required this.routingString,
    required this.senderCallsign,
    required this.messageText,
    required this.time,
    required this.sender,
    required this.messageId,
    required this.messageType,
    required this.imageIndex,
    required this.authState,
    required this.visible,
    this.peerCallsign,
  });
}

/// A single Messenger-mode conversation: one peer callsign with its most recent
/// message preview. Contacts from the address book with no message history are
/// represented with an empty [lastMessage] and null [lastTime].
class _AprsConversation {
  final String callsign;
  final String? name;
  final String lastMessage;
  final DateTime? lastTime;
  final bool lastFromMe;

  const _AprsConversation({
    required this.callsign,
    required this.name,
    required this.lastMessage,
    required this.lastTime,
    required this.lastFromMe,
  });
}

/// A MeshCore conversation: a direct-message user (peer = key prefix) or a
/// group channel (peer = channel key).
class _MeshConversation {
  final String kind;
  final String peer;
  final String title;
  final String lastMessage;
  final DateTime? lastTime;
  final bool lastFromMe;

  const _MeshConversation({
    required this.kind,
    required this.peer,
    required this.title,
    required this.lastMessage,
    required this.lastTime,
    required this.lastFromMe,
  });

  String get key => '$kind:$peer';
}

/// One row of the merged conversation list: either an APRS or a MeshCore
/// conversation.
class _ListEntry {
  final _AprsConversation? aprs;
  final _MeshConversation? mesh;

  const _ListEntry.aprs(_AprsConversation this.aprs) : mesh = null;
  const _ListEntry.mesh(_MeshConversation this.mesh) : aprs = null;

  DateTime? get time => aprs?.lastTime ?? mesh?.lastTime;
}

/// APRS tab - Automatic Packet Reporting System
class AprsTab extends StatefulWidget {
  const AprsTab({super.key});

  @override
  State<AprsTab> createState() => _AprsTabState();
}

class _AprsTabState extends State<AprsTab>
    with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
  static const int _aprsDeviceId = 1;

  /// Bubble tint for packets gated in from the APRS-IS internet service. A
  /// softer periwinkle that stays in the blue family (visually related to RF
  /// traffic) while remaining easy to tell apart from RF messages at a glance.
  static const Color _internetColor = Color(0xFFAEB6E0);

  final DataBrokerClient _broker = DataBrokerClient();

  final List<_AprsEntry> _entries = [];
  List<ChatMessage> _messages = [];

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController(
    text: 'APRS',
  );
  final FocusNode _messageFocusNode = FocusNode();
  String _selectedDestination = 'APRS';
  bool _showAllMessages = false;
  bool _showAprsIs = true;
  bool _allowTransmit = true;
  bool _aprsIsEnabled = false;
  bool _historicalLoaded = false;
  bool _aprsIsHistoricalLoaded = false;

  // The APRS tab shows a Signal-style conversation list by default. Selecting
  // "All Messages" opens the combined APRS feed ([_viewAllMessages]); selecting
  // a contact opens a per-contact conversation ([_selectedContact]). When both
  // are unset the conversation list is shown.
  bool _viewAllMessages = false;
  // Selected conversation peer (uppercased callsign). Null shows the list.
  String? _selectedContact;
  // Display names for APRS stations from the address book, keyed by callsign.
  Map<String, String> _contactNames = {};
  // Avatar overrides (chosen logo / custom image) keyed by uppercased callsign.
  Map<String, ({String? icon, String? image})> _contactAvatars = {};
  // Configured APRS route name for each contact, keyed by contact id. Empty or
  // missing means the contact has no route preference.
  Map<String, String> _contactRoutes = {};
  // Uppercased ids of SMS/phone contacts; messages to these route via the SMS
  // gateway instead of being addressed to the id directly.
  Set<String> _smsContacts = {};
  // Uppercased ids of all messenger-eligible address-book contacts (APRS + SMS),
  // shown in the conversation list even without message history.
  List<String> _addressBookIds = [];

  // MeshCore (device 204) state. The "All MeshCore Messages" feed is
  // [_viewAllMesh]; a MeshCore conversation is [_selectedMesh] ("kind:peer").
  bool _viewAllMesh = false;
  String? _selectedMesh;
  final List<MeshCoreMessage> _meshMessages = [];
  List<Map<dynamic, dynamic>> _meshContacts = const [];
  List<Map<dynamic, dynamic>> _meshChannels = const [];
  String _meshState = MeshCoreState.disconnected;
  String _meshSelfName = '';
  bool _meshConfigured = false;

  /// Mirrors the 'MeshCoreSupport' feature setting; when false every MeshCore
  /// entry point in this tab is hidden.
  bool _meshEnabled = false;

  /// Address-book MeshCore users keyed by conversation peer (key prefix).
  Map<String, StationInfo> _meshBook = {};
  final TextEditingController _meshController = TextEditingController();

  // Local station identity (from device 0).
  String _callsign = '';
  String _stationId = '';

  // Destinations shown in the combo box.
  List<String> _destinations = ['ALL', 'QST', 'CQ'];

  // APRS routes for digipeater paths.
  List<_AprsRouteDef> _aprsRoutes = [];
  int _selectedRouteIndex = 0;

  // Channel availability state for the missing-channel banner.
  bool _hasAprsChannel = false;
  bool _showMissingChannel = false;

  /// Latest lock state reported for each radio device id. While the radio the
  /// APRS tab would transmit on is locked to another usage (BBS, Terminal,
  /// Winlink, Torrent, ...) no APRS data may be sent.
  final Map<int, RadioLockState> _lockStates = {};

  // Beacon banner state.
  int _beaconInterval = 0; // seconds; 0 = off
  bool _beaconOnCurrentChannel = false;

  // Software beacon indicator state.
  SoftwareBeaconConfig _softwareBeacon = const SoftwareBeaconConfig();
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Load persisted settings from device 0.
    _callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final stationIdInt = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    _stationId = stationIdInt > 0 ? stationIdInt.toString() : '';
    _allowTransmit = (_broker.getValue<int>(0, 'AllowTransmit', 1) ?? 1) != 0;
    _aprsIsEnabled = (_broker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) != 0;
    _showAllMessages =
        (_broker.getValue<int>(0, 'AprsShowTelemetry', 0) ?? 0) != 0;
    _showAprsIs = (_broker.getValue<int>(0, 'AprsShowAprsIs', 1) ?? 1) != 0;
    _selectedRouteIndex = _broker.getValue<int>(0, 'SelectedAprsRoute', 0) ?? 0;
    _parseAndSetRoutes(_broker.getValue<String>(0, 'AprsRoutes', '') ?? '');
    final savedDest = _broker.getValue<String>(0, 'AprsDestination', '') ?? '';
    if (savedDest.isNotEmpty) {
      _selectedDestination = savedDest;
      _destinationController.text = savedDest;
    }
    _loadStationDestinations();

    // Re-evaluate the send button enabled state as the user edits the fields.
    _destinationController.addListener(_onInputChanged);
    _messageController.addListener(_onInputChanged);

    // Subscribe to live APRS events.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsFrame',
      callback: _onAprsFrame,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsPacketList',
      callback: _onAprsPacketList,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsStoreReady',
      callback: _onAprsStoreReady,
    );

    // Clears made here or in another window (detached window, or the hosted
    // web page forwarding its clears to this desktop host).
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'ClearAprsPackets',
      callback: _onClearAprsPackets,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: clearAprsConversationEvent,
      callback: _onClearAprsConversation,
    );

    // Persisted internet (APRS-IS) history, served by the APRS-IS manager.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsIsPacketList',
      callback: _onAprsIsPacketList,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsIsStoreReady',
      callback: _onAprsIsStoreReady,
    );

    // Keep the APRS-IS visibility filter in sync with the Map tab.
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsShowAprsIs',
      callback: (_, _, data) {
        final show = (data is int ? data : 1) == 1;
        if (show == _showAprsIs || !mounted) return;
        setState(() {
          _showAprsIs = show;
          for (final e in _entries) {
            e.visible = _computeVisible(
              e.messageType,
              e.aprsPacket.fromAprsIs,
              e.sender,
            );
          }
        });
        _rebuildMessages();
      },
    );

    // Handle "Message this station" requests dispatched from the Map tab's
    // station context menu (device 0, key 'AprsMessageStation', data =
    // callsign). Opens a conversation in Messenger mode or pre-fills the
    // destination in the classic feed.
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsMessageStation',
      callback: _onMessageStationRequested,
    );

    // Cloud push (HTCloudServer) asks us to open a sender's conversation when a
    // notification is tapped. The request may arrive before this tab is built
    // (the tap also switches to this tab), so it is sent as a retained signal:
    // handled live here for an already-open tab, and read once in initState
    // below for a freshly-built tab.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsOpenConversation',
      callback: _onOpenConversationRequested,
    );

    // Re-tapping the APRS tab icon while it is already active returns the view
    // to the conversation list.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'AprsShowContactList',
      callback: (_, _, _) {
        if (!mounted) return;
        if (!_hasContent) return;
        _closeConversation();
      },
    );

    _initMeshCore();

    // Subscribe to settings changes from device 0.
    _broker.subscribeMultiple(
      deviceId: 0,
      names: const [
        'CallSign',
        'StationId',
        'AprsRoutes',
        'AllowTransmit',
        'AprsIsEnabled',
        'Stations',
        'AprsCloudAvatars',
      ],
      callback: _onSettingsChanged,
    );

    // Subscribe to radio/channel changes for the missing-channel banner.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'ConnectedRadios',
      callback: _onChannelStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Channels',
      callback: _onChannelStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AllChannelsLoaded',
      callback: _onChannelStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockStateChanged,
    );

    // Subscribe to beacon-related settings changes.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'BssSettings',
      callback: _onBeaconStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Settings',
      callback: _onBeaconStateChanged,
    );

    _broker.subscribe(
      deviceId: 0,
      name: 'SoftwareBeaconConfig',
      callback: _onSoftwareBeaconConfigChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SoftwareBeaconSent',
      callback: _onSoftwareBeaconSent,
    );

    _recomputeChannelState();
    _recomputeBeaconState();
    _loadSoftwareBeaconConfig();
    _seedLockStates();

    // Request the historical APRS packet list.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );

    // Request the persisted internet (APRS-IS) history.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsIsPackets',
      data: null,
      store: false,
    );

    // If a cloud-push notification tap requested opening a conversation before
    // this tab existed, the request was retained on the broker. Consume it now.
    final pendingOpen =
        (_broker.getValue<String>(_aprsDeviceId, 'AprsOpenConversation', '') ??
                '')
            .trim();
    if (pendingOpen.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onOpenConversationRequested(
          _aprsDeviceId,
          'AprsOpenConversation',
          pendingOpen,
        );
      });
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    _messageController.dispose();
    _destinationController.dispose();
    _meshController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MeshCore
  // ---------------------------------------------------------------------------

  void _initMeshCore() {
    _applyMeshState(_broker.getValueDynamic(meshCoreDeviceId, 'MeshCoreState'));
    _applyMeshInfo(_broker.getValueDynamic(meshCoreDeviceId, 'MeshCoreInfo'));
    _meshContacts = _mapList(
      _broker.getValueDynamic(meshCoreDeviceId, 'MeshCoreContacts'),
    );
    _meshChannels = _mapList(
      _broker.getValueDynamic(meshCoreDeviceId, 'MeshCoreChannels'),
    );
    _meshConfigured =
        _broker.getValueDynamic(0, 'MeshCoreLastDevice', null) is Map;
    _meshEnabled = _broker.getValue<int>(0, 'MeshCoreSupport', 0) == 1;
    _broker.subscribe(
      deviceId: 0,
      name: 'MeshCoreSupport',
      callback: (_, _, data) {
        if (!mounted) return;
        final enabled = data == 1;
        if (enabled == _meshEnabled) return;
        setState(() => _meshEnabled = enabled);
        if (!enabled && _inMeshView) _closeConversation();
      },
    );
    _meshController.addListener(() {
      if (mounted) setState(() {});
    });

    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreState',
      callback: (_, _, data) {
        if (!mounted) return;
        setState(() {
          _applyMeshState(data);
          if (_meshState == MeshCoreState.connected) _meshConfigured = true;
        });
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreInfo',
      callback: (_, _, data) {
        if (mounted) setState(() => _applyMeshInfo(data));
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreContacts',
      callback: (_, _, data) {
        if (mounted) setState(() => _meshContacts = _mapList(data));
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreChannels',
      callback: (_, _, data) {
        if (mounted) setState(() => _meshChannels = _mapList(data));
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessageList',
      callback: (_, _, data) {
        if (!mounted || data is! List) return;
        setState(() {
          _meshMessages
            ..clear()
            ..addAll(data.whereType<Map>().map(MeshCoreMessage.fromJson));
        });
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessage',
      callback: (_, _, data) {
        if (!mounted || data is! Map) return;
        final msg = MeshCoreMessage.fromJson(data);
        setState(() {
          final i = _meshMessages.indexWhere((m) => m.id == msg.id);
          if (i >= 0) {
            _meshMessages[i] = msg;
          } else {
            _meshMessages.add(msg);
          }
        });
      },
    );
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessagesCleared',
      callback: (_, _, data) {
        if (!mounted || data is! Map) return;
        final kind = data['kind'];
        final peer = data['peer'];
        setState(() {
          if (kind == null || peer == null) {
            _meshMessages.clear();
          } else {
            _meshMessages.removeWhere((m) => m.kind == kind && m.peer == peer);
          }
        });
      },
    );
    // "Message" from a MeshCore node on the Map tab ("kind:peer").
    _broker.subscribe(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreOpenConversation',
      callback: (_, _, data) => _onMeshOpenRequested(data),
    );
    // A request made before this tab existed (notification tap or Map "Message"
    // that also switched to this tab) is retained on the broker.
    final pendingMesh = _broker.getValue<String>(
      meshCoreDeviceId,
      'MeshCoreOpenConversation',
      '',
    );
    if (pendingMesh != null && pendingMesh.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onMeshOpenRequested(pendingMesh),
      );
    }
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'RequestMeshCoreMessages',
      data: null,
      store: false,
    );
  }

  static List<Map<dynamic, dynamic>> _mapList(Object? data) =>
      data is List ? data.whereType<Map>().toList() : const [];

  /// Opens the MeshCore conversation ("kind:peer") requested by a notification
  /// tap or the Map tab, then clears the retained request.
  void _onMeshOpenRequested(Object? data) {
    if (!mounted || data is! String || data.isEmpty) return;
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreOpenConversation',
      data: '',
      store: true,
    );
    final sep = data.indexOf(':');
    if (!_meshEnabled || sep <= 0 || sep == data.length - 1) return;
    _openMeshConversation(data);
  }

  void _applyMeshState(Object? data) {
    if (data is Map) {
      _meshState = data['state']?.toString() ?? MeshCoreState.disconnected;
    }
  }

  void _applyMeshInfo(Object? data) {
    _meshSelfName = data is Map ? (data['name']?.toString() ?? '') : '';
  }

  bool get _meshConnected => _meshState == MeshCoreState.connected;

  bool get _inMeshView => _viewAllMesh || _selectedMesh != null;

  /// Whether a feed or conversation (rather than the list) is open.
  bool get _hasContent =>
      _viewAllMessages || _selectedContact != null || _inMeshView;

  Map<dynamic, dynamic>? _meshContactByPrefix(String prefix) =>
      _meshContacts.where((c) => c['prefix'] == prefix).firstOrNull;

  Map<dynamic, dynamic>? _meshChannelByKey(String key) =>
      _meshChannels.where((c) => c['key'] == key).firstOrNull;

  String _meshTitle(String kind, String peer) {
    if (kind == MeshCoreKind.group) {
      final name = _meshChannelByKey(peer)?['name']?.toString();
      return (name == null || name.isEmpty) ? peer : name;
    }
    // The address-book name wins over the name the node advertises.
    final bookName = _meshBook[peer]?.name;
    if (bookName != null && bookName.isNotEmpty) return bookName;
    final name = _meshContactByPrefix(peer)?['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    // Fall back to the name stored with an incoming message.
    final msg = _meshMessages
        .where((m) => m.peer == peer && !m.outgoing && m.sender.isNotEmpty)
        .lastOrNull;
    return msg?.sender ?? peer;
  }

  /// Avatar for a MeshCore direct-message peer, using the address-book logo or
  /// image when the user is a contact.
  Widget _meshUserAvatar(String peer, {double radius = 20}) {
    final book = _meshBook[peer];
    final key =
        book?.callsign ?? _meshContactByPrefix(peer)?['key']?.toString() ?? peer;
    return ContactAvatar(
      callsign: key,
      avatarIcon: book?.avatarIcon,
      avatarImage: book?.avatarImage,
      initials: nameInitials(_meshTitle(MeshCoreKind.user, peer)),
      radius: radius,
    );
  }

  /// Opens the contact dialog for a MeshCore user: edits the address-book
  /// entry, or creates one prefilled from the radio's contact for [peer].
  Future<void> _editMeshContact(String peer) async {
    final existing = _meshBook[peer];
    final radio = _meshContactByPrefix(peer);
    final result = await showStationDialog(
      context,
      existing: existing,
      fixedType: StationType.meshCore,
      initialCallsign: radio?['key']?.toString(),
      initialName: existing == null
          ? _meshTitle(MeshCoreKind.user, peer)
          : null,
    );
    if (result == null || !mounted) return;
    _saveStation(result);
    final newPeer = meshCorePeerForKey(result.callsign);
    if (newPeer != peer) _openMeshConversation('${MeshCoreKind.user}:$newPeer');
  }

  /// Adds or replaces [station] (matched by ID and type) in the address book.
  void _saveStation(StationInfo station) {
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    final stations = <StationInfo>[
      if (raw is List)
        for (final item in raw)
          if (item is Map) StationInfo.fromJson(Map<String, dynamic>.from(item)),
    ];
    stations.removeWhere(
      (s) =>
          s.callsign == station.callsign &&
          s.stationType == station.stationType,
    );
    stations.add(station);
    _broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  /// MeshCore conversations: group channels on the radio, plus users who are
  /// HTCommander contacts. Other users the radio knows (it can remember many)
  /// get no thread; their direct messages stay in "All MeshCore Messages",
  /// where they can be added as contacts.
  List<_MeshConversation> _buildMeshConversations() {
    final latest = <String, MeshCoreMessage>{};
    for (final m in _meshMessages) {
      if (m.kind == MeshCoreKind.user && !_meshBook.containsKey(m.peer)) {
        continue;
      }
      final existing = latest[m.conversationKey];
      if (existing == null || !m.time.isBefore(existing.time)) {
        latest[m.conversationKey] = m;
      }
    }
    final result = <_MeshConversation>[
      for (final m in latest.values)
        _MeshConversation(
          kind: m.kind,
          peer: m.peer,
          title: _meshTitle(m.kind, m.peer),
          lastMessage: m.kind == MeshCoreKind.group && !m.outgoing
              ? '${m.sender}: ${m.text}'
              : m.text,
          lastTime: m.time,
          lastFromMe: m.outgoing,
        ),
    ];
    void addIdle(String kind, String peer) {
      if (peer.isEmpty || latest.containsKey('$kind:$peer')) return;
      result.add(
        _MeshConversation(
          kind: kind,
          peer: peer,
          title: _meshTitle(kind, peer),
          lastMessage: '',
          lastTime: null,
          lastFromMe: false,
        ),
      );
    }

    for (final ch in _meshChannels) {
      addIdle(MeshCoreKind.group, ch['key']?.toString() ?? '');
    }
    for (final peer in _meshBook.keys) {
      addIdle(MeshCoreKind.user, peer);
    }
    return result;
  }

  void _openAllMesh() {
    setState(() {
      _viewAllMessages = false;
      _selectedContact = null;
      _selectedMesh = null;
      _viewAllMesh = true;
    });
  }

  void _openMeshConversation(String key) {
    setState(() {
      _viewAllMessages = false;
      _selectedContact = null;
      _viewAllMesh = false;
      _selectedMesh = key;
      _meshController.clear();
    });
  }

  ({String kind, String peer})? get _selectedMeshParts {
    final key = _selectedMesh;
    if (key == null) return null;
    final i = key.indexOf(':');
    return (kind: key.substring(0, i), peer: key.substring(i + 1));
  }

  /// UTF-8 bytes the composer may still use in the selected conversation.
  int get _meshBytesLeft {
    final sel = _selectedMeshParts;
    if (sel == null) return 0;
    final max = sel.kind == MeshCoreKind.group
        ? maxChannelTextBytes(_meshSelfName)
        : MeshCoreConst.maxTextBytes;
    return max - utf8Length(_meshController.text.trim());
  }

  bool get _canSendMesh {
    final sel = _selectedMeshParts;
    if (sel == null || !_meshConnected) return false;
    if (_meshController.text.trim().isEmpty || _meshBytesLeft < 0) {
      return false;
    }
    if (sel.kind == MeshCoreKind.group) {
      return _meshChannelByKey(sel.peer) != null;
    }
    return true;
  }

  void _sendMesh() {
    final sel = _selectedMeshParts;
    if (sel == null || !_canSendMesh) return;
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: sel.kind == MeshCoreKind.group
          ? 'MeshCoreSendGroup'
          : 'MeshCoreSendDirect',
      data: {'peer': sel.peer, 'text': _meshController.text.trim()},
      store: false,
    );
    _meshController.clear();
  }

  Future<void> _addMeshConversation(bool group) async {
    if (!group) {
      // Users are address-book contacts; the manager adds them to the radio.
      final station = await showStationDialog(
        context,
        fixedType: StationType.meshCore,
      );
      if (station == null || !mounted) return;
      _saveStation(station);
      _openMeshConversation(
        '${MeshCoreKind.user}:${meshCorePeerForKey(station.callsign)}',
      );
      return;
    }
    if (!_meshConnected) {
      await showMeshCoreConnectionDialog(context);
      if (!mounted || !_meshConnected) return;
    }
    final peer = await showMeshCoreAddGroupDialog(context);
    if (peer == null || !mounted) return;
    _openMeshConversation('${MeshCoreKind.group}:$peer');
  }

  ChatMessage _meshToChat(MeshCoreMessage m, AppLocalizations l10n) {
    final parts = <String>[];
    if (_viewAllMesh) parts.add(_meshTitle(m.kind, m.peer));
    if (m.outgoing) {
      parts.add(_meshSelfName.isEmpty ? m.sender : _meshSelfName);
    } else {
      if (m.kind == MeshCoreKind.group && m.sender.isNotEmpty) {
        parts.add(m.sender);
      }
      final hops = m.pathLen == null ? null : hopsFromPathLen(m.pathLen!);
      parts.add(hops == null ? l10n.meshDirect : l10n.meshHops(hops));
      if (m.snr != null) parts.add('SNR ${m.snr!.toStringAsFixed(1)} dB');
    }
    final (IconData? icon, Color? color) = switch (m.state) {
      MeshCoreDelivery.pending => (Icons.schedule, null),
      MeshCoreDelivery.sent => (Icons.done, null),
      MeshCoreDelivery.delivered => (Icons.done_all, Colors.green),
      MeshCoreDelivery.failed => (Icons.error_outline, Colors.red),
      _ => (null, null),
    };
    return ChatMessage(
      id: 'mc-${m.id}',
      route: parts.where((p) => p.isNotEmpty).join(' · '),
      senderCallsign: m.sender,
      message: m.text.isEmpty ? ' ' : m.text,
      time: m.time,
      isSender: m.outgoing,
      icon: icon,
      iconColor: color,
      tag: m,
    );
  }

  /// The direct-message peer (key prefix) who sent [m], or null when unknown.
  /// Group messages carry only the sender's display name, so the sender is
  /// resolved only when exactly one companion user the radio knows has that
  /// name.
  String? _meshSenderPeer(MeshCoreMessage m) {
    if (m.outgoing) return null;
    if (m.kind == MeshCoreKind.user) return m.peer;
    if (m.sender.isEmpty || m.sender == _meshSelfName) return null;
    final matches = _meshContacts
        .where((c) => c['type'] == 1 && c['name']?.toString() == m.sender)
        .toList();
    return matches.length == 1 ? matches.first['prefix']?.toString() : null;
  }

  /// Full public key for a direct-message peer, when the address book or the
  /// radio knows it.
  String? _meshKeyForPeer(String peer) =>
      _meshBook[peer]?.callsign ?? _meshContactByPrefix(peer)?['key']?.toString();

  /// The callsign the sender's name starts with (e.g. "KK7VZT-Base"). The
  /// name the node advertises is tried before the address-book name.
  String? _meshCallsignFor(MeshCoreMessage m) {
    if (m.outgoing) return null;
    final names = <String>[
      m.sender,
      if (m.kind == MeshCoreKind.user) ...[
        _meshContactByPrefix(m.peer)?['name']?.toString() ?? '',
        _meshBook[m.peer]?.name ?? '',
      ],
    ];
    for (final n in names) {
      final cs = callsignFromName(n);
      if (cs != null) return cs;
    }
    return null;
  }

  Future<void> _showMeshDetails(MeshCoreMessage m) async {
    final callsign = _meshCallsignFor(m);
    final license = callsign == null
        ? null
        : await lookupCallsignRecord(callsign);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final group = m.kind == MeshCoreKind.group;
    final senderPeer = _meshSenderPeer(m);
    final senderKey = senderPeer == null ? null : _meshKeyForPeer(senderPeer);
    String fmt(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final hops = m.pathLen == null ? null : hopsFromPathLen(m.pathLen!);
    final state = switch (m.state) {
      MeshCoreDelivery.pending => l10n.meshDeliveryPending,
      MeshCoreDelivery.sent => l10n.meshDeliverySent,
      MeshCoreDelivery.delivered => l10n.meshDeliveryDelivered,
      MeshCoreDelivery.failed => l10n.meshDeliveryFailed,
      _ => l10n.meshDeliveryReceived,
    };
    final self = _meshSelfName.isEmpty ? m.sender : _meshSelfName;
    final from = m.outgoing
        ? self
        : group
        ? '${m.sender.isEmpty ? '?' : m.sender} (${l10n.meshUnverified})'
        : _meshTitle(MeshCoreKind.user, m.peer);
    AprsDetailsDialog.show(
      context,
      title: l10n.meshDetailsTitle,
      items: [
        AprsDetailItem(
          l10n.meshDetailType,
          group ? l10n.meshGroupMessage : l10n.meshDirectMessage,
        ),
        AprsDetailItem(
          l10n.meshDetailConversation,
          _meshTitle(m.kind, m.peer),
        ),
        AprsDetailItem(l10n.meshDetailFrom, from),
        if (callsign != null) ...[
          AprsDetailItem(l10n.cslFieldCallsign, callsign),
          if (licenseGradeText(license) != null)
            AprsDetailItem(l10n.cslFieldClass, licenseGradeText(license)!),
          if (license != null && license.name.isNotEmpty)
            AprsDetailItem(l10n.cslFieldName, license.name),
          if (license != null && license.location.isNotEmpty)
            AprsDetailItem(l10n.cslFieldLocation, license.location),
        ],
        if (m.outgoing && !group)
          AprsDetailItem(
            l10n.meshDetailTo,
            _meshTitle(MeshCoreKind.user, m.peer),
          ),
        if (senderKey != null)
          AprsDetailItem(l10n.meshPublicKey, senderKey)
        else if (!m.outgoing && !group)
          AprsDetailItem(l10n.meshDetailKeyPrefix, m.peer),
        AprsDetailItem(l10n.meshDetailTime, fmt(m.time)),
        if (m.senderTime > 0)
          AprsDetailItem(
            l10n.meshDetailSenderTime,
            fmt(DateTime.fromMillisecondsSinceEpoch(m.senderTime * 1000)),
          ),
        if (!m.outgoing)
          AprsDetailItem(
            l10n.meshDetailRoute,
            hops == null ? l10n.meshDirect : l10n.meshHops(hops),
          ),
        if (m.snr != null)
          AprsDetailItem('SNR', '${m.snr!.toStringAsFixed(2)} dB'),
        AprsDetailItem(l10n.meshDetailDelivery, state),
        AprsDetailItem(
          l10n.meshDetailLength,
          l10n.meshDetailBytes(utf8Length(m.text)),
        ),
        AprsDetailItem(l10n.meshDetailMessage, m.text),
      ],
    );
  }

  Future<void> _onMeshContextMenu(ChatMessage message, Offset position) async {
    final m = message.tag;
    if (m is! MeshCoreMessage) return;
    final l10n = AppLocalizations.of(context);
    final canResend =
        m.outgoing && m.state == MeshCoreDelivery.failed && _meshConnected;
    // Offer to add the sender only when they are not a contact yet and their
    // key can be found (always for direct messages).
    final senderPeer = _meshSenderPeer(m);
    final canAddContact =
        senderPeer != null &&
        !_meshBook.containsKey(senderPeer) &&
        (m.kind == MeshCoreKind.user || _meshKeyForPeer(senderPeer) != null);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'details', child: Text(l10n.aprsDetails)),
        PopupMenuItem(value: 'copy', child: Text(l10n.aprsCopyMessage)),
        if (canResend)
          PopupMenuItem(value: 'resend', child: Text(l10n.meshResend)),
        if (_viewAllMesh)
          PopupMenuItem(
            value: 'open',
            child: Text(_meshTitle(m.kind, m.peer)),
          ),
        if (canAddContact)
          PopupMenuItem(value: 'addContact', child: Text(l10n.aprsAddContact)),
        if (_meshCallsignFor(m) != null)
          PopupMenuItem(value: 'lookup', child: Text(l10n.callsignLookup)),
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'details':
        _showMeshDetails(m);
      case 'lookup':
        CallsignLookupDialog.show(
          context,
          initialCallsign: _meshCallsignFor(m),
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
      case 'resend':
        _broker.dispatch(
          deviceId: meshCoreDeviceId,
          name: 'MeshCoreResend',
          data: {'id': m.id},
          store: false,
        );
      case 'open':
        _openMeshConversation(m.conversationKey);
      case 'addContact':
        await _editMeshContact(senderPeer!);
    }
  }

  Widget _buildMeshContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sel = _selectedMeshParts;
    final messages = [
      for (final m in _meshMessages)
        if (sel == null || (m.kind == sel.kind && m.peer == sel.peer))
          _meshToChat(m, l10n),
    ];
    return Column(
      children: [
        if (!_meshConnected)
          MaterialBanner(
            content: Text(l10n.meshNotConnected),
            actions: [
              TextButton(
                onPressed: () => showMeshCoreConnectionDialog(context),
                child: Text(l10n.meshConnectionMenu),
              ),
            ],
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatWidget(
                  messages: messages,
                  onMessageContextMenu: _onMeshContextMenu,
                  onMessageDoubleTap: (msg) {
                    final m = msg.tag;
                    if (m is! MeshCoreMessage) return;
                    // In the combined feed, double-click opens the thread;
                    // inside a thread it shows the message details.
                    if (_viewAllMesh) {
                      _openMeshConversation(m.conversationKey);
                    } else {
                      _showMeshDetails(m);
                    }
                  },
                ),
              ),
              if (sel != null && sel.kind == MeshCoreKind.user)
                _buildMeshAvatarOverlay(sel.peer),
            ],
          ),
        ),
        if (sel != null) _buildMeshInputPanel(l10n),
      ],
    );
  }

  /// Corner avatar for a MeshCore user conversation (same look as the APRS
  /// one). Tapping it edits the contact, or adds it to the address book.
  Widget _buildMeshAvatarOverlay(String peer) {
    final scheme = Theme.of(context).colorScheme;
    const double corner = 104;
    return Positioned(
      top: 0,
      right: 0,
      child: SizedBox(
        width: corner,
        height: corner,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CornerTrianglePainter(scheme.surfaceContainerHigh),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: _meshTitle(MeshCoreKind.user, peer),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _editMeshContact(peer),
                  child: _meshUserAvatar(peer, radius: 32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeshInputPanel(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final left = _meshBytesLeft;
    return Container(
      height: 50,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(color: scheme.onSurfaceVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _meshController,
                enabled: _meshConnected,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _meshConnected
                      ? l10n.meshTypeMessage
                      : l10n.meshNotConnected,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _sendMesh(),
              ),
            ),
          ),
          if (left < 40) ...[
            const SizedBox(width: 8),
            Text(
              l10n.meshBytesLeft(left),
              style: TextStyle(
                fontSize: 12,
                color: left < 0 ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _canSendMesh ? _sendMesh : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Icon(Icons.send, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshStatusIcon() {
    final l10n = AppLocalizations.of(context);
    final (Color color, String tip) = switch (_meshState) {
      MeshCoreState.connected => (Colors.green, l10n.meshStatusConnected),
      MeshCoreState.error => (Colors.red, l10n.meshStatusError),
      MeshCoreState.disconnected => (
        Theme.of(context).colorScheme.outline,
        l10n.meshStatusDisconnected,
      ),
      _ => (Colors.orange, l10n.meshStatusConnecting),
    };
    return Tooltip(
      message: 'MeshCore: $tip',
      child: InkWell(
        onTap: () => showMeshCoreConnectionDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.hub, size: 20, color: color),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings / routes / destinations
  // ---------------------------------------------------------------------------

  void _parseAndSetRoutes(String routesStr) {
    final routes = <_AprsRouteDef>[];
    if (routesStr.isNotEmpty) {
      final parts = routesStr.split('|');
      // Stored as "Name|Path|Name|Path...".
      for (var i = 0; i + 1 < parts.length; i += 2) {
        if (parts[i].isNotEmpty) {
          routes.add(_AprsRouteDef(parts[i], parts[i + 1]));
        }
      }
    }
    _aprsRoutes = routes;
    if (_selectedRouteIndex >= _aprsRoutes.length) _selectedRouteIndex = 0;
  }

  void _loadStationDestinations() {
    final dests = <String>['ALL', 'QST', 'CQ'];
    final names = <String, String>{};
    final avatars = <String, ({String? icon, String? image})>{};
    final routes = <String, String>{};
    final smsContacts = <String>{};
    final addressBookIds = <String>[];
    final meshBook = <String, StationInfo>{};
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['Callsign'] ?? item['callsign'] ?? '')
            .toString()
            .trim();
        if (id.isEmpty) continue;
        final typeRaw = item['StationType'] ?? item['stationType'];
        final typeStr = '$typeRaw'.toLowerCase();
        final typeIndex = typeRaw is int ? typeRaw : int.tryParse(typeStr);
        final isAprs = typeIndex == 1 || typeStr == 'aprs';
        final isSms = typeIndex == 7 || typeStr == 'sms';

        // MeshCore users are keyed by their 6-byte key prefix, which is how
        // the companion identifies direct-message senders.
        if (typeIndex == StationType.meshCore.index ||
            typeStr == StationType.meshCore.name.toLowerCase()) {
          final station = StationInfo.fromJson(item);
          meshBook[meshCorePeerForKey(station.callsign)] = station;
          continue;
        }

        if (isAprs && !dests.contains(id)) dests.add(id);
        // Only APRS and SMS contacts take part in Messenger conversations.
        if (!isAprs && !isSms) continue;

        // SMS contacts are keyed by their digits-only phone number so gateway
        // messages ("@<phone> ...") thread into the matching contact.
        final key = isSms ? _digitsOnly(id) : _peerKey(id);
        if (key.isEmpty) continue;
        if (!addressBookIds.contains(key)) addressBookIds.add(key);
        if (isSms) smsContacts.add(key);

        final name = (item['Name'] ?? item['name'])?.toString().trim() ?? '';
        if (name.isNotEmpty) names[key] = name;

        final route =
            (item['APRSRoute'] ?? item['aprsRoute'])?.toString().trim() ?? '';
        if (route.isNotEmpty) routes[key] = route;

        final icon = (item['AvatarIcon'] ?? item['avatarIcon'])?.toString();
        final image = (item['AvatarImage'] ?? item['avatarImage'])?.toString();
        if ((icon != null && icon.isNotEmpty) ||
            (image != null && image.isNotEmpty)) {
          avatars[key] = (
            icon: (icon != null && icon.isNotEmpty) ? icon : null,
            image: (image != null && image.isNotEmpty) ? image : null,
          );
        }
      }
    }
    _destinations = dests;
    _contactNames = names;
    _contactAvatars = avatars;
    _contactRoutes = routes;
    _smsContacts = smsContacts;
    _addressBookIds = addressBookIds;
    _meshBook = meshBook;
    _mergeCloudAvatars();
  }

  /// Merges avatars learned from cloud-push notifications into [_contactAvatars]
  /// as a fallback, so a sender's avatar shows even when they are not in the
  /// address book. Address-book entries always win, so a user's own overrides
  /// are never replaced.
  void _mergeCloudAvatars() {
    final raw = _broker.getValueDynamic(0, 'AprsCloudAvatars', null);
    if (raw is! Map) return;
    raw.forEach((k, v) {
      final key = '$k'.toUpperCase();
      if (key.isEmpty || _contactAvatars.containsKey(key) || v is! Map) return;
      final icon = v['icon']?.toString();
      final image = v['image']?.toString();
      final hasIcon = icon != null && icon.isNotEmpty;
      final hasImage = image != null && image.isNotEmpty;
      if (!hasIcon && !hasImage) return;
      _contactAvatars[key] = (
        icon: hasIcon ? icon : null,
        image: hasImage ? image : null,
      );
    });
  }

  void _onSettingsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      switch (name) {
        case 'CallSign':
          _callsign = data as String? ?? '';
          break;
        case 'StationId':
          final id = data is int ? data : int.tryParse('$data') ?? 0;
          _stationId = id > 0 ? id.toString() : '';
          break;
        case 'AprsRoutes':
          _parseAndSetRoutes(data as String? ?? '');
          break;
        case 'AllowTransmit':
          final v = data is int ? data : int.tryParse('$data') ?? 0;
          _allowTransmit = v != 0;
          break;
        case 'AprsIsEnabled':
          final v = data is int ? data : int.tryParse('$data') ?? 0;
          _aprsIsEnabled = v != 0;
          break;
        case 'Stations':
          _loadStationDestinations();
          break;
        case 'AprsCloudAvatars':
          _loadStationDestinations();
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Channel availability
  // ---------------------------------------------------------------------------

  void _onChannelStateChanged(int deviceId, String name, Object? data) {
    _recomputeChannelState();
  }

  void _onLockStateChanged(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    setState(() {
      _lockStates[deviceId] = RadioLockState.fromJson(
        Map<String, dynamic>.from(data),
      );
    });
    // APRSSat mode allows transmit without an APRS channel, so re-evaluate the
    // "missing APRS channel" warning as the lock is taken or released.
    _recomputeChannelState();
  }

  /// Seeds the current lock state for every connected radio from the broker, so
  /// a radio that is already locked when the tab is built disables transmit
  /// without waiting for the next LockState broadcast.
  void _seedLockStates() {
    for (final id in _connectedRadioDeviceIds()) {
      final data = _broker.getValueDynamic(id, 'LockState', null);
      if (data is Map) {
        _lockStates[id] = RadioLockState.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
    }
  }

  /// Device id of a connected radio locked in APRSSat mode (tracking an APRS
  /// satellite via VFO A), or -1. In this mode all of the radio's traffic is
  /// APRS, so the tab may transmit even without a dedicated "APRS" channel.
  int get _aprsSatRadioDeviceId {
    for (final id in _connectedRadioDeviceIds()) {
      final ls = _lockStates[id];
      if (ls != null && ls.isLocked && ls.usage == 'APRSSat') return id;
    }
    return -1;
  }

  /// True when a connected radio is currently in APRSSat mode.
  bool get _isAprsSatActive => _aprsSatRadioDeviceId >= 0;

  /// Whether the radio the APRS tab would transmit on is locked to a usage
  /// that blocks APRS activity (BBS, Terminal, Winlink, Torrent, ...).
  ///
  /// The digipeater usage is intentionally excluded: while the digipeater holds
  /// the lock the radio stays on the APRS channel, so the user is still allowed
  /// to send APRS messages and to open the digipeater dialog.
  bool get _isRadioLockedForOtherUsage {
    final id = _getPreferredAprsRadioDeviceId();
    if (id <= 0) return false;
    final ls = _lockStates[id];
    return ls != null && ls.isLocked && ls.usage != 'Digipeater';
  }

  void _onBeaconStateChanged(int deviceId, String name, Object? data) {
    _recomputeBeaconState();
  }

  void _onSoftwareBeaconConfigChanged(int deviceId, String name, Object? data) {
    _loadSoftwareBeaconConfig();
  }

  void _loadSoftwareBeaconConfig() {
    var config = const SoftwareBeaconConfig();
    final raw = _broker.getValueDynamic(0, 'SoftwareBeaconConfig', null);
    try {
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          config = SoftwareBeaconConfig.fromJson(decoded);
        }
      } else if (raw is Map<String, dynamic>) {
        config = SoftwareBeaconConfig.fromJson(raw);
      }
    } catch (_) {
      // Malformed configuration: treat the software beacon as off.
    }
    if (!mounted) {
      _softwareBeacon = config;
      return;
    }
    setState(() => _softwareBeacon = config);
  }

  void _onSoftwareBeaconSent(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          data == true
              ? l10n.aprsSoftwareBeaconSent
              : l10n.aprsSoftwareBeaconNotSent,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _recomputeBeaconState() {
    int interval = 0;
    bool onCurrent = false;
    for (final id in _connectedRadioDeviceIds()) {
      final bss = _broker.getJsonValue<RadioBssSettings>(
        id,
        'BssSettings',
        (json) => RadioBssSettings.fromJson(json),
      );
      final settings = _broker.getJsonValue<RadioSettings>(
        id,
        'Settings',
        (json) => RadioSettings.fromJson(json),
      );
      if (bss != null &&
          bss.shouldShareLocation &&
          bss.locationShareInterval > 0) {
        interval = bss.locationShareInterval;
        onCurrent = (settings?.autoShareLocCh ?? 0) == 0;
        break;
      }
    }
    if (interval != _beaconInterval || onCurrent != _beaconOnCurrentChannel) {
      if (!mounted) {
        _beaconInterval = interval;
        _beaconOnCurrentChannel = onCurrent;
        return;
      }
      setState(() {
        _beaconInterval = interval;
        _beaconOnCurrentChannel = onCurrent;
      });
    }
  }

  List<int> _connectedRadioDeviceIds() {
    final ids = <int>[];
    final raw = _broker.getValueDynamic(_aprsDeviceId, 'ConnectedRadios', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = item['DeviceId'];
          if (id is int) ids.add(id);
        }
      }
    }
    return ids;
  }

  /// True when at least one radio is fully connected (not merely connecting).
  /// The beacon/digipeater dialogs need a live radio to talk to, so their menu
  /// items must stay disabled while a connection is still in progress.
  bool _hasFullyConnectedRadio() {
    for (final id in _connectedRadioDeviceIds()) {
      final state = _broker.getValue<String>(id, 'State');
      if (state == 'Connected') return true;
    }
    return false;
  }

  bool _radioHasAprsChannel(int deviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return false;
    for (final channel in channels) {
      // The APRS channel name must be all-caps "APRS" to match the routing used
      // throughout the app (radio, modem, decoder, handlers all compare
      // case-sensitively). A channel named e.g. "aprs" is a misconfiguration:
      // it will not route any APRS traffic, so it must trigger the warning.
      if (channel.name == 'APRS') return true;
    }
    return false;
  }

  void _recomputeChannelState() {
    final ids = _connectedRadioDeviceIds();
    bool hasLoaded = false;
    bool hasAprs = false;
    for (final id in ids) {
      final allLoaded =
          _broker.getValue<bool>(id, 'AllChannelsLoaded', false) ?? false;
      if (!allLoaded) continue;
      hasLoaded = true;
      if (_radioHasAprsChannel(id)) {
        hasAprs = true;
        break;
      }
    }
    // In APRSSat mode the radio transmits APRS via VFO A without an APRS
    // channel, so the missing-channel warning would be misleading: suppress it.
    final showMissing = hasLoaded && !hasAprs && !_isAprsSatActive;
    if (!mounted) {
      _hasAprsChannel = hasAprs;
      _showMissingChannel = showMissing;
      return;
    }
    if (hasAprs != _hasAprsChannel || showMissing != _showMissingChannel) {
      setState(() {
        _hasAprsChannel = hasAprs;
        _showMissingChannel = showMissing;
      });
    }
  }

  /// Returns the preferred radio device id with an APRS channel, or -1.
  int _getPreferredAprsRadioDeviceId() {
    // A radio in APRSSat mode is the preferred APRS target: it is tuned to an
    // APRS satellite via VFO A and transmits APRS even without an APRS channel.
    final satId = _aprsSatRadioDeviceId;
    if (satId >= 0) return satId;
    for (final id in _connectedRadioDeviceIds()) {
      final allLoaded =
          _broker.getValue<bool>(id, 'AllChannelsLoaded', false) ?? false;
      if (!allLoaded) continue;
      if (_radioHasAprsChannel(id)) return id;
    }
    return -1;
  }

  /// True when messages can be sent to the APRS-IS internet service even
  /// without a radio: APRS-IS is enabled, transmit is allowed, and a callsign
  /// is set (which yields a verified passcode).
  bool get _aprsIsTransmitAvailable =>
      _aprsIsEnabled && _allowTransmit && _callsign.trim().isNotEmpty;

  /// True when a message can be transmitted: either an APRS channel is
  /// available on a connected radio or APRS-IS can carry the message, and both
  /// the destination and message fields are non-empty. In APRSSat mode transmit
  /// is allowed even without an APRS channel (the radio's APRS-satellite lock).
  bool get _canSend =>
      (_hasAprsChannel || _aprsIsTransmitAvailable || _isAprsSatActive) &&
      (!_isRadioLockedForOtherUsage || _isAprsSatActive) &&
      ((_selectedContact != null) ||
          _destinationController.text.trim().isNotEmpty) &&
      _messageController.text.trim().isNotEmpty;

  /// Rebuilds when the destination/message fields change so the send button
  /// enabled state stays in sync.
  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Incoming APRS packets
  // ---------------------------------------------------------------------------

  void _onAprsStoreReady(int deviceId, String name, Object? data) {
    if (_historicalLoaded) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );
  }

  void _onAprsPacketList(int deviceId, String name, Object? data) {
    if (_historicalLoaded) return;
    if (data is! List) return;
    _historicalLoaded = true;
    for (final item in data) {
      if (item is AprsPacket && item.packet != null) {
        _addAprsPacket(item, !item.packet!.incoming, rebuild: false);
      }
    }
    _sortEntriesByTime();
    _rebuildMessages();
  }

  void _onAprsIsStoreReady(int deviceId, String name, Object? data) {
    if (_aprsIsHistoricalLoaded) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsIsPackets',
      data: null,
      store: false,
    );
  }

  void _onAprsIsPacketList(int deviceId, String name, Object? data) {
    if (_aprsIsHistoricalLoaded) return;
    if (data is! List) return;
    _aprsIsHistoricalLoaded = true;
    for (final item in data) {
      if (item is AprsPacket && item.packet != null) {
        // Internet packets are usually received; messages we sent (recovered
        // from aprs.fi) carry incoming=false and are shown as outgoing.
        _addAprsPacket(item, !item.packet!.incoming, rebuild: false);
      }
    }
    _sortEntriesByTime();
    _rebuildMessages();
  }

  /// Keeps the message list chronological after a bulk historical load, so RF
  /// and internet history (which arrive as separate async batches) interleave
  /// by time instead of appearing as two blocks.
  void _sortEntriesByTime() {
    _entries.sort((a, b) => a.time.compareTo(b.time));
  }

  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (data is! AprsFrameEventArgs) return;
    final args = data;
    final isSender = !args.ax25Packet.incoming;
    _addAprsPacket(args.aprsPacket, isSender);
  }

  ChatAuthState _mapAuth(AuthState s) {
    switch (s) {
      case AuthState.success:
        return ChatAuthState.success;
      case AuthState.failed:
        return ChatAuthState.failed;
      case AuthState.none:
        return ChatAuthState.none;
      case AuthState.unknown:
        return ChatAuthState.unknown;
    }
  }

  IconData? _iconFor(_AprsEntry e) {
    if (e.sender) {
      if (e.imageIndex == 0) return Icons.check;
      if (e.imageIndex == 1) return Icons.close;
      return Icons.schedule;
    }
    if (e.imageIndex == 3) return Icons.location_on;
    return null;
  }

  ChatMessage _entryToMessage(int index, _AprsEntry e) {
    final trimmed = e.messageText.trim();
    return ChatMessage(
      id: '$index',
      route: e.routingString,
      senderCallsign: e.senderCallsign,
      // Symbol-only packets carry no comment; render a single space so the
      // chat bubble (with its symbol) still draws instead of collapsing.
      message: trimmed.isEmpty ? ' ' : trimmed,
      time: e.time,
      isSender: e.sender,
      authState: _mapAuth(e.authState),
      latitude: e.latitude,
      longitude: e.longitude,
      icon: _iconFor(e),
      bubbleSymbol: _bubbleSymbolFor(e),
      // Tint packets gated in from the APRS-IS internet service so they stand
      // apart from RF traffic; RF messages keep the default bubble colour.
      bubbleColorOverride: e.aprsPacket.fromAprsIs ? _internetColor : null,
      tag: e,
    );
  }

  /// Builds the mapped APRS symbol widget for a message bubble, or null when
  /// the packet has no symbol or no mapped icon for it. Overlay combo symbols
  /// blend their letter halo with the bubble colour so the symbol sits on a
  /// transparent background (no chip) while staying readable.
  ///
  /// Uses fixed colours rather than [Theme.of] because this runs while the
  /// message list is (re)built from DataBroker callbacks, which can happen
  /// before the widget's inherited dependencies are ready.
  Widget? _bubbleSymbolFor(_AprsEntry e) {
    final table = e.aprsPacket.symbolTable;
    final code = e.aprsPacket.symbol;
    if (table.isEmpty || code.isEmpty) return null;
    final symbol = aprsSymbolFor(table, code);
    if (symbol == null || !symbol.hasVisual) return null;
    return aprsSymbolWidgetFor(
      table,
      code,
      size: 18,
      color: Colors.black87,
      haloColor: _bubbleColorFor(e),
    );
  }

  /// Returns the bubble background colour used for [e], mirroring
  /// [ChatWidget]'s defaults, so overlay symbol halos can blend into it.
  Color _bubbleColorFor(_AprsEntry e) {
    const senderColor = Color(0xFFBEE1A5);
    const authColor = Color(0xFF6ECD6E);
    const failedColor = Color(0xFFEB96A2);
    const normalColor = Color(0xFF8AC0DB);
    if (e.sender) return senderColor;
    switch (e.authState) {
      case AuthState.success:
        return authColor;
      case AuthState.failed:
        return failedColor;
      default:
        return e.aprsPacket.fromAprsIs ? _internetColor : normalColor;
    }
  }

  void _rebuildMessages() {
    final list = <ChatMessage>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (!_entryInCurrentView(e)) continue;
      list.add(_entryToMessage(i, e));
    }
    if (mounted) {
      setState(() => _messages = list);
    } else {
      _messages = list;
    }
  }

  /// Whether [e] should appear in the chat view given the current filters and,
  /// in Messenger mode with a selected contact, the conversation peer.
  bool _entryInCurrentView(_AprsEntry e) {
    if (_selectedContact != null) {
      // In a focused conversation, show every message to/from the peer,
      // ignoring the telemetry / internet-traffic toggles (those govern the
      // combined feed). peerCallsign is only set for message packets, so
      // telemetry never leaks in here.
      return e.peerCallsign != null &&
          e.peerCallsign!.toUpperCase() == _selectedContact;
    }
    if (!e.visible) return false;
    return true;
  }

  /// Appends a single newly added entry to the display list without rebuilding
  /// the entire message list. A full rebuild re-created a [ChatMessage] for
  /// every entry (O(n) allocations) and ran on every incoming packet, so cost
  /// grew with history size. Appending keeps the per-packet cost constant.
  void _appendMessage(int index, _AprsEntry e) {
    if (!_entryInCurrentView(e)) return;
    final msg = _entryToMessage(index, e);
    if (mounted) {
      setState(() => _messages.add(msg));
    } else {
      _messages.add(msg);
    }
  }

  /// Ports the C# `AddAprsPacket` display logic.
  void _addAprsPacket(
    AprsPacket aprsPacket,
    bool sender, {
    bool rebuild = true,
  }) {
    final packet = aprsPacket.packet;
    if (packet == null) return;
    if (packet.addresses.isEmpty) return;

    String? messageId;
    String? messageText;
    PacketDataType messageType = aprsPacket.dataType;
    int imageIndex = -1;
    String? peerCallsign;

    final senderAddr = packet.addresses.length > 1
        ? packet.addresses[1]
        : packet.addresses[0];
    String routingString = senderAddr.toString();
    String senderCallsign = senderAddr.callSignWithId;

    // Traffic relayed inside a third-party header (e.g. an IGate gating an
    // internet message onto RF) carries the IGate as the AX.25 source. Use the
    // original sender parsed from that header so the "from" field is correct.
    final thirdPartySource =
        aprsPacket.thirdPartySourceCallsign?.stationCallsign;
    if (thirdPartySource != null && thirdPartySource.isNotEmpty) {
      senderCallsign = thirdPartySource;
      routingString = thirdPartySource;
    }

    final pos = aprsPacket.position;
    if (pos.coordinateSet.latitude.value != 0 &&
        pos.coordinateSet.longitude.value != 0) {
      imageIndex = 3;
    }

    if (aprsPacket.dataType == PacketDataType.message) {
      final localCallsignWithId = _stationId.isEmpty
          ? _callsign
          : '$_callsign-$_stationId';
      final addressee = aprsPacket.messageData.addressee;
      final forSelf =
          addressee == _callsign || addressee == localCallsignWithId;

      // ACK / REJ update prior sent messages and return.
      if (aprsPacket.messageData.msgType == MessageType.mtAck) {
        if (forSelf) _updateDeliveryIcon(aprsPacket, packet, 0, rebuild);
        return;
      }
      if (aprsPacket.messageData.msgType == MessageType.mtRej) {
        if (forSelf) _updateDeliveryIcon(aprsPacket, packet, 1, rebuild);
        return;
      }

      if (sender) {
        routingString = '→ $addressee';
      } else if (senderAddr.address == addressee ||
          senderAddr.callSignWithId == addressee) {
        routingString = addressee;
      } else {
        routingString = '$senderCallsign → $addressee';
      }
      // Shared threading rules, so clearing a conversation deletes exactly
      // these messages from the stores.
      peerCallsign = aprsConversationPeer(
        sender: senderCallsign,
        addressee: addressee,
        text: aprsPacket.messageData.msgText,
        outgoing: sender,
        local: AprsLocalStation(_callsign, localCallsignWithId),
      );
      if (packet.authState == AuthState.success) routingString += ' ✓';
      if (packet.authState == AuthState.failed) routingString += ' ❌';

      messageId = aprsPacket.messageData.seqId.isEmpty
          ? null
          : aprsPacket.messageData.seqId;
      messageText = aprsPacket.messageData.msgText;

      // APRS SMS gateway traffic uses "@<phone> <text>". Thread it into the SMS
      // contact matching the phone number (digits only), for both outbound
      // messages (addressee "SMS") and inbound gateway replies (from SMS/SMSGTE).
      final msgText = aprsPacket.messageData.msgText;
      final fromSmsGateway = !sender && _senderIsSmsGateway(senderCallsign);
      if ((addressee == 'SMS' || fromSmsGateway) && msgText.startsWith('@')) {
        final sp = msgText.indexOf(' ');
        if (sp > 1) {
          final phone = _digitsOnly(msgText.substring(1, sp));
          if (phone.isNotEmpty) {
            messageText = msgText.substring(sp + 1);
            routingString = sender ? '→ SMS: $phone' : 'SMS: $phone';
          }
        }
      }
    } else {
      // Non-message packets (status, telemetry, etc.).
      if (aprsPacket.weather != null && aprsPacket.weather!.hasData) {
        messageText = aprsPacket.weather!.toReadableString();
      } else if (aprsPacket.comment.isNotEmpty &&
          aprsPacket.dataType != PacketDataType.micE &&
          aprsPacket.dataType != PacketDataType.micECurrent &&
          aprsPacket.dataType != PacketDataType.micEOld) {
        messageText = aprsPacket.comment;
      } else if (aprsPacket.dataType == PacketDataType.status &&
          aprsPacket.informationField.isNotEmpty) {
        // Status reports keep their text in the information field, not the
        // comment, so a status-only beacon would otherwise show nothing.
        messageText = aprsPacket.informationField;
      }
    }

    // Single-address packets.
    if (packet.addresses.length == 1) {
      routingString = senderCallsign = packet.addresses[0].toString();
      messageText = packet.dataStr;
    }

    if (messageText == null || messageText.trim().isEmpty) {
      // Position beacons and similar packets may carry no comment/message
      // text but still decode as valid APRS with a symbol. Display these
      // (governed by the "Show all" toggle like other non-message packets)
      // instead of dropping them entirely.
      final hasSymbol =
          aprsPacket.symbolTable.isNotEmpty && aprsPacket.symbol.isNotEmpty;
      if (!hasSymbol) return;
      messageText = '';
    }

    final entry = _AprsEntry(
      aprsPacket: aprsPacket,
      packet: packet,
      routingString: routingString,
      senderCallsign: senderCallsign,
      messageText: messageText,
      time: packet.time,
      sender: sender,
      messageId: messageId,
      messageType: messageType,
      imageIndex: imageIndex,
      authState: packet.authState,
      visible: _computeVisible(messageType, aprsPacket.fromAprsIs, sender),
      peerCallsign: peerCallsign,
    );

    var removedLaterDuplicate = false;
    if (aprsPacket.dataType == PacketDataType.message) {
      final duplicatesToRemove = <_AprsEntry>[];
      for (final n in _entries) {
        if (n.aprsPacket.dataType != PacketDataType.message ||
            n.senderCallsign != entry.senderCallsign ||
            n.aprsPacket.messageData.addressee.toUpperCase() !=
                entry.aprsPacket.messageData.addressee.toUpperCase() ||
            n.aprsPacket.messageData.msgText !=
                entry.aprsPacket.messageData.msgText) {
          continue;
        }
        final incomingFromIs = entry.aprsPacket.fromAprsIs;
        final existingFromIs = n.aprsPacket.fromAprsIs;
        if (incomingFromIs != existingFromIs) {
          // One copy is a locally-recorded RF message, the other an
          // internet-recovered echo (e.g. from the aprs.fi backfill) of the
          // same message. Always keep the RF copy: it is the authoritative
          // local record and must never be dropped just because aprs.fi echoed
          // it back with a slightly different timestamp.
          if (incomingFromIs) return; // existing RF copy wins; ignore the echo.
          duplicatesToRemove.add(n); // incoming RF replaces the internet copy.
          continue;
        }
        // Same origin: collapse retransmissions, keeping the oldest copy.
        if (!n.time.isAfter(entry.time)) return;
        duplicatesToRemove.add(n);
      }
      if (duplicatesToRemove.isNotEmpty) {
        _entries.removeWhere(duplicatesToRemove.contains);
        removedLaterDuplicate = true;
      }
    } else {
      // Keep the short duplicate window for beacons and other non-message
      // packets, where identical content can be a legitimate later update.
      // Our own transmissions are exempt so every manual beacon shows.
      for (final n in _entries) {
        if (sender && !aprsPacket.fromAprsIs) break;
        if (entry.messageId == n.messageId &&
            entry.messageText == n.messageText &&
            entry.senderCallsign == n.senderCallsign &&
            n.time.add(const Duration(minutes: 5)).compareTo(packet.time) > 0 &&
            entry.time != n.time) {
          return;
        }
      }
    }

    if (entry.imageIndex == 3) {
      entry.latitude = pos.coordinateSet.latitude.value;
      entry.longitude = pos.coordinateSet.longitude.value;
    }

    if (!rebuild) {
      // Bulk historical load: append now; the caller sorts afterwards.
      _entries.add(entry);
      _pruneAprsIsHistory();
      return;
    }

    // Live path: keep _entries in chronological order. Real-time traffic
    // arrives newest-last (a cheap append), but backfilled aprs.fi messages
    // carry older timestamps and must slot into their correct position so the
    // bubbles stay sorted by time.
    var insertIndex = _entries.length;
    while (insertIndex > 0 &&
        _entries[insertIndex - 1].time.isAfter(entry.time)) {
      insertIndex--;
    }
    _entries.insert(insertIndex, entry);
    final appendedAtEnd = insertIndex == _entries.length - 1;
    // Pruning shifts entry indices, so a full rebuild is required then instead
    // of a cheap append; likewise when the entry slotted in out of order.
    final pruned = _pruneAprsIsHistory();
    if (pruned || removedLaterDuplicate || !appendedAtEnd) {
      _rebuildMessages();
    } else {
      _appendMessage(_entries.length - 1, entry);
    }
  }

  /// Maximum number of APRS-IS (internet-gated) messages retained in memory.
  /// The app may run for weeks or years, so internet history is bounded; RF
  /// messages are unaffected.
  static const int _maxAprsIsEntries = 1000;

  /// Drops the oldest APRS-IS entries beyond [_maxAprsIsEntries]. Returns true
  /// when any entry was removed, in which case callers must fully rebuild the
  /// message list because remaining entry indices have shifted.
  bool _pruneAprsIsHistory() {
    var count = 0;
    for (final e in _entries) {
      if (e.aprsPacket.fromAprsIs) count++;
    }
    if (count <= _maxAprsIsEntries) return false;
    // Entries are appended in arrival order, so removing the first matching
    // ones drops the oldest internet messages.
    var toRemove = count - _maxAprsIsEntries;
    _entries.removeWhere((e) {
      if (toRemove > 0 && e.aprsPacket.fromAprsIs) {
        toRemove--;
        return true;
      }
      return false;
    });
    return true;
  }

  void _updateDeliveryIcon(
    AprsPacket aprsPacket,
    AX25Packet packet,
    int imageIndex,
    bool rebuild,
  ) {
    bool updated = false;
    for (final n in _entries) {
      if (n.sender && n.messageId == aprsPacket.messageData.seqId) {
        if (n.authState == AuthState.unknown ||
            (n.authState == AuthState.success &&
                packet.authState == AuthState.success) ||
            (n.authState == AuthState.none &&
                packet.authState == AuthState.none)) {
          n.imageIndex = imageIndex;
          updated = true;
        }
      }
    }
    if (updated && rebuild) _rebuildMessages();
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  List<String>? _getSelectedRoute() {
    if (_aprsRoutes.isEmpty) return null;
    if (_selectedRouteIndex >= _aprsRoutes.length) _selectedRouteIndex = 0;
    return _aprsRoutes[_selectedRouteIndex].toRouteArray();
  }

  /// Configured route name for a contact, or the empty string when none is set.
  String _contactRouteName(String callsign) =>
      _contactRoutes[callsign.toUpperCase()] ?? '';

  /// Route array for a named route, or null when no route with that name exists.
  List<String>? _routeArrayForName(String name) {
    for (final r in _aprsRoutes) {
      if (r.name == name) return r.toRouteArray();
    }
    return null;
  }

  /// True when a per-contact conversation is open, the contact has a route
  /// preference, but that route no longer exists in the configured routes.
  bool get _selectedContactRouteMissing {
    if (_selectedContact == null) return false;
    final name = _contactRouteName(_selectedContact!);
    if (name.isEmpty) return false;
    return _routeArrayForName(name) == null;
  }

  /// Route to use when sending: a contact's own route while in a conversation,
  /// otherwise the route chosen in the header dropdown for the "All Messages"
  /// feed. Falls back to the selected route when the contact has no preference.
  List<String>? _routeForSending() {
    if (_selectedContact != null) {
      final name = _contactRouteName(_selectedContact!);
      if (name.isNotEmpty) return _routeArrayForName(name);
    }
    return _getSelectedRoute();
  }

  /// Semi-transparent overlay shown over the message list while a radio channel
  /// is being dragged onto the tab, hinting that dropping will share it.
  Widget _buildChannelDropOverlay() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber.shade700, width: 2),
        color: Colors.amber.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          AppLocalizations.of(context).aprsDropShare,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Called when a radio channel is dropped onto the tab. Encodes it as a
  /// channel-share token and inserts it into the message box so it can be sent
  /// as an APRS message.
  void _onChannelDropped(radio.RadioChannelInfo channel) {
    _insertIntoMessage(ChannelShare.encode(channel));
  }

  /// Inserts [snippet] into the message box at the caret, adding surrounding
  /// spaces so it stays a self-contained token, then refocuses the input.
  void _insertIntoMessage(String snippet) {
    final text = _messageController.text;
    final sel = _messageController.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final spaceBefore = before.isNotEmpty && !before.endsWith(' ') ? ' ' : '';
    final spaceAfter = after.isNotEmpty && !after.startsWith(' ') ? ' ' : '';
    final insert = '$spaceBefore$snippet$spaceAfter';
    final caret = before.length + insert.length;
    _messageController.value = TextEditingValue(
      text: before + insert + after,
      selection: TextSelection.collapsed(offset: caret),
    );
    _messageFocusNode.requestFocus();
  }

  void _sendMessage() {
    final inConversation = _selectedContact != null;
    // Messages to an SMS/phone contact are relayed through the "SMS" gateway,
    // exactly like the "Send SMS Message..." menu (@<number> <text>).
    final toSms = inConversation && _smsContacts.contains(_selectedContact);
    final text = _messageController.text;
    if (text.trim().isEmpty) return;

    final String destination;
    final String outgoing;
    if (toSms) {
      destination = 'SMS';
      // The SMS gateway expects a bare numeric phone number.
      final phone = _selectedContact!.replaceAll(RegExp(r'[^0-9]'), '');
      outgoing = '@$phone ${text.trim()}';
    } else {
      destination = inConversation
          ? _selectedContact!
          : _destinationController.text.trim().toUpperCase();
      outgoing = text;
    }
    if (destination.isEmpty) return;

    final radioDeviceId = _getPreferredAprsRadioDeviceId();
    if (radioDeviceId == -1 && !_aprsIsTransmitAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).aprsNoChannel),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      data: AprsSendMessageData(
        destination: destination,
        message: outgoing,
        radioDeviceId: radioDeviceId,
        route: _routeForSending(),
      ),
      store: false,
    );
    _messageController.clear();
    // Return focus to the input so the user can keep typing.
    _messageFocusNode.requestFocus();
  }

  /// Opens the SMS dialog and, on confirmation, sends a specially crafted APRS
  /// message to the "SMS" gateway (mirrors the C# `aprsSmsButton_Click`).
  Future<void> _sendSmsMessage() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showAprsSmsDialog(context);
    if (result == null || !mounted) return;

    final radioDeviceId = _getPreferredAprsRadioDeviceId();
    if (radioDeviceId == -1 && !_aprsIsTransmitAvailable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).aprsNoChannel),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      data: AprsSendMessageData(
        destination: 'SMS',
        message: result.gatewayMessage,
        radioDeviceId: radioDeviceId,
        route: _getSelectedRoute(),
      ),
      store: false,
    );
  }

  /// Opens the weather dialog and, on confirmation, sends a weather request to
  /// the "WXBOT" APRS gateway (mirrors the C# `weatherReportToolStripMenuItem_Click`).
  Future<void> _sendWeatherReport() async {
    final messenger = ScaffoldMessenger.of(context);
    final weatherMessage = await showAprsWeatherDialog(context);
    if (weatherMessage == null || !mounted) return;

    final radioDeviceId = _getPreferredAprsRadioDeviceId();
    if (radioDeviceId == -1 && !_aprsIsTransmitAvailable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).aprsNoChannel),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      data: AprsSendMessageData(
        destination: 'WXBOT',
        message: weatherMessage,
        radioDeviceId: radioDeviceId,
        route: _getSelectedRoute(),
      ),
      store: false,
    );
  }

  /// Shows the APRS packet details dialog for a double-tapped message.
  void _onMessageDoubleTap(ChatMessage message) {
    final tag = message.tag;
    if (tag is! _AprsEntry) return;
    AprsDetailsDialog.show(
      context,
      items: _buildDetailItems(tag),
      latitude: message.latitude,
      longitude: message.longitude,
      locationTitle: message.senderCallsign,
      symbolTable: tag.aprsPacket.symbolTable,
      symbolCode: tag.aprsPacket.symbol,
    );
  }

  /// Builds the name/value detail rows for an APRS entry, mirroring the C#
  /// `AprsDetailsForm.SetMessage` logic.
  List<AprsDetailItem> _buildDetailItems(_AprsEntry e) {
    final items = <AprsDetailItem>[];
    items.add(AprsDetailItem('Time', e.time.toString()));

    var i = 1;
    for (final addr in e.packet.addresses) {
      items.add(AprsDetailItem('AX.25 Addr $i', addr.callSignWithId));
      i++;
    }

    final aprs = e.aprsPacket;
    items.add(AprsDetailItem('Type', _dataTypeLabel(aprs.dataType)));
    if (aprs.comment.isNotEmpty) {
      items.add(AprsDetailItem('Comment', aprs.comment));
    }
    final dest = aprs.destCallsign?.stationCallsign ?? '';
    if (dest.isNotEmpty) {
      items.add(AprsDetailItem('DestCallsign', dest));
    }
    final thirdParty = aprs.thirdPartyHeader ?? '';
    if (thirdParty.isNotEmpty) {
      items.add(AprsDetailItem('ThirdParty Header', thirdParty));
    }

    final md = aprs.messageData;
    if (md.addressee.isNotEmpty || md.msgText.isNotEmpty) {
      items.add(AprsDetailItem('MsgType', md.msgType.name));
      if (md.addressee.isNotEmpty) {
        items.add(AprsDetailItem('Addressee', md.addressee));
      }
      if (md.seqId.isNotEmpty) {
        items.add(AprsDetailItem('SeqId', md.seqId));
      }
      if (md.msgText.isNotEmpty) {
        items.add(AprsDetailItem('MsgText', md.msgText));
      }
    }

    final pos = aprs.position;
    if (pos.course != 0) {
      items.add(AprsDetailItem('Course', pos.course.toString()));
    }
    if (pos.speed != 0) {
      items.add(AprsDetailItem('Speed', pos.speed.toString()));
    }
    if (pos.altitude != 0) {
      items.add(AprsDetailItem('Altitude', pos.altitude.toString()));
    }
    if (pos.ambiguity != 0) {
      items.add(AprsDetailItem('Ambiguity', pos.ambiguity.toString()));
    }
    if (pos.gridsquare.isNotEmpty) {
      items.add(AprsDetailItem('Gridsquare', pos.gridsquare));
    }
    final lat = pos.coordinateSet.latitude.value;
    final lon = pos.coordinateSet.longitude.value;
    if (lat != 0) {
      items.add(AprsDetailItem('Latitude', lat.toString()));
    }
    if (lon != 0) {
      items.add(AprsDetailItem('Longitude', lon.toString()));
    }

    final auth = aprs.authCode ?? '';
    if (auth.isNotEmpty) {
      items.add(AprsDetailItem('Authentication', auth));
    }

    final wx = aprs.weather;
    if (wx != null && wx.hasData) {
      if (wx.windDirection != null) {
        items.add(AprsDetailItem('Wind Direction', '${wx.windDirection}°'));
      }
      if (wx.windSpeed != null) {
        items.add(AprsDetailItem('Wind Speed', '${wx.windSpeed} mph'));
      }
      if (wx.windGust != null) {
        items.add(AprsDetailItem('Wind Gust', '${wx.windGust} mph'));
      }
      if (wx.temperature != null) {
        items.add(AprsDetailItem('Temperature', '${wx.temperature}°F'));
      }
      if (wx.humidity != null) {
        items.add(AprsDetailItem('Humidity', '${wx.humidity}%'));
      }
      if (wx.barometricPressure != null) {
        items.add(
          AprsDetailItem(
            'Pressure',
            '${wx.barometricPressure!.toStringAsFixed(1)} mb',
          ),
        );
      }
      if (wx.rainLastHour != null) {
        items.add(
          AprsDetailItem(
            'Rain (1h)',
            '${(wx.rainLastHour! / 100).toStringAsFixed(2)} in',
          ),
        );
      }
      if (wx.rainLast24Hours != null) {
        items.add(
          AprsDetailItem(
            'Rain (24h)',
            '${(wx.rainLast24Hours! / 100).toStringAsFixed(2)} in',
          ),
        );
      }
      if (wx.rainSinceMidnight != null) {
        items.add(
          AprsDetailItem(
            'Rain (since midnight)',
            '${(wx.rainSinceMidnight! / 100).toStringAsFixed(2)} in',
          ),
        );
      }
      if (wx.snowLast24Hours != null) {
        items.add(AprsDetailItem('Snow (24h)', '${wx.snowLast24Hours} in'));
      }
      if (wx.luminosity != null) {
        items.add(AprsDetailItem('Luminosity', '${wx.luminosity} W/m²'));
      }
    }

    final tlm = aprs.telemetry;
    if (tlm != null && tlm.hasData) {
      items.add(AprsDetailItem('Telemetry Seq', tlm.sequence.toString()));
      for (var c = 0; c < tlm.analog.length; c++) {
        items.add(
          AprsDetailItem('Telemetry Ch${c + 1}', tlm.analog[c].toString()),
        );
      }
      if (tlm.binaryBits != null) {
        items.add(
          AprsDetailItem(
            'Telemetry Binary',
            tlm.binary.map((b) => b ? '1' : '0').join(),
          ),
        );
      }
    }

    return items;
  }

  /// Returns a human-readable label for an APRS [PacketDataType].
  String _dataTypeLabel(PacketDataType type) {
    final name = type.name;
    final buffer = StringBuffer();
    for (var c = 0; c < name.length; c++) {
      final ch = name[c];
      if (c == 0) {
        buffer.write(ch.toUpperCase());
      } else if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
        buffer.write(' ');
        buffer.write(ch);
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Opens the "Show Location" map when a message's position marker is tapped.
  void _onMessageIconTap(ChatMessage message) {
    final lat = message.latitude;
    final lon = message.longitude;
    if (lat == null || lon == null) return;
    if (lat == 0 && lon == 0) return;
    showAprsLocationDialog(
      context,
      latitude: lat,
      longitude: lon,
      title: message.senderCallsign,
    );
  }

  void _onMessageContextMenu(ChatMessage message, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final hasLocation =
        message.latitude != null &&
        message.longitude != null &&
        (message.latitude != 0 || message.longitude != 0);
    final hasChannel = ChannelShare.findAll(message.message).isNotEmpty;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'details',
          child: Text(AppLocalizations.of(context).aprsDetails),
        ),
        if (hasLocation)
          PopupMenuItem<String>(
            value: 'location',
            child: Text(AppLocalizations.of(context).aprsShowLocation),
          ),
        if (!message.isSender)
          PopupMenuItem<String>(
            value: 'setReceiver',
            child: Text(AppLocalizations.of(context).aprsSetReceiver),
          ),
        PopupMenuItem<String>(
          value: 'copyMessage',
          child: Text(AppLocalizations.of(context).aprsCopyMessage),
        ),
        if (hasChannel)
          PopupMenuItem<String>(
            value: 'copyChannel',
            child: Text(AppLocalizations.of(context).aprsCopyChannel),
          ),
        PopupMenuItem<String>(
          value: 'copyCallsign',
          child: Text(AppLocalizations.of(context).aprsCopyCallsign),
        ),
        PopupMenuItem<String>(
          value: 'lookup',
          child: Text(AppLocalizations.of(context).callsignLookup),
        ),
      ],
    );

    if (selected == null || !mounted) return;
    switch (selected) {
      case 'details':
        _onMessageDoubleTap(message);
        break;
      case 'location':
        showAprsLocationDialog(
          context,
          latitude: message.latitude!,
          longitude: message.longitude!,
          title: message.senderCallsign,
        );
        break;
      case 'copyMessage':
        _copyMessage(message);
        break;
      case 'copyChannel':
        _copyChannel(message);
        break;
      case 'setReceiver':
        _setReceiver(message.senderCallsign);
        break;
      case 'copyCallsign':
        Clipboard.setData(ClipboardData(text: message.senderCallsign));
        break;
      case 'lookup':
        CallsignLookupDialog.show(
          context,
          initialCallsign: message.senderCallsign,
        );
        break;
    }
  }

  /// Handles a "Message this station" request from the Map tab. When the
  /// station is a known APRS contact it opens that conversation; otherwise it
  /// opens the combined "All Messages" feed and pre-fills the destination.
  void _onMessageStationRequested(int deviceId, String name, dynamic data) {
    if (data is! String || data.trim().isEmpty || !mounted) return;
    final callsign = data.trim().toUpperCase();
    if (_isAprsContact(callsign)) {
      _openConversation(callsign);
    } else {
      // No contact for this station: open the combined feed and pre-fill the
      // destination so the user can message them.
      setState(() {
        _viewAllMessages = true;
        _selectedContact = null;
        _viewAllMesh = false;
        _selectedMesh = null;
      });
      _setReceiver(callsign);
      _rebuildMessages();
    }
  }

  /// Opens the conversation requested by a cloud-push notification tap, then
  /// clears the retained request so a later rebuild of this tab does not
  /// reopen it.
  void _onOpenConversationRequested(int deviceId, String name, dynamic data) {
    if (data is! String || data.trim().isEmpty || !mounted) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsOpenConversation',
      data: '',
      store: true,
    );
    // A notification tap always corresponds to a message received from this
    // peer, so open that peer's conversation directly — even when the sender
    // is not a saved address-book contact but only has a message thread, and
    // even when that thread has not finished loading yet on a cold start.
    _openConversation(data.trim().toUpperCase());
  }

  /// Whether [callsign] (upper-cased) is a known APRS contact in the address
  /// book. SMS contacts (keyed by phone digits) are excluded.
  bool _isAprsContact(String callsign) {
    final target = _peerKey(callsign);
    return _addressBookIds.contains(target) && !_smsContacts.contains(target);
  }

  /// Sets the APRS receiver (destination) to [callsign], updating the input
  /// field and persisting the choice via the data broker.
  void _setReceiver(String callsign) {
    final dest = callsign.toUpperCase();
    setState(() {
      _selectedDestination = dest;
      _destinationController.text = dest;
    });
    _broker.dispatch(deviceId: 0, name: 'AprsDestination', data: dest);
  }

  /// Copies the message body to the clipboard. When the message carries an
  /// inline image, the image bytes are placed on the clipboard instead.
  Future<void> _copyMessage(ChatMessage message) async {
    final imagePath = message.imagePath;
    if (imagePath != null) {
      final file = File(imagePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await Pasteboard.writeImage(bytes);
        return;
      }
    }
    await Clipboard.setData(ClipboardData(text: message.message));
  }

  /// Copies the first shared-channel token found in [message] to the clipboard
  /// so it can be pasted onto a radio channel slot.
  void _copyChannel(ChatMessage message) {
    final matches = ChannelShare.findAll(message.message);
    if (matches.isEmpty) return;
    final token = message.message.substring(
      matches.first.start,
      matches.first.end,
    );
    Clipboard.setData(ClipboardData(text: token));
  }

  void _toggleShowAll() {
    setState(() {
      _showAllMessages = !_showAllMessages;
      for (final e in _entries) {
        e.visible = _computeVisible(
          e.messageType,
          e.aprsPacket.fromAprsIs,
          e.sender,
        );
      }
    });
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsShowTelemetry',
      data: _showAllMessages ? 1 : 0,
    );
    _rebuildMessages();
  }

  /// Computes whether an entry should be shown given the current filters. APRS-IS
  /// (internet) traffic is hidden entirely when [_showAprsIs] is off; otherwise
  /// the usual telemetry/message rule applies. Packets we transmitted ourselves
  /// (e.g. software beacons) are always shown.
  bool _computeVisible(PacketDataType type, bool fromAprsIs, bool sender) {
    if (fromAprsIs && !_showAprsIs) return false;
    if (sender && !fromAprsIs) return true;
    return _showAllMessages || type == PacketDataType.message;
  }

  void _toggleShowAprsIs() {
    setState(() {
      _showAprsIs = !_showAprsIs;
      for (final e in _entries) {
        e.visible = _computeVisible(
          e.messageType,
          e.aprsPacket.fromAprsIs,
          e.sender,
        );
      }
    });
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsShowAprsIs',
      data: _showAprsIs ? 1 : 0,
    );
    _rebuildMessages();
  }

  void _openAllMessages() {
    setState(() {
      _viewAllMessages = true;
      _selectedContact = null;
      _viewAllMesh = false;
      _selectedMesh = null;
    });
    _rebuildMessages();
  }

  /// Opens a conversation for [callsign] in Messenger mode, filtering the chat
  /// to that peer.
  void _openConversation(String callsign) {
    setState(() {
      _viewAllMessages = false;
      _selectedContact = _peerKey(callsign);
      _viewAllMesh = false;
      _selectedMesh = null;
    });
    _rebuildMessages();
  }

  /// Returns to the Messenger conversation list.
  void _closeConversation() {
    setState(() {
      _selectedContact = null;
      _viewAllMessages = false;
      _viewAllMesh = false;
      _selectedMesh = null;
    });
    _rebuildMessages();
  }

  Future<void> _clearMessages() async {
    final l10n = AppLocalizations.of(context);
    if (_inMeshView) {
      final sel = _selectedMeshParts;
      final confirmed = await DialogHelper.showConfirmDialog(
        context,
        title: l10n.meshAllMessages,
        message: sel != null
            ? l10n.aprsClearContactPrompt
            : l10n.meshClearPrompt,
        okText: l10n.tabClear,
      );
      if (!confirmed || !mounted) return;
      _broker.dispatch(
        deviceId: meshCoreDeviceId,
        name: 'MeshCoreClearMessages',
        data: {'kind': sel?.kind, 'peer': sel?.peer},
        store: false,
      );
      return;
    }
    final inConversation = _selectedContact != null;
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.aprsClearTitle,
      message: inConversation
          ? l10n.aprsClearContactPrompt
          : l10n.aprsClearPrompt,
      okText: l10n.tabClear,
    );
    if (!confirmed || !mounted) return;

    // In a conversation, clear only that contact's messages; leave the rest.
    // The tab (and every other window, including the desktop host when this is
    // the hosted web page) updates in the event handlers below, while the
    // stores delete the messages so they do not reload on the next launch.
    if (inConversation) {
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: clearAprsConversationEvent,
        data: <String, Object?>{'peer': _selectedContact!},
        store: false,
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'ClearAprsPackets',
      data: null,
      store: false,
    );
  }

  /// Removes every APRS message from the list (all APRS messages were cleared,
  /// here or in another window).
  void _onClearAprsPackets(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _entries.clear();
      _messages = [];
    });
  }

  /// Removes the messages of the cleared conversation `data['peer']`.
  void _onClearAprsConversation(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final peer = data is Map ? data['peer']?.toString() : null;
    if (peer == null || peer.isEmpty) return;
    setState(() {
      _entries.removeWhere(
        (e) => e.peerCallsign != null && e.peerCallsign!.toUpperCase() == peer,
      );
    });
    _rebuildMessages();
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'showAll',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showAllMessages
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(l10n.aprsShowAll),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'showAprsIs',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showAprsIs
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(l10n.aprsShowAprsIs),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'sendSms',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled:
              _allowTransmit &&
              (_hasAprsChannel ||
                  _aprsIsTransmitAvailable ||
                  _isAprsSatActive) &&
              (!_isRadioLockedForOtherUsage || _isAprsSatActive),
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.aprsSendSms)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'weatherReport',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled:
              _allowTransmit &&
              (_hasAprsChannel ||
                  _aprsIsTransmitAvailable ||
                  _isAprsSatActive) &&
              (!_isRadioLockedForOtherUsage || _isAprsSatActive),
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.aprsWeatherReport)],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'beaconSettings',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _hasFullyConnectedRadio(),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(l10n.aprsBeaconSettingsMenu),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'softwareBeacon',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(l10n.aprsSoftwareBeaconMenu),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'digipeater',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _hasFullyConnectedRadio() && !_isRadioLockedForOtherUsage,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(l10n.aprsDigipeaterMenu),
            ],
          ),
        ),
        if (_meshEnabled) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'meshConnection',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text(l10n.meshConnectionMenu),
              ],
            ),
          ),
        ],
        if (_meshEnabled && _selectedMeshParts?.kind == MeshCoreKind.group)
          PopupMenuItem<String>(
            value: 'meshRemoveGroup',
            height: menuItemHeight,
            padding: menuItemPadding,
            enabled: _meshConnected,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text(l10n.meshRemoveGroup),
              ],
            ),
          ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          // Nothing to clear while viewing the conversation list.
          enabled: _hasContent,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.tabClear)],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [const SizedBox(width: 20), Text(l10n.tabDetach)],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'showAll':
          _toggleShowAll();
          break;
        case 'showAprsIs':
          _toggleShowAprsIs();
          break;
        case 'sendSms':
          _sendSmsMessage();
          break;
        case 'weatherReport':
          _sendWeatherReport();
          break;
        case 'beaconSettings':
          if (context.mounted) showEditBeaconSettingsDialog(context);
          break;
        case 'softwareBeacon':
          if (context.mounted) showSoftwareBeaconDialog(context);
          break;
        case 'digipeater':
          if (context.mounted) showDigipeaterDialog(context);
          break;
        case 'clear':
          _clearMessages();
          break;
        case 'meshConnection':
          if (context.mounted) showMeshCoreConnectionDialog(context);
          break;
        case 'meshRemoveGroup':
          _removeMeshGroup();
          break;
        case 'detach':
          _detachWindow();
          break;
      }
    });
  }

  Future<void> _detachWindow() async {
    await windowService.createWindow('aprs');
  }

  Future<void> _removeMeshGroup() async {
    final sel = _selectedMeshParts;
    if (sel == null || sel.kind != MeshCoreKind.group) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.meshRemoveGroup,
      message: l10n.meshRemoveGroupPrompt(_meshTitle(sel.kind, sel.peer)),
      okText: l10n.commonRemove,
    );
    if (!confirmed || !mounted) return;
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreRemoveChannel',
      data: {'peer': sel.peer},
      store: false,
    );
    _closeConversation();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Match the Satellite tab: side-by-side (list + content) when very
        // wide, single-view switch otherwise, using the same 720px trigger.
        final wide = constraints.maxWidth >= 720;
        return wide ? _buildWideLayout(context) : _buildNarrowLayout(context);
      },
    );
  }

  /// Narrow (single-column) layout: the conversation list OR the selected
  /// content (all messages / a conversation) takes over the whole tab.
  Widget _buildNarrowLayout(BuildContext context) {
    // Conversation list view: header + list, no input panel.
    if (!_hasContent) {
      return Column(
        children: [
          _buildHeader(),
          if (_showMissingChannel) _buildMissingChannelBanner(),
          Expanded(child: _buildMessengerList()),
        ],
      );
    }
    return Column(
      children: [
        _buildHeader(),
        if (_showMissingChannel) _buildMissingChannelBanner(),
        Expanded(child: _buildConversationContent(context)),
      ],
    );
  }

  /// Wide layout: the conversation list is pinned on the left and the selected
  /// content (all messages / a conversation) is shown on the right.
  Widget _buildWideLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasContent = _hasContent;
    return Column(
      children: [
        _buildHeader(wide: true),
        if (_showMissingChannel) _buildMissingChannelBanner(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _buildMessengerList()),
              const VerticalDivider(width: 1),
              Expanded(
                child: hasContent
                    ? _buildConversationContent(context)
                    : Center(
                        child: Text(
                          AppLocalizations.of(context).aprsSelectConversation,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The selected content (all messages / a conversation): the chat feed with
  /// its optional missing-route banner, avatar overlay and input panel.
  Widget _buildConversationContent(BuildContext context) {
    if (_inMeshView) return _buildMeshContent(context);
    return Column(
      children: [
        if (_selectedContactRouteMissing) _buildMissingRouteBanner(),
        Expanded(
          child: DragTarget<radio.RadioChannelInfo>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) => _onChannelDropped(details.data),
            builder: (context, candidate, rejected) {
              final channelHover = candidate.isNotEmpty;
              return Stack(
                children: [
                  Positioned.fill(
                    child: ChatWidget(
                      messages: _messages,
                      onMessageDoubleTap: _onMessageDoubleTap,
                      onMessageContextMenu: _onMessageContextMenu,
                      onMessageIconTap: _onMessageIconTap,
                    ),
                  ),
                  if (_selectedContact != null)
                    _buildConversationAvatarOverlay(),
                  if (channelHover)
                    Positioned.fill(
                      child: IgnorePointer(child: _buildChannelDropOverlay()),
                    ),
                ],
              );
            },
          ),
        ),
        if (_allowTransmit) _buildInputPanel(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Messenger mode
  // ---------------------------------------------------------------------------

  /// Corner overlay shown in a conversation: a filled top-right triangle (so
  /// scrolling messages don't peek around the avatar) with the contact avatar
  /// on top. Tapping it opens the contact edit dialog.
  Widget _buildConversationAvatarOverlay() {
    final callsign = _selectedContact!;
    final scheme = Theme.of(context).colorScheme;
    final avatar = _avatarDataFor(callsign);
    const double corner = 104;
    return Positioned(
      top: 0,
      right: 0,
      child: SizedBox(
        width: corner,
        height: corner,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CornerTrianglePainter(scheme.surfaceContainerHigh),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: _contactDisplayName(callsign),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _editSelectedContact,
                  child: ContactAvatar(
                    callsign: callsign,
                    avatarIcon: avatar.icon,
                    avatarImage: avatar.image,
                    radius: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the contact edit dialog for the selected conversation peer, creating
  /// an APRS contact if one does not exist yet, and persists the result.
  Future<void> _editSelectedContact() async {
    final callsign = _selectedContact;
    if (callsign == null) return;

    final stations = <StationInfo>[];
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          stations.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          stations.add(StationInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    // Prefer an existing contact matching this peer. SMS peers are the phone
    // number's digits, so match SMS contacts by their digits-only id. A peer
    // that is all digits is an SMS phone number even when not yet saved as a
    // contact, so a new one opens as an SMS (not APRS) contact.
    final isSms =
        _smsContacts.contains(callsign) || _looksLikePhoneNumber(callsign);
    StationInfo? existing;
    for (final s in stations) {
      final sid = isSms ? _digitsOnly(s.callsign) : s.callsign.toUpperCase();
      if (sid != callsign) continue;
      existing = s;
      final preferred = isSms ? StationType.sms : StationType.aprs;
      if (s.stationType == preferred) break;
    }

    final result = await showStationDialog(
      context,
      existing:
          existing ??
          StationInfo(
            callsign: callsign,
            stationType: isSms ? StationType.sms : StationType.aprs,
          ),
    );
    if (result == null || !mounted) return;

    stations.removeWhere(
      (s) =>
          s.callsign == result.callsign && s.stationType == result.stationType,
    );
    stations.add(result);
    _broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  /// Display name for a conversation peer: the address-book name if known,
  /// otherwise the callsign.
  String _contactDisplayName(String callsign) {
    return _contactNames[callsign.toUpperCase()] ?? callsign;
  }

  /// Digits-only form of a phone number, used as the SMS conversation key.
  String _digitsOnly(String s) => aprsDigitsOnly(s);

  /// Conversation key for a callsign: uppercased, with a "-0" SSID dropped so
  /// "SMS" and "SMS-0" share one thread.
  static String _peerKey(String callsign) => aprsPeerKey(callsign);

  /// Whether [peer] looks like an SMS phone-number conversation key. SMS peers
  /// are threaded under the phone number's digits, whereas APRS callsigns
  /// always contain letters, so an all-digits peer is a phone number.
  bool _looksLikePhoneNumber(String peer) =>
      peer.isNotEmpty && RegExp(r'^\d+$').hasMatch(peer);

  /// Whether [callsign] is the APRS SMS gateway (SMS / SMSGTE, any SSID).
  bool _senderIsSmsGateway(String callsign) => isAprsSmsGateway(callsign);

  /// Short relative time such as "5m", "3h" or "5d".
  String _relativeTimeShort(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 365) return '${diff.inDays}d';
    return '${diff.inDays ~/ 365}y';
  }

  /// Builds the ordered list of Messenger conversations from message history and
  /// the APRS address book. Peers with recent messages come first (most recent
  /// on top); address-book contacts with no messages follow, sorted by name.
  List<_AprsConversation> _buildConversations() {
    final byPeer = <String, _AprsEntry>{};
    for (final e in _entries) {
      final peer = e.peerCallsign;
      if (peer == null || peer.isEmpty) continue;
      final key = peer.toUpperCase();
      final existing = byPeer[key];
      if (existing == null || e.time.isAfter(existing.time)) {
        byPeer[key] = e;
      }
    }

    final conversations = <_AprsConversation>[];
    for (final entry in byPeer.entries) {
      final e = entry.value;
      conversations.add(
        _AprsConversation(
          callsign: entry.key,
          name: _contactNames[entry.key],
          lastMessage: e.messageText.trim(),
          lastTime: e.time,
          lastFromMe: e.sender,
        ),
      );
    }
    conversations.sort((a, b) => b.lastTime!.compareTo(a.lastTime!));

    // Append address-book contacts (APRS + SMS) that have no message history.
    final existingKeys = byPeer.keys.toSet();
    final extras = <_AprsConversation>[];
    for (final id in _addressBookIds) {
      if (existingKeys.contains(id)) continue;
      extras.add(
        _AprsConversation(
          callsign: id,
          name: _contactNames[id],
          lastMessage: '',
          lastTime: null,
          lastFromMe: false,
        ),
      );
    }
    extras.sort(
      (a, b) => _contactDisplayName(
        a.callsign,
      ).toLowerCase().compareTo(_contactDisplayName(b.callsign).toLowerCase()),
    );

    return [...conversations, ...extras];
  }

  /// Avatar data (custom logo / image) for a conversation peer, or none.
  ({String? icon, String? image}) _avatarDataFor(String callsign) {
    final a = _contactAvatars[callsign.toUpperCase()];
    return (icon: a?.icon, image: a?.image);
  }

  Widget _buildMessengerList() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final aprs = _buildConversations();
    final mesh = _meshEnabled
        ? _buildMeshConversations()
        : const <_MeshConversation>[];
    // Conversations with activity from both networks are interleaved by time;
    // idle address-book entries follow (APRS first, then MeshCore by name).
    final active = <_ListEntry>[
      for (final c in aprs)
        if (c.lastTime != null) _ListEntry.aprs(c),
      for (final c in mesh)
        if (c.lastTime != null) _ListEntry.mesh(c),
    ]..sort((a, b) => b.time!.compareTo(a.time!));
    final idleMesh = [
      for (final c in mesh)
        if (c.lastTime == null) c,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final conversations = <_ListEntry>[
      ...active,
      for (final c in aprs)
        if (c.lastTime == null) _ListEntry.aprs(c),
      for (final c in idleMesh) _ListEntry.mesh(c),
    ];
    final feeds = <Widget>[
      _buildAllMessagesTile(),
      if (_meshEnabled) _buildAllMeshTile(),
    ];

    return Column(
      children: [
        Expanded(
          // The "All ... Messages" feeds are always shown first, followed by
          // the per-contact conversations.
          child: ListView.separated(
            itemCount: conversations.length + feeds.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: scheme.outlineVariant),
            itemBuilder: (context, index) {
              if (index < feeds.length) return feeds[index];
              final entry = conversations[index - feeds.length];
              return entry.aprs != null
                  ? _buildConversationTile(entry.aprs!)
                  : _buildMeshConversationTile(entry.mesh!);
            },
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        // Add-contact action, styled like the Contacts tab bottom bar.
        Container(
          height: 50,
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              SizedBox(
                height: 34,
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'aprs':
                        _openAddContact(StationType.aprs);
                      case 'sms':
                        _openAddContact(StationType.sms);
                      case 'meshUser':
                        _addMeshConversation(false);
                      case 'meshGroup':
                        _addMeshConversation(true);
                    }
                  },
                  tooltip: '',
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'aprs',
                      child: Text(l10n.stationTitleAprs),
                    ),
                    PopupMenuItem(
                      value: 'sms',
                      child: Text(l10n.stationTitleSms),
                    ),
                    if (_meshEnabled) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'meshUser',
                        child: Text(l10n.meshUser),
                      ),
                      PopupMenuItem(
                        value: 'meshGroup',
                        child: Text(l10n.meshGroup),
                      ),
                    ],
                  ],
                  child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      disabledBackgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary,
                      disabledForegroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimary,
                    ),
                    child: Text(l10n.aprsAddContact),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The list entry that opens the combined APRS feed (all messages). Shown at
  /// the top of the conversation list with a generic icon instead of an avatar.
  Widget _buildAllMessagesTile() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ListTile(
      selected: _viewAllMessages,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.forum, color: scheme.onPrimaryContainer),
      ),
      title: Text(
        l10n.aprsAllMessages,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      onTap: _openAllMessages,
    );
  }

  /// The list entry that opens the combined MeshCore feed.
  Widget _buildAllMeshTile() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ListTile(
      selected: _viewAllMesh,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        child: Icon(Icons.hub, color: scheme.onTertiaryContainer),
      ),
      title: Text(
        l10n.meshAllMessages,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: _meshConnected || !_meshConfigured
          ? null
          : Text(
              l10n.meshStatusDisconnected,
              maxLines: 1,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
      onTap: _openAllMesh,
    );
  }

  Widget _buildMeshConversationTile(_MeshConversation c) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final group = c.kind == MeshCoreKind.group;
    final preview = c.lastMessage.isEmpty
        ? ''
        : (c.lastFromMe ? '→ ${c.lastMessage}' : c.lastMessage);
    return ListTile(
      selected: _selectedMesh == c.key,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: group
          ? CircleAvatar(
              backgroundColor: scheme.tertiaryContainer,
              child: Icon(Icons.groups, color: scheme.onTertiaryContainer),
            )
          : _meshUserAvatar(c.peer),
      title: Text(
        c.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastTime != null)
            Text(
              _relativeTimeShort(c.lastTime!),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          Text(
            group ? l10n.meshGroup : l10n.meshUser,
            style: TextStyle(fontSize: 10, color: scheme.tertiary),
          ),
        ],
      ),
      onTap: () => _openMeshConversation(c.key),
    );
  }

  Widget _buildConversationTile(_AprsConversation c) {
    final scheme = Theme.of(context).colorScheme;
    final title = _contactDisplayName(c.callsign);
    final preview = c.lastMessage.isEmpty
        ? ''
        : (c.lastFromMe ? '→ ${c.lastMessage}' : c.lastMessage);
    final avatar = _avatarDataFor(c.callsign);
    return ListTile(
      selected: !_viewAllMessages && !_inMeshView && _selectedContact == c.callsign,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: ContactAvatar(
        callsign: c.callsign,
        avatarIcon: avatar.icon,
        avatarImage: avatar.image,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: c.lastTime == null
          ? null
          : Text(
              _relativeTimeShort(c.lastTime!),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
      onTap: () => _openConversation(c.callsign),
    );
  }

  /// Opens the add-station dialog (locked to [type]) and persists the new
  /// contact to the address book.
  Future<void> _openAddContact(StationType type) async {
    final station = await showStationDialog(context, fixedType: type);
    if (station == null || !mounted) return;
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    final stations = <StationInfo>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          stations.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          stations.add(StationInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final exists = stations.any(
      (s) =>
          s.callsign == station.callsign &&
          s.stationType == station.stationType,
    );
    if (!exists) {
      stations.add(station);
      _broker.dispatch(
        deviceId: 0,
        name: 'Stations',
        data: stations.map((s) => s.toJson()).toList(),
      );
    }
    // Open the conversation with the new contact. SMS conversations are keyed
    // by the digits-only phone number to match gateway message threading.
    final peerKey = station.stationType == StationType.sms
        ? _digitsOnly(station.callsign)
        : station.callsign;
    if (peerKey.isNotEmpty) {
      _openConversation(peerKey);
    }
  }

  Widget _buildBeaconIcon() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bool isWarning = _beaconOnCurrentChannel;
    final Color color = isWarning ? scheme.error : scheme.tertiary;
    final String tooltip = isWarning
        ? l10n.aprsBeaconWarning
        : l10n.aprsBeaconActive(_formatBeaconInterval(_beaconInterval));

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => showEditBeaconSettingsDialog(context),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.wifi_tethering, color: color, size: 24),
        ),
      ),
    );
  }

  Widget _buildSoftwareBeaconIcon() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tooltip = _softwareBeacon.manual
        ? l10n.aprsSoftwareBeaconManualMode
        : l10n.aprsSoftwareBeaconActive(
            _formatBeaconInterval(_softwareBeacon.intervalSeconds),
          );

    return Builder(
      builder: (iconContext) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => _showSoftwareBeaconMenu(iconContext),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.cell_tower, color: scheme.tertiary, size: 24),
          ),
        ),
      ),
    );
  }

  /// Offers a one-time beacon or the software beacon settings.
  Future<void> _showSoftwareBeaconMenu(BuildContext anchorContext) async {
    final l10n = AppLocalizations.of(context);
    final box = anchorContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy + box.size.height,
        box.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<String>(
          value: 'sendNow',
          child: Text(l10n.aprsSoftwareBeaconSendNow),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Text(l10n.aprsSoftwareBeaconMenu),
        ),
      ],
    );
    if (value == null || !mounted) return;
    switch (value) {
      case 'sendNow':
        _broker.dispatch(
          deviceId: 0,
          name: 'SendSoftwareBeacon',
          data: true,
          store: false,
        );
        break;
      case 'settings':
        showSoftwareBeaconDialog(context);
        break;
    }
  }

  String _formatBeaconInterval(int seconds) {
    final l10n = AppLocalizations.of(context);
    if (seconds < 60) return l10n.aprsIntervalSeconds(seconds);
    final minutes = seconds ~/ 60;
    return minutes == 1
        ? l10n.aprsIntervalMinute
        : l10n.aprsIntervalMinutes(minutes);
  }

  Widget _buildMissingChannelBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: scheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).aprsMissingChannel,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _setupAprsChannel,
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(AppLocalizations.of(context).aprsSetup),
          ),
        ],
      ),
    );
  }

  /// Warning shown when the selected contact references an APRS route that no
  /// longer exists. Matches the style of [_buildMissingChannelBanner].
  Widget _buildMissingRouteBanner() {
    final scheme = Theme.of(context).colorScheme;
    final routeName = _selectedContact != null
        ? _contactRouteName(_selectedContact!)
        : '';
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: scheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).aprsMissingRoute(routeName),
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the APRS channel setup dialog and, on confirmation, writes a new
  /// "APRS" channel to the radio by overwriting the selected channel slot.
  /// Mirrors the C# `aprsSetupButton_Click`.
  Future<void> _setupAprsChannel() async {
    final messenger = ScaffoldMessenger.of(context);

    // Find a connected radio with all channels loaded.
    int radioDeviceId = -1;
    List<radio.RadioChannelInfo>? channels;
    for (final id in _connectedRadioDeviceIds()) {
      final allLoaded =
          _broker.getValue<bool>(id, 'AllChannelsLoaded', false) ?? false;
      if (!allLoaded) continue;
      final list = _broker.getJsonListValue<radio.RadioChannelInfo>(
        id,
        'Channels',
        (json) => radio.RadioChannelInfo.fromJson(json),
      );
      if (list != null && list.isNotEmpty) {
        radioDeviceId = id;
        channels = list;
        break;
      }
    }

    if (radioDeviceId == -1 || channels == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).aprsNoLoadedChannels),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await showAprsConfigurationDialog(
      context,
      channels: channels,
    );
    if (result == null || !mounted) return;

    radio.RadioChannelInfo? selected;
    for (final c in channels) {
      if (c.channelId == result.channelId) {
        selected = c;
        break;
      }
    }
    if (selected == null) return;

    final freqHz = (result.frequencyMhz * 1000000).round();
    final aprsChannel = selected.copyWith(
      name: 'APRS',
      rxFreq: freqHz,
      txFreq: freqHz,
      rxMod: radio.RadioModulationType.fm,
      txMod: radio.RadioModulationType.fm,
      bandwidth: radio.RadioBandwidthType.wide,
      mute: true,
      preDeEmphBypass: true,
      scan: false,
      talkAround: false,
      txAtMaxPower: true,
      txAtMedPower: false,
      txSubAudio: 0,
      rxSubAudio: 0,
      txDisable: false,
    );

    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'WriteChannel',
      data: aprsChannel,
      store: false,
    );
  }

  Widget _buildHeader({bool wide = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showDropdown =
              _viewAllMessages &&
              constraints.maxWidth > 250 &&
              _aprsRoutes.length > 1;
          final inConversation = _selectedContact != null;
          // A back arrow is shown for the feeds and for a conversation so the
          // user can return to the list. In the wide layout the list stays
          // visible, so no back button is needed.
          final inContent = !wide && _hasContent;
          final l10n = AppLocalizations.of(context);
          final meshSel = _selectedMeshParts;
          final String? subtitle = inConversation
              ? _contactDisplayName(_selectedContact!)
              : meshSel != null
              ? _meshTitle(meshSel.kind, meshSel.peer)
              : null;
          // Feeds and conversations are labelled with their network name.
          final network = (_viewAllMesh || meshSel != null)
              ? 'MeshCore'
              : (_viewAllMessages || inConversation)
              ? l10n.tabAprs
              : null;
          final title = network == null
              ? l10n.tabMessaging
              : subtitle == null
              ? network
              : '$network - $subtitle';
          return Row(
            children: [
              // The back arrow and the title share one wide hit box on the left
              // so the whole left side of the title bar returns to the list.
              if (inContent)
                Expanded(
                  child: InkWell(
                    onTap: _closeConversation,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.arrow_back, size: 20),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (_meshEnabled &&
                  (_meshConfigured ||
                      _meshState != MeshCoreState.disconnected))
                _buildMeshStatusIcon(),
              // Beacon active indicator - opens beacon settings on tap.
              if (_beaconInterval > 0) _buildBeaconIcon(),
              if (_beaconInterval > 0) const SizedBox(width: 4),
              // Software beacon indicator (periodic or manual) - tap for
              // send-now / settings.
              if (_softwareBeacon.isActive) _buildSoftwareBeaconIcon(),
              if (_softwareBeacon.isActive) const SizedBox(width: 4),
              // APRS Route dropdown - hide when too narrow or only one route.
              if (showDropdown)
                Container(
                  height: 28,
                  width: 140,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.onSurfaceVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedRouteIndex < _aprsRoutes.length
                          ? _selectedRouteIndex
                          : 0,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                      items: [
                        for (var i = 0; i < _aprsRoutes.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              _aprsRoutes[i].name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedRouteIndex = value);
                          _broker.dispatch(
                            deviceId: 0,
                            name: 'SelectedAprsRoute',
                            data: value,
                          );
                        }
                      },
                    ),
                  ),
                ),
              Builder(
                builder: (context) => InkWell(
                  onTap: () => _showMenu(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/MenuIcon.png',
                      width: 24,
                      height: 24,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.menu, size: 24);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputPanel() {
    final scheme = Theme.of(context).colorScheme;
    // In a Messenger conversation the destination is fixed to the selected
    // contact, so the destination combo box is hidden.
    final inConversation = _selectedContact != null;
    return Container(
      height: 50,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      clipBehavior: Clip.hardEdge,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Destination combo box (text input with dropdown)
          if (!inConversation) ...[
            SizedBox(
              width: 120,
              height: 34,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: scheme.onSurfaceVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destinationController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          border: InputBorder.none,
                          isDense: true,
                          isCollapsed: true,
                        ),
                        onChanged: (value) {
                          _selectedDestination = value.toUpperCase();
                          _broker.dispatch(
                            deviceId: 0,
                            name: 'AprsDestination',
                            data: _selectedDestination,
                          );
                        },
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      height: 32,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          setState(() {
                            _selectedDestination = value;
                            _destinationController.text = value;
                          });
                          _broker.dispatch(
                            deviceId: 0,
                            name: 'AprsDestination',
                            data: value,
                          );
                        },
                        itemBuilder: (context) => _destinations.map((dest) {
                          return PopupMenuItem<String>(
                            value: dest,
                            height: 36,
                            child: Text(
                              dest,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Text input
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(color: scheme.onSurfaceVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).aprsTypeMessage,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _canSend ? _sendMessage : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Icon(Icons.send, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fills the top-right corner with a triangle whose points are the top-right
/// corner, a point down the right edge, and a point left along the top edge.
class _CornerTrianglePainter extends CustomPainter {
  final Color color;
  _CornerTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, 0) // top-right corner
      ..lineTo(size.width, size.height) // down the right edge
      ..lineTo(0, 0) // left along the top edge
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerTrianglePainter old) => old.color != color;
}
