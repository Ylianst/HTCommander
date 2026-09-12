/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../radio/radio_models.dart';
import '../radio/repeaterbook_client.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../utils/channel_colors.dart';
import 'channel_context_menu.dart';
import 'channel_details_dialog.dart';
import 'dialog_utils.dart';

/// Opens the "RepeaterBook" dialog. Search results appear on the left; the
/// radio's channel slots are on the right. The user drags a repeater onto a
/// slot (or selects both and presses the move button); nothing is written to
/// the radio until OK is pressed.
Future<void> showRepeaterBookDialog(
  BuildContext context, {
  required String token,
  required int deviceId,
  String? radioName,
  required List<RadioChannelInfo> radioChannels,
  double? currentLat,
  double? currentLon,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RepeaterBookDialog(
      token: token,
      deviceId: deviceId,
      radioName: radioName,
      radioChannels: radioChannels,
      currentLat: currentLat,
      currentLon: currentLon,
    ),
  );
}

/// A search result mapped to a channel, with its distance from the operator.
class _ResultChannel {
  final RadioChannelInfo channel;
  final RepeaterBookResult source;
  final double? distanceKm;
  _ResultChannel(this.channel, this.source, this.distanceKm);
}

class RepeaterBookDialog extends StatefulWidget {
  final String token;
  final int deviceId;
  final String? radioName;
  final List<RadioChannelInfo> radioChannels;
  final double? currentLat;
  final double? currentLon;

  const RepeaterBookDialog({
    super.key,
    required this.token,
    required this.deviceId,
    this.radioName,
    required this.radioChannels,
    this.currentLat,
    this.currentLon,
  });

  @override
  State<RepeaterBookDialog> createState() => _RepeaterBookDialogState();
}

class _RepeaterBookDialogState extends State<RepeaterBookDialog> {
  static const double _tileWidth = 156;
  static const double _tileHeight = 52;

  final DataBrokerClient _broker = DataBrokerClient();

  String _country = 'United States';
  String _state = '';
  String _city = '';
  bool _searching = false;
  String _status = '';
  bool _statusIsError = false;

  /// Mapped, open/on-air search results (the left column).
  List<_ResultChannel> _results = const [];

  /// Radio slots sorted by channel id (the right column).
  late final List<RadioChannelInfo> _slots;

  /// Pending assignments: slot channel id -> repeater channel to write.
  final Map<int, RadioChannelInfo> _staged = <int, RadioChannelInfo>{};

  int? _selectedResultIndex;
  int? _selectedSlotId;

  /// When true the results area is replaced by a map of the search results.
  bool _showMap = false;
  final MapController _mapController = MapController();

  RepeaterBookClient? _client;

  @override
  void initState() {
    super.initState();
    _slots = List<RadioChannelInfo>.from(widget.radioChannels)
      ..sort((a, b) => a.channelId.compareTo(b.channelId));

    // Restore the last-used search so reopening the dialog is pre-filled.
    _country =
        DataBroker.getValue<String>(0, 'RepeaterBookCountry', 'United States') ??
            'United States';
    _state = DataBroker.getValue<String>(0, 'RepeaterBookState', '') ?? '';
    _city = DataBroker.getValue<String>(0, 'RepeaterBookCity', '') ?? '';
  }

  @override
  void dispose() {
    _client?.close();
    _mapController.dispose();
    super.dispose();
  }

  bool get _hasLocation =>
      widget.currentLat != null && widget.currentLon != null;

  // --- Search ----------------------------------------------------------------

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final country = _country.trim();
    final state = _state.trim();
    final city = _city.trim();

    // export.php needs a state (or city) to narrow the query; guide the user.
    if (RepeaterBookClient.resolveStateId(state).isEmpty &&
        city.isEmpty &&
        (country == 'United States' ||
            country == 'Canada' ||
            country == 'Mexico')) {
      setState(() {
        _status = 'Enter a state/province (or a city) to search.';
        _statusIsError = true;
      });
      return;
    }

    // The radio is analog-only, so the search is fixed to FM analog.
    final query = RepeaterBookQuery(
      service: RepeaterBookService.amateur,
      country: country,
      state: state,
      city: city,
      mode: 'analog',
    );

