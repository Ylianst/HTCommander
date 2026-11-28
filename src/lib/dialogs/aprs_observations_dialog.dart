/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import '../aprs/aprs_observation.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

Future<void> showAprsObservationsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ObservationsDialog());

class _ObservationsDialog extends StatefulWidget {
  const _ObservationsDialog();
  @override
  State<_ObservationsDialog> createState() => _ObservationsDialogState();
}

class _ObservationsDialogState extends State<_ObservationsDialog> {
  final _broker = DataBrokerClient();
  List<AprsObservation> _records = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _read(_broker.getValueDynamic(1, 'AprsObservations', []));
    _readError(_broker.getValueDynamic(1, 'AprsObservationError'));
    _broker.subscribe(deviceId: 1, name: 'AprsObservations', callback: (_, _, data) {
      if (mounted) setState(() => _read(data));
    });
    _broker.subscribe(deviceId: 1, name: 'AprsObservationError', callback: (_, _, data) {
      if (mounted) setState(() => _readError(data));
    });
    _broker.dispatch(deviceId: 1, name: 'RequestAprsObservations', data: null, store: false);
  }

  void _read(Object? data) {
    _records = (data as List).reversed.map((json) =>
      AprsObservation.fromJson(Map<String, dynamic>.from(json as Map))).toList();
  }

  void _readError(Object? data) => _error = data is Map ? data['detail']?.toString() : null;

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HTDialog(
      title: l10n.aprsObservations, maxWidth: 760, maxHeight: 650,
      content: SizedBox(height: 470, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.aprsObservationsHelp),
        Text('${_records.length}/${AprsObservation.capacity}'),
        if (_error != null) Text(l10n.aprsObservationStorageError(_error!),
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Expanded(child: ListView.builder(itemCount: _records.length, itemBuilder: (context, index) {
          final record = _records[index];
          final kind = switch (record.kind) {
            AprsReceiveKind.directRf => l10n.aprsObservationDirect,
            AprsReceiveKind.digipeatedRf => l10n.aprsObservationDigipeated,
            AprsReceiveKind.thirdParty => l10n.aprsObservationThirdParty,
            AprsReceiveKind.internet => l10n.radioConnectionInternet,
            AprsReceiveKind.loopback => l10n.aprsObservationLoopback,
            AprsReceiveKind.invalid => l10n.aprsObservationInvalid,
          };
          final path = record.path.map((h) => '${h.callsign}${h.used ? '*' : ''}').join(',');
          return ExpansionTile(key: ValueKey(record.id),
            title: Text('${record.source ?? '?'} > ${record.addressee ?? record.destination ?? '?'}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('$kind - ${record.live ? l10n.aprsObservationLive : l10n.aprsObservationHistory}\n'
              '${record.observed.toIso8601String()}\n'
              '${record.radioMac ?? record.channelName} [${record.radioDeviceId ?? '-'}] / '
              '${record.channelName} ${record.channel}/${record.region} / ${record.decoder}'),
            childrenPadding: const EdgeInsets.all(12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!record.persisted) Text(l10n.aprsObservationPending),
              if (record.duplicate != AprsDecodeDuplicate.none)
                Text('${record.duplicate == AprsDecodeDuplicate.sameDecoder
                  ? l10n.aprsObservationSameDecoder : l10n.aprsObservationOtherDecoder}: ${record.duplicateOf}'),
              SelectableText('${record.frameSource ?? '?'} > ${record.destination ?? '?'}${path.isEmpty ? '' : ',$path'}'),
              SelectableText(record.information),
              SelectableText('RX ${record.received.toIso8601String()} / ${record.frameType} / ${record.corrections}'),
              SelectableText(record.dataHex),
            ],
          );
        })),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose))],
    );
  }
}
