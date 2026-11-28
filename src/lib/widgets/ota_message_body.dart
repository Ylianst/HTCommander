import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../aprs/ota.dart';
import '../aprs/aprs_util.dart';
import '../dialogs/aprs_location_dialog.dart';
import '../l10n/app_localizations.dart';
import '../services/callsign_lookup_service.dart';
import 'callsign_license_line.dart';

Widget _otaLink(String label, VoidCallback? onTap, {String? tooltip}) {
  final button = TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: const Color(0xFF0B57D0),
      textStyle: const TextStyle(fontSize: 14, decoration: TextDecoration.underline),
    ),
    child: Text(label),
  );
  return tooltip == null ? button : Tooltip(message: tooltip, child: button);
}

void _showOtaGridLocation(BuildContext context, String grid) {
  final center = AprsUtil.gridSquareToLatLon(grid);
  final bounds = AprsUtil.gridSquareBounds(grid);
  showAprsLocationDialog(
    context,
    latitude: center.latitude,
    longitude: center.longitude,
    title: AppLocalizations.of(context).otaGridCenterTitle(grid),
    defaultZoom: 11,
    zoomStorageKey: 'OtaGridZoom',
    areaBounds: LatLngBounds(
      LatLng(bounds.south, bounds.west),
      LatLng(bounds.north, bounds.east),
    ),
  );
}

Widget _otaGridLink(BuildContext context, String grid) => _otaLink(
  grid,
  () => _showOtaGridLocation(context, grid),
  tooltip: AppLocalizations.of(context).otaGridCenterTitle(grid),
);

class OtaCqMessageBody extends StatelessWidget {
  final OtaReply reply;
  final ValueChanged<String>? onChase;
  final ValueChanged<String>? onInfo;