    // Remember the inputs so the dialog is pre-filled next time.
    DataBroker.dispatch(deviceId: 0, name: 'RepeaterBookCountry', data: country);
    DataBroker.dispatch(deviceId: 0, name: 'RepeaterBookState', data: state);
    DataBroker.dispatch(deviceId: 0, name: 'RepeaterBookCity', data: city);

    setState(() {
      _searching = true;
      _status = 'Searching RepeaterBook…';
      _statusIsError = false;
      _results = const [];
    });

    _client ??= RepeaterBookClient();
    try {
      final raw = await _client!.search(query, widget.token);
      if (!mounted) return;

      final mapped = <_ResultChannel>[];
      for (final r in raw) {
        // Only open, on-air repeaters (hide closed/private/off-air).
        if (!r.isOpenAndOnAir) continue;
        final ch = RepeaterBookClient.toRadioChannelInfo(r);
        if (ch == null) continue;
        double? dist;
        if (_hasLocation && r.latitude != null && r.longitude != null) {
          dist = RepeaterBookClient.distanceKm(
            widget.currentLat!,
            widget.currentLon!,
            r.latitude!,
            r.longitude!,
          );
        }
        mapped.add(_ResultChannel(ch, r, dist));
      }

      if (_hasLocation) {
        mapped.sort((a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity));
      }

      setState(() {
        _results = mapped;
        _searching = false;
        _selectedResultIndex = null;
        _status = mapped.isEmpty
            ? 'No open, on-air repeaters found for that search.'
            : '${mapped.length} repeater(s) found.';
        _statusIsError = false;
      });

      // Reframe the map on the new results when it is the active view.
      if (_showMap) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitMapToResults());
      }
    } on RepeaterBookException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _status = e.message;
        _statusIsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _status = 'RepeaterBook search failed: $e';
        _statusIsError = true;
      });
    }
  }

  // --- Assign / write --------------------------------------------------------

  void _assign(RadioChannelInfo repeater, int slotId) {
    setState(() {
      _staged[slotId] = repeater;
      _selectedSlotId = slotId;
    });
  }

  void _moveSelected() {
    final idx = _selectedResultIndex;
    final slotId = _selectedSlotId;
    if (idx == null || slotId == null) return;
    if (idx < 0 || idx >= _results.length) return;
    _assign(_results[idx].channel, slotId);
  }

  void _clearStaged(int slotId) {
    setState(() => _staged.remove(slotId));
  }

  void _onOk() {
    // Write every staged channel to the radio, re-targeted to its slot id.
    for (final entry in _staged.entries) {
      final channel = entry.value.copyWith(channelId: entry.key);
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'WriteChannel',
        data: channel,
        store: false,
      );
    }
    Navigator.of(context).pop();
  }

  String _slotLabel(RadioChannelInfo slot) {
    final channel = _staged[slot.channelId] ?? slot;
    if (channel.name.isNotEmpty) return channel.name;
    return 'Ch ${slot.channelId + 1}';
  }

  String? _resultSubtitle(_ResultChannel rc) {
    final parts = <String>[];
    if (rc.distanceKm != null) parts.add('${rc.distanceKm!.toStringAsFixed(0)} km');
    if (rc.source.pl.isNotEmpty) parts.add('PL ${rc.source.pl}');
    if (rc.source.nearestCity.isNotEmpty && parts.length < 2) {
      parts.add(rc.source.nearestCity);
    }
    return parts.isEmpty ? null : parts.join('  •  ');
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radio = widget.radioName;
    final title = (radio != null && radio.isNotEmpty)
        ? 'RepeaterBook — $radio'
        : 'RepeaterBook';

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(title, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: _showMap ? 'Show channel imports' : 'Show stations on map',
            icon: Icon(_showMap ? Icons.view_list_outlined : Icons.map_outlined),
            onPressed: _toggleMap,
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      content: SizedBox(
        width: 660,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchHeader(),
            const SizedBox(height: 8),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusIsError ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: _showMap
                  ? _buildMap()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildResultsColumn()),
                        _buildMoveButtons(),
                        Expanded(child: _buildRadioColumn()),
                      ],
                    ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://www.repeaterbook.com'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Data courtesy of RepeaterBook.com',
                  style: DialogStyles.linkStyle,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _staged.isEmpty ? null : _onOk,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text('Write to radio (${_staged.length})'),
        ),
      ],
    );
  }

  Widget _buildSearchHeader() {
    return Row(
      children: [
        SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _searching ? null : _openSearchParams,
            style: DialogStyles.primaryButtonStyle(context),
            icon: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search, size: 18),
            label: const Text('Search'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _criteriaSummary(),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _criteriaSummary() {
    final parts = <String>[
      if (_country.trim().isNotEmpty) _country.trim(),
      if (_state.trim().isNotEmpty) _state.trim(),
      if (_city.trim().isNotEmpty) _city.trim(),
    ];
    return parts.isEmpty ? 'Tap Search to choose an area.' : parts.join('  •  ');
  }

  Future<void> _openSearchParams() async {
    final result =
        await showDialog<({String country, String state, String city})>(
      context: context,
      builder: (context) => _SearchParamsDialog(
        country: _country,
        state: _state,
        city: _city,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _country = result.country;
      _state = result.state;
      _city = result.city;
    });
    await _search();
  }

  // --- Map -------------------------------------------------------------------

  void _toggleMap() {
    setState(() => _showMap = !_showMap);
    // The map is (re)built with an initial camera fit, but refit once it has a
    // size in case results changed while it was hidden.
    if (_showMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMapToResults());
    }
  }

  /// The map points for the current results that carry coordinates.
  List<LatLng> get _resultPoints {
    final points = <LatLng>[];
    for (final rc in _results) {
      final lat = rc.source.latitude;
      final lon = rc.source.longitude;
      if (lat != null && lon != null) points.add(LatLng(lat, lon));
    }
    return points;
  }

  /// A camera that frames every mapped result, or null when there are none.
  CameraFit? _resultsCameraFit() {
    final points = _resultPoints;
    if (points.isEmpty) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
      maxZoom: 13,
    );
  }

  void _fitMapToResults() {
    final fit = _resultsCameraFit();
    if (fit == null) return;
    _mapController.fitCamera(fit);
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 18) {
      _mapController.move(_mapController.camera.center, currentZoom + 1);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > 2) {
      _mapController.move(_mapController.camera.center, currentZoom - 1);
    }
  }

  Widget _buildZoomButton(String label, VoidCallback onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final scheme = Theme.of(context).colorScheme;

    final markers = <Marker>[];
    for (int i = 0; i < _results.length; i++) {
      final r = _results[i].source;
      final lat = r.latitude;
      final lon = r.longitude;
      if (lat == null || lon == null) continue;
      final selected = _selectedResultIndex == i;
      markers.add(
        Marker(
          point: LatLng(lat, lon),
          width: 40,
          height: 40,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => setState(() => _selectedResultIndex = i),
            child: Icon(
              Icons.location_on,
              size: selected ? 40 : 30,
              color: selected ? scheme.primary : scheme.error,
              shadows: const [Shadow(blurRadius: 2, color: Colors.black45)],
            ),
          ),
        ),
      );
    }

    // Fall back to the operator's location, then a world view, when no result
    // has coordinates yet.
    final initialCenter = _resultPoints.isNotEmpty
        ? _resultPoints.first
        : (_hasLocation
            ? LatLng(widget.currentLat!, widget.currentLon!)
            : const LatLng(20, 0));

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _resultPoints.isEmpty ? 2 : 10,
              initialCameraFit: _resultsCameraFit(),
              onTap: (_, _) => setState(() => _selectedResultIndex = null),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.meshcentral.htcommander',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          // Zoom buttons overlay (top-left), matching the APRS map.
          Positioned(
            left: 10,
            top: 10,
            child: Column(
              children: [
                _buildZoomButton('+', _zoomIn),
                const SizedBox(height: 4),
                _buildZoomButton('−', _zoomOut),
              ],
            ),
          ),
          if (markers.isEmpty)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _searching
                      ? 'Searching…'
                      : 'Search to see stations on the map.',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
            ),
          if (_selectedResultIndex != null &&
              _selectedResultIndex! < _results.length)
            _buildMapInfoCard(_results[_selectedResultIndex!]),
        ],
      ),
    );
  }

  /// A small banner shown over the map naming the tapped station.
  Widget _buildMapInfoCard(_ResultChannel rc) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        rc.channel.name.isNotEmpty ? rc.channel.name : (rc.source.callsign);
    final freq = rc.channel.rxFreq > 0
        ? '${(rc.channel.rxFreq / 1000000).toStringAsFixed(3)} MHz'
        : null;
    final subtitle = _resultSubtitle(rc);
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surface.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'Repeater' : name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (freq != null || subtitle != null)
                      Text(
                        [?freq, ?subtitle].join('  •  '),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Details',
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () =>
                    showChannelDetailsDialog(context, channel: rc.channel),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _selectedResultIndex = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsColumn() {
    return _buildColumnFrame(
      header: 'RepeaterBook (${_results.length})',
      child: _results.isEmpty
          ? Center(
              child: Text(
                _searching ? '' : 'Search to list repeaters.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < _results.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildResultTile(i, _results[i]),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildRadioColumn() {
    return _buildColumnFrame(
      header: 'Radio channels (${_slots.length})',
      child: _slots.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Connect a radio to program channels.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final slot in _slots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildSlotTile(slot),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildColumnFrame({required String header, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Text(header,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            // Give the tiles a Material to paint their ink on.
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveButtons() {
    final canMove = _selectedResultIndex != null && _selectedSlotId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Assign selected repeater to selected slot',
            icon: const Icon(Icons.arrow_forward),
            onPressed: canMove ? _moveSelected : null,
            style: IconButton.styleFrom(
              backgroundColor: canMove
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(int index, _ResultChannel rc) {
    final channel = rc.channel;
    final selected = _selectedResultIndex == index;
    final palette = ChannelPalette.of(context);
    final label = channel.name.isNotEmpty ? channel.name : 'RPT';
    final subtitle = _resultSubtitle(rc);

    final tile = _channelTile(
      label: label,
      freqHz: channel.rxFreq,
      subtitle: subtitle,
      background: selected ? palette.selected : palette.base,
      highlight: selected,
      onTap: () => setState(() => _selectedResultIndex = index),
      onInfo: () => showChannelDetailsDialog(context, channel: channel),
      onContextMenu: (pos) => showChannelContextMenu(
        context: context,
        globalPosition: pos,
        channel: channel,
        onDetails: () => showChannelDetailsDialog(context, channel: channel),
      ),
    );

    return Draggable<RadioChannelInfo>(
      data: channel,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: _channelTile(
            label: label,
            freqHz: channel.rxFreq,
            subtitle: subtitle,
            background: palette.selected,
            highlight: true,
            width: _tileWidth,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _buildSlotTile(RadioChannelInfo slot) {
    final staged = _staged[slot.channelId];
    final isStaged = staged != null;
    final selected = _selectedSlotId == slot.channelId;
    final channel = staged ?? slot;

    return DragTarget<RadioChannelInfo>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _assign(details.data, slot.channelId),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        final palette = ChannelPalette.of(context);
        return _channelTile(
          label: _slotLabel(slot),
          freqHz: channel.rxFreq,
          slotNumber: slot.channelId + 1,
          background: isStaged
              ? palette.pending
              : (selected || hovering ? palette.selected : palette.base),
          highlight: selected || hovering || isStaged,
          onTap: () => setState(() => _selectedSlotId = slot.channelId),
          onInfo: () => showChannelDetailsDialog(
            context,
            channel:
                isStaged ? channel.copyWith(channelId: slot.channelId) : slot,
            title: isStaged ? 'Pending: ${_slotLabel(slot)}' : null,
          ),
          onClear: isStaged ? () => _clearStaged(slot.channelId) : null,
          onContextMenu: (pos) => showChannelContextMenu(
            context: context,
            globalPosition: pos,
            channel:
                isStaged ? channel.copyWith(channelId: slot.channelId) : slot,
            onDetails: () => showChannelDetailsDialog(
              context,
              channel:
                  isStaged ? channel.copyWith(channelId: slot.channelId) : slot,
              title: isStaged ? 'Pending: ${_slotLabel(slot)}' : null,
            ),
            onPaste: (pasted) => _assign(pasted, slot.channelId),
            onClear: isStaged ? () => _clearStaged(slot.channelId) : null,
          ),
        );
      },
    );
  }

  Widget _channelTile({
    required String label,
    required int freqHz,
    required Color background,
    bool highlight = false,
    int? slotNumber,
    String? subtitle,
    double? width,
    VoidCallback? onTap,
    VoidCallback? onInfo,
    VoidCallback? onClear,
    void Function(Offset globalPosition)? onContextMenu,
  }) {
    final freq =
        freqHz > 0 ? '${(freqHz / 1000000).toStringAsFixed(3)} MHz' : null;
    final palette = ChannelPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onContextMenu == null
          ? null
          : (d) => onContextMenu(d.globalPosition),
      onLongPressStart: onContextMenu == null
          ? null
          : (d) => onContextMenu(d.globalPosition),
      child: Container(
        width: width,
        height: _tileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: highlight ? palette.borderHighlight : palette.border,
            width: highlight ? 1.5 : 0.5,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.onChannel,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (slotNumber != null)
                    Text(
                      'Slot $slotNumber',
                      style: TextStyle(
                        fontSize: 8,
                        color: palette.onChannelSecondary,
                      ),
                    ),
                  if (freq != null)
                    Text(
                      freq,
                      style: TextStyle(
                        fontSize: 9,
                        color: palette.onChannelSecondary,
                      ),
                    ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 8,
                          color: palette.onChannelSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (onClear != null)
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  tooltip: 'Clear',
                  icon: Icon(Icons.cancel, color: palette.onChannel),
                  onPressed: onClear,
                ),
              )
            else if (onInfo != null)
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  tooltip: 'Details',
                  icon: Icon(Icons.info_outline, color: palette.onChannel),
                  onPressed: onInfo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Modal that collects the RepeaterBook search area (country / state / city).
/// Stacked vertically so it stays usable on a phone. Returns the values on OK,
/// or null on Cancel.
class _SearchParamsDialog extends StatefulWidget {
  final String country;
  final String state;
  final String city;

  const _SearchParamsDialog({
    required this.country,
    required this.state,
    required this.city,
  });

  @override
  State<_SearchParamsDialog> createState() => _SearchParamsDialogState();
}

class _SearchParamsDialogState extends State<_SearchParamsDialog> {
  static const _countries = ['United States', 'Canada', 'Mexico', 'Other'];

  late final TextEditingController _stateController;
  late final TextEditingController _cityController;
  late final TextEditingController _otherCountryController;

  String _country = 'United States';
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateController = TextEditingController(text: widget.state);
    _cityController = TextEditingController(text: widget.city);
    _otherCountryController = TextEditingController();
    if (_countries.contains(widget.country)) {
      _country = widget.country;
    } else if (widget.country.isNotEmpty) {
      _country = 'Other';
      _otherCountryController.text = widget.country;
    }
  }

  @override
  void dispose() {
    _stateController.dispose();
    _cityController.dispose();
    _otherCountryController.dispose();
    super.dispose();
  }

  void _onOk() {
    final isOther = _country == 'Other';
    final country =
        isOther ? _otherCountryController.text.trim() : _country;
    final state = isOther ? '' : _stateController.text.trim();
    final city = _cityController.text.trim();
    final isNa = country == 'United States' ||
        country == 'Canada' ||
        country == 'Mexico';

    if (country.isEmpty) {
      setState(() => _error = 'Enter a country.');
      return;
    }
    if (isNa &&
        RepeaterBookClient.resolveStateId(state).isEmpty &&
        city.isEmpty) {
      setState(() => _error = 'Enter a state/province, or a city.');
      return;
    }
    Navigator.of(context).pop((country: country, state: state, city: city));
  }

  @override
  Widget build(BuildContext context) {
    final isOther = _country == 'Other';
    return AlertDialog(
      title: const Text('Search RepeaterBook'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _country,
              isExpanded: true,
              decoration:
                  DialogStyles.inputDecoration(context, labelText: 'Country'),
              items: [
                for (final c in _countries)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() {
                _country = v ?? 'United States';
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (isOther)
              TextField(
                controller: _otherCountryController,
                decoration: DialogStyles.inputDecoration(
                  context,
                  labelText: 'Country name',
                  hintText: 'e.g. Switzerland',
                ),
              )
            else
              TextField(
                controller: _stateController,
                decoration: DialogStyles.inputDecoration(
                  context,
                  labelText: 'State / Province',
                  hintText: 'e.g. Virginia or VA',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityController,
              onSubmitted: (_) => _onOk(),
              decoration: DialogStyles.inputDecoration(
                context,
                labelText: 'City (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onOk,
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
