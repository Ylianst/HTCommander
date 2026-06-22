import 'package:flutter/material.dart';
import 'chat_widget.dart';
import '../dialogs/aprs_details_dialog.dart';
import '../dialogs/aprs_sms_dialog.dart';
import '../dialogs/aprs_weather_dialog.dart';
import '../services/window_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_auth.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../models/radio_models.dart';
import '../radio/ax25_packet.dart';

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
  });
}

/// APRS tab - Automatic Packet Reporting System
class AprsTab extends StatefulWidget {
  const AprsTab({super.key});

  @override
  State<AprsTab> createState() => _AprsTabState();
}

class _AprsTabState extends State<AprsTab> with AutomaticKeepAliveClientMixin {
  static const int _aprsDeviceId = 1;

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
  bool _allowTransmit = true;
  bool _historicalLoaded = false;

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
    _showAllMessages =
        (_broker.getValue<int>(0, 'AprsShowTelemetry', 0) ?? 0) != 0;
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

    // Subscribe to settings changes from device 0.
    _broker.subscribeMultiple(
      deviceId: 0,
      names: const [
        'CallSign',
        'StationId',
        'AprsRoutes',
        'AllowTransmit',
        'Stations',
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

    _recomputeChannelState();

    // Request the historical APRS packet list.
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _messageController.dispose();
    _destinationController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
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
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final station = AprsStationInfo.fromJson(item);
          if (station != null &&
              station.isAprs &&
              station.callsign.isNotEmpty &&
              !dests.contains(station.callsign)) {
            dests.add(station.callsign);
          }
        }
      }
    }
    _destinations = dests;
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
        case 'Stations':
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

  bool _radioHasAprsChannel(int deviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return false;
    for (final channel in channels) {
      if (channel.name.toUpperCase() == 'APRS') return true;
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
    final showMissing = hasLoaded && !hasAprs;
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
    for (final id in _connectedRadioDeviceIds()) {
      final allLoaded =
          _broker.getValue<bool>(id, 'AllChannelsLoaded', false) ?? false;
      if (!allLoaded) continue;
      if (_radioHasAprsChannel(id)) return id;
    }
    return -1;
  }

  /// True when a message can be transmitted: an APRS channel is available and
  /// both the destination and message fields are non-empty (matches the C#
  /// `UpdateSendButtonState`).
  bool get _canSend =>
      _hasAprsChannel &&
      _destinationController.text.trim().isNotEmpty &&
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
    _rebuildMessages();
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

  void _rebuildMessages() {
    final list = <ChatMessage>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (!e.visible) continue;
      list.add(
        ChatMessage(
          id: '$i',
          route: e.routingString,
          senderCallsign: e.senderCallsign,
          message: e.messageText.trim(),
          time: e.time,
          isSender: e.sender,
          authState: _mapAuth(e.authState),
          latitude: e.latitude,
          longitude: e.longitude,
          icon: _iconFor(e),
          tag: e,
        ),
      );
    }
    if (mounted) {
      setState(() => _messages = list);
    } else {
      _messages = list;
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

    final senderAddr = packet.addresses.length > 1
        ? packet.addresses[1]
        : packet.addresses[0];
    String routingString = senderAddr.toString();
    String senderCallsign = senderAddr.callSignWithId;

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
      } else {
        if (senderAddr.address == addressee ||
            senderAddr.callSignWithId == addressee) {
          routingString = addressee;
        } else {
          routingString = '$senderCallsign → $addressee';
        }
      }
      if (packet.authState == AuthState.success) routingString += ' ✓';
      if (packet.authState == AuthState.failed) routingString += ' ❌';

      messageId = aprsPacket.messageData.seqId.isEmpty
          ? null
          : aprsPacket.messageData.seqId;
      messageText = aprsPacket.messageData.msgText;

      // SMS messages with special formatting.
      final msgText = aprsPacket.messageData.msgText;
      if (addressee == 'SMS' && msgText.length > 12 && msgText[0] == '@') {
        final i = msgText.indexOf(' ');
        if (i >= 0) {
          routingString = '→ SMS: ${msgText.substring(1, i)}';
          messageText = msgText.substring(i + 1);
        }
      }

      // Drop exact duplicates already shown.
      if (messageId != null) {
        for (final n in _entries) {
          if (n.messageId == messageId &&
              n.routingString == routingString &&
              n.messageText == messageText) {
            return;
          }
        }
      }
    } else {
      // Non-message packets (status, telemetry, etc.).
      if (aprsPacket.comment.isNotEmpty &&
          aprsPacket.dataType != PacketDataType.micE &&
          aprsPacket.dataType != PacketDataType.micECurrent &&
          aprsPacket.dataType != PacketDataType.micEOld) {
        messageText = aprsPacket.comment;
      }
    }

    // Single-address packets.
    if (packet.addresses.length == 1) {
      routingString = senderCallsign = packet.addresses[0].toString();
      messageText = packet.dataStr;
    }

    if (messageText == null || messageText.trim().isEmpty) return;

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
      visible: _showAllMessages || messageType == PacketDataType.message,
    );

    // Drop duplicates within the last 5 minutes.
    for (final n in _entries) {
      if (entry.messageId == n.messageId &&
          entry.messageText == n.messageText &&
          n.time.add(const Duration(minutes: 5)).compareTo(packet.time) > 0 &&
          entry.time != n.time) {
        return;
      }
    }

    if (entry.imageIndex == 3) {
      entry.latitude = pos.coordinateSet.latitude.value;
      entry.longitude = pos.coordinateSet.longitude.value;
    }

    _entries.add(entry);
    if (rebuild) _rebuildMessages();
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

  void _sendMessage() {
    final destination = _destinationController.text.trim().toUpperCase();
    final text = _messageController.text;
    if (destination.isEmpty || text.trim().isEmpty) return;

    final radioDeviceId = _getPreferredAprsRadioDeviceId();
    if (radioDeviceId == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No radio with an APRS channel is available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      data: AprsSendMessageData(
        destination: destination,
        message: text,
        radioDeviceId: radioDeviceId,
        route: _getSelectedRoute(),
      ),
      store: false,
    );
    _messageController.clear();
  }

  /// Opens the SMS dialog and, on confirmation, sends a specially crafted APRS
  /// message to the "SMS" gateway (mirrors the C# `aprsSmsButton_Click`).
  Future<void> _sendSmsMessage() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showAprsSmsDialog(context);
    if (result == null || !mounted) return;

    final radioDeviceId = _getPreferredAprsRadioDeviceId();
    if (radioDeviceId == -1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No radio with an APRS channel is available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      data: AprsSendMessageData(
        destination: 'SMS',
        message: '@${result.phoneNumber} ${result.message}',
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
    if (radioDeviceId == -1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No radio with an APRS channel is available'),
          duration: Duration(seconds: 2),
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

  void _onMessageTap(ChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message from ${message.senderCallsign}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Shows the APRS packet details dialog for a double-tapped message.
  void _onMessageDoubleTap(ChatMessage message) {
    final tag = message.tag;
    if (tag is! _AprsEntry) return;
    AprsDetailsDialog.show(context, items: _buildDetailItems(tag));
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

  void _onMessageLongPress(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Message copied')));
              },
            ),
            if (message.hasLocation)
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Show on map'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Location: ${message.latitude}, ${message.longitude}',
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedDestination = message.senderCallsign;
                  _destinationController.text = message.senderCallsign;
                });
                _messageFocusNode.requestFocus();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleShowAll() {
    setState(() {
      _showAllMessages = !_showAllMessages;
      for (final e in _entries) {
        e.visible = _showAllMessages || e.messageType == PacketDataType.message;
      }
    });
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsShowTelemetry',
      data: _showAllMessages ? 1 : 0,
    );
    _rebuildMessages();
  }

  void _clearMessages() {
    setState(() {
      _entries.clear();
      _messages = [];
    });
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'ClearAprsPackets',
      data: null,
      store: false,
    );
  }

  void _showMenu(BuildContext context) {
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
              const Text('Show All Messages'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'sendSms',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _allowTransmit && _hasAprsChannel,
          child: const Row(
            children: [SizedBox(width: 20), Text('Send SMS Message...')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'weatherReport',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _allowTransmit && _hasAprsChannel,
          child: const Row(
            children: [SizedBox(width: 20), Text('Weather Report...')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Clear')]),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Detach...')],
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
        case 'sendSms':
          _sendSmsMessage();
          break;
        case 'weatherReport':
          _sendWeatherReport();
          break;
        case 'clear':
          _clearMessages();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        if (_showMissingChannel) _buildMissingChannelBanner(),
        Expanded(
          child: ChatWidget(
            messages: _messages,
            onMessageTap: _onMessageTap,
            onMessageDoubleTap: _onMessageDoubleTap,
            onMessageLongPress: _onMessageLongPress,
          ),
        ),
        if (_allowTransmit) _buildInputPanel(),
      ],
    );
  }

  Widget _buildMissingChannelBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3CD),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.warning_amber, color: Color(0xFF856404), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No "APRS" channel is configured on the connected radio. '
              'Add an APRS channel to send and receive APRS messages.',
              style: TextStyle(color: Color(0xFF856404), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showDropdown =
              constraints.maxWidth > 250 && _aprsRoutes.length > 1;
          return Row(
            children: [
              const Text(
                'APRS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              // APRS Route dropdown - hide when too narrow or only one route.
              if (showDropdown)
                Container(
                  height: 28,
                  width: 140,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedRouteIndex < _aprsRoutes.length
                          ? _selectedRouteIndex
                          : 0,
                      isDense: true,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 14, color: Colors.black),
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
    return Container(
      height: 50,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      clipBehavior: Clip.hardEdge,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Destination combo box (text input with dropdown)
          SizedBox(
            width: 100,
            height: 34,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
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
          // Text input
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
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