  const OtaCqMessageBody({
    super.key, required this.reply, this.onChase, this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget action(IconData icon, String tooltip, VoidCallback? onPressed) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFF0B57D0),
          backgroundColor: Colors.white.withValues(alpha: 0.45),
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Colors.black),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CQ! ${reply.page}/${reply.pages}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final op in reply.ops)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        action(Icons.flag_outlined, '${l10n.otaChase}: ${op.station}',
                            onChase == null ? null : () => onChase!(op.station)),
                        const SizedBox(width: 4),
                        action(Icons.info_outline, 'INFO! ${op.station}',
                            onInfo == null ? null : () => onInfo!(op.station)),
                        const SizedBox(width: 4),
                        action(Icons.location_on_outlined,
                            op.grid == null ? l10n.otaNoPosition :
                                l10n.otaGridCenterTitle(op.grid!),
                            op.grid == null ? null :
                                () => _showOtaGridLocation(context, op.grid!)),
                      ]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _OtaCallsignSummary(
                          key: ValueKey(op.station),
                          station: op.station,
                        ),
                        const SizedBox(height: 2),
                        Tooltip(
                      message: op.minutes == null ? l10n.otaStale : l10n.otaMinutes(op.minutes!),
                      child: Text(
                            op.minutes == null ? l10n.otaStale : l10n.otaMinutes(op.minutes!),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OtaCallsignSummary extends StatefulWidget {
  final String station;

  const _OtaCallsignSummary({super.key, required this.station});

  @override
  State<_OtaCallsignSummary> createState() => _OtaCallsignSummaryState();
}

class _OtaCallsignSummaryState extends State<_OtaCallsignSummary> {
  late final Future<CallsignLookupResult?> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = CallsignLookupService.instance.lookup(widget.station);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CallsignLookupResult?>(
      future: _lookup,
      builder: (context, snapshot) {
        final record = snapshot.data?.record;
        final summary = [
          if (record != null && record.name.isNotEmpty) record.name,
          if (record != null && record.location.isNotEmpty) record.location,
          if (licenseGradeText(record) case final String grade) grade,
        ].join(' / ');
        return Row(
          children: [
            Flexible(
              flex: 3,
              child: Text(widget.station,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Tooltip(
                message: summary,
                child: Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class OtaInfoMessageBody extends StatelessWidget {
  final OtaReply reply;
  final ValueChanged<String>? onChase;

  const OtaInfoMessageBody({super.key, required this.reply, this.onChase});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final op = reply.ops.firstOrNull;
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Colors.black),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('INFO!'),
            _otaLink(reply.station!,
                onChase == null ? null : () => onChase!(reply.station!),
                tooltip: 'CHASE ${reply.station}'),
          ]),
          if (reply.kind == OtaReplyKind.missing)
            Text(l10n.otaNotHosting(reply.station!))
          else if (reply.kind == OtaReplyKind.description)
            Text('${l10n.otaDetails}: ${reply.text ?? ''}')
          else if (op != null) ...[
            if (op.grid != null) _otaGridLink(context, op.grid!)
            else Text(l10n.commonUnknown),
            Text(op.minutes == null ? l10n.otaStale : l10n.otaMinutes(op.minutes!)),
            Text(l10n.otaInfoQsos(op.qsos!)),
            Text(l10n.otaInfoWaiting(op.waiting!)),
            Text(l10n.otaInfoPoints(op.points!)),
            Text(l10n.otaStartPosition),
            if (op.latitude != null && op.longitude != null)
              _otaLink(
                '${l10n.msgdFieldLatitude}: ${op.latitude!.toStringAsFixed(4)}\n'
                '${l10n.msgdFieldLongitude}: ${op.longitude!.toStringAsFixed(4)}',
                () => showAprsLocationDialog(
                  context,
                  latitude: op.latitude!,
                  longitude: op.longitude!,
                  title: '${op.station} - ${l10n.otaStartPosition}',
                ),
              )
            else Text(l10n.otaNoPosition),
          ],
        ],
      ),
    );
  }
}

class OtaActivityMessageBody extends StatelessWidget {
  final OtaReply reply;
  final String localStation;
  final ValueChanged<String>? onCommand;
  final VoidCallback onBeaconSettings;
  final ValueChanged<Uri> onOpenLink;

  const OtaActivityMessageBody({
    super.key, required this.reply, required this.localStation,
    this.onCommand, required this.onBeaconSettings, required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (reply.kind) {
      OtaReplyKind.beaconHost || OtaReplyKind.beaconChase =>
        l10n.otaWaitingPosition(localStation),
      OtaReplyKind.chasing => l10n.otaWaitingQsl(reply.station!),
      OtaReplyKind.pendingQsl => l10n.otaPendingQsl(reply.station!),
      OtaReplyKind.confirmed => l10n.otaConfirmed(reply.station!),
      OtaReplyKind.hosting => l10n.otaHosting(reply.station!),
      OtaReplyKind.time => l10n.otaTimer(reply.minutes!, reply.cap!),
      OtaReplyKind.chasers => 'CHASERS! ${reply.page}/${reply.pages} ${reply.total}',
      _ => reply.text ?? reply.raw,
    };
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Colors.black),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(reply.kind == OtaReplyKind.confirmed ? Icons.verified_outlined :
                Icons.info_outline, size: 18, color: Colors.black),
            const SizedBox(width: 6),
            Flexible(child: Text(label)),
          ]),
          if (reply.text != null && reply.text != label) Text(reply.text!),
          if (reply.grid != null) _otaGridLink(context, reply.grid!),
          if (reply.kind == OtaReplyKind.beaconHost ||
              reply.kind == OtaReplyKind.beaconChase) ...[
            Text(l10n.otaPositionHelp),
            _otaLink(l10n.otaBeaconSettings, onBeaconSettings),
          ],
          if (reply.kind == OtaReplyKind.chasers)
            if (reply.stations.isEmpty) Text(l10n.otaNoneReported)
            else Wrap(spacing: 12, children: [
              for (final station in reply.stations)
                _otaLink(station,
                    onCommand == null ? null : () => onCommand!('QSL $station'),
                    tooltip: 'QSL $station'),
            ]),
          Wrap(spacing: 12, children: [
            if (reply.kind == OtaReplyKind.pendingQsl)
              _otaLink('QSL ${reply.station}',
                  onCommand == null ? null : () => onCommand!('QSL ${reply.station}')),
            if (reply.kind == OtaReplyKind.time && reply.minutes! < reply.cap!)
              _otaLink('STAY', onCommand == null ? null : () => onCommand!('STAY')),
            if (reply.link != null)
              _otaLink(l10n.otaViewOp, () => onOpenLink(reply.link!)),
          ]),
        ],
      ),
    );
  }
}
